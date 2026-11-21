-- ItemCache: item data that the client may not have loaded yet (docs/ANALISI.md §1, §11, M4-2). Lua 5.1.
-- Everything goes through Core/Compat.lua (Compat.Item.Info / Instant / Request: C_Item.GetItemInfo, GetItemInfoInstant,
-- RequestLoadItemDataByID); the names and the events ITEM_DATA_LOAD_RESULT(itemID, success) and GET_ITEM_INFO_RECEIVED
-- were checked against the Forever API dump (C_Item). Both events are listened to: whichever comes first resolves the wait.
--
-- ItemCache.Lookup(item)        what the client knows now, or nil: { itemID, name, link, quality, level, classID,
--                               subclassID, equipLoc, bindType, boe, icon, loaded }. `loaded` is true when the full
--                               C_Item.GetItemInfo answered; without it only the instant fields are there (classID,
--                               subclassID, equipLoc, icon) and name / quality / bindType are nil.
-- ItemCache.Get(item, cb)       entry when the item is loaded (cb is not called); else asks the client and returns nil,
--                               "PENDING": cb(entry, nil) runs when the data arrives, cb(nil, "FAILED" | "TIMEOUT") when
--                               it never does. nil, "UNAVAILABLE" (cb not called) when the API is missing or the item
--                               has no id. One request per item however many callers wait.
-- ItemCache.IdFromLink(x)       the item id of a link, a number or "item:123", or nil.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Cache = {}
ns.ItemCache, ns.modules.ItemCache = Cache, Cache

local type, tonumber, ipairs, pairs = type, tonumber, ipairs, pairs

Cache.TIMEOUT = 10   -- seconds a request may wait before the callbacks hear "TIMEOUT"
Cache.BIND_ON_EQUIP = 2   -- the bindType of "bind on equip" (the same numbers as LE_ITEM_BIND_ON_EQUIP)
Cache.pending = {}        -- [itemID] = { callbacks = { fn, ... }, token = n }

local nextToken = 0

local function C() return ns.Compat end

function Cache.IdFromLink(item)
	if type(item) == "number" then return item > 0 and item == item and item or nil end
	if type(item) ~= "string" then return nil end
	return tonumber(item:match("item:(%d+)"))
end

function Cache.Lookup(item)
	local id = Cache.IdFromLink(item)
	if not id then return nil end
	local Item = C().Item
	local instant, info = Item.Instant(id), Item.Info(id)
	if not instant and not info then return nil end
	local out = { itemID = id, loaded = info ~= nil }
	if instant then
		out.classID, out.subclassID, out.equipLoc, out.icon = instant.classID, instant.subClassID, instant.equipLoc, instant.icon
	end
	if info then
		out.name, out.link, out.quality, out.level, out.bindType = info.name, info.link, info.quality, info.level, info.bindType
		out.classID, out.subclassID = info.classID or out.classID, info.subclassID or out.subclassID
		out.equipLoc, out.icon = info.equipLoc or out.equipLoc, info.icon or out.icon
	end
	out.boe = out.bindType == Cache.BIND_ON_EQUIP or nil
	return out
end

local function finish(id, entry, code)
	local wait = Cache.pending[id]
	if not wait then return end
	Cache.pending[id] = nil
	for _, fn in ipairs(wait.callbacks) do fn(entry, code) end
end

function Cache.Get(item, cb)
	local id = Cache.IdFromLink(item)
	if not id then return nil, "UNAVAILABLE" end
	local entry = Cache.Lookup(id)
	if entry and entry.loaded then return entry end
	local wait = Cache.pending[id]
	if wait then
		if cb then wait.callbacks[#wait.callbacks + 1] = cb end
		return nil, "PENDING"
	end
	local state = C().Item.Request(id)
	if state ~= C().AVAILABLE then return nil, "UNAVAILABLE" end
	nextToken = nextToken + 1
	wait = { callbacks = { cb }, token = nextToken }
	Cache.pending[id] = wait
	local token = nextToken
	C().After(Cache.TIMEOUT, function()
		local w = Cache.pending[id]
		if w and w.token == token then finish(id, nil, "TIMEOUT") end
	end)
	return nil, "PENDING"
end

-- ITEM_DATA_LOAD_RESULT(itemID, success) / GET_ITEM_INFO_RECEIVED(itemID, success).
function Cache.OnEvent(_, _, itemID, success)
	local id = C().Readable(itemID)
	if type(id) ~= "number" or not Cache.pending[id] then return end
	if C().Readable(success) == false then return finish(id, nil, "FAILED") end
	local entry = Cache.Lookup(id)
	if entry and entry.loaded then finish(id, entry) else finish(id, nil, "FAILED") end
end

if ns.addon and CreateFrame then
	ns.addon.ItemCache = Cache   -- also reachable from tests
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
	frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	frame:SetScript("OnEvent", Cache.OnEvent)
end
