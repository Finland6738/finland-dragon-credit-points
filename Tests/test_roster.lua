-- Roster (M3-2): the season's pool with the players' declarations (MS1 required, MS2, OS, role, class, faction,
-- availability), the lock of the declaration for the season except an officer's correction (ROSTER_CHANGED,
-- roster.manage), mains and alts (an alt never has credits), one main per faction through the twin link, the statuses
-- active / trial / inactive, the requests a player makes and an officer approves, and the import from the guild
-- note. Pure domain code on top of Members and Season.
local function Lg() return FDCP.Ledger end
local function Sn() return FDCP.Season end
local function M() return FDCP.Members end
local function R() return FDCP.Roster end
local function P() return FDCP.Permissions end

local GM, OFFICER, RAIDER = "Aurel-Camelot", "Bryn-Camelot", "Corin-Camelot"
local PACK = { { id = 409, size = 40 } }

-- A small spec table, as Data/Specs.lua will provide (ids are the client's specIDs).
local SPECS = {
	{ id = 71, class = "WARRIOR", name = "Arms", role = "DAMAGER" },
	{ id = 72, class = "WARRIOR", name = "Fury", role = "DAMAGER" },
	{ id = 73, class = "WARRIOR", name = "Protection", role = "TANK" },
	{ id = 65, class = "PALADIN", name = "Holy", role = "HEALER" },
	{ id = 66, class = "PALADIN", name = "Protection", role = "TANK" },
	{ id = 70, class = "PALADIN", name = "Retribution", role = "DAMAGER" },
	{ id = 257, class = "PRIEST", name = "Holy", role = "HEALER" },
	{ id = 256, class = "PRIEST", name = "Discipline", role = "HEALER" },
	{ id = 258, class = "PRIEST", name = "Shadow", role = "DAMAGER" },
	{ id = 62, class = "MAGE", name = "Arcane", role = "DAMAGER" },
	{ id = 64, class = "MAGE", name = "Frost", role = "DAMAGER" },
	{ id = 102, class = "DRUID", name = "Balance", role = "DAMAGER" },
	{ id = 103, class = "DRUID", name = "Feral", role = "DAMAGER" },
	{ id = 104, class = "DRUID", name = "Guardian", role = "TANK" },
	{ id = 105, class = "DRUID", name = "Restoration", role = "HEALER" },
}
local BY_ID = {}
for _, s in ipairs(SPECS) do BY_ID[s.id] = s end

local function withSpecs()
	R().SpecInfo = function(id) return BY_ID[id] end
end

-- Data/Specs.lua plugs the real table in when the addon loads; these tests check the declaration without it.
local function withoutSpecs()
	R().SpecInfo = nil
end

local function ranks()
	local h = P().NewHistory()
	P().RecordRank(h, GM, 0, 0)
	P().RecordRank(h, OFFICER, 1, 0)
	P().RecordRank(h, RAIDER, 3, 0)
	h.loaded = true
	return h
end

local function gate() return P().Gate(ranks()) end

local function newSeason(id)
	local L = Lg().New()
	assert(Sn().Open(L, { author = GM, ts = 1, season = id or "S1", label = "Tier 1", instances = PACK }))
	return L
end

-- Aurel the tank (Horde), Bryn the healer, Corin the mage, all with a class and a role given by hand.
local function decl(extra)
	local d = { class = "WARRIOR", role = "TANK", ms1 = 73 }
	for k, v in pairs(extra or {}) do d[k] = v end
	return d
end

local function join(L, member, ts, extra, config, opts)
	local d = { author = OFFICER, ts = ts, season = "S1", member = member }
	for k, v in pairs(decl(extra)) do d[k] = v end
	if extra and extra.class == false then d.class = nil end
	return R().Join(L, d, config, opts)
end

local function change(L, member, ts, set, clear, author, opts)
	return R().Change(L, { author = author or OFFICER, ts = ts, season = "S1", member = member, set = set,
		clear = clear }, opts)
end

local function award(L, member, cost, ts)
	return assert(Lg().Append(L, { author = OFFICER, ts = ts, season = "S1", type = "ITEM_AWARDED",
		payload = { member = member, item = 19000 + ts, cost = cost, response = "MS" } }))
end

local function night(L, ts)
	return assert(Lg().Append(L, { author = OFFICER, ts = ts, season = "S1", type = "NIGHT_OPENED",
		payload = { date = "2026-11-12", instanceID = 409, size = 40, difficulty = "normal" } }))
end

local function shuffled(list, seed)
	local out, state = {}, seed
	for i, v in ipairs(list) do out[i] = v end
	for i = #out, 2, -1 do
		state = (state * 1103515245 + 12345) % 2147483648
		local j = (math.floor(state / 65536) % i) + 1
		out[i], out[j] = out[j], out[i]
	end
	return out
end

describe("the declaration", function()
	it("is written in the MEMBER_JOINED of the member and read back with the credits of Members", function()
		local L = newSeason()
		local e = assert(join(L, "Aurel", 2, { faction = "Horde", ms2 = 72, os = 71, avail = { "SUN", "TUE", "WED" },
			note = "late on Tuesdays" }))
		eq(e.type, "MEMBER_JOINED")
		eq(e.payload.ms1, 73); eq(e.payload.ms2, 72); eq(e.payload.os, 71)
		eq(e.payload.class, "WARRIOR"); eq(e.payload.role, "TANK"); eq(e.payload.status, "ACTIVE")
		local m = R().Get(L, "S1", "Aurel")
		eq(m.member, "Aurel"); eq(m.faction, "Horde"); eq(m.class, "WARRIOR"); eq(m.role, "TANK")
		eq(m.ms1, 73); eq(m.ms2, 72); eq(m.os, 71); eq(m.status, "ACTIVE")
		deepEq(m.avail, { "TUE", "WED", "SUN" }, "the days come back in week order")
		eq(m.note, "late on Tuesdays")
		truthy(m.declared)
		eq(m.initialCredits, 0)
		eq(M().Get(L, "S1", "Aurel").member, "Aurel", "Members still reads the same event")
		eq(Lg().Credits(L, "S1").Aurel, 0)
	end)

	it("requires the MS1: without it nobody enters the pool through the roster", function()
		local L = newSeason()
		local d = decl(); d.ms1 = nil
		d.author, d.ts, d.season, d.member = OFFICER, 2, "S1", "Aurel"
		local e, code = R().Join(L, d)
		isNil(e); eq(code, "MS1_REQUIRED")
		eq(#R().List(L, "S1"), 0)
	end)

	it("MS1 is the main spec and MS2 the off-spec, and the third (OS) is information only", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2, { ms2 = 72, os = 71 }))
		local m = R().Get(L, "S1", "Aurel")
		-- the loot reads ms1 and ms2 only; os is kept for the roster
		eq(m.ms1, 73); eq(m.ms2, 72); eq(m.os, 71)
		isNil(R().Get(L, "S1", "Corin"))
	end)

	it("without the spec table the class and the role have to be declared", function()
		withoutSpecs()
		local L = newSeason()
		local e, code = join(L, "Aurel", 2, { class = false })
		isNil(e); eq(code, "CLASS_REQUIRED")
		local d = { author = OFFICER, ts = 2, season = "S1", member = "Aurel", class = "WARRIOR", ms1 = 73 }
		e, code = R().Join(L, d)
		isNil(e); eq(code, "ROLE_REQUIRED")
	end)

	it("with the spec table the class and the role come from the MS1, and every spec has to fit", function()
		withSpecs()
		local L = newSeason()
		local e = assert(R().Join(L, { author = OFFICER, ts = 2, season = "S1", member = "Bryn", ms1 = 257, ms2 = 256 }))
		eq(e.payload.class, "PRIEST"); eq(e.payload.role, "HEALER")
		local code
		e, code = R().Join(L, { author = OFFICER, ts = 3, season = "S1", member = "Corin", ms1 = 64, ms2 = 72 })
		isNil(e); eq(code, "SPEC_CLASS", "Fury is not a mage spec")
		e, code = R().Join(L, { author = OFFICER, ts = 3, season = "S1", member = "Corin", ms1 = 9999 })
		isNil(e); eq(code, "SPEC_UNKNOWN")
		e, code = R().Join(L, { author = OFFICER, ts = 3, season = "S1", member = "Corin", ms1 = 64, os = 9999 })
		isNil(e); eq(code, "SPEC_UNKNOWN")
		e, code = R().Join(L, { author = OFFICER, ts = 3, season = "S1", member = "Corin", ms1 = 73, role = "HEALER" })
		isNil(e); eq(code, "ROLE_MISMATCH", "the role is the role of the MS1")
		e, code = R().Join(L, { author = OFFICER, ts = 3, season = "S1", member = "Corin", ms1 = 73, class = "MAGE" })
		isNil(e); eq(code, "SPEC_CLASS")
	end)

	it("refuses the same spec twice and fields that are not valid", function()
		local L = newSeason()
		local e, code = join(L, "Aurel", 2, { ms2 = 73 })
		isNil(e); eq(code, "DUPLICATE_SPEC")
		e, code = join(L, "Aurel", 2, { ms2 = 72, os = 72 })
		isNil(e); eq(code, "DUPLICATE_SPEC")
		e, code = join(L, "Aurel", 2, { class = "DEATHKNIGHT" })
		isNil(e); eq(code, "DECLARATION:class")
		e, code = join(L, "Aurel", 2, { role = "DPS" })
		isNil(e); eq(code, "DECLARATION:role")
		e, code = join(L, "Aurel", 2, { ms1 = 0 })
		isNil(e); eq(code, "DECLARATION:ms1")
		e, code = join(L, "Aurel", 2, { ms2 = 7.5 })
		isNil(e); eq(code, "DECLARATION:ms2")
		e, code = join(L, "Aurel", 2, { status = "BENCHED" })
		isNil(e); eq(code, "DECLARATION:status")
		e, code = join(L, "Aurel", 2, { avail = { "MON", "MON" } })
		isNil(e); eq(code, "DECLARATION:avail")
		e, code = join(L, "Aurel", 2, { avail = { "FUNDAY" } })
		isNil(e); eq(code, "DECLARATION:avail")
		e, code = join(L, "Aurel", 2, { avail = {} })
		isNil(e); eq(code, "DECLARATION:avail")
		e, code = join(L, "Aurel", 2, { note = string.rep("x", 81) })
		isNil(e); eq(code, "DECLARATION:note")
		e, code = join(L, "Aurel", 2, { note = "two\nlines" })
		isNil(e); eq(code, "DECLARATION:note")
		e, code = join(L, "Aurel", 2, { faction = "Naga" })
		isNil(e)
		eq(#R().List(L, "S1"), 0)
		truthy(join(L, "Aurel", 3, { note = string.rep("x", 80) }), "80 characters are fine")
	end)

	it("is refused for a season that does not exist or is closed, and for a second join", function()
		withoutSpecs()
		local L = newSeason()
		local e, code = R().Join(L, { author = OFFICER, ts = 2, season = "S9", member = "Aurel", ms1 = 73, class = "WARRIOR",
			role = "TANK" })
		isNil(e); eq(code, "SEASON_UNKNOWN")
		assert(join(L, "Aurel", 2))
		e, code = join(L, "Aurel", 3, { ms1 = 72 })
		isNil(e); eq(code, "ALREADY_JOINED")
		assert(Sn().Close(L, { author = GM, ts = 4, season = "S1" }))
		e, code = join(L, "Bryn", 5)
		isNil(e); eq(code, "SEASON_CLOSED")
	end)

	it("a member written by Members.Join alone is in the pool but undeclared", function()
		local L = newSeason()
		assert(M().Join(L, { author = OFFICER, ts = 2, season = "S1", member = "Aurel" }))
		local m = R().Get(L, "S1", "Aurel")
		truthy(m); falsy(m.declared); eq(m.status, "ACTIVE"); isNil(m.ms1)
		local c = R().Counts(L, "S1")
		eq(c.total, 1); eq(c.undeclared, 1)
		eq(#R().SitePlayers(L, "S1"), 0, "the site needs class, spec and role")
	end)

	it("the joining credits follow Members: a late joiner gets the floor of the average", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2)); assert(join(L, "Bryn", 3, { class = "PRIEST", role = "HEALER", ms1 = 257 }))
		night(L, 10)
		award(L, "Aurel", 3, 11)
		local e = assert(join(L, "Corin", 20, { class = "MAGE", role = "DAMAGER", ms1 = 64 }))
		eq(e.payload.initialCredits, 1, "floor of (3 + 0) / 2")
		eq(e.payload.rule, "AVERAGE")
		eq(e.payload.ms1, 64)
		eq(Lg().Credits(L, "S1").Corin, 1)
	end)
end)

