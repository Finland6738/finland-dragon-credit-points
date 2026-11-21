-- UpgradeScore (M5-1): can the character use it (proficiency per class, dual wield, class and spec restrictions), the
-- slot it is compared against (rings and trinkets against the worse of the two, two-hand vs main hand + off hand), the
-- weighted stat score, the item-level delta, the verdicts and their thresholds, "not comparable", and the item-level
-- fallback of spike S5's plan B. Pure domain code: no game call is involved.
local function U() return FDCP.UpgradeScore end
local function W() return FDCP.StatWeights end

local ARMOR, WEAPON = 4, 2
local A = { MISC = 0, CLOTH = 1, LEATHER = 2, MAIL = 3, PLATE = 4, SHIELD = 6, LIBRAM = 7, IDOL = 8, TOTEM = 9 }
local Wp = { AXE1H = 0, AXE2H = 1, BOW = 2, MACE1H = 4, POLEARM = 6, SWORD1H = 7, SWORD2H = 8, STAFF = 10, FIST = 13,
	DAGGER = 15, WAND = 19 }
local SLOT = { HEAD = 1, NECK = 2, CHEST = 5, FINGER1 = 11, FINGER2 = 12, TRINKET1 = 13, TRINKET2 = 14, BACK = 15,
	MAINHAND = 16, OFFHAND = 17, RANGED = 18 }

-- Plain weights for exact numbers: one point of STR = 1, of STA = 0.5.
local STR = { STR = 1, STA = 0.5 }

local function item(equipLoc, classID, subclassID, level, stats, extra)
	local t = { equipLoc = equipLoc, classID = classID, subclassID = subclassID, level = level, stats = stats }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

local function plate(loc, level, stats, extra) return item(loc, ARMOR, A.PLATE, level, stats, extra) end
local function ring(level, stats, extra) return item("INVTYPE_FINGER", ARMOR, A.MISC, level, stats, extra) end
local function trinket(level, stats, extra) return item("INVTYPE_TRINKET", ARMOR, A.MISC, level, stats, extra) end
local function weapon(loc, sub, level, stats, extra) return item(loc, WEAPON, sub, level, stats, extra) end

local function eval(it, equipped, who, changes)
	local c = U().DefaultConfig()
	for k, v in pairs(changes or {}) do c[k] = v end
	return U().Evaluate(it, equipped, who, c)
end

local function warrior(weights) return { class = "WARRIOR", spec = 71, weights = weights or STR } end

local function canUse(class, it, spec)
	local ok, code = U().CanUse(it, class, spec)
	return ok and "OK" or code
end

