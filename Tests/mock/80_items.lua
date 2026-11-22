-- Mock client, part 9: items, stats and specializations (M1-3).
--
-- Imitates: C_Item.{GetItemInfo, GetItemInfoInstant, GetDetailedItemLevelInfo, GetItemQualityByID, GetItemStats, GetItemStatDelta,
-- IsEquippableItem, DoesItemContainSpec, GetItemSpecInfo, RequestLoadItemDataByID}, GetInventoryItemLink,
-- C_SpecializationInfo.{GetSpecialization, GetSpecializationInfo, GetInspectSpecialization}, GetNumSpecializations,
-- GetSpecializationRole, the event GET_ITEM_INFO_RECEIVED.
-- Dump files: ../WoW-Addons/docs/api/Items-Inventory (C_Item) and C_SpecializationInfo. The old globals GetItemInfo,
-- GetItemStats, GetItemInfoInstant, GetSpecialization, GetSpecializationInfo are NOT defined: the dump has only the C_*
-- ones (Compat falls back to the globals, which is a no-op here). The numbers in the signatures are in the dump.
--
-- Configure with Mock.items (kept across Mock.Reload):
--   Mock.items.Add{ id=, link=, name=, quality=, level=, equipLoc=, classID=, subclassID=, stats={ ITEM_MOD_X = n },
--       specs={ specID, ... }, cached = true }
--   Mock.items.equipped = { [slot] = link }
--   Mock.items.noStats / Mock.items.secret   behaviours for the degradation tests (see below)
--   Mock.specs.Set{ active = 2, list = { { id=, name=, role=, primaryStat= }, ... }, inspect = { [unit] = specID } }
local Mock, H = ...
local W = Mock.world

W.items = W.items or { byId = {}, byLink = {}, equipped = {}, requested = {} }
local items = W.items
Mock.items = items

function items.Add(def)
	def.cached = def.cached ~= false
	def.stats = def.stats or {}
	items.byId[def.id] = def
	items.byLink[def.link] = def
	return def
end

local function lookup(item)
	if type(item) == "number" then return items.byId[item] end
	if type(item) == "string" then
		return items.byLink[item] or items.byId[tonumber(item:match("item:(%d+)") or "")]
	end
end

C_Item = C_Item or {}

function C_Item.GetItemInfo(item)
	local d = lookup(item)
	if not d or not d.cached then return nil end
	return d.name, d.link, d.quality or 4, d.baseLevel or d.level or 100, d.minLevel or 60, d.type or "Armor", d.subType or "Plate",
		1, d.equipLoc or "INVTYPE_CHEST", d.icon or 134400, 1000, d.classID or 4, d.subclassID or 4, d.bindType or 1, 1, 0, false, ""
end

function C_Item.GetItemInfoInstant(item)
	local d = lookup(item)
	if not d then return nil end
	return d.id, d.type or "Armor", d.subType or "Plate", d.equipLoc or "INVTYPE_CHEST", d.icon or 134400, d.classID or 4,
		d.subclassID or 4
end

function C_Item.GetDetailedItemLevelInfo(item)
	local d = lookup(item)
	if not d then return nil end
	return d.level or 100, false, d.baseLevel or d.level or 100
end

-- M7-5c: the quality of a loaded item (nil until it is), as the dump's C_Item.GetItemQualityByID.
function C_Item.GetItemQualityByID(item)
	local d = lookup(item)
	if not d or not d.cached then return nil end
	return d.quality or 4
end

function C_Item.GetItemStats(link)
	if items.secret then return Mock.SECRET end
	local d = lookup(link)
	if not d or items.noStats then return nil end
	local copy = {}
	for k, v in pairs(d.stats) do copy[k] = v end
	return copy
end

-- The statistics of item 2 minus item 1, for the keys of both.
function C_Item.GetItemStatDelta(link1, link2)
	local a, b = lookup(link1), lookup(link2)
	if not a or not b or items.noStats then return {} end
	local out = {}
	for k, v in pairs(b.stats) do out[k] = v - (a.stats[k] or 0) end
	for k, v in pairs(a.stats) do if out[k] == nil then out[k] = -v end end
	return out
end

function C_Item.IsEquippableItem(item)
	local d = lookup(item)
	return d ~= nil and d.equipLoc ~= nil and d.equipLoc ~= ""
end

function C_Item.DoesItemContainSpec(item, classID, specID)
	local d = lookup(item)
	if not d or not d.specs then return false end
	for _, id in ipairs(d.specs) do if id == specID then return true end end
	return false
end

function C_Item.GetItemSpecInfo(item)
	local d = lookup(item)
	if not d or not d.specs then return nil end
	local out = {}
	for i, id in ipairs(d.specs) do out[i] = id end
	return out
end

function C_Item.RequestLoadItemDataByID(id)
	items.requested[#items.requested + 1] = id
	local d = items.byId[id]
	if d and not d.cached then
		C_Timer.After(0, function() d.cached = true; Mock.Fire("GET_ITEM_INFO_RECEIVED", id, true); Mock.Fire("ITEM_DATA_LOAD_RESULT", id, true) end)
	end
end

function GetInventoryItemLink(unit, slot)
	if unit ~= "player" then return nil end
	return items.equipped[slot]
end

-- Specializations.
W.specs = W.specs or { active = 1, list = {
	{ id = 71, name = "Arms", role = "DAMAGER", primaryStat = 1 },
	{ id = 72, name = "Fury", role = "DAMAGER", primaryStat = 1 },
	{ id = 73, name = "Protection", role = "TANK", primaryStat = 1 },
}, inspect = {} }
local specs = W.specs
Mock.specs = specs

function specs.Set(config)
	for k, v in pairs(config) do specs[k] = v end
	Mock.Fire("PLAYER_SPECIALIZATION_CHANGED", "player")
end

C_SpecializationInfo = C_SpecializationInfo or {}
function C_SpecializationInfo.GetSpecialization() return specs.active end
function C_SpecializationInfo.GetSpecializationInfo(index)
	local s = specs.list[index]
	if not s then return nil end
	return s.id, s.name, "", 132355, s.role, s.primaryStat or 1, 0, "", 0, true
end
function C_SpecializationInfo.GetInspectSpecialization(unit) return specs.inspect[unit] or 0 end
function GetNumSpecializations() return #specs.list end
function GetSpecializationRole(index) local s = specs.list[index]; return s and s.role end
