-- UpgradeScore (M5-1, rewritten by M7-5c): can the character use it (proficiency per class, dual wield, class and spec
-- restrictions), the slot it is compared against (rings and trinkets against the worse of the two, two-hand vs main hand +
-- off hand), and the owner's tier rule of 2026-11-22: purple over purple of the same season = minor, over blue = medium,
-- over green or an empty slot = major, an older season's purple (under the current season's item-level band) counts like a
-- blue, always with the item-level difference; a worse item is "no upgrade". Pure domain code: no game call is involved.
local function U() return FDCP.UpgradeScore end

local ARMOR, WEAPON = 4, 2
local A = { MISC = 0, CLOTH = 1, LEATHER = 2, MAIL = 3, PLATE = 4, SHIELD = 6, LIBRAM = 7, IDOL = 8, TOTEM = 9 }
local Wp = { AXE1H = 0, AXE2H = 1, BOW = 2, MACE1H = 4, POLEARM = 6, SWORD1H = 7, SWORD2H = 8, STAFF = 10, FIST = 13,
	DAGGER = 15, WAND = 19 }
local SLOT = { HEAD = 1, NECK = 2, CHEST = 5, FINGER1 = 11, FINGER2 = 12, TRINKET1 = 13, TRINKET2 = 14, BACK = 15,
	MAINHAND = 16, OFFHAND = 17, RANGED = 18 }
local Q = { GREEN = 2, BLUE = 3, PURPLE = 4, ORANGE = 5, WHITE = 1 }

-- The season's item-level band of the examples: this season's epics are 200-226.
local BAND = { min = 200, max = 226 }

-- `extra` may hold quality (default purple), itemID, classes, specs. The fifth argument (the stats of M5-1) is ignored.
local function item(equipLoc, classID, subclassID, level, _, extra)
	local t = { equipLoc = equipLoc, classID = classID, subclassID = subclassID, level = level, quality = Q.PURPLE }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

local function plate(loc, level, stats, extra) return item(loc, ARMOR, A.PLATE, level, stats, extra) end
local function ring(level, stats, extra) return item("INVTYPE_FINGER", ARMOR, A.MISC, level, stats, extra) end
local function trinket(level, stats, extra) return item("INVTYPE_TRINKET", ARMOR, A.MISC, level, stats, extra) end
local function weapon(loc, sub, level, stats, extra) return item(loc, WEAPON, sub, level, stats, extra) end
local function q(quality, extra)
	local t = { quality = quality }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

local function eval(it, equipped, who, opts)
	opts = opts or {}
	if opts.band == nil and not opts.noBand then opts.band = BAND end
	return U().Evaluate(it, equipped, who, opts)
end

local function warrior() return { class = "WARRIOR", spec = 71 } end

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

