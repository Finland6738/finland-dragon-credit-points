-- Ledger (M2-3): immutable events with per-author ids, append and idempotent merge, compensation instead of deletion,
-- credits computed from the season's events, snapshots that give the same totals, payload schema versions, the sync
-- helpers of M6 (high-water marks per author) and the first kills of the Progress export. Pure domain code.
local function Lg() return FDCP.Ledger end

local S = "S1"

local function award(L, author, ts, member, cost, extra)
	local p = { member = member, item = 19000 + ts, cost = cost, response = "MS", reasons = { "LOWER_CREDITS" } }
	for k, v in pairs(extra or {}) do p[k] = v end
	return assert(Lg().Append(L, { author = author, ts = ts, season = S, type = "ITEM_AWARDED", payload = p }))
end

local function void(L, author, ts, ref)
	return Lg().Append(L, { author = author, ts = ts, season = S, type = "AWARD_VOIDED",
		payload = { ref = ref, reason = "WRONG_WINNER" } })
end

local function adjust(L, author, ts, member, delta)
	return assert(Lg().Append(L, { author = author, ts = ts, season = S, type = "CREDITS_ADJUSTED",
		payload = { member = member, delta = delta, reason = "MANUAL_FIX" } }))
end

local function join(L, author, ts, member, initial)
	return assert(Lg().Append(L, { author = author, ts = ts, season = S, type = "MEMBER_JOINED",
		payload = { member = member, initialCredits = initial } }))
end

-- A deterministic random generator (the same sequences on every run and every machine).
local function rng(seed)
	local state = seed
	return function(n)
		state = (state * 1103515245 + 12345) % 2147483648
		return (math.floor(state / 65536) % n) + 1
	end
end

