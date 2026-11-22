-- UpgradeScore: is an item an upgrade for this character, and how big (docs/ANALISI.md §5.1, §5.3; M5-1, rewritten by M7-5c).
-- Pure Lua 5.1: it never calls the game. The inventory adapter reads the item and the worn pieces (the gear snapshot taken
-- at the encounter, Adapters/GearSnapshot.lua) and hands them over as plain tables; this file only compares codes and numbers.
--
-- The owner's rule of 2026-11-22 (M7-5c) replaced the stat weights of M5-1 / M5-3: the badge is the gap between the item's
-- quality and the worn piece's, read in three tiers, with the item-level difference beside it. The questions:
--   1. Can the character use it?  The proficiency table per class (armour and weapon types, shields, relics, dual wield),
--      the item's class restriction and spec list when the adapter knows them. An unusable item has `usable = false` and a
--      code; its verdict is NONE (the popup preselects Pass).
--   2. Against what?  The slot from `equipLoc`: rings and trinkets against the worse of the two worn (an empty slot first,
--      the same item id when it is already worn), a two-hander against main hand + off hand, a one-hander against the worse
--      of the two hands only while the character dual wields, a one-hander against a worn two-hander alone.
--   3. How big?  Each piece has a grade (Grade): 3 = epic (purple) or better of the current season, 2 = rare (blue), or an
--      epic of an older season (its item level is under the current season's band: "new raids", an old purple counts one
--      step below, like a blue), 1 = uncommon (green) or lower, 0 = an empty slot. The step is the item's grade minus the
--      worn one's: 2 or more = MAJOR, 1 = MEDIUM, 0 or less = MINOR. So a purple over a purple of the same season is a minor
--      upgrade, over a blue (or an old purple) a medium one, over a green or an empty slot a major one.
--   4. Is it better at all?  An item with a lower item level than the worn piece, or the same level and no step up, is NONE
--      ("No upgrade"). The item-level difference always goes with the verdict ("Medium upgrade · ilvl +13").
-- The badge informs the player, the master looter and the council: it never changes the winner (§3.3).
--
-- Input:
--   item     = { itemID?, equipLoc = "INVTYPE_...", classID?, subclassID?, quality?, level?, classes? = { "PALADIN", ... },
--                specs? = { specID, ... } }
--   equipped = { [inventory slot id] = { itemID?, equipLoc?, quality?, level? } } (missing slot = empty)
--   who      = { class = "WARRIOR", spec = specID? }
--   opts     = { band = { min, max } | nil (the current season's item-level band, Domain/Season.lua; nil: every epic counts
--                as the current season's), proficiency = table | nil (nil: DefaultProficiency()) }
--
-- Output of UpgradeScore.Evaluate: codes and numbers only, never sentences (the locales give the words):
--   { verdict = "MAJOR" | "MEDIUM" | "MINOR" | "NONE" | "NOT_COMPARABLE", usable = true | false | nil (nil: not an
--     equippable item, such as a token: the addon cannot tell), code = refusal / not-comparable code, or EMPTY_SLOT | nil,
--     ilvlDelta = n | nil, level = n | nil, equippedLevel = n | nil, grade = n | nil (the item's), equippedGrade = n | nil,
--     slots = { slot ids }, notes = { code, ... } }
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local UpgradeScore = {}
ns.UpgradeScore, ns.modules.UpgradeScore = UpgradeScore, UpgradeScore

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local sort, floor = table.sort, math.floor

UpgradeScore.VERDICTS = { "MAJOR", "MEDIUM", "MINOR", "NONE", "NOT_COMPARABLE" }
local VALID_VERDICT = { MAJOR = true, MEDIUM = true, MINOR = true, NONE = true, NOT_COMPARABLE = true }
UpgradeScore.VALID_VERDICT = VALID_VERDICT

-- Item qualities (Enum.ItemQuality): 2 = uncommon (green), 3 = rare (blue), 4 = epic (purple), 5 = legendary.
UpgradeScore.QUALITY = { UNCOMMON = 2, RARE = 3, EPIC = 4 }
-- The grades of Grade(): an empty slot, green or lower, blue (or an older season's purple), purple of the current season.
UpgradeScore.GRADE = { EMPTY = 0, LOW = 1, RARE = 2, EPIC = 3 }
-- The bounds of an item-level band (the Season window's fields).
UpgradeScore.BAND_MIN, UpgradeScore.BAND_MAX = 1, 2000

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


-- The rules' section "upgrade" (Domain/Rules.lua): the guild's switches, written by the Guild Master like the rest of the
-- rules and read by every client.
--   enabled   false = the popup shows no badge and the responses carry none
--   autoPass  true = an item the character cannot use is preselected on Pass (nothing is sent by itself)
-- A fresh copy on every call.
function UpgradeScore.DefaultRules()
	return { enabled = true, autoPass = true }
end

-- The keys the section had before M7-5c (the stat-weight thresholds): rules written by an older addon still carry them, and
-- Domain/Rules.lua drops them when it reads the rules.
UpgradeScore.RETIRED_RULES = { useStats = true, bigThreshold = true, smallThreshold = true, ilvlBigThreshold = true }

local RULE_FIELDS = { enabled = true, autoPass = true }

-- Checks the section: true, or false and a sorted list of codes (a field name, or "unknown:<field>").
function UpgradeScore.ValidateRules(c)
	if type(c) ~= "table" then return false, { "upgrade" } end
	local p = {}
	for _, k in ipairs({ "enabled", "autoPass" }) do
		if type(c[k]) ~= "boolean" then p[#p + 1] = k end
	end
	for k in pairs(c) do
		if not RULE_FIELDS[k] then p[#p + 1] = "unknown:" .. tostring(k) end
	end
	sort(p)
	return #p == 0, p
end

-- An item-level band { min, max } checked: a copy, or nil (whole numbers, BAND_MIN <= min <= max <= BAND_MAX).
function UpgradeScore.Band(b)
	if type(b) ~= "table" then return nil end
	local lo, hi = b.min, b.max
	local function whole(n)
		return type(n) == "number" and n == n and n == floor(n) and n >= UpgradeScore.BAND_MIN and n <= UpgradeScore.BAND_MAX
	end
	if not whole(lo) or not whole(hi) or lo > hi then return nil end
	return { min = lo, max = hi }
end

local DEFAULT_PROFICIENCY = UpgradeScore.DefaultProficiency()

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

local function isTwoHand(piece)
	return piece ~= nil and piece.equipLoc == "INVTYPE_2HWEAPON"
end

local function isWeapon(piece)
	local hand = piece and WEAPON_LOC[piece.equipLoc]
	return hand == "1H" or hand == "MH" or hand == "OH" or hand == "2H"
end

-- 2. Against what? Returns a list of candidate targets, each a list of slot ids whose pieces are read together (a
-- two-hander against main hand + off hand is one target with two slots: the lower grade, the average item level), plus notes; or nil and a NOT_COMPARABLE code. The caller
-- picks the worst target (Evaluate: the lowest grade, then the lowest item level).
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
		for _, s in ipairs(slots) do out[#out + 1] = { s } end
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

-- An epic of an older season: its item level is under the current season's band. Without a band (the Guild Master has not
-- set one) or without a level, an epic counts as the current season's.
function UpgradeScore.IsOldSeason(level, band)
	band = UpgradeScore.Band(band)
	return band ~= nil and type(level) == "number" and level < band.min
end

-- The grade of a piece (see the header): 0 empty, 1 green or lower, 2 blue or an older season's purple, 3 purple (or
-- better) of the current season; nil when the quality is not known (the client has not loaded the item yet).
function UpgradeScore.Grade(piece, band)
	if piece == nil then return UpgradeScore.GRADE.EMPTY end
	local q = piece.quality
	if type(q) ~= "number" then return nil end
	if q >= UpgradeScore.QUALITY.EPIC then
		if UpgradeScore.IsOldSeason(piece.level, band) then return UpgradeScore.GRADE.RARE end
		return UpgradeScore.GRADE.EPIC
	end
	if q == UpgradeScore.QUALITY.RARE then return UpgradeScore.GRADE.RARE end
	return UpgradeScore.GRADE.LOW
end

-- The tier of a step (the item's grade minus the worn one's): 2 or more MAJOR, 1 MEDIUM, 0 or less MINOR.
function UpgradeScore.Tier(step)
	if step >= 2 then return "MAJOR" end
	if step == 1 then return "MEDIUM" end
	return "MINOR"
end

local function result(verdict, extra)
	local r = { verdict = verdict, usable = true, slots = {}, notes = {} }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end

local function addNote(r, code)
	if not contains(r.notes, code) then r.notes[#r.notes + 1] = code end
end

-- The worn pieces of a target: the lowest grade among them (nil when one is not known), their average item level (nil when
-- one is not known), and whether every slot is empty.
local function gather(target, equipped, band)
	local grade, level, levels, worn, known = nil, 0, 0, 0, true
	for _, s in ipairs(target) do
		local piece = equipped[s]
		if piece then
			worn = worn + 1
			local g = UpgradeScore.Grade(piece, band)
			if g == nil then known = false elseif grade == nil or g < grade then grade = g end
			if type(piece.level) == "number" and level then
				level, levels = level + piece.level, levels + 1
			else
				level = nil
			end
		end
	end
	if worn == 0 then return { empty = true, grade = UpgradeScore.GRADE.EMPTY } end
	return { grade = known and grade or nil, level = level and levels > 0 and level / levels or nil }
end

-- The whole evaluation (see the header).
function UpgradeScore.Evaluate(item, equipped, who, opts)
	opts = opts or {}
	who = who or {}
	equipped = equipped or {}
	local config = { proficiency = opts.proficiency }
	local band = UpgradeScore.Band(opts.band)
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
	r.grade = UpgradeScore.Grade(item, band)
	if r.grade == nil then
		r.verdict, r.code = "NOT_COMPARABLE", "NO_QUALITY"
		return r
	end
	if r.grade == UpgradeScore.GRADE.RARE and type(item.quality) == "number" and item.quality >= UpgradeScore.QUALITY.EPIC then
		addNote(r, "ITEM_OLD_SEASON")
	end

	-- The worst target: an empty one first, then the lowest grade, then the lowest item level.
	local pieces, worstIndex = {}, nil
	for i, t in ipairs(targets) do
		local p = gather(t, equipped, band)
		pieces[i] = p
		if p.grade == nil then
			r.verdict, r.code = "NOT_COMPARABLE", "NO_QUALITY"
			for _, s in ipairs(t) do r.slots[#r.slots + 1] = s end
			return r
		end
		local w = worstIndex and pieces[worstIndex]
		if not w or p.grade < w.grade or (p.grade == w.grade and (p.level or 1 / 0) < (w.level or 1 / 0)) then
			worstIndex = i
		end
	end
	local target, piece = targets[worstIndex], pieces[worstIndex]
	for _, s in ipairs(target) do r.slots[#r.slots + 1] = s end
	r.equippedGrade = piece.grade

	if piece.empty then
		addNote(r, "EMPTY_SLOT")
		r.verdict, r.code = "MAJOR", "EMPTY_SLOT"
		return r
	end
	r.equippedLevel = piece.level
	if piece.grade == UpgradeScore.GRADE.RARE then
		for _, s in ipairs(target) do
			local p = equipped[s]
			if p and type(p.quality) == "number" and p.quality >= UpgradeScore.QUALITY.EPIC then addNote(r, "OLD_SEASON") end
		end
	end
	if r.level and piece.level then r.ilvlDelta = r.level - piece.level end

	local step = r.grade - piece.grade
	if r.ilvlDelta == nil then
		-- no item level on one side: the grades alone can still tell a step up, never "worse"
		if step <= 0 then
			r.verdict, r.code = "NOT_COMPARABLE", "NO_ITEM_LEVEL"
			return r
		end
	elseif r.ilvlDelta < 0 or (r.ilvlDelta == 0 and step <= 0) then
		r.verdict = "NONE"
		return r
	end
	r.verdict = UpgradeScore.Tier(step)
	return r
end

-- The wire form of a result (Net/Protocol.lua, SRESP `vd`): a few small fields, codes and integers only.
--   v = verdict, u = false when the character cannot use the item, c = code, l = item-level delta. nil for something that is
--   not a result. The `b` (basis) and `p` (percent) of the stat-weight verdicts before M7-5c are gone.
local function whole(n, lo, hi)
	n = n >= 0 and floor(n + 0.5) or -floor(-n + 0.5)
	return n < lo and lo or n > hi and hi or n
end

UpgradeScore.ILVL_MAX = 2000

function UpgradeScore.Pack(r)
	if type(r) ~= "table" or not VALID_VERDICT[r.verdict] then return nil end
	local w = { v = r.verdict }
	if r.usable == false then w.u = false end
	if type(r.code) == "string" then w.c = r.code end
	if type(r.ilvlDelta) == "number" and r.ilvlDelta == r.ilvlDelta then
		w.l = whole(r.ilvlDelta, -UpgradeScore.ILVL_MAX, UpgradeScore.ILVL_MAX)
	end
	return w
end

-- The other way: a wire verdict as the shape of Evaluate's result (verdict, usable, code, ilvlDelta). A verdict code this
-- version does not know (the BIG / SMALL of a client older than M7-5c) gives nil: an old client's badge is not shown.
function UpgradeScore.Unpack(w)
	if type(w) ~= "table" or not VALID_VERDICT[w.v] then return nil end
	return { verdict = w.v, usable = w.u ~= false, code = w.c, ilvlDelta = w.l }
end

-- A short debug rendering (tests and /fdcp debug): "MEDIUM ilvl +13".
function UpgradeScore.Describe(r)
	local parts = { tostring(r.verdict) }
	if r.usable == false then parts[#parts + 1] = "unusable" end
	if r.code then parts[#parts + 1] = tostring(r.code) end
	if r.ilvlDelta then parts[#parts + 1] = ("ilvl %+.0f"):format(r.ilvlDelta) end
	return table.concat(parts, " ")
end

if ns.addon then ns.addon.UpgradeScore = UpgradeScore end   -- also reachable from tests