describe("the tiers (owner decision of 2026-11-22)", function()
	local function head(level, quality) return plate("INVTYPE_HEAD", level, nil, { quality = quality }) end
	local function vsHead(worn) return eval(head(226), { [SLOT.HEAD] = worn }, warrior()) end

	it("purple over purple of the same season: minor upgrade, with the item-level difference", function()
		local r = vsHead(head(213, Q.PURPLE))
		eq(r.verdict, "MINOR"); eq(r.usable, true)
		eq(r.ilvlDelta, 13); eq(r.level, 226); eq(r.equippedLevel, 213)
		eq(r.grade, 3); eq(r.equippedGrade, 3)
		deepEq(r.slots, { SLOT.HEAD })
		eq(U().Describe(r), "MINOR ilvl +13")
	end)

	it("purple over blue: medium upgrade", function()
		local r = vsHead(head(190, Q.BLUE))
		eq(r.verdict, "MEDIUM"); eq(r.ilvlDelta, 36); eq(r.equippedGrade, 2)
	end)

	it("purple over green or lower: major upgrade", function()
		eq(vsHead(head(150, Q.GREEN)).verdict, "MAJOR")
		eq(vsHead(head(150, Q.WHITE)).verdict, "MAJOR")
		eq(vsHead(head(150, 0)).verdict, "MAJOR", "a grey piece too")
	end)

	it("an empty slot: major upgrade, without an item-level difference", function()
		local r = eval(head(226), {}, warrior())
		eq(r.verdict, "MAJOR"); eq(r.code, "EMPTY_SLOT"); contains(r.notes, "EMPTY_SLOT")
		isNil(r.ilvlDelta); eq(r.equippedGrade, 0)
		eq(r.usable, true)
	end)

	it("new raids: a purple of an older season counts like a blue (medium)", function()
		local r = vsHead(head(187, Q.PURPLE))   -- under the band's 200: last season's epic
		eq(r.verdict, "MEDIUM"); eq(r.ilvlDelta, 39); eq(r.equippedGrade, 2)
		contains(r.notes, "OLD_SEASON")
		-- at the band's minimum it is this season's
		eq(vsHead(head(200, Q.PURPLE)).verdict, "MINOR")
	end)

	it("an older season's purple under a green or empty slot is still a step up", function()
		local old = head(187, Q.PURPLE)
		local r = eval(old, { [SLOT.HEAD] = head(150, Q.GREEN) }, warrior())
		eq(r.verdict, "MEDIUM", "grade 2 over grade 1")
		contains(r.notes, "ITEM_OLD_SEASON")
		eq(eval(old, { [SLOT.HEAD] = head(180, Q.BLUE) }, warrior()).verdict, "MINOR", "old purple over blue: same grade")
		eq(eval(old, {}, warrior()).verdict, "MAJOR")
	end)

	it("without a band every purple counts as the current season's", function()
		local r = eval(head(226), { [SLOT.HEAD] = head(187, Q.PURPLE) }, warrior(), { noBand = true })
		eq(r.verdict, "MINOR")
		eq(eval(head(226), { [SLOT.HEAD] = head(187, Q.PURPLE) }, warrior(), { band = { min = 300, max = 200 } }).verdict,
			"MINOR", "a damaged band is no band")
	end)

	it("a legendary counts like a purple", function()
		eq(vsHead(head(220, Q.ORANGE)).verdict, "MINOR")
	end)

	it("a worse item is no upgrade, whatever the colours", function()
		local r = vsHead(head(230, Q.PURPLE))
		eq(r.verdict, "NONE"); eq(r.ilvlDelta, -4); eq(r.usable, true)
		eq(vsHead(head(230, Q.BLUE)).verdict, "NONE", "a blue above the item's level")
		eq(vsHead(head(226, Q.PURPLE)).verdict, "NONE", "the same level, the same grade")
		eq(vsHead(head(226, Q.BLUE)).verdict, "MEDIUM", "the same level, a step up")
	end)

	it("a blue item over a green one is medium; over a blue one minor", function()
		local blue = plate("INVTYPE_HEAD", 190, nil, { quality = Q.BLUE })
		eq(eval(blue, { [SLOT.HEAD] = head(150, Q.GREEN) }, warrior()).verdict, "MEDIUM")
		eq(eval(blue, { [SLOT.HEAD] = head(180, Q.BLUE) }, warrior()).verdict, "MINOR")
		eq(eval(blue, { [SLOT.HEAD] = head(150, Q.WHITE) }, warrior()).verdict, "MEDIUM")
	end)

	it("an unknown quality is not comparable (the client has not loaded the item)", function()
		local r = vsHead({ equipLoc = "INVTYPE_HEAD", level = 200 })
		eq(r.verdict, "NOT_COMPARABLE"); eq(r.code, "NO_QUALITY")
		r = eval(plate("INVTYPE_HEAD", 226, nil, { quality = false }), {}, warrior())
		eq(r.verdict, "NOT_COMPARABLE"); eq(r.code, "NO_QUALITY")
	end)

	it("without item levels a step up still shows, a same-grade piece is not comparable", function()
		local r = eval(plate("INVTYPE_HEAD", nil), { [SLOT.HEAD] = q(Q.GREEN, { equipLoc = "INVTYPE_HEAD" }) }, warrior())
		eq(r.verdict, "MAJOR"); isNil(r.ilvlDelta)
		r = eval(plate("INVTYPE_HEAD", nil), { [SLOT.HEAD] = q(Q.PURPLE, { equipLoc = "INVTYPE_HEAD" }) }, warrior(), { noBand = true })
		eq(r.verdict, "NOT_COMPARABLE"); eq(r.code, "NO_ITEM_LEVEL")
	end)

	it("Tier maps the steps", function()
		eq(U().Tier(3), "MAJOR"); eq(U().Tier(2), "MAJOR"); eq(U().Tier(1), "MEDIUM"); eq(U().Tier(0), "MINOR")
		eq(U().Tier(-1), "MINOR")
	end)

	it("Grade and the band", function()
		eq(U().Grade(nil, BAND), 0)
		eq(U().Grade(q(Q.GREEN), BAND), 1)
		eq(U().Grade(q(Q.BLUE, { level = 300 }), BAND), 2)
		eq(U().Grade(q(Q.PURPLE, { level = 199 }), BAND), 2)
		eq(U().Grade(q(Q.PURPLE, { level = 200 }), BAND), 3)
		eq(U().Grade(q(Q.PURPLE, { level = 250 }), BAND), 3, "above the band: not older")
		eq(U().Grade(q(Q.PURPLE), BAND), 3, "no level: the current season")
		isNil(U().Grade({}, BAND))
		truthy(U().IsOldSeason(199, BAND)); falsy(U().IsOldSeason(199, nil))
		deepEq(U().Band({ min = 200, max = 226 }), { min = 200, max = 226 })
		deepEq(U().Band({ min = 200, max = 200 }), { min = 200, max = 200 })
		isNil(U().Band({ min = 227, max = 226 })); isNil(U().Band({ min = 0, max = 10 }))
		isNil(U().Band({ min = 200.5, max = 226 })); isNil(U().Band({ min = 200, max = 2001 })); isNil(U().Band("x"))
	end)

	it("an unusable item stays 'not usable', whatever the slot holds", function()
		local r = eval(item("INVTYPE_HEAD", ARMOR, A.PLATE, 226), {}, { class = "MAGE", spec = 63 })
		eq(r.verdict, "NONE"); eq(r.usable, false); eq(r.code, "ARMOR_TYPE")
	end)

	it("shirts and tabards are not comparable", function()
		local r = eval(item("INVTYPE_TABARD", ARMOR, A.MISC, 1), {}, warrior())
		eq(r.verdict, "NOT_COMPARABLE"); eq(r.code, "COSMETIC")
	end)
end)

