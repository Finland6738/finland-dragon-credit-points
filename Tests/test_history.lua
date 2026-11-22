-- History views (M6-1): the nights by week, a member and an item, from the ledger. Domain/History.lua is pure; the
-- History tab, the Member window and the Item window draw what it returns. Attendance is for the officers only.
local function Lg() return FDCP.Ledger end
local function Sn() return FDCP.Season end
local function M() return FDCP.Members end
local function N() return FDCP.Nights end
local function H() return FDCP.History end
local function P() return FDCP.Permissions end
local function NC() return FDCP.NightController end
local function RC() return FDCP.RosterController end
local function HW() return FDCP.HistoryWindow end

local GM, OFFICER, RAIDER = "Aurel-Camelot", "Bryn-Camelot", "Corin-Camelot"
local POOL = { "Aurel", "Bryn", "Corin", "Dara", "Edda", "Fenn" }
local PACK = { { id = 409, size = 40 }, { id = 249, size = 40 } }
local function full(n) return n .. "-Camelot" end

local function award(L, ts, member, item, cost, extra)
	local p = { target = "member", member = member and full(member), item = item, cost = cost, reasons = {}, flags = {} }
	for k, v in pairs(extra or {}) do p[k] = v end
	return assert(Lg().Append(L, { author = OFFICER, ts = ts, season = "S1", type = "ITEM_AWARDED", payload = p }))
end

