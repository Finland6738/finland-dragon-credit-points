-- ReadinessData: the fixed tables of the raid readiness check (docs/ANALISI.md §4.2, M8-2). Lua 5.1, data only.
--
-- [verify on Forever] EVERY id in this file is the one of the original game (patch 1.12 era) and is TO VERIFY ON WOW
-- FOREVER (docs/checklists/M8.md): the item ids of the consumables, the spell ids of the buffs they give, and the item
-- types that take an enchant. A wrong id never breaks anything: a consumable id the client does not know is counted as 0,
-- a buff id that is wrong is never seen (the category then still counts the bags), so the worst a wrong id does is a
-- false "low" or "missing" in the master looter's table until the table is fixed.
--
-- What it gives:
--   ReadinessData.SLOTS        the inventory slots that can carry an enchant, in the order of the character sheet
--   ReadinessData.CATEGORIES   the consumable categories, in the order of the table: { code, items = { itemID, ... },
--                              buffs = { BUFF_KIND, ... } (an active buff of one of these kinds counts as the category met),
--                              unit = nil | "AMMO" (ammunition: the count is in pieces, not in stacks or uses) }
--   ReadinessData.BUFFS        { [spellID] = BUFF_KIND }: the readiness buffs read from the player's own auras
--   ReadinessData.MANA         the classes that use mana (the target of a requirement `mana = true`)
--   ReadinessData.Enchantable(slot, instant)  pure: may the item worn in `slot` carry a permanent enchant?
--   ReadinessData.Category(code), ReadinessData.ItemsOf(code), ReadinessData.BuffOf(spellID)
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local ReadinessData = {}
ns.ReadinessData, ns.modules.ReadinessData = ReadinessData, ReadinessData

local type, ipairs = type, ipairs

-- INVSLOT_*: 1 head, 3 shoulder, 5 chest, 7 legs, 8 feet, 9 wrist, 10 hands, 15 back, 16 main hand, 17 off hand,
-- 18 ranged. Rings, neck, trinkets, waist, shirt and tabard take no permanent enchant in this era.
ReadinessData.SLOTS = { 1, 3, 5, 7, 8, 9, 10, 15, 16, 17, 18 }
local IS_SLOT = {}
for _, s in ipairs(ReadinessData.SLOTS) do IS_SLOT[s] = true end
ReadinessData.IS_SLOT = IS_SLOT

-- Worn in the off hand or the ranged slot, these take no enchant: a held-in-off-hand item, a relic (idol, libram, totem),
-- a thrown weapon, a wand. Only shields and weapons in the off hand, only bows, guns and crossbows in the ranged slot.
ReadinessData.NO_ENCHANT_EQUIPLOC = { INVTYPE_HOLDABLE = true, INVTYPE_RELIC = true, INVTYPE_THROWN = true }
ReadinessData.RANGED_SCOPE_SUBCLASSES = { [2] = true, [3] = true, [18] = true }   -- weapon subclass: bow, gun, crossbow
ReadinessData.WEAPON_CLASS = 2

-- Buff kinds: WELL_FED (the buff of a cooked food), FLASK, ELIXIR (battle or guardian: the era does not tell them apart).
ReadinessData.BUFF_KINDS = { "WELL_FED", "FLASK", "ELIXIR" }

-- [verify on Forever] spell id of the aura -> buff kind.
ReadinessData.BUFFS = {
	-- Well Fed: the generic food buffs and the named ones of the raid foods
	[19705] = "WELL_FED", [19706] = "WELL_FED", [19708] = "WELL_FED", [19709] = "WELL_FED", [19710] = "WELL_FED",
	[19711] = "WELL_FED",
	[18191] = "WELL_FED",   -- Increased Stamina (Cooked Glossy Mightfish)
	[18192] = "WELL_FED",   -- Increased Agility (Grilled Squid)
	[18193] = "WELL_FED",   -- Increased Spirit
	[18194] = "WELL_FED",   -- Mana Regeneration (Nightfin Soup)
	[18222] = "WELL_FED",   -- Health Regeneration (Poached Sunscale Salmon)
	[22730] = "WELL_FED",   -- Increased Intellect (Runn Tum Tuber Surprise)
	[24799] = "WELL_FED",   -- Well Fed (Smoked Desert Dumplings)
	[25661] = "WELL_FED",   -- Well Fed (Dirge's Kickin' Chimaerok Chops)
	[18125] = "WELL_FED",   -- Blessed Sunfruit
	[18141] = "WELL_FED",   -- Blessed Sunfruit Juice
	-- Flasks
	[17626] = "FLASK",      -- Flask of the Titans
	[17627] = "FLASK",      -- Flask of Distilled Wisdom
	[17628] = "FLASK",      -- Flask of Supreme Power
	[17629] = "FLASK",      -- Flask of Chromatic Resistance
	-- Elixirs
	[17538] = "ELIXIR",     -- Elixir of the Mongoose
	[17537] = "ELIXIR",     -- Elixir of Brute Force
	[17539] = "ELIXIR",     -- Greater Arcane Elixir
	[17535] = "ELIXIR",     -- Elixir of the Sages
	[11405] = "ELIXIR",     -- Elixir of Giants
	[11334] = "ELIXIR",     -- Elixir of Greater Agility
	[11474] = "ELIXIR",     -- Elixir of Shadow Power
	[26276] = "ELIXIR",     -- Elixir of Greater Firepower
	[21920] = "ELIXIR",     -- Elixir of Frost Power
	[11348] = "ELIXIR",     -- Elixir of Superior Defense
	[3593] = "ELIXIR",      -- Elixir of Fortitude
	[24361] = "ELIXIR",     -- Major Troll's Blood Potion
	[24363] = "ELIXIR",     -- Mageblood Potion
	[24382] = "ELIXIR",     -- Spirit of Zanza
}

