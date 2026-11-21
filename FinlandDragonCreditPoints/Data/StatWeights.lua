-- StatWeights: the default stat weights per spec for the upgrade score (docs/ANALISI.md §5.1, §13 question 8; M5-1).
-- Lua 5.1, data only.
--
-- These are the reversible default of issue #2 (open question 8): editable default weights per class and spec, with
-- the item-level fallback of Domain/UpgradeScore.lua when stats are unreliable. They are a rough approximation (§5.3:
-- procs, use effects, set bonuses and caps are not in the score), relative to the spec's main stat = 1.0. Personal
-- weights and the optional Pawn-like import arrive with M5-3 and replace a spec's row as a whole; until the Guild
-- Master answers issue #2 nothing else reads them.
--
-- STATS maps the client's stat keys (the keys of C_Item.GetItemStats / GetItemStatDelta, [verify] on WoW Forever in
-- spike S5) to the short codes the weights use. A key missing here keeps its own name and scores 0.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local StatWeights = {}
ns.StatWeights, ns.modules.StatWeights = StatWeights, StatWeights

local type, pairs = type, pairs

StatWeights.STATS = {
	ITEM_MOD_STRENGTH_SHORT = "STR",
	ITEM_MOD_AGILITY_SHORT = "AGI",
	ITEM_MOD_STAMINA_SHORT = "STA",
	ITEM_MOD_INTELLECT_SHORT = "INT",
	ITEM_MOD_SPIRIT_SHORT = "SPI",
	ITEM_MOD_ATTACK_POWER_SHORT = "AP",
	ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP",
	ITEM_MOD_SPELL_POWER_SHORT = "SP",
	ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP",
	ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL",
	ITEM_MOD_CRIT_RATING_SHORT = "CRIT",
	ITEM_MOD_CRIT_SPELL_RATING_SHORT = "CRIT",
	ITEM_MOD_HIT_RATING_SHORT = "HIT",
	ITEM_MOD_HIT_SPELL_RATING_SHORT = "HIT",
	ITEM_MOD_HASTE_RATING_SHORT = "HASTE",
	ITEM_MOD_EXPERTISE_RATING_SHORT = "EXPERTISE",
	ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "ARPEN",
	ITEM_MOD_MASTERY_RATING_SHORT = "MASTERY",
	ITEM_MOD_VERSATILITY = "VERS",
	ITEM_MOD_MANA_REGENERATION_SHORT = "MP5",
	ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEF",
	ITEM_MOD_DODGE_RATING_SHORT = "DODGE",
	ITEM_MOD_PARRY_RATING_SHORT = "PARRY",
	ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK",
	ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCKVALUE",
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
	RESISTANCE0_NAME = "ARMOR",
}

-- The rows, by specID (Data/Specs.lua). Weapon DPS weighs for the specs whose weapon damage matters.
local MELEE = { STA = 0.1, MASTERY = 0.5, VERS = 0.5 }
local CASTER = { STA = 0.1, MASTERY = 0.5, VERS = 0.5 }

local function row(base, t)
	local out = {}
	for k, v in pairs(base) do out[k] = v end
	for k, v in pairs(t) do out[k] = v end
	return out
end

