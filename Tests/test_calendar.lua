-- The calendar and the planned bench on the mock client (M3-4): Adapters/Calendar.lua reads the official raid event and
-- who signed up (through Compat), App/NightController.lua links a night to the event and answers "who to bench" from
-- Domain/Rotation.lua; the master looter decides and ApplyBench writes it.
local function Lg() return FDCP.Ledger end
local function Sn() return FDCP.Season end
local function N() return FDCP.Nights end
local function R() return FDCP.Roster end
local function NC() return FDCP.NightController end
local function Cal() return FDCP.Calendar end

local ME = "Testchar-TestRealm"
local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }
local TEN_MAN = { name = "Karazhan", type = "raid", difficultyID = 14, difficultyName = "Normal", maxPlayers = 10,
	instanceID = 531 }

local function guild(myRank)
	return function(Mock)
		Mock.guild.Set({ name = "Keepers", ranks = RANKS, myRank = myRank or 1, members = {
			{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
		} })
	end
end

local function settle() Mock.Advance(3) end

-- The calendar of the test: January 2026 (the mock client's clock says 2026-01-01).
local function calendar(events)
	Mock.calendar.Set{ opened = true, month = { month = 1, year = 2026, numDays = 31, firstWeekday = 4 }, events = events or {} }
end

local function raidEvent(extra)
	local e = { title = "Raid night", eventType = 0, calendarType = "GUILD_EVENT", eventID = 2001, invites = {} }
	for k, v in pairs(extra or {}) do e[k] = v end
	return e
end

local function eventCount(L) local n = 0; for _ in pairs(L.events) do n = n + 1 end; return n end
local function has(list, name) for _, v in ipairs(list) do if v == name then return true end end return false end

-- Twelve raiders of the ten-player raid (531): T1 T2 tanks, H1..H3 healers, D1..D7 damage dealers; every name "-TestRealm".
local function bound()
	local L = Lg().New()
	assert(Sn().Open(L, { author = "Aurel-TestRealm", ts = 1, season = "S1", instances = { { id = 531, size = 10 } } }))
	local specs = {}
	for i = 1, 2 do specs[#specs + 1] = { "T" .. i, 73 } end
	for i = 1, 3 do specs[#specs + 1] = { "H" .. i, 257 } end
	for i = 1, 7 do specs[#specs + 1] = { "D" .. i, 72 } end
	for i, s in ipairs(specs) do
		assert(R().Join(L, { author = "Bryn-TestRealm", ts = 1 + i, season = "S1", member = s[1] .. "-TestRealm",
			faction = "Horde", ms1 = s[2] }))
	end
	NC():Bind(L)
	Mock.encounter.Set({ instance = TEN_MAN })
	return L
end

local function short(list)
	local out = {}
	for i, n in ipairs(list) do out[i] = n:gsub("%-TestRealm$", "") end
	return out
end

describe("the calendar adapter", function()
	before_boot(guild(1))

	it("asks the client to load the calendar at login and announces when it has data", function()
		truthy(Mock.calendar.opened)
		local loaded = 0
		FDCP.Bus:On("CALENDAR_LOADED", function() loaded = loaded + 1 end)
		Mock.Fire("CALENDAR_UPDATE_EVENT_LIST")
		eq(loaded, 1)
	end)

	it("counts the months from the one the calendar shows", function()
		local shown = { month = 1, year = 2026 }
		eq(Cal().MonthOffset(shown, 20260101), 0)
		eq(Cal().MonthOffset(shown, 20260331), 2)
		eq(Cal().MonthOffset(shown, 20251231), -1)
		eq(Cal().MonthOffset({ month = 12, year = 2025 }, 20260102), 1)
		isNil(Cal().MonthOffset(nil, 20260101))
		isNil(Cal().MonthOffset(shown, 20261301))
	end)

	it("lists the raid events of a day, the guild's own first, and ignores everything else", function()
		calendar({ [1] = {
			raidEvent({ title = "Player raid", calendarType = "PLAYER", eventID = 2000 }),
			raidEvent({ title = "Guild raid", eventID = 2001 }),
			raidEvent({ title = "Dinner", eventType = 4, eventID = 2002 }),
			raidEvent({ title = "Holiday", calendarType = "HOLIDAY", eventID = 2003 }),
			raidEvent({ title = "Reset", calendarType = "RAID_RESET", eventID = 2004 }),
		}, [2] = { raidEvent({ eventID = 2010 }) } })
		local list = Cal().RaidEvents(20260101)
		eq(#list, 2)
		eq(list[1].eventID, 2001); eq(list[1].guild, true); eq(list[1].index, 2); eq(list[1].offset, 0); eq(list[1].day, 20260101)
		eq(list[2].eventID, 2000); eq(list[2].guild, false)
		local first, n = Cal().FindRaidEvent(20260101)
		eq(first.eventID, 2001); eq(n, 2)
		local none, zero = Cal().FindRaidEvent(20260105)
		isNil(none); eq(zero, 0)
		deepEq(Cal().RaidEvents("x"), {})
	end)

	it("reads nothing before the calendar is loaded, and nothing when the month is unknown", function()
		calendar({ [1] = { raidEvent() } })
		Mock.calendar.opened = false
		deepEq(Cal().RaidEvents(20260101), {})
		Cal().Request()
		eq(#Cal().RaidEvents(20260101), 1)
	end)

	it("reads the sign-ups as Name-Realm answers and closes the event again", function()
		calendar({ [1] = { raidEvent({ invites = {
			{ name = "Aurel", inviteStatus = 1 }, { name = "Bryn", inviteStatus = 3 }, { name = "Corin", inviteStatus = 6 },
			{ name = "D1", inviteStatus = 8 }, { name = "D2", inviteStatus = 5 },
			{ name = "D3", inviteStatus = 2 }, { name = "D4", inviteStatus = 4 },
			{ name = "D5", inviteStatus = 0 }, { name = "D6", inviteStatus = 7 }, { name = "Far-Other Realm", inviteStatus = 1 },
		} }) } })
		local signups, read = Cal().Signups(Cal().FindRaidEvent(20260101))
		eq(read, 10)
		deepEq(signups, { ["Aurel-TestRealm"] = "yes", ["Bryn-TestRealm"] = "yes", ["Corin-TestRealm"] = "yes",
			["D1-TestRealm"] = "maybe", ["D2-TestRealm"] = "maybe", ["D3-TestRealm"] = "no", ["D4-TestRealm"] = "no",
			["Far-OtherRealm"] = "yes" })   -- not answered (invited / not signed up): not in the table
		isNil(Mock.calendar.openEvent)
		isNil(Cal().Signups(nil))
		isNil(Cal().Signups({ offset = 0, day = 20260104, index = 1 }))
	end)
end)

describe("a night linked to the calendar", function()
	before_boot(guild(1))

	it("is linked to the official raid event of today when there is one", function()
		local L = bound()
		calendar({ [1] = { raidEvent({ eventID = 777 }) } })
		settle()
		local night = assert(NC():Open({}))
		eq(night.eventID, 777)
		eq(N().Get(L, night.id).eventID, 777)
	end)

	it("opens without a link when the calendar has no raid event, and a given event wins", function()
		local L = bound()
		calendar({ [1] = { raidEvent({ title = "Dinner", eventType = 4 }) } })
		settle()
		local night = assert(NC():Open({}))
		isNil(night.eventID)
		assert(NC():Close())
		local linked = assert(NC():Open({ eventID = 55 }))
		eq(linked.eventID, 55)
		assert(NC():Close())
		local bad, code = NC():Open({ eventID = -3 })
		isNil(bad); eq(code, "payload:eventID")
		isNil(N().Current(L, "S1"))
	end)
end)

describe("proposing and applying a bench", function()
	before_boot(guild(1))

	it("proposes the bench for a night about to start and writes nothing", function()
		local L = bound()
		settle()
		local before = eventCount(L)
		local p = assert(NC():ProposeBench({ instanceID = 531 }))
		eq(p.slots, 10); eq(p.candidates, 12); eq(#p.bench, 2); eq(#p.raid, 10)
		isNil(p.event); isNil(p.signups)
		eq(eventCount(L), before)
		-- the minimums of the preset (2 tanks, 4 healers) cannot hold with 3 healers: the minimum is capped by who exists
		for _, n in ipairs(p.bench) do truthy(n:find("^D")) end
		deepEq(p.warnings, {})
	end)

	it("uses the calendar's sign-ups: a decline is left out, a tentative answer sits out first", function()
		local L = bound()
		calendar({ [1] = { raidEvent({ invites = { { name = "D1", inviteStatus = 2 }, { name = "D7", inviteStatus = 8 },
			{ name = "H1", inviteStatus = 1 } } }) } })
		settle()
		local p = assert(NC():ProposeBench({ instanceID = 531 }))
		eq(p.event.eventID, 2001)
		eq(p.excluded["D1-TestRealm"], "DECLINED")
		eq(p.candidates, 11)
		eq(#p.bench, 1)
		eq(p.bench[1], "D7-TestRealm"); eq(p.why["D7-TestRealm"], "MAYBE")
		local blind = assert(NC():ProposeBench({ instanceID = 531, useCalendar = false }))
		isNil(blind.event)
		eq(blind.candidates, 12)
	end)

	it("lets the master looter decide: ApplyBench writes the bench in one change, and the open night is proposed again the same", function()
		local L = bound()
		settle()
		assert(NC():Open({ instanceID = 531, difficulty = "normal" }))
		local p = assert(NC():ProposeBench({}))
		eq(p.slots, 10); eq(#p.bench, 2)
		local before = eventCount(L)
		local event = assert(NC():ApplyBench(p.bench))
		eq(event.type, "LINEUP_CHANGED")
		eq(eventCount(L), before + 1)
		deepEq(short(N().Lists(N().Lineup(L, N().Current(L, "S1").id)).bench), short(p.bench))
		local again = assert(NC():ProposeBench({}))
		deepEq(again.bench, p.bench)
		local none, code = NC():ApplyBench(p.bench)
		isNil(none); eq(code, "NO_CHANGE")
		none, code = NC():ApplyBench({ "Nobody" })
		isNil(none); eq(code, "NOT_MEMBER")
	end)

	it("applies a bench only to an open night", function()
		bound()
		settle()
		local e, code = NC():ApplyBench({ "D1" })
		isNil(e); eq(code, "NO_NIGHT_OPEN")
	end)

	it("takes the proposal's volunteers and kept members from the master looter", function()
		bound()
		settle()
		local p = assert(NC():ProposeBench({ instanceID = 531, volunteers = { "D6-TestRealm" }, keep = { "D1-TestRealm", "D2-TestRealm" } }))
		truthy(has(p.bench, "D6-TestRealm")); eq(p.why["D6-TestRealm"], "VOLUNTEER")
		falsy(has(p.bench, "D1-TestRealm")); falsy(has(p.bench, "D2-TestRealm"))
	end)

	it("needs an official instance when no night is open, a season and the right to run a night", function()
		bound()
		settle()
		local p, code = NC():ProposeBench({})
		isNil(p); eq(code, "NOT_IN_PACK")
		p, code = NC():ProposeBench({ instanceID = 409 })
		eq(code, "NOT_IN_PACK")
		Mock.guild.SetRank("Testchar", 3)
		settle()
		p, code = NC():ProposeBench({ instanceID = 531 })
		isNil(p); eq(code, "RANK_TOO_LOW")
		local empty = Lg().New()
		NC():Bind(empty)
		p, code = NC():ProposeBench({ instanceID = 531 })
		eq(code, "NO_SEASON")
	end)
end)