describe("rings and trinkets against the worse of the two", function()
	it("a ring is compared with the worse worn ring: the lower grade first", function()
		local r = eval(ring(226), { [SLOT.FINGER1] = ring(213), [SLOT.FINGER2] = ring(220, nil, { quality = Q.BLUE }) }, warrior())
		deepEq(r.slots, { SLOT.FINGER2 }); eq(r.verdict, "MEDIUM"); eq(r.ilvlDelta, 6)
	end)

	it("with the same grade, the lower item level", function()
		local r = eval(ring(226), { [SLOT.FINGER1] = ring(220), [SLOT.FINGER2] = ring(205) }, warrior())
		deepEq(r.slots, { SLOT.FINGER2 }); eq(r.verdict, "MINOR"); eq(r.ilvlDelta, 21)
	end)

	it("an empty ring slot is taken first", function()
		local r = eval(ring(226), { [SLOT.FINGER1] = ring(213) }, warrior())
		deepEq(r.slots, { SLOT.FINGER2 }); eq(r.verdict, "MAJOR"); eq(r.code, "EMPTY_SLOT")
	end)

	it("the same ring already worn is compared with itself", function()
		local r = eval(ring(226, nil, { itemID = 7 }), { [SLOT.FINGER1] = ring(150, nil, { quality = Q.GREEN }),
			[SLOT.FINGER2] = ring(220, nil, { itemID = 7 }) }, warrior())
		deepEq(r.slots, { SLOT.FINGER2 }); contains(r.notes, "SAME_ITEM_EQUIPPED"); eq(r.verdict, "MINOR")
	end)

	it("trinkets: the worse of the two, an older season's purple counting as a blue", function()
		local r = eval(trinket(226), { [SLOT.TRINKET1] = trinket(213), [SLOT.TRINKET2] = trinket(190) }, warrior())
		deepEq(r.slots, { SLOT.TRINKET2 }); eq(r.verdict, "MEDIUM"); contains(r.notes, "OLD_SEASON")
		r = eval(trinket(226), { [SLOT.TRINKET1] = trinket(150, nil, { quality = Q.GREEN }), [SLOT.TRINKET2] = trinket(190) },
			warrior())
		deepEq(r.slots, { SLOT.TRINKET1 }); eq(r.verdict, "MAJOR")
	end)

	it("one ring of unknown quality makes the comparison wait", function()
		local r = eval(ring(226), { [SLOT.FINGER1] = ring(213), [SLOT.FINGER2] = { equipLoc = "INVTYPE_FINGER", level = 210 } },
			warrior())
		eq(r.verdict, "NOT_COMPARABLE"); eq(r.code, "NO_QUALITY")
	end)
end)

