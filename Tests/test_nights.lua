-- Nights (M3-3): an official raid night with its lineup (raid / bench / absent) and the attendance per boss.
-- Domain/Nights.lua is pure; Adapters/Group.lua reads the raid and ENCOUNTER_END; App/NightController.lua writes the
-- ledger from them (the mock raid and the mock encounter drive it, as the client would).
local function Lg() return FDCP.Ledger end
local function Sn() return FDCP.Season end
local function M() return FDCP.Members end
local function N() return FDCP.Nights end
local function P() return FDCP.Permissions end
local function NC() return FDCP.NightController end

local GM, OFFICER, RAIDER = "Aurel-Camelot", "Bryn-Camelot", "Corin-Camelot"
local PACK = { { id = 409, size = 40 }, { id = 509, size = 20 }, { id = 469, size = 40 } }
local POOL = { "Aurel", "Bryn", "Corin", "Dara", "Edda", "Fenn", "Gale", "Hale" }

local function ranks()
	local h = P().NewHistory()
	P().RecordRank(h, GM, 0, 0)
	P().RecordRank(h, OFFICER, 1, 0)
	P().RecordRank(h, RAIDER, 3, 0)
	h.loaded = true
	return h
end

local function gate() return P().Gate(ranks()) end

-- A season "S1" with the pack above and the pool of eight mains (joined before the first night), no gate.
local function newSeason()
	local L = Lg().New()
	assert(Sn().Open(L, { author = GM, ts = 1, season = "S1", label = "Tier 1", instances = PACK }))
	for i, name in ipairs(POOL) do
		assert(M().Join(L, { author = OFFICER, ts = 1 + i, season = "S1", member = name, faction = "Horde" }))
	end
	return L
end

local function open(L, ts, extra)
	local d = { author = OFFICER, ts = ts, season = "S1", date = "2026-11-12", instanceID = 409, difficulty = "normal",
		faction = "Horde" }
	for k, v in pairs(extra or {}) do d[k] = v end
	return N().Open(L, d)
end

local function lineup(L, ts, raid, bench, absent, author)
	return N().SetLineup(L, { author = author or OFFICER, ts = ts, season = "S1", raid = raid, bench = bench, absent = absent })
end

local function kill(L, id, ts, extra)
	local d = { author = OFFICER, ts = ts, season = "S1", encounterID = id, difficulty = 14, date = "2026-11-12" }
	for k, v in pairs(extra or {}) do d[k] = v end
	return N().Kill(L, d)
end

-- The simulated night of the spec: seven members, a bench, joins and leaves around three bosses.
--   100 night opened (Molten Core, normal)
--   101 raid Aurel Bryn Corin Dara; Edda and Gale on the bench
--   200 boss 610 killed       raid A B C D        bench E G   absent F H
--   250 Dara leaves, Fenn joins
--   300 boss 611 killed       raid A B C F        bench E G   absent D H
--   350 Edda comes off the bench into the raid, Bryn leaves
--   400 boss 612 killed       raid A C E F        bench G     absent B D H
--   450 Hale joins, 500 night closed
local function simulated()
	local L = newSeason()
	assert(open(L, 100))
	assert(lineup(L, 101, { "Aurel", "Bryn", "Corin", "Dara" }, { "Edda", "Gale" }))
	assert(kill(L, 610, 200))
	assert(lineup(L, 250, { "Fenn" }, nil, { "Dara" }))
	assert(kill(L, 611, 300))
	assert(lineup(L, 350, { "Edda" }, nil, { "Bryn" }))
	assert(kill(L, 612, 400))
	assert(lineup(L, 450, { "Hale" }))
	assert(N().Close(L, { author = OFFICER, ts = 500, season = "S1" }))
	return L
end

local function names(list) return table.concat(list, ",") end

