-- Seasons, members and late joiners (M2-4): open/close, the pack of instances 10/20/40 with one credit table for
-- Normal and Veteran, startCredits, mains and alts (one main per faction), and late joiners written as
-- MEMBER_JOINED{initialCredits} so the value stays stable. Pure domain code.
local function Lg() return FDCP.Ledger end
local function Sn() return FDCP.Season end
local function M() return FDCP.Members end

local OFFICER = "Aurel-Camelot"
local PACK = { { id = 409, size = 40 }, { id = 249, size = 20 }, { id = 309, size = 10 } }

local function open(L, id, ts, extra)
	local d = { author = OFFICER, ts = ts or 1, season = id or "S1", label = "Tier 1", instances = PACK }
	for k, v in pairs(extra or {}) do d[k] = v end
	return Sn().Open(L, d)
end

local function join(L, member, ts, extra, config)
	local d = { author = OFFICER, ts = ts, season = "S1", member = member }
	for k, v in pairs(extra or {}) do d[k] = v end
	return M().Join(L, d, config)
end

local function award(L, member, cost, ts)
	return assert(Lg().Append(L, { author = OFFICER, ts = ts, season = "S1", type = "ITEM_AWARDED",
		payload = { member = member, item = 19000 + ts, cost = cost, response = "MS" } }))
end

local function night(L, ts)
	return assert(Lg().Append(L, { author = OFFICER, ts = ts, season = "S1", type = "NIGHT_OPENED",
		payload = { instanceID = 409, size = 40, difficulty = "normal" } }))
end

local function cfg(lateJoin, mainOnly)
	local c = M().DefaultConfig()
	for k, v in pairs(lateJoin or {}) do c.lateJoin[k] = v end
	if mainOnly ~= nil then c.mainOnly = mainOnly end
	return c
end

-- A season with Aurel 3, Bryn 2, Corin 0 credits after one night (average 5 / 3 = 1.67).
local function seeded()
	local L = Lg().New()
	assert(open(L))
	assert(join(L, "Aurel", 2)); assert(join(L, "Bryn", 3)); assert(join(L, "Corin", 4))
	night(L, 10)
	award(L, "Aurel", 2, 11); award(L, "Aurel", 1, 12); award(L, "Bryn", 2, 13)
	return L
end

