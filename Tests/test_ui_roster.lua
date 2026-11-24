-- The Roster tab (M3-7): UI/Widgets/DataTable.lua (sort, pool, wheel), App/RosterController.lua and UI/Windows/Roster.lua
-- (the three role columns, the guild's faction in the header, the officers' status buttons and inbox), UI/Windows/Nights.lua (open and
-- close a night, the lineup, the proposed bench, the attendance for officers only). docs/ANALISI.md §6, §9.3.
local function Lg() return FDCP.Ledger end
local function Sn() return FDCP.Season end
local function R() return FDCP.Roster end
local function N() return FDCP.Nights end
local function NC() return FDCP.NightController end
local function RC() return FDCP.RosterController end
local function RW() return FDCP.RosterWindow end
local function NW() return FDCP.NightsWindow end

local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }
local RAID_INSTANCE = { name = "Molten Core", type = "raid", difficultyID = 14, difficultyName = "Normal", maxPlayers = 40,
	instanceID = 409 }
local REALM = "TestRealm"
local function full(n) return n .. "-" .. REALM end

local function guild(myRank)
	return function(M)
		M.guild.Set({ name = "Keepers", ranks = RANKS, myRank = myRank or 1, members = {
			{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
		} })
	end
end

-- name, spec, status, faction
local POOL = {
	{ "Aurel", 73, "ACTIVE", "Horde" },    -- Protection Warrior (tank)
	{ "Bryn", 65, "ACTIVE", "Horde" },     -- Holy Paladin (healer)
	{ "Corin", 105, "TRIAL", "Horde" },    -- Restoration Druid (healer, trial)
	{ "Dara", 63, "ACTIVE", "Horde" },     -- Fire Mage (dps)
	{ "Edda", 258, "ACTIVE", "Horde" },    -- Shadow Priest (dps)
	{ "Fenn", 70, "ACTIVE", "Alliance" },  -- Retribution Paladin (dps)
}

-- The ledger of the guild: a season with the pack of Molten Core (40) and the pool above; the player is "Testchar" (the
-- mock's character), bound to the controller.
local function bound()
	local L = Lg().New()
	assert(Sn().Open(L, { author = full("Aurel"), ts = 1, season = "S1", instances = { { id = 409, size = 40 } } }))
	for i, p in ipairs(POOL) do
		assert(R().Join(L, { author = full("Bryn"), ts = 1 + i, season = "S1", member = full(p[1]), faction = p[4], ms1 = p[2],
			status = p[3] }))
	end
	NC():Bind(L)
	Mock.encounter.Set({ instance = RAID_INSTANCE })
	Mock.Advance(3)
	RC().faction = "Horde"
	return L
end

local function open()
	Mock.Slash("/fdcp")
	RW():Refresh()
	return RW().pool
end

local function texts(rows, field)
	local out = {}
	for _, r in ipairs(rows) do
		if r:IsShown() then out[#out + 1] = (field and r[field] or r.name):GetText() end
	end
	return out
end

local function names(list)
	local out = {}
	for i, r in ipairs(list) do out[i] = r end
	return table.concat(out, ",")
end

describe("the data table", function()
	before_boot(guild(1))

	local function make(count, rowH)
		local f = CreateFrame("Frame", nil, UIParent)
		f:SetSize(600, 200)
		local t = FDCP.Widgets.DataTable(f, {
			{ id = "name", title = "Name", flex = 1, text = function(d) return d.name end, value = function(d) return d.name end },
			{ id = "n", title = "Count", width = 80, align = "RIGHT", mono = true, text = function(d) return d.n end,
				value = function(d) return d.n end },
		}, { rowHeight = rowH or 20, pool = 20 })
		t:SetAllPoints(f)
		local data = {}
		for i = 1, count do data[i] = { name = string.char(64 + (i % 26) + 1) .. i, n = (i * 7) % 11 } end
		t:SetData(data)
		return t, data
	end

	it("shows only as many rows as fit, recycled from the pool", function()
		local t = make(30)
		local shown = t:VisibleRows()
		eq(#shown, t:Capacity())
		truthy(#shown >= 8 and #shown < 30)
		eq(#t.rows, 20)
	end)

	it("sorts by a header, descending on the second click, ties keep the order", function()
		local t = make(6)
		t.heads[2]:Click()
		local prev = -1
		for _, d in ipairs(t:GetData()) do truthy(d.n >= prev); prev = d.n end
		eq(t:GetSort(), "n")
		t.heads[2]:Click()
		local id, desc = t:GetSort()
		eq(id, "n"); eq(desc, true)
		prev = 99
		for _, d in ipairs(t:GetData()) do truthy(d.n <= prev); prev = d.n end
	end)

	it("the first row follows the sort, and the mouse wheel scrolls the list", function()
		local t, data = make(40)
		t:SortBy("name", false)
		local first = t:VisibleRows()[1].cells[1]:GetText()
		eq(first, t:GetData()[1].name)
		t.list:GetScript("OnMouseWheel")(t.list, -1)
		eq(t.offset, 3)
		eq(t:VisibleRows()[1].cells[1]:GetText(), t:GetData()[4].name)
		t:SetOffset(999)
		eq(t.offset, 40 - t:Capacity())
		t.list:GetScript("OnMouseWheel")(t.list, 1)
		eq(t.offset, 40 - t:Capacity() - 3)
	end)

	it("an empty table shows its empty text", function()
		local t = make(0)
		t:SetEmptyText("nothing")
		t:Refresh()
		truthy(t.empty:IsShown())
		eq(#t:VisibleRows(), 0)
	end)
end)

describe("the pool", function()
	before_boot(guild(1))

	it("draws the three role columns with the counts against the targets and the free slots", function()
		bound()
		local pool = open()
		eq(pool.cards.TANK.count:GetText(), "1/2")
		eq(pool.cards.HEALER.count:GetText(), "2/4")
		eq(pool.cards.DAMAGER.count:GetText(), "2/34")
		eq(pool.cards.TANK.free:GetText(), "1 free slots")
		eq(pool.cards.HEALER.free:GetText(), "2 free slots")
		eq(names(texts(pool.cards.HEALER.rows)), "Corin,Bryn", "by class, then name")
		eq(names(texts(pool.cards.DAMAGER.rows)), "Dara,Edda")
		eq(pool.cards.HEALER.bar:GetFraction(), 0.5)
		eq(pool.summary:GetText(), "5 players, 1 on trial, 0 without a declaration")
	end)

	it("marks the Trial members and shows the spec", function()
		bound()
		local pool = open()
		local rows = pool.cards.HEALER.rows
		truthy(rows[1].trial:IsShown())   -- Corin
		falsy(rows[2].trial:IsShown())
		eq(rows[1].spec:GetText(), "Restoration")
		eq(rows[2].spec:GetText(), "Holy")
	end)

	it("shows the pool of the guild's faction, without a faction switch", function()
		bound()
		local pool = open()
		isNil(pool.faction)
		eq(RC():Faction(), "Horde")
		eq(pool.eyebrow:GetText(), "THE RAIDERS OF THE SEASON · HORDE")
		eq(pool.cards.DAMAGER.count:GetText(), "2/34", "Fenn (Alliance) belongs to the other guild")
	end)

	it("an officer changes a status with the row's button; the ledger holds the change", function()
		local L = bound()
		local pool = open()
		local row = pool.cards.HEALER.rows[1]   -- Corin, on trial
		truthy(row.status:IsShown())
		row.status:Click()
		eq(R().Get(L, "S1", full("Corin")).status, "ACTIVE")
		eq(pool.message:GetText(), "Corin updated.")
		falsy(pool.cards.HEALER.rows[1].trial:IsShown())
		pool.cards.DAMAGER.rows[1].status:Click()   -- Dara to Trial
		eq(R().Get(L, "S1", full("Dara")).status, "TRIAL")
		eq(pool.summary:GetText(), "5 players, 1 on trial, 0 without a declaration")
	end)

	it("a member sees the pool but no status button and no inbox", function()
		bound()
		Mock.guild.SetMyRank(3)
		Mock.Advance(3)
		local pool = open()
		eq(pool.cards.HEALER.count:GetText(), "2/4")
		falsy(pool.cards.HEALER.rows[1].status:IsShown())
		falsy(pool.inbox:IsShown())
		local e, code = RC():SetStatus(full("Dara"), "TRIAL")
		isNil(e); eq(code, "RANK_TOO_LOW")
	end)

	it("the inbox lists the requests; approving writes the declaration, rejecting drops it", function()
		local L = bound()
		local req = assert(RC():RequestJoin({ member = full("Gale"), faction = "Horde", ms1 = 73 }))
		assert(RC():RequestAlt({ alt = full("Fox"), main = full("Aurel"), faction = "Horde" }))
		local pool = open()
		truthy(pool.inbox:IsShown())
		eq(pool.inbox.title:GetText(), "REQUESTS TO APPROVE: 2")
		eq(pool.inbox.rows[1].text:GetText(), "Gale asks to join: Warrior Protection")
		eq(pool.inbox.rows[2].text:GetText(), "Fox is an alt of Aurel")
		pool.inbox.rows[1].approve:Click()
		truthy(R().Get(L, "S1", full("Gale")))
		eq(pool.cards.TANK.count:GetText(), "2/2")
		eq(pool.cards.TANK.free:GetText(), "")
		eq(pool.inbox.title:GetText(), "REQUESTS TO APPROVE: 1")
		pool.inbox.rows[1].reject:Click()
		eq(#R().Pending(RC():Requests(), "S1"), 0)
		eq(pool.inbox.rows[1].text:GetText(), "No pending requests.")
		isNil(RC():Approve(req.id) and nil)
	end)

	it("says so when no season is open", function()
		local L = Lg().New()
		NC():Bind(L)
		Mock.Advance(3)
		local pool = open()
		eq(pool.empty:GetText(), "No season is open: the Guild Master opens one in the settings.")
		falsy(pool.cards.TANK:IsShown())
	end)

	it("shows the texts in Italian", function()
		T.boot(function(M) guild(1)(M); M.player.locale = "itIT" end)
		bound()
		local pool = open()
		eq(pool.cards.TANK.free:GetText(), "1 posti liberi")
		eq(pool.cards.TANK.title:GetText(), "Tank")
		eq(RW().root.sub.buttons.night.label:GetText(), "Serata")
		contains(pool.eyebrow:GetText(), "ORDA")
	end)

	it("has the three sub-tabs, the pool first", function()
		bound()
		open()
		eq(RW():ActiveSub(), "pool")
		truthy(RW().root.panes.pool:IsShown())
		falsy(RW().root.panes.night:IsShown())
		RW():SelectSub("night")
		truthy(RW().root.panes.night:IsShown())
		falsy(RW().root.panes.pool:IsShown())
		RW():SelectSub("addon")
		truthy(RW().root.panes.addon:IsShown())
		truthy(FDCP.AddonPanel.root)
	end)
end)

describe("the night", function()
	before_boot(guild(1))

	local function night()
		bound()
		open()
		RW():SelectSub("night")
		return NW().root
	end

	it("opens a night with the button, in the instance the officer stands in", function()
		local L = bound()
		open()
		RW():SelectSub("night")
		local root = NW().root
		eq(root.status:GetText(), "No night open.")
		truthy(root.open:IsShown()); falsy(root.close:IsShown())
		root.open:Click()
		local current = N().Current(L, "S1")
		truthy(current)
		eq(current.instanceID, 409); eq(current.difficulty, "normal")
		eq(root.message:GetText(), "Night opened.")
		eq(root.status:GetText(), "Molten Core · Normal · 40 players · 2026-01-01")
		truthy(root.close:IsShown()); falsy(root.open:IsShown())
	end)

	it("closes it, and the buttons change back", function()
		local L = bound()
		open()
		RW():SelectSub("night")
		local root = NW().root
		root.open:Click()
		root.close:Click()
		truthy(N().List(L, "S1")[1].closed)
		eq(root.message:GetText(), "Night closed.")
		eq(root.status:GetText(), "No night open.")
	end)

	it("shows the lineup in three columns and moves a player with the row button", function()
		local L = bound()
		open()
		Mock.group.Set({ raid = true, members = { { name = "Aurel", inGuild = true }, { name = "Bryn", inGuild = true } } })
		RW():SelectSub("night")
		local root = NW().root
		root.open:Click()
		eq(names(texts(root.cols.raid.rows)), "Aurel,Bryn")
		eq(root.cols.raid.title:GetText(), "IN THE RAID  2")
		root.cols.raid.rows[2].act:Click()   -- Bryn to the bench
		eq(names(texts(root.cols.raid.rows)), "Aurel")
		eq(names(texts(root.cols.bench.rows)), "Bryn")
		root.cols.bench.rows[1].act:Click()  -- back
		eq(names(texts(root.cols.raid.rows)), "Aurel,Bryn")
	end)

	it("proposes the bench from the rotation and applies it when the night is open", function()
		local L = bound()
		open()
		RW():SelectSub("night")
		local root = NW().root
		root.propose:Click()
		eq(root.message:GetText(), "Nobody needs to sit out: the pool fits the raid.")
		root.open:Click()
		falsy(root.apply:IsShown())
	end)

	it("refuses what the controller refuses and says why", function()
		local L = bound()
		open()
		Mock.encounter.Set({ instance = { name = "Elsewhere", type = "none", difficultyID = 0, difficultyName = "", instanceID = 1 } })
		RW():SelectSub("night")
		local root = NW().root
		NW().instanceId = 9999
		root.open:Click()
		eq(root.message:GetText(), "That instance is not one of the season's official raids.")
		eq(#N().List(L, "S1"), 0)
	end)

	it("the attendance is for the officers: they get the table, members get nothing", function()
		local L = bound()
		open()
		Mock.group.Set({ raid = true, members = { { name = "Aurel", inGuild = true }, { name = "Bryn", inGuild = true } } })
		RW():SelectSub("night")
		local root = NW().root
		root.open:Click()
		Mock.encounter.End(610, "Lucifron", true)
		NW():Refresh()
		truthy(root.table:IsShown()); truthy(root.attTitle:IsShown())
		eq(#root.table:GetData(), 5, "the whole pool of the faction")
		local first = root.table:VisibleRows()[1]
		eq(first.cells[1]:GetText(), "Aurel")
		eq(first.cells[4]:GetText(), "1/1")
		eq(first.cells[5]:GetText(), "100%")
		-- demoted: the table goes away, nothing of the attendance stays on screen
		Mock.guild.SetMyRank(3)
		Mock.Advance(3)
		NW():Refresh()
		falsy(root.table:IsShown()); falsy(root.attTitle:IsShown())
		falsy(root.open:IsShown()); falsy(root.close:IsShown()); falsy(root.propose:IsShown())
		falsy(root.cols.raid.rows[1].act:IsShown())
		eq(names(texts(root.cols.raid.rows)), "Aurel,Bryn", "the lineup is still visible")
	end)

	it("a member never gets the table even when they open the tab first", function()
		bound()
		Mock.guild.SetMyRank(3)
		Mock.Advance(3)
		open()
		RW():SelectSub("night")
		isNil(NW().root.table)
		falsy(NW().root.attTitle:IsShown())
	end)

	it("the attendance table sorts by a header", function()
		local L = bound()
		open()
		Mock.group.Set({ raid = true, members = { { name = "Aurel", inGuild = true }, { name = "Bryn", inGuild = true } } })
		RW():SelectSub("night")
		local root = NW().root
		root.open:Click()
		Mock.encounter.End(610, "Lucifron", true)
		NW():Refresh()
		root.table.heads[1]:Click()
		root.table.heads[1]:Click()
		eq(root.table:VisibleRows()[1].cells[1]:GetText(), "Edda")
	end)
end)