describe("two-hand vs main hand + off hand", function()
	local function twoHander(level, quality) return weapon("INVTYPE_2HWEAPON", Wp.SWORD2H, level, nil, { quality = quality }) end
	local function oneHander(level, quality) return weapon("INVTYPE_WEAPON", Wp.SWORD1H, level, nil, { quality = quality }) end
	local function shield(level, quality) return item("INVTYPE_SHIELD", ARMOR, A.SHIELD, level, nil, { quality = quality }) end

	it("a two-hander against main hand + off hand: the lower grade, the average item level", function()
		local r = eval(twoHander(226), { [SLOT.MAINHAND] = oneHander(213), [SLOT.OFFHAND] = shield(180, Q.BLUE) }, warrior())
		deepEq(r.slots, { SLOT.MAINHAND, SLOT.OFFHAND }); contains(r.notes, "TWO_HAND_VS_PAIR")
		eq(r.verdict, "MEDIUM", "the blue shield sets the grade")
		near(r.equippedLevel, (213 + 180) / 2); near(r.ilvlDelta, 226 - (213 + 180) / 2)
	end)

	it("a two-hander against a two-hander", function()
		local r = eval(twoHander(226), { [SLOT.MAINHAND] = twoHander(213) }, warrior())
		eq(r.verdict, "MINOR"); eq(r.ilvlDelta, 13)
	end)

	it("a two-hander with only a main hand worn", function()
		local r = eval(twoHander(226), { [SLOT.MAINHAND] = oneHander(150, Q.GREEN) }, warrior())
		eq(r.verdict, "MAJOR"); eq(r.ilvlDelta, 76)
	end)

	it("a one-hander against a worn two-hander is compared with it alone", function()
		local r = eval(oneHander(226), { [SLOT.MAINHAND] = twoHander(190, Q.BLUE) }, { class = "PALADIN", spec = 70 })
		deepEq(r.slots, { SLOT.MAINHAND }); contains(r.notes, "REPLACES_TWO_HAND"); eq(r.verdict, "MEDIUM")
	end)

	it("a shield with a two-hander worn is not comparable", function()
		local r = eval(shield(226), { [SLOT.MAINHAND] = twoHander(213) }, { class = "PALADIN", spec = 66 })
		eq(r.verdict, "NOT_COMPARABLE"); eq(r.code, "TWO_HAND_EQUIPPED")
	end)

	it("a one-hander for a dual wielder: the worse of the two hands", function()
		local r = eval(oneHander(226), { [SLOT.MAINHAND] = oneHander(220),
			[SLOT.OFFHAND] = weapon("INVTYPE_WEAPON", Wp.SWORD1H, 213, nil, { quality = Q.BLUE }) }, { class = "WARRIOR", spec = 72 })
		deepEq(r.slots, { SLOT.OFFHAND }); eq(r.verdict, "MEDIUM")
	end)

	it("a one-hander for a class that does not dual wield: the main hand only", function()
		local r = eval(oneHander(226), { [SLOT.MAINHAND] = oneHander(213), [SLOT.OFFHAND] = shield(150, Q.GREEN) },
			{ class = "PALADIN", spec = 70 })
		deepEq(r.slots, { SLOT.MAINHAND }); eq(r.verdict, "MINOR")
	end)

	it("empty hands: major", function()
		eq(eval(twoHander(226), {}, warrior()).verdict, "MAJOR")
		eq(eval(oneHander(226), {}, warrior()).verdict, "MAJOR")
	end)
end)