describe("1. can the character use it", function()
	it("armour types follow the class", function()
		local chest = function(sub) return item("INVTYPE_CHEST", ARMOR, sub, 100, {}) end
		eq(canUse("WARRIOR", chest(A.PLATE)), "OK")
		eq(canUse("PALADIN", chest(A.PLATE)), "OK")
		eq(canUse("HUNTER", chest(A.PLATE)), "ARMOR_TYPE")
		eq(canUse("HUNTER", chest(A.MAIL)), "OK")
		eq(canUse("SHAMAN", chest(A.MAIL)), "OK")
		eq(canUse("ROGUE", chest(A.MAIL)), "ARMOR_TYPE")
		eq(canUse("ROGUE", chest(A.LEATHER)), "OK")
		eq(canUse("DRUID", chest(A.LEATHER)), "OK")
		eq(canUse("DRUID", chest(A.MAIL)), "ARMOR_TYPE")
		eq(canUse("PRIEST", chest(A.LEATHER)), "ARMOR_TYPE")
		eq(canUse("MAGE", chest(A.CLOTH)), "OK")
		eq(canUse("WARLOCK", chest(A.CLOTH)), "OK")
		eq(canUse("WARRIOR", chest(A.CLOTH)), "OK")   -- can wear it; the weights say whether it helps
	end)

	it("cloaks, rings, necks, trinkets and held-in-off-hand items fit every class", function()
		for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
			eq(canUse(class, item("INVTYPE_CLOAK", ARMOR, A.CLOTH, 100, {})), "OK")
			eq(canUse(class, ring(100, {})), "OK")
			eq(canUse(class, item("INVTYPE_NECK", ARMOR, A.MISC, 100, {})), "OK")
			eq(canUse(class, trinket(100, {})), "OK")
			eq(canUse(class, item("INVTYPE_HOLDABLE", ARMOR, A.MISC, 100, {})), "OK")
		end
	end)

	it("shields and relics", function()
		local shield = item("INVTYPE_SHIELD", ARMOR, A.SHIELD, 100, {})
		eq(canUse("WARRIOR", shield), "OK")
		eq(canUse("PALADIN", shield), "OK")
		eq(canUse("SHAMAN", shield), "OK")
		eq(canUse("DRUID", shield), "ARMOR_TYPE")
		eq(canUse("ROGUE", shield), "ARMOR_TYPE")
		eq(canUse("PALADIN", item("INVTYPE_RELIC", ARMOR, A.LIBRAM, 100, {})), "OK")
		eq(canUse("DRUID", item("INVTYPE_RELIC", ARMOR, A.LIBRAM, 100, {})), "ARMOR_TYPE")
		eq(canUse("DRUID", item("INVTYPE_RELIC", ARMOR, A.IDOL, 100, {})), "OK")
		eq(canUse("SHAMAN", item("INVTYPE_RELIC", ARMOR, A.TOTEM, 100, {})), "OK")
		eq(canUse("PALADIN", item("INVTYPE_RELIC", ARMOR, A.TOTEM, 100, {})), "ARMOR_TYPE")
	end)

	it("weapon types follow the class", function()
		eq(canUse("PALADIN", weapon("INVTYPE_2HWEAPON", Wp.SWORD2H, 100, {})), "OK")
		eq(canUse("ROGUE", weapon("INVTYPE_2HWEAPON", Wp.SWORD2H, 100, {})), "WEAPON_TYPE")
		eq(canUse("ROGUE", weapon("INVTYPE_WEAPON", Wp.DAGGER, 100, {})), "OK")
		eq(canUse("PALADIN", weapon("INVTYPE_WEAPON", Wp.DAGGER, 100, {})), "WEAPON_TYPE")
		eq(canUse("MAGE", weapon("INVTYPE_WEAPON", Wp.DAGGER, 100, {})), "OK")
		eq(canUse("MAGE", weapon("INVTYPE_WEAPON", Wp.MACE1H, 100, {})), "WEAPON_TYPE")
		eq(canUse("PRIEST", weapon("INVTYPE_WEAPON", Wp.MACE1H, 100, {})), "OK")
		eq(canUse("DRUID", weapon("INVTYPE_2HWEAPON", Wp.POLEARM, 100, {})), "WEAPON_TYPE")
		eq(canUse("DRUID", weapon("INVTYPE_2HWEAPON", Wp.STAFF, 100, {})), "OK")
		eq(canUse("PRIEST", weapon("INVTYPE_RANGEDRIGHT", Wp.WAND, 100, {})), "OK")
		eq(canUse("WARRIOR", weapon("INVTYPE_RANGEDRIGHT", Wp.WAND, 100, {})), "WEAPON_TYPE")
		eq(canUse("ROGUE", weapon("INVTYPE_RANGED", Wp.BOW, 100, {})), "OK")
		eq(canUse("PRIEST", weapon("INVTYPE_RANGED", Wp.BOW, 100, {})), "WEAPON_TYPE")
		eq(canUse("SHAMAN", weapon("INVTYPE_WEAPON", Wp.SWORD1H, 100, {})), "WEAPON_TYPE")
		-- A subclass the tables do not know is never refused.
		eq(canUse("PRIEST", weapon("INVTYPE_WEAPON", 99, 100, {})), "OK")
	end)

	it("an off-hand weapon needs dual wield (the enhancement shaman's talent is per spec)", function()
		local oh = weapon("INVTYPE_WEAPONOFFHAND", Wp.FIST, 100, {})
		eq(canUse("WARRIOR", oh, 72), "OK")
		eq(canUse("ROGUE", oh, 259), "OK")
		eq(canUse("HUNTER", weapon("INVTYPE_WEAPONOFFHAND", Wp.AXE1H, 100, {}), 253), "OK")
		eq(canUse("SHAMAN", oh, 263), "OK")
		eq(canUse("SHAMAN", oh, 262), "DUAL_WIELD")
		eq(canUse("DRUID", oh, 103), "DUAL_WIELD")
		truthy(U().CanDualWield("SHAMAN", 263))
		falsy(U().CanDualWield("SHAMAN", 264))
		falsy(U().CanDualWield("PALADIN", 70))
	end)

	it("class and spec restrictions; tokens are not equippable but not refused", function()
		local tier = plate("INVTYPE_CHEST", 100, {}, { classes = { "PALADIN" } })
		eq(canUse("WARRIOR", tier), "CLASS_RESTRICTED")
		eq(canUse("PALADIN", tier), "OK")
		local bySpec = plate("INVTYPE_CHEST", 100, {}, { specs = { 66 } })
		eq(canUse("PALADIN", bySpec, 70), "SPEC_RESTRICTED")
		eq(canUse("PALADIN", bySpec, 66), "OK")
		eq(canUse("PALADIN", bySpec, nil), "OK")   -- no declared spec: not refused

		local token = { equipLoc = "INVTYPE_NON_EQUIP_IGNORE", classID = 15, subclassID = 0, level = 100,
			classes = { "PALADIN", "PRIEST", "WARLOCK" } }
		local r = eval(token, {}, { class = "PRIEST", spec = 257 })
		eq(r.verdict, "NOT_COMPARABLE")
		eq(r.code, "NOT_EQUIPPABLE")
		isNil(r.usable)   -- the popup must not pass on a token by itself
		r = eval(token, {}, { class = "WARRIOR", spec = 71 })
		eq(r.verdict, "NONE")
		eq(r.code, "CLASS_RESTRICTED")
		eq(r.usable, false)
		eq(canUse("DEATHKNIGHT", ring(100, {})), "UNKNOWN_CLASS")
	end)

	it("an unusable item is NONE with usable = false and its code", function()
		local r = eval(plate("INVTYPE_HEAD", 120, { STR = 200 }), { [SLOT.HEAD] = item("INVTYPE_HEAD", ARMOR, A.CLOTH, 50, {}) },
			{ class = "MAGE", spec = 63 })
		eq(r.verdict, "NONE")
		eq(r.usable, false)
		eq(r.code, "ARMOR_TYPE")
	end)

	it("the proficiency table can be edited through the configuration", function()
		local prof = U().DefaultProficiency()
		prof.ROGUE.weapon.AXE1H = true
		local axe = weapon("INVTYPE_WEAPON", Wp.AXE1H, 100, {})
		eq(canUse("ROGUE", axe), "WEAPON_TYPE")
		truthy(U().CanUse(axe, "ROGUE", 260, { proficiency = prof }))
		-- A fresh copy on every call.
		falsy(U().DefaultProficiency().ROGUE.weapon.AXE1H)
	end)
end)

