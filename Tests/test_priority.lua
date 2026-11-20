-- Priority (M2-2): the award algorithm of docs/ANALISI.md §3.4 with the regulation's three examples (ring, shoulder,
-- cloak), tiers, valid rolls, metrics, tie-breaks, rerolls among the tied only, the BoE and the other fallbacks, and
-- the proposal { winner, cost, reason codes, flags }. Pure domain code: no game call is involved.
local function P() return FDCP.Priority end

local function roll(player, value, extra)
	local r = { player = player, value = value, min = 1, max = 100 }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end

local function round(...)
	return { rolls = { ... } }
end

local COSTS = { MS = 1, OS = 0 }

local function evaluate(state, config)
	state.costs = state.costs or COSTS
	return P().Evaluate(state, config)
end

local function cfg(changes)
	local c = P().DefaultConfig()
	for k, v in pairs(changes or {}) do c[k] = v end
	return c
end

local function has(list, code)
	for _, v in ipairs(list or {}) do
		if v == code then return true end
	end
	return false
end

local function players(list)
	local t = {}
	for _, r in ipairs(list or {}) do t[#t + 1] = r.player end
	table.sort(t)
	return t
end

describe("the regulation's three examples", function()
	it("ring: same credits, the higher roll (76) wins", function()
		local r = evaluate({
			responses = { Aurel = "MS", Bryn = "MS", Corin = "MS" },
			credits = { Aurel = 0, Bryn = 0, Corin = 0 },
			costs = { MS = 1, OS = 0 },
			rounds = { round(roll("Aurel", 45), roll("Bryn", 76), roll("Corin", 12)) },
		})
		eq(r.status, "PROPOSAL")
		local p = r.proposal
		eq(p.kind, "AWARD")
		eq(p.winner, "Bryn")
		eq(p.roll, 76)
		eq(p.cost, 1)
		eq(p.credits, 0)
		eq(p.response, "MS")
		eq(p.tier, 1)
		deepEq(p.reasons, { "MAIN_SPEC_TIER", "HIGHER_ROLL" })
		deepEq(p.flags, {})
		deepEq(players(p.rivals), { "Aurel", "Corin" })
	end)

	it("shoulder: fewer credits win, the roll (34) does not count", function()
		local r = evaluate({
			responses = { Aurel = "MS", Bryn = "MS", Corin = "MS" },
			credits = { Aurel = 0, Bryn = 2, Corin = 3 },
			rounds = { round(roll("Aurel", 34), roll("Bryn", 90), roll("Corin", 99)) },
		})
		local p = r.proposal
		eq(p.winner, "Aurel")
		eq(p.roll, 34)
		deepEq(p.reasons, { "MAIN_SPEC_TIER", "LOWER_CREDITS" })
		eq(#p.rivals, 2)
		eq(p.rivals[1].player, "Bryn")
		eq(p.rivals[1].metric, 2)
		eq(p.rivals[2].player, "Corin")
		eq(p.rivals[2].metric, 3)
	end)

	it("cloak: a tie on credits and roll is rerolled between Bryn and Corin only", function()
		local state = {
			responses = { Aurel = "MS", Bryn = "MS", Corin = "MS" },
			credits = { Aurel = 1, Bryn = 1, Corin = 1 },
			rounds = { round(roll("Aurel", 40), roll("Bryn", 88), roll("Corin", 88)) },
		}
		local r = evaluate(state)
		eq(r.status, "REROLL")
		eq(r.tier, 1)
		deepEq(r.among, { "Bryn", "Corin" })
		eq(r.round, 2)

		-- Aurel rolls again in the reroll: not a candidate, discarded.
		state.rounds[2] = round(roll("Aurel", 100), roll("Bryn", 20), roll("Corin", 61))
		r = evaluate(state)
		eq(r.status, "PROPOSAL")
		local p = r.proposal
		eq(p.winner, "Corin")
		eq(p.roll, 88)
		eq(p.reroll, 61)
		deepEq(p.reasons, { "MAIN_SPEC_TIER", "REROLL_WON" })
		truthy(has(p.flags, "DISCARDED_ROLLS"))
		eq(#r.discarded, 1)
		deepEq(r.discarded[1], { round = 2, player = "Aurel", code = "NOT_ELIGIBLE" })
		eq(#p.rerolls, 1)
	end)
end)

describe("tiers", function()
	it("off-spec opens only when no main-spec answered", function()
		local state = {
			responses = { Aurel = "OS", Bryn = "MS", Corin = "OS" },
			credits = { Aurel = 0, Bryn = 5, Corin = 0 },
			rounds = { round(roll("Bryn", 3)) },
		}
		local r = evaluate(state)
		eq(r.proposal.winner, "Bryn")
		eq(r.proposal.cost, 1)
		deepEq(r.proposal.reasons, { "MAIN_SPEC_TIER", "ONLY_CANDIDATE" })
	end)

	it("the first round asks the main-spec tier among its responders only", function()
		local r = evaluate({ responses = { Aurel = "OS", Bryn = "MS", Corin = "PASS" } })
		eq(r.status, "ROLL")
		eq(r.stage, "TIER")
		eq(r.tier, 1)
		deepEq(r.among, { "Bryn" })
		eq(r.round, 1)
	end)

	it("no main-spec responder: the off-spec tier rolls at cost 0", function()
		local state = { responses = { Aurel = "OS", Bryn = "OS", Corin = "PASS" }, credits = { Aurel = 4, Bryn = 1 } }
		local r = evaluate(state)
		eq(r.status, "ROLL")
		eq(r.tier, 2)
		deepEq(r.among, { "Aurel", "Bryn" })
		state.rounds = { round(roll("Aurel", 99), roll("Bryn", 2)) }
		r = evaluate(state)
		eq(r.proposal.winner, "Bryn")
		eq(r.proposal.cost, 0)
		eq(r.proposal.response, "OS")
		deepEq(r.proposal.reasons, { "OFFSPEC_TIER", "LOWER_CREDITS" })
	end)

	it("main-spec responders who do not roll leave the tier empty: off-spec opens next", function()
		local state = {
			responses = { Aurel = "MS", Bryn = "OS" },
			rounds = { round(roll("Bryn", 50)) },   -- Bryn's roll in the main-spec round does not count
		}
		local r = evaluate(state)
		eq(r.status, "ROLL")
		eq(r.tier, 2)
		eq(r.round, 2)
		deepEq(r.discarded[1], { round = 1, player = "Bryn", code = "NOT_ELIGIBLE" })
		state.rounds[2] = round(roll("Bryn", 7))
		r = evaluate(state)
		eq(r.proposal.winner, "Bryn")
		eq(r.history[1].outcome, "EMPTY")
		eq(r.history[2].outcome, "WINNER")
	end)

	it("transmog is off in the preset and is a third tier when enabled", function()
		local state = { responses = { Aurel = "TMOG" } }
		local r = evaluate(state)
		eq(r.status, "PROPOSAL")
		eq(r.proposal.kind, "ML")
		local c = P().DefaultConfig()
		c.responses.TMOG.enabled = true
		r = evaluate(state, c)
		eq(r.status, "ROLL")
		eq(r.tier, 3)
		state.rounds = { round(roll("Aurel", 10)) }
		state.costs = { MS = 1, OS = 0, TMOG = 0 }
		r = evaluate(state, c)
		deepEq(r.proposal.reasons, { "TRANSMOG_TIER", "ONLY_CANDIDATE" })
		eq(r.proposal.cost, 0)
	end)

	it("a cost the council decides is flagged", function()
		local r = evaluate({
			responses = { Aurel = "MS" },
			costs = { OS = 0 },
			rounds = { round(roll("Aurel", 10)) },
		})
		isNil(r.proposal.cost)
		truthy(has(r.proposal.flags, "COST_BY_COUNCIL"))
	end)

	it("without costs the item is priced through Pricing", function()
		local r = P().Evaluate({
			responses = { Aurel = "MS" },
			item = { itemID = 9, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON", quality = 4 },
			rounds = { round(roll("Aurel", 10)) },
		})
		eq(r.proposal.cost, 2)
	end)
end)

describe("BoE and fallbacks", function()
	it("a BoE without main-spec goes to the bank, the off-spec tier does not open", function()
		local r = evaluate({ boe = true, responses = { Aurel = "OS", Bryn = "OS" } }, cfg({ bankCharacter = "Oste" }))
		eq(r.status, "PROPOSAL")
		local p = r.proposal
		eq(p.kind, "BANK")
		eq(p.winner, "Oste")
		eq(p.cost, 0)
		deepEq(p.reasons, { "BOE_BANK" })
		deepEq(p.flags, {})
	end)

	it("a BoE whose main-spec responders do not roll goes to the bank", function()
		local r = evaluate({ boe = true, responses = { Aurel = "MS" }, rounds = { round() } })
		eq(r.proposal.kind, "BANK")
		isNil(r.proposal.winner)
		truthy(has(r.proposal.flags, "NO_BANK_CHARACTER"))
	end)

	it("a BoE with main-spec is rolled like any other item", function()
		local r = evaluate({ boe = true, responses = { Aurel = "MS" }, rounds = { round(roll("Aurel", 1)) } })
		eq(r.proposal.kind, "AWARD")
		eq(r.proposal.winner, "Aurel")
	end)

	it("boeFallback = offspec opens the off-spec tier", function()
		local r = evaluate({ boe = true, responses = { Aurel = "OS" } }, cfg({ boeFallback = "offspec" }))
		eq(r.status, "ROLL")
		eq(r.tier, 2)
	end)

	it("boeFallback = disenchant", function()
		local r = evaluate({ boe = true, responses = {} }, cfg({ boeFallback = "disenchant", disenchanter = "Dorn" }))
		eq(r.proposal.kind, "DISENCHANT")
		eq(r.proposal.winner, "Dorn")
		deepEq(r.proposal.reasons, { "FALLBACK_DISENCHANT" })
	end)

	it("no candidate at all: the master looter decides (preset)", function()
		local r = evaluate({ responses = { Aurel = "PASS" } })
		eq(r.proposal.kind, "ML")
		isNil(r.proposal.winner)
		deepEq(r.proposal.reasons, { "FALLBACK_ML" })
	end)

	it("fallback = disenchant without a disenchanter is flagged", function()
		local r = evaluate({ responses = {} }, cfg({ fallback = "disenchant" }))
		eq(r.proposal.kind, "DISENCHANT")
		truthy(has(r.proposal.flags, "NO_DISENCHANTER"))
	end)

	it("fallback = freeroll: anyone present rolls, the highest roll wins at cost 0", function()
		local c = cfg({ fallback = "freeroll" })
		local state = { responses = {}, credits = { Aurel = 0, Bryn = 9 }, present = { Aurel = true, Bryn = true } }
		local r = evaluate(state, c)
		eq(r.status, "ROLL")
		eq(r.stage, "FREE_ROLL")
		isNil(r.among)
		state.rounds = { round(roll("Aurel", 30), roll("Bryn", 80), roll("Zed", 100)) }
		r = evaluate(state, c)
		local p = r.proposal
		eq(p.kind, "AWARD")
		eq(p.winner, "Bryn")
		eq(p.cost, 0)
		deepEq(p.reasons, { "FALLBACK_FREE_ROLL", "HIGHER_ROLL" })
		deepEq(r.discarded[1], { round = 1, player = "Zed", code = "NOT_PRESENT" })
	end)

	it("a free roll nobody rolls goes to the master looter", function()
		local r = evaluate({ responses = {}, rounds = { round() } }, cfg({ fallback = "freeroll" }))
		eq(r.proposal.kind, "ML")
		truthy(has(r.proposal.flags, "FREE_ROLL_EMPTY"))
	end)

	it("a tied free roll is rerolled", function()
		local r = evaluate({ responses = {}, rounds = { round(roll("Aurel", 50), roll("Bryn", 50)) } },
			cfg({ fallback = "freeroll" }))
		eq(r.status, "REROLL")
		eq(r.stage, "FREE_ROLL")
		deepEq(r.among, { "Aurel", "Bryn" })
	end)
end)

describe("valid rolls", function()
	local function oneRound(rolls, extra)
		local state = { responses = { Aurel = "MS", Bryn = "MS" }, rounds = { { rolls = rolls } } }
		for k, v in pairs(extra or {}) do state[k] = v end
		return evaluate(state)
	end

	it("a roll that is not 1-100 is discarded and does not use the turn", function()
		local r = oneRound({ roll("Aurel", 99, { max = 1000 }), roll("Aurel", 10), roll("Bryn", 5) })
		eq(r.proposal.winner, "Aurel")
		eq(r.proposal.roll, 10)
		deepEq(r.discarded[1], { round = 1, player = "Aurel", code = "NOT_1_100" })
		local r2 = oneRound({ roll("Aurel", 2, { min = 2 }), roll("Bryn", 5) })
		eq(r2.discarded[1].code, "NOT_1_100")
	end)

	it("only the first 1-100 roll of the round counts", function()
		local r = oneRound({ roll("Aurel", 10), roll("Aurel", 100), roll("Bryn", 50) })
		eq(r.proposal.winner, "Bryn")
		deepEq(r.discarded[1], { round = 1, player = "Aurel", code = "DUPLICATE" })
	end)

	it("a value outside the range or not an integer is discarded", function()
		local r = oneRound({ roll("Aurel", 0), roll("Aurel", 101), roll("Aurel", 5.5), roll("Bryn", 1) })
		eq(r.proposal.winner, "Bryn")
		eq(#r.discarded, 3)
		for _, d in ipairs(r.discarded) do eq(d.code, "BAD_VALUE") end
	end)

	it("a malformed entry is discarded", function()
		local r = oneRound({ { value = 5, min = 1, max = 100 }, "x", roll("Bryn", 1) })
		eq(r.proposal.winner, "Bryn")
		eq(r.discarded[1].code, "BAD_ROLL")
		eq(r.discarded[2].code, "BAD_ROLL")
	end)

	it("rolls before the round opened or after it closed are discarded", function()
		local state = {
			responses = { Aurel = "MS", Bryn = "MS", Corin = "MS" },
			rounds = { { openedAt = 100, closedAt = 130, rolls = {
				roll("Aurel", 99, { ts = 90 }), roll("Bryn", 20, { ts = 110 }), roll("Corin", 98, { ts = 140 }) } } },
		}
		local r = evaluate(state)
		eq(r.proposal.winner, "Bryn")
		eq(r.discarded[1].code, "BEFORE_OPEN")
		eq(r.discarded[2].code, "AFTER_CLOSE")
		deepEq(r.proposal.reasons, { "MAIN_SPEC_TIER", "ONLY_CANDIDATE" })
	end)

	it("a character not present cannot be a candidate nor roll", function()
		local state = { responses = { Aurel = "MS", Bryn = "MS" }, present = { Bryn = true } }
		local r = evaluate(state)
		deepEq(r.among, { "Bryn" })
		state.rounds = { round(roll("Aurel", 99), roll("Bryn", 1)) }
		r = evaluate(state)
		eq(r.proposal.winner, "Bryn")
		eq(r.discarded[1].code, "NOT_PRESENT")
	end)

	it("without the addon a roll is ignored (requireAddon, preset on)", function()
		local state = { responses = { Aurel = "MS", Bryn = "MS" }, addon = { Bryn = true },
			rounds = { round(roll("Aurel", 99), roll("Bryn", 1)) } }
		local r = evaluate(state)
		eq(r.proposal.winner, "Bryn")
		eq(r.discarded[1].code, "NO_ADDON")
		r = evaluate(state, cfg({ requireAddon = false }))
		eq(r.proposal.winner, "Aurel")
	end)

	it("nobody rolls in any tier: fallback", function()
		local r = evaluate({ responses = { Aurel = "MS", Bryn = "OS" }, rounds = { round(), round() } })
		eq(r.proposal.kind, "ML")
		eq(#r.history, 2)
	end)
end)

describe("metrics", function()
	it("credits per night: fewer credits per night played win", function()
		local state = {
			responses = { Aurel = "MS", Bryn = "MS" },
			credits = { Aurel = 4, Bryn = 3 },
			nights = { Aurel = 8, Bryn = 3 },
			rounds = { round(roll("Aurel", 10), roll("Bryn", 90)) },
		}
		local r = evaluate(state, cfg({ metric = "creditsPerNight" }))
		eq(r.proposal.winner, "Aurel")
		eq(r.proposal.metric, 0.5)
		deepEq(r.proposal.reasons, { "MAIN_SPEC_TIER", "LOWER_CREDITS_PER_NIGHT" })
		-- With plain credits Bryn wins.
		eq(evaluate(state).proposal.winner, "Bryn")
	end)

	it("credits per night: zero nights count as one, equal ratios fall to the roll", function()
		local state = {
			responses = { Aurel = "MS", Bryn = "MS" },
			credits = { Aurel = 1, Bryn = 2 },
			nights = { Aurel = 0, Bryn = 2 },
			rounds = { round(roll("Aurel", 10), roll("Bryn", 90)) },
		}
		local r = evaluate(state, cfg({ metric = "creditsPerNight" }))
		eq(r.proposal.winner, "Bryn")
		deepEq(r.proposal.reasons, { "MAIN_SPEC_TIER", "HIGHER_ROLL" })
	end)

	it("roll only: credits are ignored", function()
		local r = evaluate({
			responses = { Aurel = "MS", Bryn = "MS" },
			credits = { Aurel = 0, Bryn = 10 },
			rounds = { round(roll("Aurel", 10), roll("Bryn", 90)) },
		}, cfg({ metric = "roll" }))
		eq(r.proposal.winner, "Bryn")
		deepEq(r.proposal.reasons, { "MAIN_SPEC_TIER", "HIGHER_ROLL" })
	end)

	it("missing credits count as 0; decimal credits compare exactly", function()
		local r = evaluate({
			responses = { Aurel = "MS", Bryn = "MS" },
			credits = { Bryn = 0.5 },
			rounds = { round(roll("Aurel", 1), roll("Bryn", 100)) },
		})
		eq(r.proposal.winner, "Aurel")
		eq(r.proposal.credits, 0)
		deepEq(r.proposal.reasons, { "MAIN_SPEC_TIER", "LOWER_CREDITS" })
	end)
end)

describe("rerolls", function()
	local function tied()
		return {
			responses = { Aurel = "MS", Bryn = "MS", Corin = "MS" },
			rounds = { round(roll("Aurel", 70), roll("Bryn", 70), roll("Corin", 70)) },
		}
	end

	it("a reroll tie narrows to the tied again", function()
		local state = tied()
		state.rounds[2] = round(roll("Aurel", 5), roll("Bryn", 60), roll("Corin", 60))
		local r = evaluate(state)
		eq(r.status, "REROLL")
		deepEq(r.among, { "Bryn", "Corin" })
		eq(r.round, 3)
		state.rounds[3] = round(roll("Bryn", 61), roll("Corin", 2))
		r = evaluate(state)
		eq(r.proposal.winner, "Bryn")
		eq(r.proposal.reroll, 61)
		eq(#r.proposal.rerolls, 2)
		deepEq(r.proposal.reasons, { "MAIN_SPEC_TIER", "REROLL_WON" })
	end)

	it("a reroll nobody rolls is asked again among the same players", function()
		local state = tied()
		state.rounds[2] = round()
		local r = evaluate(state)
		eq(r.status, "REROLL")
		deepEq(r.among, { "Aurel", "Bryn", "Corin" })
	end)

	it("a tied player who does not reroll forfeits", function()
		local state = tied()
		state.rounds[2] = round(roll("Corin", 3))
		eq(evaluate(state).proposal.winner, "Corin")
	end)

	it("after maxRerolls the master looter decides", function()
		local state = tied()
		for i = 2, 3 do state.rounds[i] = round(roll("Aurel", 9), roll("Bryn", 9)) end
		local r = evaluate(state, cfg({ maxRerolls = 2 }))
		eq(r.proposal.kind, "ML")
		deepEq(r.proposal.reasons, { "TIE_ML" })
		truthy(has(r.proposal.flags, "REROLL_LIMIT"))
		deepEq(r.proposal.among, { "Aurel", "Bryn" })
	end)

	it("without reroll in tieBreak a full tie goes to the master looter", function()
		local r = evaluate(tied(), cfg({ tieBreak = { "roll" } }))
		eq(r.proposal.kind, "ML")
		truthy(has(r.proposal.flags, "TIE_UNRESOLVED"))
		deepEq(r.proposal.among, { "Aurel", "Bryn", "Corin" })
	end)

	it("without roll in tieBreak equal credits go straight to a reroll", function()
		local r = evaluate({
			responses = { Aurel = "MS", Bryn = "MS" },
			rounds = { round(roll("Aurel", 1), roll("Bryn", 99)) },
		}, cfg({ tieBreak = { "reroll" } }))
		eq(r.status, "REROLL")
		deepEq(r.among, { "Aurel", "Bryn" })
	end)

	it("the off-spec tier rerolls too", function()
		local r = evaluate({
			responses = { Aurel = "OS", Bryn = "OS" },
			rounds = { round(roll("Aurel", 4), roll("Bryn", 4)) },
		})
		eq(r.status, "REROLL")
		eq(r.tier, 2)
	end)
end)

describe("purity and validation", function()
	it("the same input gives the same output and is not modified", function()
		local state = {
			responses = { Aurel = "MS", Bryn = "MS", Corin = "MS" },
			credits = { Aurel = 1, Bryn = 1, Corin = 1 },
			costs = { MS = 1, OS = 0 },
			rounds = { round(roll("Aurel", 40), roll("Bryn", 88), roll("Corin", 88)), round(roll("Bryn", 20), roll("Corin", 61)) },
		}
		local a = P().Evaluate(state)
		local b = P().Evaluate(state)
		deepEq(a, b)
		eq(#state.rounds, 2)
		eq(#state.rounds[1].rolls, 3)
	end)

	it("an empty or missing state falls back to the master looter", function()
		eq(P().Evaluate(nil).proposal.kind, "ML")
		eq(P().Evaluate({}).proposal.kind, "ML")
	end)

	it("the preset is valid", function()
		local ok, problems = P().Validate(P().DefaultConfig())
		truthy(ok)
		deepEq(problems, {})
	end)

	it("Validate lists every problem", function()
		local c = P().DefaultConfig()
		c.metric = "gold"
		c.tieBreak = { "roll", "coin" }
		c.maxRerolls = 0
		c.fallback = "bank"
		c.boeFallback = "nope"
		c.freeRollCost = -1
		c.responses.OS = { tier = 0 }
		local ok, problems = P().Validate(c)
		falsy(ok)
		deepEq(problems, { "boeFallback", "fallback", "freeRollCost", "maxRerolls", "metric", "responses:OS", "tieBreak:coin" })
		ok, problems = P().Validate({ metric = "credits", tieBreak = {}, maxRerolls = 1, fallback = "ml", boeFallback = "bank",
			responses = { MS = { tier = 1, enabled = false } } })
		falsy(ok)
		deepEq(problems, { "responses:none" })
		falsy(P().Validate("x"))
	end)
end)
