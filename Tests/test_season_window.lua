-- The season window (M6-1b): UI/Windows/Season.lua over App/SeasonController.lua. The Guild Master opens and closes a
-- season from the Settings tab, each with an explicit confirmation (closing with two); everybody else sees it read-only.
local function Lg() return FDCP.Ledger end
local function Sn() return FDCP.Season end
local function NC() return FDCP.NightController end
local function SC() return FDCP.SeasonController end
local function SW() return FDCP.SeasonWindow end

local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }
local MC, ONY = 409, 249

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

local function open()
	Mock.Slash("/fdcp")
	FDCP.MainWindow:SelectTab("settings")
	SW():Refresh()
	return SW().root
end

local function click(b) b:GetScript("OnClick")(b) end

local function count(L, t)
	local n = 0
	for _, e in pairs(L.events) do if e.type == t then n = n + 1 end end
	return n
end

describe("the season window for the Guild Master", function()
	before_boot(guild(0))

	it("opens a season from the chosen pack, sizes, rule and start credits, after a confirmation", function()
		local L = bound()
		local root = open()
		eq(root.name:GetText(), "No season is open")
		truthy(root.form:IsShown()); falsy(root.close:IsShown())
		root.form.label:SetText("Cataclysm")
		root.form.startEdit:SetText("5")
		root.form.rows[1].chip:GetScript("OnClick")(root.form.rows[1].chip)
		root.form.rows[2].chip:GetScript("OnClick")(root.form.rows[2].chip)
		root.form.rows[2].seg:Select(20)
		root.form.method:Select("zero")
		click(root.form.open)
		truthy(SW().dialog:IsShown(), "the summary asks first")
		eq(count(L, "SEASON_OPENED"), 0, "nothing written yet")
		click(SW().dialog.cancel)
		falsy(SW().dialog:IsShown())
		eq(count(L, "SEASON_OPENED"), 0, "cancelled: nothing written")
		click(root.form.open)
		click(SW().dialog.confirm)
		eq(count(L, "SEASON_OPENED"), 1, "one audited event")
		eq(count(L, "CONFIG_CHANGED"), 1, "the late-join rule is changed in the rules, audited")
		local s = Sn().Current(L)
		eq(s.label, "Cataclysm"); eq(s.startCredits, 5)
		deepEq(s.instances, { { id = MC, size = 40 }, { id = ONY, size = 20 } })
		eq(FDCP.Rules.Current(L).members.lateJoin.method, "zero")
		eq(root.name:GetText(), "Cataclysm")
		eq(root.message:GetText(), "Season opened.")
		eq(root.pack:GetText(), "Raids: Molten Core (40) · Onyxia’s Lair (20)")
		falsy(root.form:IsShown()); truthy(root.close:IsShown())
	end)

	it("refuses an empty pack and a bad start credit, and a second open season", function()
		local L = bound()
		local root = open()
		click(root.form.open)
		eq(root.message:GetText(), "Pick at least one raid.")
		root.form.rows[1].chip:GetScript("OnClick")(root.form.rows[1].chip)
		root.form.startEdit:SetText("abc")
		click(root.form.open)
		eq(root.message:GetText(), "The start credits must be a whole number, zero or more.")
		falsy(SW().dialog and SW().dialog:IsShown())
		local ev, why = SC():Open({ instances = { { id = MC, size = 40 } } })
		isNil(ev); eq(why, "CONFIRM_REQUIRED")
		assert(SC():Open({ confirmed = true, instances = { { id = MC, size = 40 } } }))
		local s2, why2 = SC():Open({ confirmed = true, instances = { { id = MC, size = 40 } } })
		isNil(s2); eq(why2, "SEASON_ALREADY_OPEN")
		eq(SW().ErrorText(why2), "Another season is already open: close it first.")
		eq(count(L, "SEASON_OPENED"), 1)
	end)

	it("closing asks two separate confirmations and does nothing without them", function()
		local L = bound()
		assert(SC():Open({ confirmed = true, label = "S", instances = { { id = MC, size = 40 } } }))
		local root = open()
		truthy(root.close:IsShown())
		click(root.close)
		truthy(SW().dialog:IsShown())
		click(SW().dialog.confirm)                       -- first step only
		eq(SW().dialog.title:GetText(), "Are you really sure?")
		eq(count(L, "SEASON_CLOSED"), 0)
		click(SW().dialog.cancel)
		eq(count(L, "SEASON_CLOSED"), 0, "cancelled at the second step")
		local ev, why = SC():Close({ confirmed = true })
		isNil(ev); eq(why, "CONFIRM_REQUIRED")
		click(root.close)
		click(SW().dialog.confirm); click(SW().dialog.confirm)
		eq(count(L, "SEASON_CLOSED"), 1, "one audited event")
		isNil(Sn().Current(L))
		eq(root.message:GetText(), "Season closed.")
		truthy(root.form:IsShown()); falsy(root.close:IsShown())
		eq(count(L, "SEASON_OPENED"), 1, "nothing is deleted")
	end)

	it("a season with an open night cannot be closed", function()
		local L = bound()
		assert(SC():Open({ confirmed = true, instances = { { id = MC, size = 40 } } }))
		assert(FDCP.Nights.Open(L, { author = NC():Me(), ts = 10, season = Sn().Current(L).id, date = "2026-01-01",
			instanceID = MC, difficulty = "normal", faction = "Horde" }, FDCP.PermissionService:Gate()))
		local s, why = SC():Close({ confirmed = true, confirmedAgain = true })
		isNil(s); eq(why, "NIGHT_OPEN")
	end)
end)