describe("3. the weighted score", function()
	it("score = Σ weight × value; stats without a weight are listed", function()
		local score, unscored = U().Score({ STR = 10, STA = 4, CRIT = 3 }, { STR = 1, STA = 0.5 })
		near(score, 12)
		deepEq(unscored, { "CRIT" })
	end)

	it("the client's stat keys become short codes (Data/StatWeights.lua)", function()
		local s = U().NormalizeStats({ ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_STAMINA_SHORT = 15, RESISTANCE0_NAME = 900,
			ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 5, ITEM_MOD_SPELL_POWER_SHORT = 3, STR = 1, ITEM_MOD_SOMETHING_NEW = 2,
			junk = "x" })
		deepEq(s, { STR = 21, STA = 15, ARMOR = 900, SP = 8, ITEM_MOD_SOMETHING_NEW = 2 })
		isNil(U().NormalizeStats(nil))
	end)

	it("upgrade % = (new − equipped) / equipped, with the item-level delta", function()
		local r = eval(plate("INVTYPE_HEAD", 126, { STR = 40, STA = 30 }),
			{ [SLOT.HEAD] = plate("INVTYPE_HEAD", 120, { STR = 35, STA = 30 }) }, warrior())
		eq(r.basis, "STATS")
		near(r.score, 55)
		near(r.equippedScore, 50)
		near(r.pct, 0.1)
		eq(r.ilvlDelta, 6)
		eq(r.verdict, "BIG")
		deepEq(r.slots, { SLOT.HEAD })
		eq(U().Describe(r), "BIG STATS +10.0% ilvl +6")
	end)

	it("the stats are read with the client's keys on both sides", function()
		local r = eval(plate("INVTYPE_HEAD", 126, { ITEM_MOD_STRENGTH_SHORT = 40 }),
			{ [SLOT.HEAD] = plate("INVTYPE_HEAD", 120, { ITEM_MOD_STRENGTH_SHORT = 39 }) }, warrior())
		near(r.pct, 1 / 39)
		eq(r.verdict, "SMALL")
	end)

	it("the spec's default weights are used when the character has none", function()
		local who = { class = "MAGE", spec = 63 }
		local r = eval(item("INVTYPE_HEAD", ARMOR, A.CLOTH, 120, { SP = 50, INT = 20 }),
			{ [SLOT.HEAD] = item("INVTYPE_HEAD", ARMOR, A.CLOTH, 120, { STR = 80, AGI = 40 }) }, who)
		eq(r.basis, "STATS")
		eq(r.verdict, "BIG")   -- strength scores nothing for a mage: from zero
		contains(r.notes, "FROM_ZERO")
		near(r.score, 50 * 1.0 + 20 * W().DEFAULT[63].INT)
	end)
end)

