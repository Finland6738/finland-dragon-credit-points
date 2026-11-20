-- Pricing: the cost of an item for a response (docs/ANALISI.md §3.2). Pure Lua 5.1: it never calls the game.
--
-- The cost resolves in this order, the first that answers wins (§3.2):
--   0. tracking: an item below the quality threshold (the group's loot threshold) never enters a session, so it has
--      no price ("NOT_TRACKED"); this gate comes first, an override never brings an untracked item into a session;
--   1. per-item override: `overrides[itemID] = { cost = n }` fixes the base cost, `{ category = "weapon" }` fixes the
--      category and the matrix gives the cost ("OVERRIDE_COST" / "OVERRIDE_CATEGORY");
--   2. the category × quality matrix ("MATRIX"); a cell is a number (decimals allowed), "council" (the council
--      decides, e.g. legendaries) or missing (the combination is not priced: the council decides too, "NO_CELL");
--   3. the multipliers: response (MS × 1, OS × 0, transmog × 0), raid size (10/20/40, preset × 1) and difficulty
--      (Normal and Veteran share one table, preset × 1). They apply to an overridden cost as well: an off-spec answer
--      costs 0 on every item.
-- The final cost is rounded to `decimals` places (2 by default), so 1.5 × 1 stays 1.5 and float noise never reaches
-- the ledger. Results carry codes and numbers, never sentences.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Pricing = {}
ns.Pricing, ns.modules.Pricing = Pricing, Pricing

local type, pairs, ipairs, tostring, floor = type, pairs, ipairs, tostring, math.floor

local function Classifier() return ns.Classifier end

Pricing.COUNCIL = "council"
Pricing.RESPONSES = { "MS", "OS", "TMOG" }
Pricing.DIFFICULTIES = { "normal", "veteran" }
Pricing.RAID_SIZES = { 10, 20, 40 }

-- The cost configuration of the "Patto" preset (§3.1, §3.2). A fresh copy on every call.
-- matrix[category][quality]: qualities are Enum.ItemQuality ids (3 blue, 4 purple, 5 orange); green (2) has no cell
-- because the preset does not track it.
function Pricing.DefaultCost()
	local C = Pricing.COUNCIL
	return {
		matrix = {
			weapon = { [3] = 2, [4] = 2, [5] = C },
			offhand = { [3] = 1, [4] = 1, [5] = C },
			trinket = { [3] = 2, [4] = 2, [5] = C },
			quest = { [3] = 2, [4] = 2, [5] = C },
			jewelry = { [3] = 1, [4] = 1, [5] = C },
			armor = { [3] = 1, [4] = 1, [5] = C },
			cosmetic = { [3] = 0, [4] = 0 },
			other = { [3] = 1, [4] = 1 },
		},
		responseMultiplier = { MS = 1, OS = 0, TMOG = 0 },
		raidSizeMultiplier = { [10] = 1, [20] = 1, [40] = 1 },
		difficultyMultiplier = { normal = 1, veteran = 1 },
		overrides = {},        -- [itemID] = { cost = n } | { category = "..." }
		tokens = {},           -- the season's token list: { [itemID] = true }
		minQuality = 3,        -- used when the caller does not pass the group's loot threshold
		decimals = 2,
	}
end

local DEFAULT_COST = Pricing.DefaultCost()

-- Rounds a non-negative number to `decimals` places.
function Pricing.Round(x, decimals)
	if type(decimals) ~= "number" or decimals < 0 then decimals = 2 end
	local p = 10 ^ floor(decimals)
	return floor(x * p + 0.5) / p
end

local function multiplier(map, key)
	if type(map) ~= "table" or key == nil then return 1 end
	local m = map[key]
	if type(m) == "number" then return m end
	return 1
end

-- The base cost of an item, before the response multiplier. Returns a table:
--   tracked   false when the item is below the threshold (then nothing else is set but quality and category)
--   category  the category code (Domain/Classifier.lua)
--   rule      how the classifier chose it ("QUEST", "SUBCLASS", "EQUIPLOC", "CLASS", "DEFAULT", "OVERRIDE")
--   quality   the item quality
--   source    "OVERRIDE_COST" | "OVERRIDE_CATEGORY" | "MATRIX"
--   base      the base cost (number), or nil when the council decides
--   council   true when the council decides the cost
--   reason    nil, or "NOT_TRACKED" | "COUNCIL" | "NO_CELL"
-- ctx = { lootThreshold = n, classifierTable = tbl } (both optional).
function Pricing.Base(item, cost, ctx)
	cost = cost or DEFAULT_COST
	ctx = ctx or {}
	item = type(item) == "table" and item or {}
	local r = { quality = item.quality }
	local category, rule = Classifier().Classify(item, cost.tokens, ctx.classifierTable)
	r.category, r.rule = category, rule

	local threshold = ctx.lootThreshold
	if type(threshold) ~= "number" then threshold = cost.minQuality end
	if not Classifier().IsTracked(item.quality, threshold) then
		r.tracked, r.reason = false, "NOT_TRACKED"
		return r
	end
	r.tracked = true

	local override = item.itemID ~= nil and type(cost.overrides) == "table" and cost.overrides[item.itemID] or nil
	if type(override) == "table" and type(override.cost) == "number" then
		r.source, r.base = "OVERRIDE_COST", override.cost
		return r
	end
	if type(override) == "table" and Classifier().IsCategory(override.category) then
		r.source, r.category, r.rule = "OVERRIDE_CATEGORY", override.category, "OVERRIDE"
	else
		r.source = "MATRIX"
	end

	local row = type(cost.matrix) == "table" and cost.matrix[r.category] or nil
	local cell = type(row) == "table" and row[item.quality] or nil
	if type(cell) == "number" then
		r.base = cell
	elseif cell == Pricing.COUNCIL then
		r.council, r.reason = true, "COUNCIL"
	else
		r.council, r.reason = true, "NO_CELL"
	end
	return r
end

-- The cost of an item for a response. Returns the table of Pricing.Base plus:
--   response    the response code
--   multiplier  response × raid size × difficulty
--   cost        the final cost (rounded), or nil when the item is not tracked, the council decides, or the response
--               is unknown (reason "UNKNOWN_RESPONSE")
-- ctx = { raidSize = 10 | 20 | 40, difficulty = "normal" | "veteran", lootThreshold = n, classifierTable = tbl }.
-- An unknown raid size or difficulty multiplies by 1.
function Pricing.Price(item, response, cost, ctx)
	cost = cost or DEFAULT_COST
	ctx = ctx or {}
	local r = Pricing.Base(item, cost, ctx)
	r.response = response
	if not r.tracked then return r end
	local rm = type(cost.responseMultiplier) == "table" and cost.responseMultiplier[response] or nil
	if type(rm) ~= "number" then
		r.reason = r.reason or "UNKNOWN_RESPONSE"
		return r
	end
	r.multiplier = rm * multiplier(cost.raidSizeMultiplier, ctx.raidSize)
		* multiplier(cost.difficultyMultiplier, ctx.difficulty)
	if r.base == nil then
		-- The council prices it; a zero multiplier (off-spec) still makes it free.
		if r.multiplier == 0 then r.cost = 0 end
		return r
	end
	r.cost = Pricing.Round(r.base * r.multiplier, cost.decimals)
	return r
end

local function checkNumber(problems, code, v)
	if type(v) ~= "number" or v ~= v or v < 0 or v == math.huge then problems[#problems + 1] = code end
end

-- Checks a cost configuration: every cell, multiplier and override cost is a finite number >= 0 (the community
-- site refuses negative costs), every category is known. Returns true, or false plus a sorted list of codes.
function Pricing.Validate(cost)
	if type(cost) ~= "table" then return false, { "cost" } end
	local problems = {}
	if type(cost.matrix) ~= "table" then
		problems[#problems + 1] = "matrix"
	else
		for category, row in pairs(cost.matrix) do
			if not Classifier().IsCategory(category) or type(row) ~= "table" then
				problems[#problems + 1] = "matrix:" .. tostring(category)
			else
				for q, cell in pairs(row) do
					if cell ~= Pricing.COUNCIL then checkNumber(problems, "matrix:" .. category .. ":" .. tostring(q), cell) end
				end
			end
		end
	end
	for _, section in ipairs({ "responseMultiplier", "raidSizeMultiplier", "difficultyMultiplier" }) do
		local s = cost[section]
		if type(s) ~= "table" then
			problems[#problems + 1] = section
		else
			for k, v in pairs(s) do checkNumber(problems, section .. ":" .. tostring(k), v) end
		end
	end
	if cost.overrides ~= nil then
		if type(cost.overrides) ~= "table" then
			problems[#problems + 1] = "overrides"
		else
			for id, o in pairs(cost.overrides) do
				local code = "overrides:" .. tostring(id)
				if type(o) ~= "table" then
					problems[#problems + 1] = code
				elseif o.cost ~= nil then
					checkNumber(problems, code, o.cost)
				elseif not Classifier().IsCategory(o.category) then
					problems[#problems + 1] = code
				end
			end
		end
	end
	table.sort(problems)
	return #problems == 0, problems
end

if ns.addon then ns.addon.Pricing = Pricing end   -- also reachable from tests
