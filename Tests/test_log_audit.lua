-- History › Log and Audit (M6-2): everything that dropped, assigned or not, and every council intervention and settings
-- change with its reason. Domain/History.lua (Log, Audit, filters) and the two panes of the History tab (mock client).
local function Lg() return FDCP.Ledger end
local function Sn() return FDCP.Season end
local function M() return FDCP.Members end
local function N() return FDCP.Nights end
local function H() return FDCP.History end
local function NC() return FDCP.NightController end
local function HW() return FDCP.HistoryWindow end
local function LW() return FDCP.LogWindow end
local function AW() return FDCP.AuditWindow end

local GM, OFFICER = "Aurel-Camelot", "Bryn-Camelot"
local POOL = { "Aurel", "Bryn", "Corin", "Dara" }
local function full(n) return n .. "-Camelot" end

local function award(L, ts, member, item, cost, extra)
	local p = { target = "member", member = member and full(member), item = item, cost = cost, reasons = {}, flags = {} }
	for k, v in pairs(extra or {}) do p[k] = v end
	return assert(Lg().Append(L, { author = OFFICER, ts = ts, season = "S1", type = "ITEM_AWARDED", payload = p }))
end

-- Season S1, one night in Molten Core (ts 100), the council's interventions of the M5 tests and a rules change:
--   19003 to Bryn (1, response MAIN_SPEC_TIER, boss 663), 19004 to Corin (2) departing from the rule (OBVIOUS_WASTE) with a
--   correction before the roll, 19007 to Dara decided by the council's vote, 19003 to Aurel voided (MISTAKE), 19005 to
--   the bank, 19009 seen and not given; Bryn adjusted +1 (PENALTY... see below); the GM changes the rules at ts 90 and 140.
local function ledger()
	local L = Lg().New()
	assert(Sn().Open(L, { author = GM, ts = 1, season = "S1", label = "Tier 1", instances = { { id = 409, size = 40 } } }))
	for i, name in ipairs(POOL) do
		assert(M().Join(L, { author = OFFICER, ts = 1 + i, season = "S1", member = full(name), faction = "Horde" }))
	end
	local r = FDCP.Rules.Current(L)
	r.session.autoAdvance = not r.session.autoAdvance
	assert(FDCP.Rules.Change(L, { author = GM, ts = 90, rules = r, confirmed = true }))
	assert(N().Open(L, { author = OFFICER, ts = 100, season = "S1", date = "2026-11-10", instanceID = 409,
		difficulty = "normal", faction = "Horde" }))
	assert(N().Kill(L, { author = OFFICER, ts = 110, season = "S1", encounterID = 663, instanceID = 409, difficulty = 14 }))
	award(L, 121, "Bryn", 19003, 1, { response = "MAIN_SPEC", encounter = 663 })
	award(L, 122, "Corin", 19004, 2, { intervention = true, mlReason = "OBVIOUS_WASTE", ruleWinner = full("Aurel"), ruleCost = 1,
		encounter = 663, corrections = { { category = "weapon", cost = 2, reason = "MISTAKE", by = OFFICER } } })
	award(L, 123, "Dara", 19007, 1, { votes = { [full("Dara")] = 2 }, encounter = 663 })
	local wrong = award(L, 124, "Aurel", 19003, 1, { encounter = 663 })
	award(L, 125, nil, 19005, 0, { target = "bank", encounter = 663 })
	assert(Lg().Append(L, { author = OFFICER, ts = 126, season = "S1", type = "DROP_SEEN", payload = { item = 19009, encounter = 663 } }))
	assert(Lg().Append(L, { author = OFFICER, ts = 127, season = "S1", type = "AWARD_VOIDED",
		payload = { ref = wrong.id, reason = "MISTAKE" } }))
	assert(Lg().Append(L, { author = OFFICER, ts = 128, season = "S1", type = "CREDITS_ADJUSTED",
		payload = { member = full("Bryn"), delta = -1, reason = "PENALTY" } }))
	assert(N().Close(L, { author = OFFICER, ts = 130, season = "S1" }))
	local r2 = FDCP.Rules.Current(L)
	r2.session.autoAdvance = not r2.session.autoAdvance
	r2.cost.perBoss = nil
	assert(FDCP.Rules.Change(L, { author = GM, ts = 140, rules = r2, confirmed = true }))
	return L, wrong