describe("4. verdicts and thresholds", function()
	local function headPct(newStr, oldStr, changes)
		return eval(plate("INVTYPE_HEAD", 120, { STR = newStr }), { [SLOT.HEAD] = plate("INVTYPE_HEAD", 120, { STR = oldStr }) },
			warrior(), changes)
	end

	it("BIG at the threshold (preset 5%), SMALL above zero, NONE at zero or below", function()
		eq(headPct(105, 100).verdict, "BIG")
		eq(headPct(104.9, 100).verdict, "SMALL")
		eq(headPct(100.1, 100).verdict, "SMALL")
		eq(headPct(100, 100).verdict, "NONE")
		eq(headPct(90, 100).verdict, "NONE")
		near(headPct(90, 100).pct, -0.1)
	end)

	it("the thresholds are configurable", function()
		eq(headPct(107, 100, { bigThreshold = 0.10 }).verdict, "SMALL")
		eq(headPct(110, 100, { bigThreshold = 0.10 }).verdict, "BIG")
		eq(headPct(100.5, 100, { smallThreshold = 0.01 }).verdict, "NONE")
		eq(headPct(101.5, 100, { smallThreshold = 0.01 }).verdict, "SMALL")
	end)

	it("Verdict on its own, per basis", function()
		local c = U().DefaultConfig()
		c.ilvlBigThreshold = 0.03
		eq(U().Verdict(0.04, c, "STATS"), "SMALL")
		eq(U().Verdict(0.04, c, "ILVL"), "BIG")
		eq(U().Verdict(0, c, "ILVL"), "NONE")
	end)

	it("the configuration is checked", function()
		truthy(U().ValidateConfig(U().DefaultConfig()))
		local c = U().DefaultConfig(); c.bigThreshold = -1
		eq(select(2, U().ValidateConfig(c)), "BAD_THRESHOLD")
		c = U().DefaultConfig(); c.smallThreshold = 0.2
		eq(select(2, U().ValidateConfig(c)), "BAD_THRESHOLD")
		c = U().DefaultConfig(); c.proficiency = "x"
		eq(select(2, U().ValidateConfig(c)), "BAD_PROFICIENCY")
		eq(select(2, U().ValidateConfig(nil)), "BAD_CONFIG")
	end)

	it("an empty slot is a BIG upgrade without a percentage", function()
		local r = eval(plate("INVTYPE_HEAD", 120, { STR = 10 }), {}, warrior())
		eq(r.verdict, "BIG")
		isNil(r.pct)
		contains(r.notes, "EMPTY_SLOT")
		deepEq(r.slots, { SLOT.HEAD })
	end)

	it("shirts and tabards are not comparable", function()
		local r = eval(item("INVTYPE_BODY", ARMOR, A.MISC, 1, {}), {}, warrior())
		eq(r.verdict, "NOT_COMPARABLE")
		eq(r.code, "COSMETIC")
		eq(r.usable, true)
	end)
end)

