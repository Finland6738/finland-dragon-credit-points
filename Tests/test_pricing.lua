-- Classifier and Pricing (M2-1): every cell of the docs/ANALISI.md §3.2 matrix, the classification rules (quest item =
-- Quest class OR starts a quest OR season token), the quality threshold, the override order and the multipliers.
-- Pure domain code: no game call is involved.
local function C() return FDCP.Classifier end
local function P() return FDCP.Pricing end

-- One sample item per category of the matrix (classID, subclassID, equipLoc as C_Item.GetItemInfoInstant gives them).
local SAMPLES = {
	weapon = { itemID = 1001, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON" },
	offhand = { itemID = 1002, classID = 4, subclassID = 6, equipLoc = "INVTYPE_SHIELD" },
	trinket = { itemID = 1003, classID = 4, subclassID = 0, equipLoc = "INVTYPE_TRINKET" },
	quest = { itemID = 1004, classID = 12, subclassID = 0, equipLoc = "" },
	jewelry = { itemID = 1005, classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER" },
	armor = { itemID = 1006, classID = 4, subclassID = 3, equipLoc = "INVTYPE_SHOULDER" },
	cosmetic = { itemID = 1007, classID = 9, subclassID = 1, equipLoc = "" },
	other = { itemID = 1008, classID = 7, subclassID = 0, equipLoc = "" },
}

local function item(category, quality, extra)
	local t = {}
	for k, v in pairs(SAMPLES[category]) do t[k] = v end
	t.quality = quality
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

-- The §3.2 matrix as the regulation writes it: false = not tracked, "council", "-" = no cell.
local MATRIX = {
	weapon = { false, 2, 2, "council" },
	offhand = { false, 1, 1, "council" },
	trinket = { false, 2, 2, "council" },
	quest = { false, 2, 2, "council" },
	jewelry = { false, 1, 1, "council" },
	armor = { false, 1, 1, "council" },
	cosmetic = { false, 0, 0, "-" },
	other = { false, 1, 1, "-" },
}
local QUALITIES = { 2, 3, 4, 5 }   -- green, blue, purple, orange

describe("the §3.2 matrix", function()
	for category, row in pairs(MATRIX) do
		for i, expected in ipairs(row) do
			local q = QUALITIES[i]
			it(category .. " quality " .. q, function()
				local r = P().Price(item(category, q), "MS")
				eq(r.category, category)
				if expected == false then
					eq(r.tracked, false)
					eq(r.reason, "NOT_TRACKED")
					isNil(r.cost)
				elseif expected == "council" then
					eq(r.tracked, true)
					eq(r.council, true)
					eq(r.reason, "COUNCIL")
					isNil(r.cost)
				elseif expected == "-" then
					eq(r.council, true)
					eq(r.reason, "NO_CELL")
					isNil(r.cost)
				else
					eq(r.tracked, true)
					eq(r.source, "MATRIX")
					eq(r.base, expected)
					eq(r.cost, expected)
					isNil(r.reason)
				end
			end)
		end
	end

	it("poor and common items are never tracked", function()
		for _, q in ipairs({ 0, 1 }) do
			eq(P().Price(item("weapon", q), "MS").tracked, false)
		end
	end)

	it("every cell is editable, decimals included", function()
		local cost = P().DefaultCost()
		cost.matrix.armor[4] = 1.5
		cost.matrix.weapon[5] = 3
		eq(P().Price(item("armor", 4), "MS", cost).cost, 1.5)
		eq(P().Price(item("weapon", 5), "MS", cost).cost, 3)
		eq(P().Price(item("armor", 3), "MS", cost).cost, 1)
	end)

	it("DefaultCost returns a fresh copy", function()
		local a = P().DefaultCost()
		a.matrix.weapon[4] = 9
		eq(P().DefaultCost().matrix.weapon[4], 2)
		eq(P().Price(item("weapon", 4), "MS").cost, 2)
	end)
end)

describe("classification", function()
	local function cat(t) return (C().Classify(t)) end

	it("weapons: one hand, two hands, main and off hand, ranged, thrown, wands", function()
		for _, loc in ipairs({ "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND",
				"INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN" }) do
			eq(cat({ classID = 2, subclassID = 1, equipLoc = loc }), "weapon", loc)
		end
		local c, rule = C().Classify({ classID = 2, subclassID = 19, equipLoc = "INVTYPE_RANGEDRIGHT" })
		eq(c, "weapon")
		eq(rule, "SUBCLASS")
	end)

	it("shields, held in off-hand and relics are off-hand", function()
		eq(cat({ classID = 4, subclassID = 6, equipLoc = "INVTYPE_SHIELD" }), "offhand")
		eq(cat({ classID = 4, subclassID = 0, equipLoc = "INVTYPE_HOLDABLE" }), "offhand")
		eq(cat({ classID = 4, subclassID = 7, equipLoc = "INVTYPE_RELIC" }), "offhand")
	end)

	it("rings and necks are jewellery, trinkets are trinkets", function()
		eq(cat({ classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER" }), "jewelry")
		eq(cat({ classID = 4, subclassID = 0, equipLoc = "INVTYPE_NECK" }), "jewelry")
		eq(cat({ classID = 4, subclassID = 0, equipLoc = "INVTYPE_TRINKET" }), "trinket")
	end)

	it("every armour slot and the cloak are armour", function()
		for _, loc in ipairs({ "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_WAIST",
				"INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_CLOAK" }) do
			eq(cat({ classID = 4, subclassID = 2, equipLoc = loc }), "armor", loc)
		end
	end)

	it("recipes, mounts, pets, cosmetic armour, shirts and tabards are cosmetic", function()
		eq(cat({ classID = 9, subclassID = 2, equipLoc = "" }), "cosmetic")
		eq(cat({ classID = 15, subclassID = 5, equipLoc = "" }), "cosmetic")
		eq(cat({ classID = 15, subclassID = 2, equipLoc = "" }), "cosmetic")
		eq(cat({ classID = 4, subclassID = 5, equipLoc = "INVTYPE_HEAD" }), "cosmetic")
		eq(cat({ classID = 4, subclassID = 0, equipLoc = "INVTYPE_BODY" }), "cosmetic")
		eq(cat({ classID = 4, subclassID = 0, equipLoc = "INVTYPE_TABARD" }), "cosmetic")
	end)

	it("anything else is other", function()
		local c, rule = C().Classify({ classID = 7, subclassID = 0, equipLoc = "" })
		eq(c, "other")
		eq(rule, "DEFAULT")
		eq(cat({}), "other")
		eq((C().Classify(nil)), "other")
	end)

	it("a quest item is the Quest class OR starts a quest OR is a season token", function()
		local c, rule = C().Classify({ itemID = 5, classID = 12, subclassID = 0, equipLoc = "" })
		eq(c, "quest")
		eq(rule, "QUEST")
		-- an armour piece that starts a quest
		eq(cat({ itemID = 6, classID = 4, subclassID = 4, equipLoc = "INVTYPE_CHEST", startsQuest = true }), "quest")
		-- a chain piece the game does not mark: only the token list knows it (set and list forms)
		local piece = { itemID = 7, classID = 15, subclassID = 0, equipLoc = "" }
		eq(cat(piece), "other")
		eq((C().Classify(piece, { [7] = true })), "quest")
		eq((C().Classify(piece, { 3, 7 })), "quest")
		eq((C().Classify(piece, { [8] = true })), "other")
		falsy(C().IsQuestItem(piece, nil))
	end)

	it("a token is priced as a quest item", function()
		local cost = P().DefaultCost()
		cost.tokens[1008] = true
		local r = P().Price(item("other", 4), "MS", cost)
		eq(r.category, "quest")
		eq(r.cost, 2)
	end)

	it("the tables are editable", function()
		local tbl = C().DefaultTable()
		tbl.equipLoc.INVTYPE_CLOAK = "jewelry"
		tbl.equipLoc.INVTYPE_RELIC = "weapon"
		eq((C().Classify({ classID = 4, subclassID = 1, equipLoc = "INVTYPE_CLOAK" }, nil, tbl)), "jewelry")
		eq((C().Classify({ classID = 4, subclassID = 7, equipLoc = "INVTYPE_RELIC" }, nil, tbl)), "weapon")
		-- the default is untouched
		eq((C().Classify({ classID = 4, subclassID = 1, equipLoc = "INVTYPE_CLOAK" })), "armor")
		-- and Pricing uses the table it is given
		local r = P().Price({ classID = 4, subclassID = 1, equipLoc = "INVTYPE_CLOAK", quality = 4 }, "MS", nil,
			{ classifierTable = tbl })
		eq(r.category, "jewelry")
		eq(r.cost, 1)
	end)

	it("validates a table", function()
		truthy(C().Validate(C().DefaultTable()))
		local tbl = C().DefaultTable()
		tbl.equipLoc.INVTYPE_HEAD = "hat"
		local ok, problems = C().Validate(tbl)
		falsy(ok)
		deepEq(problems, { "equipLoc:INVTYPE_HEAD" })
		falsy(C().Validate(nil))
	end)
end)

describe("quality threshold", function()
	it("follows the group's loot threshold", function()
		local green = item("armor", 2)
		eq(P().Price(green, "MS").tracked, false)
		-- the group lowers the threshold to green: the item enters, the preset has no green cell, the council decides
		local r = P().Price(green, "MS", nil, { lootThreshold = 2 })
		eq(r.tracked, true)
		eq(r.reason, "NO_CELL")
		-- the group raises it to purple: blue items leave the sessions
		eq(P().Price(item("armor", 3), "MS", nil, { lootThreshold = 4 }).tracked, false)
		eq(P().Price(item("armor", 4), "MS", nil, { lootThreshold = 4 }).cost, 1)
	end)

	it("an unknown quality is not tracked", function()
		falsy(C().IsTracked(nil, 3))
		truthy(C().IsTracked(3, nil))
		falsy(C().IsTracked(2, nil))
	end)

	it("a guild that prices green items adds the cells", function()
		local cost = P().DefaultCost()
		cost.matrix.armor[2] = 0.5
		cost.minQuality = 2
		eq(P().Price(item("armor", 2), "MS", cost).cost, 0.5)
	end)
end)

describe("override order", function()
	it("an override cost beats the matrix and the council cell", function()
		local cost = P().DefaultCost()
		cost.overrides[1006] = { cost = 2 }       -- shoulders fixed at 2 for the season
		cost.overrides[1001] = { cost = 4 }       -- a legendary weapon priced in advance
		local r = P().Price(item("armor", 4), "MS", cost)
		eq(r.source, "OVERRIDE_COST")
		eq(r.cost, 2)
		eq(r.category, "armor")
		r = P().Price(item("weapon", 5), "MS", cost)
		eq(r.source, "OVERRIDE_COST")
		eq(r.cost, 4)
		isNil(r.council)
	end)

	it("an override category goes through the matrix", function()
		local cost = P().DefaultCost()
		cost.overrides[1005] = { category = "weapon" }   -- a ring the council values like a weapon
		local r = P().Price(item("jewelry", 4), "MS", cost)
		eq(r.source, "OVERRIDE_CATEGORY")
		eq(r.category, "weapon")
		eq(r.rule, "OVERRIDE")
		eq(r.cost, 2)
		r = P().Price(item("jewelry", 5), "MS", cost)
		eq(r.reason, "COUNCIL")
	end)

	it("an override category beats the quest rule and the token list", function()
		local cost = P().DefaultCost()
		cost.tokens[1004] = true
		cost.overrides[1004] = { category = "armor" }
		eq(P().Price(item("quest", 4), "MS", cost).cost, 1)
	end)

	it("a cost override beats a category override in the same entry", function()
		local cost = P().DefaultCost()
		cost.overrides[1006] = { cost = 0.5, category = "weapon" }
		local r = P().Price(item("armor", 4), "MS", cost)
		eq(r.source, "OVERRIDE_COST")
		eq(r.cost, 0.5)
	end)

	it("an override never brings an untracked item into a session", function()
		local cost = P().DefaultCost()
		cost.overrides[1006] = { cost = 2 }
		local r = P().Price(item("armor", 2), "MS", cost)
		eq(r.tracked, false)
		isNil(r.cost)
	end)

	it("an override with an unknown category is ignored", function()
		local cost = P().DefaultCost()
		cost.overrides[1006] = { category = "hat" }
		local r = P().Price(item("armor", 4), "MS", cost)
		eq(r.source, "MATRIX")
		eq(r.category, "armor")
	end)

	it("the response multiplier applies after the override", function()
		local cost = P().DefaultCost()
		cost.overrides[1006] = { cost = 2 }
		eq(P().Price(item("armor", 4), "OS", cost).cost, 0)
		eq(P().Price(item("armor", 4), "MS", cost).cost, 2)
	end)
end)

describe("multipliers", function()
	it("response: MS × 1, OS × 0, transmog × 0", function()
		eq(P().Price(item("weapon", 4), "MS").cost, 2)
		eq(P().Price(item("weapon", 4), "OS").cost, 0)
		eq(P().Price(item("weapon", 4), "TMOG").cost, 0)
	end)

	it("off-spec on a council item is free", function()
		local r = P().Price(item("weapon", 5), "OS")
		eq(r.council, true)
		eq(r.cost, 0)
		isNil(P().Price(item("weapon", 5), "MS").cost)
	end)

	it("an unknown response has no cost", function()
		local r = P().Price(item("weapon", 4), "PASS")
		isNil(r.cost)
		eq(r.reason, "UNKNOWN_RESPONSE")
		eq(r.base, 2)
	end)

	it("raid size: preset × 1 for 10, 20 and 40, editable", function()
		for _, size in ipairs({ 10, 20, 40 }) do
			eq(P().Price(item("weapon", 4), "MS", nil, { raidSize = size }).cost, 2)
		end
		local cost = P().DefaultCost()
		cost.raidSizeMultiplier[10] = 0.5
		eq(P().Price(item("weapon", 4), "MS", cost, { raidSize = 10 }).cost, 1)
		eq(P().Price(item("armor", 4), "MS", cost, { raidSize = 10 }).cost, 0.5)
		eq(P().Price(item("armor", 4), "MS", cost, { raidSize = 40 }).cost, 1)
		eq(P().Price(item("armor", 4), "MS", cost, { raidSize = 25 }).cost, 1)   -- unknown size: × 1
	end)

	it("difficulty: Normal and Veteran share one table, preset × 1, editable", function()
		eq(P().Price(item("trinket", 4), "MS", nil, { difficulty = "normal" }).cost, 2)
		eq(P().Price(item("trinket", 4), "MS", nil, { difficulty = "veteran" }).cost, 2)
		local cost = P().DefaultCost()
		cost.difficultyMultiplier.veteran = 1.5
		local r = P().Price(item("trinket", 4), "MS", cost, { difficulty = "veteran", raidSize = 20 })
		eq(r.multiplier, 1.5)
		eq(r.cost, 3)
	end)

	it("decimal costs are rounded to two places", function()
		local cost = P().DefaultCost()
		cost.matrix.armor[4] = 0.1
		cost.difficultyMultiplier.veteran = 3
		eq(P().Price(item("armor", 4), "MS", cost, { difficulty = "veteran" }).cost, 0.3)
		cost.decimals = 0
		cost.matrix.armor[4] = 1.5
		cost.difficultyMultiplier.veteran = 1
		eq(P().Price(item("armor", 4), "MS", cost).cost, 2)
		eq(P().Round(1.234, 2), 1.23)
		eq(P().Round(0.1 * 3, 2), 0.3)
		eq(P().Round(2, nil), 2)
	end)
end)

describe("validation", function()
	it("the preset is valid", function()
		local ok, problems = P().Validate(P().DefaultCost())
		truthy(ok)
		deepEq(problems, {})
	end)

	it("refuses negative or non-numeric costs, unknown categories and bad overrides", function()
		local cost = P().DefaultCost()
		cost.matrix.armor[4] = -1
		cost.matrix.hats = { [4] = 1 }
		cost.responseMultiplier.OS = "zero"
		cost.overrides[10] = { cost = -2 }
		cost.overrides[11] = { category = "hat" }
		cost.overrides[12] = 3
		local ok, problems = P().Validate(cost)
		falsy(ok)
		deepEq(problems, { "matrix:armor:4", "matrix:hats", "overrides:10", "overrides:11", "overrides:12",
			"responseMultiplier:OS" })
		falsy(P().Validate(nil))
		falsy(P().Validate({}))
	end)
end)

describe("domain purity", function()
	it("Classifier and Pricing never name a game API", function()
		for _, name in ipairs({ "Classifier", "Pricing" }) do
			local src = Mock.ReadSource("FinlandDragonCreditPoints/Domain/" .. name .. ".lua")
			notNil(src, name)
			src = src:gsub("%-%-[^\n]*", "")   -- comments may name the adapter's APIs
			for _, api in ipairs({ "C_Item", "GetItemInfo", "GetLootThreshold", "CreateFrame", "Compat" }) do
				falsy(src:find(api .. "[%.%(:]"), name .. " calls " .. api)
			end
		end
	end)
end)