end

describe("the loot log", function()
	it("lists every drop, assigned or not, with the boss, the recipient, the response and the cost", function()
		local L = ledger()
		local rows = assert(H().Log(L, "S1"))
		eq(#rows, 6, "five awards and one drop nobody got")
		local bryn = rows[1]
		eq(bryn.kind, "AWARD"); eq(bryn.item, 19003); eq(bryn.member, full("Bryn")); eq(bryn.cost, 1)
		eq(bryn.response, "MAIN_SPEC"); eq(bryn.boss, 663); eq(bryn.nightDate, "2026-11-10")
		eq(rows[2].intervention, true)
		eq(rows[5].target, "bank")
		local seen = rows[6]
		eq(seen.kind, "SEEN"); eq(seen.item, 19009); eq(seen.boss, 663); eq(seen.target, "none")
		eq(seen.nightDate, "2026-11-10")
		eq(H().Log(L, "S9"), nil)
		eq(select(2, H().Log(L, "S9")), "SEASON_UNKNOWN")
	end)

	it("keeps a voided award in the log, marked", function()
		local L, wrong = ledger()
		local rows = H().Log(L, "S1")
		eq(rows[4].id, wrong.id); eq(rows[4].voided, true)
		eq(#H().FilterLog(rows, { state = "voided" }), 1)
	end)

	it("filters by state, member, item, boss and recipient", function()
		local rows = H().Log(ledger(), "S1")
		eq(#H().FilterLog(rows, { state = "assigned" }), 4, "four awards, the voided one and the unseen drop are out")
		eq(#H().FilterLog(rows, { state = "unassigned" }), 1)
		eq(#H().FilterLog(rows, { state = "valid" }), 5)
		eq(#H().FilterLog(rows, { member = full("Bryn") }), 1)
		eq(#H().FilterLog(rows, { item = 19003 }), 2)
		eq(#H().FilterLog(rows, { boss = 663 }), 6)
		eq(#H().FilterLog(rows, { boss = 999 }), 0)
		eq(#H().FilterLog(rows, { target = "bank" }), 1)
		eq(#H().FilterLog(rows, { response = "MAIN_SPEC" }), 1)
		eq(#H().FilterLog(rows, nil), 6)
	end)
end)

describe("the audit", function()
	it("has every council intervention with its reason, the voids, the adjustments and the settings changes", function()
		local L = ledger()
		local list = assert(H().Audit(L, "S1"))
		local by = {}
		for _, e in ipairs(list) do by[e.kind] = (by[e.kind] or 0) + 1 end
		eq(by.MODIFY, 1); eq(by.CORRECT, 1); eq(by.VOTE, 1); eq(by.VOID, 1); eq(by.ADJUST, 1); eq(by.CONFIG, 2)
		for _, e in ipairs(list) do
			if e.kind == "MODIFY" then eq(e.reason, "OBVIOUS_WASTE"); eq(e.ruleWinner, full("Aurel")) end
			if e.kind == "CORRECT" then eq(e.reason, "MISTAKE") end
			if e.kind == "VOID" then eq(e.reason, "MISTAKE"); eq(e.item, nil) end
			if e.kind == "ADJUST" then eq(e.reason, "PENALTY"); eq(e.delta, -1) end
		end
		for i = 2, #list do truthy(list[i - 1].ts <= list[i].ts, "oldest first") end
	end)

	it("reads the settings changes from the rules, with who, when and what changed", function()
		local list = H().Audit(ledger(), "S1")
		local cfg = {}
		for _, e in ipairs(list) do if e.kind == "CONFIG" then cfg[#cfg + 1] = e end end
		eq(cfg[1].author, GM); eq(cfg[1].ts, 90)
		eq(#cfg[1].changes, 1); eq(cfg[1].changes[1], "session.autoAdvance")
		eq(cfg[2].ts, 140)
		truthy(#cfg[2].changes >= 1)
	end)

	it("filters by kind, member, author and item", function()
		local list = H().Audit(ledger(), "S1")
		eq(#H().FilterAudit(list, { kind = "CONFIG" }), 2)
		eq(#H().FilterAudit(list, { author = GM }), 2)
		eq(#H().FilterAudit(list, { member = full("Corin") }), 1)
		eq(#H().FilterAudit(list, { kind = "VOID", author = OFFICER }), 1)
		eq(#H().FilterAudit(list, nil), #list)
		eq(select(2, H().Audit(ledger(), "S9")), "SEASON_UNKNOWN")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The two panes (the mock client).

local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }
local function guild(rank)
	return function(Mock)
		Mock.guild.Set({ name = "Keepers", ranks = RANKS, myRank = rank or 1, members = {
			{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
		} })
	end
end

local function open(sub)
	local L = ledger()
	NC():Bind(L)
	Mock.Advance(3)
	Mock.Slash("/fdcp")
	FDCP.MainWindow:SelectTab("history")
	HW():Refresh()
	HW().root.sub:Select(sub)
	return L
end

local function texts(row)
	local out = {}
	for i, c in ipairs(row.cells) do out[i] = c:GetText() or "" end
	return table.concat(out, " | ")
end
local function allRows(t)
	local out = {}
	for _, r in ipairs(t:VisibleRows()) do out[#out + 1] = texts(r) end
	return table.concat(out, "\n")
end

describe("the Log pane", function()
	before_boot(guild(1))

	it("shows every drop and filters by state and search", function()
		open("log")
		truthy(HW().root.panes.log:IsShown())
		eq(#LW().rows, 6)
		contains(LW().count:GetText(), "6 of 6")
		local t = allRows(LW().table)
		contains(t, "Not given"); contains(t, "Guild bank"); contains(t, "Bryn")
		LW().filter:Select("unassigned")
		eq(#LW().rows, 1)
		LW().filter:Select("voided")
		eq(#LW().rows, 1)
		LW().filter:Select("all")
		LW():SetSearch("bryn")
		eq(#LW().rows, 1, "the search finds a member")
		LW():SetSearch("19009")
		eq(#LW().rows, 1, "and an item")
		LW():SetSearch("zzz")
		eq(#LW().rows, 0)
		LW():SetSearch("")
		eq(#LW().rows, 6)
	end)

	it("says what each recipient is and leaves the cost of a drop nobody got empty", function()
		open("log")
		local rows = LW().rows
		eq(LW().Recipient(rows[1]), "Bryn"); eq(LW().Recipient(rows[5]), "Guild bank"); eq(LW().Recipient(rows[6]), "Not given")
		eq(LW().Response(rows[1]), FDCP.Reasons.Text("RESPONSE", "MAIN_SPEC"))
		eq(LW().Response(rows[2]), "")
	end)
end)

describe("the Audit pane", function()
	before_boot(guild(1))

	it("shows every entry with its reason and filters by kind and search", function()
		open("audit")
		truthy(HW().root.panes.audit:IsShown())
		eq(#AW().rows, #AW().all)
		local joined = {}
		for _, e in ipairs(AW().all) do joined[#joined + 1] = AW().Line(e) end
		local text = table.concat(joined, "\n")
		contains(text, FDCP.Reasons.Text("CORRECTION", "OBVIOUS_WASTE"))
		contains(text, FDCP.Reasons.Text("CORRECTION", "MISTAKE"))
		contains(text, FDCP.Reasons.Text("CORRECTION", "PENALTY"))
		contains(text, "session.autoAdvance")
		AW().seg:Select("config")
		eq(#AW().rows, 2)
		AW().seg:Select("void")
		eq(#AW().rows, 1)
		AW().seg:Select("council")
		eq(#AW().rows, 3, "the departure, the correction and the vote")
		AW().seg:Select("all")
		AW():SetSearch("zzz")
		eq(#AW().rows, 0)
		AW():SetSearch("")
		eq(#AW().rows, #AW().all)
	end)

	it("follows the season shown in the Nights pane", function()
		open("audit")
		eq(HW().seasonShown, "S1")
		truthy(#AW().rows > 0)
	end)
end)