local function shuffle(list, rand)
	local out = {}
	for i, v in ipairs(list) do out[i] = v end
	for i = #out, 2, -1 do
		local j = rand(i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

local function all(L)
	local list = {}
	for _, e in pairs(L.events) do list[#list + 1] = e end
	return list
end

describe("append", function()
	it("gives ids unique per author: author + sequence", function()
		local L = Lg().New()
		local a1 = award(L, "Aurel-Camelot", 10, "Bryn", 2)
		local a2 = award(L, "Aurel-Camelot", 11, "Corin", 1)
		local b1 = award(L, "Dara-Camelot", 11, "Corin", 1)
		eq(a1.id, "Aurel-Camelot:1")
		eq(a2.id, "Aurel-Camelot:2")
		eq(b1.id, "Dara-Camelot:1")
		eq(a1.v, 1)
		eq(Lg().Count(L), 3)
		deepEq(Lg().Heads(L), { ["Aurel-Camelot"] = 2, ["Dara-Camelot"] = 1 })
	end)

	it("copies the payload: changing the draft later changes nothing", function()
		local L = Lg().New()
		local p = { member = "Bryn", item = 1, cost = 2 }
		local e = Lg().Append(L, { author = "Aurel", ts = 1, season = S, type = "ITEM_AWARDED", payload = p })
		p.cost = 99
		eq(e.payload.cost, 2)
		eq(Lg().Credits(L, S).Bryn, 2)
	end)

	it("refuses bad events with a code", function()
		local L = Lg().New()
		local function try(draft) local e, code = Lg().Append(L, draft); isNil(e); return code end
		eq(try({ author = "Aurel", ts = 1, season = S, type = "NOPE", payload = {} }), "UNKNOWN_TYPE")
		eq(try({ author = "", ts = 1, season = S, type = "ITEM_AWARDED", payload = {} }), "author")
		eq(try({ author = "A:b", ts = 1, season = S, type = "ITEM_AWARDED", payload = {} }), "author")
		eq(try({ author = "Aurel", ts = -1, season = S, type = "ITEM_AWARDED", payload = { member = "B", item = 1, cost = 1 } }), "ts")
		eq(try({ author = "Aurel", ts = 1, type = "ITEM_AWARDED", payload = { member = "B", item = 1, cost = 1 } }), "season")
		eq(try({ author = "Aurel", ts = 1, season = S, type = "ITEM_AWARDED", payload = { item = 1, cost = 1 } }), "payload:member")
		eq(try({ author = "Aurel", ts = 1, season = S, type = "ITEM_AWARDED", payload = { member = "B", item = 1, cost = -1 } }), "payload:cost")
		eq(try({ author = "Aurel", ts = 1, season = S, type = "ITEM_AWARDED", payload = { member = "B", item = 1, cost = 1, reasons = { "a sentence" } } }), "payload:reasons")
		eq(try({ author = "Aurel", ts = 1, season = S, type = "CREDITS_ADJUSTED", payload = { member = "B", delta = 1, reason = "because he asked" } }), "payload:reason")
		eq(try({ author = "Aurel", ts = 1, season = S, type = "CREDITS_ADJUSTED", payload = { member = "B", delta = 0, reason = "X" } }), "payload:delta")
		eq(try({ author = "Aurel", ts = 1, season = S, type = "DROP_SEEN", payload = { f = function() end } }), "payload")
		eq(Lg().Count(L), 0)
		deepEq(Lg().Heads(L), {})
	end)

	it("accepts guild-level types without a season", function()
		local L = Lg().New()
		notNil(Lg().Append(L, { author = "Aurel", ts = 1, type = "CONFIG_CHANGED", payload = { key = "metric", value = "credits" } }))
		notNil(Lg().Append(L, { author = "Aurel", ts = 2, type = "PERMISSIONS_CHANGED", payload = { award = 2 } }))
	end)

	it("an award to the bank or the disenchanter moves no credits", function()
		local L = Lg().New()
		notNil(Lg().Append(L, { author = "Aurel", ts = 1, season = S, type = "ITEM_AWARDED",
			payload = { target = "bank", item = 5, cost = 0, reasons = { "BOE_BANK" } } }))
		notNil(Lg().Append(L, { author = "Aurel", ts = 2, season = S, type = "ITEM_AWARDED",
			payload = { target = "disenchant", item = 6, cost = 0 } }))
		local _, code = Lg().Append(L, { author = "Aurel", ts = 3, season = S, type = "ITEM_AWARDED",
			payload = { target = "guild", item = 6, cost = 0 } })
		eq(code, "payload:target")
		deepEq(Lg().Credits(L, S), {})
	end)
end)

describe("credits", function()
	it("are the sum of the season's events, decimals included", function()
		local L = Lg().New()
		join(L, "Aurel", 1, "Bryn", 3)
		award(L, "Aurel", 2, "Bryn", 2)
		award(L, "Aurel", 3, "Corin", 1.5)
		award(L, "Aurel", 4, "Corin", 0.1)
		award(L, "Aurel", 5, "Corin", 0.2)
		adjust(L, "Aurel", 6, "Dara", -1)
		Lg().Append(L, { author = "Aurel", ts = 7, season = "S2", type = "ITEM_AWARDED",
			payload = { member = "Bryn", item = 9, cost = 2 } })
		deepEq(Lg().Credits(L, S), { Bryn = 5, Corin = 1.8, Dara = -1 })
		deepEq(Lg().Credits(L, "S2"), { Bryn = 2 })
		deepEq(Lg().Credits(L, "S3"), {})
	end)

	it("count only the first MEMBER_JOINED of a member, whatever the arrival order", function()
		local A, B = Lg().New(), Lg().New()
		local late = join(A, "Aurel", 50, "Bryn", 4)
		local early = join(A, "Dara", 10, "Bryn", 2)
		Lg().Merge(B, { late }); Lg().TakeSnapshot(B, 60); Lg().Merge(B, { early })
		eq(Lg().Credits(A, S).Bryn, 2)
		eq(Lg().Credits(B, S).Bryn, 2)
		eq(Lg().Credits(B, S, { full = true }).Bryn, 2)
	end)

	it("a void restores the previous credits", function()
		local L = Lg().New()
		award(L, "Aurel", 1, "Bryn", 1)
		local before = Lg().Credits(L, S)
		local wrong = award(L, "Aurel", 2, "Bryn", 2)
		eq(Lg().Credits(L, S).Bryn, 3)
		local v = assert(void(L, "Dara", 3, wrong.id))
		deepEq(Lg().Credits(L, S), before)
		truthy(Lg().IsVoided(L, wrong.id))
		notNil(Lg().Get(L, wrong.id))   -- never deleted: the audit still shows it
		eq(v.payload.ref, wrong.id)
	end)

	it("a void of an adjustment takes the adjustment back", function()
		local L = Lg().New()
		local a = adjust(L, "Aurel", 1, "Bryn", 3)
		eq(Lg().Credits(L, S).Bryn, 3)
		notNil(void(L, "Aurel", 2, a.id))
		eq(Lg().Credits(L, S).Bryn, 0)
	end)

	it("refuses a void of a missing, not voidable or already voided event", function()
		local L = Lg().New()
		local a = award(L, "Aurel", 1, "Bryn", 2)
		local j = join(L, "Aurel", 2, "Corin", 0)
		local _, c1 = void(L, "Aurel", 3, "Aurel:99"); eq(c1, "REF_MISSING")
		local _, c2 = void(L, "Aurel", 3, j.id); eq(c2, "REF_NOT_VOIDABLE")
		local _, c3 = void(L, "Aurel", 3, "nonsense"); eq(c3, "payload:ref")
		local v = assert(void(L, "Aurel", 3, a.id))
		local _, c4 = void(L, "Dara", 4, a.id); eq(c4, "ALREADY_VOIDED")
		local _, c5 = void(L, "Dara", 4, v.id); eq(c5, "REF_NOT_VOIDABLE")
		eq(Lg().Credits(L, S).Bryn, 0)
	end)

	it("two voids of the same award (two officers offline) take it back once", function()
		local A, B, C = Lg().New(), Lg().New(), Lg().New()
		local a = award(A, "Aurel", 1, "Bryn", 2)
		Lg().Merge(B, { a }); Lg().Merge(C, { a })
		local v1 = assert(void(B, "Dara", 2, a.id))
		local v2 = assert(void(C, "Esme", 3, a.id))
		Lg().Merge(A, { v2, v1 })
		eq(Lg().Credits(A, S).Bryn, 0)
	end)

	it("a void that arrives before its award cancels it", function()
		local A, B = Lg().New(), Lg().New()
		local a = award(A, "Aurel", 1, "Bryn", 2)
		local v = assert(void(A, "Dara", 2, a.id))
		Lg().Merge(B, { v })
		deepEq(Lg().Credits(B, S), {})
		Lg().TakeSnapshot(B, 3)
		Lg().Merge(B, { a })
		eq(Lg().Credits(B, S).Bryn or 0, 0)
		eq(Lg().Credits(B, S, { full = true }).Bryn or 0, 0)
	end)
end)

describe("merge", function()
	it("merging the same events twice changes nothing", function()
		local A, B = Lg().New(), Lg().New()
		join(A, "Aurel", 1, "Bryn", 1)
		local a = award(A, "Aurel", 2, "Bryn", 2)
		award(A, "Dara", 3, "Corin", 1)
		void(A, "Dara", 4, a.id)
		local r1 = Lg().Merge(B, all(A))
		eq(r1.added, 4)
		local credits = Lg().Credits(B, S)
		local r2 = Lg().Merge(B, all(A))
		eq(r2.added, 0)
		eq(r2.duplicate, 4)
		deepEq(Lg().Credits(B, S), credits)
		deepEq(Lg().Credits(B, S), Lg().Credits(A, S))
		eq(Lg().Count(B), 4)
	end)

	it("reports a conflict (same id, other content) and keeps the stored event", function()
		local A, B = Lg().New(), Lg().New()
		local a = award(A, "Aurel", 1, "Bryn", 2)
		local forged = {}
		for k, v in pairs(a) do forged[k] = v end
		forged.payload = { member = "Bryn", item = a.payload.item, cost = 0 }
		Lg().Merge(B, { a })
		local r = Lg().Merge(B, { forged })
		deepEq(r.conflict, { a.id })
		eq(r.added, 0)
		eq(Lg().Credits(B, S).Bryn, 2)
	end)

	it("refuses malformed events and keeps the good ones", function()
		local A, B = Lg().New(), Lg().New()
		local a = award(A, "Aurel", 1, "Bryn", 2)
		local badId = { id = "Aurel:7", author = "Aurel", seq = 2, ts = 1, season = S, type = "DROP_SEEN", v = 1, payload = {} }
		local r = Lg().Merge(B, { a, badId, "junk" })
		eq(r.added, 1)
		deepEq(r.invalid, { "id", "event" })
	end)

	it("keeps events of an unknown type or a newer version for sync, and ignores them in the totals", function()
		local A = Lg().New()
		local future = { id = "Zed:1", author = "Zed", seq = 1, ts = 5, season = S, type = "ITEM_AWARDED", v = 9,
			payload = { whatever = { 1, 2 } } }
		local unknown = { id = "Zed:2", author = "Zed", seq = 2, ts = 6, season = S, type = "BOUNTY_PAID", v = 1,
			payload = { member = "Bryn", amount = 3 } }
		local r = Lg().Merge(A, { future, unknown })
		eq(r.added, 2)
		deepEq(Lg().Credits(A, S), {})
		deepEq(Lg().Stats(A), { events = 2, unreadable = 2 })
		eq(#Lg().Since(A, {}), 2)   -- forwarded to the next officer
	end)

	it("a ledger written by a newer addon is read-only", function()
		local L, readOnly = Lg().Open({ schema = 99, events = {} })
		truthy(readOnly)
		local e, code = Lg().Append(L, { author = "Aurel", ts = 1, season = S, type = "DROP_SEEN", payload = {} })
		isNil(e); eq(code, "READ_ONLY")
		local r, code2 = Lg().Merge(L, {})
		isNil(r); eq(code2, "READ_ONLY")
		local _, ro = Lg().Open({})
		falsy(ro)
	end)
end)

describe("payload versions", function()
	it("upgrades an older payload on read and never changes the stored event", function()
		local TYPES, UPGRADES = Lg().TYPES, Lg().UPGRADES
		local old = TYPES.ITEM_AWARDED.v
		TYPES.ITEM_AWARDED.v = 2
		UPGRADES.ITEM_AWARDED = { [1] = function(p) p.cost = p.price; p.price = nil; return p end }
		local ok, err = pcall(function()
			local L = Lg().New()
			local e = { id = "Aurel:1", author = "Aurel", seq = 1, ts = 1, season = S, type = "ITEM_AWARDED", v = 1,
				payload = { member = "Bryn", item = 3, price = 2 } }
			eq(Lg().Merge(L, { e }).added, 1)
			eq(Lg().Credits(L, S).Bryn, 2)
			eq(L.events["Aurel:1"].payload.price, 2)
			isNil(L.events["Aurel:1"].payload.cost)
			eq(Lg().Append(L, { author = "Aurel", ts = 2, season = S, type = "ITEM_AWARDED",
				payload = { member = "Bryn", item = 4, cost = 1 } }).v, 2)
		end)
		TYPES.ITEM_AWARDED.v, UPGRADES.ITEM_AWARDED = old, nil
		if not ok then error(err, 0) end
	end)

	it("an older payload without an upgrade step is kept but not read", function()
		local TYPES = Lg().TYPES
		local old = TYPES.DROP_SEEN.v
		TYPES.DROP_SEEN.v = 3
		local ok, err = pcall(function()
			local L = Lg().New()
			Lg().Merge(L, { { id = "A:1", author = "A", seq = 1, ts = 1, season = S, type = "DROP_SEEN", v = 1, payload = {} } })
			eq(Lg().Stats(L).unreadable, 1)
		end)
		TYPES.DROP_SEEN.v = old
		if not ok then error(err, 0) end
	end)
end)

describe("sync helpers", function()
	it("heads are contiguous high-water marks; gaps list the holes; since gives what a peer lacks", function()
		local A, B = Lg().New(), Lg().New()
		local evs = {}
		for i = 1, 5 do evs[i] = award(A, "Aurel", i, "Bryn", 1) end
		local d1 = award(A, "Dara", 10, "Corin", 1)
		Lg().Merge(B, { evs[1], evs[2], evs[4], d1 })
		deepEq(Lg().Heads(B), { Aurel = 2, Dara = 1 })
		deepEq(Lg().Gaps(B), { Aurel = { 3 } })
		local missing = Lg().Since(A, Lg().Heads(B))
		eq(#missing, 3)   -- 3, 4 and 5: 4 is sent again, the merge ignores it
		eq(missing[1].id, "Aurel:3")
		local r = Lg().Merge(B, missing)
		eq(r.added, 2); eq(r.duplicate, 1)
		deepEq(Lg().Heads(B), { Aurel = 5, Dara = 1 })
		deepEq(Lg().Gaps(B), {})
		deepEq(Lg().Credits(B, S), Lg().Credits(A, S))
	end)

	it("orders events canonically: time, author, sequence", function()
		local L = Lg().New()
		award(L, "Dara", 5, "X", 1)
		award(L, "Aurel", 5, "X", 1)
		award(L, "Aurel", 1, "X", 1)
		local ids = {}
		for i, e in ipairs(Lg().Sorted(L)) do ids[i] = e.id end
		deepEq(ids, { "Aurel:2", "Aurel:1", "Dara:1" })
	end)
end)

describe("snapshots", function()
	it("snapshot + tail equals the full ledger", function()
		local L = Lg().New()
		join(L, "Aurel", 1, "Bryn", 2)
		local a = award(L, "Aurel", 2, "Bryn", 2)
		award(L, "Aurel", 3, "Corin", 1)
		local snap = Lg().TakeSnapshot(L, 100)
		eq(snap.count, 3)
		deepEq(snap.heads, { Aurel = 3 })
		void(L, "Dara", 4, a.id)
		adjust(L, "Dara", 5, "Corin", 0.5)
		deepEq(Lg().Credits(L, S), { Bryn = 2, Corin = 1.5 })
		deepEq(Lg().Credits(L, S), Lg().Credits(L, S, { full = true }))
	end)

	it("keeps the newest snapshots only and survives the SavedVariables round trip", function()
		local L = Lg().New()
		for i = 1, 6 do
			award(L, "Aurel", i, "Bryn", 1)
			Lg().TakeSnapshot(L, i)
		end
		eq(#L.snapshots, Lg().MAX_SNAPSHOTS)
		eq(L.snapshots[#L.snapshots].ts, 6)
		-- A plain copy, as the client writes and reads it back.
		local function clone(t)
			if type(t) ~= "table" then return t end
			local c = {}
			for k, v in pairs(t) do c[k] = clone(v) end
			return c
		end
		local R = Lg().Open(clone(L))
		award(R, "Aurel", 7, "Bryn", 1)
		eq(Lg().Credits(R, S).Bryn, 7)
	end)
end)

describe("first kills", function()
	it("are the oldest date of ENCOUNTER_KILLED and PROGRESS_SET per encounter", function()
		local L = Lg().New()
		local function ev(ts, t, p) assert(Lg().Append(L, { author = "Aurel", ts = ts, season = S, type = t, payload = p })) end
		ev(1, "ENCOUNTER_KILLED", { encounterID = 610, difficulty = 1, time = 1, date = "2026-11-12" })
		ev(2, "ENCOUNTER_KILLED", { encounterID = 610, difficulty = 1, time = 2, date = "2026-11-19" })
		ev(3, "PROGRESS_SET", { encounterID = 611, faction = "Horde", date = "2026-10-01" })
		ev(4, "PROGRESS_SET", { encounterID = 610, faction = "Alliance", date = "2026-01-01" })
		ev(5, "ENCOUNTER_KILLED", { encounterID = 612, difficulty = 1, time = 5 })
		deepEq(Lg().FirstKills(L, "Horde"), { [610] = "2026-11-12", [611] = "2026-10-01" })
		local _, code = Lg().Append(L, { author = "Aurel", ts = 6, season = S, type = "PROGRESS_SET",
			payload = { encounterID = 610, date = "12/11" } })
		eq(code, "payload:date")
	end)
end)

-- An independent model: the credits of a season computed directly from the list of events, without the ledger.
local function model(events)
	local byId, voided, credits, joined = {}, {}, {}, {}
	for _, e in ipairs(events) do byId[e.id] = e end
	for _, e in ipairs(events) do
		if e.type == "AWARD_VOIDED" then voided[e.payload.ref] = true end
	end
	for _, e in ipairs(events) do
		local p = e.payload
		if e.type == "MEMBER_JOINED" then
			local j = joined[p.member]
			if not j or Lg().Before(e, j) then joined[p.member] = e end
		elseif not voided[e.id] then
			if e.type == "ITEM_AWARDED" then
				credits[p.member] = (credits[p.member] or 0) + p.cost
			elseif e.type == "CREDITS_ADJUSTED" then
				credits[p.member] = (credits[p.member] or 0) + p.delta
			end
		end
	end
	for m, j in pairs(joined) do credits[m] = (credits[m] or 0) + (j.payload.initialCredits or 0) end
	for m, n in pairs(credits) do credits[m] = Lg().Round(n) end
	return credits
end

describe("random event sequences", function()
	local AUTHORS = { "Aurel", "Dara", "Esme" }
	local MEMBERS = { "Bryn", "Corin", "Fenna", "Gael" }
	local COSTS = { 0, 0.5, 1, 1.5, 2, 0.1, 0.2 }

	-- Three officers write on their own ledgers and swap events now and then; returns the union of all events.
	local function generate(rand, n)
		local books = { Lg().New(), Lg().New(), Lg().New() }
		local written = {}
		for t = 1, n do
			local i = rand(3)
			local L, author = books[i], AUTHORS[i]
			local roll = rand(10)
			local e
			if roll <= 4 then
				e = award(L, author, t, MEMBERS[rand(4)], COSTS[rand(#COSTS)])
			elseif roll <= 5 then
				e = adjust(L, author, t, MEMBERS[rand(4)], rand(2) == 1 and -1 or 0.5)
			elseif roll <= 6 then
				e = join(L, author, rand(n), MEMBERS[rand(4)], rand(4) - 1)
			elseif roll <= 8 then
				local candidates = Lg().Sorted(L, function(x) return Lg().VOIDABLE[x.type] and not Lg().IsVoided(L, x.id) end)
				if #candidates > 0 then e = assert(void(L, author, t, candidates[rand(#candidates)].id)) end
			else
				Lg().Merge(L, all(books[rand(3)]))   -- a sync with another officer
			end
			if e then written[#written + 1] = e end
		end
		return written
	end

	for seed = 1, 25 do
		it("seed " .. seed .. ": every order, duplicates and snapshots give the model's credits", function()
			local rand = rng(seed * 7919)
			local events = generate(rand, 60)
			local expected = model(events)

			local full = Lg().New()
			eq(Lg().Merge(full, events).added, #events)
			deepEq(Lg().Credits(full, S), expected)

			-- Another officer receives the events shuffled, in batches, with duplicates, snapshotting on the way.
			local B = Lg().New()
			local order = shuffle(events, rand)
			local i = 1
			while i <= #order do
				local batch = {}
				local last = math.min(#order, i + rand(6) - 1)
				for k = i, last do batch[#batch + 1] = order[k] end
				if rand(3) == 1 then batch[#batch + 1] = order[rand(#order)] end
				Lg().Merge(B, batch)
				if rand(4) == 1 then Lg().TakeSnapshot(B, i) end
				deepEq(Lg().Credits(B, S), Lg().Credits(B, S, { full = true }), "snapshot + tail at " .. i)
				i = last + 1
			end
			Lg().Merge(B, events)   -- whatever is still missing
			deepEq(Lg().Credits(B, S), expected)
			deepEq(Lg().Heads(B), Lg().Heads(full))
			deepEq(Lg().Gaps(B), {})

			-- Merging everything again changes nothing.
			local r = Lg().Merge(B, events)
			eq(r.added, 0)
			deepEq(Lg().Credits(B, S), expected)
		end)
	end
end)