StatWeights.DEFAULT = {
	-- Warrior
	[71] = row(MELEE, { STR = 1.0, AGI = 0.6, AP = 0.5, CRIT = 0.9, HIT = 1.0, HASTE = 0.6, EXPERTISE = 0.9, ARPEN = 0.6, DPS = 4.0 }),
	[72] = row(MELEE, { STR = 1.0, AGI = 0.6, AP = 0.5, CRIT = 0.9, HIT = 1.0, HASTE = 0.7, EXPERTISE = 0.9, ARPEN = 0.6, DPS = 4.0 }),
	[73] = row(MELEE, { STA = 1.0, ARMOR = 0.1, DEF = 1.0, DODGE = 0.8, PARRY = 0.7, BLOCK = 0.5, BLOCKVALUE = 0.3, AGI = 0.5, STR = 0.4, HIT = 0.3, EXPERTISE = 0.4, DPS = 1.0 }),
	-- Paladin
	[65] = row(CASTER, { SP = 1.0, HEAL = 1.0, INT = 0.8, MP5 = 0.8, CRIT = 0.6, HASTE = 0.6, SPI = 0.2 }),
	[66] = row(MELEE, { STA = 1.0, ARMOR = 0.1, DEF = 1.0, DODGE = 0.7, PARRY = 0.6, BLOCK = 0.5, BLOCKVALUE = 0.4, SP = 0.3, STR = 0.3, AGI = 0.4, HIT = 0.3, EXPERTISE = 0.4 }),
	[70] = row(MELEE, { STR = 1.0, AGI = 0.6, AP = 0.45, CRIT = 0.8, HIT = 1.0, HASTE = 0.5, EXPERTISE = 0.8, ARPEN = 0.5, INT = 0.1, SP = 0.3, DPS = 4.0 }),
	-- Hunter
	[253] = row(MELEE, { AGI = 1.0, AP = 0.5, RAP = 0.45, CRIT = 0.8, HIT = 1.0, HASTE = 0.6, ARPEN = 0.6, INT = 0.2, DPS = 4.0 }),
	[254] = row(MELEE, { AGI = 1.0, AP = 0.5, RAP = 0.45, CRIT = 0.9, HIT = 1.0, HASTE = 0.6, ARPEN = 0.7, INT = 0.2, DPS = 4.0 }),
	[255] = row(MELEE, { AGI = 1.0, AP = 0.45, RAP = 0.4, CRIT = 0.8, HIT = 1.0, HASTE = 0.6, ARPEN = 0.5, INT = 0.2, DPS = 4.0 }),
	-- Rogue
	[259] = row(MELEE, { AGI = 1.0, STR = 0.5, AP = 0.5, CRIT = 0.8, HIT = 1.0, HASTE = 0.8, EXPERTISE = 0.9, ARPEN = 0.5, DPS = 4.0 }),
	[260] = row(MELEE, { AGI = 1.0, STR = 0.5, AP = 0.5, CRIT = 0.8, HIT = 1.0, HASTE = 0.8, EXPERTISE = 0.9, ARPEN = 0.7, DPS = 4.0 }),
	[261] = row(MELEE, { AGI = 1.0, STR = 0.5, AP = 0.5, CRIT = 0.8, HIT = 1.0, HASTE = 0.7, EXPERTISE = 0.8, ARPEN = 0.6, DPS = 4.0 }),
	-- Priest
	[256] = row(CASTER, { SP = 1.0, HEAL = 1.0, INT = 0.7, SPI = 0.5, MP5 = 0.8, CRIT = 0.5, HASTE = 0.6 }),
	[257] = row(CASTER, { SP = 1.0, HEAL = 1.0, INT = 0.6, SPI = 0.6, MP5 = 0.8, CRIT = 0.5, HASTE = 0.6 }),
	[258] = row(CASTER, { SP = 1.0, INT = 0.3, SPI = 0.3, CRIT = 0.5, HIT = 1.0, HASTE = 0.8 }),
	-- Shaman
	[262] = row(CASTER, { SP = 1.0, INT = 0.4, CRIT = 0.7, HIT = 1.0, HASTE = 0.7, MP5 = 0.2 }),
	[263] = row(MELEE, { STR = 1.0, AGI = 0.8, AP = 0.5, CRIT = 0.8, HIT = 1.0, HASTE = 0.8, EXPERTISE = 0.8, ARPEN = 0.5, INT = 0.1, SP = 0.2, DPS = 4.0 }),
	[264] = row(CASTER, { SP = 1.0, HEAL = 1.0, INT = 0.7, MP5 = 1.0, CRIT = 0.5, HASTE = 0.6, SPI = 0.1 }),
	-- Mage
	[62] = row(CASTER, { SP = 1.0, INT = 0.5, SPI = 0.2, CRIT = 0.6, HIT = 1.0, HASTE = 0.8 }),
	[63] = row(CASTER, { SP = 1.0, INT = 0.3, CRIT = 0.8, HIT = 1.0, HASTE = 0.8 }),
	[64] = row(CASTER, { SP = 1.0, INT = 0.3, CRIT = 0.6, HIT = 1.0, HASTE = 0.8 }),
	-- Warlock
	[265] = row(CASTER, { SP = 1.0, INT = 0.3, SPI = 0.2, CRIT = 0.5, HIT = 1.0, HASTE = 0.8 }),
	[266] = row(CASTER, { SP = 1.0, INT = 0.3, CRIT = 0.6, HIT = 1.0, HASTE = 0.8 }),
	[267] = row(CASTER, { SP = 1.0, INT = 0.3, CRIT = 0.7, HIT = 1.0, HASTE = 0.8 }),
	-- Druid (feral weapons only count for their stats: no DPS weight)
	[102] = row(CASTER, { SP = 1.0, INT = 0.4, SPI = 0.2, CRIT = 0.7, HIT = 1.0, HASTE = 0.7 }),
	[103] = row(MELEE, { AGI = 1.0, STR = 0.8, AP = 0.5, CRIT = 0.8, HIT = 0.9, HASTE = 0.5, EXPERTISE = 0.8, ARPEN = 0.6 }),
	[104] = row(MELEE, { STA = 1.0, AGI = 0.8, ARMOR = 0.2, DEF = 0.6, DODGE = 0.9, STR = 0.3, AP = 0.1, HIT = 0.3, EXPERTISE = 0.5 }),
	[105] = row(CASTER, { SP = 1.0, HEAL = 1.0, INT = 0.6, SPI = 0.6, MP5 = 0.8, CRIT = 0.3, HASTE = 0.7 }),
}

-- A spec's default weights as a fresh copy (the caller may edit it), or nil for an unknown spec.
function StatWeights.Default(specID)
	local r = type(specID) == "number" and StatWeights.DEFAULT[specID]
	if not r then return nil end
	local out = {}
	for k, v in pairs(r) do out[k] = v end
	return out
end

-- The upgrade score's hooks (Domain/UpgradeScore.lua).
if ns.UpgradeScore then
	ns.UpgradeScore.STAT_KEYS = StatWeights.STATS
	ns.UpgradeScore.DefaultWeights = StatWeights.Default
end

if ns.addon then ns.addon.StatWeights = StatWeights end   -- also reachable from tests
