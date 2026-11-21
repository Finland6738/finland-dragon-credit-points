-- The loot window and the item cache (M4-2): Adapters/LootSource.lua reads the corpse as the master looter, Adapters/ItemCache.lua
-- waits for item data the client has not loaded. The mock corpse and the mock item cache drive them; the result feeds the
-- LOOT_OPENED input of Domain/SessionFSM.lua.
local function LS() return FDCP.LootSource end
local function IC() return FDCP.ItemCache end
local function F() return FDCP.SessionFSM end

local ML = "Dara"
local function link(id) return "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[Item " .. id .. "]|h|r" end
local BOSS = "Creature-0-3-2000-1-11502-0000A1B2C3"
local ADD = "Creature-0-3-2000-1-11503-0000A1B2C4"

local function addItems()
	Mock.items.Add{ id = 19001, link = link(19001), name = "Shoulders", quality = 4, equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 4 }
	Mock.items.Add{ id = 19002, link = link(19002), name = "Sword", quality = 4, equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7 }
	Mock.items.Add{ id = 19004, link = link(19004), name = "Green Ring", quality = 2, equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0 }
	Mock.items.Add{ id = 19006, link = link(19006), name = "Boe Cloak", quality = 4, equipLoc = "INVTYPE_CLOAK", classID = 4, subclassID = 1,
		bindType = 2 }
end

local function corpse(extra)
	local cfg = { method = "master", masterLooter = true, threshold = 3, slots = {
		{ link = link(19001), name = "Shoulders", quality = 4, sources = { BOSS, 1 } },
		{ link = link(19002), name = "Sword", quality = 4, sources = { BOSS, 1 } },
		{ link = link(19004), name = "Green Ring", quality = 2, sources = { ADD, 1 } },
	} }
	for k, v in pairs(extra or {}) do cfg[k] = v end
	Mock.loot.Set(cfg)
end

