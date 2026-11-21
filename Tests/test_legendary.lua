-- Legendary projects (M5-6, docs/ANALISI.md §3.7): the projects folded from the ledger (opened, pieces paid, completed
-- or abandoned) through the permission gate, who receives a chain piece in each mode (council, vote, roll, queue), the
-- session that recognises a piece when the corpse is opened and proposes it without a roll at legendary.chainPieceCost,
-- and the /fdcp legendary command. The last part runs a small raid on the network simulator.
local function F() return FDCP.SessionFSM end
local function Lg() return FDCP.Ledger end
local function LG() return FDCP.Legendary end

local ML = "Dara"
local SEASON = "S1"
local RAID = { Aurel = true, Bryn = true, Corin = true, Dara = true }   -- Elin is in the pool, not in the raid
local POOL = { "Aurel", "Bryn", "Corin", "Dara", "Elin" }
local FINAL = 19019                       -- the legendary itself
local LEFT, RIGHT, ESSENCE = 18563, 18564, 19017   -- its chain pieces
local RING = { itemID = 19003, slot = 1, classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER", quality = 4 }
local function piece(id, slot) return { itemID = id, slot = slot or 2, classID = 15, subclassID = 0, quality = 5 } end
-- A chain piece below the loot threshold: the cost rules would leave it out of a session.
local LOW_ESSENCE = { itemID = ESSENCE, slot = 3, classID = 15, subclassID = 0, quality = 2 }

local function has(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then return true end
	end
	return false
end

-- A season with its pool on a fresh ledger (no gate unless one is given).
local function season(opts)
	local L = Lg().New()
	assert(FDCP.Season.Open(L, { author = ML, ts = 1, season = SEASON, instances = { { id = 409, size = 40 } } }, nil, opts))
	for i, name in ipairs(POOL) do
		assert(FDCP.Members.Join(L, { author = ML, ts = 1 + i, season = SEASON, member = name }, nil, opts))
	end
	return L
end

local function project(L, fields, opts)
	local d = { author = ML, ts = 20, season = SEASON, name = "Thunderfury", item = FINAL, pieces = { LEFT, RIGHT, ESSENCE },
		builder = "Bryn" }
	for k, v in pairs(fields or {}) do d[k] = v end
	if fields and fields.builder == false then d.builder = nil end
	return LG().OpenProject(L, d, opts)
end

local function rules(mutate)
	local r = FDCP.Rules.DefaultConfig()
	r.session.autoAdvance = false
	if mutate then mutate(r) end
	return r
end

-- A session on a ledger with one project. opts = { rules, project (fields), isCouncil, pieces (false = no env) }.
local function bench(opts)
	opts = opts or {}
	local b = { L = season(), t = 1000 }
	b.project = assert(project(b.L, opts.project))
	b.s = assert(F().New({ id = "S1-1", season = SEASON, ml = ML, ts = 1000, encounter = 601, rules = opts.rules or rules(),
		present = RAID, addon = RAID }))
	local function env()
		local e = { ledger = b.L, isCouncil = opts.isCouncil }
		if opts.pieces ~= false then e.legendary = function() return LG().Pieces(b.L, SEASON) end end
		return e
	end
	function b.step(input)
		input.ts = input.ts or b.t
		return F().Step(b.s, input, env())
	end
	function b.must(input)
		local ok, code, effects = b.step(input)
		if not ok then error("refused " .. tostring(input.type) .. ": " .. tostring(code), 2) end
		return effects
	end
	function b.refused(input)
		local ok, code = b.step(input)
		falsy(ok, "accepted " .. tostring(input.type))
		return code
	end
	function b.ml(kind, extra)
		local input = extra or {}
		input.type, input.by = kind, ML
		return b.must(input)
	end
	function b.item(i) return b.s.items[i or b.s.active] end
	function b.events(typ)
		local out = {}
		for _, e in ipairs(Lg().Sorted(b.L)) do
			if e.type == typ then out[#out + 1] = e end
		end
		return out
	end
	function b.open(items)
		b.must({ type = "LOOT_OPENED", items = items or { piece(LEFT) }, encounter = 601 })
		b.ml("START")
	end
	return b
end

local function effectTypes(effects)
	local out = {}
	for _, e in ipairs(effects) do out[#out + 1] = e.type end
	return out
end

---------------------------------------------------------------------------------------------------------------------

describe("legendary projects in the ledger", function()
	it("opens a project with its chain pieces and builder, and lists them", function()
		local L = season()
		local e = assert(project(L, { queue = { "Corin", "Bryn" } }))
		eq(e.type, "LEGENDARY_PROJECT_OPENED"); eq(e.season, SEASON)
		local list = LG().Projects(L, SEASON)
		eq(#list, 1)
		local p = list[1]
		eq(p.id, e.id); eq(p.name, "Thunderfury"); eq(p.item, FINAL); eq(p.builder, "Bryn")
		deepEq(p.pieces, { LEFT, RIGHT, ESSENCE }); deepEq(p.queue, { "Corin", "Bryn" })
		truthy(p.open); eq(#p.paid, 0)
		local pieces = LG().Pieces(L, SEASON)
		eq(pieces[LEFT].project, e.id); eq(pieces[ESSENCE].builder, "Bryn"); eq(pieces[FINAL], nil)
		deepEq(pieces[RIGHT].queue, { "Corin", "Bryn" })
		eq(LG().Get(L, SEASON, e.id).name, "Thunderfury")
		eq(#LG().Projects(L, "S2"), 0, "a project belongs to its season")
	end)

	it("refuses a project without a name, a final item, pieces, or with a builder outside the pool", function()
		local L = season()
		local cases = {
			{ { name = "" }, "BAD_NAME" },
			{ { name = string.rep("x", LG().MAX_NAME + 1) }, "BAD_NAME" },
			{ { item = 0 }, "BAD_ITEM" },
			{ { item = 1.5 }, "BAD_ITEM" },
			{ { pieces = {} }, "BAD_PIECES" },
			{ { pieces = { LEFT, LEFT } }, "BAD_PIECES" },
			{ { pieces = { LEFT, -3 } }, "BAD_PIECES" },
			{ { builder = "Zed" }, "NOT_MEMBER" },
			{ { builder = "Bryn:1" }, "NOT_MEMBER" },
			{ { queue = { "Corin", "Zed" } }, "NOT_MEMBER" },
			{ { queue = { "Corin", "Corin" } }, "NOT_MEMBER" },
			{ { season = "S9" }, "SEASON_UNKNOWN" },
		}
		for _, case in ipairs(cases) do
			local e, code = project(L, case[1])
			isNil(e); eq(code, case[2])
		end
		eq(#LG().Projects(L, SEASON), 0)
		truthy(project(L, { builder = false }), "a project may start without a builder")
	end)

	it("never gives one piece to two open projects; once closed, its pieces are free again", function()
		local L = season()
		local first = assert(project(L))
		local e, code = project(L, { name = "Second", pieces = { ESSENCE, 19018 }, builder = "Corin" })
		isNil(e); eq(code, "PIECE_TAKEN")
		assert(LG().Close(L, { author = ML, ts = 30, ref = first.id, outcome = "COMPLETED" }))
		local second = assert(project(L, { name = "Second", pieces = { ESSENCE, 19018 }, builder = "Corin" }))
		eq(LG().Pieces(L, SEASON)[ESSENCE].project, second.id)
		eq(LG().Pieces(L, SEASON)[LEFT], nil)
	end)

	it("records the pieces paid, and drops one whose award was voided", function()
		local L = season()
		local p = assert(project(L))
		local award = assert(Lg().Append(L, { author = ML, ts = 40, season = SEASON, type = "ITEM_AWARDED",
			payload = { target = "member", member = "Bryn", item = LEFT, cost = 2, legendary = p.id } }))
		local paid = assert(LG().Pay(L, { author = ML, ts = 40, ref = p.id, item = LEFT, member = "Bryn", cost = 2,
			award = award.id }))
		eq(paid.type, "LEGENDARY_PROJECT_PAID"); eq(paid.season, SEASON)
		local _, code = LG().Pay(L, { author = ML, ts = 41, ref = p.id, item = RING.itemID, member = "Bryn", cost = 2 })
		eq(code, "NOT_A_PIECE")
		_, code = LG().Pay(L, { author = ML, ts = 41, ref = "Nobody:3", item = LEFT, member = "Bryn", cost = 2 })
		eq(code, "PROJECT_UNKNOWN")
		_, code = LG().Pay(L, { author = ML, ts = 41, ref = award.id, item = LEFT, member = "Bryn", cost = 2 })
		eq(code, "PROJECT_UNKNOWN", "an award is not a project")
		local list = LG().Projects(L, SEASON)
		eq(#list[1].paid, 1); eq(list[1].paid[1].member, "Bryn"); eq(list[1].paid[1].cost, 2)
		deepEq(LG().PaidBy(list[1]), { Bryn = 1 })
		assert(FDCP.Council.Void(L, { author = ML, ts = 50, ref = award.id, reason = "LEGENDARY" }))
		list = LG().Projects(L, SEASON)
		eq(#list[1].paid, 0); eq(#list[1].voided, 1)
		eq(Lg().Credits(L, SEASON).Bryn, 0, "the award's credits come back with the void")
	end)

	it("closes a project completed or abandoned, once", function()
		local L = season()
		local p = assert(project(L))
		local _, code = LG().Close(L, { author = ML, ts = 60, ref = p.id, outcome = "DONE" })
		eq(code, "BAD_OUTCOME")
		local e = assert(LG().Close(L, { author = ML, ts = 60, ref = p.id, outcome = "COMPLETED" }))
		eq(e.payload.outcome, "COMPLETED"); eq(e.season, SEASON)
		local list = LG().Projects(L, SEASON)
		falsy(list[1].open); eq(list[1].outcome, "COMPLETED"); eq(list[1].closedBy, ML)
		_, code = LG().Close(L, { author = ML, ts = 61, ref = p.id, outcome = "ABANDONED" })
		eq(code, "PROJECT_CLOSED")
		_, code = LG().Pay(L, { author = ML, ts = 61, ref = p.id, item = LEFT, member = "Bryn", cost = 2 })
		eq(code, "PROJECT_CLOSED")
		eq(#LG().Active(L, SEASON), 0)

		local q = assert(project(L, { name = "Atiesh", pieces = { 22726 }, builder = "Corin" }))
		assert(LG().Close(L, { author = ML, ts = 70, ref = q.id, outcome = "ABANDONED", reason = "OTHER" }))
		local closed = LG().Get(L, SEASON, q.id)
		eq(closed.outcome, "ABANDONED"); eq(closed.reason, "OTHER")
	end)

	it("checks the payloads of the three types, also when they arrive from another officer", function()
		local L = season()
		local bad = {
			{ type = "LEGENDARY_PROJECT_OPENED", payload = { name = "X", item = FINAL, pieces = {} } },
			{ type = "LEGENDARY_PROJECT_PAID", payload = { ref = "nope", item = LEFT, member = "Bryn", cost = 2 } },
			{ type = "LEGENDARY_PROJECT_PAID", payload = { ref = "Dara:1", item = LEFT, member = "Bryn", cost = -1 } },
			{ type = "LEGENDARY_PROJECT_CLOSED", payload = { ref = "Dara:1", outcome = "MAYBE" } },
		}
		for i, draft in ipairs(bad) do
			local e, code = Lg().Append(L, { author = "Bryn", ts = 80 + i, season = SEASON, type = draft.type,
				payload = draft.payload })
			isNil(e, draft.type); truthy(tostring(code):find("^payload:"), tostring(code))
		end
		-- a CLOSED for an unknown project, or a PAID after the close, is kept for the sync but never counted
		local p = assert(project(L))
		assert(Lg().Append(L, { author = "Bryn", ts = 90, season = SEASON, type = "LEGENDARY_PROJECT_CLOSED",
			payload = { ref = "Bryn:999", outcome = "COMPLETED" } }))
		assert(LG().Close(L, { author = ML, ts = 91, ref = p.id, outcome = "COMPLETED" }))
		assert(Lg().Append(L, { author = "Bryn", ts = 92, season = SEASON, type = "LEGENDARY_PROJECT_PAID",
			payload = { ref = p.id, item = LEFT, member = "Bryn", cost = 2 } }))
		local list = LG().Projects(L, SEASON)
		eq(#list, 1); eq(#list[1].paid, 0); eq(list[1].outcome, "COMPLETED")
	end)

	it("counts a piece paid with an earlier timestamp than its project (a session's own clock)", function()
		local L = season()
		local p = assert(project(L, { ts = 5000 }))
		assert(LG().Pay(L, { author = ML, ts = 12, ref = p.id, item = LEFT, member = "Bryn", cost = 2 }))
		eq(#LG().Projects(L, SEASON)[1].paid, 1)
	end)

	it("passes the permission gate: night.run (the officers) writes them, a raider cannot", function()
		local RANKS = { Aurel = 0, Bryn = 1, Corin = 3, Dara = 0 }
		local gate = FDCP.Permissions.Gate(function(author) return RANKS[author] end)
		local L = season(gate)
		local e, code = project(L, { author = "Corin" }, gate)
		isNil(e); eq(code, "RANK_TOO_LOW")
		local p = assert(project(L, { author = "Bryn" }, gate))
		_, code = LG().Close(L, { author = "Corin", ts = 30, ref = p.id, outcome = "ABANDONED" }, gate)
		eq(code, "RANK_TOO_LOW")
		_, code = LG().Pay(L, { author = "Corin", ts = 30, ref = p.id, item = LEFT, member = "Bryn", cost = 2 }, gate)
		eq(code, "RANK_TOO_LOW")
		assert(LG().Pay(L, { author = "Dara", ts = 31, ref = p.id, item = LEFT, member = "Bryn", cost = 2 }, gate))
		assert(LG().Close(L, { author = "Bryn", ts = 32, ref = p.id, outcome = "COMPLETED" }, gate))
		for _, typ in ipairs({ "LEGENDARY_PROJECT_OPENED", "LEGENDARY_PROJECT_PAID", "LEGENDARY_PROJECT_CLOSED" }) do
			eq(FDCP.Permissions.EVENT_PERMISSION[typ], "night.run", typ)
		end
	end)
end)

describe("who receives a chain piece", function()
	local P = { project = "Dara:9", builder = "Bryn", queue = { "Elin", "Corin", "Bryn" } }

	it("council and vote: the builder, if the project has one and he is in the raid", function()
		for _, mode in ipairs({ "council", "vote" }) do
			local w, reason, flags = LG().Recipient(P, mode, RAID)
			eq(w, "Bryn"); eq(reason, "LEGENDARY_BUILDER"); deepEq(flags, {})
			w, reason, flags = LG().Recipient({ project = "x", builder = "Elin" }, mode, RAID)
			isNil(w); deepEq(flags, { "BUILDER_ABSENT" })
			w, reason, flags = LG().Recipient({ project = "x" }, mode, RAID)
			isNil(w); deepEq(flags, { "NO_BUILDER" })
			eq(LG().Recipient({ project = "x", builder = "Elin" }, mode, nil), "Elin", "the raid is not known: no guess")
		end
	end)

	it("queue: the first of the list who is present", function()
		local w, reason, flags = LG().Recipient(P, "queue", RAID)
		eq(w, "Corin"); eq(reason, "LEGENDARY_QUEUE"); deepEq(flags, {})
		eq(LG().Recipient(P, "queue", { Bryn = true }), "Bryn")
		eq(LG().Recipient({ project = "x", builder = "Aurel", queue = {} }, "queue", RAID), "Aurel", "no queue: the builder")
		w, reason, flags = LG().Recipient(P, "queue", { Aurel = true })
		isNil(w); deepEq(flags, { "QUEUE_EMPTY" })
	end)

	it("roll: nobody, the item is rolled", function()
		local w, reason, flags = LG().Recipient(P, "roll", RAID)
		isNil(w); isNil(reason); deepEq(flags, {})
	end)

	it("has words for its reasons, flags, refusals and outcomes", function()
		local R = FDCP.Reasons
		for _, code in ipairs({ "LEGENDARY_BUILDER", "LEGENDARY_QUEUE" }) do truthy(R.Key("REASON", code), code) end
		for _, code in ipairs({ "NO_BUILDER", "BUILDER_ABSENT", "QUEUE_EMPTY" }) do truthy(R.Key("FLAG", code), code) end
		for _, code in ipairs({ "PROJECT_UNKNOWN", "PROJECT_CLOSED", "NOT_A_PIECE", "PIECE_TAKEN", "BAD_NAME", "BAD_ITEM",
			"BAD_PIECES", "BAD_OUTCOME" }) do
			truthy(R.Key("REFUSAL", code), code)
		end
		for code in pairs(LG().OUTCOMES) do truthy(R.Key("OUTCOME", code), code) end
		for mode in pairs(FDCP.Rules.LEGENDARY_MODES) do truthy(LG().MODES[mode], mode) end
	end)
end)

---------------------------------------------------------------------------------------------------------------------

describe("a chain piece in the session", function()
	it("council (the preset): recognised, priced at chainPieceCost, given to the builder without a roll", function()
		local b = bench()
		eq(FDCP.Rules.DefaultConfig().legendary.mode, "council")
		b.open({ RING, piece(LEFT, 2) })
		local ring, left = b.item(1), b.item(2)
		isNil(ring.legendary, "an ordinary item stays ordinary")
		eq(left.legendary.project, b.project.id); eq(left.legendary.builder, "Bryn"); eq(left.legendary.mode, "council")
		for response, cost in pairs(left.costs) do eq(cost, 2, response) end
		truthy(left.costs.MS and left.costs.OS)
		local effects = b.ml("OPEN_ROLL", { index = 2 })
		local types = effectTypes(effects)
		truthy(has(types, "LEGENDARY_PIECE")); falsy(has(types, "OPEN_ROUND"), "no roll")
		eq(b.s.state, "PROPOSAL")
		local p = b.item().proposal
		eq(p.winner, "Bryn"); eq(p.cost, 2); deepEq(p.reasons, { "LEGENDARY_BUILDER" }); deepEq(p.flags, {})
		effects = b.ml("CONFIRM")
		truthy(has(effectTypes(effects), "LEGENDARY_PAID"))
		local award = b.events("ITEM_AWARDED")[1]
		eq(award.payload.member, "Bryn"); eq(award.payload.cost, 2); eq(award.payload.item, LEFT)
		eq(award.payload.legendary, b.project.id)
		local paid = b.events("LEGENDARY_PROJECT_PAID")[1]
		eq(paid.payload.ref, b.project.id); eq(paid.payload.award, award.id); eq(paid.payload.member, "Bryn")
		eq(paid.author, ML)
		eq(Lg().Credits(b.L, SEASON).Bryn, 2)
		eq(#LG().Projects(b.L, SEASON)[1].paid, 1)
		eq(b.item(2).legendary.paid, paid.id)
		-- the ring is still rolled as usual
		effects = b.ml("OPEN_ROLL", { index = 1 })
		truthy(has(effectTypes(effects), "OPEN_ROUND"))
	end)

	it("the cost follows the rules' chainPieceCost (customisable)", function()
		local b = bench({ rules = rules(function(r) r.legendary.chainPieceCost = 3.5 end) })
		b.open()
		b.ml("OPEN_ROLL")
		eq(b.item().proposal.cost, 3.5)
		b.ml("CONFIRM")
		eq(Lg().Credits(b.L, SEASON).Bryn, 3.5)
	end)

	it("with awardMode auto the piece goes to the builder by itself, still without a roll", function()
		local b = bench({ rules = rules(function(r)
			r.session.awardMode = "auto"
			r.session.autoAdvance = true
			r.session.interventionSeconds = 5
		end) })
		b.must({ type = "LOOT_OPENED", items = { piece(RIGHT) }, encounter = 601 })
		b.ml("START")
		eq(b.s.state, "PROPOSAL", "autoAdvance opened it")
		truthy(b.item(1).autoAt)
		b.must({ type = "TICK", ts = 1010 })
		eq(b.item(1).state, "ASSIGNED"); eq(b.item(1).award.member, "Bryn")
		eq(#b.events("LEGENDARY_PROJECT_PAID"), 1)
	end)

	it("a builder outside the raid: no winner, a flag; the master looter chooses with a reason", function()
		local b = bench({ project = { builder = "Elin" } })
		b.open()
		b.ml("OPEN_ROLL")
		local p = b.item().proposal
		isNil(p.winner); truthy(has(p.flags, "BUILDER_ABSENT"))
		eq(b.refused({ type = "CONFIRM", by = ML }), "NO_WINNER")
		eq(b.refused({ type = "MODIFY", by = ML, winner = "Corin" }), "REASON_REQUIRED")
		b.ml("MODIFY", { winner = "Corin", reason = "LEGENDARY" })
		eq(b.item().proposal.winner, "Corin"); eq(b.item().proposal.cost, 2, "the chain's cost, not a response's")
		b.ml("CONFIRM")
		local award = b.events("ITEM_AWARDED")[1]
		eq(award.payload.mlReason, "LEGENDARY"); eq(award.payload.cost, 2)
		eq(b.events("LEGENDARY_PROJECT_PAID")[1].payload.member, "Corin")
	end)

	it("a project without a builder flags NO_BUILDER; to the bank it is not a piece paid", function()
		local b = bench({ project = { builder = false },
			rules = rules(function(r) r.priority.bankCharacter = "Aurel" end) })
		b.open()
		b.ml("OPEN_ROLL")
		truthy(has(b.item().proposal.flags, "NO_BUILDER"))
		b.ml("REJECT", { ["then"] = "BANK" })
		b.ml("CONFIRM")
		eq(#b.events("ITEM_AWARDED"), 1)
		eq(#b.events("LEGENDARY_PROJECT_PAID"), 0)
	end)

	it("vote: the council votes, the majority wins at the chain's cost; confirm waits for the vote", function()
		local b = bench({ rules = rules(function(r) r.legendary.mode = "vote" end),
			isCouncil = function(name) return name == "Aurel" or name == "Bryn" or name == "Dara" end })
		b.open()
		b.ml("OPEN_ROLL")
		local item = b.item()
		eq(item.proposal.winner, "Bryn", "the builder is proposed first")
		truthy(F().VoteDecides(b.s, item)); falsy(F().VoteDecides(b.s, nil), "only the chain piece")
		eq(b.refused({ type = "CONFIRM", by = ML }), "VOTE_OPEN")
		eq(b.refused({ type = "VOTE", by = "Corin", choice = "Corin" }), "NOT_COUNCIL")
		b.must({ type = "VOTE", by = "Aurel", choice = "Corin" })
		b.must({ type = "VOTE", by = "Dara", choice = "Corin" })
		b.must({ type = "VOTE", by = "Bryn", choice = "Bryn" })
		b.ml("CLOSE_VOTE")
		eq(item.proposal.winner, "Corin"); eq(item.proposal.cost, 2)
		b.ml("CONFIRM")
		local award = b.events("ITEM_AWARDED")[1]
		eq(award.payload.member, "Corin"); eq(award.payload.mlReason, "COUNCIL_VOTE")
		deepEq(award.payload.votes, { Corin = 2, Bryn = 1 })
		eq(b.events("LEGENDARY_PROJECT_PAID")[1].payload.member, "Corin")
		eq(Lg().Credits(b.L, SEASON).Corin, 2)
	end)

	it("vote with awardMode auto: never awarded before the vote is closed", function()
		local b = bench({ rules = rules(function(r)
			r.legendary.mode = "vote"
			r.session.awardMode = "auto"
			r.session.interventionSeconds = 0
		end) })
		b.open()
		b.ml("OPEN_ROLL")
		isNil(b.item().autoAt)
		b.must({ type = "TICK", ts = 1100 })
		eq(b.item().state, "PROPOSAL")
		b.must({ type = "VOTE", by = "Aurel", choice = "Bryn" })
		b.ml("CLOSE_VOTE")
		b.ml("CONFIRM")
		eq(b.events("ITEM_AWARDED")[1].payload.member, "Bryn")
	end)

	it("roll: the piece is rolled like any item, the category prices it, the project is not touched", function()
		local b = bench({ rules = rules(function(r) r.legendary.mode = "roll" end) })
		b.open({ { itemID = LEFT, slot = 2, classID = 4, subclassID = 0, equipLoc = "INVTYPE_WRIST", quality = 4 } })
		b.ml("OPEN_ROLL")
		isNil(b.item().legendary)
		eq(b.s.state, "ROLLING")
		b.must({ type = "RESPONSE", player = "Aurel", response = "MS" })
		b.must({ type = "ROLL", player = "Aurel", value = 50, min = 1, max = 100 })
		b.ml("CLOSE_ROUND")
		eq(b.item().proposal.winner, "Aurel")
		b.ml("CONFIRM")
		isNil(b.events("ITEM_AWARDED")[1].payload.legendary)
		eq(#b.events("LEGENDARY_PROJECT_PAID"), 0)

		-- an item that is not tracked by the cost rules stays out in mode roll, as before
		local c = bench({ rules = rules(function(r) r.legendary.mode = "roll" end) })
		c.must({ type = "LOOT_OPENED", items = { LOW_ESSENCE }, encounter = 601 })
		eq(#c.s.items, 0); deepEq(c.s.skipped, { ESSENCE })
	end)

	it("queue: the first of the season's list who is present", function()
		local b = bench({ rules = rules(function(r) r.legendary.mode = "queue" end),
			project = { queue = { "Elin", "Corin", "Bryn" } } })
		b.open()
		b.ml("OPEN_ROLL")
		local p = b.item().proposal
		eq(p.winner, "Corin"); deepEq(p.reasons, { "LEGENDARY_QUEUE" }); eq(p.cost, 2)
		b.ml("CONFIRM")
		eq(b.events("LEGENDARY_PROJECT_PAID")[1].payload.member, "Corin")

		local c = bench({ rules = rules(function(r) r.legendary.mode = "queue" end), project = { queue = { "Elin" } } })
		c.open()
		c.ml("OPEN_ROLL")
		isNil(c.item().proposal.winner); truthy(has(c.item().proposal.flags, "QUEUE_EMPTY"))
	end)

	it("keeps a chain piece the cost rules would not track, and only for an open project", function()
		local b = bench()
		b.must({ type = "LOOT_OPENED", items = { LOW_ESSENCE }, encounter = 601 })
		eq(#b.s.items, 1); truthy(b.s.items[1].legendary)
		local c = bench({ pieces = false })   -- no projects known: the item is not tracked, as before M5-6
		c.must({ type = "LOOT_OPENED", items = { LOW_ESSENCE }, encounter = 601 })
		eq(#c.s.items, 0)
		local d = bench()
		assert(LG().Close(d.L, { author = ML, ts = 900, ref = d.project.id, outcome = "COMPLETED" }))
		d.must({ type = "LOOT_OPENED", items = { LOW_ESSENCE }, encounter = 601 })
		eq(#d.s.items, 0, "a completed project's piece is an ordinary drop")
	end)

	it("the master looter may correct the piece's cost before its turn; a project closed meanwhile is reported", function()
		local b = bench()
		b.open()
		b.ml("CORRECT_ITEM", { index = 1, cost = 1, reason = "LEGENDARY" })
		for _, cost in pairs(b.item(1).costs) do eq(cost, 1) end
		b.ml("OPEN_ROLL")
		eq(b.item().proposal.cost, 1)
		assert(LG().Close(b.L, { author = ML, ts = 1001, ref = b.project.id, outcome = "ABANDONED" }))
		local effects = b.ml("CONFIRM")
		local notPaid
		for _, e in ipairs(effects) do
			if e.type == "LEGENDARY_NOT_PAID" then notPaid = e end
		end
		eq(notPaid.code, "PROJECT_CLOSED")
		eq(#b.events("ITEM_AWARDED"), 1, "the award stands")
		deepEq(b.events("ITEM_AWARDED")[1].payload.corrections[1].reason, "LEGENDARY")
	end)

	it("a rejected piece comes back with the same proposal; a session saved before M5-6 still works", function()
		local b = bench()
		b.open()
		b.ml("OPEN_ROLL")
		b.ml("REJECT", { ["then"] = "REOPEN" })
		eq(b.item().proposal.winner, "Bryn")
		eq(b.refused({ type = "REJECT", by = ML, ["then"] = "NEXT_TIER" }), "NO_TIER")
		b.s.rules.legendary = nil   -- an older saved session: the presets
		b.ml("CONFIRM")
		eq(b.item(1).state, "ASSIGNED")
	end)
end)

---------------------------------------------------------------------------------------------------------------------

describe("the /fdcp legendary command", function()
	local LS = function() return FDCP.LegendaryService end

	it("reads item links or ids and the builder or the queue", function()
		local link = "|cffff8000|Hitem:19019::::::::70:::::|h[Thunderfury]|h|r"
		deepEq(LS().ParseItems(link), { 19019 })
		deepEq(LS().ParseItems("18563 18564, 19017"), { 18563, 18564, 19017 })
		local d = LS().ParseOpen("Thunderfury; " .. link .. "; 18563 18564 19017; Bryn")
		eq(d.name, "Thunderfury"); eq(d.item, 19019); deepEq(d.pieces, { 18563, 18564, 19017 }); eq(d.builder, "Bryn")
		isNil(d.queue)
		d = LS().ParseOpen("Atiesh; 22589; 22726; -; Corin Bryn")
		isNil(d.builder); deepEq(d.queue, { "Corin", "Bryn" })
		isNil(LS().ParseOpen("Atiesh; 22589"))
		isNil(LS().ParseOpen("; 22589; 22726; Bryn"))
		isNil(LS().ParseOpen("Atiesh; 22589 22590; 22726; Bryn"))
		isNil(LS().ParseOpen("Atiesh; 22589; 22726; Bryn Corin"))
	end)

	it("says every mode and a project's line in both languages", function()
		for _, lang in ipairs({ "enUS", "itIT" }) do
			for _, mode in ipairs(LG().MODE_ORDER) do
				local key = "LEGENDARY_MODE_" .. mode:upper()
				local text = FDCP.Locale.Text(lang, key)
				truthy(text ~= key and text ~= "", lang .. " " .. key)
			end
		end
		local line = LS().ProjectLine(1, { name = "Thunderfury", item = FINAL, builder = "Bryn-Camelot", paid = { {} },
			pieces = { LEFT, RIGHT }, open = true })
		truthy(line:find("Thunderfury", 1, true)); truthy(line:find("Bryn", 1, true))
		falsy(line:find("Camelot", 1, true)); falsy(line:find("LEGENDARY_", 1, true))
		line = LS().ProjectLine(2, { name = "Atiesh", item = 22589, paid = {}, pieces = { 22726 }, open = false,
			outcome = "ABANDONED" })
		falsy(line:find("LEGENDARY_", 1, true)); falsy(line:find("RC_", 1, true))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- A raid of four on the simulator: Aurel is the Guild Master and the master looter, Bryn an officer. Aurel opens the
-- project with /fdcp legendary, the boss drops a chain piece, the session proposes it to Bryn without a roll.

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end
local NAMES = { "Aurel", "Bryn", "Corin", "Dara" }
local NET_RANKS = { Aurel = 0, Bryn = 1, Corin = 3, Dara = 3 }
local BOSS, BOSS_GUID = 663, "Creature-0-3-2000-1-11502-0000A1B2C3"
local LEFT_LINK = "|cffff8000|Hitem:18563::::::::70:::::|h[Bindings of the Windseeker]|h|r"

local function setupFor(name)
	return function(M)
		M.items.Add{ id = LEFT, link = LEFT_LINK, name = "Bindings of the Windseeker", quality = 5, classID = 15,
			subclassID = 0 }
		local members = {}
		for _, n in ipairs(NAMES) do
			if n ~= name then members[#members + 1] = { name = n, rank = NET_RANKS[n], class = "WARRIOR" } end
		end
		M.guild.Set({ name = "Dragon", members = members, myRank = NET_RANKS[name] })
		M.loot.Set{ method = "master", masterLooter = name == "Aurel", masterPartyID = 1, threshold = 3,
			candidates = NAMES, slots = {} }
		M.encounter.Set{ instance = { name = "Molten Core", type = "raid", difficultyID = 9, difficultyName = "Normal",
			maxPlayers = 40, instanceID = 409 } }
	end
end

describe("a chain piece in a simulated raid", function()
	it("the master looter's client recognises the piece and the builder receives it at the chain's cost", function()
		local net = Sim.new{ realm = REALM, step = 0.25 }
		local c = {}
		for _, n in ipairs(NAMES) do c[n] = net:Client(n, { setup = setupFor(n) }) end
		net:Raid(NAMES)
		net:Advance(3)
		local a = c.Aurel.addon()
		local L = assert(a.NightController:Ledger())
		local gate = a.PermissionService:Gate()
		assert(a.Season.Open(L, { author = full("Aurel"), ts = a.Compat.ServerTime(), season = "S1",
			instances = { { id = 409, size = 40 } } }, nil, gate))
		for i, n in ipairs(NAMES) do
			assert(a.Members.Join(L, { author = full("Aurel"), ts = a.Compat.ServerTime() + i, season = "S1",
				member = full(n) }, nil, gate))
		end
		a.LegendaryService.Command("legendary open Thunderfury; 19019; 18563 18564 19017; Bryn")
		local list = a.LegendaryService:Projects()
		eq(#list, 1); eq(list[1].builder, full("Bryn"))
		assert(a.NightController:Open({ instanceID = 409 }))
		net:Advance(20)
		net:Encounter(BOSS, "Lucifron", "kill")
		c.Aurel.Mock.loot.Set{ slots = { { link = LEFT_LINK, name = "Bindings of the Windseeker", quality = 5,
			sources = { BOSS_GUID, 1 } } } }
		c.Aurel.Mock.loot.Open()
		net:Advance(3)
		local SC = a.SessionController
		local s = SC.session
		eq(#s.items, 1); truthy(s.items[1].legendary, "the piece is recognised from the ledger")
		assert(SC:Command("START"))   -- autoAdvance (the preset) opens the piece's turn: a proposal, no roll
		net:Advance(1)
		eq(s.state, "PROPOSAL")
		eq(s.items[1].proposal.winner, full("Bryn")); eq(s.items[1].proposal.cost, 2)
		-- the raid hears a proposal, no roll opened
		local view = c.Bryn.addon().Protocol.Session.view
		eq(view.proposal.w, full("Bryn")); isNil(view.round)
		assert(SC:Command("CONFIRM"))
		net:Advance(1)
		list = a.LegendaryService:Projects()
		eq(#list[1].paid, 1); eq(list[1].paid[1].member, full("Bryn"))
		eq(a.Ledger.Credits(L, "S1")[full("Bryn")], 2)
		a.LegendaryService.Command("legendary complete 1")
		falsy(a.LegendaryService:Projects()[1].open)
	end)
end)
