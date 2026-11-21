-- Inventory: what the player wears and what an item is worth against it, read from the game for Domain/UpgradeScore.lua
-- (docs/ANALISI.md §5.1, M5-2). Lua 5.1. Everything goes through Core/Compat.lua (Compat.Item: GetInventoryItemLink,
-- C_Item.GetItemInfo / GetItemInfoInstant, GetDetailedItemLevelInfo, GetItemStats, GetItemStatDelta, IsEquippableItem,
-- DoesItemContainSpec, GetItemSpecInfo; Compat.Player, Compat.Spec); the names were checked against the Forever API dump.
-- The domain gets plain tables, never a game object, and a secret value never reaches it (Compat reads them as nil).
--
-- A piece (the shape UpgradeScore.Evaluate takes):
--   { itemID, link ("item:..." without the hyperlink markup), equipLoc, classID, subclassID, level, stats = { [client key]
--     = n } | nil (unknown), specs = { specID, ... } | nil (nil: not restricted, or the client does not say) }
-- Not known from the API and left out: the class restriction of a token and the use / proc effect of a trinket (they are
-- in the tooltip text only), hence the limits of §5.3.
--
-- Inventory.Ref(x)                the item string "item:..." of a link, an id or an item string, and the id; nil, nil if none
-- Inventory.Piece(x, opts)        a piece of an item (a link, an id or an item string), nil and a code ("UNKNOWN",
--                                 "NOT_LOADED") when the client has no data. opts.classID / opts.classFile: the character,
--                                 to read the spec list with DoesItemContainSpec when GetItemSpecInfo says nothing;
--                                 opts.unloaded = accept an item whose full data is not loaded; opts.noSpecs = skip the spec list.
-- Inventory.Equipped()            { [slot] = piece } of the player's inventory slots (INVSLOT_*; shirt and tabard are not
--                                 compared), and the list of the item strings in slot order
-- Inventory.Fill(piece, equipped) fills a missing stats table of the piece or of an equipped piece from
--                                 C_Item.GetItemStatDelta (the difference is reliable even when one table is not)
-- Inventory.Player()              { class = "WARRIOR", classID, spec = the active specID | nil }
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Inventory = {}
ns.Inventory, ns.modules.Inventory = Inventory, Inventory

local type, tonumber, pairs, ipairs = type, tonumber, pairs, ipairs

-- The inventory slots compared (UpgradeScore.SLOT): everything but the shirt (4) and the tabard (19).
Inventory.SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local function C() return ns.Compat end

-- "item:19003:..." from a hyperlink, an item string or a number; the item id with it.
function Inventory.Ref(x)
	if type(x) == "number" then
		if x > 0 and x == math.floor(x) then return "item:" .. x, x end
		return nil, nil
	end
	if type(x) ~= "string" then return nil, nil end
	local ref = x:match("(item:[%-%d:]+)")
	local id = ref and tonumber(ref:match("^item:(%d+)"))
	if not id then return nil, nil end
	return ref, id
end

-- The specs an item is for: GetItemSpecInfo, else DoesItemContainSpec over the character's class. nil when neither
-- says anything (the item is then not restricted).
local function specsOf(ref, opts)
	local list = C().Item.SpecInfo(ref)
	if list and #list > 0 then return list end
	local classID = opts and opts.classID
	local classFile = opts and opts.classFile
	if type(classID) ~= "number" or not classFile or not ns.Specs then return nil end
	local out = {}
	for _, spec in ipairs(ns.Specs.OfClass(classFile)) do
		if C().Item.ContainsSpec(ref, classID, spec.id) == true then out[#out + 1] = spec.id end
	end
	if #out == 0 then return nil end
	return out
end

-- A piece of an item. `x` may be the full hyperlink of a worn item (the item level then includes its upgrades).
function Inventory.Piece(x, opts)
	local ref, id = Inventory.Ref(x)
	if not ref then return nil, "UNKNOWN" end
	local Item = C().Item
	local entry = ns.ItemCache and ns.ItemCache.Lookup(id) or nil
	if not entry then return nil, "UNKNOWN" end
	if not entry.loaded and not (opts and opts.unloaded) then return nil, "NOT_LOADED" end
	local arg = type(x) == "string" and x or ref
	local equipLoc = entry.equipLoc
	if equipLoc and equipLoc ~= "" and Item.IsEquippable(ref) == false then equipLoc = "" end
	local piece = { itemID = id, link = ref, equipLoc = equipLoc, classID = entry.classID, subclassID = entry.subclassID,
		level = Item.Level(arg) or entry.level, stats = Item.Stats(arg) }
	if equipLoc and equipLoc ~= "" and not (opts and opts.noSpecs) then piece.specs = specsOf(ref, opts) end
	return piece
end

-- The worn pieces by slot, and their item strings in slot order.
function Inventory.Equipped()
	local equipped, links = {}, {}
	for _, slot in ipairs(Inventory.SLOTS) do
		local link = C().Item.EquippedLink(slot)
		if link then
			local piece = Inventory.Piece(link, { unloaded = true, noSpecs = true })
			if piece then
				piece.slot = slot
				equipped[slot] = piece
				links[#links + 1] = piece.link
			end
		end
	end
	return equipped, links
end

local function plus(a, b, sign)
	local out = {}
	for k, v in pairs(a) do out[k] = v end
	for k, v in pairs(b) do out[k] = (out[k] or 0) + sign * v end
	return out
end

-- Completes what GetItemStats left unknown, from GetItemStatDelta(worn, new) = new - worn: a worn piece without stats gets
-- new - delta, a new piece without stats gets worn + delta. Only pieces whose stats are nil are touched. Returns the
-- number of tables filled.
function Inventory.Fill(piece, equipped)
	local filled = 0
	local Item = C().Item
	for _, worn in pairs(equipped or {}) do
		if (piece.stats == nil) ~= (worn.stats == nil) then   -- one side is unknown, the other known
			local delta = Item.StatDelta(worn.link, piece.link)
			if delta then
				if worn.stats == nil then
					worn.stats = plus(piece.stats, delta, -1)
				else
					piece.stats = plus(worn.stats, delta, 1)
				end
				filled = filled + 1
			end
		end
	end
	return filled
end

-- The character: its class (file name and id) and the specID it plays now.
function Inventory.Player()
	local active = C().Spec.Active()
	return { class = C().Player.ClassFile(), classID = C().Player.ClassID(), spec = active and active.id or nil }
end

if ns.addon then ns.addon.Inventory = Inventory end   -- also reachable from tests
