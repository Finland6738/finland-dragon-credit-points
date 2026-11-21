-- Wishlist: the player's own list of best-in-slot items (docs/ANALISI.md §5.1 point 5, M5-3). Pure domain code on a plain
-- table `{ [itemID] = true }` (the caller keeps it in FinlandDragonCreditPointsCharDB); it never calls the game. The popup
-- reminds the player when an item on the list is up for grabs; the list never changes who wins and nobody else sees it.
--
-- Wishlist.ItemIDs(text) -> the item ids named in a text: item links or `item:123` pieces, then bare numbers.
-- Wishlist.Add(list, id) -> true | false, code (BAD_ITEM, FULL; adding what is there is true, nothing changes)
-- Wishlist.Remove(list, id) -> true when it was there
-- Wishlist.Has(list, id), Wishlist.Count(list), Wishlist.List(list) (ids, ascending), Wishlist.Clear(list)
-- Wishlist.Sanitize(raw) -> a clean list (positive whole ids only, at most MAX).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Wishlist = {}
ns.Wishlist, ns.modules.Wishlist = Wishlist, Wishlist

local type, pairs, tonumber, sort = type, pairs, tonumber, table.sort

Wishlist.MAX = 300
Wishlist.MAX_ID = 10000000

local function valid(id)
	return type(id) == "number" and id == id and id >= 1 and id <= Wishlist.MAX_ID and id == math.floor(id)
end

function Wishlist.ItemIDs(text)
	local out, seen = {}, {}
	if type(text) ~= "string" then return out end
	local function take(id)
		id = tonumber(id)
		if valid(id) and not seen[id] then seen[id] = true; out[#out + 1] = id end
	end
	local rest = text:gsub("item:(%d+)", function(id) take(id); return " " end)
	for id in (" " .. rest .. " "):gmatch("%s(%d+)%s") do take(id) end
	return out
end

function Wishlist.Count(list)
	local n = 0
	for _ in pairs(list or {}) do n = n + 1 end
	return n
end

function Wishlist.Has(list, id) return type(list) == "table" and list[id] == true end

function Wishlist.Add(list, id)
	if not valid(id) then return false, "BAD_ITEM" end
	if list[id] then return true end
	if Wishlist.Count(list) >= Wishlist.MAX then return false, "FULL" end
	list[id] = true
	return true
end

function Wishlist.Remove(list, id)
	if list[id] then list[id] = nil; return true end
	return false
end

function Wishlist.Clear(list)
	for id in pairs(list) do list[id] = nil end
end

function Wishlist.List(list)
	local out = {}
	for id in pairs(list or {}) do out[#out + 1] = id end
	sort(out)
	return out
end

function Wishlist.Sanitize(raw)
	local out, n = {}, 0
	if type(raw) ~= "table" then return out end
	for id, v in pairs(raw) do
		if v == true and valid(id) and n < Wishlist.MAX then out[id] = true; n = n + 1 end
	end
	return out
end

if ns.addon then ns.addon.Wishlist = Wishlist end   -- also reachable from tests
