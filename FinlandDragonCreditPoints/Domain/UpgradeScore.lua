-- UpgradeScore: is an item an upgrade for this character, and how big (docs/ANALISI.md §5.1, §5.3; M5-1). Pure Lua 5.1:
-- it never calls the game. The inventory adapter (M5-2) reads the item, the equipped pieces and their stats from the
-- client and hands them over as plain tables; this file only compares numbers.
--
-- The four questions of §5.1:
--   1. Can the character use it?  The proficiency table per class (armour and weapon types, shields, relics, dual
--      wield), the item's class restriction and spec list when the adapter knows them. An unusable item has
--      `usable = false` and a code; its verdict is NONE (the popup preselects Pass, M5-2).
--   2. Against what?  The slot from `equipLoc`: rings and trinkets against the worse of the two equipped (an empty
--      slot first, the same item id when it is already worn), a two-hander against main hand + off hand, a one-hander
--      against the worse of the two hands only when the character is dual wielding, a one-hander against an equipped
--      two-hander alone.
--   3. How much?  `score = Σ weight(stat) × value` with the weights of the declared spec, `upgrade % = (new − equipped)
--      / equipped`, plus the item-level delta. Item-level only (plan B of spike S5) when stats are unreliable
--      (`config.useStats = false`), unknown, or carry no weighted stat, or when there are no weights for the spec.
--   4. Verdict.  BIG (≥ `bigThreshold`, preset 5%), SMALL (> `smallThreshold`, preset 0), NONE, NOT_COMPARABLE.
--
-- Input:
--   item     = { itemID?, equipLoc = "INVTYPE_...", classID?, subclassID?, level?, stats? = { [stat] = n },
--                effect? = true (use / proc effect the weights cannot see), classes? = { "PALADIN", ... },
--                specs? = { specID, ... } }
--   equipped = { [inventory slot id] = same shape as item } (missing slot = empty)
--   who      = { class = "WARRIOR", spec = specID?, weights? = { [stat] = n } }   -- weights: the spec's defaults
--   config   = UpgradeScore.DefaultConfig() with changes, or nil
-- `stats` may use the client's keys (ITEM_MOD_STRENGTH_SHORT, from C_Item.GetItemStats / GetItemStatDelta) or the short
-- codes of Data/StatWeights.lua (STR); `stats = nil` means unknown, `{}` means known and empty.
--
-- Output of UpgradeScore.Evaluate: codes and numbers only, never sentences (the locales give the words, M5-2):
--   { verdict = "BIG" | "SMALL" | "NONE" | "NOT_COMPARABLE", usable = true | false | nil (nil: not an equippable item,
--     such as a token: the addon cannot tell), code = refusal / not-comparable code | nil,
--     basis = "STATS" | "ILVL" | nil, pct = fraction | nil (nil: empty slot or equipped score 0), ilvlDelta = n | nil,
--     score = n | nil, equippedScore = n | nil, level = n | nil, equippedLevel = n | nil, slots = { slot ids },
--     notes = { code, ... }, unscored = { stat code, ... } }
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local UpgradeScore = {}
ns.UpgradeScore, ns.modules.UpgradeScore = UpgradeScore, UpgradeScore

local type, pairs, ipairs, next, tostring = type, pairs, ipairs, next, tostring
local sort = table.sort

UpgradeScore.VERDICTS = { "BIG", "SMALL", "NONE", "NOT_COMPARABLE" }

-- Inventory slot ids (INVSLOT_*): the same numbers as GetInventoryItemLink.
UpgradeScore.SLOT = {
	HEAD = 1, NECK = 2, SHOULDER = 3, BODY = 4, CHEST = 5, WAIST = 6, LEGS = 7, FEET = 8, WRIST = 9, HAND = 10,
	FINGER1 = 11, FINGER2 = 12, TRINKET1 = 13, TRINKET2 = 14, BACK = 15, MAINHAND = 16, OFFHAND = 17, RANGED = 18,
	TABARD = 19,
}
local S = UpgradeScore.SLOT