describe("the declaration is locked for the season", function()
	it("a second declaration changes nothing: the first one counts", function()
		withoutSpecs()
		local L = newSeason()
		assert(join(L, "Aurel", 2))
		local e, code = join(L, "Aurel", 3, { ms1 = 72, ms2 = 71 })
		isNil(e); eq(code, "ALREADY_JOINED")
		eq(R().Get(L, "S1", "Aurel").ms1, 73)
	end)

	it("only an officer's ROSTER_CHANGED moves it: a raider is refused by the gate", function()
		local L = newSeason()
		local g = gate()
		assert(join(L, "Aurel", 2, nil, nil, g))
		local e, code = change(L, "Aurel", 3, { ms1 = 72 }, nil, RAIDER, g)
		isNil(e); eq(code, "RANK_TOO_LOW")
		eq(R().Get(L, "S1", "Aurel").ms1, 73)
		e = assert(change(L, "Aurel", 4, { ms1 = 72 }, nil, OFFICER, g))
		eq(e.type, "ROSTER_CHANGED"); eq(e.payload.member, "Aurel"); eq(e.payload.set.ms1, 72)
		eq(R().Get(L, "S1", "Aurel").ms1, 72)
	end)

	it("a raider cannot declare, change or link directly: every roster event needs roster.manage", function()
		local L = newSeason()
		local g = gate()
		local e, code = join(L, "Corin", 2, nil, nil, g)  -- written by OFFICER: fine
		truthy(e)
		e, code = R().Join(L, { author = RAIDER, ts = 3, season = "S1", member = "Dara", class = "MAGE", role = "DAMAGER",
			ms1 = 64 }, nil, g)
		isNil(e); eq(code, "RANK_TOO_LOW")
		e, code = R().LinkAlt(L, { author = RAIDER, ts = 4, season = "S1", alt = "Corinalt", main = "Corin" }, g)
		isNil(e); eq(code, "RANK_TOO_LOW")
		e, code = R().SetStatus(L, { author = RAIDER, ts = 5, season = "S1", member = "Corin", status = "INACTIVE" }, g)
		isNil(e); eq(code, "RANK_TOO_LOW")
		eq(R().Get(L, "S1", "Corin").status, "ACTIVE")
	end)

	it("a ROSTER_CHANGED of a raider arriving in a merge is refused, an officer's is stored", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2))
		local forged = { id = RAIDER .. ":1", author = RAIDER, seq = 1, ts = 5, season = "S1", type = "ROSTER_CHANGED", v = 1,
			payload = { member = "Aurel", set = { ms1 = 72 } } }
		local real = { id = OFFICER .. ":9", author = OFFICER, seq = 9, ts = 6, season = "S1", type = "ROSTER_CHANGED",
			v = 1, payload = { member = "Aurel", set = { ms2 = 72 } } }
		local report = Lg().Merge(L, { forged, real }, gate())
		eq(report.added, 1); eq(#report.refused, 1); eq(report.refused[1].code, "RANK_TOO_LOW")
		local m = R().Get(L, "S1", "Aurel")
		eq(m.ms1, 73); eq(m.ms2, 72)
	end)

	it("a correction writes only what changes and keeps the rest", function()
		withSpecs()
		local L = newSeason()
		assert(R().Join(L, { author = OFFICER, ts = 2, season = "S1", member = "Aurel", ms1 = 73, ms2 = 72,
			avail = { "MON", "THU" }, note = "ok" }))
		local e = assert(change(L, "Aurel", 3, { ms1 = 73, ms2 = 71, note = "ok" }))
		deepEq(e.payload.set, { ms2 = 71 }, "ms1 and note are the same: not written")
		local m = R().Get(L, "S1", "Aurel")
		eq(m.ms1, 73); eq(m.ms2, 71); deepEq(m.avail, { "MON", "THU" }); eq(m.note, "ok")
		eq(m.changes, 1); eq(m.changedAt, 3)
		local code
		e, code = change(L, "Aurel", 4, { ms2 = 71 })
		isNil(e); eq(code, "UNCHANGED")
		e, code = change(L, "Aurel", 4, { avail = { "THU", "MON" } })
		isNil(e); eq(code, "UNCHANGED", "the same days in another order")
	end)

	it("clears the optional fields, never the MS1", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2, { ms2 = 72, os = 71, avail = { "MON" }, note = "hi" }))
		local e = assert(change(L, "Aurel", 3, nil, { "os", "note", "ms2" }))
		deepEq(e.payload.clear, { "ms2", "note", "os" })
		local m = R().Get(L, "S1", "Aurel")
		isNil(m.ms2); isNil(m.os); isNil(m.note); deepEq(m.avail, { "MON" })
		local code
		e, code = change(L, "Aurel", 4, nil, { "ms1" })
		isNil(e); eq(code, "DECLARATION:ms1")
		e, code = change(L, "Aurel", 4, nil, { "role" })
		isNil(e); eq(code, "DECLARATION:role")
		e, code = change(L, "Aurel", 4, { note = "x" }, { "note" })
		isNil(e); eq(code, "DECLARATION:note", "set and clear of the same field")
		e, code = change(L, "Aurel", 4, nil, { "note" })
		isNil(e); eq(code, "UNCHANGED", "nothing to clear")
	end)

	it("checks the corrected declaration as a whole", function()
		withSpecs()
		local L = newSeason()
		assert(R().Join(L, { author = OFFICER, ts = 2, season = "S1", member = "Aurel", ms1 = 73 }))
		local e, code = change(L, "Aurel", 3, { ms2 = 64 })
		isNil(e); eq(code, "SPEC_CLASS")
		e, code = change(L, "Aurel", 3, { ms2 = 73 })
		isNil(e); eq(code, "DUPLICATE_SPEC")
		e, code = change(L, "Aurel", 3, { foo = 1 })
		isNil(e); eq(code, "DECLARATION:foo")
		-- a new MS1 of another class needs the class too, and takes the role of the new spec
		e, code = change(L, "Aurel", 3, { ms1 = 257 })
		isNil(e); eq(code, "SPEC_CLASS")
		e = assert(change(L, "Aurel", 3, { ms1 = 257, class = "PRIEST" }))
		eq(e.payload.set.role, "HEALER")
		local m = R().Get(L, "S1", "Aurel")
		eq(m.class, "PRIEST"); eq(m.role, "HEALER"); eq(m.ms1, 257)
	end)

	it("only members of the pool can be corrected, and the season has to be open", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2)); assert(join(L, "Bryn", 3, { class = "PRIEST", role = "HEALER", ms1 = 257 }))
		assert(R().LinkAlt(L, { author = OFFICER, ts = 4, season = "S1", alt = "Aurelalt", main = "Aurel" }))
		local e, code = change(L, "Corin", 5, { status = "TRIAL" })
		isNil(e); eq(code, "NOT_MEMBER")
		e, code = change(L, "Aurelalt", 5, { status = "TRIAL" })
		isNil(e); eq(code, "IS_ALT")
		e, code = change(L, "", 5, { status = "TRIAL" })
		isNil(e); eq(code, "member")
		e, code = R().Change(L, { author = OFFICER, ts = 5, season = "S2", member = "Aurel", set = { status = "TRIAL" } })
		isNil(e); eq(code, "SEASON_UNKNOWN")
		assert(Sn().Close(L, { author = GM, ts = 6, season = "S1" }))
		e, code = change(L, "Aurel", 7, { status = "TRIAL" })
		isNil(e); eq(code, "SEASON_CLOSED")
		isNil(R().Change(L, nil))
	end)

	it("a ROSTER_CHANGED of a name outside the pool, or a malformed one, is ignored and never read", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2))
		for _, p in ipairs({
			{ member = "Aurel" },                                        -- nothing to change
			{ member = "Aurel", set = {} },
			{ member = "Aurel", set = { faction = "Horde" } },           -- not a correctable field
			{ member = "Aurel", set = { ms1 = -3 } },
			{ member = "Aurel", clear = { "ms1" } },
			{ member = "Aurel", set = { note = "a" }, clear = { "note" } },
			{ member = "Aurel", set = { status = "BENCH" } },
			{ member = "Aurel", set = { status = "TRIAL" }, reason = "not a code" },
			{ set = { status = "TRIAL" } },
		}) do
			local ok, code = Lg().Check({ id = OFFICER .. ":1", author = OFFICER, seq = 1, ts = 5, season = "S1",
				type = "ROSTER_CHANGED", v = 1, payload = p })
			falsy(ok, code)
		end
		assert(Lg().Check({ id = OFFICER .. ":1", author = OFFICER, seq = 1, ts = 5, season = "S1",
			type = "ROSTER_CHANGED", v = 1, payload = { member = "Aurel", set = { status = "TRIAL" }, reason = "TRIAL_ENDED" } }))
		-- a valid change for somebody who never joined does nothing
		local report = Lg().Merge(L, { { id = OFFICER .. ":50", author = OFFICER, seq = 50, ts = 5, season = "S1",
			type = "ROSTER_CHANGED", v = 1, payload = { member = "Ghost", set = { status = "TRIAL" } } } })
		eq(report.added, 1)
		isNil(R().Get(L, "S1", "Ghost"))
		eq(R().Get(L, "S1", "Aurel").changes, 0)
	end)

	it("the ledger checks the declaration in a MEMBER_JOINED that arrives from another client", function()
		local bad = { id = OFFICER .. ":1", author = OFFICER, seq = 1, ts = 2, season = "S1", type = "MEMBER_JOINED", v = 1,
			payload = { member = "Aurel", initialCredits = 0, ms1 = "fury" } }
		local ok, code = Lg().Check(bad)
		falsy(ok); eq(code, "payload:ms1")
		bad.payload = { member = "Aurel", initialCredits = 0, class = "WARRIOR", role = "TANK", ms1 = 73, status = "TRIAL" }
		truthy(Lg().Check(bad))
		bad.payload.status = "SOMETIMES"
		ok, code = Lg().Check(bad)
		falsy(ok); eq(code, "payload:status")
	end)