describe("opening and closing a night", function()
	it("writes NIGHT_OPENED with the date, the instance, the size and the difficulty, and NIGHT_CLOSED ends it", function()
		local L = newSeason()
		local e = assert(open(L, 100))
		eq(e.type, "NIGHT_OPENED")
		deepEq(e.payload, { date = "2026-11-12", instanceID = 409, size = 40, difficulty = "normal", faction = "Horde" })
		local n = N().Current(L, "S1")
		eq(n.id, e.id); eq(n.date, "2026-11-12"); eq(n.instanceID, 409); eq(n.size, 40); eq(n.difficulty, "normal")
		eq(n.closed, false); eq(n.author, OFFICER)
		local c = assert(N().Close(L, { author = OFFICER, ts = 200, season = "S1" }))
		eq(c.type, "NIGHT_CLOSED"); eq(c.payload.night, e.id)
		isNil(N().Current(L, "S1"))
		local list = N().List(L, "S1")
		eq(#list, 1); eq(list[1].closed, true); eq(list[1].closedAt, 200); eq(list[1].closeId, c.id)
	end)

	it("takes the size from the season's pack: 10, 20 and 40 players", function()
		local L = newSeason()
		eq(assert(open(L, 100, { instanceID = 509 })).payload.size, 20)
		assert(N().Close(L, { author = OFFICER, ts = 150, season = "S1" }))
		eq(assert(open(L, 200, { instanceID = 469 })).payload.size, 40)
		local code
		assert(N().Close(L, { author = OFFICER, ts = 250, season = "S1" }))
		_, code = open(L, 300, { instanceID = 409, size = 20 })
		eq(code, "SIZE", "a size that is not the pack's for that instance")
		local ten = Lg().New()
		assert(Sn().Open(ten, { author = GM, ts = 1, season = "S1", instances = { { id = 531, size = 10 } } }))
		eq(assert(open(ten, 10, { instanceID = 531 })).payload.size, 10)
	end)

	it("counts official raids only: an instance outside the season's pack is refused", function()
		local L = newSeason()
		local e, code = open(L, 100, { instanceID = 1234 })
		isNil(e); eq(code, "NOT_IN_PACK")
		eq(#N().List(L, "S1"), 0)
	end)

	it("records Normal and Veteran, which share the season's one credit table", function()
		local L = newSeason()
		eq(assert(open(L, 100, { difficulty = "normal" })).payload.difficulty, "normal")
		assert(N().Close(L, { author = OFFICER, ts = 150, season = "S1" }))
		eq(assert(open(L, 200, { difficulty = "veteran" })).payload.difficulty, "veteran")
		local _, code = open(L, 300, { difficulty = "heroic" })
		eq(code, "DIFFICULTY")
		local season = Sn().Get(L, "S1")
		eq(Sn().CreditTable(season, 409, "normal"), "S1")
		eq(Sn().CreditTable(season, 409, "veteran"), "S1")
	end)

	it("turns the client's difficulty into a code: by name first, then by id", function()
		eq(N().DifficultyCode(14, "Normal"), "normal")
		eq(N().DifficultyCode(99, "Veteran"), "veteran")
		eq(N().DifficultyCode(99, "Veterano"), "veteran")
		eq(N().DifficultyCode(15, nil), "veteran")
		eq(N().DifficultyCode(14, nil), "normal")
		isNil(N().DifficultyCode(77, "Mythic"))
	end)

	it("keeps one night open per season, and refuses a close or a lineup without one", function()
		local L = newSeason()
		assert(open(L, 100))
		local e, code = open(L, 110)
		isNil(e); eq(code, "NIGHT_ALREADY_OPEN")
		assert(N().Close(L, { author = OFFICER, ts = 120, season = "S1" }))
		_, code = N().Close(L, { author = OFFICER, ts = 130, season = "S1" })
		eq(code, "NO_NIGHT_OPEN")
		_, code = lineup(L, 140, { "Aurel" })
		eq(code, "NO_NIGHT_OPEN")
		assert(open(L, 200), "a new night can open once the first is closed")
		eq(#N().List(L, "S1"), 2)
	end)

	it("refuses an unknown or closed season and a malformed date", function()
		local L = newSeason()
		local _, code = N().Open(L, { author = OFFICER, ts = 1, season = "S9", date = "2026-11-12", instanceID = 409,
			difficulty = "normal" })
		eq(code, "SEASON_UNKNOWN")
		_, code = open(L, 100, { date = "12/11/2026" })
		eq(code, "payload:date")
		_, code = open(L, 100, { date = "2026-13-01" })
		eq(code, "payload:date")
		assert(Sn().Close(L, { author = GM, ts = 50, season = "S1" }))
		_, code = open(L, 100)
		eq(code, "SEASON_CLOSED")
	end)

	it("lets only the ranks with night.run write it (the trust gate of M2-5)", function()
		local L = newSeason()
		local e, code = N().Open(L, { author = RAIDER, ts = 100, season = "S1", date = "2026-11-12", instanceID = 409,
			difficulty = "normal" }, gate())
		isNil(e); eq(code, "RANK_TOO_LOW")
		assert(N().Open(L, { author = OFFICER, ts = 100, season = "S1", date = "2026-11-12", instanceID = 409,
			difficulty = "normal" }, gate()))
		_, code = N().SetLineup(L, { author = RAIDER, ts = 110, season = "S1", raid = { "Aurel" } }, gate())
		eq(code, "RANK_TOO_LOW")
		_, code = N().Kill(L, { author = RAIDER, ts = 120, season = "S1", encounterID = 610 }, gate())
		eq(code, "RANK_TOO_LOW")
		_, code = N().Close(L, { author = RAIDER, ts = 130, season = "S1" }, gate())
		eq(code, "RANK_TOO_LOW")
	end)

	it("also reads a close that names no night, and one that arrives before its night", function()
		local L = newSeason()
		local o = assert(open(L, 100))
		assert(Lg().Append(L, { author = OFFICER, ts = 200, season = "S1", type = "NIGHT_CLOSED", payload = {} }))
		eq(N().List(L, "S1")[1].closed, true)
		-- the close of a night that is not here yet waits in the ledger and counts once the night is merged
		local other = Lg().New()
		assert(Sn().Open(other, { author = GM, ts = 1, season = "S1", instances = PACK }))
		assert(Lg().Append(other, { author = OFFICER, ts = 200, season = "S1", type = "NIGHT_CLOSED",
			payload = { night = o.id } }))
		eq(#N().List(other, "S1"), 0)
		assert(Lg().Merge(other, { o }))
		eq(N().List(other, "S1")[1].closed, true)
	end)
end)

describe("the lineup", function()
	it("is raid, bench or absent, written as the members that changed, in one event", function()
		local L = newSeason()
		local night = assert(open(L, 100))
		local e = assert(lineup(L, 101, { "Corin", "Aurel" }, { "Edda" }))
		eq(e.type, "LINEUP_CHANGED")
		deepEq(e.payload, { night = night.id, raid = { "Aurel", "Corin" }, bench = { "Edda" } })
		local lists = N().Lists(N().Lineup(L, night.id))
		deepEq(lists, { raid = { "Aurel", "Corin" }, bench = { "Edda" }, absent = {} })
		-- only real changes are written: the same lineup again is "no change"
		local x, code = lineup(L, 102, { "Aurel" }, { "Edda" })
		isNil(x); eq(code, "NO_CHANGE")
		assert(lineup(L, 103, { "Dara" }, nil, { "Aurel" }))
		deepEq(N().Lists(N().Lineup(L, night.id)), { raid = { "Corin", "Dara" }, bench = { "Edda" }, absent = { "Aurel" } })
	end)

	it("moves a benched member into the raid and back", function()
		local L = newSeason()
		local night = assert(open(L, 100))
		assert(lineup(L, 101, nil, { "Edda" }))
		eq(N().Lineup(L, night.id).Edda, "BENCH")
		assert(lineup(L, 102, { "Edda" }))
		eq(N().Lineup(L, night.id).Edda, "RAID")
		assert(lineup(L, 103, nil, { "Edda" }))
		eq(N().Lineup(L, night.id).Edda, "BENCH")
	end)

	it("logs the boss of reference: the last boss killed before the change", function()
		local L = newSeason()
		assert(open(L, 100))
		local a = assert(lineup(L, 101, { "Aurel" }))
		isNil(a.payload.boss, "nothing killed yet")
		assert(kill(L, 610, 200))
		local b = assert(lineup(L, 250, { "Bryn" }))
		eq(b.payload.boss, 610)
		assert(kill(L, 611, 300))
		local c = assert(lineup(L, 350, { "Corin" }))
		eq(c.payload.boss, 611)
		eq(c.ts, 350, "and the time of the change")
	end)

	it("takes only pool mains, and an unknown name refuses the whole change", function()
		local L = newSeason()
		assert(open(L, 100))
		local e, code = lineup(L, 101, { "Aurel", "Nobody" })
		isNil(e); eq(code, "NOT_MEMBER")
		eq(#Lg().Sorted(L, function(x) return x.type == "LINEUP_CHANGED" end), 0)
	end)

	it("reads the lineup as it was at a moment", function()
		local L = newSeason()
		local night = assert(open(L, 100))
		assert(lineup(L, 101, { "Aurel", "Bryn" }))
		local late = assert(lineup(L, 300, nil, nil, { "Bryn" }))
		deepEq(N().Lists(N().Lineup(L, night.id)).raid, { "Aurel" })
		deepEq(N().Lists(N().Lineup(L, night.id, { at = late })).raid, { "Aurel", "Bryn" })
	end)

	it("checks the payload: lists of names, no name twice, at least one member", function()
		local L = newSeason()
		local night = assert(open(L, 100))
		local function try(payload)
			return Lg().Append(L, { author = OFFICER, ts = 101, season = "S1", type = "LINEUP_CHANGED", payload = payload })
		end
		local _, code = try({ night = night.id })
		eq(code, "payload:lineup")
		_, code = try({ night = night.id, raid = { "Aurel" }, bench = { "Aurel" } })
		eq(code, "payload:bench")
		_, code = try({ night = night.id, raid = { 5 } })
		eq(code, "payload:raid")
		_, code = try({ night = "nonsense", raid = { "Aurel" } })
		eq(code, "payload:night")
		_, code = try({ night = night.id, raid = { "Aurel" }, boss = -1 })
		eq(code, "payload:boss")
		assert(try({ night = night.id, raid = { "Aurel" } }))
	end)
end)

describe("attendance per boss", function()
	it("gives the expected raid, bench and absent members at each of the three bosses", function()
		local L = simulated()
		local a = N().Attendance(L, "S1")
		eq(#a.nights, 1)
		local kills = a.nights[1].kills
		eq(#kills, 3)
		eq(kills[1].kill.encounterID, 610)
		eq(names(kills[1].raid), "Aurel,Bryn,Corin,Dara")
		eq(names(kills[1].bench), "Edda,Gale")
		eq(names(kills[1].absent), "Fenn,Hale")
		eq(kills[2].kill.encounterID, 611)
		eq(names(kills[2].raid), "Aurel,Bryn,Corin,Fenn")
		eq(names(kills[2].bench), "Edda,Gale")
		eq(names(kills[2].absent), "Dara,Hale")
		eq(kills[3].kill.encounterID, 612)
		eq(names(kills[3].raid), "Aurel,Corin,Edda,Fenn")
		eq(names(kills[3].bench), "Gale")
		eq(names(kills[3].absent), "Bryn,Dara,Hale")
		eq(names(a.nights[1].final.raid), "Aurel,Corin,Edda,Fenn,Hale")
	end)

	it("counts per member the nights played, the benches and the bosses attended out of the ones possible", function()
		local a = N().Attendance(simulated(), "S1")
		local m = a.members
		eq(m.Aurel.bosses, 3); eq(m.Aurel.possible, 3); eq(m.Aurel.played, 1); eq(m.Aurel.benched, 0)
		eq(m.Bryn.bosses, 2); eq(m.Dara.bosses, 1); eq(m.Fenn.bosses, 2); eq(m.Edda.bosses, 1)
		eq(m.Edda.played, 1); eq(m.Edda.benched, 0, "benched and then played: that night is a play, not a bench")
		eq(m.Gale.bosses, 0); eq(m.Gale.played, 0); eq(m.Gale.benched, 1); eq(m.Gale.possible, 3)
		eq(m.Hale.bosses, 0); eq(m.Hale.played, 1, "in the raid at the end, after the last boss")
		eq(m.Hale.possible, 3)
	end)

	it("does not count as absent a member who joined the pool after the kill, or one who is inactive", function()
		local L = newSeason()
		assert(open(L, 100))
		assert(lineup(L, 101, { "Aurel" }))
		assert(kill(L, 610, 200))
		assert(M().Join(L, { author = OFFICER, ts = 250, season = "S1", member = "Ivo", faction = "Horde" }))
		assert(kill(L, 611, 300))
		local a = N().Attendance(L, "S1")
		local first, second = a.nights[1].kills[1], a.nights[1].kills[2]
		eq(#first.absent, 7)
		eq(#second.absent, 8, "Ivo is in the pool at the second boss")
		local has = false
		for _, n in ipairs(first.absent) do if n == "Ivo" then has = true end end
		falsy(has)
	end)

	it("leaves out the pool members of the other faction, and counts those without a faction", function()
		local L = newSeason()
		assert(M().Join(L, { author = OFFICER, ts = 20, season = "S1", member = "Zed", faction = "Alliance" }))
		assert(M().Join(L, { author = OFFICER, ts = 21, season = "S1", member = "Nox" }))
		assert(open(L, 100))
		assert(kill(L, 610, 200))
		local absent = N().Attendance(L, "S1").nights[1].kills[1].absent
		local text = "," .. names(absent) .. ","
		falsy(text:find(",Zed,", 1, true))
		truthy(text:find(",Nox,", 1, true))
		eq(#absent, 9)
	end)

	it("records a kill once per night and boss even when two officers write it", function()
		local L = newSeason()
		assert(open(L, 100))
		assert(lineup(L, 101, { "Aurel" }))
		assert(kill(L, 610, 200))
		-- the second officer's client wrote the same kill a second later
		assert(Lg().Append(L, { author = RAIDER, ts = 201, season = "S1", type = "ENCOUNTER_KILLED",
			payload = { encounterID = 610, difficulty = 14, time = 201, date = "2026-11-12",
				night = N().Current(L, "S1").id } }))
		eq(#N().Kills(L, { season = "S1" }), 1)
		eq(N().Attendance(L, "S1").members.Aurel.bosses, 1)
		local _, code = kill(L, 610, 210)
		eq(code, "ALREADY_KILLED")
	end)

	it("gives the same attendance whatever order the events are merged in", function()
		local L = simulated()
		local reference = N().Attendance(L, "S1")
		local events = Lg().Sorted(L)
		for seed = 1, 6 do
			local mixed, state = {}, seed
			for i, e in ipairs(events) do mixed[i] = e end
			for i = #mixed, 2, -1 do
				state = (state * 1103515245 + 12345) % 2147483648
				local j = (math.floor(state / 65536) % i) + 1
				mixed[i], mixed[j] = mixed[j], mixed[i]
			end
			local other = Lg().New()
			assert(Lg().Merge(other, mixed))
			deepEq(N().Attendance(other, "S1"), reference, "seed " .. seed)
		end
	end)

	it("keeps the nights apart: two nights in two instances in the same evening", function()
		local L = newSeason()
		assert(open(L, 100))
		assert(lineup(L, 101, { "Aurel", "Bryn" }))
		assert(kill(L, 610, 200))
		assert(N().Close(L, { author = OFFICER, ts = 300, season = "S1" }))
		assert(open(L, 400, { instanceID = 509 }))
		assert(lineup(L, 401, { "Aurel", "Corin" }))
		assert(kill(L, 1000, 500, { instanceID = 509 }))
		local a = N().Attendance(L, "S1")
		eq(#a.nights, 2)
		eq(names(a.nights[1].kills[1].raid), "Aurel,Bryn")
		eq(names(a.nights[2].kills[1].raid), "Aurel,Corin")
		eq(a.members.Aurel.played, 2); eq(a.members.Bryn.played, 1); eq(a.members.Aurel.bosses, 2)
		eq(#N().Attendance(L, "S1", { night = a.nights[2].night.id }).nights, 1)
	end)

	it("hands the nights played to the late-join basis of the members' credits", function()
		local L = simulated()
		local played = N().Played(L, "S1")
		eq(played.Aurel, 1); eq(played.Gale, 0)
		local _, _, basis = M().LateJoinCredits(L, "S1", M().DefaultConfig(), { nights = played })
		eq(basis, 7, "Gale was only benched: not in the basis of minNights = 1")
		local _, _, all = M().LateJoinCredits(L, "S1", M().DefaultConfig())
		eq(all, 8)
	end)
end)

describe("kills", function()
	it("are written with the night, the encounter, the difficulty and the date", function()
		local L = newSeason()
		local night = assert(open(L, 100))
		local e = assert(kill(L, 610, 200, { size = 40 }))
		eq(e.payload.encounterID, 610); eq(e.payload.difficulty, 14); eq(e.payload.night, night.id)
		eq(e.payload.date, "2026-11-12"); eq(e.payload.time, 200); eq(e.payload.instanceID, 409); eq(e.payload.size, 40)
		local list = N().Kills(L, { season = "S1", night = night.id })
		eq(#list, 1); eq(list[1].encounterID, 610); eq(list[1].night, night.id)
	end)

	it("are available per encounter, inside a night or outside one (the first kills of M3-3b)", function()
		local L = newSeason()
		-- before any night: a kill outside a night
		local outside = assert(kill(L, 610, 50, { date = "2026-11-05" }))
		isNil(outside.payload.night)
		local night = assert(open(L, 100))
		assert(kill(L, 610, 200, { date = "2026-11-12" }))
		assert(kill(L, 611, 210))
		-- another instance while a night is open does not belong to the night
		local other = assert(kill(L, 700, 220, { instanceID = 509 }))
		isNil(other.payload.night)
		assert(N().Close(L, { author = OFFICER, ts = 300, season = "S1" }))
		local by = N().KillsByEncounter(L, "S1")
		eq(#by[610], 2); eq(by[610][1].date, "2026-11-05"); isNil(by[610][1].night)
		eq(by[610][2].night, night.id)
		eq(#by[611], 1); eq(#by[700], 1)
		eq(Lg().FirstKills(L)[610], "2026-11-05", "the oldest date is the first kill")
		eq(#N().Kills(L, { season = "S1", night = night.id }), 2)
		eq(#N().Kills(L, { encounterID = 611 }), 1)
	end)

	it("a kill without a date, a night or a time is still a valid event, and bad fields are refused", function()
		local L = newSeason()
		assert(Lg().Append(L, { author = OFFICER, ts = 1, season = "S1", type = "ENCOUNTER_KILLED",
			payload = { encounterID = 610 } }))
		local function try(extra)
			local p = { encounterID = 610 }
			for k, v in pairs(extra) do p[k] = v end
			return select(2, Lg().Append(L, { author = OFFICER, ts = 2, season = "S1", type = "ENCOUNTER_KILLED", payload = p }))
		end
		eq(try({ difficulty = -1 }), "payload:difficulty")
		eq(try({ time = "now" }), "payload:time")
		eq(try({ night = "x" }), "payload:night")
		eq(try({ instanceID = 0 }), "payload:instanceID")
		eq(try({ size = 0 }), "payload:size")
		eq(try({ date = "yesterday" }), "payload:date")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The adapter and the controller on the mock client

local ME = "Testchar-TestRealm"
local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }
local RAID_INSTANCE = { name = "Molten Core", type = "raid", difficultyID = 14, difficultyName = "Normal", maxPlayers = 40,
	instanceID = 409 }

local function guild(myRank)
	return function(Mock)
		Mock.guild.Set({ name = "Keepers", ranks = RANKS, myRank = myRank or 1, members = {
			{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
		} })
	end
end

local function settle() Mock.Advance(3) end

local function raid(...)
	local members = {}
	for _, n in ipairs({ ... }) do members[#members + 1] = { name = n, inGuild = true } end
	Mock.group.Set({ raid = true, members = members })
end

-- The player is an officer; the pool is Aurel, Bryn, Corin, Dara, Edda ("-TestRealm"), Aurel has an alt "Fox".
local function bound(extra)
	local L = Lg().New()
	assert(Sn().Open(L, { author = "Aurel-TestRealm", ts = 1, season = "S1", instances = { { id = 409, size = 40 } } }))
	for i, n in ipairs({ "Aurel", "Bryn", "Corin", "Dara", "Edda" }) do
		assert(M().Join(L, { author = "Bryn-TestRealm", ts = 1 + i, season = "S1", member = n .. "-TestRealm",
			faction = "Horde" }))
	end
	assert(M().LinkAlt(L, { author = "Bryn-TestRealm", ts = 9, season = "S1", alt = "Fox-TestRealm",
		main = "Aurel-TestRealm" }))
	NC():Bind(L)
	Mock.encounter.Set({ instance = RAID_INSTANCE })
	return L
end

local function lists(L)
	local night = N().Current(L, "S1")
	local l = N().Lists(N().Lineup(L, night.id))
	for _, k in ipairs({ "raid", "bench", "absent" }) do
		for i, n in ipairs(l[k]) do l[k][i] = n:gsub("%-TestRealm$", "") end
	end
	return l
end

describe("the group adapter", function()
	before_boot(guild(1))

	it("reads the raid through Compat as Name-Realm, the player included", function()
		raid("Aurel", "Zed-Other Realm")
		local s = FDCP.Group.Snapshot()
		truthy(s.inRaid); truthy(s.complete); eq(s.size, 3); eq(s.read, 3); eq(s.me, ME)
		truthy(s.members["Aurel-TestRealm"]); truthy(s.members[ME])
		eq(s.members["Zed-Other Realm"] ~= nil or s.members["Zed-OtherRealm"] ~= nil, true)
	end)

	it("says nothing about a party or an empty group", function()
		local s = FDCP.Group.Snapshot()
		falsy(s.inRaid); eq(s.read, 0); falsy(s.complete)
		Mock.group.Set({ raid = false, members = { { name = "Aurel" } } })
		s = FDCP.Group.Snapshot()
		falsy(s.inRaid); eq(next(s.members), nil)
	end)

	it("marks the snapshot incomplete when the client hides a name", function()
		raid("Aurel", "Bryn")
		Mock.group.secretGUIDs = true
		local s = FDCP.Group.Snapshot()
		truthy(s.inRaid); falsy(s.complete)
		eq(s.read, 1, "only the player's own row is readable")
		Mock.group.secretGUIDs = false
	end)

	it("scans once, a second after a burst of group events, and emits GROUP_SCANNED", function()
		local seen = {}
		FDCP.Bus:On("GROUP_SCANNED", function(_, snapshot) seen[#seen + 1] = snapshot end)
		raid("Aurel")
		raid("Aurel", "Bryn")
		raid("Aurel", "Bryn", "Corin")
		eq(#seen, 0)
		Mock.Advance(2)
		eq(#seen, 1)
		eq(seen[1].size, 4)
	end)

	it("turns ENCOUNTER_END into ENCOUNTER_ENDED and drops a hidden one", function()
		local seen = {}
		FDCP.Bus:On("ENCOUNTER_ENDED", function(_, info) seen[#seen + 1] = info end)
		Mock.encounter.End(610, "Lucifron", true)
		eq(#seen, 1)
		eq(seen[1].encounterID, 610); eq(seen[1].name, "Lucifron"); eq(seen[1].success, true)
		eq(seen[1].difficultyID, 14); eq(seen[1].groupSize, 20)
		Mock.encounter.End(611, "Magmadar", false)
		eq(seen[2].success, false)
		Mock.Fire("ENCOUNTER_END", Mock.SECRET, "x", 14, 20, 1)
		eq(#seen, 2, "a secret encounter id is never read")
	end)
end)

describe("the night controller", function()
	before_boot(guild(1))

	it("opens a night in the instance the officer stands in, writes the lineup from the raid and the date", function()
		local L = bound()
		settle()
		raid("Aurel", "Bryn", "Zed")
		local night = assert(NC():Open({}))
		eq(night.instanceID, 409); eq(night.size, 40); eq(night.difficulty, "normal"); eq(night.date, "2026-01-01")
		eq(night.faction, "Horde"); eq(night.author, ME)
		deepEq(lists(L), { raid = { "Aurel", "Bryn" }, bench = {}, absent = {} })
		eq(NC():Current().id, night.id)
	end)

	it("opens by choice before the raid is formed (a bench planned, the alt resolved to its main)", function()
		local L = bound()
		settle()
		local night = assert(NC():Open({ instanceID = 409, difficulty = "veteran", bench = { "Edda", "Fox" } }))
		eq(night.difficulty, "veteran")
		deepEq(lists(L), { raid = {}, bench = { "Aurel", "Edda" }, absent = {} })
	end)

	it("refuses what is not an official night, and what the rank does not allow", function()
		local L = bound()
		settle()
		local n, code = NC():Open({ instanceID = 9999, difficulty = "normal" })
		isNil(n); eq(code, "NOT_IN_PACK")
		n, code = NC():Open({ instanceID = 409, difficulty = "legendary" })
		eq(code, "DIFFICULTY")
		n, code = NC():Open({ instanceID = 409, difficulty = "normal", bench = { "Nobody" } })
		eq(code, "NOT_MEMBER")
		eq(#N().List(L, "S1"), 0, "nothing was opened")
		assert(NC():Open({ instanceID = 409, difficulty = "normal" }))
		n, code = NC():Open({ instanceID = 409, difficulty = "normal" })
		eq(code, "NIGHT_ALREADY_OPEN")
	end)

	it("follows joins and leaves of the group while the night is open", function()
		local L = bound()
		settle()
		raid("Aurel", "Bryn", "Corin")
		assert(NC():Open({}))
		deepEq(lists(L), { raid = { "Aurel", "Bryn", "Corin" }, bench = {}, absent = {} })
		raid("Aurel", "Bryn", "Dara")
		settle()
		deepEq(lists(L), { raid = { "Aurel", "Bryn", "Dara" }, bench = {}, absent = { "Corin" } })
		raid("Aurel", "Bryn", "Dara", "Zed")
		settle()
		eq(#Lg().Sorted(L, function(e) return e.type == "LINEUP_CHANGED" end), 2, "a stranger changes nothing")
	end)

	it("counts an alt in the raid for its main", function()
		local L = bound()
		settle()
		raid("Fox", "Bryn")
		assert(NC():Open({}))
		deepEq(lists(L), { raid = { "Aurel", "Bryn" }, bench = {}, absent = {} })
		raid("Bryn")
		settle()
		deepEq(lists(L), { raid = { "Bryn" }, bench = {}, absent = { "Aurel" } })
	end)

	it("keeps a benched member on the bench until they join again, and puts one back with Unbench", function()
		local L = bound()
		settle()
		raid("Aurel", "Bryn", "Corin")
		assert(NC():Open({ bench = { "Corin" } }))
		deepEq(lists(L), { raid = { "Aurel", "Bryn" }, bench = { "Corin" }, absent = {} }, "in the group but benched")
		assert(NC():Bench("Bryn"))
		deepEq(lists(L), { raid = { "Aurel" }, bench = { "Bryn", "Corin" }, absent = {} })
		raid("Aurel")
		settle()
		deepEq(lists(L), { raid = { "Aurel" }, bench = { "Bryn", "Corin" }, absent = {} }, "the bench survives a leave")
		raid("Aurel", "Corin")
		settle()
		deepEq(lists(L), { raid = { "Aurel", "Corin" }, bench = { "Bryn" }, absent = {} }, "joining again ends the bench")
		assert(NC():Unbench("Bryn"))
		deepEq(lists(L), { raid = { "Aurel", "Corin" }, bench = {}, absent = { "Bryn" } }, "not in the group: absent")
		local e, code = NC():SetState("Nobody", "BENCH")
		isNil(e); eq(code, "NOT_MEMBER")
		e, code = NC():SetState("Bryn", "WHATEVER")
		eq(code, "BAD_STATE")
	end)

	it("never removes anybody when the client hides a row", function()
		local L = bound()
		settle()
		raid("Aurel", "Bryn")
		assert(NC():Open({}))
		raid("Aurel", "Corin", "Dara")
		Mock.group.secretGUIDs = true
		settle()
		Mock.group.secretGUIDs = false
		deepEq(lists(L), { raid = { "Aurel", "Bryn" }, bench = {}, absent = {} }, "an incomplete read changes nothing")
		settle()
		FDCP.Group.ScanNow()
		deepEq(lists(L), { raid = { "Aurel", "Corin", "Dara" }, bench = {}, absent = { "Bryn" } })
	end)

	it("records a night of three bosses with the lineup of each kill, even a join not scanned yet", function()
		local L = bound()
		settle()
		raid("Aurel", "Bryn", "Corin")
		assert(NC():Open({}))
		Mock.encounter.Start(610, "Lucifron")
		Mock.encounter.End(610, "Lucifron", true)
		raid("Aurel", "Bryn", "Dara")   -- no time passes: the debounced scan has not run, the kill reads the group itself
		Mock.encounter.Start(611, "Magmadar")
		Mock.encounter.End(611, "Magmadar", true)
		Mock.Advance(1)
		Mock.encounter.Start(612, "Gehennas")
		Mock.encounter.End(612, "Gehennas", false)   -- a wipe is not a kill
		raid("Aurel", "Dara", "Edda")
		Mock.Advance(2)
		Mock.encounter.End(612, "Gehennas", true)
		assert(NC():Close())
		local a = N().Attendance(L, "S1")
		local kills = a.nights[1].kills
		eq(#kills, 3)
		eq(kills[1].kill.encounterID, 610)
		eq(names(kills[1].raid), "Aurel-TestRealm,Bryn-TestRealm,Corin-TestRealm")
		eq(names(kills[2].raid), "Aurel-TestRealm,Bryn-TestRealm,Dara-TestRealm")
		eq(names(kills[3].raid), "Aurel-TestRealm,Dara-TestRealm,Edda-TestRealm")
		eq(kills[1].kill.date, "2026-01-01"); eq(kills[1].kill.difficulty, 14); eq(kills[1].kill.instanceID, 409)
		eq(kills[1].kill.size, 20)
		eq(a.members["Aurel-TestRealm"].bosses, 3); eq(a.members["Bryn-TestRealm"].bosses, 2)
		eq(a.members["Dara-TestRealm"].bosses, 2); eq(a.members["Corin-TestRealm"].bosses, 1)
		isNil(N().Current(L, "S1"))
		eq(N().List(L, "S1")[1].closed, true)
		-- the kills are what the Progress tab reads (M3-3b)
		eq(Lg().FirstKills(L)[610], "2026-01-01")
	end)

	it("writes nothing for a kill in another instance, outside a night, or from a client that did not open the night", function()
		local L = bound()
		settle()
		raid("Aurel")
		Mock.encounter.End(610, "Lucifron", true)
		eq(#N().Kills(L), 0, "no night open: the kill is left to M3-3b")
		assert(NC():Open({}))
		Mock.encounter.Set({ instance = { name = "Onyxia's Lair", type = "raid", difficultyID = 14, difficultyName = "Normal",
			maxPlayers = 40, instanceID = 249 } })
		Mock.encounter.End(1084, "Onyxia", true)
		eq(#N().Kills(L), 0)
		Mock.encounter.Set({ instance = RAID_INSTANCE })
		-- a night another officer opened: this client does not run it
		assert(NC():Close())
		assert(N().Open(L, { author = "Bryn-TestRealm", ts = GetServerTime() + 1, season = "S1", date = "2026-01-01",
			instanceID = 409, difficulty = "normal" }))
		Mock.encounter.End(610, "Lucifron", true)
		eq(#N().Kills(L), 0)
		local e, code = NC():Sync()
		isNil(e); eq(code, "NOT_RUNNER")
		-- the master looter named in the night does run it
		assert(NC():Close())
		assert(N().Open(L, { author = "Bryn-TestRealm", ts = GetServerTime() + 2, season = "S1", date = "2026-01-01",
			instanceID = 409, difficulty = "normal", ml = ME }))
		Mock.encounter.End(610, "Lucifron", true)
		eq(#N().Kills(L), 1)
	end)

	it("records a boss once even when the end event comes twice", function()
		local L = bound()
		settle()
		raid("Aurel")
		assert(NC():Open({}))
		Mock.encounter.End(610, "Lucifron", true)
		Mock.encounter.End(610, "Lucifron", true)
		eq(#N().Kills(L), 1)
	end)

	it("announces the night, the lineup and the kills on the bus", function()
		bound()
		settle()
		local seen = {}
		for _, name in ipairs({ "NIGHT_OPENED", "NIGHT_CLOSED", "NIGHT_LINEUP_CHANGED", "NIGHT_ENCOUNTER_RECORDED" }) do
			FDCP.Bus:On(name, function() seen[#seen + 1] = name end)
		end
		raid("Aurel")
		assert(NC():Open({}))
		Mock.encounter.End(610, "Lucifron", true)
		assert(NC():Close())
		deepEq(seen, { "NIGHT_OPENED", "NIGHT_LINEUP_CHANGED", "NIGHT_ENCOUNTER_RECORDED", "NIGHT_CLOSED" })
	end)

	it("shows the attendance to officers only (view.attendance)", function()
		local L = bound()
		settle()
		raid("Aurel", "Bryn")
		assert(NC():Open({}))
		Mock.encounter.End(610, "Lucifron", true)
		local a = assert(NC():Attendance())
		eq(a.members["Aurel-TestRealm"].bosses, 1)
		local lineupLists, night = NC():Lineup()
		eq(night.size, 40); eq(#lineupLists.raid, 2)
		-- the player is demoted to a raider: the same ledger, no attendance
		Mock.guild.SetRank("Testchar", 3)
		settle()
		local none, code = NC():Attendance()
		isNil(none); eq(code, "RANK_TOO_LOW")
		local n
		n, code = NC():Close()
		isNil(n); eq(code, "RANK_TOO_LOW")
		isNil((N().List(L, "S1"))[1].closeId)
	end)

	it("a raider cannot open a night, and nothing is written while the guild roster loads", function()
		Mock.guild.Set({ name = "Keepers", ranks = RANKS, myRank = 3, members = { { name = "Aurel", rank = 0 } } })
		bound()
		settle()
		local n, code = NC():Open({ instanceID = 409, difficulty = "normal" })
		isNil(n); eq(code, "RANK_TOO_LOW")
		Mock.guild.Set({ name = "Keepers", ranks = RANKS, myRank = 1, loading = true, members = { { name = "Aurel", rank = 0 } } })
		Mock.Advance(1)
		-- the history of this session may still hold the old roster; a fresh bind has not read one yet
		FDCP.PermissionService:Bind()
		n, code = NC():Open({ instanceID = 409, difficulty = "normal" })
		isNil(n); eq(code, "PENDING")
	end)

	it("needs a season and a ledger", function()
		local L = Lg().New()
		NC():Bind(L)
		settle()
		local n, code = NC():Open({ instanceID = 409, difficulty = "normal" })
		isNil(n); eq(code, "NO_SEASON")
		isNil(NC():Current())
		_, code = NC():Attendance()
		eq(code, "NO_SEASON")
		_, code = NC():Close()
		eq(code, "NO_SEASON")
	end)

	it("keeps its ledger in the guild's saved data, and never writes a read-only database", function()
		settle()
		FDCP.Config:UpdateGuildKey()
		NC().ledger = nil
		local L = assert(NC():Ledger())
		eq(FDCP.Config:GuildData().ledger, L, "the ledger lives in the guild's saved table")
		eq(NC():Ledger(), L)
		NC().ledger = nil
		FDCP.Config.readOnly = true
		isNil(NC():Ledger())
		FDCP.Config.readOnly = false
	end)
end)