-- Season S1, six mains (start credits 0), three nights over two weeks:
--   ts 100  Tue 2026-11-10 Molten Core: Aurel Bryn Corin raid, Dara bench; kills Lucifron, Magmadar; awards 19003 to Bryn (1),
--           19004 to Corin (2), 19003 to Aurel (1) voided afterwards, 19005 to the guild bank
--   ts 200  Thu 2026-11-12 Molten Core: Aurel Dara raid, Corin bench; kill Lucifron; 19003 to Dara (2)
--   ts 300  Tue 2026-11-17 Onyxia's Lair (249): Aurel Bryn raid; kill Onyxia; 19006 to Bryn (1); Bryn adjusted +1 (CORRECTION)
local function ledger()
	local L = Lg().New()
	assert(Sn().Open(L, { author = GM, ts = 1, season = "S1", label = "Tier 1", instances = PACK }))
	for i, name in ipairs(POOL) do
		assert(M().Join(L, { author = OFFICER, ts = 1 + i, season = "S1", member = full(name), faction = "Horde" }))
	end
	local function night(ts, date, instance)
		return assert(N().Open(L, { author = OFFICER, ts = ts, season = "S1", date = date, instanceID = instance,
			difficulty = "normal", faction = "Horde" }))
	end
	local function close(ts) assert(N().Close(L, { author = OFFICER, ts = ts, season = "S1" })) end
	local function kill(ts, id, instance)
		assert(N().Kill(L, { author = OFFICER, ts = ts, season = "S1", encounterID = id, instanceID = instance, difficulty = 14 }))
	end
	local function lineup(ts, raid, bench)
		local r, b = {}, {}
		for _, n in ipairs(raid) do r[#r + 1] = full(n) end
		for _, n in ipairs(bench or {}) do b[#b + 1] = full(n) end
		assert(N().SetLineup(L, { author = OFFICER, ts = ts, season = "S1", raid = r, bench = b }))
	end
	night(100, "2026-11-10", 409)
	lineup(101, { "Aurel", "Bryn", "Corin" }, { "Dara" })
	kill(110, 663, 409)
	kill(120, 664, 409)
	award(L, 121, "Bryn", 19003, 1)
	award(L, 122, "Corin", 19004, 2, { intervention = true, mlReason = "TRADEOFF", ruleWinner = full("Aurel"), ruleCost = 1 })
	local wrong = award(L, 123, "Aurel", 19003, 1)
	award(L, 124, nil, 19005, 0, { target = "bank" })
	assert(Lg().Append(L, { author = OFFICER, ts = 125, season = "S1", type = "AWARD_VOIDED",
		payload = { ref = wrong.id, reason = "MISTAKE" } }))
	close(130)
	night(200, "2026-11-12", 409)
	lineup(201, { "Aurel", "Dara" }, { "Corin" })
	kill(210, 663, 409)
	award(L, 211, "Dara", 19003, 2)
	close(220)
	night(300, "2026-11-17", 249)
	lineup(301, { "Aurel", "Bryn" })
	kill(310, 1065, 249)
	award(L, 311, "Bryn", 19006, 1)
	assert(Lg().Append(L, { author = OFFICER, ts = 312, season = "S1", type = "CREDITS_ADJUSTED",
		payload = { member = full("Bryn"), delta = 1, reason = "CORRECTION" } }))
	close(320)
	return L, wrong
end

describe("the weeks", function()
	it("names a week by its Monday, across month, year and leap-day edges", function()
		eq(H().WeekOf("2026-11-10"), "2026-11-09", "a Tuesday")
		eq(H().WeekOf("2026-11-09"), "2026-11-09", "a Monday")
		eq(H().WeekOf("2026-11-15"), "2026-11-09", "a Sunday")
		eq(H().WeekOf("2026-11-16"), "2026-11-16")
		eq(H().WeekOf("2026-01-01"), "2025-12-29", "into the previous year")
		eq(H().WeekOf("2024-03-01"), "2024-02-26", "after a leap day")
		isNil(H().WeekOf("2026-13-01"))
		isNil(H().WeekOf(nil))
	end)
end)

describe("the nights view", function()
	it("lists the nights by week, newest first, with instance, bosses, drops and what was spent", function()
		local L = ledger()
		local v = assert(H().Nights(L, "S1"))
		eq(#v.weeks, 2)
		eq(v.weeks[1].week, "2026-11-16"); eq(v.weeks[2].week, "2026-11-09")
		eq(#v.weeks[1].nights, 1); eq(#v.weeks[2].nights, 2)
		eq(#v.nights, 3)
		local c, b, a = v.nights[1], v.nights[2], v.nights[3]
		eq(c.date, "2026-11-17"); eq(b.date, "2026-11-12"); eq(a.date, "2026-11-10")
		eq(a.instanceID, 409); eq(a.size, 40); eq(a.difficulty, "normal"); eq(a.closed, true)
		eq(table.concat(a.bosses, ","), "663,664")
		eq(a.bossTotal, 10)
		eq(a.dropCount, 4, "every award, a voided one and a bank item included")
		eq(a.spent, 3, "1 + 2: the voided award and the bank item cost nothing")
		eq(a.awardedTo, 2)
		eq(c.instanceID, 249); eq(c.spent, 1); eq(#c.bosses, 1)
		eq(b.spent, 2)
	end)

	it("keeps a voided award in the drops, marked, and out of the credits", function()
		local L, wrong = ledger()
		local a = H().Nights(L, "S1").nights[3]
		local found
		for _, d in ipairs(a.drops) do if d.id == wrong.id then found = d end end
		truthy(found); eq(found.voided, true); eq(found.member, full("Aurel"))
		local bank
		for _, d in ipairs(a.drops) do if d.target == "bank" then bank = d end end
		truthy(bank); eq(bank.item, 19005)
	end)

	it("the credits spent per night add up to the ledger's total spent", function()
		local L = ledger()
		local v = H().Nights(L, "S1")
		local spent = 0
		for _, n in ipairs(v.nights) do spent = spent + n.spent end
		local credits = Lg().Credits(L, "S1")
		local sum = 0
		for _, c in pairs(credits) do sum = sum + c end
		eq(Lg().Round(spent + 1), sum, "the ledger's sum is the nights' spending plus Bryn's +1 adjustment")
	end)

	it("hides the lineup and the bench without the attendance permission, and shows them with it", function()
		local L = ledger()
		local plain = H().Nights(L, "S1")
		for _, n in ipairs(plain.nights) do isNil(n.lineup, "no lineup for a member") end
		local off = H().Nights(L, "S1", { attendance = true })
		local a = off.nights[3]
		eq(table.concat(a.lineup.raid, ","), "Aurel-Camelot,Bryn-Camelot,Corin-Camelot")
		eq(table.concat(a.lineup.bench, ","), "Dara-Camelot")
	end)

	it("answers an unknown season with a code and a season with no nights with an empty list", function()
		local L = ledger()
		local none, why = H().Nights(L, "S404")
		isNil(none); eq(why, "SEASON_UNKNOWN")
		assert(Sn().Close(L, { author = GM, ts = 400, season = "S1" }))
		assert(Sn().Open(L, { author = GM, ts = 401, season = "S2", instances = PACK }))
		local v = H().Nights(L, "S2")
		eq(#v.nights, 0); eq(#v.weeks, 0)
	end)
end)

describe("the member view", function()
	it("lists the member's items and a credit curve that ends at the ledger's number", function()
		local L = ledger()
		local v = assert(H().Member(L, "S1", full("Bryn")))
		eq(v.member, full("Bryn"))
		eq(#v.items, 2)
		eq(v.items[1].item, 19003); eq(v.items[2].item, 19006)
		eq(v.total, Lg().Credits(L, "S1")[full("Bryn")])
		eq(v.total, 3, "1 + 1 + the +1 adjustment")
		eq(#v.curve, 4)
		eq(v.curve[1].kind, "START"); eq(v.curve[1].total, 0)
		eq(v.curve[2].kind, "AWARD"); eq(v.curve[2].total, 1)
		eq(v.curve[3].kind, "AWARD"); eq(v.curve[3].total, 2)
		eq(v.curve[4].kind, "ADJUST"); eq(v.curve[4].total, 3)
		eq(v.curve[#v.curve].total, v.total)
	end)

	it("every member's curve ends at the ledger's credits", function()
		local L = ledger()
		local credits = Lg().Credits(L, "S1")
		for _, name in ipairs(POOL) do
			eq(H().Member(L, "S1", full(name)).total, credits[full(name)], name)
		end
	end)

	it("a voided award stays in the items, marked, and moves nothing in the curve", function()
		local L = ledger()
		local v = H().Member(L, "S1", full("Aurel"))
		eq(#v.items, 1); eq(v.items[1].voided, true)
		eq(#v.curve, 1)
		eq(v.total, 0)
	end)

	it("the council's actions about the member: a modify and the void of an award they held", function()
		local L = ledger()
		local corin = H().Member(L, "S1", full("Corin"))
		eq(#corin.council, 1); eq(corin.council[1].kind, "MODIFY"); eq(corin.council[1].reason, "TRADEOFF")
		local aurel = H().Member(L, "S1", full("Aurel"))
		eq(#aurel.council, 1); eq(aurel.council[1].kind, "VOID"); eq(aurel.council[1].reason, "MISTAKE")
		local bryn = H().Member(L, "S1", full("Bryn"))
		eq(#bryn.council, 1); eq(bryn.council[1].kind, "ADJUST"); eq(bryn.council[1].delta, 1)
	end)

	it("carries the attendance only with the permission", function()
		local L = ledger()
		local plain = H().Member(L, "S1", full("Aurel"))
		isNil(plain.attendance)
		local off = H().Member(L, "S1", full("Aurel"), { attendance = true })
		truthy(off.attendance)
		eq(off.attendance.played, 3); eq(off.attendance.benched, 0)
		eq(off.attendance.perNight[1].state, "PLAYED")
		local dara = H().Member(L, "S1", full("Dara"), { attendance = true }).attendance
		eq(dara.played, 1); eq(dara.benched, 1, "benched on the first night, played the second")
		eq(dara.perNight[1].state, "BENCH"); eq(dara.perNight[2].state, "PLAYED"); eq(dara.perNight[3].state, "ABSENT")
		eq(dara.bosses, 1)
	end)

	it("answers an unknown member or season with a code", function()
		local L = ledger()
		local none, why = H().Member(L, "S1", full("Nobody"))
		isNil(none); eq(why, "MEMBER_UNKNOWN")
		none, why = H().Member(L, "S404", full("Bryn"))
		eq(why, "SEASON_UNKNOWN")
	end)
end)

describe("the item view", function()
	it("lists an item's drops and who owns it, the voided one kept out of the count", function()
		local L = ledger()
		local v = H().Item(L, 19003)
		eq(#v.drops, 3, "Bryn, Aurel (voided), Dara")
		eq(v.count, 2)
		eq(#v.owners, 2)
		eq(v.owners[1].count, 1)
		eq(v.owners[1].member, full("Bryn"), "equal counts: by name")
		eq(v.owners[2].member, full("Dara"))
		local voided = 0
		for _, d in ipairs(v.drops) do if d.voided then voided = voided + 1 end end
		eq(voided, 1)
	end)

	it("an item given to the bank has a drop and no owner, and an unknown item is empty", function()
		local L = ledger()
		local bank = H().Item(L, 19005)
		eq(bank.count, 1); eq(#bank.owners, 0); eq(bank.drops[1].target, "bank")
		local none = H().Item(L, 99999)
		eq(none.count, 0); eq(#none.drops, 0); eq(#none.owners, 0)
	end)

	it("counts the drops seen and can be limited to one season", function()
		local L = ledger()
		assert(Lg().Append(L, { author = OFFICER, ts = 150, season = "S1", type = "DROP_SEEN", payload = { item = 19003 } }))
		eq(H().Item(L, 19003).seen, 1)
		eq(H().Item(L, 19003, { season = "S2" }).count, 0)
		eq(H().Item(L, 19003, { season = "S1" }).count, 2)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The History tab and the Member and Item windows (the mock client). The player is an officer (rank 1) unless a test
-- demotes them to a raider.

local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }
local function guild(rank)
	return function(Mock)
		Mock.guild.Set({ name = "Keepers", ranks = RANKS, myRank = rank or 1, members = {
			{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
		} })
	end
end

local function bound()
	local L = ledger()
	NC():Bind(L)
	Mock.Advance(3)
	return L
end

local function open()
	Mock.Slash("/fdcp")
	FDCP.MainWindow:SelectTab("history")
	HW():Refresh()
	return HW().nights
end

local function cell(row, i) return row.cells[i]:GetText() end
local function allText(lines)
	local out = {}
	for _, l in ipairs(lines) do out[#out + 1] = l.text:GetText() end
	return table.concat(out, "\n")
end

describe("the History tab", function()
	before_boot(guild(1))

	it("has the sub-tabs Nights, Log, Audit and Export, the Export one says it is coming", function()
		bound()
		open()
		local root = HW().root
		truthy(root.panes.nights:IsShown())
		eq(HW():ActiveSub(), "nights")
		root.sub:Select("log")
		truthy(root.panes.log:IsShown()); falsy(root.panes.nights:IsShown())
		contains(root.panes.export.soon:GetText(), "later version")
		root.sub:Select("export")
		truthy(root.panes.export:IsShown())
		root.sub:Select("nights")
		truthy(root.panes.nights:IsShown())
	end)

	it("lists the nights newest first with the instance, bosses, drops and credits spent", function()
		bound()
		local n = open()
		local rows = n.table:VisibleRows()
		eq(#rows, 3)
		eq(cell(rows[1], 2), "17/11"); eq(cell(rows[2], 2), "12/11"); eq(cell(rows[3], 2), "10/11")
		eq(cell(rows[1], 3), "Onyxia\226\128\153s Lair")
		eq(cell(rows[3], 3), "Molten Core")
		eq(cell(rows[3], 4), "2/10")
		eq(cell(rows[3], 5), "4")
		eq(cell(rows[3], 6), "3")
		eq(cell(rows[1], 1), "16/11", "the first night of a week shows the week")
		eq(cell(rows[2], 1), "09/11")
		eq(cell(rows[3], 1), "", "the second night of the same week does not repeat it")
		contains(HW().root.panes.nights:IsShown() and n.eyebrow:GetText() or "", "TIER 1")
	end)

	it("shows the detail of the selected night: bosses, drops with the voided one marked, lineup and bench for an officer", function()
		bound()
		local n = open()
		eq(HW().nightId, HW().view.nights[1].id, "the newest night is selected first")
		n.table:VisibleRows()[3]:Click()
		contains(n.head:GetText(), "2026-11-10")
		contains(n.head:GetText(), "Molten Core"); contains(n.head:GetText(), "40 players"); contains(n.head:GetText(), "Normal")
		contains(n.bosses:GetText(), "Lucifron"); contains(n.bosses:GetText(), "Magmadar")
		contains(n.raid:GetText(), "Aurel"); contains(n.raid:GetText(), "Corin")
		contains(n.bench:GetText(), "Dara")
		local drops = n.drops:VisibleRows()
		eq(#drops, 4)
		local text = {}
		for i, r in ipairs(drops) do text[i] = cell(r, 1) .. "|" .. cell(r, 2) .. "|" .. cell(r, 3) end
		contains(table.concat(text, "\n"), "(cancelled)")
		contains(table.concat(text, "\n"), "Guild bank")
		contains(table.concat(text, "\n"), "Bryn")
	end)

	it("a drop opens the Member and Item windows", function()
		bound()
		local n = open()
		n.table:VisibleRows()[3]:Click()
		falsy(FDCP.MemberWindow:IsShown())
		local row
		for _, r in ipairs(n.drops:VisibleRows()) do if cell(r, 2) == "Corin" then row = r end end
		row:Click()
		n.member:Click()
		truthy(FDCP.MemberWindow:IsShown())
		eq(FDCP.MemberWindow.shown, full("Corin"), "the ledger's own name")
		row:Click()
		n.item:Click()
		truthy(FDCP.ItemWindow:IsShown())
		eq(FDCP.ItemWindow.shown, 19004)
	end)

	it("the Member window carries the items, the curve and the council, and the attendance for an officer", function()
		bound()
		assert(FDCP.MemberWindow:Show(full("Corin"), "S1"))
		local text = allText(FDCP.MemberWindow.frame:Lines())
		contains(text, "Credits: 2 (start: 0)")
		contains(text, "10/11"); contains(text, "2 credits")
		contains(text, "Award: +2 → 2")
		contains(text, "to Corin instead of Aurel")
		contains(text, "ATTENDANCE (OFFICERS ONLY)")
		contains(text, "Nights played: 1")
	end)

	it("the Item window lists the owners and every drop", function()
		bound()
		assert(FDCP.ItemWindow:Show(19003))
		local text = allText(FDCP.ItemWindow.frame:Lines())
		contains(text, "Dropped 3 times")
		contains(text, "given 2 times")
		contains(text, "Bryn × 1"); contains(text, "Dara × 1")
		contains(text, "(cancelled)")
		contains(text, "to Dara")
	end)
end)

describe("a member in the History tab", function()
	before_boot(guild(3))

	it("never sees the lineup, the bench or the attendance", function()
		bound()
		local n = open()
		n.table:VisibleRows()[3]:Click()
		eq(n.raid:GetText(), ""); eq(n.bench:GetText(), "")
		falsy(n.raid:IsShown()); falsy(n.bench:IsShown())
		eq(#n.drops:VisibleRows(), 4, "the drops and the credits are public")
		assert(FDCP.MemberWindow:Show(full("Corin"), "S1"))
		local text = allText(FDCP.MemberWindow.frame:Lines())
		falsy(text:lower():find("attendance", 1, true), "no attendance for a member")
		falsy(text:find("Nights played", 1, true))
		contains(text, "Credits: 2")
		isNil(FDCP.MemberWindow.data.attendance)
		for _, night in ipairs(HW().view.nights) do isNil(night.lineup) end
	end)
end)

describe("the History tab without data", function()
	before_boot(guild(1))

	it("says so when there is no season, and cycles the season when there are several", function()
		local L = Lg().New()
		NC():Bind(L)
		Mock.Advance(3)
		local n = open()
		contains(n.empty:GetText(), "No season is open")
		falsy(n.table:IsShown())
		L = bound()
		open()
		truthy(HW().nights.table:IsShown())
		assert(Sn().Close(L, { author = GM, ts = 400, season = "S1" }))
		assert(Sn().Open(L, { author = GM, ts = 401, season = "S2", label = "Tier 2", instances = PACK }))
		HW():Refresh()
		eq(HW().seasonShown, "S2")
		eq(#HW().nights.table:GetData(), 0)
		contains(HW().nights.hint:GetText(), "No night")
		HW():CycleSeason()
		eq(HW().seasonShown, "S1")
		eq(#HW().nights.table:GetData(), 3)
	end)
end)