describe("the loot source", function()
	before_boot(function(M) addItems() end)

	it("reads the slots at or above the threshold with their data and sources", function()
		corpse()
		local c = LS().Read()
		eq(#c.items, 2)
		eq(c.threshold, 3)
		eq(c.items[1].itemID, 19001)
		eq(c.items[1].slot, 1)
		eq(c.items[1].equipLoc, "INVTYPE_SHOULDER")
		eq(c.items[2].classID, 2)
		deepEq(c.skipped, { 19004 })
		deepEq(c.bosses, { 11502 })
		eq(c.pending, 0)
		truthy(c.items[1].loaded)
	end)

	it("does nothing when the player is not the master looter, and says why", function()
		corpse({ masterLooter = false })
		local c, code = LS().Read()
		isNil(c)
		eq(code, "NOT_MASTER_LOOTER")
		local seen = 0
		FDCP.Bus:On("LOOT_COLLECTED", function() seen = seen + 1 end)
		Mock.loot.Open()
		eq(seen, 0)
	end)

	it("reports an empty corpse", function()
		corpse({ slots = {} })
		local c, code = LS().Read()
		isNil(c)
		eq(code, "NO_ITEMS")
	end)

	it("leaves out a slot without an item link (money, currencies)", function()
		corpse({ slots = { { name = "12 Gold", quality = 1 }, { link = link(19001), name = "Shoulders", quality = 4 } } })
		local c = LS().Read()
		eq(#c.items, 1)
		eq(c.items[1].itemID, 19001)
	end)

	it("announces the collection when LOOT_OPENED fires", function()
		corpse()
		local got
		FDCP.Bus:On("LOOT_COLLECTED", function(_, c) got = c end)
		Mock.loot.Open()
		eq(#got.items, 2)
		local closed = 0
		FDCP.Bus:On("LOOT_WINDOW_CLOSED", function() closed = closed + 1 end)
		Mock.loot.Close()
		eq(closed, 1)
	end)

	it("names the boss of the corpse from the last kill and forgets an old one", function()
		corpse()
		Mock.encounter.Start(1118, "Boss")
		Mock.encounter.End(1118, "Boss", true)
		eq(LS().Read().encounter, 1118)
		Mock.Advance(LS().ENCOUNTER_WINDOW + 60)
		isNil(LS().Read().encounter)
	end)

	it("ignores the kill of a wipe", function()
		corpse()
		Mock.encounter.Start(1118, "Boss")
		Mock.encounter.End(1118, "Boss", false)
		isNil(LS().Read().encounter)
	end)

	it("parses the creature id of a GUID", function()
		eq(LS().NpcID(BOSS), 11502)
		isNil(LS().NpcID("Player-3-0A1B2C3D"))
		isNil(LS().NpcID(nil))
	end)

	it("proposes a category and a cost for the master looter to confirm", function()
		corpse()
		local c = LS().Preview(LS().Read(), FDCP.Pricing.DefaultCost())
		eq(c.items[1].category, "armor")
		eq(c.items[2].category, "weapon")
		truthy(c.items[1].base ~= nil or c.items[1].council)
	end)

	it("feeds the session state machine", function()
		corpse()
		local s = assert(F().New{ id = "N1", season = "S1", ml = ML, ts = 1 })
		local c = LS().Read()
		local ok, code = F().Step(s, LS().ToInput(c, 2, ML), {})
		truthy(ok, tostring(code))
		eq(s.state, "COLLECTING")
		eq(#s.items, 2)
		eq(s.items[2].itemID, 19002)
		eq(s.items[2].category, "weapon")
	end)
end)

describe("the item cache", function()
	before_boot(function(M)
		addItems()
		Mock.items.Add{ id = 19010, link = link(19010), name = "Far Away", quality = 4, equipLoc = "INVTYPE_HEAD", classID = 4,
			subclassID = 4, cached = false }
	end)

	it("answers at once for a cached item and never calls back", function()
		local called = false
		local e = IC().Get(link(19001), function() called = true end)
		eq(e.name, "Shoulders")
		truthy(e.loaded)
		Mock.Advance(1)
		eq(called, false)
	end)

	it("knows the id of a link, a number and a bare item string", function()
		eq(IC().IdFromLink(link(19001)), 19001)
		eq(IC().IdFromLink(19001), 19001)
		eq(IC().IdFromLink("item:5"), 5)
		isNil(IC().IdFromLink("nonsense"))
		isNil(IC().IdFromLink(-3))
	end)

	it("asks once and resolves every waiting caller when the data arrives", function()
		local got = {}
		local e, state = IC().Get(19010, function(entry, code) got[#got + 1] = { entry, code } end)
		isNil(e)
		eq(state, "PENDING")
		IC().Get(19010, function(entry, code) got[#got + 1] = { entry, code } end)
		eq(#Mock.items.requested, 1)
		eq(#got, 0)
		Mock.Advance(1)
		eq(#got, 2)
		eq(got[1][1].name, "Far Away")
		isNil(got[1][2])
		isNil(IC().pending[19010])
	end)

	it("serves the instant fields while the full data is missing", function()
		local e = IC().Lookup(19010)
		eq(e.equipLoc, "INVTYPE_HEAD")
		eq(e.loaded, false)
		isNil(e.name)
	end)

	it("gives up after the timeout", function()
		Mock.items.byId[19010].noLoad = true
		local code
		C_Item.RequestLoadItemDataByID = function(id) Mock.items.requested[#Mock.items.requested + 1] = id end
		IC().Get(19010, function(_, c) code = c end)
		Mock.Advance(IC().TIMEOUT - 1)
		isNil(code)
		Mock.Advance(2)
		eq(code, "TIMEOUT")
	end)

	it("reports a failed load", function()
		C_Item.RequestLoadItemDataByID = function(id) Mock.items.requested[#Mock.items.requested + 1] = id end
		local code
		IC().Get(19010, function(_, c) code = c end)
		Mock.Fire("ITEM_DATA_LOAD_RESULT", 19010, false)
		eq(code, "FAILED")
	end)

	it("ignores a secret or unrelated event", function()
		IC().OnEvent(nil, "ITEM_DATA_LOAD_RESULT", Mock.SECRET, true)
		IC().OnEvent(nil, "ITEM_DATA_LOAD_RESULT", 999, true)
		eq(next(IC().pending), nil)
	end)

	it("says UNAVAILABLE when the client has no request API", function()
		C_Item.RequestLoadItemDataByID = nil
		local e, state = IC().Get(19010, function() end)
		isNil(e)
		eq(state, "UNAVAILABLE")
	end)
end)

describe("the collection with a cache miss", function()
	before_boot(function(M)
		addItems()
		Mock.items.Add{ id = 19010, link = link(19010), name = "Far Away", quality = 4, equipLoc = "INVTYPE_HEAD", classID = 4,
			subclassID = 4, cached = false }
	end)

	it("waits for the missing item and then completes the list", function()
		corpse({ slots = { { link = link(19001), name = "Shoulders", quality = 4 }, { link = link(19010), name = "Far Away", quality = 4 } } })
		local ready, events = nil, 0
		FDCP.Bus:On("LOOT_COLLECTED", function() events = events + 1 end)
		local c = LS().Collect(function(col) ready = col end)
		eq(c.pending, 1)
		isNil(ready)
		eq(events, 0)
		Mock.Advance(1)
		eq(ready, c)
		eq(events, 1)
		eq(c.pending, 0)
		eq(c.items[2].name, "Far Away")
		truthy(c.items[2].loaded)
	end)

	it("completes after the timeout with what the slot said when the data never comes", function()
		C_Item.RequestLoadItemDataByID = function() end
		corpse({ slots = { { link = link(19010), name = "Far Away", quality = 4 } } })
		local ready
		LS().Collect(function(col) ready = col end)
		isNil(ready)
		Mock.Advance(IC().TIMEOUT + 1)
		truthy(ready)
		eq(ready.items[1].equipLoc, "INVTYPE_HEAD")
		eq(ready.items[1].loaded, false)
		eq(ready.pending, 0)
	end)

	it("calls back at once when everything is cached", function()
		corpse()
		local ready
		LS().Collect(function(col) ready = col end)
		truthy(ready)
	end)

	it("marks a bind-on-equip item", function()
		corpse({ slots = { { link = link(19006), name = "Boe Cloak", quality = 4 } } })
		local c = LS().Read()
		eq(c.items[1].boe, true)
		eq(LS().ToInput(c, 1, ML).items[1].boe, true)
	end)
end)
