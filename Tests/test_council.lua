-- The loot council (M5-5, docs/ANALISI.md §3.6, §3.4): who is on it (the rank and the raid, or the rules' explicit list),
-- the interventions with their mandatory reason (category or cost before the roll, another candidate for obvious waste,
-- a player who did not roll at full cost), the void and the manual adjustment through the permission gate, the vote
-- (each member from their own client, the master looter sees the votes before confirming) and the audit that reads every
-- intervention back from the ledger. The last part runs a small raid on the network simulator.
local function F() return FDCP.SessionFSM end
local function Lg() return FDCP.Ledger end
local function C() return FDCP.Council end

local ML = "Dara"
local SEASON = "S1"
local RAID = { Aurel = true, Bryn = true, Corin = true, Dara = true }
local RING = { itemID = 19003, slot = 1, classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER", quality = 4 }
local SWORD = { itemID = 19002, slot = 3, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON", quality = 4 }

local function has(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then return true end
	end
	return false
end

local function rules(mutate)
	local r = FDCP.Rules.DefaultConfig()
	r.session.autoAdvance = false
	if mutate then mutate(r) end
	return r
end

-- A session on its own ledger. opts = { rules, isCouncil, credits }.
local function bench(opts)
	opts = opts or {}
	local b = { L = Lg().New(), t = 1000 }
	b.s = assert(F().New({ id = "S1-1", season = SEASON, ml = ML, ts = 1000, encounter = 601, rules = opts.rules or rules(),
		present = RAID, addon = RAID }))
	local function env() return { ledger = b.L, credits = opts.credits or {}, isCouncil = opts.isCouncil } end
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
	function b.awards()
		local out = {}
		for _, e in ipairs(Lg().Sorted(b.L)) do
			if e.type == "ITEM_AWARDED" then out[#out + 1] = e end
		end
		return out
	end
	-- The ring rolled by Aurel (MS, 40) and Bryn (MS, 80): Bryn wins at 1 credit; Corin and Dara do not answer.
	function b.toProposal(items)
		b.must({ type = "LOOT_OPENED", items = items or { RING }, encounter = 601 })
		b.ml("START")
		b.ml("OPEN_ROLL")
		b.must({ type = "RESPONSE", player = "Aurel", response = "MS" })
		b.must({ type = "RESPONSE", player = "Bryn", response = "MS" })
		b.must({ type = "ROLL", player = "Aurel", value = 40, min = 1, max = 100 })
		b.must({ type = "ROLL", player = "Bryn", value = 80, min = 1, max = 100 })
		b.ml("CLOSE_ROUND")
		eq(b.s.state, "PROPOSAL")
		eq(b.item().proposal.winner, "Bryn")
	end
	return b
end

---------------------------------------------------------------------------------------------------------------------

describe("who is on the council", function()
	it("by rank and presence in the raid (the preset)", function()
		local council = FDCP.Rules.DefaultConfig().council
		deepEq(council.members, {})
		truthy(C().IsMember(council, { name = "Bryn-Camelot", rank = true, present = true }))
		local ok, code = C().IsMember(council, { name = "Bryn-Camelot", rank = true, present = false })
		falsy(ok); eq(code, "NOT_PRESENT")
		ok, code = C().IsMember(council, { name = "Bryn-Camelot", rank = true })   -- the raid is not known
		falsy(ok); eq(code, "NOT_PRESENT")
		ok, code = C().IsMember(council, { name = "Corin-Camelot", rank = false, present = true })
		falsy(ok); eq(code, "NOT_COUNCIL")
		council.requirePresent = false
		truthy(C().IsMember(council, { name = "Bryn-Camelot", rank = true, present = false }))
	end)

	it("by the explicit list, which replaces the rank", function()
		local council = FDCP.Rules.DefaultConfig().council
		council.members = { "Corin-Camelot" }
		truthy(C().HasList(council))
		truthy(C().IsMember(council, { name = "Corin-Camelot", rank = false, present = true }))
		local ok, code = C().IsMember(council, { name = "Bryn-Camelot", rank = true, present = true })
		falsy(ok); eq(code, "NOT_COUNCIL")
		ok, code = C().IsMember(council, { name = "Corin-Camelot", rank = false, present = false })
		falsy(ok); eq(code, "NOT_PRESENT")
	end)

	it("checks the list in the rules, and gives older rules an empty one", function()
		local R = FDCP.Rules
		for _, bad in ipairs({ "Corin", { "Corin", "Corin" }, { "Co:rin" }, { [2] = "Corin" }, { "" } }) do
			local r = R.DefaultConfig()
			r.council.members = bad
			local ok, problems = R.Validate(r)
			falsy(ok); truthy(has(problems, "council.members"), tostring(bad))
		end
		local long = {}
		for i = 1, C().MAX_MEMBERS + 1 do long[i] = "P" .. i end
		local r = R.DefaultConfig()
		r.council.members = long
		falsy((R.Validate(r)))
		local old = R.DefaultConfig()
		old.council.members = nil
		deepEq(R.WithDefaults(old).council.members, {})
		truthy(R.Validate(R.WithDefaults(old)))
	end)
end)

---------------------------------------------------------------------------------------------------------------------

describe("interventions in a session, always with a reason", function()
	it("corrects the category or the cost before the roll, never after it opens", function()
		local b = bench()
		b.must({ type = "LOOT_OPENED", items = { RING, SWORD }, encounter = 601 })
		eq(b.refused({ type = "CORRECT_ITEM", by = ML, index = 1, cost = 3 }), "REASON_REQUIRED")
		eq(b.refused({ type = "CORRECT_ITEM", by = ML, index = 1, cost = 3, reason = "NOT_A_REASON" }), "REASON_REQUIRED")
		b.ml("CORRECT_ITEM", { index = 1, cost = 3, reason = "COUNCIL_COST" })
		eq(b.s.items[1].costs.MS, 3)
		b.ml("START")
		b.ml("CORRECT_ITEM", { index = 2, category = "offhand", reason = "WRONG_CATEGORY" })   -- still before its roll
		b.ml("OPEN_ROLL", { index = 1 })
		eq(b.refused({ type = "CORRECT_ITEM", by = ML, index = 1, cost = 1, reason = "WRONG_CATEGORY" }), "CATEGORY_LOCKED")
		eq(b.refused({ type = "CORRECT_ITEM", by = "Aurel", index = 2, cost = 1, reason = "WRONG_CATEGORY" }), "NOT_ML")
		-- the award carries the correction to the audit
		b.must({ type = "RESPONSE", player = "Aurel", response = "MS" })
		b.must({ type = "ROLL", player = "Aurel", value = 50, min = 1, max = 100 })
		b.ml("CLOSE_ROUND")
		b.ml("CONFIRM")
		local e = b.awards()[1]
		eq(e.payload.cost, 3)
		eq(#e.payload.corrections, 1)
		eq(e.payload.corrections[1].reason, "COUNCIL_COST"); eq(e.payload.corrections[1].cost, 3)
		eq(e.payload.corrections[1].by, ML)
	end)

	it("with lockCategoryOnOpen off, a correction is still possible while the roll is open", function()
		local b = bench({ rules = rules(function(r) r.session.lockCategoryOnOpen = false end) })
		b.must({ type = "LOOT_OPENED", items = { RING }, encounter = 601 })
		b.ml("START")
		b.ml("OPEN_ROLL")
		b.ml("CORRECT_ITEM", { index = 1, cost = 2, reason = "MISTAKE" })
		eq(b.item(1).costs.MS, 2)
	end)

	it("obvious waste: another candidate, who pays the cost of their own response", function()
		local b = bench()
		b.toProposal()
		eq(b.refused({ type = "MODIFY", by = ML, winner = "Aurel" }), "REASON_REQUIRED")
		b.ml("MODIFY", { winner = "Aurel", reason = "OBVIOUS_WASTE" })
		local p = b.item().proposal
		eq(p.winner, "Aurel"); eq(p.cost, 1); truthy(has(p.flags, "OUT_OF_ORDER"))
		b.ml("CONFIRM")
		local e = b.awards()[1]
		truthy(e.payload.intervention); eq(e.payload.mlReason, "OBVIOUS_WASTE")
		eq(e.payload.ruleWinner, "Bryn"); eq(e.payload.member, "Aurel")
	end)

	it("passed to game the system: a player who did not roll gets it at full cost", function()
		local b = bench({ rules = rules(function(r) r.cost.responseMultiplier.MS = 2 end) })
		b.toProposal()
		local full = b.item().proposal.cost
		b.ml("MODIFY", { winner = "Corin", reason = "PASSED_TO_GAME" })
		local p = b.item().proposal
		eq(p.winner, "Corin"); eq(p.cost, full); isNil(p.response)
		b.ml("CONFIRM")
		local e = b.awards()[1]
		eq(e.payload.member, "Corin"); eq(e.payload.cost, full); eq(e.payload.mlReason, "PASSED_TO_GAME")
	end)
end)

---------------------------------------------------------------------------------------------------------------------

describe("the council's vote in the state machine", function()
	local function isCouncil(name) return name == "Aurel" or name == "Bryn" or name == "Dara" end

	it("is off in the preset", function()
		local b = bench()
		b.toProposal()
		falsy(F().VotesOn(b.s))
		eq(b.refused({ type = "VOTE", by = "Aurel", choice = "Bryn" }), "NOT_COUNCIL_MODE")
	end)

	it("with council.vote the ML sees the votes before confirming; they go with the award", function()
		local b = bench({ rules = rules(function(r) r.council.vote = true end), isCouncil = isCouncil })
		b.toProposal()
		truthy(F().VotesOn(b.s))
		eq(b.refused({ type = "VOTE", by = "Corin", choice = "Aurel" }), "NOT_COUNCIL")
		eq(b.refused({ type = "VOTE", by = "Aurel", choice = "Zed" }), "NOT_PRESENT")
		local fx = b.must({ type = "VOTE", by = "Aurel", choice = "Bryn" })
		eq(fx[1].type, "VOTED")
		b.must({ type = "VOTE", by = "Dara", choice = "Aurel" })
		b.must({ type = "VOTE", by = "Dara", choice = "Bryn" })   -- a member changes their mind: one vote each
		deepEq(b.item().votes, { Aurel = "Bryn", Dara = "Bryn" })
		local board = FDCP.SessionBoard.Build({ host = true, session = b.s }, { now = b.t })
		eq(board.votes.total, 2); truthy(board.votes.open)
		eq(board.votes.tally[1].choice, "Bryn"); eq(board.votes.tally[1].n, 2)
		truthy(board.actions.closeVote); truthy(board.actions.confirm)   -- advisory: the ML may confirm at once
		b.ml("CONFIRM")
		deepEq(b.awards()[1].payload.votes, { Bryn = 2 })
		falsy(b.awards()[1].payload.intervention)
	end)

	it("council mode: the vote decides, a majority for another player is an intervention", function()
		local b = bench({ rules = rules(function(r) r.session.awardMode = "council" end), isCouncil = isCouncil })
		b.toProposal()
		eq(b.refused({ type = "CONFIRM", by = ML }), "VOTE_OPEN")
		b.must({ type = "VOTE", by = "Aurel", choice = "Aurel" })
		b.must({ type = "VOTE", by = "Dara", choice = "Aurel" })
		b.must({ type = "VOTE", by = "Bryn", choice = "Bryn" })
		b.ml("CLOSE_VOTE")
		eq(b.item().proposal.winner, "Aurel")
		eq(b.refused({ type = "VOTE", by = "Bryn", choice = "Aurel" }), "VOTE_CLOSED")
		b.ml("CONFIRM")
		local e = b.awards()[1]
		eq(e.payload.mlReason, "COUNCIL_VOTE"); deepEq(e.payload.votes, { Aurel = 2, Bryn = 1 })
	end)

	it("auto mode: a vote against the proposal holds the automatic award for the ML", function()
		local b = bench({ rules = rules(function(r)
			r.session.awardMode = "auto"; r.session.interventionSeconds = 10; r.council.vote = true
		end), isCouncil = isCouncil })
		b.toProposal()
		truthy(b.item().autoAt)
		b.must({ type = "VOTE", by = "Aurel", choice = "Bryn" })   -- agrees: the window keeps running
		truthy(b.item().autoAt)
		local fx = b.must({ type = "VOTE", by = "Dara", choice = "Aurel" })
		eq(fx[#fx].type, "AUTO_HELD")
		isNil(b.item().autoAt); eq(b.item().autoHeld, "VOTE")
		b.t = 2000
		b.must({ type = "TICK" })
		eq(b.s.state, "PROPOSAL", "nothing was awarded by itself")
		local board = FDCP.SessionBoard.Build({ host = true, session = b.s }, { now = b.t })
		eq(board.proposal.autoHeld, "VOTE")
		b.ml("CONFIRM")
		eq(#b.awards(), 1)
	end)

	it("auto mode with agreeing votes still awards by itself", function()
		local b = bench({ rules = rules(function(r)
			r.session.awardMode = "auto"; r.session.interventionSeconds = 10; r.council.vote = true
		end), isCouncil = isCouncil })
		b.toProposal()
		b.must({ type = "VOTE", by = "Aurel", choice = "Bryn" })
		b.t = 1020
		b.must({ type = "TICK" })
		eq(#b.awards(), 1)
		deepEq(b.awards()[1].payload.votes, { Bryn = 1 })
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Void and adjust through the permission gate: GM rank 0, officer 1, raider 3.

local GM, OFFICER, RAIDER = "Aurel", "Bryn", "Corin"
local RANKS = { Aurel = 0, Bryn = 1, Corin = 3 }
local function gate() return FDCP.Permissions.Gate(function(author) return RANKS[author] end) end

local function season()
	local L = Lg().New()
	assert(FDCP.Season.Open(L, { author = GM, ts = 1, season = SEASON, instances = { { id = 409, size = 40 } } }, nil, gate()))
	for i, name in ipairs({ "Aurel", "Bryn", "Corin", "Dara" }) do
		assert(FDCP.Members.Join(L, { author = OFFICER, ts = 1 + i, season = SEASON, member = name }, nil, gate()))
	end
	return L
end

local function award(L, ts, member, cost, extra)
	local payload = { target = "member", member = member, item = 19003, cost = cost, reasons = { "ONLY_CANDIDATE" },
		flags = {} }
	for k, v in pairs(extra or {}) do payload[k] = v end
	return assert(Lg().Append(L, { author = OFFICER, ts = ts, season = SEASON, type = "ITEM_AWARDED", payload = payload },
		gate()))
end

describe("void and adjust, through the permission gate", function()
	it("outside a night only credits.adjust (the GM in the preset) writes them", function()
		local L = season()
		local a = award(L, 10, "Bryn", 1)
		eq(Lg().Credits(L, SEASON).Bryn, 1)
		local e, code = C().Void(L, { author = OFFICER, ts = 20, ref = a.id, reason = "MISTAKE" }, gate())
		isNil(e); eq(code, "RANK_TOO_LOW")
		_, code = C().Void(L, { author = GM, ts = 20, ref = a.id }, gate())
		eq(code, "REASON_REQUIRED")
		_, code = C().Void(L, { author = GM, ts = 20, ref = a.id, reason = "PENALTY" }, gate())   -- not a void's reason
		eq(code, "REASON_REQUIRED")
		_, code = C().Void(L, { author = GM, ts = 20, ref = "Nobody:9", reason = "MISTAKE" }, gate())
		eq(code, "REF_MISSING")
		local v = assert(C().Void(L, { author = GM, ts = 20, ref = a.id, reason = "DUPLICATE_AWARD" }, gate()))
		eq(v.type, "AWARD_VOIDED"); eq(v.payload.member, "Bryn"); eq(v.payload.item, 19003)
		eq(Lg().Credits(L, SEASON).Bryn, 0, "the credits come back")
		truthy(Lg().Get(L, a.id), "the award stays in the ledger")
		_, code = C().Void(L, { author = GM, ts = 21, ref = a.id, reason = "MISTAKE" }, gate())
		eq(code, "ALREADY_VOIDED")
		_, code = C().Void(L, { author = GM, ts = 21, ref = v.id, reason = "MISTAKE" }, gate())
		eq(code, "REF_NOT_VOIDABLE")

		_, code = C().Adjust(L, { author = OFFICER, ts = 30, season = SEASON, member = "Corin", delta = -1,
			reason = "MISTAKE" }, gate())
		eq(code, "RANK_TOO_LOW")
		local adj = assert(C().Adjust(L, { author = GM, ts = 30, season = SEASON, member = "Corin", delta = 2,
			reason = "PENALTY" }, gate()))
		eq(Lg().Credits(L, SEASON).Corin, 2)
		-- an adjustment can be voided too
		assert(C().Void(L, { author = GM, ts = 31, ref = adj.id, reason = "MISTAKE" }, gate()))
		eq(Lg().Credits(L, SEASON).Corin, 0)
	end)

	it("during a night of the season the master looter (night.run) writes them", function()
		local L = season()
		local a = award(L, 10, "Bryn", 1)
		assert(FDCP.Nights.Open(L, { author = OFFICER, ts = 50, season = SEASON, date = "2026-11-12", instanceID = 409,
			difficulty = "normal" }, gate()))
		assert(C().Void(L, { author = OFFICER, ts = 60, ref = a.id, reason = "OBVIOUS_WASTE" }, gate()))
		assert(C().Adjust(L, { author = OFFICER, ts = 61, season = SEASON, member = "Dara", delta = -1, reason = "BONUS" }, gate()))
		local _, code = C().Adjust(L, { author = RAIDER, ts = 62, season = SEASON, member = "Dara", delta = 1,
			reason = "MISTAKE" }, gate())
		eq(code, "RANK_TOO_LOW")
		eq(Lg().Credits(L, SEASON).Dara, -1)
	end)

	it("refuses an adjustment without a reason, of nothing, or for someone outside the pool", function()
		local L = season()
		local function adjust(fields)
			local d = { author = GM, ts = 40, season = SEASON, member = "Dara", delta = 1, reason = "BONUS" }
			for k, v in pairs(fields) do d[k] = v end
			local e, code = C().Adjust(L, d, gate())
			isNil(e)
			return code
		end
		eq(adjust({ reason = false }), "REASON_REQUIRED")
		eq(adjust({ reason = "OBVIOUS_WASTE" }), "REASON_REQUIRED")
		eq(adjust({ delta = 0 }), "BAD_DELTA")
		eq(adjust({ delta = 1001 }), "BAD_DELTA")
		eq(adjust({ delta = "1" }), "BAD_DELTA")
		eq(adjust({ member = "Zed" }), "NOT_MEMBER")
		eq(Lg().Count(L), 5, "nothing was written")
	end)
end)

describe("the audit", function()
	it("reads every intervention back from the ledger, in order", function()
		local L = season()
		local plain = award(L, 10, "Aurel", 1)
		local modified = award(L, 11, "Corin", 1, { intervention = true, mlReason = "OBVIOUS_WASTE", ruleWinner = "Bryn",
			ruleCost = 1, flags = { "OUT_OF_ORDER" }, votes = { Corin = 2 },
			corrections = { { cost = 1, reason = "COUNCIL_COST", by = OFFICER } } })
		local voted = award(L, 12, "Dara", 1, { votes = { Dara = 3 } })
		assert(C().Void(L, { author = GM, ts = 20, ref = modified.id, reason = "MISTAKE" }, gate()))
		assert(C().Adjust(L, { author = GM, ts = 21, season = SEASON, member = "Bryn", delta = 1, reason = "PENALTY" }, gate()))
		local list = C().Audit(L, SEASON)
		local kinds = {}
		for i, e in ipairs(list) do kinds[i] = e.kind end
		deepEq(kinds, { "CORRECT", "MODIFY", "VOTE", "VOID", "ADJUST" })
		eq(list[1].reason, "COUNCIL_COST"); eq(list[1].id, modified.id)
		eq(list[2].member, "Corin"); eq(list[2].ruleWinner, "Bryn"); eq(list[2].reason, "OBVIOUS_WASTE")
		truthy(list[2].voided, "the voided award is marked")
		deepEq(list[2].votes, { Corin = 2 })
		eq(list[3].id, voted.id); falsy(list[3].voided)
		eq(list[4].ref, modified.id); eq(list[4].refType, "ITEM_AWARDED"); eq(list[4].reason, "MISTAKE")
		eq(list[5].delta, 1); eq(list[5].reason, "PENALTY"); eq(list[5].author, GM)
		for _, e in ipairs(list) do isNil(e.id == plain.id and e or nil, "a plain award is no intervention") end
		eq(#C().Audit(L, "S2"), 0)
		-- the awards a void can still cancel, newest first
		local voidable = C().Voidable(L, SEASON)
		eq(#voidable, 2); eq(voidable[1].id, voted.id); eq(voidable[2].id, plain.id)
	end)

	it("says every entry in words", function()
		local L = season()
		award(L, 11, "Corin", 1, { intervention = true, mlReason = "OBVIOUS_WASTE", ruleWinner = "Bryn", ruleCost = 1,
			flags = {}, corrections = { { cost = 1, reason = "COUNCIL_COST", by = OFFICER } } })
		local v = award(L, 12, "Dara", 1, { votes = { Dara = 3 } })
		assert(C().Void(L, { author = GM, ts = 20, ref = v.id, reason = "MISTAKE" }, gate()))
		assert(C().Adjust(L, { author = GM, ts = 21, season = SEASON, member = "Bryn", delta = 1, reason = "PENALTY" }, gate()))
		for _, entry in ipairs(C().Audit(L, SEASON)) do
			local line = FDCP.CouncilService.AuditLine(entry)
			truthy(type(line) == "string" and #line > 10, entry.kind)
			falsy(line:find("COUNCIL_AUDIT", 1, true), line)
		end
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The vote over the network: a raid of five on the simulator. Aurel is the Guild Master and the master looter, Bryn and
-- Elin officers (rank 1: council.member), Corin and Dara raiders.

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end
local NAMES = { "Aurel", "Bryn", "Corin", "Dara", "Elin" }
local NET_RANKS = { Aurel = 0, Bryn = 1, Elin = 1, Corin = 3, Dara = 3 }
local BOSS, BOSS_GUID = 663, "Creature-0-3-2000-1-11502-0000A1B2C3"
local RING_LINK = "|cffa335ee|Hitem:19003::::::::70:::::|h[Ring of the Keeper]|h|r"

local function setupFor(name)
	return function(M)
		M.items.Add{ id = 19003, link = RING_LINK, name = "Ring of the Keeper", quality = 4, equipLoc = "INVTYPE_FINGER",
			classID = 4, subclassID = 0 }
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

local function A(c) return c.addon() end

-- The raid, the season and the rules (awardMode `mode`), the night, the kill, the ring's roll: Bryn and Corin answer
-- main-spec and roll (Bryn 80, Corin 30): the proposal names Bryn.
local function raidToProposal(mode)
	local net = Sim.new{ realm = REALM, step = 0.25 }
	local c = {}
	for _, n in ipairs(NAMES) do c[n] = net:Client(n, { setup = setupFor(n) }) end
	net:Raid(NAMES)
	net:Advance(3)
	local a = A(c.Aurel)
	local L = assert(a.NightController:Ledger())
	assert(a.Season.Open(L, { author = full("Aurel"), ts = a.Compat.ServerTime(), season = "S1",
		instances = { { id = 409, size = 40 } } }, nil, a.PermissionService:Gate()))
	local r = a.Rules.Current(L)
	r.session.awardMode = mode
	r.session.autoAdvance = false
	assert(a.Rules.Change(L, { author = full("Aurel"), ts = a.Compat.ServerTime(), rules = r, confirmed = true },
		a.PermissionService:Gate()))
	assert(a.NightController:Open({ instanceID = 409 }))
	net:Advance(20)
	net:Encounter(BOSS, "Lucifron", "kill")
	c.Aurel.Mock.loot.Set{ slots = { { link = RING_LINK, name = "Ring of the Keeper", quality = 4, sources = { BOSS_GUID, 1 } } } }
	c.Aurel.Mock.loot.Open()
	net:Advance(3)
	local SC = a.SessionController
	assert(SC:Command("START"))
	assert(SC:Command("OPEN_ROLL"))
	net:Advance(1)
	local P = function(n) return A(c[n]).Protocol.Session end
	assert(P("Bryn"):Respond("MS"))
	assert(P("Corin"):Respond("MS"))
	net:Advance(1)
	net:Roll("Bryn", 80)
	net:Roll("Corin", 30)
	net:Advance(1)
	assert(SC:Command("CLOSE_ROUND"))
	net:Advance(1)
	local s = SC.session
	eq(s.state, "PROPOSAL")
	eq(s.items[1].proposal.winner, full("Bryn"))
	return net, c, s
end

describe("the vote over the network", function()
	it("each council member votes from their own client; the ML sees the votes and closes the vote", function()
		local net, c, s = raidToProposal("council")
		local function CS(n) return A(c[n]).CouncilService end
		truthy(CS("Bryn"):IsMember(), "an officer in the raid is on the council")
		falsy(CS("Corin"):IsMember(), "a raider is not")
		-- every client heard the proposal
		eq(A(c.Elin).Protocol.Session.view.proposal.w, full("Bryn"))

		assert(CS("Elin"):Vote("Corin"))
		assert(CS("Bryn"):Vote("Corin"))
		local ok, code = CS("Corin"):Vote("Corin")
		falsy(ok); eq(code, "NOT_COUNCIL")
		net:Advance(1)
		deepEq(s.items[1].votes, { [full("Elin")] = full("Corin"), [full("Bryn")] = full("Corin") })
		-- the master looter's window shows the votes and offers to close the vote, not to confirm yet
		local board = A(c.Aurel).SessionController:Board()
		eq(board.votes.total, 2); eq(board.votes.tally[1].choice, full("Corin"))
		truthy(board.actions.closeVote); falsy(board.actions.confirm)
		truthy(A(c.Aurel).SessionBoard.VoteText(board.votes):find("Corin", 1, true))
		-- another council member sees the votes in their read-only view
		deepEq(A(c.Bryn).Protocol.Session:Votes(1), { [full("Elin")] = full("Corin"), [full("Bryn")] = full("Corin") })

		-- a raider's own message is refused at the ML, and so is a vote that names another voter
		local ml = A(c.Aurel).Protocol.Session
		local refusedBefore, forgedBefore = ml.stats.refused, ml.stats.forged
		A(c.Corin).Transport:Send("RAID", { t = "SVOTE", s = s.id, i = 1, c = full("Corin") }, { prio = "ALERT" })
		A(c.Corin).Transport:Send("RAID", { t = "SVOTE", s = s.id, i = 1, c = full("Corin"), by = full("Elin") },
			{ prio = "ALERT" })
		net:Advance(1)
		eq(ml.stats.refused, refusedBefore + 1, "NOT_COUNCIL")
		eq(ml.stats.forged, forgedBefore + 1, "FORGED")
		eq(s.items[1].votes[full("Corin")], nil)

		-- the ML closes the vote: the majority goes to Corin, an intervention with COUNCIL_VOTE
		local SC = A(c.Aurel).SessionController
		assert(SC:Command("CLOSE_VOTE"))
		net:Advance(1)
		eq(s.items[1].proposal.winner, full("Corin"))
		truthy(A(c.Bryn).Protocol.Session.view.proposal.vc, "the raid hears the vote closed")
		ok, code = CS("Bryn"):Vote("Bryn")
		falsy(ok); eq(code, "VOTE_CLOSED")
		assert(SC:Command("CONFIRM"))
		local e
		for _, ev in ipairs(A(c.Aurel).Ledger.Sorted(SC:Ledger())) do
			if ev.type == "ITEM_AWARDED" then e = ev end
		end
		eq(e.payload.member, full("Corin")); eq(e.payload.mlReason, "COUNCIL_VOTE")
		deepEq(e.payload.votes, { [full("Corin")] = 2 })
		local audit = CS("Aurel"):Audit()
		eq(audit[#audit].kind, "MODIFY"); eq(audit[#audit].reason, "COUNCIL_VOTE")
	end)

	it("a member who reloads gets the votes cast so far with the state", function()
		local net, c, s = raidToProposal("council")
		assert(A(c.Bryn).CouncilService:Vote("Corin"))
		net:Advance(1)
		net:Reload("Elin")
		net:Advance(8)
		deepEq(A(c.Elin).Protocol.Session:Votes(1), { [full("Bryn")] = full("Corin") })
		eq(s.items[1].votes[full("Bryn")], full("Corin"))
	end)

	it("a client of the previous protocol drops the vote unread and keeps following the session", function()
		local net, c = raidToProposal("confirm")
		local P = A(c.Dara).Protocol
		local before = P.Session.stats.bad
		-- what an older client does with a type it does not know: the codec drops it (simulated by a decode of an unknown type)
		truthy(P.VERSION >= 4); eq(P.MIN, 2)
		local codec = A(c.Dara).Codec
		local text = codec:Encode({ t = "SVOTEX", s = "x" })
		isNil((codec:Decode(text)), "an unknown type is not decoded")
		eq(P.Session.stats.bad, before)
		eq(P.Session.view.proposal.w, full("Bryn"))
	end)
end)
