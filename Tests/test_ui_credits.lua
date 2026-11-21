-- The Credits tab (M3-8): Domain/CreditTable.lua (the numbers, from the ledger) and UI/Windows/Credits.lua (the accordion,
-- the night columns, the total chip, the queue, the filters, the player's own row). docs/ANALISI.md §9.3.
local function Lg() return FDCP.Ledger end
local function Sn() return FDCP.Season end
local function R() return FDCP.Roster end
local function Nt() return FDCP.Nights end
local function CT() return FDCP.CreditTable end
local function NC() return FDCP.NightController end
local function RC() return FDCP.RosterController end
local function CW() return FDCP.CreditsWindow end

local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }
local REALM = "TestRealm"
local function full(n) return n .. "-" .. REALM end

local function guild(M)
	M.guild.Set({ name = "Keepers", ranks = RANKS, myRank = 1, members = {
		{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
	} })
end

-- name, spec, faction
local POOL = {
	{ "Aurel", 73, "Horde" },     -- Protection Warrior (tank)
	{ "Bryn", 65, "Horde" },      -- Holy Paladin (healer)
	{ "Corin", 105, "Horde" },    -- Restoration Druid (healer)
	{ "Dara", 63, "Horde" },      -- Fire Mage (dps)
	{ "Edda", 258, "Horde" },     -- Shadow Priest (dps)
	{ "Fenn", 70, "Alliance" },   -- Retribution Paladin (dps)
	{ "Testchar", 63, "Horde" },  -- the player (a mage)
}

local function award(L, author, ts, season, member, cost, extra)
	local p = { target = "member", member = full(member), item = 100 + ts, cost = cost, reasons = {}, flags = {} }
	for k, v in pairs(extra or {}) do p[k] = v end
	return assert(Lg().Append(L, { author = author, ts = ts, season = season, type = "ITEM_AWARDED", payload = p }))
end

-- Season S1 (closed, one night) and S2 (open, two nights); the pack is Molten Core (40).
local function bound()
	local L = Lg().New()
	local A, B = full("Aurel"), full("Bryn")
	assert(Sn().Open(L, { author = A, ts = 1, season = "S1", label = "Season 1", instances = { { id = 409, size = 40 } } }))
	for i, p in ipairs(POOL) do
		assert(R().Join(L, { author = B, ts = 2 + i, season = "S1", member = full(p[1]), faction = p[3], ms1 = p[2] }))
	end
	assert(Nt().Open(L, { author = A, ts = 20, season = "S1", date = "2026-09-30", instanceID = 409, difficulty = "normal" }))
	award(L, A, 21, "S1", "Dara", 2)
	assert(Nt().Close(L, { author = A, ts = 30, season = "S1" }))
	assert(Sn().Close(L, { author = A, ts = 31, season = "S1" }))

	assert(Sn().Open(L, { author = A, ts = 100, season = "S2", label = "Season 2", instances = { { id = 409, size = 40 } } }))
	for i, p in ipairs(POOL) do
		assert(R().Join(L, { author = B, ts = 101 + i, season = "S2", member = full(p[1]), faction = p[3], ms1 = p[2] }))
	end
	assert(Nt().Open(L, { author = A, ts = 200, season = "S2", date = "2026-10-14", instanceID = 409, difficulty = "normal" }))
	award(L, A, 201, "S2", "Bryn", 1)
	award(L, A, 202, "S2", "Corin", 2)
	award(L, A, 203, "S2", "Corin", 1)       -- the same member twice in a night: they add up
	award(L, A, 204, "S2", "Fenn", 2)        -- the other faction
	assert(Nt().Close(L, { author = A, ts = 210, season = "S2" }))
	assert(Nt().Open(L, { author = A, ts = 300, season = "S2", date = "2026-10-21", instanceID = 409, difficulty = "normal" }))
	award(L, A, 301, "S2", "Aurel", 1)
	local voided = award(L, A, 302, "S2", "Edda", 2)
	assert(Lg().Append(L, { author = A, ts = 303, season = "S2", type = "AWARD_VOIDED", payload = { ref = voided.id, reason = "MISTAKE" } }))
	award(L, A, 304, "S2", "Testchar", 1)
	assert(Lg().Append(L, { author = A, ts = 305, season = "S2", type = "CREDITS_ADJUSTED",
		payload = { member = full("Dara"), delta = 1, reason = "CORRECTION" } }))
	NC():Bind(L)
	Mock.Advance(3)
	RC().faction = "Horde"
	return L
end

local function row(data, name)
	for _, r in ipairs(data.rows) do if r.member == full(name) then return r end end
end

describe("the credit table (Domain/CreditTable.lua)", function()
	before_boot(guild)

	it("the totals are the ledger's and the night columns add up to them", function()
		local L = bound()
		local data = assert(CT().Build(L, "S2", { faction = "Horde" }))
		local credits = Lg().Credits(L, "S2")
		eq(#data.rows, 6, "the Horde's playing mains only")
		for _, r in ipairs(data.rows) do
			eq(r.total, credits[r.member], r.member .. " total")
			local sum = 0
			for _, v in pairs(r.perNight) do sum = sum + v end
			eq(Lg().Round(r.base + sum), r.total, r.member .. " base + nights")
		end
		eq(#data.nights, 2)
		local n1, n2 = data.nights[1].id, data.nights[2].id
		local corin = row(data, "Corin")
		eq(corin.perNight[n1], 3, "two awards of the same night add up")
		isNil(corin.perNight[n2])
		eq(row(data, "Aurel").perNight[n2], 1)
		eq(row(data, "Testchar").perNight[n2], 1)
		eq(row(data, "Dara").perNight[n2], nil)
		eq(row(data, "Dara").total, 1, "an adjustment is in the total only")
		eq(row(data, "Dara").base, 1)
	end)

	it("a voided award leaves no trace and the other faction is not in the table", function()
		local L = bound()
		local data = CT().Build(L, "S2", { faction = "Horde" })
		eq(row(data, "Edda").total, 0)
		isNil(row(data, "Edda").perNight[data.nights[2].id])
		isNil(row(data, "Fenn"))
		local all = CT().Build(L, "S2")
		eq(#all.rows, 7)
		eq(row(all, "Fenn").perNight[all.nights[1].id], 2)
	end)

	it("the queue is the lowest total first, then the name", function()
		local L = bound()
		local data = CT().Build(L, "S2", { faction = "Horde" })
		local order = {}
		for _, r in ipairs(data.rows) do order[#order + 1] = r.member:gsub("%-.*", "") .. ":" .. r.total .. ":" .. r.rank end
		eq(table.concat(order, " "), "Edda:0:1 Aurel:1:2 Bryn:1:3 Dara:1:4 Testchar:1:5 Corin:3:6")
	end)

	it("an award belongs to the night that was open, and a night in the payload wins", function()
		local L = bound()
		local nights = Nt().List(L, "S2")
		local late = award(L, full("Aurel"), 400, "S2", "Edda", 1)             -- after both nights closed? the 2nd is open
		eq(CT().PerNight(L, "S2", nights)[full("Edda")][nights[2].id], 1)
		award(L, full("Aurel"), 401, "S2", "Edda", 2, { night = nights[1].id })
		local per = CT().PerNight(L, "S2", nights)[full("Edda")]
		eq(per[nights[1].id], 2)
		eq(per[nights[2].id], 1)
		truthy(late)
	end)

	it("a season with no night has no columns and a closed season keeps its own table", function()
		local L = Lg().New()
		assert(Sn().Open(L, { author = full("Aurel"), ts = 1, season = "S9", instances = { { id = 409, size = 40 } } }))
		assert(R().Join(L, { author = full("Aurel"), ts = 2, season = "S9", member = full("Aurel"), faction = "Horde", ms1 = 73 }))
		local data = CT().Build(L, "S9", { faction = "Horde" })
		eq(#data.nights, 0)
		eq(data.rows[1].total, 0)
		local none, why = CT().Build(L, "S404")
		isNil(none)
		eq(why, "SEASON_UNKNOWN")
		local b = bound()
		eq(row(CT().Build(b, "S1", { faction = "Horde" }), "Dara").total, 2, "Season 1 keeps Dara's 2")
		eq(CT().Seasons(b)[1].id, "S2", "newest first")
	end)
end)

describe("the Credits tab", function()
	before_boot(guild)

	local function open()
		Mock.Slash("/fdcp")
		FDCP.MainWindow:SelectTab("credits")
		CW():Refresh()
		return CW().root
	end

	local function cells(r, i)
		local out = {}
		for _, row in ipairs(r) do out[#out + 1] = row.cells[i]:GetText() end
		return out
	end

	it("one accordion per season, the newest open, a column per night with +N, the total and the queue", function()
		bound()
		local root = open()
		eq(CW().root.openId, "S2")
		truthy(root.cards.S2:IsShown()); truthy(root.cards.S1:IsShown())
		local t = root.cards.S2.table
		truthy(t:IsShown())
		falsy(root.cards.S1.table and root.cards.S1.table:IsShown())
		eq(#t.columns, 6, "queue, player, spec, two nights, total")
		contains(t.heads[4].label:GetText(), "14/10")
		contains(t.heads[4].label:GetText(), "MOLTEN CORE")
		local rows = t:VisibleRows()
		eq(#rows, 6)
		eq(table.concat(cells(rows, 1), ","), "1,2,3,4,5,6")
		eq(rows[1].cells[2]:GetText(), "Edda")
		eq(rows[1].cells[3]:GetText(), "Priest · Shadow")
		eq(rows[6].cells[2]:GetText(), "Corin")
		eq(rows[6].cells[4]:GetText(), "+3")
		eq(rows[6].cells[5]:GetText(), "·")
		eq(rows[6].cells[6]:GetText(), "3")
		eq(rows[2].cells[5]:GetText(), "+1", "Aurel, second night")
		contains(root.eyebrow:GetText(), "SEASON 2")
		contains(root.cards.S2.sub:GetText(), "2 nights")
		eq(root.cards.S2.count:GetText(), "6 in the roster")
	end)

	it("the totals on screen are the ledger's", function()
		local L = bound()
		local credits = Lg().Credits(L, "S2")
		local t = open().cards.S2.table
		for _, r in ipairs(t:VisibleRows()) do
			eq(tonumber(r.cells[6]:GetText()), credits[r.data.member], r.data.member)
		end
	end)

	it("a click on a season opens it and closes the other", function()
		bound()
		local root = open()
		root.cards.S1.head:Click()
		eq(CW().root.openId, "S1")
		truthy(root.cards.S1.table:IsShown())
		falsy(root.cards.S2.table:IsShown())
		eq(root.cards.S1.table:VisibleRows()[6].cells[5]:GetText(), "2", "Dara, last of the queue")
		contains(root.eyebrow:GetText(), "CLOSED")
	end)

	it("sorts by a header and back", function()
		bound()
		local t = open().cards.S2.table
		t.heads[2]:Click()
		eq(t:VisibleRows()[1].cells[2]:GetText(), "Aurel")
		t.heads[2]:Click()
		eq(t:VisibleRows()[1].cells[2]:GetText(), "Testchar")
		t.heads[6]:Click()
		eq(t:VisibleRows()[1].cells[6]:GetText(), "0")
		t.heads[6]:Click()
		eq(t:VisibleRows()[1].cells[6]:GetText(), "3")
	end)

	it("filters by role and by class, and the queue position stays", function()
		bound()
		local root = open()
		CW():SetRole("HEALER")
		local rows = root.cards.S2.table:VisibleRows()
		eq(table.concat(cells(rows, 2), ","), "Bryn,Corin")
		eq(table.concat(cells(rows, 1), ","), "3,6", "the position is the one of the whole queue")
		CW():SetRole(nil)
		CW():SetClass("MAGE")
		eq(table.concat(cells(root.cards.S2.table:VisibleRows(), 2), ","), "Dara,Testchar")
		CW():CycleClass()
		eq(CW().class, "WARLOCK", "the next class after the mage")
		CW():CycleClass(); CW():CycleClass()
		isNil(CW().class, "after the last class it is all classes again")
		CW():SetClass("DRUID"); CW():SetRole("TANK")
		eq(#root.cards.S2.table:VisibleRows(), 0)
		truthy(root.cards.S2.table.empty:IsShown())
	end)

	it("the faction switch shows the other queue", function()
		bound()
		local root = open()
		RC():SetFaction("Alliance")
		local rows = root.cards.S2.table:VisibleRows()
		eq(#rows, 1)
		eq(rows[1].cells[2]:GetText(), "Fenn")
		eq(rows[1].cells[4]:GetText(), "+2")
	end)

	it("the player's own row is highlighted", function()
		bound()
		local t = open().cards.S2.table
		local mine, others = 0, 0
		for _, r in ipairs(t:VisibleRows()) do
			if r.mine:IsShown() then
				mine = mine + 1
				eq(r.cells[2]:GetText(), "Testchar")
			else
				others = others + 1
			end
		end
		eq(mine, 1); eq(others, 5)
	end)

	it("it follows a new night and shows the tab empty without a season", function()
		local L = bound()
		local root = open()
		assert(Nt().Close(L, { author = full("Aurel"), ts = 310, season = "S2" }))
		assert(Nt().Open(L, { author = full("Aurel"), ts = 320, season = "S2", date = "2026-10-28", instanceID = 409, difficulty = "normal" }))
		FDCP.Bus:Emit("NIGHT_OPENED")
		eq(#root.cards.S2.table.columns, 7)
		NC():Bind(Lg().New())
		CW():Refresh()
		eq(root.empty:GetText(), FDCP.L["ROSTER_NO_SEASON"])
	end)

	it("the numbers are written the same in both languages' keys", function()
		eq(CW().Plus(2), "+2"); eq(CW().Plus(0.5), "+0.5"); eq(CW().Num(10), "10"); eq(CW().ShortDate("2026-10-14"), "14/10")
		for _, k in ipairs({ "CREDITS_COL_RANK", "CREDITS_HINT", "CREDITS_SEASON_SUB", "CREDITS_EYEBROW_OPEN" }) do
			truthy(FDCP.Locale.Text("itIT", k) ~= k, k)
			truthy(FDCP.Locale.Text("enUS", k) ~= k, k)
		end
	end)
end)
