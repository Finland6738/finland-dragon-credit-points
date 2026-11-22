-- Site export (M6-4): the three files of the community site built from the ledger (Domain/SiteExport.lua, pure), the saved
-- copy in the SavedVariables (App/SiteExportService.lua) and the Site form of the History › Export pane. The files match the
-- golden files of Tests/golden/site_*.json, and the rules of the site's scripts/validate.mjs are checked here on the same
-- data (tools/test_site_export.py checks the golden files again with Python's json and merges them into the site's files).
local function Lg() return FDCP.Ledger end
local function Sn() return FDCP.Season end
local function R() return FDCP.Roster end
local function Nt() return FDCP.Nights end
local function SE() return FDCP.SiteExport end
local function SES() return FDCP.SiteExportService end
local function NC() return FDCP.NightController end
local function RC() return FDCP.RosterController end
local function HW() return FDCP.HistoryWindow end
local function XW() return FDCP.ExportWindow end

local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }
local REALM = "TestRealm"
local function full(n) return n .. "-" .. REALM end

local function guild(rank)
	return function(M)
		M.guild.Set({ name = "Keepers", ranks = RANKS, myRank = rank or 1, members = {
			{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
		} })
	end
end

local function golden(name, text)
	local ok, expected = pcall(Golden, name)
	if not ok then fail("GOLDEN-BEGIN:" .. name .. "\n" .. text .. "GOLDEN-END") end
	eq(text, expected, name)
end

-- Unwraps the objects of SiteExport (O) into plain Lua tables, so a test can check them like parsed JSON.
local function plain(v)
	if type(v) ~= "table" or v == SE().NULL then return v end
	if v.__o then
		local t = {}
		for _, kv in ipairs(v.list) do t[kv[1]] = plain(kv[2]) end
		return t
	end
	local t = {}
	for i, x in ipairs(v) do t[i] = plain(x) end
	return t
end

-- The rules of the site's scripts/validate.mjs: returns a list of problems.
local CLASSES = { warrior = true, paladin = true, hunter = true, rogue = true, priest = true, shaman = true, mage = true,
	warlock = true, druid = true }
local function validate(roster, loot)
	local problems = {}
	for _, p in ipairs(roster.players) do
		if not CLASSES[p.class] then problems[#problems + 1] = "class " .. tostring(p.class) end
		if not (p.role == "tank" or p.role == "healer" or p.role == "dps") then problems[#problems + 1] = "role " .. tostring(p.role) end
	end
	for _, s in ipairs(loot.seasons) do
		local names = {}
		for _, p in ipairs(s.roster) do
			names[p.name] = true
			if not CLASSES[p.class] then problems[#problems + 1] = "season class " .. tostring(p.class) end
		end
		for _, r in ipairs(s.raids) do
			for _, a in ipairs(r.awards) do
				if not names[a.player] then problems[#problems + 1] = "player " .. tostring(a.player) end
				if not (a.cost == 0 or a.cost == 1 or a.cost == 2) then problems[#problems + 1] = "cost " .. tostring(a.cost) end
			end
		end
	end
	return problems
end

local POOL = {
	-- name, spec, faction, status
	{ "Aurel", 73, "Horde", "ACTIVE" },     -- Protection Warrior (tank)
	{ "Bryn", 65, "Horde", "ACTIVE" },      -- Holy Paladin (healer)
	{ "Corin", 105, "Horde", "TRIAL" },     -- Restoration Druid (healer), in trial
	{ "Dara", 63, "Horde", "ACTIVE" },      -- Fire Mage (dps)
	{ "Édda", 258, "Horde", "ACTIVE" },     -- Shadow Priest (dps), leaves the roster later
	{ "Fenn", 70, "Alliance", "ACTIVE" },   -- the other faction
}

local function award(L, author, ts, member, cost, extra)
	local payload = { target = "member", member = full(member), item = 1000 + ts, cost = cost, response = "MS", reasons = {}, flags = {} }
	for k, v in pairs(extra or {}) do payload[k] = v end
	return assert(Lg().Append(L, { author = author, ts = ts, season = "S2", type = "ITEM_AWARDED", payload = payload }))
end

-- Season "S1" (older, closed, one night) and season "S2" labelled "2": two instances, three closed nights, one open night,
-- a late joiner with an average and one with a fixed credit, bank and other-faction awards, a voided award, a cost of 3, an
-- adjustment, an inactive member and a first kill entered by hand.
local function ledger(opts)
	opts = opts or {}
	local L = Lg().New()
	local A, B = full("Aurel"), full("Bryn")
	assert(Sn().Open(L, { author = A, ts = 1, season = "S1", label = "1", instances = { { id = 409, size = 40 } } }))
	assert(R().Join(L, { author = B, ts = 2, season = "S1", member = full("Aurel"), faction = "Horde", ms1 = 73 }))
	assert(Nt().Open(L, { author = A, ts = 3, season = "S1", date = "2026-09-02", instanceID = 409, difficulty = "normal" }))
	assert(Lg().Append(L, { author = A, ts = 4, season = "S1", type = "ITEM_AWARDED", payload = { target = "member", member = A, item = 77, cost = 1, response = "MS", reasons = {}, flags = {} } }))
	assert(Nt().Close(L, { author = A, ts = 5, season = "S1" }))
	assert(Sn().Close(L, { author = A, ts = 6, season = "S1" }))

	assert(Sn().Open(L, { author = A, ts = 10, season = "S2", label = "2", instances = { { id = 409, size = 40 }, { id = 249, size = 40 } } }))
	for i, p in ipairs(POOL) do
		assert(R().Join(L, { author = B, ts = 10 + i, season = "S2", member = full(p[1]), faction = p[3], ms1 = p[2], status = p[4] }))
	end
	assert(Nt().Open(L, { author = A, ts = 20, season = "S2", date = "2026-10-14", instanceID = 409, difficulty = "normal" }))
	assert(Nt().Kill(L, { author = A, ts = 21, season = "S2", encounterID = 663, date = "2026-10-14", instanceID = 409 }))
	assert(Nt().Kill(L, { author = A, ts = 22, season = "S2", encounterID = 664, date = "2026-10-14", instanceID = 409 }))
	assert(Nt().SetLineup(L, { author = A, ts = 21, season = "S2", raid = { full("Aurel"), full("Bryn") }, bench = { full("Dara") } }))
	award(L, A, 23, "Bryn", 1)
	award(L, A, 24, "Corin", 2)
	award(L, A, 25, "Aurel", 2)
	award(L, A, 26, "Dara", 2)
	award(L, A, 27, "Aurel", 0, { response = "OS" })
	local voided = award(L, A, 28, "Édda", 2)
	assert(Lg().Append(L, { author = A, ts = 29, season = "S2", type = "AWARD_VOIDED", payload = { ref = voided.id, reason = "MISTAKE" } }))
	award(L, A, 30, "Aurel", 1, { target = "bank" })
	assert(Nt().Close(L, { author = A, ts = 31, season = "S2" }))
	-- a late joiner: the average of the roster (floor) is her starting credit
	assert(R().Join(L, { author = B, ts = 35, season = "S2", member = full("Hadri"), faction = "Horde", ms1 = 105 }))
	assert(R().SetStatus(L, { author = B, ts = 36, season = "S2", member = full("Édda"), status = "INACTIVE" }))
	-- a late joiner with a fixed credit of 3 (a 2 and a 1)
	local cfg = FDCP.Members.DefaultConfig()
	cfg.lateJoin.method, cfg.lateJoin.fixed = "fixed", 3
	assert(R().Join(L, { author = B, ts = 37, season = "S2", member = full("Ivo"), faction = "Horde", ms1 = 64 }, cfg))
	assert(Nt().Open(L, { author = A, ts = 40, season = "S2", date = "2026-10-21", instanceID = 409, difficulty = "normal" }))
	assert(Nt().Kill(L, { author = A, ts = 41, season = "S2", encounterID = 663, date = "2026-10-21", instanceID = 409 }))
	award(L, A, 42, "Hadri", 1)
	award(L, A, 43, "Fenn", 2)
	award(L, A, 44, "Aurel", 3)
	award(L, B, 45, "Ivo", 1.5)
	assert(Lg().Append(L, { author = A, ts = 45, season = "S2", type = "CREDITS_ADJUSTED", payload = { member = full("Dara"), delta = 1.5, reason = "CORRECTION" } }))
	assert(Nt().Close(L, { author = A, ts = 46, season = "S2" }))
	assert(Nt().Open(L, { author = A, ts = 50, season = "S2", date = "2026-10-21", instanceID = 249, difficulty = "normal" }))
	assert(Nt().Kill(L, { author = A, ts = 51, season = "S2", encounterID = 1084, date = "2026-10-21", instanceID = 249 }))
	assert(Nt().Close(L, { author = A, ts = 52, season = "S2" }))
	if not opts.noOpenNight then
		assert(Nt().Open(L, { author = A, ts = 60, season = "S2", date = "2026-10-28", instanceID = 409, difficulty = "normal" }))
		award(L, A, 61, "Bryn", 1)
	end
	-- a first kill entered by hand, older than the addon, and the other guild's date (it must never reach the file)
	assert(FDCP.Progress.Set(L, { author = A, ts = 70, encounterID = 663, faction = "Nebulah", date = "2026-09-30" }))
	assert(FDCP.Progress.Set(L, { author = A, ts = 71, encounterID = 664, faction = "Nebulaa", date = "2026-10-02" }))
	return L
end

local function opts(extra)
	local o = { faction = "Horde", siteFaction = "Nebulah", today = "2026-10-29",
		itemName = function(id) return "Item " .. id .. " of the Test" end,
		labels = { startCredits = "Crediti iniziali (media del roster)", adjustment = "Correzione crediti" } }
	for k, v in pairs(extra or {}) do o[k] = v end
	return o
end

local function build(extra) return SE().Build(ledger(), opts(extra)) end

local function warningOf(list, code, season)
	for _, w in ipairs(list) do
		if w.code == code and (season == nil or w.season == season) then return w.n end
	end
end

describe("the site files", function()
	it("match the golden files", function()
		local b = build()
		golden("site_roster.json", b.files.roster)
		golden("site_loot.json", b.files.loot)
		golden("site_progress.json", b.files.progress)
		golden("site_fragment_roster.json", b.fragments.roster)
		golden("site_fragment_loot.json", b.fragments.loot)
		golden("site_fragment_progress.json", b.fragments.progress)
	end)

	it("are deterministic: the same ledger gives the same bytes", function()
		deepEq(build(), build())
	end)

	it("pass the rules of the site's validate script (classes, roles, players in the roster, cost 0-2)", function()
		local L = ledger()
		local roster = plain(SE().Roster(L, nil, opts()))
		local loot = plain(SE().Loot(L, opts()))
		deepEq(validate(roster, loot), {})
	end)

	it("give the site totals equal to the addon's credits for every member the site shows", function()
		local L = ledger()
		local loot = plain(SE().Loot(L, opts()))
		local s2 = loot.seasons[1]
		local credits = Lg().Credits(L, "S2")
		local site = {}
		for _, r in ipairs(s2.raids) do
			for _, a in ipairs(r.awards) do site[a.player] = (site[a.player] or 0) + a.cost end
		end
		for _, p in ipairs(s2.roster) do
			local addon = credits[full(p.name)] or 0
			-- the adjustment of Dara (1.5) is the one thing the current format cannot show
			if p.name == "Dara" then addon = addon - 1.5 end
			-- the award of the open night (Bryn, 1) goes out with its night
			if p.name == "Bryn" then addon = addon - 1 end
			-- a cost of 1.5 is rounded to 2 (and said so)
			if p.name == "Ivo" then addon = addon + 0.5 end
			eq(site[p.name] or 0, addon, p.name)
		end
	end)
end)

describe("roster.json", function()
	it("lists the playing mains of the guild's faction with the site's words", function()
		local o = plain(SE().Roster(ledger(), nil, opts()))
		eq(o.updated, "2026-10-29")
		local by = {}
		for _, p in ipairs(o.players) do by[p.name] = p end
		eq(by.Aurel.class, "warrior"); eq(by.Aurel.spec, "Protection"); eq(by.Aurel.role, "tank")
		eq(by.Aurel.faction, "Nebulah"); eq(by.Aurel.rank, "Raider")
		eq(by.Bryn.class, "paladin"); eq(by.Bryn.role, "healer")
		eq(by.Corin.rank, "Trial"); eq(by.Dara.role, "dps")
		isNil(by["Édda"], "an inactive member is not in the roster")
		isNil(by.Fenn, "the other faction's main is not exported")
		eq(#o.players, 6, "Aurel, Bryn, Corin, Dara, Hadri and Ivo: the inactive member and the other faction are out")
	end)

	it("uses the site key of the guild and the season given", function()
		local o = plain(SE().Roster(ledger(), "S1", opts({ siteFaction = "Nebulaa" })))
		eq(#o.players, 1); eq(o.players[1].faction, "Nebulaa")
	end)
end)

describe("loot.json", function()
	local function s2() return plain(SE().Season(ledger(), "S2", opts())) end

	it("has the seasons newest first and one raid per closed night, by date", function()
		local loot = plain(SE().Loot(ledger(), opts()))
		eq(#loot.seasons, 2)
		eq(loot.seasons[1].season, "2"); eq(loot.seasons[2].season, "1")
		eq(loot.seasons[2].closed, true); eq(loot.seasons[1].closed, false)
		local s = loot.seasons[1]
		eq(#s.raids, 3, "the night still open is not a column")
		eq(s.raids[1].id, "s2-r1"); eq(s.raids[1].instance, "Molten Core"); eq(s.raids[1].date, "14/10"); eq(s.raids[1].bosses, "2/10")
		eq(s.raids[2].id, "s2-r2"); eq(s.raids[2].date, "21/10"); eq(s.raids[2].bosses, "1/10")
		eq(s.raids[3].id, "s2-r3"); eq(s.raids[3].instance, "Onyxia\226\128\153s Lair"); eq(s.raids[3].bosses, "1/1")
		eq(s.updated, "2026-10-21", "the date of the last exported night")
	end)

	it("has every main of the season in the roster, a member who left and a late joiner included, no other faction", function()
		local s = s2()
		local names = {}
		for _, p in ipairs(s.roster) do names[p.name] = p end
		for _, n in ipairs({ "Aurel", "Bryn", "Corin", "Dara", "Édda", "Hadri", "Ivo" }) do truthy(names[n], n) end
		isNil(names.Fenn)
		eq(names.Hadri.spec, "Restoration"); eq(names.Hadri.faction, "Nebulah")
		isNil(names.Aurel.start, "no `start` in the current format")
	end)

	it("folds voids in, leaves bank awards out, and writes the corrected state with the site's words", function()
		local s = s2()
		local r1 = s.raids[1].awards
		local function find(list, player, cost)
			for _, a in ipairs(list) do if a.player == player and a.cost == cost then return a end end
		end
		truthy(find(r1, "Bryn", 1)); truthy(find(r1, "Corin", 2)); truthy(find(r1, "Dara", 2))
		isNil(find(r1, "Édda", 2), "the voided award is not exported")
		local off = find(r1, "Aurel", 0)
		truthy(off); contains(off.item, "(off-spec)"); contains(off.item, "of the Test")
		eq(#r1, 5, "Bryn, Corin, Aurel (2 and the off-spec 0) and Dara: the bank item is out")
		isNil(off.kind, "no `kind` in the current format")
	end)

	it("writes the starting credits as synthetic rows in the member's first night, in the guild's words", function()
		local s = s2()
		local rows = {}
		for ri, r in ipairs(s.raids) do
			for _, a in ipairs(r.awards) do
				if a.item == "Crediti iniziali (media del roster)" then rows[#rows + 1] = { ri, a.player, a.cost } end
			end
		end
		-- the average of the roster at the time was 1 (7 / 5 floored): one row of 1 for Hadri; Ivo's fixed 3 is a 2 and a 1
		local per = {}
		for _, x in ipairs(rows) do
			eq(x[1], 2, x[2] .. " starts in the first night after joining")
			per[x[2]] = (per[x[2]] or 0) + x[3]
		end
		eq(per.Hadri, 1); eq(per.Ivo, 3)
		for _, x in ipairs(rows) do truthy(x[3] == 1 or x[3] == 2) end
	end)

	it("splits a cost of 3 into a 2 and a 1 and says it, leaves an adjustment out and says it", function()
		local b = build()
		local costs = {}
		for _, a in ipairs(plain(SE().Season(ledger(), "S2", opts())).raids[2].awards) do
			if a.player == "Aurel" then costs[#costs + 1] = a.cost end
		end
		table.sort(costs)
		deepEq(costs, { 1, 2 })
		eq(warningOf(b.warnings, "COST_ROUNDED", "2"), 1, "only Ivo's 1.5 loses something: a 3 splits into a 2 and a 1 exactly")
		eq(warningOf(b.warnings, "ADJUSTMENT_NOT_SHOWN", "2"), 1)
		eq(warningOf(b.warnings, "AWARD_OUTSIDE_ROSTER", "2"), 1, "Fenn is of the other faction")
		eq(warningOf(b.warnings, "AWARD_NOT_MEMBER", "2"), 1, "the bank item")
		eq(warningOf(b.warnings, "NIGHT_OPEN", "2"), 1)
		eq(warningOf(b.warnings, "AWARD_OPEN_NIGHT", "2"), 1)
	end)

	it("takes an award to the night it was written in or the night it names", function()
		local L = ledger({ noOpenNight = true })
		local A = full("Aurel")
		-- named night: the first night, written after the second one closed
		local first = Nt().List(L, "S2")[1]
		award(L, A, 80, "Bryn", 2, { night = first.id })
		local s = plain(SE().Season(L, "S2", opts()))
		local n = 0
		for _, a in ipairs(s.raids[1].awards) do if a.player == "Bryn" and a.cost == 2 then n = n + 1 end end
		eq(n, 1)
	end)

	it("refuses a season that does not exist", function()
		local obj, why = SE().Season(ledger(), "S9", opts())
		isNil(obj); eq(why, "SEASON_UNKNOWN")
	end)

	it("without a season, or a night, gives empty lists and no error", function()
		local L = Lg().New()
		local b = SE().Build(L, opts())
		eq(b.files.roster, '{\n  "updated": "2026-10-29",\n  "players": []\n}\n')
		eq(b.files.loot, '{\n  "seasons": []\n}\n')
		eq(b.fragments.loot, "null\n")
		isNil(b.season)
	end)
end)

describe("progress.json", function()
	it("has the own key only, the oldest date between the recorded kills and the one entered by hand, and null for the rest", function()
		local o = plain(SE().Progress(ledger(), opts()))
		eq(#o.instances, 2)
		local mc = o.instances[1]
		eq(mc.id, "mc"); eq(mc.name, "Molten Core"); eq(mc.size, 40)
		eq(mc.bosses[1].name, "Lucifron"); eq(mc.bosses[1].Nebulah, "2026-09-30", "a first kill entered by hand, older than the addon")
		eq(mc.bosses[2].name, "Magmadar"); eq(mc.bosses[2].Nebulah, "2026-10-14")
		eq(mc.bosses[3].Nebulah, SE().NULL)
		for _, inst in ipairs(o.instances) do
			for _, b in ipairs(inst.bosses) do isNil(b.Nebulaa, "the other guild's date never goes out") end
		end
		eq(o.instances[2].bosses[1].Nebulah, "2026-10-21")
		isNil(mc.cover); isNil(mc.locked)
	end)

	it("takes the key of the other faction when the guild is the other one", function()
		local o = plain(SE().Progress(ledger(), opts({ siteFaction = "Nebulaa" })))
		eq(o.instances[1].bosses[2].Nebulaa, "2026-10-02")
		eq(o.instances[1].bosses[1].Nebulaa, "2026-10-14", "the guild's own recorded kills count for its key; the other key's entered date does not")
	end)
end)

describe("what never leaves the addon", function()
	it("has no attendance, bench, realm, note, council reason or alt in any file", function()
		local L = ledger()
		local b = SE().Build(L, opts())
		for _, text in pairs(b.files) do
			for _, word in ipairs({ "bench", "lineup", "attend", "testrealm", "reason", "note", "twin", "avail" }) do
				falsy(text:lower():find(word, 1, true), word)
			end
		end
		for _, text in pairs(b.fragments) do falsy(text:lower():find("testrealm", 1, true)) end
	end)
end)

describe("the extended format (the hidden option of issue #3)", function()
	it("writes `start` on the roster rows and `kind` on the rows, instead of the synthetic rows", function()
		local b = build({ extended = true })
		golden("site_loot_extended.json", b.files.loot)
		local s = plain(SE().Season(ledger(), "S2", opts({ extended = true })))
		local names = {}
		for _, p in ipairs(s.roster) do names[p.name] = p end
		eq(names.Hadri.start, 1); eq(names.Ivo.start, 3); isNil(names.Aurel.start)
		for _, r in ipairs(s.raids) do
			for _, a in ipairs(r.awards) do
				truthy(a.kind == "award" or a.kind == "adjust")
				falsy(a.item == "Crediti iniziali (media del roster)")
			end
		end
		local adjust
		for _, a in ipairs(s.raids[2].awards) do if a.kind == "adjust" then adjust = a end end
		truthy(adjust); eq(adjust.cost, 1.5); eq(adjust.player, "Dara")
	end)

	it("is off by default and in the rules", function()
		eq(FDCP.Progress.DefaultConfig().extended, false)
		local ok = FDCP.Progress.ValidateConfig({ factionName = "", extended = true })
		truthy(ok)
		local bad, problems = FDCP.Progress.ValidateConfig({ factionName = "", extended = "yes" })
		falsy(bad); eq(problems[1], "extended")
	end)
end)

describe("the saved copy and the Site form", function()
	local function open(rank)
		local L = ledger({ noOpenNight = true })
		NC():Bind(L)
		Mock.Advance(3)
		RC().faction = "Horde"
		Mock.Slash("/fdcp")
		FDCP.MainWindow:SelectTab("history")
		HW():Refresh()
		HW().root.sub:Select("export")
		return L
	end

	describe("an officer", function()
		before_boot(guild(1))

		it("saves the files at every night close and on request, as JSON text with the codes of what was left out", function()
			local L = open()
			RC().faction = "Horde"
			local saved, why = SES():Save()
			assert(saved, tostring(why))
			eq(saved.faction, "Nebulah"); eq(saved.season, "S2"); eq(saved.extended, false)
			contains(saved.files.loot, '"season": "2"')
			contains(saved.files.progress, '"Nebulah"')
			deepEq(SES():Saved(), saved)
			local found = false
			for _, w in ipairs(saved.warnings) do if w:find("^AWARD_NOT_MEMBER:1:2$") then found = true end end
			truthy(found, "a warning line is CODE:n:season")
			-- a night closed saves again, silently
			SES().Saved().files = nil
			FDCP.Bus:Emit("NIGHT_CLOSED", {})
			truthy(SES():Saved().files.roster)
		end)

		it("shows the Site form: three files, full or fragment, selectable, with the warning", function()
			open()
			XW().seg:Select("site")
			eq(XW().kind, "site")
			truthy(XW().filesSeg:IsShown()); truthy(XW().formSeg:IsShown())
			contains(XW().edit:GetText(), '"players"')
			XW().filesSeg:Select("loot")
			contains(XW().edit:GetText(), '"seasons"')
			contains(XW().edit:GetText(), "Item ")
			XW().formSeg:Select("fragment")
			contains(XW().warning:GetText(), "by hand")
			contains(XW().edit:GetText(), '"season": "2"')
			falsy(XW().edit:GetText():find('"seasons"', 1, true))
			XW().filesSeg:Select("progress")
			contains(XW().edit:GetText(), '"bosses"')
			XW().formSeg:Select("full")
			contains(XW().edit:GetText(), '"instances"')
			contains(XW().warning:GetText(), "site_export.py")
			XW():SelectAll()
			truthy(XW().edit._highlighted)
			local text = XW().text
			XW().edit:SetText("tampered")
			Mock.RunScript(XW().edit, "OnTextChanged", true)
			eq(XW().edit:GetText(), text, "an edit by hand is put back")
		end)

		it("saves from the button and says so", function()
			open()
			XW().seg:Select("site")
			XW().saveButton:Click()
			truthy(SES():Saved())
			contains(XW().notes:GetText(), "site_export.py")
		end)

		it("hides the Site-only controls on the other kinds", function()
			open()
			XW().seg:Select("site")
			XW().seg:Select("csv")
			falsy(XW().filesSeg:IsShown()); falsy(XW().saveButton:IsShown())
		end)
	end)

	describe("a raider", function()
		before_boot(guild(3))

		it("cannot save or build, and a forced call is refused", function()
			open()
			local saved, why = SES():Save()
			isNil(saved); eq(why, "RANK_TOO_LOW")
			local texts, why2 = XW().Generate("site", "S2")
			isNil(texts); eq(why2, "RANK_TOO_LOW")
			isNil(SES():Saved())
		end)
	end)
end)
