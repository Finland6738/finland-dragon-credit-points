-- Profiles and presets (M7-3, docs/ANALISI.md §10): the AceDB profiles of the personal settings, the profile string
-- (export, check, preview, import), the four presets of the rules applied from the Settings tab by the Guild Master and their
-- round trip through the configuration string, and the Profiles pane.
local function Lg() return FDCP.Ledger end
local function NC() return FDCP.NightController end
local function SC() return FDCP.SettingsController end
local function SW() return FDCP.SettingsWindow end
local function PW() return FDCP.ProfilesWindow end
local function Cfg() return FDCP.Config end

local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }

local function guild(myRank)
	return function(Mock)
		Mock.guild.Set({ name = "Keepers", ranks = RANKS, myRank = myRank, members = {
			{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
		} })
	end
end

local function bound()
	local L = Lg().New()
	NC():Bind(L)
	Mock.Advance(3)
	return L
end

local function click(b) b:GetScript("OnClick")(b) end

local function open(sub)
	Mock.Slash("/fdcp")
	FDCP.MainWindow:SelectTab("settings")
	SW().root.sub:Select(sub or "profiles")
	SW():Refresh()
	return SW().root
end

describe("the profile table (Domain/Profiles)", function()
	before_boot(guild(0))

	it("exports only the personal settings, never the machine's", function()
		local p = FDCP.Profiles.Export({ theme = "aurora", debug = true, minimap = { hide = true }, sounds = false, rollSeconds = 45 })
		eq(p.kind, "PRF")
		deepEq(p.settings, { theme = "aurora", sounds = false, rollSeconds = 45 })
	end)

	it("checks the values with the configuration's validators and refuses an empty or foreign string", function()
		local check = function(data) return FDCP.Profiles.Check(data, Cfg().Validate) end
		local ok = check({ kind = "PRF", v = 1, settings = { theme = "aurora", unknown = 1 } })
		deepEq(ok, { theme = "aurora" })
		local n, why = check({ kind = "PRF", v = 1, settings = { theme = "nope" } })
		isNil(n); eq(why, "BAD:theme:BAD_VALUE")
		n, why = check({ kind = "PRF", v = 1, settings = { rollSeconds = 1 } }); eq(why, "BAD:rollSeconds:OUT_OF_RANGE")
		n, why = check({ kind = "PRF", v = 1, settings = {} }); eq(why, "EMPTY")
		n, why = check({ kind = "PRF", v = 9, settings = { theme = "aurora" } }); eq(why, "NEWER")
		n, why = check({ kind = "CFG", v = 1 }); eq(why, "kind")
	end)

	it("diffs in the order of the window and skips equal values", function()
		local d = FDCP.Profiles.Diff({ theme = "nebula", sounds = true, effects = true }, { sounds = false, theme = "aurora", effects = true })
		eq(#d, 2); eq(d[1].key, "theme"); eq(d[1].to, "aurora"); eq(d[2].key, "sounds"); eq(d[2].from, true)
	end)

	it("accepts a name of 1 to 32 plain characters", function()
		truthy(FDCP.Profiles.ValidName("Raid night"))
		falsy(FDCP.Profiles.ValidName("")); falsy(FDCP.Profiles.ValidName("   "))
		falsy(FDCP.Profiles.ValidName(("x"):rep(33))); falsy(FDCP.Profiles.ValidName("a\nb")); falsy(FDCP.Profiles.ValidName(7))
	end)
end)

describe("the AceDB profiles", function()
	before_boot(guild(0))

	it("creates, switches, copies, deletes and resets", function()
		local start = Cfg():CurrentProfile()
		truthy(Cfg():NewProfile("Raid"))
		eq(Cfg():CurrentProfile(), "Raid")
		truthy(Cfg():Set("theme", "aurora"))
		truthy(Cfg():SelectProfile(start))
		eq(Cfg():Get("theme"), "nebula", "the other profile is untouched")
		truthy(Cfg():CopyProfile("Raid"))
		eq(Cfg():Get("theme"), "aurora")
		truthy(Cfg():ResetProfile())
		eq(Cfg():Get("theme"), "nebula")
		deepEq(Cfg():ProfileNames()[1], start, "the current one is first")
		truthy(Cfg():DeleteProfile("Raid"))
		falsy(Cfg():HasProfile("Raid"))
	end)

	it("refuses a bad name, a duplicate, the current one and a missing one", function()
		local start = Cfg():CurrentProfile()
		local ok, why = Cfg():NewProfile(""); falsy(ok); eq(why, "BAD_NAME")
		truthy(Cfg():NewProfile("A"))
		ok, why = Cfg():NewProfile("A"); eq(why, "EXISTS")
		ok, why = Cfg():DeleteProfile("A"); eq(why, "CURRENT")
		ok, why = Cfg():SelectProfile("Nope"); eq(why, "NO_PROFILE")
		ok, why = Cfg():CopyProfile("A"); eq(why, "SAME")
		ok, why = Cfg():CopyProfile(start); truthy(ok)
	end)

	it("redraws the look when the profile changes", function()
		local start = Cfg():CurrentProfile()
		truthy(Cfg():NewProfile("Look"))
		truthy(SC():SetPersonal("theme", "drago"))
		eq(FDCP.Theme.Current(), "drago")
		truthy(SC():SelectProfile(start))
		eq(FDCP.Theme.Current(), "nebula")
	end)

	it("writes nothing when the saved data is from a newer version", function()
		Cfg().readOnly = true
		local ok, why = Cfg():NewProfile("X"); falsy(ok); eq(why, "READ_ONLY")
		ok, why = Cfg():ResetProfile(); eq(why, "READ_ONLY")
	end)
end)

describe("the profile string", function()
	before_boot(guild(0))

	it("round-trips: what one player writes another reads", function()
		truthy(SC():SetPersonal("theme", "aurora")); truthy(SC():SetPersonal("sounds", false)); truthy(SC():SetPersonal("rollSeconds", 45))
		local text = SC():ExportProfile()
		truthy(text:find("^!FDCP:PRF:1:"))
		truthy(Cfg():NewProfile("Friend"))
		eq(Cfg():Get("theme"), "nebula")
		local p = SC():PreviewProfile(text)
		eq(#p.changes, 3)
		eq(SC():ImportProfile(text), 3)
		eq(Cfg():Get("theme"), "aurora"); eq(FDCP.Theme.Current(), "aurora")
		eq(Cfg():Get("sounds"), false); eq(Cfg():Get("rollSeconds"), 45)
		local n, why = SC():ImportProfile(text); isNil(n); eq(why, "UNCHANGED")
		eq(SC():ExportProfile(), text, "the same profile gives the same string")
	end)

	it("ignores line breaks a chat window added and refuses what is not a profile", function()
		local text = SC():ExportProfile()
		local wrapped = text:sub(1, 20) .. "\n " .. text:sub(21)
		truthy(SC():PreviewProfile(wrapped))
		local n, why = SC():PreviewProfile("hello"); isNil(n); eq(why, "FORMAT")
		n, why = SC():PreviewProfile(""); eq(why, "EMPTY")
		n, why = SC():PreviewProfile("!FDCP:CFG:1:AAAA"); eq(why, "KIND")
		n, why = SC():PreviewProfile("!FDCP:PRF:9:AAAA"); eq(why, "NEWER")
	end)

	it("a string whose values are wrong writes nothing", function()
		local bad = FDCP.BackupService.Encode({ kind = "PRF", v = 1, settings = { theme = "nope", sounds = false } })
		local n, why = SC():ImportProfile(bad)
		isNil(n); eq(why, "BAD:theme:BAD_VALUE")
		eq(Cfg():Get("sounds"), true)
	end)
end)

describe("the presets of the rules", function()
	before_boot(guild(0))

	it("lists the four presets and marks the one in force", function()
		bound()
		local list = SC():Presets()
		eq(#list, 4); eq(list[1].code, "PATTO"); truthy(list[1].active)
		for i = 2, 4 do falsy(list[i].active) end
	end)

	it("applies each preset as the form would and the string carries it unchanged", function()
		local L = bound()
		for _, code in ipairs(FDCP.Presets.ORDER) do
			-- from another preset so there is something to change
			local other = code == "ROLL_ONLY" and "LOOT_COUNCIL" or "ROLL_ONLY"
			if FDCP.Presets.Match(SC():Rules()) ~= other then assert(SC():ApplyPreset(other)) end
			local diff = SC():PresetDiff(code)
			truthy(#diff > 0, code)
			assert(SC():ApplyPreset(code))
			eq(FDCP.Presets.Match(SC():Rules()), code, code .. " is in force")
			deepEq(SC():PresetDiff(code), {}, "nothing left to change")
			local text = assert(FDCP.BackupService:ExportConfig())
			if FDCP.Presets.Match(SC():Rules()) ~= other then assert(SC():ApplyPreset(other)) end
			local e = assert(FDCP.BackupService:ImportConfig(text, { confirmed = true }))
			eq(FDCP.Presets.Match(SC():Rules()), code, code .. " round-trips through the string")
			eq(Lg().Payload(e).preset, code, "the audit keeps the preset's code")
		end
		-- the ledger accepted every write
		truthy(FDCP.Rules.Current(L))
	end)

	it("refuses to apply the preset in force and an unknown one", function()
		bound()
		local e, why = SC():ApplyPreset("PATTO"); isNil(e); eq(why, "UNCHANGED")
		e, why = SC():ApplyPreset("NOPE"); isNil(e); eq(why, "UNKNOWN_PRESET")
	end)

	it("keeps the guild's own values (council members, faction name)", function()
		bound()
		local rules = SC():Rules()
		rules.council.members = { "Aurel", "Bryn" }
		assert(SC():ApplyRules(rules))
		assert(SC():ApplyPreset("LOOT_COUNCIL"))
		deepEq(SC():Rules().council.members, { "Aurel", "Bryn" })
	end)
end)

describe("the presets for an officer", function()
	before_boot(guild(1))

	it("an officer cannot apply a preset", function()
		bound()
		local e, why = SC():ApplyPreset("ROLL_ONLY"); isNil(e); eq(why, "NOT_GM")
		eq(FDCP.Presets.Match(SC():Rules()), "PATTO")
	end)
end)

describe("the Profiles pane", function()
	before_boot(guild(0))

	it("sits after Personal and lists the profiles with the current one marked", function()
		bound()
		local root = open("profiles")
		eq(root.sub:Active(), "profiles")
		eq(SW().SUBTABS[2], "profiles")
		eq(PW().list:Count(), #Cfg():ProfileNames())
		eq(PW().list:Selected(), Cfg():CurrentProfile())
		eq(PW().presets:Count(), 4)
	end)

	it("creates and switches profiles from the buttons, deleting only after a confirmation", function()
		bound()
		open("profiles")
		local start = Cfg():CurrentProfile()
		PW().name:SetText("Raid")
		click(PW().new)
		eq(Cfg():CurrentProfile(), "Raid")
		PW().list:Select(start)
		click(PW().use)
		eq(Cfg():CurrentProfile(), start)
		PW().list:Select("Raid")
		click(PW().delete)
		truthy(SW().dialog:IsShown())
		truthy(Cfg():HasProfile("Raid"))
		click(SW().dialog.confirm)
		falsy(Cfg():HasProfile("Raid"))
		PW().name:SetText("")
		click(PW().new)
		eq(PW().message:GetText(), FDCP.L["PROFILES_ERR_BAD_NAME"])
	end)

	it("shows what a preset changes and applies it after a confirmation", function()
		bound()
		open("profiles")
		PW().presets:Select("ROLL_ONLY")
		contains(PW().presetNote:GetText(), "would change")
		click(PW().apply)
		truthy(SW().dialog:IsShown())
		eq(FDCP.Presets.Match(SC():Rules()), "PATTO", "nothing is written before the confirmation")
		click(SW().dialog.confirm)
		eq(FDCP.Presets.Match(SC():Rules()), "ROLL_ONLY")
		PW():Refresh()
		contains(PW().presets.choices[2].text, "in force")
	end)

	it("exports the profile and imports a pasted one after a preview", function()
		bound()
		open("profiles")
		SC():SetPersonal("theme", "aurora")
		click(PW().export)
		local text = PW().edit:GetText()
		truthy(text:find("^!FDCP:PRF:"))
		SC():SetPersonal("theme", "nebula")
		PW().edit:SetText(text)
		click(PW().import)
		truthy(SW().dialog:IsShown())
		eq(Cfg():Get("theme"), "nebula")
		click(SW().dialog.confirm)
		eq(Cfg():Get("theme"), "aurora")
		PW().edit:SetText("garbage")
		click(PW().import)
		eq(PW().message:GetText(), FDCP.L["PROFILES_ERR_FORMAT"])
	end)
end)

describe("the Profiles pane for an officer", function()
	before_boot(guild(1))

	it("shows the presets but the apply button stays off", function()
		bound()
		open("profiles")
		PW().presets:Select("ROLL_ONLY")
		falsy(PW().apply:IsEnabled())
		click(PW().apply)
		falsy(SW().dialog and SW().dialog:IsShown())
	end)
end)