describe("2. rings and trinkets against the worse of the two", function()
	it("a ring is compared with the worse equipped ring", function()
		local eq_ = { [SLOT.FINGER1] = ring(120, { STR = 30 }), [SLOT.FINGER2] = ring(115, { STR = 20 }) }
		local r = eval(ring(120, { STR = 21 }), eq_, warrior())
		deepEq(r.slots, { SLOT.FINGER2 })
		near(r.pct, 0.05)
		eq(r.verdict, "BIG")      -- big against the worse ring, a loss against the better one
		eq(r.ilvlDelta, 5)
	end)

	it("an empty ring slot is taken first", function()
		local r = eval(ring(100, { STR = 1 }), { [SLOT.FINGER1] = ring(120, { STR = 30 }) }, warrior())
		deepEq(r.slots, { SLOT.FINGER2 })
		eq(r.verdict, "BIG")
		contains(r.notes, "EMPTY_SLOT")
	end)

	it("the same ring already worn is compared with itself", function()
		local eq_ = { [SLOT.FINGER1] = ring(120, { STR = 10 }, { itemID = 501 }), [SLOT.FINGER2] = ring(100, { STR = 5 }) }
		local r = eval(ring(120, { STR = 10 }, { itemID = 501 }), eq_, warrior())
		deepEq(r.slots, { SLOT.FINGER1 })
		eq(r.verdict, "NONE")
		contains(r.notes, "SAME_ITEM_EQUIPPED")
	end)

	it("item-level only: the ring with the lower item level is the worse", function()
		local eq_ = { [SLOT.FINGER1] = ring(110, nil), [SLOT.FINGER2] = ring(120, nil) }
		local r = eval(ring(116, nil), eq_, warrior())
		eq(r.basis, "ILVL")
		deepEq(r.slots, { SLOT.FINGER1 })
		eq(r.ilvlDelta, 6)
		near(r.pct, 6 / 110)
		eq(r.verdict, "BIG")
	end)

	it("trinkets: the worse of the two", function()
		local eq_ = { [SLOT.TRINKET1] = trinket(120, { STR = 40 }), [SLOT.TRINKET2] = trinket(120, { STR = 50 }) }
		local r = eval(trinket(120, { STR = 41 }), eq_, warrior())
		deepEq(r.slots, { SLOT.TRINKET1 })
		eq(r.verdict, "SMALL")
	end)

	it("a trinket with a use effect is not comparable", function()
		local eq_ = { [SLOT.TRINKET1] = trinket(120, { STR = 40 }), [SLOT.TRINKET2] = trinket(120, { STR = 50 }) }
		local r = eval(trinket(130, { STR = 10 }, { effect = true }), eq_, warrior())
		eq(r.verdict, "NOT_COMPARABLE")
		eq(r.code, "EFFECT_TRINKET")
		eq(r.usable, true)
	end)

	it("an equipped effect trinket is kept; with two of them nothing is comparable", function()
		local eq_ = { [SLOT.TRINKET1] = trinket(120, { STR = 60 }), [SLOT.TRINKET2] = trinket(110, {}, { effect = true }) }
		local r = eval(trinket(120, { STR = 61 }), eq_, warrior())
		deepEq(r.slots, { SLOT.TRINKET1 })
		eq(r.verdict, "SMALL")
		contains(r.notes, "EFFECT_TRINKET_KEPT")
		eq_[SLOT.TRINKET1].effect = true
		r = eval(trinket(120, { STR = 61 }), eq_, warrior())
		eq(r.verdict, "NOT_COMPARABLE")
		eq(r.code, "EFFECT_TRINKETS")
	end)

	it("a use effect on another slot is compared on its stats with a note", function()
		local r = eval(plate("INVTYPE_HEAD", 120, { STR = 60 }, { effect = true }),
			{ [SLOT.HEAD] = plate("INVTYPE_HEAD", 120, { STR = 50 }) }, warrior())
		eq(r.verdict, "BIG")
		contains(r.notes, "EFFECT_IGNORED")
	end)
end)