describe("seasons", function()
	it("open with the pack of instances and startCredits from the preset", function()
		local L = Lg().New()
		local e = assert(open(L))
		eq(e.type, "SEASON_OPENED"); eq(e.season, "S1")
		local s = Sn().Get(L, "S1")
		eq(s.label, "Tier 1"); eq(s.startCredits, 0); eq(#s.instances, 3)
		truthy(Sn().IsOpen(L, "S1"))
		eq(Sn().Current(L).id, "S1")
		eq(Sn().DefaultConfig().startCredits, 0)
	end)

	it("take startCredits from the draft or the configuration", function()
		local L = Lg().New()
		assert(Sn().Open(L, { author = OFFICER, ts = 1, season = 7, instances = PACK }, { startCredits = 4 }))
		eq(Sn().Get(L, 7).startCredits, 4)
		local L2 = Lg().New()
		assert(open(L2, "S1", 1, { startCredits = 1.5 }))
		eq(Sn().Get(L2, "S1").startCredits, 1.5)
	end)

	it("give one credit table to every instance, size and both difficulties", function()
		local L = Lg().New()
		assert(open(L))
		local s = Sn().Get(L, "S1")
		for _, inst in ipairs(PACK) do
			eq(Sn().InstanceSize(s, inst.id), inst.size)
			eq(Sn().CreditTable(s, inst.id, "normal"), "S1")
			eq(Sn().CreditTable(s, inst.id, "veteran"), "S1")
		end
		local id, code = Sn().CreditTable(s, 999, "normal")
		isNil(id); eq(code, "NOT_IN_PACK")
		id, code = Sn().CreditTable(s, 409, "mythic")
		isNil(id); eq(code, "DIFFICULTY")
	end)

	it("refuse a malformed pack", function()
		local L = Lg().New()
		local cases = {
			{ {}, "payload:instances" },
			{ { { id = 409, size = 25 } }, "payload:instances" },
			{ { { id = 409, size = 40 }, { id = 409, size = 20 } }, "payload:instances" },
			{ { { id = 0, size = 10 } }, "payload:instances" },
		}
		for _, c in ipairs(cases) do
			local e, code = open(L, "S1", 1, { instances = c[1] })
			isNil(e); eq(code, c[2])
		end
		local e, code = open(L, "S1", 1, { startCredits = -1 })
		isNil(e); eq(code, "payload:startCredits")
		eq(Lg().Count(L), 0)
	end)

	it("allow one open season at a time and never reuse an id", function()
		local L = Lg().New()
		assert(open(L, "S1", 1))
		local e, code = open(L, "S2", 2)
		isNil(e); eq(code, "SEASON_ALREADY_OPEN")
		assert(Sn().Close(L, { author = OFFICER, ts = 3, season = "S1" }))
		falsy(Sn().IsOpen(L, "S1"))
		isNil(Sn().Current(L))
		e, code = open(L, "S1", 4)
		isNil(e); eq(code, "SEASON_EXISTS")
		assert(open(L, "S2", 5))
		eq(Sn().Current(L).id, "S2")
		local list = Sn().List(L)
		eq(list[1].id, "S1"); eq(list[2].id, "S2")
		eq(list[1].closedAt, 3)
	end)

	it("close only a known, open season", function()
		local L = Lg().New()
		local e, code = Sn().Close(L, { author = OFFICER, ts = 1, season = "S1" })
		isNil(e); eq(code, "SEASON_UNKNOWN")
		assert(open(L))
		assert(Sn().Close(L, { author = OFFICER, ts = 2, season = "S1" }))
		e, code = Sn().Close(L, { author = OFFICER, ts = 3, season = "S1" })
		isNil(e); eq(code, "SEASON_CLOSED")
	end)

	it("count the first opening and a close merged from another officer, whatever the order", function()
		local A, B = Lg().New(), Lg().New()
		assert(open(A, "S1", 5, { label = "First" }))
		assert(Sn().Open(B, { author = "Dara-Camelot", ts = 6, season = "S1", label = "Second", instances = PACK }))
		local close = assert(Sn().Close(B, { author = "Dara-Camelot", ts = 4, season = "S1" }))   -- clock behind
		Lg().Merge(A, { close })
		Lg().Merge(A, B.events)
		local s = Sn().Get(A, "S1")
		eq(s.label, "First")
		truthy(s.closed)
		isNil(Sn().Current(A))
	end)

	it("count the official nights of the season", function()
		local L = seeded()
		eq(Sn().NightCount(L, "S1"), 1)
		eq(Sn().NightCount(L, "S2"), 0)
	end)
end)

describe("members", function()
	it("join with the season's startCredits before the first night", function()
		local L = Lg().New()
		assert(open(L, "S1", 1, { startCredits = 2 }))
		local e = assert(join(L, "Aurel", 2, { faction = "Horde" }))
		eq(e.payload.initialCredits, 2); eq(e.payload.rule, "START"); isNil(e.payload.basis)
		eq(Lg().Credits(L, "S1").Aurel, 2)
		eq(M().Get(L, "S1", "Aurel").faction, "Horde")
	end)

	it("refuse a second join, an unknown or closed season and a bad faction", function()
		local L = Lg().New()
		local e, code = join(L, "Aurel", 1)
		isNil(e); eq(code, "SEASON_UNKNOWN")
		assert(open(L))
		assert(join(L, "Aurel", 2))
		e, code = join(L, "Aurel", 3)
		isNil(e); eq(code, "ALREADY_JOINED")
		e, code = join(L, "Bryn", 3, { faction = "Scourge" })
		isNil(e); eq(code, "payload:faction")
		e, code = join(L, "", 3)
		isNil(e); eq(code, "member")
		assert(Sn().Close(L, { author = OFFICER, ts = 4, season = "S1" }))
		e, code = join(L, "Corin", 5)
		isNil(e); eq(code, "SEASON_CLOSED")
	end)

	it("link alts to a main: the alt resolves to the main and has no credits of its own", function()
		local L = Lg().New()
		assert(open(L))
		assert(join(L, "Aurel", 2, { faction = "Horde" }))
		assert(M().LinkAlt(L, { author = OFFICER, ts = 3, season = "S1", alt = "Aurelbank", main = "Aurel",
			faction = "Horde" }))
		assert(M().LinkAlt(L, { author = OFFICER, ts = 4, season = "S1", alt = "Aurelalt", main = "Aurel" }))
		eq(M().Resolve(L, "S1", "Aurelbank"), "Aurel")
		eq(M().Resolve(L, "S1", "Aurel"), "Aurel")
		local who, code = M().Resolve(L, "S1", "Nobody")
		isNil(who); eq(code, "NOT_MEMBER")
		deepEq(M().Get(L, "S1", "Aurel").alts, { "Aurelalt", "Aurelbank" })
		local e
		e, code = join(L, "Aurelbank", 5)
		isNil(e); eq(code, "IS_ALT")
		-- Without mainOnly every character counts on its own.
		eq(M().Resolve(L, "S1", "Aurelbank", cfg(nil, false)), "Aurelbank")
	end)

	it("refuse a bad link", function()
		local L = Lg().New()
		assert(open(L))
		assert(join(L, "Aurel", 2, { faction = "Horde" }))
		assert(join(L, "Bryn", 3, { faction = "Horde" }))
		local function link(alt, main, faction)
			return M().LinkAlt(L, { author = OFFICER, ts = 9, season = "S1", alt = alt, main = main, faction = faction })
		end
		local e, code = link("Corinalt", "Corin")
		isNil(e); eq(code, "MAIN_UNKNOWN")
		e, code = link("Bryn", "Aurel")
		isNil(e); eq(code, "ALT_IS_MAIN")
		e, code = link("Aurel", "Aurel")
		isNil(e); eq(code, "alt")
		-- One main per faction: an Alliance character is not an alt of a Horde main, it is a main of its own.
		e, code = link("Aurelally", "Aurel", "Alliance")
		isNil(e); eq(code, "FACTION_MISMATCH")
		assert(join(L, "Aurelally", 10, { faction = "Alliance" }))
		assert(link("Aurelbank", "Aurel"))
		e, code = link("Aurelbank", "Bryn")
		isNil(e); eq(code, "ALREADY_LINKED")
	end)

	it("resolve merged conflicts: first join and first link count, a main is never an alt", function()
		local A, B = Lg().New(), Lg().New()
		assert(open(A))
		Lg().Merge(B, A.events)
		assert(join(A, "Aurel", 5, { faction = "Horde" }))
		assert(M().Join(B, { author = "Dara-Camelot", ts = 4, season = "S1", member = "Aurel", faction = "Horde" }))
		assert(join(A, "Bryn", 6))
		assert(M().Join(B, { author = "Dara-Camelot", ts = 6, season = "S1", member = "Bryn" }))
		assert(M().LinkAlt(A, { author = OFFICER, ts = 8, season = "S1", alt = "Twin", main = "Aurel" }))
		assert(M().LinkAlt(B, { author = "Dara-Camelot", ts = 7, season = "S1", alt = "Twin", main = "Bryn" }))
		-- On B, Corin joins as a main while A had him as Aurel's alt.
		assert(M().LinkAlt(A, { author = OFFICER, ts = 9, season = "S1", alt = "Corin", main = "Aurel" }))
		assert(M().Join(B, { author = "Dara-Camelot", ts = 10, season = "S1", member = "Corin" }))
		Lg().Merge(A, B.events)
		Lg().Merge(B, A.events)
		for _, L in ipairs({ A, B }) do
			local st = M().State(L, "S1")
			eq(st.members.Aurel.joined, "Dara-Camelot:1")
			eq(st.alts.Twin, "Bryn")
			isNil(st.alts.Corin)
			notNil(st.members.Corin)
		end
	end)

	it("list the pool by credits, then name", function()
		local L = seeded()
		local roster = M().Roster(L, "S1")
		eq(roster[1].member, "Corin"); eq(roster[1].credits, 0)
		eq(roster[2].member, "Bryn"); eq(roster[2].credits, 2)
		eq(roster[3].member, "Aurel"); eq(roster[3].credits, 3)
	end)
end)

describe("late joiners", function()
	it("get the floor of the roster average and keep it when the average changes later", function()
		local L = seeded()
		local e = assert(join(L, "Hadri", 20))
		eq(e.payload.initialCredits, 1)          -- floor(5 / 3)
		eq(e.payload.rule, "AVERAGE"); eq(e.payload.basis, 3)
		eq(Lg().Credits(L, "S1").Hadri, 1)
		-- The average moves (Aurel and Corin win more, an award is voided): Hadri's start does not.
		award(L, "Corin", 2, 21)
		local a = award(L, "Aurel", 2, 22)
		assert(Lg().Append(L, { author = OFFICER, ts = 23, season = "S1", type = "AWARD_VOIDED",
			payload = { ref = a.id, reason = "WRONG_WINNER" } }))
		eq(Lg().Credits(L, "S1").Hadri, 1)
		eq(Lg().Credits(L, "S1", { full = true }).Hadri, 1)
		Lg().TakeSnapshot(L, 24)
		award(L, "Bryn", 2, 25)
		eq(Lg().Credits(L, "S1").Hadri, 1)
		eq(M().Get(L, "S1", "Hadri").initialCredits, 1)
		-- A later joiner sees the new average: (3 + 4 + 2 + 1) / 4 = 2.5 -> 2. Hadri now counts in the basis.
		local e2 = assert(join(L, "Ilse", 30))
		eq(e2.payload.initialCredits, 2); eq(e2.payload.basis, 4)
		eq(Lg().Credits(L, "S1").Hadri, 1)
	end)

	it("keep the value after a merge with another officer's ledger", function()
		local L = seeded()
		assert(join(L, "Hadri", 20))
		local other = Lg().New()
		Lg().Merge(other, L.events)
		assert(Lg().Append(other, { author = "Dara-Camelot", ts = 21, season = "S1", type = "ITEM_AWARDED",
			payload = { member = "Corin", item = 1, cost = 2 } }))
		Lg().Merge(L, other.events)
		eq(Lg().Credits(L, "S1").Hadri, 1)
		eq(Lg().Credits(other, "S1").Hadri, 1)
	end)

	it("use every method and rounding of the configuration", function()
		local L = seeded()                              -- credits 3, 2, 0
		local function value(lj)
			return M().LateJoinCredits(L, "S1", cfg(lj), { exclude = "New" })
		end
		eq(value({}), 1)
		eq(value({ rounding = "round" }), 2)
		eq(value({ rounding = "ceil" }), 2)
		eq(value({ decimals = 2 }), 1.66)
		eq(value({ decimals = 2, rounding = "round" }), 1.67)
		local v, rule = value({ method = "median" })
		eq(v, 2); eq(rule, "MEDIAN")
		v, rule = value({ method = "min" })
		eq(v, 0); eq(rule, "MIN")
		v, rule = value({ method = "zero" })
		eq(v, 0); eq(rule, "ZERO")
		v, rule = value({ method = "fixed", fixed = 1.5 })
		eq(v, 1.5); eq(rule, "FIXED")
		award(L, "Corin", 1, 14)                        -- 3, 2, 1: even median with four after a join
		assert(join(L, "Hadri", 15, nil, cfg({ method = "fixed", fixed = 4 })))
		v = M().LateJoinCredits(L, "S1", cfg({ method = "median", decimals = 1 }), {})
		eq(v, 2.5)                                    -- (2 + 3) / 2 over 1, 2, 3, 4
	end)

	it("count only members with at least minNights nights", function()
		local L = seeded()
		local nights = { Aurel = 3, Bryn = 1 }        -- Corin has none
		local v, rule, n = M().LateJoinCredits(L, "S1", cfg(), { nights = nights })
		eq(v, 2); eq(rule, "AVERAGE"); eq(n, 2)       -- floor((3 + 2) / 2)
		v, rule, n = M().LateJoinCredits(L, "S1", cfg({ minNights = 2 }), { nights = nights })
		eq(v, 3); eq(n, 1)
		v, rule, n = M().LateJoinCredits(L, "S1", cfg({ minNights = 0 }), { nights = nights })
		eq(v, 1); eq(n, 3)
		local e = assert(join(L, "Hadri", 20, { nights = nights }))
		eq(e.payload.initialCredits, 2); eq(e.payload.basis, 2)
	end)

	it("fall back to startCredits when the basis is empty", function()
		local L = Lg().New()
		assert(open(L, "S1", 1, { startCredits = 3 }))
		night(L, 2)
		local e = assert(join(L, "Aurel", 3))
		eq(e.payload.initialCredits, 3); eq(e.payload.rule, "EMPTY_BASIS"); eq(e.payload.basis, 0)
		local e2 = assert(join(L, "Bryn", 4, { nights = {} }))
		eq(e2.payload.rule, "EMPTY_BASIS")
	end)

	it("average only the joiner's faction when one is declared", function()
		local L = Lg().New()
		assert(open(L))
		assert(join(L, "Aurel", 2, { faction = "Horde" }))
		assert(join(L, "Bryn", 3, { faction = "Alliance" }))
		assert(join(L, "Corin", 4))                    -- no faction: counts for both
		night(L, 5)
		award(L, "Aurel", 2, 6); award(L, "Aurel", 2, 7); award(L, "Bryn", 1, 8); award(L, "Corin", 2, 9)
		eq(assert(join(L, "Hadri", 10, { faction = "Horde" })).payload.initialCredits, 3)    -- (4 + 2) / 2
		eq(assert(join(L, "Ilse", 11, { faction = "Alliance" })).payload.initialCredits, 1)  -- floor((1 + 2) / 2)
	end)

	it("are late only after the first night, unless forced", function()
		local L = seeded()
		local e = assert(join(L, "Hadri", 20, { late = false }))
		eq(e.payload.rule, "START"); eq(e.payload.initialCredits, 0)
		local L2 = Lg().New()
		assert(open(L2))
		assert(join(L2, "Aurel", 2))
		award(L2, "Aurel", 2, 3)
		local e2 = assert(join(L2, "Bryn", 4, { late = true }))
		eq(e2.payload.rule, "AVERAGE"); eq(e2.payload.initialCredits, 2)
	end)

	it("validate the configuration", function()
		truthy(M().Validate(M().DefaultConfig()))
		local bad = {
			{ { method = "mean" }, "lateJoin.method" },
			{ { rounding = "up" }, "lateJoin.rounding" },
			{ { decimals = 3 }, "lateJoin.decimals" },
			{ { minNights = -1 }, "lateJoin.minNights" },
			{ { fixed = -2 }, "lateJoin.fixed" },
		}
		for _, c in ipairs(bad) do
			local ok, field = M().Validate(cfg(c[1]))
			falsy(ok); eq(field, c[2])
		end
		local L = seeded()
		local e, code = join(L, "Hadri", 20, nil, cfg({ method = "mean" }))
		isNil(e); eq(code, "CONFIG:lateJoin.method")
	end)

	it("round without float noise", function()
		eq(M().Round(0.1 + 0.2, "floor", 1), 0.3)
		eq(M().Round(2.9999999999, "floor", 0), 3)
		eq(M().Round(1.0000000001, "ceil", 0), 1)
		eq(M().Round(1.25, "round", 1), 1.3)
	end)
end)