describe("the wire form (SRESP vd)", function()
	it("packs the tier, the usability, the code and the item-level difference", function()
		local r = eval(plate("INVTYPE_HEAD", 226), { [SLOT.HEAD] = plate("INVTYPE_HEAD", 190, nil, { quality = Q.BLUE }) }, warrior())
		deepEq(U().Pack(r), { v = "MEDIUM", l = 36 })
		deepEq(U().Unpack(U().Pack(r)), { verdict = "MEDIUM", usable = true, ilvlDelta = 36 })
		local empty = eval(plate("INVTYPE_HEAD", 226), {}, warrior())
		deepEq(U().Pack(empty), { v = "MAJOR", c = "EMPTY_SLOT" })
		local unusable = eval(plate("INVTYPE_HEAD", 226), {}, { class = "MAGE", spec = 63 })
		deepEq(U().Pack(unusable), { v = "NONE", u = false, c = "ARMOR_TYPE" })
		eq(U().Unpack({ v = "NONE", u = false }).usable, false)
		deepEq(U().Pack({ verdict = "MINOR", ilvlDelta = 1e9 }), { v = "MINOR", l = 2000 }, "clamped")
	end)

	it("an old client's verdict (BIG / SMALL with basis and percent) is not read", function()
		isNil(U().Unpack({ v = "BIG", b = "STATS", p = 74, l = 6 }))
		isNil(U().Unpack({ v = "SMALL" }))
		isNil(U().Pack({ verdict = "BIG" }))
		isNil(U().Unpack("x"))
	end)
end)

describe("the rules section of the upgrade badge", function()
	it("has defaults that validate", function()
		local r = U().DefaultRules()
		local ok, problems = U().ValidateRules(r)
		truthy(ok, table.concat(problems or {}, ","))
		deepEq(r, { enabled = true, autoPass = true })
	end)

	it("hands out a fresh copy every time", function()
		local a = U().DefaultRules()
		a.enabled = false
		eq(U().DefaultRules().enabled, true)
	end)

	it("names the field at fault", function()
		local function bad(mutate)
			local r = U().DefaultRules()
			mutate(r)
			local ok, problems = U().ValidateRules(r)
			falsy(ok)
			return table.concat(problems, ",")
		end
		eq(bad(function(r) r.enabled = "yes" end), "enabled")
		eq(bad(function(r) r.autoPass = nil end), "autoPass")
		eq(bad(function(r) r.useStats = true end), "unknown:useStats", "the stat-weight keys are gone")
		local ok, problems = U().ValidateRules("x")
		falsy(ok); deepEq(problems, { "upgrade" })
	end)

	it("the rules written before M7-5c (thresholds, label mode) still read and validate", function()
		local old = FDCP.Rules.DefaultConfig()
		old.upgrade.useStats, old.upgrade.bigThreshold, old.upgrade.smallThreshold, old.upgrade.ilvlBigThreshold = true, 0.05, 0, 0.05
		old.responses = { labelMode = "suggest" }
		falsy(FDCP.Rules.Validate(old), "as written they are not this version's rules")
		local read = FDCP.Rules.WithDefaults(old)
		truthy(FDCP.Rules.Validate(read))
		deepEq(read.upgrade, { enabled = true, autoPass = true })
		isNil(read.responses)
		truthy(FDCP.Ledger.Check({ id = "Gm-Camelot:1", author = "Gm-Camelot", seq = 1, ts = 1, type = "CONFIG_CHANGED", v = 1,
			payload = { rules = old } }))
	end)

	it("is a section of the guild's rules", function()
		eq(FDCP.Rules.DefaultConfig().upgrade.autoPass, true)
		isNil(FDCP.Rules.DefaultConfig().responses)
		local c = FDCP.Rules.DefaultConfig()
		c.upgrade = nil
		local ok, problems = FDCP.Rules.Validate(c)
		falsy(ok); eq(problems[1], "upgrade")
		local older = FDCP.Rules.WithDefaults({ session = { awardMode = "auto" } })
		eq(older.upgrade.enabled, true)
		truthy(FDCP.Rules.Validate(older))
	end)
end)