end)

describe("status: active, trial, inactive", function()
	it("the officer moves a member between the three, with a reason code", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2, { status = "TRIAL" }))
		eq(R().Get(L, "S1", "Aurel").status, "TRIAL")
		local e = assert(R().SetStatus(L, { author = OFFICER, ts = 3, season = "S1", member = "Aurel", status = "ACTIVE",
			reason = "TRIAL_ENDED" }))
		eq(e.payload.reason, "TRIAL_ENDED")
		eq(R().Get(L, "S1", "Aurel").status, "ACTIVE")
		assert(R().SetStatus(L, { author = OFFICER, ts = 4, season = "S1", member = "Aurel", status = "INACTIVE" }))
		eq(R().Get(L, "S1", "Aurel").status, "INACTIVE")
		local x, code = R().SetStatus(L, { author = OFFICER, ts = 5, season = "S1", member = "Aurel", status = "INACTIVE" })
		isNil(x); eq(code, "UNCHANGED")
		x, code = R().SetStatus(L, { author = OFFICER, ts = 5, season = "S1", member = "Aurel", status = "GONE" })
		isNil(x); eq(code, "DECLARATION:status")
	end)

	it("an inactive member keeps the credits and is not counted or exported", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2, { faction = "Horde" }))
		assert(join(L, "Bryn", 3, { faction = "Horde", class = "PRIEST", role = "HEALER", ms1 = 257, status = "TRIAL" }))
		assert(join(L, "Corin", 4, { faction = "Horde", class = "MAGE", role = "DAMAGER", ms1 = 64 }))
		night(L, 10)
		award(L, "Corin", 2, 11)
		assert(R().SetStatus(L, { author = OFFICER, ts = 12, season = "S1", member = "Corin", status = "INACTIVE" }))
		local c = R().Counts(L, "S1")
		eq(c.total, 2); eq(c.trial, 1); eq(c.TANK, 1); eq(c.HEALER, 1); eq(c.DAMAGER, 0)
		eq(Lg().Credits(L, "S1").Corin, 2)
		local site = R().SitePlayers(L, "S1")
		eq(#site, 2)
		eq(site[1].member, "Bryn"); eq(site[1].rank, "Trial")
		eq(site[2].member, "Aurel"); eq(site[2].rank, "Raider")
		eq(#R().List(L, "S1"), 3)
		eq(#R().List(L, "S1", { status = "INACTIVE" }), 1)
		eq(#R().List(L, "S1", { playing = true }), 2)
	end)

	it("lists by class then name and filters by faction, role and class", function()
		local L = newSeason()
		assert(join(L, "Zed", 2, { faction = "Horde" }))
		assert(join(L, "Aurel", 3, { faction = "Horde" }))
		assert(join(L, "Bryn", 4, { faction = "Alliance", class = "PRIEST", role = "HEALER", ms1 = 257 }))
		local names = {}
		for _, m in ipairs(R().List(L, "S1")) do names[#names + 1] = m.member end
		deepEq(names, { "Bryn", "Aurel", "Zed" }, "PRIEST before WARRIOR")
		eq(#R().List(L, "S1", { faction = "Alliance" }), 1)
		eq(#R().List(L, "S1", { role = "TANK" }), 2)
		eq(#R().List(L, "S1", { class = "PRIEST" }), 1)
		eq(R().Counts(L, "S1", "Horde").total, 2)
		eq(R().Counts(L, "S1", "Alliance").HEALER, 1)
	end)
end)

describe("mains and alts", function()
	it("an alt is linked to a main and never gets credits of its own", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2, { faction = "Horde" }))
		assert(R().LinkAlt(L, { author = OFFICER, ts = 3, season = "S1", alt = "Aurelalt", main = "Aurel", faction = "Horde" }))
		night(L, 10)
		-- the award of an item won with the alt goes to the main (Members.Resolve): the ledger never sees the alt
		local holder, credits, viaAlt = R().CreditHolder(L, "S1", "Aurelalt")
		eq(holder, "Aurel"); eq(credits, 0); truthy(viaAlt)
		award(L, holder, 2, 11)
		holder, credits, viaAlt = R().CreditHolder(L, "S1", "Aurelalt")
		eq(holder, "Aurel"); eq(credits, 2); truthy(viaAlt)
		holder, credits, viaAlt = R().CreditHolder(L, "S1", "Aurel")
		eq(holder, "Aurel"); eq(credits, 2); falsy(viaAlt)
		isNil(Lg().Credits(L, "S1").Aurelalt)
		local list = R().List(L, "S1")
		eq(#list, 1, "the pool lists mains only")
		deepEq(list[1].alts, { "Aurelalt" })
		eq(#M().Roster(L, "S1"), 1)
		local none, why = R().CreditHolder(L, "S1", "Stranger")
		isNil(none); eq(why, "NOT_MEMBER")
	end)

	it("an alt cannot join the pool as a main, and a main cannot become an alt", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2)); assert(join(L, "Bryn", 3, { class = "PRIEST", role = "HEALER", ms1 = 257 }))
		assert(R().LinkAlt(L, { author = OFFICER, ts = 4, season = "S1", alt = "Aurelalt", main = "Aurel" }))
		local e, code = join(L, "Aurelalt", 5)
		isNil(e); eq(code, "IS_ALT")
		e, code = R().LinkAlt(L, { author = OFFICER, ts = 5, season = "S1", alt = "Bryn", main = "Aurel" })
		isNil(e); eq(code, "ALT_IS_MAIN")
		e, code = R().LinkAlt(L, { author = OFFICER, ts = 5, season = "S1", alt = "Aurelalt", main = "Bryn" })
		isNil(e); eq(code, "ALREADY_LINKED")
		e, code = R().LinkAlt(L, { author = OFFICER, ts = 5, season = "S1", alt = "Newalt", main = "Nobody" })
		isNil(e); eq(code, "MAIN_UNKNOWN")
	end)

	it("with several mains the credit table stays one line per main", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2, { faction = "Horde" }))
		assert(join(L, "Bryn", 3, { faction = "Horde", class = "PRIEST", role = "HEALER", ms1 = 257 }))
		assert(R().LinkAlt(L, { author = OFFICER, ts = 4, season = "S1", alt = "Aurelalt", main = "Aurel" }))
		assert(R().LinkAlt(L, { author = OFFICER, ts = 5, season = "S1", alt = "Brynalt", main = "Bryn" }))
		night(L, 10)
		award(L, "Aurel", 2, 11); award(L, "Bryn", 1, 12)
		local rows = M().Roster(L, "S1")
		eq(#rows, 2); eq(rows[1].member, "Bryn"); eq(rows[1].credits, 1); eq(rows[2].credits, 2)
	end)
end)

describe("one main per faction, two for a player on both factions", function()
	local function twoFactions()
		local L = newSeason()
		assert(join(L, "Aurel", 2, { faction = "Horde" }))
		return L
	end

	it("a main of the other faction is linked to the first as the same player, with separate credits", function()
		local L = twoFactions()
		assert(join(L, "Aurela", 3, { faction = "Alliance", twin = "Aurel" }))
		eq(R().Get(L, "S1", "Aurela").twin, "Aurel")
		eq(R().Get(L, "S1", "Aurel").twin, "Aurela", "the link works both ways")
		night(L, 10)
		award(L, "Aurel", 2, 11)
		local credits = Lg().Credits(L, "S1")
		eq(credits.Aurel, 2); eq(credits.Aurela, 0)
		eq(#R().List(L, "S1", { faction = "Horde" }), 1)
		eq(#R().List(L, "S1", { faction = "Alliance" }), 1)
	end)

	it("refuses a second main in the same faction for the same player", function()
		local L = twoFactions()
		local e, code = join(L, "Aurelb", 3, { faction = "Horde", twin = "Aurel" })
		isNil(e); eq(code, "TWIN_FACTION")
		assert(join(L, "Aurela", 4, { faction = "Alliance", twin = "Aurel" }))
		e, code = join(L, "Aurelc", 5, { faction = "Alliance", twin = "Aurel" })
		isNil(e); eq(code, "TWIN_TAKEN", "Aurel already has an Alliance twin")
	end)

	it("needs the faction of both and a main that is in the pool", function()
		local L = twoFactions()
		local e, code = join(L, "Aurela", 3, { twin = "Aurel" })
		isNil(e); eq(code, "FACTION_REQUIRED")
		e, code = join(L, "Aurela", 3, { faction = "Alliance", twin = "Nobody" })
		isNil(e); eq(code, "TWIN_UNKNOWN")
		e, code = join(L, "Aurela", 3, { faction = "Alliance", twin = "Aurela" })
		isNil(e); eq(code, "TWIN_SELF")
		-- a main with no faction cannot be anybody's twin
		assert(join(L, "Nofaction", 4))
		e, code = join(L, "Aurela", 5, { faction = "Alliance", twin = "Nofaction" })
		isNil(e); eq(code, "FACTION_REQUIRED")
	end)

	it("an officer can set or clear the link later", function()
		local L = twoFactions()
		assert(join(L, "Aurela", 3, { faction = "Alliance" }))
		isNil(R().Get(L, "S1", "Aurela").twin)
		assert(change(L, "Aurela", 4, { twin = "Aurel" }))
		eq(R().Get(L, "S1", "Aurel").twin, "Aurela")
		local e, code = change(L, "Aurela", 5, { twin = "Aurela" })
		isNil(e); eq(code, "TWIN_SELF")
		assert(change(L, "Aurela", 6, nil, { "twin" }))
		isNil(R().Get(L, "S1", "Aurela").twin); isNil(R().Get(L, "S1", "Aurel").twin)
	end)

	it("after a merge the earlier pair wins and two mains never claim the same player", function()
		local L = twoFactions()
		-- two Alliance mains of two different clients both claim Aurel: the one that joined first holds it
		local function joined(author, seq, ts, name, twin)
			return { id = author .. ":" .. seq, author = author, seq = seq, ts = ts, season = "S1", type = "MEMBER_JOINED",
				v = 1, payload = { member = name, faction = "Alliance", initialCredits = 0, class = "MAGE", role = "DAMAGER",
					ms1 = 64, twin = twin } }
		end
		Lg().Merge(L, { joined("Zed-Camelot", 1, 6, "Late", "Aurel"), joined("Yan-Camelot", 1, 5, "Early", "Aurel") })
		eq(R().Get(L, "S1", "Aurel").twin, "Early")
		eq(R().Get(L, "S1", "Early").twin, "Aurel")
		isNil(R().Get(L, "S1", "Late").twin)
	end)
end)

describe("requests: the player asks, an officer approves", function()
	local function req(extra)
		local r = { from = "Aurel-Camelot", ts = 5, season = "S1", member = "Dara", faction = "Horde" }
		for k, v in pairs(decl({ class = "MAGE", role = "DAMAGER", ms1 = 64 })) do r[k] = v end
		for k, v in pairs(extra or {}) do r[k] = v end
		return r
	end

	it("a join request changes nothing in the ledger until an officer approves it", function()
		local L = newSeason()
		local requests = R().NewRequests()
		local before = Lg().Count(L)
		local r = assert(R().RequestJoin(requests, L, req()))
		eq(r.kind, "JOIN"); eq(r.state, "PENDING"); eq(r.member, "Dara"); eq(r.ms1, 64)
		eq(Lg().Count(L), before)
		isNil(R().Get(L, "S1", "Dara"))
		eq(#R().Pending(requests, "S1"), 1)
		local e = assert(R().Approve(requests, L, r.id, { author = OFFICER, ts = 6 }, nil, gate()))
		eq(e.type, "MEMBER_JOINED"); eq(e.author, OFFICER)
		local m = R().Get(L, "S1", "Dara")
		eq(m.ms1, 64); eq(m.class, "MAGE"); eq(m.faction, "Horde"); truthy(m.declared)
		eq(requests.items[r.id].state, "APPROVED"); eq(requests.items[r.id].event, e.id)
		eq(#R().Pending(requests), 0)
		local x, code = R().Approve(requests, L, r.id, { author = OFFICER, ts = 7 })
		isNil(x); eq(code, "REQUEST_CLOSED")
	end)

	it("a raider cannot approve: the gate refuses and the request stays pending", function()
		local L = newSeason()
		local requests = R().NewRequests()
		local r = assert(R().RequestJoin(requests, L, req()))
		local e, code = R().Approve(requests, L, r.id, { author = RAIDER, ts = 6 }, nil, gate())
		isNil(e); eq(code, "RANK_TOO_LOW")
		eq(requests.items[r.id].state, "PENDING")
		isNil(R().Get(L, "S1", "Dara"))
		assert(R().Approve(requests, L, r.id, { author = OFFICER, ts = 7 }, nil, gate()))
	end)

	it("an officer rejects a request", function()
		local L = newSeason()
		local requests = R().NewRequests()
		local r = assert(R().RequestJoin(requests, L, req()))
		truthy(R().Reject(requests, r.id, OFFICER, 6))
		eq(requests.items[r.id].state, "REJECTED"); eq(requests.items[r.id].by, OFFICER)
		local x, code = R().Reject(requests, r.id, OFFICER, 7)
		isNil(x); eq(code, "REQUEST_CLOSED")
		x, code = R().Reject(requests, "nope", OFFICER, 7)
		isNil(x); eq(code, "REQUEST_UNKNOWN")
		x, code = R().Approve(requests, L, "nope", { author = OFFICER, ts = 7 })
		isNil(x); eq(code, "REQUEST_UNKNOWN")
		isNil(R().Get(L, "S1", "Dara"))
	end)

	it("validates the request like the join: the MS1, the declaration, the season and the pool", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2))
		local requests = R().NewRequests()
		local x, code = R().RequestJoin(requests, L, req({ ms1 = false }))
		isNil(x)
		local r2 = req(); r2.ms1 = nil
		x, code = R().RequestJoin(requests, L, r2)
		isNil(x); eq(code, "MS1_REQUIRED")
		x, code = R().RequestJoin(requests, L, req({ member = "Aurel" }))
		isNil(x); eq(code, "ALREADY_JOINED")
		x, code = R().RequestJoin(requests, L, req({ season = "S9" }))
		isNil(x); eq(code, "SEASON_UNKNOWN")
		x, code = R().RequestJoin(requests, L, req({ from = "" }))
		isNil(x); eq(code, "from")
		x, code = R().RequestJoin(requests, L, req({ faction = "Naga" }))
		isNil(x); eq(code, "faction")
		x, code = R().RequestJoin(requests, L, req({ ms2 = 64 }))
		isNil(x); eq(code, "DUPLICATE_SPEC")
		isNil(R().RequestJoin(requests, L, nil))
		eq(#R().Pending(requests), 0)
	end)

	it("a player's second request replaces his own, another player's is refused while one is waiting", function()
		local L = newSeason()
		local requests = R().NewRequests()
		local a = assert(R().RequestJoin(requests, L, req({ ms1 = 64 })))
		local b = assert(R().RequestJoin(requests, L, req({ ms1 = 62, ts = 6 })))
		ne(a.id, b.id)
		eq(#R().Pending(requests), 1); eq(R().Pending(requests)[1].ms1, 62)
		local x, code = R().RequestJoin(requests, L, req({ from = "Bryn-Camelot", ms1 = 64 }))
		isNil(x); eq(code, "REQUEST_PENDING")
	end)

	it("a request received from the transport is stored once, with the id it came with", function()
		local L = newSeason()
		local requests = R().NewRequests()
		local incoming = req(); incoming.kind = "JOIN"; incoming.id = "Dara-Camelot#7"
		local r = assert(R().Receive(requests, L, incoming))
		eq(r.id, "Dara-Camelot#7")
		local x, code = R().Receive(requests, L, incoming)
		isNil(x); eq(code, "DUPLICATE")
		incoming.kind = "SWAP"
		x, code = R().Receive(requests, L, incoming)
		isNil(x); eq(code, "kind")
	end)

	it("an alt is declared by the player and linked when an officer approves", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2, { faction = "Horde" }))
		local requests = R().NewRequests()
		local r = assert(R().RequestAlt(requests, L, { from = "Aurelalt-Camelot", ts = 5, season = "S1", alt = "Aurelalt",
			main = "Aurel" }))
		eq(r.kind, "ALT")
		eq(M().Resolve(L, "S1", "Aurelalt"), nil, "not linked yet")
		local e = assert(R().Approve(requests, L, r.id, { author = OFFICER, ts = 6 }, nil, gate()))
		eq(e.type, "MEMBER_LINKED_ALT")
		eq(M().Resolve(L, "S1", "Aurelalt"), "Aurel")
		local holder = R().CreditHolder(L, "S1", "Aurelalt")
		eq(holder, "Aurel")
	end)

	it("validates an alt request: the main in the pool, the alt free, the faction", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2, { faction = "Horde" })); assert(join(L, "Bryn", 3))
		local requests = R().NewRequests()
		local function alt(extra)
			local r = { from = "Dara-Camelot", ts = 5, season = "S1", alt = "Dara", main = "Aurel" }
			for k, v in pairs(extra or {}) do r[k] = v end
			return R().RequestAlt(requests, L, r)
		end
		local x, code = alt({ main = "Nobody" }); isNil(x); eq(code, "MAIN_UNKNOWN")
		x, code = alt({ alt = "Bryn" }); isNil(x); eq(code, "ALT_IS_MAIN")
		x, code = alt({ alt = "Aurel", main = "Bryn" }); isNil(x); eq(code, "ALT_IS_MAIN")
		x, code = alt({ alt = "Aurel", main = "Aurel" }); isNil(x); eq(code, "alt")
		x, code = alt({ faction = "Alliance" }); isNil(x); eq(code, "FACTION_MISMATCH")
		assert(alt({ faction = "Horde" }))
		assert(R().Approve(requests, L, R().Pending(requests)[1].id, { author = OFFICER, ts = 6 }))
		x, code = alt({ main = "Bryn" }); isNil(x); eq(code, "ALREADY_LINKED")
	end)

	it("an approval that cannot be written leaves the request for the officer to reject", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2, { faction = "Horde" }))
		local requests = R().NewRequests()
		local r = assert(R().RequestAlt(requests, L, { from = "Dara-Camelot", ts = 5, season = "S1", alt = "Dara", main = "Aurel" }))
		-- meanwhile somebody joins as a main with that name
		assert(join(L, "Dara", 6))
		local e, code = R().Approve(requests, L, r.id, { author = OFFICER, ts = 7 })
		isNil(e); eq(code, "ALT_IS_MAIN")
		eq(requests.items[r.id].state, "PENDING")
		assert(Sn().Close(L, { author = GM, ts = 8, season = "S1" }))
		e, code = R().Approve(requests, L, r.id, { author = OFFICER, ts = 9 })
		isNil(e); eq(code, "SEASON_CLOSED")
	end)

	it("limits the pending requests and prunes the old and the stale ones", function()
		local L = newSeason()
		local requests = R().NewRequests()
		local saved = R().MAX_REQUESTS
		R().MAX_REQUESTS = 2
		assert(R().RequestJoin(requests, L, req({ member = "P1" })))
		local last = assert(R().RequestJoin(requests, L, req({ member = "P2" })))
		local x, code = R().RequestJoin(requests, L, req({ member = "P3" }))
		R().MAX_REQUESTS = saved
		isNil(x); eq(code, "REQUEST_LIMIT")
		truthy(R().Reject(requests, last.id, OFFICER, 10))
		eq(R().Prune(requests, L, 5), 0, "decided after the cut-off: kept")
		eq(R().Prune(requests, L, 11), 1, "decided before it: dropped")
		eq(#R().Pending(requests), 1)
		assert(Sn().Close(L, { author = GM, ts = 20, season = "S1" }))
		eq(R().Prune(requests, L, 0), 1, "a pending request of a closed season goes too")
	end)

	it("keeps the requests in plain data, so the service can save them", function()
		local L = newSeason()
		local requests = R().NewRequests()
		assert(R().RequestJoin(requests, L, req({ avail = { "SAT", "MON" } })))
		local function plain(v)
			if type(v) == "table" then
				for k, x in pairs(v) do
					if not plain(x) or (type(k) ~= "string" and type(k) ~= "number") then return false end
				end
				return true
			end
			return type(v) == "string" or type(v) == "number" or type(v) == "boolean"
		end
		truthy(plain(requests))
		deepEq(R().Pending(requests)[1].avail, { "MON", "SAT" })
	end)
end)

describe("the pool converges after a merge", function()
	it("any order of the same events gives the same pool and the same declarations", function()
		local src = newSeason()
		assert(join(src, "Aurel", 2, { faction = "Horde", ms2 = 72 }))
		assert(join(src, "Bryn", 3, { faction = "Horde", class = "PRIEST", role = "HEALER", ms1 = 257 }))
		assert(R().LinkAlt(src, { author = OFFICER, ts = 4, season = "S1", alt = "Aurelalt", main = "Aurel" }))
		assert(change(src, "Aurel", 5, { ms2 = 71 }))
		assert(change(src, "Bryn", 6, { status = "TRIAL" }))
		assert(change(src, "Aurel", 7, nil, { "ms2" }))
		local events = {}
		for _, e in pairs(src.events) do events[#events + 1] = e end
		local expected = R().State(src, "S1")
		for seed = 1, 8 do
			local L = Lg().New()
			Lg().Merge(L, shuffled(events, seed))
			local got = R().State(L, "S1")
			deepEq(got, expected, "seed " .. seed)
		end
		isNil(expected.members.Aurel.ms2); eq(expected.members.Bryn.status, "TRIAL")
		eq(expected.alts.Aurelalt, "Aurel")
	end)

	it("the first MEMBER_JOINED of a member counts, so a second client's declaration cannot overwrite it", function()
		local L = newSeason()
		local function joined(author, seq, ts, ms1)
			return { id = author .. ":" .. seq, author = author, seq = seq, ts = ts, season = "S1", type = "MEMBER_JOINED",
				v = 1, payload = { member = "Aurel", initialCredits = 0, class = "WARRIOR", role = "TANK", ms1 = ms1 } }
		end
		Lg().Merge(L, { joined(GM, 1, 9, 72), joined(OFFICER, 1, 3, 73) })
		eq(R().Get(L, "S1", "Aurel").ms1, 73)
	end)

	it("credits and snapshots are unaffected by declarations and corrections", function()
		local L = newSeason()
		assert(join(L, "Aurel", 2, { ms2 = 72 })); assert(join(L, "Bryn", 3, { class = "PRIEST", role = "HEALER", ms1 = 257 }))
		night(L, 10)
		award(L, "Aurel", 2, 11)
		Lg().TakeSnapshot(L, 12)
		assert(change(L, "Aurel", 13, { ms2 = 71 }))
		assert(R().SetStatus(L, { author = OFFICER, ts = 14, season = "S1", member = "Bryn", status = "INACTIVE" }))
		deepEq(Lg().Credits(L, "S1"), { Aurel = 2, Bryn = 0 })
		deepEq(Lg().Credits(L, "S1", { full = true }), { Aurel = 2, Bryn = 0 })
	end)
end)

describe("import from the guild note", function()
	it("reads the specs in order as MS1, MS2 and OS, with the class from the guild roster", function()
		local s = R().ParseNote("Fury / Arms / Protection", SPECS, { class = "WARRIOR" })
		eq(s.class, "WARRIOR"); eq(s.ms1, 72); eq(s.ms2, 71); eq(s.os, 73); eq(s.role, "DAMAGER")
		deepEq(s.ambiguous, {})
	end)

	it("resolves a name shared by two classes with the class, and lists it as ambiguous without one", function()
		local s = R().ParseNote("Holy, Shadow", SPECS, { class = "PRIEST" })
		eq(s.ms1, 257); eq(s.ms2, 258); eq(s.role, "HEALER")
		s = R().ParseNote("Holy paladin / Retribution", SPECS)
		eq(s.class, "PALADIN"); eq(s.ms1, 65); eq(s.ms2, 70)
		s = R().ParseNote("Holy", SPECS)
		isNil(s.ms1); isNil(s.class); deepEq(s.ambiguous, { "holy" })
		s = R().ParseNote("Frost", SPECS)
		eq(s.ms1, 64); eq(s.class, "MAGE", "a spec of one class only gives the class")
	end)

	it("understands role and status words, in English and Italian", function()
		local s = R().ParseNote("Protection warrior TRIAL", SPECS)
		eq(s.ms1, 73); eq(s.status, "TRIAL"); eq(s.role, "TANK")
		s = R().ParseNote("druid heal restoration, feral (prova)", SPECS)
		eq(s.class, "DRUID"); eq(s.ms1, 105); eq(s.ms2, 103); eq(s.role, "HEALER"); eq(s.status, "TRIAL")
		s = R().ParseNote("Balance inattivo", SPECS)
		eq(s.status, "INACTIVE")
		s = R().ParseNote("feral tank", SPECS, { class = "DRUID" })
		eq(s.role, "TANK", "the note's role word beats the spec's role")
	end)

	it("ignores the other classes' specs, a repeated spec and notes that say nothing", function()
		local s = R().ParseNote("Fury Fury Frost", SPECS, { class = "WARRIOR" })
		eq(s.ms1, 72); isNil(s.ms2)
		s = R().ParseNote("raids on tuesday, gm alt", SPECS)
		isNil(s.ms1); isNil(s.class); isNil(s.status)
		s = R().ParseNote("", SPECS); isNil(s.ms1)
		s = R().ParseNote(nil, SPECS); isNil(s.ms1)
		s = R().ParseNote("Fury", nil); isNil(s.ms1)
	end)

	it("matches multi-word names and does not read half a word", function()
		local specs = { { id = 253, class = "HUNTER", name = "Beast Mastery", role = "DAMAGER" },
			{ id = 254, class = "HUNTER", name = "Mastery", role = "DAMAGER" },
			{ id = 255, class = "HUNTER", name = "Survival", role = "DAMAGER" } }
		local s = R().ParseNote("hunter beast mastery then survival", specs)
		eq(s.ms1, 253); eq(s.ms2, 255)
		s = R().ParseNote("survivalist", specs)
		isNil(s.ms1)
	end)

	it("is only a suggestion: joining with it still goes through the officer and the checks", function()
		withSpecs()
		local L = newSeason()
		local s = R().ParseNote("Holy / Discipline trial", SPECS, { class = "PRIEST" })
		local d = { author = OFFICER, ts = 2, season = "S1", member = "Bryn", faction = "Alliance" }
		for k, v in pairs(s) do if k ~= "ambiguous" then d[k] = v end end
		local e = assert(R().Join(L, d))
		eq(e.payload.ms1, 257); eq(e.payload.ms2, 256); eq(e.payload.status, "TRIAL"); eq(e.payload.role, "HEALER")
	end)
end)