-- [verify on Forever] the consumable categories and their item ids.
ReadinessData.CATEGORIES = {
	{ code = "FOOD_BUFF", buffs = { "WELL_FED" }, items = {
		20452,   -- Smoked Desert Dumplings
		13928,   -- Grilled Squid
		13931,   -- Nightfin Soup
		18254,   -- Runn Tum Tuber Surprise
		21023,   -- Dirge's Kickin' Chimaerok Chops
		12218,   -- Monster Omelet
		18045,   -- Tender Wolf Steak
		12216,   -- Spiced Chili Crab
		13927,   -- Cooked Glossy Mightfish
		13932,   -- Poached Sunscale Salmon
		13810,   -- Blessed Sunfruit
		13813,   -- Blessed Sunfruit Juice
	} },
	{ code = "FOOD", items = {
		22895,   -- Conjured Cinnamon Roll
		8076,    -- Conjured Sweet Roll
		8932,    -- Alterac Swiss
		8952,    -- Roasted Quail
		8953,    -- Deep Fried Plantains
		8950,    -- Homemade Cherry Pie
		8957,    -- Spinefin Halibut
		13935,   -- Baked Salmon
		13933,   -- Lobster Stew
	} },
	{ code = "WATER", items = {
		8079,    -- Conjured Crystal Water
		8078,    -- Conjured Sparkling Water
		8766,    -- Morning Glory Dew
		1645,    -- Moonberry Juice
		13724,   -- Enriched Manna Biscuit
		19301,   -- Alterac Manna Biscuit
	} },
	{ code = "POTION", items = {
		13446,   -- Major Healing Potion
		3928,    -- Superior Healing Potion
		18839,   -- Combat Healing Potion
		13444,   -- Major Mana Potion
		13443,   -- Superior Mana Potion
		18841,   -- Combat Mana Potion
	} },
	{ code = "FLASK", buffs = { "FLASK", "ELIXIR" }, items = {
		13510, 13511, 13512, 13513,   -- the four flasks
		13452,   -- Elixir of the Mongoose
		13453,   -- Elixir of Brute Force
		13454,   -- Greater Arcane Elixir
		13447,   -- Elixir of the Sages
		9206,    -- Elixir of Giants
		9187,    -- Elixir of Greater Agility
		9264,    -- Elixir of Shadow Power
		21546,   -- Elixir of Greater Firepower
		17708,   -- Elixir of Frost Power
		13445,   -- Elixir of Superior Defense
		3825,    -- Elixir of Fortitude
		20004,   -- Major Troll's Blood Potion
		20007,   -- Mageblood Potion
		20079,   -- Spirit of Zanza
	} },
	{ code = "AMMO", unit = "AMMO", items = {
		3030,    -- Razor Arrow
		11285,   -- Jagged Arrow
		18042,   -- Thorium Headed Arrow
		19316,   -- Ice Threaded Arrow
		12654,   -- Doomshot
		10512,   -- Hi-Impact Mithril Slugs
		10513,   -- Mithril Gyro-Shot
		11284,   -- Accurate Slugs
		15997,   -- Thorium Shells
		19317,   -- Ice Threaded Bullet
	} },
	{ code = "PET_FOOD", items = {
		8952,    -- Roasted Quail (meat)
		4599,    -- Cured Ham Steak (meat)
		3771,    -- Wild Hog Shank (meat)
		8957,    -- Spinefin Halibut (fish)
		8953,    -- Deep Fried Plantains (fruit)
		8950,    -- Homemade Cherry Pie (bread)
		4602,    -- Moon Harvest Pumpkin (bread)
	} },
}

local BY_CODE = {}
for _, c in ipairs(ReadinessData.CATEGORIES) do BY_CODE[c.code] = c end

-- The classes that use mana (the druid too: its forms change the bar, not the need for water).
ReadinessData.MANA = { PALADIN = true, HUNTER = true, PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true }
ReadinessData.CLASSES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true,
	MAGE = true, WARLOCK = true, DRUID = true }
ReadinessData.ROLES = { TANK = true, HEALER = true, DAMAGER = true }

function ReadinessData.Category(code) return BY_CODE[code] end

function ReadinessData.ItemsOf(code)
	local c = BY_CODE[code]
	return c and c.items or {}
end

function ReadinessData.BuffOf(spellID) return ReadinessData.BUFFS[spellID] end

-- May the item worn in `slot` take a permanent enchant? `instant` is what GetItemInfoInstant says of it
-- ({ equipLoc, classID, subClassID }); nil when the client does not say (then the head-to-hands slots answer yes, the off
-- hand and the ranged slot nil: unknown).
function ReadinessData.Enchantable(slot, instant)
	if not IS_SLOT[slot] then return false end
	if slot ~= 17 and slot ~= 18 then return true end
	if type(instant) ~= "table" then return nil end
	local loc = instant.equipLoc
	if type(loc) == "string" and ReadinessData.NO_ENCHANT_EQUIPLOC[loc] then return false end
	if slot == 18 then
		if instant.classID ~= ReadinessData.WEAPON_CLASS then return false end
		return ReadinessData.RANGED_SCOPE_SUBCLASSES[instant.subClassID] == true
	end
	if type(loc) ~= "string" or loc == "" then return nil end
	return true
end

if ns.addon then ns.addon.ReadinessData = ReadinessData end   -- also reachable from tests