describe("2. two-hand vs main hand + off hand", function()
	local function mh(level, stats) return weapon("INVTYPE_WEAPONMAINHAND", Wp.SWORD1H, level, stats) end
	local function oneH(level, stats, sub) return weapon("INVTYPE_WEAPON", sub or Wp.SWORD1H, level, stats) end
	local function twoH(level, stats) return weapon("INVTYPE_2HWEAPON", Wp.SWORD2H, level, stats) end
	local function shield(level, stats) return item("INVTYPE_SHIELD", ARMOR, A.SHIELD, level, stats) end

	it("a two-hander against main hand + off hand: the stats are summed, the item levels averaged", function()
		local eq_ = { [SLOT.MAINHAND] = mh(120, { STR = 30 }), [SLOT.OFFHAND] = shield(110, { STA = 40 }) }
		local r = eval(twoH(124, { STR = 52 }), eq_, warrior())
		deepEq(r.slots, { SLOT.MAINHAND, SLOT.OFFHAND })
		near(r.equippedScore, 50)
		near(r.pct, 0.04)
		eq(r.verdict, "SMALL")
		eq(r.equippedLevel, 115)
		eq(r.ilvlDelta, 9)
		contains(r.notes, "TWO_HAND_VS_PAIR")
	end)

	it("a two-hander against a two-hander", function()
		local r = eval(twoH(124, { STR = 60 }), { [SLOT.MAINHAND] = twoH(120, { STR = 50 }) }, warrior())
		deepEq(r.slots, { SLOT.MAINHAND, SLOT.OFFHAND })
		near(r.pct, 0.2)
		eq(r.verdict, "BIG")
		eq(#r.notes, 0)
	end)

	it("a two-hander with only a main hand equipped", function()
		local r = eval(twoH(120, { STR = 50 }), { [SLOT.MAINHAND] = mh(120, { STR = 50 }) }, warrior())
		near(r.pct, 0)
		eq(r.verdict, "NONE")
		eq(r.equippedLevel, 120)
	end)

	it("a one-hander against an equipped two-hander is compared alone", function()
		local r = eval(oneH(126, { STR = 30 }), { [SLOT.MAINHAND] = twoH(120, { STR = 50 }) }, warrior())
		deepEq(r.slots, { SLOT.MAINHAND })
		near(r.pct, -0.4)
		eq(r.verdict, "NONE")
		contains(r.notes, "REPLACES_TWO_HAND")
	end)

	it("a shield or an off-hand with a two-hander equipped is not comparable", function()
		local r = eval(shield(126, { STA = 30 }), { [SLOT.MAINHAND] = twoH(120, { STR = 50 }) }, warrior())
		eq(r.verdict, "NOT_COMPARABLE")
		eq(r.code, "TWO_HAND_EQUIPPED")
		r = eval(item("INVTYPE_HOLDABLE", ARMOR, A.MISC, 126, { SP = 30 }),
			{ [SLOT.MAINHAND] = weapon("INVTYPE_2HWEAPON", Wp.STAFF, 120, { SP = 50 }) }, { class = "MAGE", spec = 63 })
		eq(r.code, "TWO_HAND_EQUIPPED")
	end)

	it("a one-hander for a dual wielder: the worse of the two hands", function()
		local rogue = { class = "ROGUE", spec = 260, weights = { AGI = 1 } }
		local eq_ = { [SLOT.MAINHAND] = oneH(120, { AGI = 40 }), [SLOT.OFFHAND] = oneH(115, { AGI = 20 }) }
		local r = eval(oneH(120, { AGI = 30 }), eq_, rogue)
		deepEq(r.slots, { SLOT.OFFHAND })
		near(r.pct, 0.5)
		eq(r.verdict, "BIG")
	end)

	it("a one-hander for a class that does not dual wield: the main hand only", function()
		local pala = { class = "PALADIN", spec = 70, weights = { STR = 1 } }
		local eq_ = { [SLOT.MAINHAND] = oneH(120, { STR = 40 }), [SLOT.OFFHAND] = shield(100, { STR = 5 }) }
		local r = eval(oneH(120, { STR = 30 }), eq_, pala)
		deepEq(r.slots, { SLOT.MAINHAND })
		eq(r.verdict, "NONE")
	end)

	it("a dual-wield class with a shield in the off hand: the main hand only", function()
		local eq_ = { [SLOT.MAINHAND] = oneH(120, { STR = 40 }), [SLOT.OFFHAND] = shield(100, { STA = 2 }) }
		local r = eval(oneH(120, { STR = 41 }), eq_, warrior())
		deepEq(r.slots, { SLOT.MAINHAND })
		eq(r.verdict, "SMALL")
	end)

	it("an off-hand weapon and a shield go to the off hand; a ranged weapon to the ranged slot", function()
		local eq_ = { [SLOT.MAINHAND] = oneH(120, { STR = 40 }), [SLOT.OFFHAND] = oneH(120, { STR = 30 }),
			[SLOT.RANGED] = weapon("INVTYPE_RANGED", Wp.BOW, 120, { AGI = 10 }) }
		local r = eval(weapon("INVTYPE_WEAPONOFFHAND", Wp.FIST, 120, { STR = 33 }), eq_, warrior())
		deepEq(r.slots, { SLOT.OFFHAND })
		near(r.pct, 0.1)
		r = eval(weapon("INVTYPE_RANGED", Wp.BOW, 120, { AGI = 12 }), eq_, { class = "WARRIOR", spec = 71, weights = { AGI = 1 } })
		deepEq(r.slots, { SLOT.RANGED })
		near(r.pct, 0.2)
	end)

	it("empty hands", function()
		local r = eval(twoH(120, { STR = 1 }), {}, warrior())
		eq(r.verdict, "BIG")
		contains(r.notes, "EMPTY_SLOT")
	end)
end)

describe("item-level fallback (plan B of spike S5)", function()
	it("useStats = false: item level only for everybody", function()
		local r = eval(plate("INVTYPE_HEAD", 126, { STR = 10 }), { [SLOT.HEAD] = plate("INVTYPE_HEAD", 120, { STR = 100 }) },
			warrior(), { useStats = false })
		eq(r.basis, "ILVL")
		contains(r.notes, "STATS_OFF")
		near(r.pct, 0.05)
		eq(r.verdict, "BIG")
		isNil(r.score)
	end)

	it("its own threshold", function()
		local new, old = plate("INVTYPE_HEAD", 123, nil), { [SLOT.HEAD] = plate("INVTYPE_HEAD", 120, nil) }
		eq(eval(new, old, warrior()).verdict, "SMALL")   -- +2.5%
		eq(eval(new, old, warrior(), { ilvlBigThreshold = 0.02 }).verdict, "BIG")
		eq(eval(plate("INVTYPE_HEAD", 120, nil), old, warrior()).verdict, "NONE")
		eq(eval(plate("INVTYPE_HEAD", 110, nil), old, warrior()).verdict, "NONE")
	end)

	it("unknown stats on either side", function()
		local r = eval(plate("INVTYPE_HEAD", 126, nil), { [SLOT.HEAD] = plate("INVTYPE_HEAD", 120, { STR = 1 }) }, warrior())
		eq(r.basis, "ILVL"); contains(r.notes, "NO_STATS")
		r = eval(plate("INVTYPE_HEAD", 126, { STR = 1 }), { [SLOT.HEAD] = plate("INVTYPE_HEAD", 120, nil) }, warrior())
		eq(r.basis, "ILVL"); contains(r.notes, "NO_STATS")
	end)

	it("no weights for the spec", function()
		local r = eval(plate("INVTYPE_HEAD", 126, { STR = 1 }), { [SLOT.HEAD] = plate("INVTYPE_HEAD", 120, { STR = 1 }) },
			{ class = "WARRIOR" })
		eq(r.basis, "ILVL"); contains(r.notes, "NO_WEIGHTS")
		r = eval(plate("INVTYPE_HEAD", 126, { STR = 1 }), { [SLOT.HEAD] = plate("INVTYPE_HEAD", 120, { STR = 1 }) },
			{ class = "WARRIOR", spec = 71, weights = {} })
		eq(r.basis, "ILVL"); contains(r.notes, "NO_WEIGHTS")
	end)

	it("no weighted stat on either side", function()
		local r = eval(plate("INVTYPE_HEAD", 126, { INT = 30 }), { [SLOT.HEAD] = plate("INVTYPE_HEAD", 120, { SPI = 30 }) },
			warrior())
		eq(r.basis, "ILVL")
		contains(r.notes, "NO_WEIGHTED_STATS")
		eq(r.verdict, "BIG")
		deepEq(r.unscored, { "INT" })
	end)

	it("without item levels it is not comparable", function()
		local r = eval(plate("INVTYPE_HEAD", nil, nil), { [SLOT.HEAD] = plate("INVTYPE_HEAD", 120, nil) }, warrior())
		eq(r.verdict, "NOT_COMPARABLE")
		eq(r.code, "NO_ITEM_LEVEL")
		r = eval(plate("INVTYPE_HEAD", 120, nil), { [SLOT.HEAD] = plate("INVTYPE_HEAD", nil, nil) }, warrior())
		eq(r.code, "NO_ITEM_LEVEL")
	end)
end)

describe("the default weights (reversible default of issue #2)", function()
	it("every spec of Data/Specs.lua has a row, with its main stat at 1.0", function()
		local MAIN = { TANK = "STA" }
		for _, s in ipairs(FDCP.Specs.LIST) do
			local w = W().Default(s.id)
			notNil(w, "spec " .. s.id)
			local top = 0
			for _, v in pairs(w) do if v > top then top = v end end
			-- Weapon DPS may weigh more than one point of the main stat; the rest never does.
			local best = 0
			for k, v in pairs(w) do if k ~= "DPS" and v > best then best = v end end
			eq(best, 1.0, "spec " .. s.id)
			if MAIN[s.role] then eq(w[MAIN[s.role]], 1.0, "spec " .. s.id) end
		end
		isNil(W().Default(999))
		isNil(W().Default("71"))
	end)

	it("a row is a fresh copy, and the upgrade score is wired to the table", function()
		local w = W().Default(71)
		w.STR = 99
		eq(W().Default(71).STR, 1.0)
		eq(U().DefaultWeights(71).STR, 1.0)
		eq(U().STAT_KEYS.ITEM_MOD_STRENGTH_SHORT, "STR")
	end)

	it("every short code of the weights is one the client's keys map to", function()
		local codes = {}
		for _, code in pairs(W().STATS) do codes[code] = true end
		for id, row in pairs(W().DEFAULT) do
			for code in pairs(row) do truthy(codes[code], ("spec %d: %s"):format(id, code)) end
		end
	end)
end)

-- The step's "done when": verdicts for a table of known item pairs per class (default weights of the declared spec).
describe("known item pairs per class", function()
	local CASES = {
		{ "Arms warrior: plate helm, more strength and hit", { class = "WARRIOR", spec = 71 },
			plate("INVTYPE_HEAD", 125, { STR = 40, STA = 30, HIT = 15 }),
			{ [SLOT.HEAD] = plate("INVTYPE_HEAD", 120, { STR = 35, STA = 30, HIT = 10 }) }, "BIG" },
		{ "Protection warrior: same item level, stamina for defense", { class = "WARRIOR", spec = 73 },
			plate("INVTYPE_CHEST", 120, { STA = 44, DEF = 20, ARMOR = 1000 }),
			{ [SLOT.CHEST] = plate("INVTYPE_CHEST", 120, { STA = 50, DEF = 12, ARMOR = 1000 }) }, "SMALL" },
		{ "Holy paladin: plate with strength is no upgrade", { class = "PALADIN", spec = 65 },
			plate("INVTYPE_HEAD", 130, { STR = 50, STA = 40 }),
			{ [SLOT.HEAD] = plate("INVTYPE_HEAD", 120, { INT = 30, SP = 40, STA = 20 }) }, "NONE" },
		{ "Hunter: plate is unusable", { class = "HUNTER", spec = 254 },
			plate("INVTYPE_HEAD", 130, { AGI = 50 }),
			{ [SLOT.HEAD] = item("INVTYPE_HEAD", ARMOR, A.MAIL, 120, { AGI = 30 }) }, "NONE", false },
		{ "Combat rogue: a better off-hand dagger", { class = "ROGUE", spec = 260 },
			weapon("INVTYPE_WEAPON", Wp.DAGGER, 125, { AGI = 15, DPS = 60 }),
			{ [SLOT.MAINHAND] = weapon("INVTYPE_WEAPON", Wp.SWORD1H, 125, { AGI = 20, DPS = 70 }),
				[SLOT.OFFHAND] = weapon("INVTYPE_WEAPON", Wp.DAGGER, 115, { AGI = 10, DPS = 55 }) }, "BIG" },
		{ "Holy priest: a ring with a little more healing", { class = "PRIEST", spec = 257 },
			ring(120, { INT = 12, SP = 30, MP5 = 5 }),
			{ [SLOT.FINGER1] = ring(120, { INT = 12, SP = 29, MP5 = 5 }), [SLOT.FINGER2] = ring(125, { INT = 15, SP = 40 }) }, "SMALL" },
		{ "Enhancement shaman: a staff against two axes", { class = "SHAMAN", spec = 263 },
			weapon("INVTYPE_2HWEAPON", Wp.STAFF, 125, { STR = 30, DPS = 90 }),
			{ [SLOT.MAINHAND] = weapon("INVTYPE_WEAPON", Wp.AXE1H, 120, { STR = 15, DPS = 60 }),
				[SLOT.OFFHAND] = weapon("INVTYPE_WEAPON", Wp.AXE1H, 120, { STR = 15, DPS = 60 }) }, "NONE" },
		{ "Fire mage: a use-effect trinket", { class = "MAGE", spec = 63 },
			trinket(130, { SP = 20 }, { effect = true }),
			{ [SLOT.TRINKET1] = trinket(120, { SP = 30 }), [SLOT.TRINKET2] = trinket(120, { HIT = 20 }) }, "NOT_COMPARABLE" },
		{ "Affliction warlock: a wand with more spell power", { class = "WARLOCK", spec = 265 },
			weapon("INVTYPE_RANGEDRIGHT", Wp.WAND, 120, { SP = 20, STA = 10 }),
			{ [SLOT.RANGED] = weapon("INVTYPE_RANGEDRIGHT", Wp.WAND, 110, { SP = 12, STA = 10 }) }, "BIG" },
		{ "Feral druid: a slightly better cloak (cloaks are cloth for every class)", { class = "DRUID", spec = 103 },
			item("INVTYPE_CLOAK", ARMOR, A.CLOTH, 125, { AGI = 20, STA = 15 }),
			{ [SLOT.BACK] = item("INVTYPE_CLOAK", ARMOR, A.CLOTH, 120, { AGI = 19, STA = 15 }) }, "SMALL" },
		{ "Restoration druid: an idol in an empty relic slot", { class = "DRUID", spec = 105 },
			item("INVTYPE_RELIC", ARMOR, A.IDOL, 120, { HEAL = 20 }), {}, "BIG" },
	}
	for _, c in ipairs(CASES) do
		it(c[1], function()
			local r = U().Evaluate(c[3], c[4], c[2])
			eq(r.verdict, c[5], U().Describe(r))
			if c[6] ~= nil then eq(r.usable, c[6]) end
		end)
	end
end)