-- equipLoc -> the slots it is compared against. The hands are handled apart (WEAPON_LOC).
UpgradeScore.EQUIP_SLOTS = {
	INVTYPE_HEAD = { S.HEAD }, INVTYPE_NECK = { S.NECK }, INVTYPE_SHOULDER = { S.SHOULDER },
	INVTYPE_CHEST = { S.CHEST }, INVTYPE_ROBE = { S.CHEST }, INVTYPE_WAIST = { S.WAIST }, INVTYPE_LEGS = { S.LEGS },
	INVTYPE_FEET = { S.FEET }, INVTYPE_WRIST = { S.WRIST }, INVTYPE_HAND = { S.HAND }, INVTYPE_CLOAK = { S.BACK },
	INVTYPE_FINGER = { S.FINGER1, S.FINGER2 }, INVTYPE_TRINKET = { S.TRINKET1, S.TRINKET2 },
	INVTYPE_RANGED = { S.RANGED }, INVTYPE_RANGEDRIGHT = { S.RANGED }, INVTYPE_THROWN = { S.RANGED },
	INVTYPE_RELIC = { S.RANGED },
}
-- The equipLocs that never carry a comparable upgrade (shirts, tabards).
UpgradeScore.COSMETIC_LOC = { INVTYPE_BODY = true, INVTYPE_TABARD = true }
-- The hands: "2H", "1H" (either hand), "MH", "OH" (an off-hand weapon), "SHIELD", "HOLDABLE".
local WEAPON_LOC = {
	INVTYPE_2HWEAPON = "2H", INVTYPE_WEAPON = "1H", INVTYPE_WEAPONMAINHAND = "MH", INVTYPE_WEAPONOFFHAND = "OH",
	INVTYPE_SHIELD = "SHIELD", INVTYPE_HOLDABLE = "HOLDABLE",
}
UpgradeScore.WEAPON_LOC = WEAPON_LOC

-- Item class / subclass ids (Enum.ItemClass, Enum.ItemArmorSubclass, Enum.ItemWeaponSubclass) -> proficiency code.
UpgradeScore.ITEM_CLASS = { WEAPON = 2, ARMOR = 4 }
UpgradeScore.ARMOR_TYPE = {
	[1] = "CLOTH", [2] = "LEATHER", [3] = "MAIL", [4] = "PLATE", [6] = "SHIELD", [7] = "LIBRAM", [8] = "IDOL",
	[9] = "TOTEM", [10] = "SIGIL",
}
UpgradeScore.WEAPON_TYPE = {
	[0] = "AXE1H", [1] = "AXE2H", [2] = "BOW", [3] = "GUN", [4] = "MACE1H", [5] = "MACE2H", [6] = "POLEARM",
	[7] = "SWORD1H", [8] = "SWORD2H", [9] = "WARGLAIVE", [10] = "STAFF", [13] = "FIST", [15] = "DAGGER",
	[16] = "THROWN", [17] = "SPEAR", [18] = "CROSSBOW", [19] = "WAND",
}

local function set(list)
	local t = {}
	for _, v in ipairs(list) do t[v] = true end
	return t
end

