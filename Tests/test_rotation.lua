-- Bench rotation (M3-4): the proposal of who sits out (fewest benches, role minimums, the calendar's sign-ups, declared
-- availability), the credit effect of a bench, and a simulated season. Pure domain code on top of Nights and Roster; the
-- calendar adapter and the controller are tested in test_calendar.lua.
local function Lg() return FDCP.Ledger end
local function Sn() return FDCP.Season end
local function N() return FDCP.Nights end
local function R() return FDCP.Roster end
local function Ro() return FDCP.Rotation end
local function Ru() return FDCP.Rules end

local GM, OFFICER = "Aurel-Camelot", "Bryn-Camelot"
local PACK = { { id = 409, size = 40 }, { id = 531, size = 10 } }

-- The real spec table of Data/Specs.lua: 73 Protection Warrior (tank), 257 Holy Priest (healer), 72 Fury Warrior (damage).
local TANK, HEALER, DPS = 73, 257, 72

local function season(size)
	local L = Lg().New()
	assert(Sn().Open(L, { author = GM, ts = 1, season = "S1", label = "Tier 1", instances = PACK }))
	return L
end

-- members = { { "Name", spec, extra }, ... }; extra = { faction?, status?, avail? }
local function pool(L, members)
	for i, m in ipairs(members) do
		local extra = m[3] or {}
		assert(R().Join(L, { author = OFFICER, ts = 1 + i, season = "S1", member = m[1], faction = extra.faction or "Horde",
			ms1 = m[2], status = extra.status, avail = extra.avail }))
	end
end

