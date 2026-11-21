-- Session state machine (M2-6): the loot session of docs/ANALISI.md §4 (waiting, collecting, announcing, roll tier N,
-- computing, reroll / next tier / fallback, proposal, confirm / reject / modify, assigned, delivered), pause,
-- session.autoAdvance, session.awardMode (confirm, auto, council), the addon rule of §4.1, the ITEM_AWARDED events it
-- writes and a session that survives /reload. Pure domain code.
local function F() return FDCP.SessionFSM end
local function Lg() return FDCP.Ledger end

local ML = "Dara"
local SEASON = "S1"
local RAID = { Aurel = true, Bryn = true, Corin = true, Dara = true }

-- Items (Pricing, preset Patto): ring and shoulder cost 1, the sword 2, an orange is priced by the council, a green is
-- not tracked.
local RING = { itemID = 19003, slot = 1, classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER", quality = 4 }
local SHOULDER = { itemID = 19001, slot = 2, classID = 4, subclassID = 4, equipLoc = "INVTYPE_SHOULDER", quality = 4 }
local SWORD = { itemID = 19002, slot = 3, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON", quality = 4 }
local GREEN = { itemID = 19004, slot = 4, classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER", quality = 2 }
local ORANGE = { itemID = 19005, slot = 5, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON", quality = 5 }
local BOE = { itemID = 19006, slot = 6, classID = 4, subclassID = 4, equipLoc = "INVTYPE_SHOULDER", quality = 4,
	boe = true }

local function has(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then return true end
	end
	return false
end

local function count(list, kind)
	local n = 0
	for _, e in ipairs(list) do
		if e.type == kind then n = n + 1 end
	end
	return n
end

-- The SavedVariables round trip: plain data only (no function, no metatable, no cycle), written as a Lua literal and
-- read back.
local function ser(v, seen)
	local t = type(v)
	if t == "number" then return string.format("%.17g", v) end
	if t == "string" then return string.format("%q", v) end
	if t == "boolean" then return tostring(v) end
	if t ~= "table" then error("cannot be saved: " .. t) end
	if getmetatable(v) ~= nil then error("a table with a metatable") end
	seen = seen or {}
	if seen[v] then error("a circular table") end
	seen[v] = true
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		local ta, tb = type(a), type(b)
		if ta ~= tb then return ta < tb end
		return a < b
	end)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = "[" .. ser(k, seen) .. "]=" .. ser(v[k], seen) end
	seen[v] = nil
	return "{" .. table.concat(parts, ",") .. "}"
end

local function reload(v) return assert(loadstring("return " .. ser(v)))() end

local function rules(mutate)
	local r = FDCP.Rules.DefaultConfig()
	if mutate then mutate(r) end
	return r
end

local function manual(mutate)
	return rules(function(r)
		r.session.autoAdvance = false
		if mutate then mutate(r) end
	end)
end

-- A session, its ledger and the effects it produced. opts = { rules, present, addon, credits, gate }.
local function bench(opts)
	opts = opts or {}
	local b = { L = Lg().New(), t = 1000, fx = {} }
	b.s = assert(F().New({ id = "S1-1", season = SEASON, ml = ML, ts = 1000, encounter = 601, rules = opts.rules,
		present = opts.present or RAID, addon = opts.addon or RAID }))
	function b.env() return { ledger = b.L, credits = opts.credits, opts = opts.gate } end
	function b.step(input)
		input.ts = input.ts or b.t
		local ok, code, effects = F().Step(b.s, input, b.env())
		for _, e in ipairs(effects) do b.fx[#b.fx + 1] = e end
		return ok, code, effects
	end
	function b.must(input)
		local ok, code, effects = b.step(input)
		if not ok then error("refused " .. tostring(input.type) .. ": " .. tostring(code), 2) end
		return effects
	end
	function b.refused(input)
		local before = ser(b.s)
		local ok, code, effects = b.step(input)
		falsy(ok, "accepted " .. tostring(input.type))
		eq(#effects, 0)
		eq(ser(b.s), before, "a refused input changed the session")
		return code
	end
	function b.ml(kind, extra)
		local input = extra or {}
		input.type, input.by = kind, ML
		return b.must(input)
	end
	function b.at(t) b.t = t end
	function b.loot(items) return b.must({ type = "LOOT_OPENED", items = items, encounter = 601 }) end
	function b.start(items)
		b.loot(items or { RING })
		return b.ml("START")
	end
	function b.respond(player, response) return b.must({ type = "RESPONSE", player = player, response = response }) end
	function b.roll(player, value, min, max)
		return b.must({ type = "ROLL", player = player, value = value, min = min or 1, max = max or 100 })
	end
	function b.item(i) return b.s.items[i or b.s.active] end
	function b.proposal() return b.item().proposal end
	function b.events()
		return Lg().Sorted(b.L, function(e) return e.type == "ITEM_AWARDED" end)
	end
	return b
end

-- The three MS responders of the regulation examples, the ML passes.
local function answerAll(b, responses)
	for _, p in ipairs({ "Aurel", "Bryn", "Corin", "Dara" }) do b.respond(p, responses[p] or "PASS") end
end

local function rollAll(b, rolls)
	for _, p in ipairs({ "Aurel", "Bryn", "Corin" }) do
		if rolls[p] then b.roll(p, rolls[p]) end
	end
end

describe("a new session", function()
	it("starts in WAITING with the rules frozen and only plain data", function()
		local b = bench()
		eq(b.s.state, "WAITING")
		eq(b.s.ml, ML); eq(b.s.season, SEASON); eq(b.s.encounter, 601)
		eq(b.s.rules.session.awardMode, "confirm")
		eq(b.s.rules.session.rollSeconds, 30)
		eq(b.s.rules.priority.metric, "credits")
		deepEq(reload(b.s), b.s)
	end)

	it("refuses bad parameters", function()
		local function code(p)
			local s, c = F().New(p)
			isNil(s)
			return c
		end
		eq(code(nil), "params")
		eq(code({ season = SEASON, ml = ML, ts = 1 }), "id")
		eq(code({ id = "x", ml = ML, ts = 1 }), "season")
		eq(code({ id = "x", season = SEASON, ml = "a:b", ts = 1 }), "ml")
		eq(code({ id = "x", season = SEASON, ml = ML }), "ts")
		eq(code({ id = "x", season = SEASON, ml = ML, ts = 1,
			rules = rules(function(r) r.session.awardMode = "lottery" end) }), "RULES:session.awardMode")
	end)

	it("keeps rules written by an older addon working (missing keys get the defaults)", function()
		local r = rules()
		r.session.rollSeconds = nil
		local s = assert(F().New({ id = "x", season = SEASON, ml = ML, ts = 1, rules = r }))
		eq(s.rules.session.rollSeconds, 30)
	end)

	it("the session rules have a roll timer, validated", function()
		local r = rules(function(c) c.session.rollSeconds = 2 end)
		local ok, problems = FDCP.Rules.Validate(r)
		falsy(ok); truthy(has(problems, "session.rollSeconds"))
		r.session.rollSeconds = 45
		truthy((FDCP.Rules.Validate(r)))
	end)
end)

describe("waiting and collecting", function()
	it("waits out a lockdown, then the ML opens the corpse", function()
		local b = bench()
		b.must({ type = "LOCKDOWN", active = true })
		eq(b.refused({ type = "LOOT_OPENED", items = { RING } }), "LOCKDOWN")
		b.must({ type = "LOCKDOWN", active = false })
		local effects = b.loot({ RING, GREEN, SWORD })
		eq(b.s.state, "COLLECTING")
		eq(#b.s.items, 2)
		deepEq(b.s.skipped, { GREEN.itemID })
		eq(effects[1].type, "COLLECTED"); eq(effects[1].count, 2)
		eq(b.s.items[1].category, "jewelry"); eq(b.s.items[1].costs.MS, 1); eq(b.s.items[1].costs.OS, 0)
		eq(b.s.items[2].category, "weapon"); eq(b.s.items[2].costs.MS, 2)
		eq(b.refused({ type = "LOOT_OPENED", items = { RING } }), "BAD_STATE")
	end)

	it("an orange is priced by the council", function()
		local b = bench()
		b.loot({ ORANGE })
		truthy(b.s.items[1].council)
		isNil(b.s.items[1].costs.MS)
		eq(b.s.items[1].costs.OS, 0)
	end)

	it("refuses a malformed item list", function()
		local b = bench()
		eq(b.refused({ type = "LOOT_OPENED", items = { { itemID = "x" } } }), "item")
		eq(b.refused({ type = "LOOT_OPENED" }), "items")
	end)

	it("the ML corrects and removes items before the start, always with a reason", function()
		local b = bench()
		b.loot({ RING, SHOULDER })
		eq(b.refused({ type = "CORRECT_ITEM", by = ML, index = 1, cost = 3 }), "REASON_REQUIRED")
		eq(b.refused({ type = "CORRECT_ITEM", by = ML, index = 1, cost = 3, reason = "BECAUSE" }), "REASON_REQUIRED")
		eq(b.refused({ type = "CORRECT_ITEM", by = ML, index = 1, category = "hat", reason = "WRONG_CATEGORY" }),
			"category")
		eq(b.refused({ type = "CORRECT_ITEM", by = ML, index = 1, cost = -1, reason = "WRONG_CATEGORY" }), "cost")
		eq(b.refused({ type = "CORRECT_ITEM", by = ML, index = 9, cost = 1, reason = "WRONG_CATEGORY" }), "index")
		eq(b.refused({ type = "CORRECT_ITEM", by = "Bryn", index = 1, cost = 3, reason = "WRONG_CATEGORY" }), "NOT_ML")
		b.ml("CORRECT_ITEM", { index = 1, category = "weapon", reason = "WRONG_CATEGORY" })
		eq(b.s.items[1].category, "weapon"); eq(b.s.items[1].costs.MS, 2)
		b.ml("CORRECT_ITEM", { index = 1, cost = 3, reason = "COUNCIL_COST" })
		eq(b.s.items[1].costs.MS, 3); eq(b.s.items[1].costs.OS, 0)
		eq(#b.s.items[1].corrections, 2)
		b.ml("REMOVE_ITEM", { index = 2 })
		eq(#b.s.items, 1)
	end)
end)

describe("announcing and opening a roll", function()
	it("START announces every item with its category and cost", function()
		local b = bench({ rules = manual() })
		b.loot({ RING, SWORD })
		local effects = b.ml("START")
		eq(b.s.state, "ANNOUNCING")
		eq(effects[1].type, "ANNOUNCE_ITEMS")
		eq(#effects[1].items, 2)
		eq(effects[1].items[2].category, "weapon"); eq(effects[1].items[2].costs.MS, 2)
		eq(count(effects, "OPEN_ROUND"), 0, "autoAdvance off: the ML opens the roll")
	end)

	it("the ML opens the roll: the raid and the credits are frozen on the item", function()
		local b = bench({ rules = manual(), credits = { Aurel = 0, Bryn = 2, Corin = 3 } })
		b.start({ RING, SWORD })
		local effects = b.ml("OPEN_ROLL", { index = 2 })
		eq(b.s.state, "ROLLING"); eq(b.s.active, 2)
		local item = b.item()
		eq(item.state, "ROLLING")
		deepEq(item.credits, { Aurel = 0, Bryn = 2, Corin = 3 })
		deepEq(item.present, RAID)
		truthy(item.round.collect)
		eq(item.round.tier, 1)
		eq(item.round.deadline, 1030)
		eq(effects[1].type, "OPEN_ROUND"); eq(effects[1].item, 2); eq(effects[1].deadline, 1030)
		eq(b.refused({ type = "OPEN_ROLL", by = ML, index = 1 }), "ITEM_IN_PROGRESS")
	end)

	it("without credits in env the item takes the season's credits from the ledger", function()
		local b = bench({ rules = manual() })
		assert(Lg().Append(b.L, { author = ML, ts = 10, season = SEASON, type = "ITEM_AWARDED",
			payload = { member = "Bryn", item = 1, cost = 2 } }))
		b.start()
		b.ml("OPEN_ROLL")
		eq(b.item().credits.Bryn, 2)
	end)

	it("with autoAdvance the roll of the first pending item opens by itself", function()
		local b = bench()
		local effects = b.start({ RING, SWORD })
		eq(b.s.state, "ROLLING"); eq(b.s.active, 1)
		eq(count(effects, "OPEN_ROUND"), 1)
	end)
end)

describe("rolling and computing: the regulation examples", function()
	it("ring: same credits, the highest roll wins (closed by the ML)", function()
		local b = bench({ rules = manual(), credits = { Aurel = 0, Bryn = 0, Corin = 0 } })
		b.start()
		b.ml("OPEN_ROLL")
		answerAll(b, { Aurel = "MS", Bryn = "MS", Corin = "MS" })
		rollAll(b, { Aurel = 45, Bryn = 76, Corin = 12 })
		eq(b.s.state, "ROLLING", "autoAdvance off: the round waits for the ML")
		b.ml("CLOSE_ROUND")
		eq(b.s.state, "PROPOSAL")
		local p = b.proposal()
		eq(p.kind, "AWARD"); eq(p.winner, "Bryn"); eq(p.cost, 1); eq(p.response, "MS"); eq(p.roll, 76)
		deepEq(p.reasons, { "MAIN_SPEC_TIER", "HIGHER_ROLL" })
		eq(#b.item().rounds, 1)
		isNil(b.item().round)
	end)

	it("shoulder: fewer credits wins, the round closes on its timer", function()
		local b = bench({ credits = { Aurel = 0, Bryn = 2, Corin = 3 } })
		b.start({ SHOULDER })
		b.respond("Aurel", "MS"); b.respond("Bryn", "MS"); b.respond("Corin", "MS")
		rollAll(b, { Aurel = 34, Bryn = 90, Corin = 99 })
		eq(b.s.state, "ROLLING", "Dara has not answered yet")
		b.must({ type = "TICK", ts = 1029 })
		eq(b.s.state, "ROLLING")
		local effects = b.must({ type = "TICK", ts = 1030 })
		eq(b.s.state, "PROPOSAL")
		eq(count(effects, "CLOSE_ROUND"), 1); eq(count(effects, "PROPOSAL"), 1)
		eq(b.proposal().winner, "Aurel")
		deepEq(b.proposal().reasons, { "MAIN_SPEC_TIER", "LOWER_CREDITS" })
		eq(b.s.log[#b.s.log].type, "AUTO_CLOSE"); eq(b.s.log[#b.s.log].code, "TIMER")
	end)

	it("the round closes as soon as everybody has answered and rolled (autoAdvance)", function()
		local b = bench({ credits = { Aurel = 0, Bryn = 2, Corin = 3 } })
		b.start({ SHOULDER })
		answerAll(b, { Aurel = "MS", Bryn = "MS", Corin = "MS" })
		b.roll("Aurel", 34); b.roll("Bryn", 90)
		eq(b.s.state, "ROLLING")
		b.roll("Corin", 99)
		eq(b.s.state, "PROPOSAL")
		eq(b.s.log[#b.s.log].code, "ALL_ROLLED")
	end)

	it("without autoAdvance the expired timer is only reported, once", function()
		local b = bench({ rules = manual() })
		b.start()
		b.ml("OPEN_ROLL")
		local effects = b.must({ type = "TICK", ts = 1031 })
		eq(count(effects, "TIMER_EXPIRED"), 1)
		eq(b.s.state, "ROLLING")
		effects = b.must({ type = "TICK", ts = 1040 })
		eq(count(effects, "TIMER_EXPIRED"), 0)
	end)

	it("cloak: a full tie opens a reroll among the tied only (the ML advances)", function()
		local b = bench({ rules = manual(), credits = { Aurel = 1, Bryn = 1, Corin = 1 } })
		b.start()
		b.ml("OPEN_ROLL")
		answerAll(b, { Aurel = "MS", Bryn = "MS", Corin = "MS" })
		rollAll(b, { Aurel = 40, Bryn = 88, Corin = 88 })
		local effects = b.ml("CLOSE_ROUND")
		eq(b.s.state, "COMPUTING")
		eq(b.item().state, "COMPUTING")
		eq(b.item().next.kind, "REROLL")
		deepEq(b.item().next.among, { "Bryn", "Corin" })
		eq(count(effects, "NEXT_ROUND"), 1)
		eq(b.refused({ type = "ADVANCE", by = "Bryn" }), "NOT_ML")
		b.ml("ADVANCE")
		eq(b.s.state, "ROLLING")
		eq(b.item().round.kind, "REROLL"); falsy(b.item().round.collect)
		eq(b.refused({ type = "RESPONSE", player = "Aurel", response = "MS" }), "RESPONSES_CLOSED")
		b.roll("Aurel", 99); b.roll("Bryn", 30); b.roll("Corin", 70)
		b.ml("CLOSE_ROUND")
		eq(b.s.state, "PROPOSAL")
		local p = b.proposal()
		eq(p.winner, "Corin"); eq(p.reroll, 70)
		deepEq(p.reasons, { "MAIN_SPEC_TIER", "REROLL_WON" })
		truthy(has(p.flags, "DISCARDED_ROLLS"))
		local found = false
		for _, d in ipairs(b.item().discarded) do
			if d.player == "Aurel" and d.code == "NOT_ELIGIBLE" then found = true end
		end
		truthy(found, "Aurel's reroll is discarded")
	end)

	it("cloak with autoAdvance: the reroll opens and closes by itself", function()
		local b = bench({ credits = { Aurel = 1, Bryn = 1, Corin = 1 } })
		b.start()
		answerAll(b, { Aurel = "MS", Bryn = "MS", Corin = "MS" })
		rollAll(b, { Aurel = 40, Bryn = 88, Corin = 88 })
		eq(b.s.state, "ROLLING")
		eq(b.item().round.kind, "REROLL")
		deepEq(b.item().round.among, { "Bryn", "Corin" })
		b.roll("Bryn", 30)
		eq(b.s.state, "ROLLING")
		b.roll("Corin", 70)
		eq(b.s.state, "PROPOSAL")
		eq(b.proposal().winner, "Corin")
	end)

	it("empty tier: nobody main-spec, the off-spec tier opens among the off-spec responders", function()
		local b = bench({ rules = manual() })
		b.start()
		b.ml("OPEN_ROLL")
		answerAll(b, { Aurel = "OS", Bryn = "OS" })
		b.roll("Aurel", 50)   -- too early: off-spec rolls when tier 2 opens
		b.ml("CLOSE_ROUND")
		eq(b.s.state, "COMPUTING")
		eq(b.item().next.tier, 2)
		deepEq(b.item().next.among, { "Aurel", "Bryn" })
		eq(b.item().dropped.code, "TIER_EMPTY")
		eq(#b.item().dropped.rolls, 1)
		eq(#b.item().rounds, 0)
		b.ml("ADVANCE")
		eq(b.item().round.tier, 2)
		b.roll("Aurel", 20); b.roll("Bryn", 60)
		b.ml("CLOSE_ROUND")
		local p = b.proposal()
		eq(p.winner, "Bryn"); eq(p.cost, 0); eq(p.response, "OS"); eq(p.tier, 2)
		deepEq(p.reasons, { "OFFSPEC_TIER", "HIGHER_ROLL" })
	end)

	it("empty tier: the main-spec responders did not roll, the next tier opens", function()
		local b = bench({ rules = manual() })
		b.start()
		b.ml("OPEN_ROLL")
		answerAll(b, { Aurel = "MS", Bryn = "OS" })
		b.ml("CLOSE_ROUND")
		eq(#b.item().rounds, 1, "the first round was tier 1's round")
		eq(b.s.state, "COMPUTING")
		eq(b.item().next.tier, 2); deepEq(b.item().next.among, { "Bryn" })
	end)

	it("fallback: a BoE nobody needs goes to the bank", function()
		local b = bench({ rules = manual(function(r) r.priority.bankCharacter = "Oste" end) })
		b.start({ BOE })
		b.ml("OPEN_ROLL")
		answerAll(b, { Aurel = "OS" })
		b.ml("CLOSE_ROUND")
		local p = b.proposal()
		eq(p.kind, "BANK"); eq(p.winner, "Oste"); eq(p.cost, 0)
		deepEq(p.reasons, { "BOE_BANK" })
		b.ml("CONFIRM")
		local e = b.events()[1]
		eq(e.payload.target, "bank"); eq(e.payload.member, "Oste"); eq(e.payload.cost, 0)
		deepEq(Lg().Credits(b.L, SEASON), {})
	end)

	it("fallback without a bank character: the ML must decide", function()
		local b = bench({ rules = manual() })
		b.start({ BOE })
		b.ml("OPEN_ROLL")
		b.ml("CLOSE_ROUND")
		eq(b.proposal().kind, "BANK")
		truthy(has(b.proposal().flags, "NO_BANK_CHARACTER"))
		eq(b.refused({ type = "CONFIRM", by = ML }), "NO_WINNER")
	end)

	it("fallback to the ML: no winner until the ML modifies, flagged ML_DECIDED", function()
		local b = bench({ rules = manual() })
		b.start()
		b.ml("OPEN_ROLL")
		answerAll(b, {})
		b.ml("CLOSE_ROUND")
		local p = b.proposal()
		eq(p.kind, "ML"); isNil(p.winner)
		deepEq(p.reasons, { "FALLBACK_ML" })
		eq(b.refused({ type = "CONFIRM", by = ML }), "NO_WINNER")
		b.ml("MODIFY", { winner = "Corin", reason = "OTHER" })
		p = b.proposal()
		eq(p.kind, "AWARD"); eq(p.winner, "Corin"); eq(p.cost, 1, "no response: the full cost")
		truthy(has(p.flags, "ML_DECIDED")); falsy(has(p.flags, "OUT_OF_ORDER"))
		b.ml("CONFIRM")
		local e = b.events()[1]
		eq(e.payload.member, "Corin"); eq(e.payload.cost, 1)
		truthy(e.payload.intervention); eq(e.payload.mlReason, "OTHER"); isNil(e.payload.ruleWinner)
		eq(Lg().Credits(b.L, SEASON).Corin, 1)
	end)

	it("free roll fallback: everybody present with the addon rolls", function()
		local b = bench({ rules = manual(function(r) r.priority.fallback = "freeroll" end) })
		b.start()
		b.ml("OPEN_ROLL")
		answerAll(b, {})
		b.ml("CLOSE_ROUND")
		eq(b.s.state, "COMPUTING")
		eq(b.item().next.stage, "FREE_ROLL"); isNil(b.item().next.among)
		b.ml("ADVANCE")
		b.roll("Aurel", 10); b.roll("Dara", 95)
		b.ml("CLOSE_ROUND")
		eq(b.proposal().winner, "Dara"); eq(b.proposal().cost, 0)
		truthy(has(b.proposal().reasons, "FALLBACK_FREE_ROLL"))
	end)

	it("a council cost leaves the proposal without a cost until the ML sets it", function()
		local b = bench({ rules = manual() })
		b.start({ ORANGE })
		b.ml("OPEN_ROLL")
		answerAll(b, { Aurel = "MS" })
		b.roll("Aurel", 5)
		b.ml("CLOSE_ROUND")
		eq(b.proposal().winner, "Aurel"); isNil(b.proposal().cost)
		truthy(has(b.proposal().flags, "COST_BY_COUNCIL"))
		eq(b.refused({ type = "CONFIRM", by = ML }), "NO_COST")
		b.ml("MODIFY", { cost = 4, reason = "COUNCIL_COST" })
		eq(b.proposal().winner, "Aurel"); eq(b.proposal().cost, 4)
		truthy(has(b.proposal().flags, "ML_DECIDED")); falsy(has(b.proposal().flags, "OUT_OF_ORDER"))
		b.ml("CONFIRM")
		eq(Lg().Credits(b.L, SEASON).Aurel, 4)
	end)
end)

describe("the proposal: confirm", function()
	local function ringProposal(opts)
		opts = opts or {}
		local b = bench({ rules = opts.rules or manual(), credits = { Aurel = 0, Bryn = 0, Corin = 0 }, gate = opts.gate })
		b.start(opts.items)
		if b.s.state == "ANNOUNCING" then b.ml("OPEN_ROLL") end
		answerAll(b, { Aurel = "MS", Bryn = "MS", Corin = "MS" })
		rollAll(b, { Aurel = 45, Bryn = 76, Corin = 12 })
		if b.s.state == "ROLLING" then b.ml("CLOSE_ROUND") end
		return b
	end

	it("writes ITEM_AWARDED with the addon's reason codes and charges the credits", function()
		local b = ringProposal()
		local effects = b.ml("CONFIRM")
		eq(b.s.state, "ANNOUNCING"); isNil(b.s.active)
		eq(b.s.items[1].state, "ASSIGNED")
		local events = b.events()
		eq(#events, 1)
		local e = events[1]
		eq(e.author, ML); eq(e.season, SEASON)
		eq(e.payload.target, "member"); eq(e.payload.member, "Bryn"); eq(e.payload.item, RING.itemID)
		eq(e.payload.cost, 1); eq(e.payload.response, "MS"); eq(e.payload.roll, 76)
		deepEq(e.payload.reasons, { "MAIN_SPEC_TIER", "HIGHER_ROLL" })
		eq(e.payload.session, "S1-1"); eq(e.payload.encounter, 601)
		isNil(e.payload.intervention); isNil(e.payload.auto)
		eq(#e.payload.rivals, 2)
		eq(Lg().Credits(b.L, SEASON).Bryn, 1)
		eq(b.s.items[1].award.event, e.id)
		eq(count(effects, "AWARDED"), 1)
		local deliver
		for _, x in ipairs(effects) do if x.type == "DELIVER" then deliver = x end end
		eq(deliver.slot, RING.slot); eq(deliver.winner, "Bryn")
	end)

	it("assigned -> delivered, only to the winner", function()
		local b = ringProposal()
		b.ml("CONFIRM")
		deepEq(F().Undelivered(b.s), { 1 })
		eq(b.refused({ type = "DELIVERED", index = 1, player = "Aurel" }), "WRONG_PLAYER")
		b.must({ type = "DELIVERED", index = 1, player = "Bryn" })
		eq(b.s.items[1].state, "DELIVERED")
		deepEq(F().Undelivered(b.s), {})
		eq(b.refused({ type = "DELIVERED", index = 1, player = "Bryn" }), "NOT_ASSIGNED")
	end)

	it("a refused event (the trust gate) changes nothing", function()
		local b = ringProposal({ gate = { accept = function() return false, "RANK_TOO_LOW" end } })
		eq(b.refused({ type = "CONFIRM", by = ML }), "RANK_TOO_LOW")
		eq(b.s.state, "PROPOSAL")
		eq(Lg().Count(b.L), 0)
	end)

	it("only the master looter confirms", function()
		local b = ringProposal()
		eq(b.refused({ type = "CONFIRM", by = "Bryn" }), "NOT_ML")
		eq(b.refused({ type = "CONFIRM" }), "NOT_ML")
	end)

	it("with autoAdvance the next item opens after the confirm, with the new credits", function()
		local b = ringProposal({ rules = rules(), items = { RING, SWORD } })
		eq(b.s.state, "PROPOSAL")
		b.ml("CONFIRM")
		eq(b.s.state, "ROLLING"); eq(b.s.active, 2)
		eq(b.item().credits.Bryn, 0, "env.credits wins over the ledger in this bench")
	end)

	describe("reject", function()
		it("PENDING: no charge, the item waits for the ML (autoAdvance does not reopen it)", function()
			local b = ringProposal({ rules = rules() })
			eq(b.s.state, "PROPOSAL")
			local effects = b.ml("REJECT", { reason = "MISTAKE" })
			eq(count(effects, "REJECTED"), 1)
			eq(b.s.state, "ANNOUNCING")
			eq(b.s.items[1].state, "PENDING")
			truthy(b.s.items[1].hold)
			eq(Lg().Count(b.L), 0)
			deepEq(b.s.items[1].responses, {})
			eq(b.s.items[1].rejected[1].winner, "Bryn")
			b.ml("OPEN_ROLL", { index = 1 })
			eq(b.s.state, "ROLLING")
			falsy(b.s.items[1].hold)
		end)

		it("REOPEN: a fresh roll at once", function()
			local b = ringProposal()
			local effects = b.ml("REJECT", { ["then"] = "REOPEN" })
			eq(b.s.state, "ROLLING"); eq(b.s.active, 1)
			truthy(b.item().round.collect)
			deepEq(b.item().rounds, {})
			eq(count(effects, "OPEN_ROUND"), 1)
			answerAll(b, { Corin = "MS" })
			b.roll("Corin", 3)
			b.ml("CLOSE_ROUND")
			eq(b.proposal().winner, "Corin")
			truthy(has(b.proposal().flags, "AFTER_REJECT"))
		end)

		it("NEXT_TIER: the off-spec responders roll", function()
			local b = bench({ rules = manual() })
			b.start()
			b.ml("OPEN_ROLL")
			answerAll(b, { Aurel = "MS", Bryn = "MS", Corin = "OS" })
			rollAll(b, { Aurel = 45, Bryn = 76 })
			b.ml("CLOSE_ROUND")
			eq(b.proposal().winner, "Bryn")
			b.ml("REJECT", { ["then"] = "NEXT_TIER", reason = "OBVIOUS_WASTE" })
			eq(b.s.state, "COMPUTING")
			eq(b.item().next.tier, 2); deepEq(b.item().next.among, { "Corin" })
			b.ml("ADVANCE")
			b.roll("Corin", 5)
			b.ml("CLOSE_ROUND")
			local p = b.proposal()
			eq(p.winner, "Corin"); eq(p.cost, 0)
			truthy(has(p.reasons, "OFFSPEC_TIER")); truthy(has(p.flags, "AFTER_REJECT"))
		end)

		it("NEXT_TIER without off-spec responders goes to the fallback", function()
			local b = ringProposal()
			b.ml("REJECT", { ["then"] = "NEXT_TIER" })
			eq(b.s.state, "PROPOSAL")
			eq(b.proposal().kind, "ML")
			eq(b.refused({ type = "REJECT", by = ML, ["then"] = "NEXT_TIER" }), "NO_TIER")
		end)

		it("BANK and DISENCHANT", function()
			local b = ringProposal({ rules = manual(function(r) r.priority.bankCharacter = "Oste" end) })
			b.ml("REJECT", { ["then"] = "BANK" })
			local p = b.proposal()
			eq(p.kind, "BANK"); eq(p.winner, "Oste"); eq(p.cost, 0)
			deepEq(p.reasons, { "REJECTED_TO_BANK" }); truthy(has(p.flags, "AFTER_REJECT"))
			b.ml("REJECT", { ["then"] = "DISENCHANT" })
			p = b.proposal()
			eq(p.kind, "DISENCHANT"); isNil(p.winner)
			truthy(has(p.flags, "NO_DISENCHANTER"))
			eq(#b.item().rejected, 2)
		end)

		it("refuses an unknown follow-up or reason", function()
			local b = ringProposal()
			eq(b.refused({ type = "REJECT", by = ML, ["then"] = "BURN" }), "then")
			eq(b.refused({ type = "REJECT", by = ML, reason = "bad" }), "reason")
		end)
	end)

	describe("modify", function()
		it("the reason is mandatory", function()
			local b = ringProposal()
			eq(b.refused({ type = "MODIFY", by = ML, winner = "Corin" }), "REASON_REQUIRED")
			eq(b.refused({ type = "MODIFY", by = ML, winner = "Corin", reason = "x" }), "REASON_REQUIRED")
			eq(b.refused({ type = "MODIFY", by = ML, reason = "OTHER" }), "NOTHING_CHANGED")
			eq(b.refused({ type = "MODIFY", by = ML, winner = "a:b", reason = "OTHER" }), "winner")
			eq(b.refused({ type = "MODIFY", by = ML, cost = -2, reason = "OTHER" }), "cost")
			eq(b.refused({ type = "MODIFY", by = ML, target = "ml", reason = "OTHER" }), "target")
		end)

		it("another winner: flagged out of order, the rule's winner kept for the audit", function()
			local b = ringProposal()
			local effects = b.ml("MODIFY", { winner = "Corin", reason = "OBVIOUS_WASTE" })
			eq(effects[1].type, "PROPOSAL"); truthy(effects[1].modified)
			eq(b.s.state, "PROPOSAL")
			local p = b.proposal()
			eq(p.winner, "Corin"); eq(p.cost, 1); eq(p.response, "MS")
			deepEq(p.reasons, { "ML_CHOICE" })
			truthy(has(p.flags, "OUT_OF_ORDER")); falsy(has(p.flags, "COST_CHANGED"))
			b.ml("MODIFY", { cost = 0.5, reason = "OTHER" })
			p = b.proposal()
			eq(p.winner, "Corin"); eq(p.cost, 0.5)
			truthy(has(p.flags, "OUT_OF_ORDER")); truthy(has(p.flags, "COST_CHANGED"))
			b.ml("CONFIRM")
			local e = b.events()[1]
			truthy(e.payload.intervention); eq(e.payload.mlReason, "OTHER")
			eq(e.payload.ruleWinner, "Bryn"); eq(e.payload.ruleCost, 1)
			eq(e.payload.member, "Corin"); eq(e.payload.cost, 0.5)
			truthy(has(e.payload.flags, "OUT_OF_ORDER"))
			eq(Lg().Credits(b.L, SEASON).Corin, 0.5)
		end)

		it("to a player who passed: the full cost (§3.6)", function()
			local b = ringProposal()
			b.ml("MODIFY", { winner = "Dara", reason = "PASSED_TO_GAME" })
			eq(b.proposal().cost, 1); isNil(b.proposal().response)
		end)

		it("back to the rule's winner and cost: no out-of-order flag", function()
			local b = ringProposal()
			b.ml("MODIFY", { winner = "Corin", reason = "MISTAKE" })
			b.ml("MODIFY", { winner = "Bryn", reason = "MISTAKE" })
			falsy(has(b.proposal().flags, "OUT_OF_ORDER"))
		end)

		it("to the bank: the bank character, cost 0", function()
			local b = ringProposal({ rules = manual(function(r) r.priority.bankCharacter = "Oste" end) })
			b.ml("MODIFY", { target = "bank", reason = "OTHER" })
			eq(b.proposal().kind, "BANK"); eq(b.proposal().winner, "Oste"); eq(b.proposal().cost, 0)
			truthy(has(b.proposal().flags, "OUT_OF_ORDER"))
			b.ml("CONFIRM")
			eq(b.events()[1].payload.target, "bank")
		end)
	end)
end)

describe("pause", function()
	it("stops the timer and keeps its remaining time", function()
		local b = bench()
		b.start()
		eq(b.item().round.deadline, 1030)
		b.ml("PAUSE", { ts = 1010 })
		truthy(b.s.paused)
		isNil(b.item().round.deadline); eq(b.item().round.remaining, 20)
		eq(b.refused({ type = "PAUSE", by = ML, ts = 1011 }), "PAUSED")
		b.must({ type = "TICK", ts = 1100 })
		eq(b.s.state, "ROLLING")
		b.roll("Aurel", 10)   -- rolls are still recorded
		eq(#b.item().round.rolls, 1)
		b.ml("RESUME", { ts = 1200 })
		eq(b.item().round.deadline, 1220)
		b.must({ type = "TICK", ts = 1219 })
		eq(b.s.state, "ROLLING")
		b.must({ type = "TICK", ts = 1220 })
		eq(b.s.state, "PROPOSAL")
		eq(b.refused({ type = "RESUME", by = ML }), "NOT_PAUSED")
	end)

	it("stops auto-advance; the ML's own commands still work", function()
		local b = bench({ credits = { Aurel = 1, Bryn = 1, Corin = 1 } })
		b.loot({ RING })
		b.ml("PAUSE")
		b.ml("START")
		eq(b.s.state, "ANNOUNCING", "paused: the roll does not open by itself")
		b.ml("OPEN_ROLL")
		answerAll(b, { Aurel = "MS", Bryn = "MS", Corin = "MS" })
		rollAll(b, { Aurel = 40, Bryn = 88, Corin = 88 })
		eq(b.s.state, "ROLLING", "paused: the round does not close by itself")
		b.ml("CLOSE_ROUND")
		eq(b.s.state, "COMPUTING", "paused: the reroll does not open by itself")
		b.ml("RESUME")
		eq(b.s.state, "ROLLING"); eq(b.item().round.kind, "REROLL")
	end)
end)

describe("award modes", function()
	local function autoBench(mutate, items)
		local b = bench({ rules = rules(function(r)
			r.session.awardMode = "auto"
			if mutate then mutate(r) end
		end), credits = { Aurel = 0, Bryn = 0, Corin = 0 } })
		b.start(items)
		answerAll(b, { Aurel = "MS", Bryn = "MS", Corin = "MS" })
		b.at(1010)
		rollAll(b, { Aurel = 45, Bryn = 76, Corin = 12 })
		return b
	end

	it("auto: the addon assigns by itself after the intervention window", function()
		local b = autoBench(nil, { RING, SWORD })
		eq(b.s.state, "PROPOSAL")
		eq(b.item().autoAt, 1040)
		b.must({ type = "TICK", ts = 1039 })
		eq(b.s.state, "PROPOSAL")
		local effects = b.must({ type = "TICK", ts = 1040 })
		eq(count(effects, "AWARDED"), 1)
		eq(b.s.items[1].state, "ASSIGNED")
		local e = b.events()[1]
		truthy(e.payload.auto); eq(e.payload.member, "Bryn")
		eq(b.s.state, "ROLLING"); eq(b.s.active, 2, "autoAdvance opens the next item")
	end)

	it("auto: the ML can still confirm, modify or reject inside the window", function()
		local b = autoBench()
		b.ml("MODIFY", { winner = "Corin", reason = "OBVIOUS_WASTE" })
		isNil(b.item().autoAt)
		b.must({ type = "TICK", ts = 5000 })
		eq(b.s.state, "PROPOSAL", "an intervention waits for the ML")
		b.ml("CONFIRM")
		eq(b.events()[1].payload.member, "Corin")
	end)

	it("auto: a proposal that needs a look is never written alone", function()
		local b = bench({ rules = rules(function(r) r.session.awardMode = "auto" end) })
		b.start()
		answerAll(b, {})
		eq(b.proposal().kind, "ML")
		isNil(b.item().autoAt)
		falsy(F().Ready(b.proposal()))
		truthy(F().Ready({ winner = "x", cost = 1, flags = { "DISCARDED_ROLLS" } }))
	end)

	it("auto: the window stops while paused", function()
		local b = autoBench()
		b.ml("PAUSE", { ts = 1020 })
		eq(b.item().autoRemaining, 20)
		b.must({ type = "TICK", ts = 3000 })
		eq(b.s.state, "PROPOSAL")
		b.ml("RESUME", { ts = 4000 })
		eq(b.item().autoAt, 4020)
		b.must({ type = "TICK", ts = 4020 })
		eq(b.s.items[1].state, "ASSIGNED")
	end)

	it("auto: a refused write falls back to the ML", function()
		local b = bench({ rules = rules(function(r) r.session.awardMode = "auto" end),
			gate = { accept = function() return false, "RANK_TOO_LOW" end } })
		b.start()
		answerAll(b, { Aurel = "MS" })
		b.roll("Aurel", 50)
		local effects = b.must({ type = "TICK", ts = 2000 })
		eq(count(effects, "AUTO_FAILED"), 1)
		eq(b.s.state, "PROPOSAL"); isNil(b.item().autoAt)
	end)

	local function councilBench()
		local b = bench({ rules = rules(function(r) r.session.awardMode = "council" end),
			credits = { Aurel = 0, Bryn = 0, Corin = 0 } })
		b.start()
		answerAll(b, { Aurel = "MS", Bryn = "MS", Corin = "MS" })
		rollAll(b, { Aurel = 45, Bryn = 76, Corin = 12 })
		return b
	end

	it("council: the vote decides; another winner is an intervention", function()
		local b = councilBench()
		eq(b.proposal().winner, "Bryn")
		isNil(b.item().autoAt)
		eq(b.refused({ type = "CONFIRM", by = ML }), "VOTE_OPEN")
		eq(b.refused({ type = "CLOSE_VOTE", by = ML }), "NO_VOTES")
		b.must({ type = "VOTE", by = "Eldon", choice = "Bryn" })
		b.must({ type = "VOTE", by = "Fen", choice = "Corin" })
		eq(b.refused({ type = "CLOSE_VOTE", by = ML }), "VOTE_TIE")
		b.must({ type = "VOTE", by = "Gwen", choice = "Corin" })
		b.ml("CLOSE_VOTE")
		eq(b.proposal().winner, "Corin")
		truthy(has(b.proposal().flags, "OUT_OF_ORDER"))
		eq(b.refused({ type = "VOTE", by = "Hale", choice = "Bryn" }), "VOTE_CLOSED")
		b.ml("CONFIRM")
		local e = b.events()[1]
		eq(e.payload.member, "Corin"); eq(e.payload.mlReason, "COUNCIL_VOTE"); truthy(e.payload.intervention)
		deepEq(e.payload.votes, { Bryn = 1, Corin = 2 })
	end)

	it("council: a vote for the rule's winner is not an intervention", function()
		local b = councilBench()
		b.must({ type = "VOTE", by = "Eldon", choice = "Bryn" })
		b.must({ type = "VOTE", by = "Eldon", choice = "Bryn" })   -- a voter changes or repeats, one vote
		b.ml("CLOSE_VOTE")
		b.ml("CONFIRM")
		local e = b.events()[1]
		eq(e.payload.member, "Bryn"); isNil(e.payload.intervention)
		deepEq(e.payload.votes, { Bryn = 1 })
	end)

	it("council: the ML may still decide by modifying (with a reason)", function()
		local b = councilBench()
		b.ml("MODIFY", { winner = "Aurel", reason = "OBVIOUS_WASTE" })
		b.ml("CONFIRM")
		eq(b.events()[1].payload.member, "Aurel")
	end)

	it("votes exist only in council mode", function()
		local b = bench({ rules = manual() })
		b.start()
		b.ml("OPEN_ROLL")
		answerAll(b, { Aurel = "MS" })
		b.roll("Aurel", 1)
		b.ml("CLOSE_ROUND")
		eq(b.refused({ type = "VOTE", by = "Eldon", choice = "Aurel" }), "NOT_COUNCIL_MODE")
		eq(b.refused({ type = "CLOSE_VOTE", by = ML }), "NOT_COUNCIL_MODE")
	end)
end)

describe("§4.1: only raiders with the addon active roll", function()
	local PRESENT = { Aurel = true, Bryn = true, Corin = true, Dara = true, Eldon = true }

	it("the ML is warned at the start, the response is refused, the roll is discarded as NO_ADDON", function()
		local b = bench({ present = PRESENT, addon = RAID, credits = { Aurel = 0, Bryn = 0, Corin = 0 } })
		b.loot({ RING, SWORD })
		local effects = b.ml("START")
		local warn
		for _, e in ipairs(effects) do if e.type == "NO_ADDON" then warn = e end end
		deepEq(warn.players, { "Eldon" })
		eq(b.refused({ type = "RESPONSE", player = "Eldon", response = "MS" }), "NO_ADDON")
		eq(b.refused({ type = "RESPONSE", player = "Zed", response = "MS" }), "NOT_PRESENT")
		b.roll("Eldon", 100)   -- a /roll by hand is kept, then discarded
		answerAll(b, { Aurel = "MS" })
		b.roll("Aurel", 2)
		eq(b.s.state, "PROPOSAL", "Eldon cannot roll, so he is not waited for")
		eq(b.proposal().winner, "Aurel")
		local found = false
		for _, d in ipairs(b.item().discarded) do
			if d.player == "Eldon" and d.code == "NO_ADDON" then found = true end
		end
		truthy(found)
	end)

	it("a player who activates the addon comes back from the next item", function()
		local b = bench({ rules = manual(), present = PRESENT, addon = RAID })
		b.start({ RING, SWORD })
		b.ml("OPEN_ROLL", { index = 1 })
		b.must({ type = "SET_RAID", present = PRESENT, addon = PRESENT })
		eq(b.refused({ type = "RESPONSE", player = "Eldon", response = "MS" }), "NO_ADDON")
		b.ml("CLOSE_ROUND")
		b.ml("MODIFY", { winner = "Aurel", reason = "OTHER" })
		b.ml("CONFIRM")
		b.ml("OPEN_ROLL", { index = 2 })
		b.respond("Eldon", "MS")
		eq(b.item().responses.Eldon, "MS")
	end)

	it("with allowNoAddon (requireAddon off) everybody present rolls", function()
		local b = bench({ rules = manual(function(r) r.priority.requireAddon = false end), present = PRESENT,
			addon = RAID })
		b.start()
		b.ml("OPEN_ROLL")
		b.respond("Eldon", "MS")
		b.roll("Eldon", 40)
		b.ml("CLOSE_ROUND")
		eq(b.proposal().winner, "Eldon")
	end)
end)

describe("guards", function()
	it("refuses unknown inputs, a missing time and inputs out of state", function()
		local b = bench()
		eq(b.refused({ type = "DANCE" }), "UNKNOWN_INPUT")
		eq(F().Step(b.s, { type = "TICK" }, {}), nil)
		local _, code = F().Step(b.s, { type = "TICK" }, {})
		eq(code, "ts")
		eq(b.refused({ type = "CONFIRM", by = ML }), "BAD_STATE")
		eq(b.refused({ type = "START", by = ML }), "BAD_STATE")
		eq(b.refused({ type = "OPEN_ROLL", by = ML }), "BAD_STATE")
		eq(b.refused({ type = "CLOSE_ROUND", by = ML }), "BAD_STATE")
		eq(b.refused({ type = "ADVANCE", by = ML }), "BAD_STATE")
		eq(b.refused({ type = "ROLL", player = "Aurel", value = 5, min = 1, max = 100 }), "NO_ROUND_OPEN")
		eq(b.refused({ type = "RESPONSE", player = "Aurel", response = "MS" }), "RESPONSES_CLOSED")
		eq(b.refused({ type = "LOCKDOWN", active = "yes" }), "active")
	end)

	it("a response is final once the player rolled; unknown or disabled responses are refused", function()
		local b = bench({ rules = manual() })
		b.start()
		b.ml("OPEN_ROLL")
		b.respond("Aurel", "MS")
		b.respond("Aurel", "OS")   -- changes freely before rolling
		b.respond("Aurel", "MS")
		b.roll("Aurel", 30)
		eq(b.refused({ type = "RESPONSE", player = "Aurel", response = "OS" }), "RESPONSE_LOCKED")
		eq(b.refused({ type = "RESPONSE", player = "Bryn", response = "TMOG" }), "BAD_RESPONSE")
		eq(b.refused({ type = "RESPONSE", player = "Bryn", response = "NEED" }), "BAD_RESPONSE")
		eq(b.refused({ type = "ROLL", player = "Bryn", value = "x", min = 1, max = 100 }), "value")
	end)

	it("keeps the label and the note of a response, replaces them with the latest answer, drops what is not valid (M4-6)", function()
		local b = bench({ rules = manual() })
		b.start()
		b.ml("OPEN_ROLL")
		b.must({ type = "RESPONSE", player = "Aurel", response = "MS", label = "BIS", note = "two-hander" })
		eq(b.item().labels.Aurel, "BIS"); eq(b.item().notes.Aurel, "two-hander")
		b.must({ type = "RESPONSE", player = "Aurel", response = "MS", label = "BIG_UPGRADE" })
		eq(b.item().labels.Aurel, "BIG_UPGRADE"); isNil(b.item().notes.Aurel, "the latest answer replaces the note too")
		b.must({ type = "RESPONSE", player = "Bryn", response = "OS", label = "bis", note = string.rep("x", 81) })
		isNil(b.item().labels.Bryn); isNil(b.item().notes.Bryn)
		eq(b.item().responses.Bryn, "OS", "the answer counts, only the extras are dropped")
		b.must({ type = "RESPONSE", player = "Corin", response = "PASS", label = "BIS", note = "no" })
		isNil(b.item().labels.Corin, "a pass carries neither")
		isNil(b.item().notes.Corin)
		b.must({ type = "RESPONSE", player = "Dara", response = "MS", label = 42, note = 7 })
		isNil(b.item().labels.Dara); isNil(b.item().notes.Dara)
	end)

	it("the labels and notes survive a /reload with the session and start again with a reopened roll", function()
		local b = bench({ rules = manual() })
		b.start()
		b.ml("OPEN_ROLL")
		b.must({ type = "RESPONSE", player = "Aurel", response = "MS", label = "BIS", note = "mine" })
		local restored = F().Restore(reload(b.s))
		eq(restored.items[1].labels.Aurel, "BIS"); eq(restored.items[1].notes.Aurel, "mine")
		b.must({ type = "RESPONSE", player = "Bryn", response = "MS" })
		b.roll("Bryn", 40)
		b.ml("CLOSE_ROUND")
		b.ml("REJECT", { ["then"] = "REOPEN" })
		isNil(b.item().labels, "a fresh roll starts without them")
		isNil(b.item().notes)
	end)

	it("lockCategoryOnOpen: the category is locked once the roll opened", function()
		local b = bench({ rules = manual() })
		b.start({ RING, SWORD })
		b.ml("OPEN_ROLL", { index = 1 })
		eq(b.refused({ type = "CORRECT_ITEM", by = ML, index = 1, category = "weapon", reason = "WRONG_CATEGORY" }),
			"CATEGORY_LOCKED")
		b.ml("CORRECT_ITEM", { index = 2, category = "armor", reason = "WRONG_CATEGORY" })
		eq(b.s.items[2].costs.MS, 1)
	end)

	it("without the lock the cost can change while rolling, and the proposal uses it", function()
		local b = bench({ rules = manual(function(r) r.session.lockCategoryOnOpen = false end) })
		b.start()
		b.ml("OPEN_ROLL")
		b.ml("CORRECT_ITEM", { index = 1, category = "weapon", reason = "WRONG_CATEGORY" })
		answerAll(b, { Aurel = "MS" })
		b.roll("Aurel", 30)
		b.ml("CLOSE_ROUND")
		eq(b.proposal().cost, 2)
		eq(b.refused({ type = "CORRECT_ITEM", by = ML, index = 1, cost = 1, reason = "WRONG_CATEGORY" }),
			"ITEM_SETTLED")
	end)

	it("END: never with an item in progress; lists what was not rolled or delivered; deliveries go on", function()
		local b = bench({ rules = manual() })
		b.start({ RING, SWORD })
		b.ml("OPEN_ROLL", { index = 1 })
		eq(b.refused({ type = "END", by = ML }), "ITEM_IN_PROGRESS")
		answerAll(b, { Aurel = "MS" })
		b.roll("Aurel", 30)
		b.ml("CLOSE_ROUND")
		b.ml("CONFIRM")
		local effects = b.ml("END")
		eq(b.s.state, "ENDED")
		deepEq(effects[1].unrolled, { 2 }); deepEq(effects[1].undelivered, { 1 })
		eq(b.refused({ type = "OPEN_ROLL", by = ML }), "ENDED")
		eq(b.refused({ type = "SET_RAID", present = RAID }), "ENDED")
		eq(b.refused({ type = "PAUSE", by = ML }), "ENDED")
		b.must({ type = "DELIVERED", index = 1, player = "Aurel" })
		eq(b.s.items[1].state, "DELIVERED")
	end)

	it("END from waiting or collecting", function()
		local b = bench()
		b.ml("END")
		eq(b.s.state, "ENDED")
	end)

	it("a session written by a newer addon is read-only", function()
		local b = bench()
		local t = reload(b.s)
		t.schema = F().SCHEMA + 1
		local s, readOnly = F().Restore(t)
		truthy(readOnly)
		local ok, code = F().Step(s, { type = "TICK", ts = 1 }, {})
		isNil(ok); eq(code, "READ_ONLY")
		isNil(F().Restore("x"))
	end)

	it("every input type is known", function()
		deepEq(F().INPUTS, { "ADVANCE", "CLOSE_ROUND", "CLOSE_VOTE", "CONFIRM", "CORRECT_ITEM", "DELIVERED", "END",
			"LOCKDOWN", "LOOT_OPENED", "MODIFY", "OPEN_ROLL", "PAUSE", "REJECT", "REMOVE_ITEM", "RESPONSE", "RESUME",
			"ROLL", "SET_RAID", "START", "TICK", "VOTE" })
	end)
end)

describe("a serialised session resumes identically (/reload)", function()
	-- A whole evening: a reroll, a confirm, a pause, a modify, a delayed delivery. Credits come from the ledger.
	local SCRIPT = {
		{ type = "LOOT_OPENED", ts = 1000, items = { RING, SWORD, GREEN }, encounter = 601 },
		{ type = "CORRECT_ITEM", ts = 1002, by = ML, index = 2, cost = 3, reason = "COUNCIL_COST" },
		{ type = "START", ts = 1005, by = ML },
		{ type = "RESPONSE", ts = 1006, player = "Aurel", response = "MS" },
		{ type = "RESPONSE", ts = 1006, player = "Bryn", response = "MS" },
		{ type = "RESPONSE", ts = 1007, player = "Corin", response = "MS" },
		{ type = "RESPONSE", ts = 1007, player = "Dara", response = "PASS" },
		{ type = "ROLL", ts = 1010, player = "Aurel", value = 88, min = 1, max = 100 },
		{ type = "ROLL", ts = 1011, player = "Aurel", value = 99, min = 1, max = 100 },
		{ type = "ROLL", ts = 1012, player = "Bryn", value = 88, min = 1, max = 100 },
		{ type = "ROLL", ts = 1013, player = "Corin", value = 12, min = 1, max = 1000 },
		{ type = "ROLL", ts = 1014, player = "Corin", value = 12, min = 1, max = 100 },
		{ type = "ROLL", ts = 1020, player = "Aurel", value = 40, min = 1, max = 100 },
		{ type = "TICK", ts = 1030 },
		{ type = "TICK", ts = 1044 },
		{ type = "CONFIRM", ts = 1050, by = ML },
		{ type = "PAUSE", ts = 1051, by = ML },
		{ type = "RESPONSE", ts = 1052, player = "Aurel", response = "MS" },
		{ type = "RESPONSE", ts = 1052, player = "Bryn", response = "MS" },
		{ type = "TICK", ts = 1060 },
		{ type = "RESUME", ts = 1070, by = ML },
		{ type = "RESPONSE", ts = 1071, player = "Corin", response = "OS" },
		{ type = "RESPONSE", ts = 1071, player = "Dara", response = "PASS" },
		{ type = "ROLL", ts = 1072, player = "Aurel", value = 70, min = 1, max = 100 },
		{ type = "ROLL", ts = 1073, player = "Bryn", value = 20, min = 1, max = 100 },
		{ type = "MODIFY", ts = 1080, by = ML, winner = "Corin", reason = "OBVIOUS_WASTE" },
		{ type = "CONFIRM", ts = 1081, by = ML },
		{ type = "DELIVERED", ts = 1082, index = 1, player = "Aurel" },
		{ type = "END", ts = 1090, by = ML },
		{ type = "DELIVERED", ts = 1300, index = 2, player = "Corin" },
	}

	local function run(saveEveryStep)
		local L = Lg().New()
		local s = assert(F().New({ id = "S1-1", season = SEASON, ml = ML, ts = 1000, encounter = 601,
			present = RAID, addon = RAID }))
		local all, states = {}, {}
		for i, input in ipairs(SCRIPT) do
			if saveEveryStep then
				s = assert(F().Restore(reload(s)))
				L = Lg().Open(reload(L))
			end
			local ok, code, effects = F().Step(s, reload(input), { ledger = L })
			if not ok then error("step " .. i .. " refused: " .. tostring(code)) end
			all[i] = effects
			states[i] = ser(s)
		end
		return s, L, all, states
	end

	it("the script plays as the rules say", function()
		local s, L = run(false)
		eq(s.state, "ENDED")
		eq(s.items[1].state, "DELIVERED"); eq(s.items[2].state, "DELIVERED")
		local events = Lg().Sorted(L, function(e) return e.type == "ITEM_AWARDED" end)
		eq(#events, 2)
		eq(events[1].payload.member, "Aurel"); deepEq(events[1].payload.reasons, { "MAIN_SPEC_TIER", "REROLL_WON" })
		eq(events[2].payload.member, "Corin"); eq(events[2].payload.cost, 0)
		eq(events[2].payload.ruleWinner, "Bryn"); eq(events[2].payload.ruleCost, 3)
		deepEq(Lg().Credits(L, SEASON), { Aurel = 1 })
		deepEq(s.skipped, { GREEN.itemID })
	end)

	it("saving and restoring before every input changes nothing", function()
		local s1, L1, fx1, st1 = run(false)
		local s2, L2, fx2, st2 = run(true)
		for i = 1, #SCRIPT do
			eq(st2[i], st1[i], "state after step " .. i)
			deepEq(fx2[i], fx1[i], "effects of step " .. i)
		end
		eq(ser(s2), ser(s1))
		eq(ser(L2), ser(L1))
	end)

	it("a timer that ran out during the reload closes the round at the next tick", function()
		local b = bench()
		b.start()
		b.respond("Aurel", "MS")   -- Bryn, Corin and Dara never answer: only the timer closes the round
		b.roll("Aurel", 50)
		local saved = ser(b.s)
		local s = assert(F().Restore(assert(loadstring("return " .. saved))()))
		eq(s.state, "ROLLING")
		local ok = F().Step(s, { type = "TICK", ts = 1500 }, { ledger = b.L })
		truthy(ok)
		eq(s.state, "PROPOSAL")
		eq(s.items[1].proposal.winner, "Aurel")
		eq(s.items[1].proposal.reasons[2], "ONLY_CANDIDATE")
	end)
end)
