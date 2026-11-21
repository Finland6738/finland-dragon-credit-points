-- LootSource: the loot window of a corpse, read by the master looter (docs/ANALISI.md §1, §4, M4-2). Lua 5.1.
-- Everything goes through Core/Compat.lua (Compat.Loot: IsMasterLooter, Threshold, Slots = GetNumLootItems, GetLootSlotLink,
-- GetLootSlotInfo, LootSlotHasItem, GetLootSourceInfo) and Adapters/ItemCache.lua; the names and the events LOOT_OPENED and
-- LOOT_CLOSED were checked against the Forever API dump (C_Loot and the global loot functions) [verify S2a in game: the
-- shape of GetLootSlotInfo and GetLootSourceInfo].
--
-- LootSource.Read()            -> collection, or nil + code ("NOT_MASTER_LOOTER" | "NO_ITEMS"). Synchronous: what the window
--                                says now, with what the client already knows of each item.
-- LootSource.Collect(onReady)  Read(), then waits for the item data that was not cached (ItemCache); onReady(collection)
--                                runs once nothing is pending (at once when everything was cached; after ItemCache.TIMEOUT
--                                at the latest). Returns the collection, or nil + code like Read.
-- LootSource.Preview(collection, cost, ctx)  fills every item with the classifier's category and the base cost
--                                (Domain/Pricing.lua), for the master looter to confirm or correct before the roll opens.
-- LootSource.ToInput(collection, ts, by)     the LOOT_OPENED input of Domain/SessionFSM.lua (the FSM prices and filters
--                                again by the group's threshold; the category is locked there once the roll opens).
--
-- collection = { threshold, encounter?, bosses = { npcID, ... }, items = { item, ... }, skipped = { itemID, ... },
--                pending = n }
-- item       = { slot, itemID, link, name?, quality?, classID?, subclassID?, equipLoc?, boe?, count, icon?, locked?,
--                npcIDs = { ... }, loaded }
-- Items below the group's threshold are left out (listed in `skipped`); currencies and money are never items. A
-- quest-item flag is not read here (spike S5): the classifier recognises the Quest class and the season's token list.
-- Bus events: "LOOT_COLLECTED"(collection) when a window was read and its data is complete, "LOOT_WINDOW_CLOSED".
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Source = {}
ns.LootSource, ns.modules.LootSource = Source, Source

local type, ipairs, tonumber = type, ipairs, tonumber

Source.ENCOUNTER_WINDOW = 1800   -- seconds a boss kill stays "the boss of this corpse"
Source.lastKill = nil            -- { encounterID, at } from ENCOUNTER_ENDED

local function C() return ns.Compat end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

-- The creature id of a GUID "Creature-0-<server>-<instance>-<zone>-<npcID>-<spawn>" (also Vehicle-), or nil.
function Source.NpcID(guid)
	if type(guid) ~= "string" then return nil end
	local kind, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(npc)
end

local function sourceNpcs(slot)
	local out, seen = {}, {}
	for _, s in ipairs(slot.sources or {}) do
		local id = Source.NpcID(s.guid)
		if id and not seen[id] then seen[id] = true; out[#out + 1] = id end
	end
	return out
end

-- The data of one slot, merged with what the cache knows (nil: not an item).
local function buildItem(slot, cache)
	local id = cache.IdFromLink(slot.link)
	if not id or slot.isCurrency or slot.hasItem == false then return nil end
	local item = { slot = slot.slot, itemID = id, link = slot.link, name = slot.name, quality = slot.quality,
		count = slot.quantity or 1, icon = slot.icon, locked = slot.locked or nil, npcIDs = sourceNpcs(slot), loaded = false }
	local known = cache.Lookup(id)
	if known then
		item.name, item.link = known.name or item.name, known.link or item.link
		item.quality = known.quality or item.quality
		item.classID, item.subclassID, item.equipLoc, item.boe = known.classID, known.subclassID, known.equipLoc, known.boe
		item.icon = known.icon or item.icon
		item.loaded = known.loaded
	end
	return item
end

function Source.Read()
	local Loot = C().Loot
	if not Loot.IsMasterLooter() then return nil, "NOT_MASTER_LOOTER" end
	local cache, threshold = ns.ItemCache, Loot.Threshold()
	local items, skipped, bosses, seen, pending = {}, {}, {}, {}, 0
	for _, slot in ipairs(Loot.Slots()) do
		local item = buildItem(slot, cache)
		if item then
			if type(threshold) == "number" and type(item.quality) == "number" and item.quality < threshold then
				skipped[#skipped + 1] = item.itemID
			else
				items[#items + 1] = item
				if not item.loaded then pending = pending + 1 end
				for _, npc in ipairs(item.npcIDs) do
					if not seen[npc] then seen[npc] = true; bosses[#bosses + 1] = npc end
				end
			end
		end
	end
	if #items == 0 and #skipped == 0 then return nil, "NO_ITEMS" end
	local kill = Source.lastKill
	local encounter = kill and C().Now() - kill.at <= Source.ENCOUNTER_WINDOW and kill.encounterID or nil
	return { threshold = threshold, encounter = encounter, bosses = bosses, items = items, skipped = skipped, pending = pending }
end

-- A cache answer for one waiting item: fills it in place; `done` runs once the last one is in.
local function resolve(collection, item, entry)
	if item.loaded then return end
	if entry then
		item.name, item.link = entry.name or item.name, entry.link or item.link
		item.quality = entry.quality or item.quality
		item.classID, item.subclassID, item.equipLoc = entry.classID, entry.subclassID, entry.equipLoc
		item.boe, item.icon, item.loaded = entry.boe, entry.icon or item.icon, true
	end
	item.waiting = nil
	collection.pending = collection.pending - 1
end

function Source.Collect(onReady)
	local collection, code = Source.Read()
	if not collection then return nil, code end
	local cache, finished = ns.ItemCache, false
	local function done()
		if finished or collection.pending > 0 then return end
		finished = true
		emit("LOOT_COLLECTED", collection)
		if onReady then onReady(collection) end
	end
	for _, item in ipairs(collection.items) do
		if not item.loaded then
			item.waiting = true
			local entry, state = cache.Get(item.itemID, function(late)
				resolve(collection, item, late)
				done()
			end)
			if entry then
				resolve(collection, item, entry)
			elseif state == "UNAVAILABLE" then   -- the API is missing: the instant data is all there will be
				item.waiting = nil
				collection.pending = collection.pending - 1
			end
		end
	end
	done()
	return collection
end

function Source.Preview(collection, cost, ctx)
	local Pricing = ns.Pricing
	ctx = ctx or {}
	if ctx.lootThreshold == nil then ctx.lootThreshold = collection.threshold end
	for _, item in ipairs(collection.items) do
		local base = Pricing.Base(item, cost, ctx)
		item.category, item.rule, item.base, item.council = base.category, base.rule, base.base, base.council == true or nil
	end
	return collection
end

function Source.ToInput(collection, ts, by)
	local items = {}
	for _, item in ipairs(collection.items) do
		items[#items + 1] = { itemID = item.itemID, slot = item.slot, quality = item.quality, classID = item.classID,
			subclassID = item.subclassID, equipLoc = item.equipLoc, boe = item.boe }
	end
	return { type = "LOOT_OPENED", ts = ts, by = by, items = items, encounter = collection.encounter }
end

function Source.OnEvent(_, event)
	if event == "LOOT_OPENED" then
		Source.Collect()
	elseif event == "LOOT_CLOSED" then
		emit("LOOT_WINDOW_CLOSED")
	end
end

if ns.Bus then
	ns.Bus:On("ENCOUNTER_ENDED", function(_, info)
		if info and info.success then Source.lastKill = { encounterID = info.encounterID, at = C().Now() } end
	end, Source)
end

if ns.addon and CreateFrame then
	ns.addon.LootSource = Source   -- also reachable from tests
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("LOOT_OPENED")
	frame:RegisterEvent("LOOT_CLOSED")
	frame:SetScript("OnEvent", Source.OnEvent)
end