-- The proficiency table per class (the nine classes of Domain/Roster.lua). A fresh copy on every call, so a caller may
-- change it freely. `dualWield` = true for the whole class, or a list of specIDs (the enhancement shaman's talent).
-- Cloth cloaks, rings, necks, trinkets and held-in-off-hand items are usable by every class and need no entry. A
-- subclass the tables do not know is never refused.
function UpgradeScore.DefaultProficiency()
	return {
		WARRIOR = {
			armor = set({ "CLOTH", "LEATHER", "MAIL", "PLATE", "SHIELD" }),
			weapon = set({ "AXE1H", "AXE2H", "MACE1H", "MACE2H", "SWORD1H", "SWORD2H", "POLEARM", "STAFF", "FIST",
				"DAGGER", "BOW", "GUN", "CROSSBOW", "THROWN" }),
			dualWield = true,
		},
		PALADIN = {
			armor = set({ "CLOTH", "LEATHER", "MAIL", "PLATE", "SHIELD", "LIBRAM" }),
			weapon = set({ "AXE1H", "AXE2H", "MACE1H", "MACE2H", "SWORD1H", "SWORD2H", "POLEARM" }),
		},
		HUNTER = {
			armor = set({ "CLOTH", "LEATHER", "MAIL" }),
			weapon = set({ "AXE1H", "AXE2H", "SWORD1H", "SWORD2H", "POLEARM", "STAFF", "FIST", "DAGGER", "BOW", "GUN",
				"CROSSBOW", "THROWN" }),
			dualWield = true,
		},
		ROGUE = {
			armor = set({ "CLOTH", "LEATHER" }),
			weapon = set({ "DAGGER", "FIST", "MACE1H", "SWORD1H", "BOW", "GUN", "CROSSBOW", "THROWN" }),
			dualWield = true,
		},
		PRIEST = {
			armor = set({ "CLOTH" }),
			weapon = set({ "MACE1H", "STAFF", "DAGGER", "WAND" }),
		},
		SHAMAN = {
			armor = set({ "CLOTH", "LEATHER", "MAIL", "SHIELD", "TOTEM" }),
			weapon = set({ "AXE1H", "AXE2H", "MACE1H", "MACE2H", "STAFF", "FIST", "DAGGER" }),
			dualWield = { 263 },
		},
		MAGE = {
			armor = set({ "CLOTH" }),
			weapon = set({ "SWORD1H", "STAFF", "DAGGER", "WAND" }),
		},
		WARLOCK = {
			armor = set({ "CLOTH" }),
			weapon = set({ "SWORD1H", "STAFF", "DAGGER", "WAND" }),
		},
		DRUID = {
			armor = set({ "CLOTH", "LEATHER", "IDOL" }),
			weapon = set({ "MACE1H", "MACE2H", "STAFF", "FIST", "DAGGER" }),
		},
	}
end

-- The preset thresholds (§5.1 point 4). A fresh copy on every call.
function UpgradeScore.DefaultConfig()
	return {
		bigThreshold = 0.05,      -- BIG from +5% of weighted score
		smallThreshold = 0,       -- SMALL above this (strictly), NONE at or below
		ilvlBigThreshold = 0.05,  -- BIG from +5% of item level, when the comparison is item-level only
		useStats = true,          -- false: item-level only for everybody (plan B of spike S5)
		proficiency = nil,        -- nil: DefaultProficiency()
	}
end

-- Checks a configuration: true, or nil and a code.
function UpgradeScore.ValidateConfig(c)
	if type(c) ~= "table" then return nil, "BAD_CONFIG" end
	for _, k in ipairs({ "bigThreshold", "smallThreshold", "ilvlBigThreshold" }) do
		local v = c[k]
		if type(v) ~= "number" or v ~= v or v < 0 or v > 10 then return nil, "BAD_THRESHOLD" end
	end
	if c.smallThreshold > c.bigThreshold then return nil, "BAD_THRESHOLD" end
	if c.proficiency ~= nil and type(c.proficiency) ~= "table" then return nil, "BAD_PROFICIENCY" end
	return true
end

-- The rules' section "upgrade" (Domain/Rules.lua, M5-2): the guild's thresholds and switches, written by the Guild
-- Master like the rest of the rules and read by every client, so the verdicts of a raid use the same numbers.
--   enabled   false = the popup shows no verdict and the responses carry none
--   autoPass  true = an item the character cannot use is preselected on Pass (nothing is sent by itself)
-- and the thresholds / useStats of DefaultConfig. A fresh copy on every call.
function UpgradeScore.DefaultRules()
	local c = UpgradeScore.DefaultConfig()
	c.proficiency = nil
	c.enabled, c.autoPass = true, true
	return c
end

local RULE_FIELDS = { enabled = true, autoPass = true, useStats = true, bigThreshold = true, smallThreshold = true,
	ilvlBigThreshold = true }

-- Checks the section: true, or false and a sorted list of codes (a field name, or "unknown:<field>").
function UpgradeScore.ValidateRules(c)
	if type(c) ~= "table" then return false, { "upgrade" } end
	local p = {}
	for _, k in ipairs({ "enabled", "autoPass", "useStats" }) do
		if type(c[k]) ~= "boolean" then p[#p + 1] = k end
	end
	for _, k in ipairs({ "bigThreshold", "smallThreshold", "ilvlBigThreshold" }) do
		local v = c[k]
		if type(v) ~= "number" or v ~= v or v < 0 or v > 10 then p[#p + 1] = k end
	end
	if type(c.smallThreshold) == "number" and type(c.bigThreshold) == "number" and c.smallThreshold > c.bigThreshold then
		p[#p + 1] = "smallThreshold"
	end
	for k in pairs(c) do
		if not RULE_FIELDS[k] then p[#p + 1] = "unknown:" .. tostring(k) end
	end
	sort(p)
	return #p == 0, p
end

-- The score's configuration of a rules section (nil: the presets).
function UpgradeScore.ConfigFromRules(rules)
	local c = UpgradeScore.DefaultConfig()
	if type(rules) == "table" then
		for _, k in ipairs({ "bigThreshold", "smallThreshold", "ilvlBigThreshold", "useStats" }) do
			if rules[k] ~= nil then c[k] = rules[k] end
		end
	end
	return c
end

local DEFAULT_PROFICIENCY = UpgradeScore.DefaultProficiency()

-- Hooks set by Data/StatWeights.lua: the client's stat key -> short code, and a spec's default weights (a fresh copy).
UpgradeScore.STAT_KEYS = UpgradeScore.STAT_KEYS or {}
UpgradeScore.DefaultWeights = UpgradeScore.DefaultWeights or function() return nil end

-- Stats with short codes: the client's keys are translated, short codes pass through, non-numbers and unknown client
-- keys (a code the table does not list) are kept under their own name (they score 0 unless a weight names them).
function UpgradeScore.NormalizeStats(raw)
	if type(raw) ~= "table" then return nil end
	local out = {}
	for k, v in pairs(raw) do
		if type(k) == "string" and type(v) == "number" and v == v then
			local code = UpgradeScore.STAT_KEYS[k] or k
			out[code] = (out[code] or 0) + v
		end
	end
	return out
end

-- Σ weight × value. Returns the score and the sorted list of stats with a non-zero value and no weight.
function UpgradeScore.Score(stats, weights)
	local score, unscored = 0, {}
	for code, v in pairs(stats or {}) do
		local w = weights and weights[code]
		if type(w) == "number" and w == w then
			score = score + w * v
		elseif v ~= 0 then
			unscored[#unscored + 1] = code
		end
	end
	sort(unscored)
	return score, unscored
end

local function contains(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then return true end
	end
	return false
end

local function profOf(config, class)
	local table_ = (config and config.proficiency) or DEFAULT_PROFICIENCY
	return table_[class]
end

-- Can this class (and spec) dual wield?
function UpgradeScore.CanDualWield(class, spec, config)
	local p = profOf(config, class)
	local dw = p and p.dualWield
	if dw == true then return true end
	if type(dw) == "table" then return contains(dw, spec) end
	return false
end

-- 1. Can the character use it? true, or false and a code: NOT_EQUIPPABLE, CLASS_RESTRICTED, SPEC_RESTRICTED,
-- UNKNOWN_CLASS, ARMOR_TYPE, WEAPON_TYPE, DUAL_WIELD. The class and spec restrictions come first, so a token for
-- another class is refused while a token for this class is only "not equippable".
function UpgradeScore.CanUse(item, class, spec, config)
	if type(item) ~= "table" then return false, "NOT_EQUIPPABLE" end
	if type(item.classes) == "table" and #item.classes > 0 and not contains(item.classes, class) then
		return false, "CLASS_RESTRICTED"
	end
	if type(item.specs) == "table" and #item.specs > 0 and spec ~= nil and not contains(item.specs, spec) then
		return false, "SPEC_RESTRICTED"
	end
	local loc = item.equipLoc
	if type(loc) ~= "string" or not (UpgradeScore.EQUIP_SLOTS[loc] or WEAPON_LOC[loc] or UpgradeScore.COSMETIC_LOC[loc]) then
		return false, "NOT_EQUIPPABLE"
	end
	local p = profOf(config, class)
	if not p then return false, "UNKNOWN_CLASS" end
	local C = UpgradeScore.ITEM_CLASS
	if item.classID == C.ARMOR and loc ~= "INVTYPE_CLOAK" then
		local kind = UpgradeScore.ARMOR_TYPE[item.subclassID]
		if kind and not (p.armor and p.armor[kind]) then return false, "ARMOR_TYPE" end
	elseif item.classID == C.WEAPON then
		local kind = UpgradeScore.WEAPON_TYPE[item.subclassID]
		if kind and not (p.weapon and p.weapon[kind]) then return false, "WEAPON_TYPE" end
	end
	if loc == "INVTYPE_WEAPONOFFHAND" and not UpgradeScore.CanDualWield(class, spec, config) then
		return false, "DUAL_WIELD"
	end
	return true
end

local function result(verdict, extra)
	local r = { verdict = verdict, usable = true, slots = {}, notes = {}, unscored = {} }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end

local function isTwoHand(piece)
	return piece ~= nil and piece.equipLoc == "INVTYPE_2HWEAPON"
end

local function isWeapon(piece)
	local hand = piece and WEAPON_LOC[piece.equipLoc]
	return hand == "1H" or hand == "MH" or hand == "OH" or hand == "2H"
end

-- 2. Against what? Returns a list of candidate targets, each a list of slot ids whose pieces are summed (a two-hander
-- against main hand + off hand is one target with two slots), plus notes; or nil and a NOT_COMPARABLE code. The caller
-- picks the worst target.
function UpgradeScore.Targets(item, equipped, class, spec, config)
	equipped = equipped or {}
	local loc = item.equipLoc
	local notes = {}
	if UpgradeScore.COSMETIC_LOC[loc] then return nil, "COSMETIC" end
	local slots = UpgradeScore.EQUIP_SLOTS[loc]
	if slots then
		if #slots == 1 then return { { slots[1] } }, notes end
		-- A pair (rings, trinkets): the same item already worn first, then an empty slot, then both.
		if item.itemID then
			for _, s in ipairs(slots) do
				if equipped[s] and equipped[s].itemID == item.itemID then
					notes[#notes + 1] = "SAME_ITEM_EQUIPPED"
					return { { s } }, notes
				end
			end
		end
		for _, s in ipairs(slots) do
			if not equipped[s] then return { { s } }, notes end
		end
		local out = {}
		for _, s in ipairs(slots) do
			if loc == "INVTYPE_TRINKET" and equipped[s].effect then
				notes[#notes + 1] = "EFFECT_TRINKET_KEPT"
			else
				out[#out + 1] = { s }
			end
		end
		if #out == 0 then return nil, "EFFECT_TRINKETS" end
		return out, notes
	end
	local hand = WEAPON_LOC[loc]
	if not hand then return nil, "NOT_EQUIPPABLE" end
	local mh, oh = equipped[S.MAINHAND], equipped[S.OFFHAND]
	if hand == "2H" then
		if not isTwoHand(mh) then notes[#notes + 1] = "TWO_HAND_VS_PAIR" end
		return { { S.MAINHAND, S.OFFHAND } }, notes
	end
	if isTwoHand(mh) then
		if hand == "1H" or hand == "MH" then
			notes[#notes + 1] = "REPLACES_TWO_HAND"
			return { { S.MAINHAND } }, notes
		end
		return nil, "TWO_HAND_EQUIPPED"
	end
	if hand == "MH" then return { { S.MAINHAND } }, notes end
	if hand == "OH" or hand == "SHIELD" or hand == "HOLDABLE" then return { { S.OFFHAND } }, notes end
	-- A one-hander: either hand only while the character is dual wielding (a weapon in the off hand).
	if UpgradeScore.CanDualWield(class, spec, config) and isWeapon(oh) and mh then
		return { { S.MAINHAND }, { S.OFFHAND } }, notes
	end
	return { { S.MAINHAND } }, notes
end

-- 4. The verdict of an upgrade fraction on a basis ("STATS" or "ILVL").
function UpgradeScore.Verdict(pct, config, basis)
	config = config or UpgradeScore.DefaultConfig()
	local big = basis == "ILVL" and config.ilvlBigThreshold or config.bigThreshold
	if pct >= big then return "BIG" end
	if pct > config.smallThreshold then return "SMALL" end
	return "NONE"
end

-- The pieces of a target: their summed stats (nil when one is unknown), their average item level (nil when one is
-- unknown), whether every slot is empty, and whether one carries an effect.
local function gather(target, equipped)
	local stats, level, levels, worn, effect = {}, 0, 0, 0, false
	for _, s in ipairs(target) do
		local piece = equipped[s]
		if piece then
			worn = worn + 1
			if piece.effect then effect = true end
			local st = UpgradeScore.NormalizeStats(piece.stats)
			if not st then
				stats = nil
			elseif stats then
				for k, v in pairs(st) do stats[k] = (stats[k] or 0) + v end
			end
			if type(piece.level) == "number" and level then
				level, levels = level + piece.level, levels + 1
			else
				level = nil
			end
		end
	end
	if worn == 0 then return { empty = true, stats = {}, level = nil } end
	return { stats = stats, level = level and levels > 0 and level / levels or nil, effect = effect }
end

local function addNote(r, code)
	if not contains(r.notes, code) then r.notes[#r.notes + 1] = code end
end

-- 3 and 4: the whole evaluation (see the header).
function UpgradeScore.Evaluate(item, equipped, who, config)
	config = config or UpgradeScore.DefaultConfig()
	who = who or {}
	equipped = equipped or {}
	local ok, code = UpgradeScore.CanUse(item, who.class, who.spec, config)
	if not ok then
		local r = result("NONE", { usable = false, code = code })
		-- Not an equippable item (a token, a recipe): nothing to compare, and the addon cannot tell it is useless.
		if code == "NOT_EQUIPPABLE" then r.verdict, r.usable = "NOT_COMPARABLE", nil end
		return r
	end
	local targets, notesOrCode = UpgradeScore.Targets(item, equipped, who.class, who.spec, config)
	if not targets then return result("NOT_COMPARABLE", { code = notesOrCode }) end
	local r = result("NONE", { level = type(item.level) == "number" and item.level or nil })
	for _, n in ipairs(notesOrCode) do addNote(r, n) end

	if item.effect and item.equipLoc == "INVTYPE_TRINKET" then
		r.verdict, r.code = "NOT_COMPARABLE", "EFFECT_TRINKET"
		return r
	end
	if item.effect then addNote(r, "EFFECT_IGNORED") end

	-- The basis: stats when they are trusted, known on every side and the spec has weights.
	local weights = who.weights
	if weights == nil and who.spec ~= nil then weights = UpgradeScore.DefaultWeights(who.spec) end
	local newStats = UpgradeScore.NormalizeStats(item.stats)
	local pieces = {}
	for i, t in ipairs(targets) do pieces[i] = gather(t, equipped) end
	local basis = "STATS"
	if not config.useStats then
		basis = "ILVL"; addNote(r, "STATS_OFF")
	elseif type(weights) ~= "table" or next(weights) == nil then
		basis = "ILVL"; addNote(r, "NO_WEIGHTS")
	elseif not newStats then
		basis = "ILVL"; addNote(r, "NO_STATS")
	else
		for _, p in ipairs(pieces) do
			if not p.stats then basis = "ILVL"; addNote(r, "NO_STATS") break end
		end
	end

	-- Scores and the worst target.
	local newScore, unscored
	if basis == "STATS" then
		newScore, unscored = UpgradeScore.Score(newStats, weights)
		r.unscored = unscored
		local allZero = newScore == 0
		for _, p in ipairs(pieces) do
			p.score = UpgradeScore.Score(p.stats, weights)
			if p.score ~= 0 then allZero = false end
		end
		if allZero then basis = "ILVL"; addNote(r, "NO_WEIGHTED_STATS") end
	end
	local worst, worstIndex
	for i, p in ipairs(pieces) do
		local value
		if p.empty then
			value = -1 / 0
		elseif basis == "STATS" then
			value = p.score
		else
			value = p.level or 1 / 0
		end
		if worst == nil or value < worst then worst, worstIndex = value, i end
	end
	local target, piece = targets[worstIndex], pieces[worstIndex]
	for _, s in ipairs(target) do r.slots[#r.slots + 1] = s end
	r.basis = basis
	r.equippedLevel = piece.level
	if r.level and piece.level then r.ilvlDelta = r.level - piece.level end

	if piece.empty then
		addNote(r, "EMPTY_SLOT")
		if basis == "STATS" then r.score, r.equippedScore = newScore, 0 end
		r.verdict = "BIG"
		return r
	end

	if basis == "STATS" then
		r.score, r.equippedScore = newScore, piece.score
		if piece.score <= 0 then
			if newScore > 0 then
				addNote(r, "FROM_ZERO"); r.verdict = "BIG"
			else
				r.verdict = "NONE"
			end
			return r
		end
		r.pct = (newScore - piece.score) / piece.score
	else
		if not r.level or not piece.level or piece.level <= 0 then
			r.verdict, r.code = "NOT_COMPARABLE", "NO_ITEM_LEVEL"
			return r
		end
		r.pct = (r.level - piece.level) / piece.level
	end
	r.verdict = UpgradeScore.Verdict(r.pct, config, basis)
	return r
end

-- The wire form of a result (Net/Protocol.lua, SRESP `vd`): a few small fields, codes and integers only.
--   v = verdict, u = false when the character cannot use the item, c = code, b = basis, p = upgrade in permille
--   (74 = +7.4%), l = item-level delta. nil for something that is not a result.
local floor = math.floor
local function whole(n, lo, hi)
	n = n >= 0 and floor(n + 0.5) or -floor(-n + 0.5)
	return n < lo and lo or n > hi and hi or n
end

UpgradeScore.PERMILLE_MAX, UpgradeScore.ILVL_MAX = 100000, 2000

function UpgradeScore.Pack(r)
	if type(r) ~= "table" or type(r.verdict) ~= "string" then return nil end
	local w = { v = r.verdict }
	if r.usable == false then w.u = false end
	if type(r.code) == "string" then w.c = r.code end
	if type(r.basis) == "string" then w.b = r.basis end
	if type(r.pct) == "number" and r.pct == r.pct then
		w.p = whole(r.pct * 1000, -UpgradeScore.PERMILLE_MAX, UpgradeScore.PERMILLE_MAX)
	end
	if type(r.ilvlDelta) == "number" and r.ilvlDelta == r.ilvlDelta then
		w.l = whole(r.ilvlDelta, -UpgradeScore.ILVL_MAX, UpgradeScore.ILVL_MAX)
	end
	return w
end

-- The other way: a wire verdict as the shape of Evaluate's result (verdict, usable, code, basis, pct, ilvlDelta).
function UpgradeScore.Unpack(w)
	if type(w) ~= "table" or type(w.v) ~= "string" then return nil end
	return { verdict = w.v, usable = w.u ~= false, code = w.c, basis = w.b, pct = w.p and w.p / 1000 or nil,
		ilvlDelta = w.l }
end

-- A short debug rendering (tests and /fdcp debug): "BIG STATS +7.4% ilvl +6".
function UpgradeScore.Describe(r)
	local parts = { tostring(r.verdict), tostring(r.basis or "-") }
	if r.pct then parts[#parts + 1] = ("%+.1f%%"):format(r.pct * 100) end
	if r.ilvlDelta then parts[#parts + 1] = ("ilvl %+.0f"):format(r.ilvlDelta) end
	return table.concat(parts, " ")
end

if ns.addon then ns.addon.UpgradeScore = UpgradeScore end   -- also reachable from tests