describe("the item-level band in the season window (M7-5c)", function()
	before_boot(guild(0))

	it("can be given when the season opens, and shows on the card", function()
		local L = bound()
		local root = open()
		root.form.rows[1].chip:GetScript("OnClick")(root.form.rows[1].chip)
		root.form.bandMin:SetText("200")
		root.form.bandMax:SetText("226")
		click(root.form.open)
		click(SW().dialog.confirm)
		eq(count(L, "SEASON_OPENED"), 1)
		eq(count(L, "SEASON_BAND_SET"), 1)
		deepEq(Sn().Current(L).band, { min = 200, max = 226 })
		eq(root.band:GetText(), "Item-level band: 200–226")
		truthy(root.bandForm:IsShown())
		eq(root.bandForm.bandMin:GetText(), "200")
	end)

	it("an open season's band is changed with a confirmation; a bad band is refused", function()
		local L = bound()
		assert(SC():Open({ confirmed = true, instances = { { id = MC, size = 40 } } }))
		local root = open()
		eq(root.band:GetText(), FDCP.L["SEASON_BAND_NONE"])
		local bf = root.bandForm
		bf.bandMin:SetText("230"); bf.bandMax:SetText("200")
		click(bf.save)
		eq(root.message:GetText(), FDCP.L["SEASON_ERR_BAND"])
		falsy(SW().dialog and SW().dialog:IsShown())
		bf.bandMin:SetText("213"); bf.bandMax:SetText("239")
		click(bf.save)
		truthy(SW().dialog:IsShown(), "it asks first")
		eq(count(L, "SEASON_BAND_SET"), 0)
		click(SW().dialog.confirm)
		eq(count(L, "SEASON_BAND_SET"), 1)
		deepEq(Sn().Current(L).band, { min = 213, max = 239 })
		eq(root.message:GetText(), FDCP.L["SEASON_BAND_DONE"])
		eq(root.band:GetText(), "Item-level band: 213–239")
		local s, why = SC():SetBand({ confirmed = true, min = 213, max = 239 })
		isNil(s); eq(why, "UNCHANGED")
		s, why = SC():SetBand({ min = 1, max = 2 })
		isNil(s); eq(why, "CONFIRM_REQUIRED")
	end)

	it("a bad band in the opening form stops the opening", function()
		local L = bound()
		local root = open()
		root.form.rows[1].chip:GetScript("OnClick")(root.form.rows[1].chip)
		root.form.bandMin:SetText("abc")
		click(root.form.open)
		eq(root.message:GetText(), FDCP.L["SEASON_ERR_BAND"])
		eq(count(L, "SEASON_OPENED"), 0)
	end)

	it("speaks Italian", function()
		FDCP.Locale.SetActive("itIT")
		local L = bound()
		assert(SC():Open({ confirmed = true, instances = { { id = MC, size = 40 } }, band = { min = 200, max = 226 } }))
		local root = open()
		eq(root.band:GetText(), "Fascia di item level: 200–226")
	end)
end)

describe("the season window for a member", function()
	before_boot(guild(3))

	it("shows the season read-only, with no buttons, and refuses a forced call", function()
		local L = bound()
		assert(Sn().Open(L, { author = "Aurel-TestRealm", ts = 1, season = "S1", label = "Season 1",
			instances = { { id = MC, size = 40 } } }))
		local root = open()
		eq(root.name:GetText(), "Season 1")
		eq(root.pack:GetText(), "Raids: Molten Core (40)")
		eq(root.rule:GetText(), "Late joiners start with: Fewest credits of the pool")
		eq(root.start:GetText(), "Start credits: 0")
		falsy(root.form:IsShown()); falsy(root.close:IsShown())
		falsy(root.bandForm:IsShown(), "no band editor for a member")
		local s, why = SC():Close({ confirmed = true, confirmedAgain = true })
		isNil(s); eq(why, "RANK_TOO_LOW")
		s, why = SC():SetBand({ confirmed = true, min = 200, max = 226 })
		isNil(s); eq(why, "RANK_TOO_LOW")
		SW():OnClose()
		falsy(SW().dialog and SW().dialog:IsShown())
		eq(root.message:GetText(), "Your guild rank cannot do this.")
		eq(count(L, "SEASON_CLOSED"), 0)
	end)

	it("cannot open a season either", function()
		local L = bound()
		local root = open()
		falsy(root.form:IsShown())
		local s, why = SC():Open({ confirmed = true, instances = { { id = MC, size = 40 } } })
		isNil(s); eq(why, "RANK_TOO_LOW")
		eq(count(L, "SEASON_OPENED"), 0)
	end)
end)

describe("the season window without a guild", function()
	before_boot(function() end)

	it("says the data is not loaded", function()
		local root = open()
		eq(root.name:GetText(), "The guild data is not loaded yet")
		falsy(root.form:IsShown()); falsy(root.close:IsShown())
	end)
end)