local function team(prefix, count, spec, extra)
	local list = {}
	for i = 1, count do list[#list + 1] = { prefix .. i, spec, extra } end
	return list
end

local function concat(...)
	local out = {}
	for _, t in ipairs({ ... }) do for _, v in ipairs(t) do out[#out + 1] = v end end
	return out
end

local nightTs = 100
-- Plays a night of the ten-player raid (531): the lineup, one kill, the close. Dates run on from 2026-11-01.
local function play(L, raid, bench, day)
	nightTs = nightTs + 100
	local ts = nightTs
	assert(N().Open(L, { author = OFFICER, ts = ts, season = "S1", date = ("2026-11-%02d"):format(day or 1), instanceID = 531,
		difficulty = "normal", faction = "Horde" }))
	assert(N().SetLineup(L, { author = OFFICER, ts = ts + 1, season = "S1", raid = raid, bench = bench }))
	assert(N().Kill(L, { author = OFFICER, ts = ts + 2, season = "S1", encounterID = 9000 + ts, difficulty = 14 }))
	assert(N().Close(L, { author = OFFICER, ts = ts + 3, season = "S1" }))
end

local function eventCount(L) local n = 0; for _ in pairs(L.events) do n = n + 1 end; return n end
local function has(list, name) for _, v in ipairs(list) do if v == name then return true end end return false end
local function count(list, prefix) local n = 0; for _, v in ipairs(list) do if v:sub(1, #prefix) == prefix then n = n + 1 end end; return n end

describe("the weekday of a night", function()
	it("gives the roster's day code for a calendar date", function()
		eq(Ro().Weekday("2026-11-21"), "SAT")
		eq(Ro().Weekday("2026-11-22"), "SUN")
		eq(Ro().Weekday("2026-11-23"), "MON")
		eq(Ro().Weekday("2026-01-01"), "THU")
		eq(Ro().Weekday("2000-02-29"), "TUE")
		eq(Ro().Weekday("1999-12-31"), "FRI")
		eq(Ro().Weekday("2026-03-01"), "SUN")
	end)

	it("refuses what is not a date", function()
		isNil(Ro().Weekday("tomorrow"))
		isNil(Ro().Weekday("2026-13-01"))
		isNil(Ro().Weekday(nil))
	end)
end)

describe("the proposal of a bench", function()
	it("benches nobody when the places are enough, and says how many stay empty", function()
		local L = season()
		pool(L, concat(team("T", 2, TANK), team("H", 3, HEALER), team("D", 3, DPS)))
		local p = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde" }))
		eq(p.slots, 10); eq(p.candidates, 8); eq(#p.raid, 8); eq(#p.bench, 0); eq(p.short, 2)
		deepEq(p.warnings, {})
	end)

	it("benches exactly the surplus, the ones with the fewest benches first", function()
		local L = season()
		pool(L, team("D", 12, DPS))
		-- D1..D4 sat out before (one bench each), D5..D8 played: the next two benches come from the ones never benched
		play(L, { "D5", "D6", "D7", "D8", "D9", "D10", "D11", "D12", "D1", "D2" }, { "D3", "D4" }, 1)
		local p = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde" }))
		eq(#p.bench, 2)
		eq(#p.raid, 10)
		-- nobody benched twice while others have not been benched once: D3 and D4 are the only ones with a bench
		falsy(has(p.bench, "D3")); falsy(has(p.bench, "D4"))
		eq(p.why[p.bench[1]], "ROTATION")
	end)

	it("among equal benches the one who played the most nights sits out", function()
		local L = season()
		pool(L, team("D", 11, DPS))
		play(L, { "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9", "D10" }, { "D11" }, 1)
		play(L, { "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9", "D11" }, { "D10" }, 2)
		play(L, { "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D10", "D11" }, { "D9" }, 3)
		-- D1..D8 never benched; they played all three nights, D9..D11 played two: so the bench is one of D1..D8, by name
		local p = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde" }))
		deepEq(p.bench, { "D1" })
	end)

	it("is the same on every client: the same ledger gives the same proposal, and nothing is written", function()
		local L = season()
		pool(L, concat(team("T", 3, TANK), team("H", 4, HEALER), team("D", 7, DPS)))
		local before = eventCount(L)
		local a = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde" }))
		local b = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde" }))
		deepEq(a, b)
		eq(eventCount(L), before)
	end)

	it("keeps the minimum of tanks and healers in the raid", function()
		local L = season()
		-- 2 tanks, 3 healers, 7 damage dealers: 12 for 10 places; the alphabetical order would bench H and T first
		pool(L, concat({ { "A1", TANK }, { "A2", TANK } }, { { "A3", HEALER }, { "A4", HEALER }, { "A5", HEALER } }, team("D", 7, DPS)))
		local rules = Ru().DefaultConfig()
		rules.bench.minTanks, rules.bench.minHealers = 2, 3
		local p = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde", rules = rules }))
		eq(#p.bench, 2)
		for _, name in ipairs(p.bench) do eq(name:sub(1, 1), "D", "only damage dealers sit out") end
		deepEq(p.warnings, {})
	end)

	it("lets a minimum go and says so when the places cannot be filled otherwise", function()
		local L = season()
		-- 2 tanks, 2 healers, 8 damage dealers... 12 for 10, but the minimums (2 + 4) leave only 6 damage dealers' worth of room
		pool(L, concat({ { "A1", TANK }, { "A2", TANK } }, { { "A3", HEALER }, { "A4", HEALER } }, team("D", 1, DPS), team("E", 7, DPS)))
		local rules = Ru().DefaultConfig()
		rules.bench.minTanks, rules.bench.minHealers = 2, 4
		-- the healers number 2 only: the minimum is capped by who exists, so nobody is protected beyond that
		local p = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde", rules = rules }))
		eq(#p.bench, 2)
		deepEq(p.warnings, {})
		for _, name in ipairs(p.bench) do truthy(name:sub(1, 1) == "D" or name:sub(1, 1) == "E") end
		-- with one damage dealer only and three benches wanted, the minimums have to break
		local L2 = season()
		pool(L2, concat({ { "A1", TANK }, { "A2", TANK }, { "A3", TANK } }, { { "A4", HEALER }, { "A5", HEALER }, { "A6", HEALER } },
			team("D", 5, DPS)))
		local strict = Ru().DefaultConfig()
		strict.bench.minTanks, strict.bench.minHealers = 3, 3
		local q = assert(Ro().Propose(L2, "S1", { size = 10, faction = "Horde", rules = strict }))
		eq(#q.bench, 1); eq(#q.raid, 10)
		local L3 = season()
		pool(L3, concat({ { "A1", TANK }, { "A2", TANK }, { "A3", TANK } }, { { "A4", HEALER }, { "A5", HEALER }, { "A6", HEALER } },
			team("D", 3, DPS)))
		local r = assert(Ro().Propose(L3, "S1", { size = 6, faction = "Horde", rules = strict }))
		-- 9 candidates, 6 places, minimums 3 + 3 = 6: the three damage dealers sit out and nothing breaks
		deepEq(r.bench, { "D1", "D2", "D3" }); deepEq(r.warnings, {})
		local r2 = assert(Ro().Propose(L3, "S1", { size = 5, faction = "Horde", rules = strict }))
		-- 9 candidates, 5 places: 4 sit out, only 3 damage dealers are not protected: a tank or a healer gives way
		eq(#r2.bench, 4)
		eq(#r2.warnings, 1)
		truthy(r2.warnings[1] == "ROLE_TANK" or r2.warnings[1] == "ROLE_HEALER")
	end)

	it("counts a member with no declared role as a damage dealer and ignores inactive members and the other faction", function()
		local L = season()
		pool(L, concat(team("D", 11, DPS), { { "Inactive", DPS, { status = "INACTIVE" } }, { "Elsewhere", DPS, { faction = "Alliance" } } }))
		local p = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde" }))
		eq(p.candidates, 11)
		eq(#p.bench, 1)
		falsy(has(p.raid, "Inactive")); falsy(has(p.raid, "Elsewhere")); falsy(has(p.bench, "Inactive"))
	end)

	it("takes the size, the faction and the date from the night and does not count the night being planned", function()
		local L = season()
		pool(L, team("D", 12, DPS))
		play(L, { "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9", "D10" }, { "D11", "D12" }, 1)
		-- a second night, open, with D1 and D2 benched already: asking again for this night gives the same answer as before
		local plan = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde" }))
		eq(#plan.bench, 2)
		nightTs = nightTs + 100
		local ev = assert(N().Open(L, { author = OFFICER, ts = nightTs, season = "S1", date = "2026-11-08", instanceID = 531,
			difficulty = "normal", faction = "Horde" }))
		assert(N().SetLineup(L, { author = OFFICER, ts = nightTs + 1, season = "S1", bench = plan.bench }))
		local again = assert(Ro().Propose(L, "S1", { night = ev.id }))
		deepEq(again.bench, plan.bench)
		eq(again.slots, 10)
		local x, code = Ro().Propose(L, "S1", { night = "nope" })
		isNil(x); eq(code, "NIGHT_UNKNOWN")
		x, code = Ro().Propose(L, "S2", {})
		eq(code, "SEASON_UNKNOWN")
		x, code = Ro().Propose(L, "S1", { size = 0 })
		eq(code, "SIZE")
	end)
end)

describe("preferences, the calendar and the master looter's hand", function()
	local function twelve()
		local L = season()
		pool(L, team("D", 12, DPS))
		return L
	end

	it("puts a volunteer on the bench first, and a tentative sign-up before the rotation", function()
		local L = twelve()
		local p = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde", volunteers = { "D9" }, signups = { D11 = "maybe" } }))
		deepEq(p.bench, { "D11", "D9" })
		eq(p.why.D9, "VOLUNTEER"); eq(p.why.D11, "MAYBE")
		local q = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde", volunteers = { "D9", "D8", "D7" } }))
		eq(#q.bench, 2)
		deepEq(q.bench, { "D7", "D8" })   -- the volunteers beyond the surplus are not benched; by name among equals
	end)

	it("does not bench a volunteer tank when the minimum would break", function()
		local L = season()
		pool(L, concat({ { "A1", TANK }, { "A2", TANK } }, team("D", 10, DPS)))
		local rules = Ru().DefaultConfig()
		rules.bench.minTanks, rules.bench.minHealers = 2, 0
		local p = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde", rules = rules, volunteers = { "A1" } }))
		falsy(has(p.bench, "A1"))
		eq(#p.bench, 2)
	end)

	it("leaves out who declined (they are not there to be benched) and who cannot come that weekday", function()
		local L = season()
		pool(L, concat(team("D", 10, DPS), { { "Late", DPS, { avail = { "SAT", "SUN" } } }, { "Weekday", DPS, { avail = { "MON", "TUE" } } },
			{ "Maybe", DPS } }))
		-- 2026-11-21 is a Saturday: "Weekday" is not coming; "D1" declined on the calendar
		local p = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde", date = "2026-11-21", signups = { D1 = "no" } }))
		eq(p.excluded.D1, "DECLINED"); eq(p.excluded.Weekday, "UNAVAILABLE")
		eq(p.candidates, 11)
		eq(#p.bench, 1)
		falsy(has(p.raid, "D1")); falsy(has(p.raid, "Weekday")); falsy(has(p.bench, "D1"))
		local free = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde", date = "2026-11-21", useAvailability = false }))
		isNil(free.excluded.Weekday)
		eq(free.candidates, 13)
	end)

	it("never proposes a kept member and drops a member the master looter excludes", function()
		local L = twelve()
		local p = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde", keep = { "D1", "D2" }, exclude = { "D12" } }))
		eq(p.excluded.D12, "MANUAL")
		eq(p.candidates, 11)
		eq(#p.bench, 1)
		falsy(has(p.bench, "D1")); falsy(has(p.bench, "D2"))
		local all = assert(Ro().Propose(L, "S1", { size = 4, faction = "Horde", keep = { "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9", "D10", "D11", "D12" } }))
		eq(#all.bench, 0)
		deepEq(all.warnings, { "TOO_MANY_KEPT" })
	end)
end)

describe("a simulated season", function()
	-- 14 raiders for ten places: 3 tanks, 4 healers, 7 damage dealers; every night the proposal is followed.
	it("is fair inside every role and respects the role minimums every night", function()
		nightTs = 100
		local L = season()
		pool(L, concat(team("T", 3, TANK), team("H", 4, HEALER), team("D", 7, DPS)))
		local rules = Ru().DefaultConfig()
		rules.bench.minTanks, rules.bench.minHealers = 2, 3
		local seen = {}
		for night = 1, 24 do
			local p = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde", rules = rules }))
			eq(#p.raid, 10, "night " .. night); eq(#p.bench, 4, "night " .. night)
			truthy(count(p.raid, "T") >= 2, "tanks in the raid, night " .. night)
			truthy(count(p.raid, "H") >= 3, "healers in the raid, night " .. night)
			deepEq(p.warnings, {})
			play(L, p.raid, p.bench, night)
			seen[night] = p
		end
		local counts = Ro().Counts(L, "S1")
		local byRole = { T = {}, H = {}, D = {} }
		for name, c in pairs(counts) do
			eq(c.played + c.benched, 24, name .. " is always on one list or the other")
			local list = byRole[name:sub(1, 1)]
			list[#list + 1] = c.benched
		end
		for role, list in pairs(byRole) do
			table.sort(list)
			truthy(list[#list] - list[1] <= 1, ("the benches of the %s role differ by at most one: %s"):format(role, table.concat(list, ",")))
		end
		-- everybody sat out at least once, and the heaviest bench is not far from the lightest overall
		local lo, hi = math.huge, 0
		for _, c in pairs(counts) do lo, hi = math.min(lo, c.benched), math.max(hi, c.benched) end
		truthy(lo >= 1)
		truthy(hi - lo <= 8, "overall spread " .. (hi - lo))
	end)

	it("is fair among identical members: with no roles in play the benches differ by at most one", function()
		nightTs = 100
		local L = season()
		pool(L, team("D", 13, DPS))
		for night = 1, 26 do
			local p = assert(Ro().Propose(L, "S1", { size = 10, faction = "Horde" }))
			eq(#p.bench, 3)
			play(L, p.raid, p.bench, night)
		end
		local lo, hi = math.huge, 0
		for _, c in pairs(Ro().Counts(L, "S1")) do lo, hi = math.min(lo, c.benched), math.max(hi, c.benched) end
		eq(lo, 6); eq(hi, 6)   -- 26 nights x 3 benches = 78 = 13 x 6
	end)
end)

describe("the effect of a bench on the credits", function()
	local function benched()
		nightTs = 100
		local L = season()
		pool(L, team("D", 12, DPS))
		play(L, { "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9", "D10" }, { "D11", "D12" }, 1)
		play(L, { "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9", "D11" }, { "D10", "D12" }, 2)
		return L
	end

	it("counts the benches and the nights played of a member", function()
		local c = Ro().Counts(benched(), "S1")
		eq(c.D12.benched, 2); eq(c.D12.played, 0)
		eq(c.D11.benched, 1); eq(c.D11.played, 1)
		eq(c.D1.benched, 0); eq(c.D1.played, 2)
	end)

	it("is none in the guild's preset: the rotation never penalizes", function()
		local L = benched()
		deepEq(Ro().CreditEffect(L, "S1"), {})
		deepEq(Ro().Credits(L, "S1"), Lg().Credits(L, "S1"))
	end)

	it("gives a bonus (credits down, never below zero) or a malus (credits up) per bench", function()
		local L = benched()
		local bonus = Ru().DefaultConfig()
		bonus.bench.creditEffect, bonus.bench.creditAmount = "bonus", 1
		deepEq(Ro().CreditEffect(L, "S1", bonus), { D10 = -1, D11 = -1, D12 = -2 })
		local credits = Ro().Credits(L, "S1", bonus)
		eq(credits.D12, 0, "a member at zero already has the top priority")
		eq(credits.D1, 0)
		-- give D10 and D12 credits through the ledger: 3 and 1
		assert(Lg().Append(L, { author = OFFICER, ts = 900, season = "S1", type = "CREDITS_ADJUSTED", payload = { member = "D10", delta = 3, reason = "RC_TEST" } }))
		assert(Lg().Append(L, { author = OFFICER, ts = 901, season = "S1", type = "CREDITS_ADJUSTED", payload = { member = "D12", delta = 1, reason = "RC_TEST" } }))
		credits = Ro().Credits(L, "S1", bonus)
		eq(credits.D10, 2); eq(credits.D12, 0)
		local malus = Ru().DefaultConfig()
		malus.bench.creditEffect, malus.bench.creditAmount = "malus", 0.5
		credits = Ro().Credits(L, "S1", malus)
		eq(credits.D10, 3.5); eq(credits.D12, 2); eq(credits.D1, 0)
	end)

	it("reads the rules in force from the ledger when none are given", function()
		local L = benched()
		local rules = Ru().DefaultConfig()
		rules.bench.creditEffect = "malus"
		assert(Ru().Change(L, { author = GM, ts = 800, rules = rules, confirmed = true }))
		eq(Ro().CreditEffect(L, "S1").D12, 2)
	end)
end)
