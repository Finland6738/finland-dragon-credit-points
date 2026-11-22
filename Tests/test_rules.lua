-- Rules and presets (M2-5): the configuration schema of docs/ANALISI.md §3 with validation and defaults, the rules as
-- CONFIG_CHANGED events of the ledger (the rules in force when an event was written, the open-season confirmation),
-- and the four presets of §10 ("Patto", "Solo roll", "Loot council puro", "EPGP semplice"). Pure domain code.
local function Lg() return FDCP.Ledger end
local function R() return FDCP.Rules end
local function Pr() return FDCP.Presets end

local GM = "Aurel-Camelot"
local PACK = { { id = 409, size = 40 } }

local function has(list, code)
	for _, v in ipairs(list or {}) do
		if v == code then return true end
	end
	return false
end

local function bad(mutate)
	local c = R().DefaultConfig()
	mutate(c)
	local ok, problems = R().Validate(c)
	falsy(ok)
	return problems
end

local function roll(player, value) return { player = player, value = value, min = 1, max = 100 } end

-- The three regulation examples' items, priced by a configuration.
local SHOULDER = { itemID = 19001, classID = 4, subclassID = 4, equipLoc = "INVTYPE_SHOULDER", quality = 4 }
local SWORD = { itemID = 19002, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON", quality = 4 }
local RING = { itemID = 19003, classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER", quality = 4 }

local function price(rules, item, response, ctx)
	return FDCP.Pricing.Price(item, response, rules.cost, ctx).cost
end

-- The shoulder example (§3.4): credits 0, 2, 3; rolls 34, 90, 99.
local function shoulder(rules)
	return FDCP.Priority.Evaluate({
		responses = { Aurel = "MS", Bryn = "MS", Corin = "MS" },
		credits = { Aurel = 0, Bryn = 2, Corin = 3 },
		item = SHOULDER, costConfig = rules.cost,
		rounds = { { rolls = { roll("Aurel", 34), roll("Bryn", 90), roll("Corin", 99) } } },
	}, rules.priority)
end

describe("the rules schema", function()
	it("the defaults are the Patto preset of §3.1 and pass validation", function()
		local c = R().DefaultConfig()
		local ok, problems = R().Validate(c)
		truthy(ok); deepEq(problems, {})
		eq(c.night.requiresOfficialStart, true)
		eq(c.members.mainOnly, true)
		eq(c.members.lateJoin.method, "min"); eq(c.members.lateJoin.rounding, "floor")   -- M7-5b: the fewest credits
		eq(c.penalties.absence, 1); eq(c.penalties.autoApply, false)
		eq(c.season.startCredits, 0)
		eq(c.cost.raidSizeMultiplier[10], 1); eq(c.cost.raidSizeMultiplier[40], 1)
		eq(c.cost.difficultyMultiplier.normal, 1); eq(c.cost.difficultyMultiplier.veteran, 1)
		eq(c.cost.responseMultiplier.OS, 0)
		eq(c.priority.metric, "credits")
		deepEq(c.priority.tieBreak, { "roll", "reroll" })
		eq(c.priority.boeFallback, "bank")
		eq(c.priority.responses.OS.tier, 2)
		eq(c.session.awardMode, "confirm"); eq(c.session.lockCategoryOnOpen, true)
		eq(c.council.vote, false)
		eq(c.legendary.mode, "council"); eq(c.legendary.chainPieceCost, 2)
		eq(c.bench.creditEffect, "none")
		eq(c.bench.creditAmount, 1); eq(c.bench.minTanks, 2); eq(c.bench.minHealers, 4)
	end)

	it("each section is the module's own default", function()
		local c = R().DefaultConfig()
		local members = FDCP.Members.DefaultConfig()
		members.lateJoin.method = "min"   -- the Patto preset's own choice (M7-5b)
		deepEq(c.members, members)
		deepEq(c.penalties, FDCP.Absence.DefaultConfig())
		deepEq(c.season, FDCP.Season.DefaultConfig())
		deepEq(c.cost, FDCP.Pricing.DefaultCost())
		deepEq(c.priority, FDCP.Priority.DefaultConfig())
	end)

	it("hands out a fresh copy every time", function()
		local a = R().DefaultConfig()
		a.cost.matrix.weapon[4] = 9
		a.priority.tieBreak[1] = "reroll"
		eq(R().DefaultConfig().cost.matrix.weapon[4], 2)
		eq(R().DefaultConfig().priority.tieBreak[1], "roll")
	end)

	it("every rule of the Patto preset works through the engine", function()
		local c = R().DefaultConfig()
		-- §3.2 costs: weapon 2, armour 1, jewellery 1; off-spec free; same cost for 10/20/40 and Normal/Veteran.
		eq(price(c, SWORD, "MS"), 2)
		eq(price(c, SHOULDER, "MS"), 1)
		eq(price(c, RING, "MS"), 1)
		eq(price(c, SWORD, "OS"), 0)
		eq(price(c, SWORD, "MS", { raidSize = 10, difficulty = "veteran" }), price(c, SWORD, "MS", { raidSize = 40 }))
		-- §3.4: fewer credits wins whatever the roll.
		local r = shoulder(c)
		eq(r.status, "PROPOSAL"); eq(r.proposal.winner, "Aurel"); eq(r.proposal.cost, 1)
		truthy(has(r.proposal.reasons, "LOWER_CREDITS"))
	end)

	it("refuses what is not a configuration", function()
		local ok, problems = R().Validate("rules")
		falsy(ok); deepEq(problems, { "config" })
		ok, problems = R().Validate({})
		falsy(ok)
		for _, s in ipairs(R().SECTIONS) do truthy(has(problems, s)) end
	end)

	it("refuses a missing or an unknown section", function()
		truthy(has(bad(function(c) c.legendary = nil end), "legendary"))
		truthy(has(bad(function(c) c.loot = {} end), "unknown:loot"))
	end)

	it("names the field at fault in every section", function()
		truthy(has(bad(function(c) c.night.requiresOfficialStart = "yes" end), "night.requiresOfficialStart"))
		truthy(has(bad(function(c) c.members.lateJoin.method = "mean" end), "members.lateJoin.method"))
		truthy(has(bad(function(c) c.season.startCredits = -1 end), "season.startCredits"))
		truthy(has(bad(function(c) c.cost.matrix.weapon[4] = -2 end), "cost.matrix:weapon:4"))
		truthy(has(bad(function(c) c.cost.responseMultiplier.MS = "one" end), "cost.responseMultiplier:MS"))
		truthy(has(bad(function(c) c.priority.metric = "loot" end), "priority.metric"))
		truthy(has(bad(function(c) c.priority.boeFallback = "trash" end), "priority.boeFallback"))
		truthy(has(bad(function(c) c.session.awardMode = "random" end), "session.awardMode"))
		truthy(has(bad(function(c) c.session.autoAdvance = 1 end), "session.autoAdvance"))
		truthy(has(bad(function(c) c.session.lockCategoryOnOpen = nil end), "session.lockCategoryOnOpen"))
		truthy(has(bad(function(c) c.session.interventionSeconds = 2.5 end), "session.interventionSeconds"))
		truthy(has(bad(function(c) c.session.interventionSeconds = 601 end), "session.interventionSeconds"))
		truthy(has(bad(function(c) c.council.vote = "no" end), "council.vote"))
		truthy(has(bad(function(c) c.council.requirePresent = nil end), "council.requirePresent"))
		truthy(has(bad(function(c) c.legendary.mode = "dice" end), "legendary.mode"))
		truthy(has(bad(function(c) c.legendary.chainPieceCost = -2 end), "legendary.chainPieceCost"))
		truthy(has(bad(function(c) c.bench.creditEffect = "double" end), "bench.creditEffect"))
		truthy(has(bad(function(c) c.bench.creditAmount = -1 end), "bench.creditAmount"))
		truthy(has(bad(function(c) c.bench.creditAmount = 101 end), "bench.creditAmount"))
		truthy(has(bad(function(c) c.bench.minTanks = 1.5 end), "bench.minTanks"))
		truthy(has(bad(function(c) c.bench.minHealers = 41 end), "bench.minHealers"))
		truthy(has(bad(function(c) c.bench.minHealers = nil end), "bench.minHealers"))
	end)

	it("accepts the bench effects bonus and malus and a minimum of zero", function()
		local c = R().DefaultConfig()
		c.bench.creditEffect = "bonus"; c.bench.creditAmount = 0.5; c.bench.minTanks = 0; c.bench.minHealers = 0
		truthy(R().Validate(c))
		c.bench.creditEffect = "malus"
		truthy(R().Validate(c))
	end)

	it("fills the bench keys that rules written before M3-4 lack", function()
		local old = R().DefaultConfig()
		old.bench = { creditEffect = "none" }
		local c = R().WithDefaults(old)
		eq(c.bench.minTanks, 2); eq(c.bench.minHealers, 4); eq(c.bench.creditAmount, 1)
		truthy(R().Validate(c))
	end)

	it("lists every problem, sorted", function()
		local problems = bad(function(c) c.session.awardMode = "x"; c.bench.creditEffect = "x"; c.legendary.mode = "x" end)
		deepEq(problems, { "bench.creditEffect", "legendary.mode", "session.awardMode" })
	end)

	it("accepts the documented alternatives", function()
		local c = R().DefaultConfig()
		c.session.awardMode = "auto"; c.session.interventionSeconds = 0
		c.legendary.mode = "queue"; c.legendary.chainPieceCost = 1.5
		c.priority.metric = "creditsPerNight"; c.priority.boeFallback = "freeroll"
		c.members.lateJoin.method = "median"
		c.season.startCredits = 3
		c.cost.matrix.armor[4] = 1.5
		truthy(R().Validate(c))
	end)

	it("fills a missing section or key, never inside a key that is present", function()
		local c = R().DefaultConfig()
		c.legendary = nil
		c.session.interventionSeconds = nil
		c.cost.matrix = { weapon = { [4] = 3 } }   -- the guild wrote only this row
		local f = R().WithDefaults(c)
		deepEq(f.legendary, R().DefaultConfig().legendary)
		eq(f.session.interventionSeconds, 30)
		deepEq(f.cost.matrix, { weapon = { [4] = 3 } })
		isNil(c.legendary)   -- the input is untouched
		deepEq(R().WithDefaults(nil), R().DefaultConfig())
	end)

	it("lists the paths two configurations differ in", function()
		local a, b = R().DefaultConfig(), R().DefaultConfig()
		deepEq(R().Diff(a, b), {})
		b.cost.matrix.weapon[4] = 3
		b.session.awardMode = "auto"
		b.cost.overrides[19019] = { cost = 5 }
		deepEq(R().Diff(a, b), { "cost.matrix.weapon.4", "cost.overrides.19019", "session.awardMode" })
	end)
end)

describe("the rules in the ledger", function()
	local function changed(L, ts, mutate, extra)
		local rules = R().DefaultConfig()
		mutate(rules)
		local d = { author = GM, ts = ts, rules = rules }
		for k, v in pairs(extra or {}) do d[k] = v end
		return R().Change(L, d)
	end

	it("are the defaults until the GM writes them", function()
		local L = Lg().New()
		local rules, from = R().Current(L)
		deepEq(rules, R().DefaultConfig()); isNil(from)
	end)

	it("a CONFIG_CHANGED carries the whole configuration", function()
		local L = Lg().New()
		local e = assert(changed(L, 5, function(c) c.cost.matrix.weapon[4] = 3 end, { preset = "PATTO" }))
		eq(e.type, "CONFIG_CHANGED"); isNil(e.season)
		eq(e.payload.preset, "PATTO"); isNil(e.payload.confirmed)
		local rules, from = R().Current(L)
		eq(rules.cost.matrix.weapon[4], 3); eq(from, e.id)
		truthy(R().Validate(e.payload.rules))
		eq(price(rules, SWORD, "MS"), 3)
	end)

	it("the rules in force are those written before the event", function()
		local L = Lg().New()
		local first = assert(changed(L, 10, function(c) c.cost.matrix.weapon[4] = 3 end))
		local second = assert(changed(L, 20, function(c) c.cost.matrix.weapon[4] = 4 end))
		local award = assert(Lg().Append(L, { author = GM, ts = 15, season = "S1", type = "ITEM_AWARDED",
			payload = { member = "Bryn", item = 19002, cost = 3 } }))
		eq(R().Current(L, award).cost.matrix.weapon[4], 3)
		eq(R().Current(L, first).cost.matrix.weapon[4], 2)   -- before the first change: the defaults
		eq(R().Current(L, second).cost.matrix.weapon[4], 3)
		eq(R().Current(L).cost.matrix.weapon[4], 4)
	end)

	it("refuses invalid rules, a bad preset code and a change that changes nothing", function()
		local L = Lg().New()
		local e, code = changed(L, 1, function(c) c.priority.metric = "loot" end)
		isNil(e); eq(code, "RULES:priority.metric")
		e, code = changed(L, 1, function(c) c.session.awardMode = "auto" end, { preset = "my preset" })
		isNil(e); eq(code, "preset")
		e, code = R().Change(L, { author = GM, ts = 1, rules = R().DefaultConfig() })
		isNil(e); eq(code, "UNCHANGED")
		e, code = R().Change(L, "rules")
		isNil(e); eq(code, "event")
		eq(Lg().Count(L), 0)
	end)

	it("fills a partial configuration with the defaults before writing it", function()
		local L = Lg().New()
		local e = assert(R().Change(L, { author = GM, ts = 1, rules = { session = { awardMode = "auto" } } }))
		eq(e.payload.rules.session.awardMode, "auto")
		eq(e.payload.rules.session.interventionSeconds, 30)
		deepEq(e.payload.rules.cost, FDCP.Pricing.DefaultCost())
	end)

	it("need an explicit confirmation while a season is open", function()
		local L = Lg().New()
		assert(FDCP.Season.Open(L, { author = GM, ts = 1, season = "S1", instances = PACK }))
		local e, code = changed(L, 2, function(c) c.cost.matrix.weapon[4] = 3 end)
		isNil(e); eq(code, "CONFIRM_REQUIRED")
		e = assert(changed(L, 3, function(c) c.cost.matrix.weapon[4] = 3 end, { confirmed = true }))
		eq(e.payload.confirmed, true)
		assert(FDCP.Season.Close(L, { author = GM, ts = 4, season = "S1" }))
		assert(changed(L, 5, function(c) c.cost.matrix.weapon[4] = 4 end))
	end)

	it("a merged CONFIG_CHANGED with invalid rules is refused", function()
		local L = Lg().New()
		local rules = R().DefaultConfig()
		rules.legendary.mode = "dice"
		local r = Lg().Merge(L, { { id = GM .. ":1", author = GM, seq = 1, ts = 1, type = "CONFIG_CHANGED", v = 1,
			payload = { rules = rules } } })
		eq(r.added, 0); deepEq(r.invalid, { "payload:rules" })
		r = Lg().Merge(L, { { id = GM .. ":1", author = GM, seq = 1, ts = 1, type = "CONFIG_CHANGED", v = 1,
			payload = { rules = R().DefaultConfig(), confirmed = "yes" } } })
		deepEq(r.invalid, { "payload:confirmed" })
	end)
end)

describe("presets", function()
	it("are the four of §10, each a valid configuration", function()
		deepEq(Pr().ORDER, { "PATTO", "ROLL_ONLY", "LOOT_COUNCIL", "EPGP_SIMPLE" })
		eq(Pr().DEFAULT, "PATTO")
		for _, code in ipairs(Pr().ORDER) do
			truthy(Pr().Has(code))
			local ok, problems = R().Validate(Pr().Get(code))
			truthy(ok, code .. ": " .. table.concat(problems or {}, ","))
		end
		local p, code = Pr().Get("DKP")
		isNil(p); eq(code, "UNKNOWN_PRESET")
		falsy(Pr().Has("DKP"))
	end)

	it("Patto is the default configuration", function()
		deepEq(Pr().Get("PATTO"), R().DefaultConfig())
	end)

	it("Solo roll: the highest roll wins and nothing costs credits", function()
		local c = Pr().Get("ROLL_ONLY")
		eq(c.priority.metric, "roll")
		eq(price(c, SWORD, "MS"), 0); eq(price(c, RING, "MS"), 0)
		local r = shoulder(c)
		eq(r.proposal.winner, "Corin"); eq(r.proposal.cost, 0)
		eq(c.members.lateJoin.method, "zero")
		eq(c.cost.matrix.weapon[5], "council")   -- a legendary cell stays the council's
	end)

	it("Loot council puro: the council votes on every item, nothing costs credits", function()
		local c = Pr().Get("LOOT_COUNCIL")
		eq(c.session.awardMode, "council"); eq(c.council.vote, true)
		eq(c.legendary.mode, "vote")
		eq(price(c, SWORD, "MS"), 0)
	end)

	it("EPGP semplice: the fewest credits per night played wins", function()
		local c = Pr().Get("EPGP_SIMPLE")
		eq(c.priority.metric, "creditsPerNight")
		eq(price(c, SWORD, "MS"), 2)
		local r = FDCP.Priority.Evaluate({
			responses = { Aurel = "MS", Bryn = "MS" },
			credits = { Aurel = 4, Bryn = 2 }, nights = { Aurel = 4, Bryn = 1 },
			costs = { MS = 1, OS = 0 },
			rounds = { { rolls = { roll("Aurel", 10), roll("Bryn", 90) } } },
		}, c.priority)
		eq(r.proposal.winner, "Aurel")
	end)

	it("are fresh copies", function()
		local a = Pr().Get("ROLL_ONLY")
		a.priority.metric = "credits"
		eq(Pr().Get("ROLL_ONLY").priority.metric, "roll")
	end)

	it("a configuration is recognised as its preset until the GM edits it", function()
		for _, code in ipairs(Pr().ORDER) do eq(Pr().Match(Pr().Get(code)), code) end
		local c = Pr().Get("EPGP_SIMPLE")
		c.cost.matrix.weapon[4] = 5
		isNil(Pr().Match(c))
	end)

	it("are applied as a CONFIG_CHANGED with the preset's code", function()
		local L = Lg().New()
		local e = assert(Pr().Apply(L, "LOOT_COUNCIL", { author = GM, ts = 1 }))
		eq(e.payload.preset, "LOOT_COUNCIL")
		eq(Pr().Match(R().Current(L)), "LOOT_COUNCIL")
		local none, code = Pr().Apply(L, "DKP", { author = GM, ts = 2 })
		isNil(none); eq(code, "UNKNOWN_PRESET")
		none, code = Pr().Apply(L, "LOOT_COUNCIL", { author = GM, ts = 3 })
		isNil(none); eq(code, "UNCHANGED")
	end)
end)
