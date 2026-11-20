-- Nights: an official raid night, its lineup and the attendance per boss (docs/ANALISI.md §2, §6, §3.1). Pure Lua 5.1: it
-- never calls the game. It sits on top of Domain/Season.lua (the pack of official raids) and Domain/Roster.lua (the pool and
-- its mains and alts); nothing here counts credits (the rotation never penalizes: §6, owner decision).
--
-- Read from the ledger, never stored apart:
--   NIGHT_OPENED{date, instanceID, size, difficulty, faction?, ml?}  a night of the season starts. `date` is the realm's
--       calendar day (YYYY-MM-DD, what the community site shows), `instanceID` an instance of the season's pack (only
--       official raids count: Nights.Open refuses any other), `size` the pack's size for it (10, 20 or 40), `difficulty`
--       `normal` or `veteran` (recorded for the history; both share the one credit table, §3.1), `faction` the client's
--       faction token of the player who opened it (a pool main of the other faction is not "absent" from this night) and
--       `ml` the master looter when it is not the officer who opened it. One night is open per season at a time.
--   NIGHT_CLOSED{night?}  the night is over (`night` = the id of the NIGHT_OPENED it closes; without it, the newest night
--       opened before the close that is still open).
--   LINEUP_CHANGED{night, boss?, raid?, bench?, absent?}  a change of the lineup: the lists of members who are now RAID
--       (in the raid group, playing), BENCH (benched by the master looter, not playing) or ABSENT (neither). Only the members
--       that changed are written, in one event, so a raid forming costs one event and not forty. `boss` is the boss of
--       reference: the encounter id of the last boss killed in the night before the change (nil before the first kill), so
--       the log says "this change came after that boss". A member with no entry is ABSENT.
--   ENCOUNTER_KILLED{encounterID, difficulty?, time?, date?, night?, instanceID?, size?}  a boss was killed (from
--       ENCOUNTER_END with success). `difficulty` is the client's difficultyID, `time` the server time, `size` the group
--       size. Inside a night it carries `night`; outside one (M3-3b, the first kills of the Progress tab) there is none.
--
-- Attendance per boss: a boss counts as attended by every member whose lineup state is RAID **at the moment of the kill**
-- (the lineup events that come before the kill in the ledger's canonical order). Someone who dies or disconnects but stays
-- in the raid is present; someone who joins after the pull and is in the raid at the kill is present too. Several officers
-- in the raid may each write the same kill: the first one of an encounter in a night counts, the others are ignored, so a
-- merge is idempotent. Attendance is for the officers only (`view.attendance`, §6): the service that shows it checks the
-- permission, and nothing public exports it.
--
-- A fixed table of difficulties (Nights.DIFFICULTY_IDS) turns the client's difficultyID into `normal` or `veteran`; it is a
-- guess until the spike names the real ids on WoW Forever, and the officer can always choose the difficulty by hand.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Nights = {}
ns.Nights, ns.modules.Nights = Nights, Nights

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local floor, sort = math.floor, table.sort

local function Ledger() return ns.Ledger end
local function Season() return ns.Season end
local function Roster() return ns.Roster end

Nights.STATES = { RAID = true, BENCH = true, ABSENT = true }
Nights.MAX_LINEUP = 200   -- members in one LINEUP_CHANGED

-- The client's difficultyID -> difficulty code. [verify] on WoW Forever (spike): 14 is Normal in the retail ids; Veteran
-- is the next one in this table until the spike names it. The name the client gives (Nights.DifficultyCode) is looked at
-- first.
Nights.DIFFICULTY_IDS = { [14] = "normal", [15] = "veteran" }

local function isName(s) return type(s) == "string" and s ~= "" and not s:find(":", 1, true) end
local function isInt(n) return type(n) == "number" and n == floor(n) and n > -math.huge and n < math.huge end
local function isNum(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end

-- "YYYY-MM-DD" with a month 1-12 and a day 1-31.
function Nights.ValidDate(s)
	if type(s) ~= "string" then return false end
	local y, m, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not y then return false end
	m, d = tonumber(m), tonumber(d)
	return m >= 1 and m <= 12 and d >= 1 and d <= 31
end

-- The realm's day number YYYYMMDD as "YYYY-MM-DD".
function Nights.FormatDay(day)
	if type(day) ~= "number" then return nil end
	return ("%04d-%02d-%02d"):format(floor(day / 10000), floor(day / 100) % 100, day % 100)
end

-- The difficulty code of a night from what the client says about the instance: the difficulty name when it says
-- "veteran" / "normal" (any language the guild may have: veterano / normale), else the id table, else nil.
function Nights.DifficultyCode(difficultyID, difficultyName)
	if type(difficultyName) == "string" then
		local n = difficultyName:lower()
		if n:find("veteran", 1, true) then return "veteran" end
		if n:find("normal", 1, true) then return "normal" end
	end
	return Nights.DIFFICULTY_IDS[difficultyID]
end

---------------------------------------------------------------------------------------------------------------------
-- Ledger checks

local function nameList(list)
	if type(list) ~= "table" then return nil end
	local n = 0
	for i, name in pairs(list) do
		if type(i) ~= "number" or not isName(name) then return nil end
		n = n + 1
	end
	if n ~= #list then return nil end
	return n
end

do
	local CHECKS = Ledger().CHECKS
	local baseKill = CHECKS.ENCOUNTER_KILLED

	CHECKS.NIGHT_OPENED = function(p)
		if not Nights.ValidDate(p.date) then return "date" end
		if not isInt(p.instanceID) or p.instanceID <= 0 then return "instanceID" end
		if not Ledger().RAID_SIZES[p.size] then return "size" end
		if not Season().DIFFICULTIES[p.difficulty] then return "difficulty" end
		if p.faction ~= nil and not Ledger().FACTIONS[p.faction] then return "faction" end
		if p.ml ~= nil and not isName(p.ml) then return "ml" end
	end

	CHECKS.NIGHT_CLOSED = function(p)
		if p.night ~= nil and not Ledger().SplitId(p.night) then return "night" end
	end

	CHECKS.ENCOUNTER_KILLED = function(p)
		local bad = baseKill(p)
		if bad then return bad end
		if p.difficulty ~= nil and (not isInt(p.difficulty) or p.difficulty < 0) then return "difficulty" end
		if p.time ~= nil and (not isNum(p.time) or p.time < 0) then return "time" end
		if p.night ~= nil and not Ledger().SplitId(p.night) then return "night" end
		if p.instanceID ~= nil and (not isInt(p.instanceID) or p.instanceID <= 0) then return "instanceID" end
		if p.size ~= nil and (not isInt(p.size) or p.size <= 0) then return "size" end
	end

	CHECKS.LINEUP_CHANGED = function(p)
		if not Ledger().SplitId(p.night) then return "night" end
		if p.boss ~= nil and (not isInt(p.boss) or p.boss <= 0) then return "boss" end
		local seen, total = {}, 0
		for _, state in ipairs({ "raid", "bench", "absent" }) do
			if p[state] ~= nil then
				local n = nameList(p[state])
				if not n then return state end
				for _, name in ipairs(p[state]) do
					if seen[name] then return state end
					seen[name] = true
				end
				total = total + n
			end
		end
		if total == 0 or total > Nights.MAX_LINEUP then return "lineup" end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Reading

local function readable(L, e)
	local Lg = Ledger()
	return Lg.Readable(e) and Lg.Payload(e) or nil
end

-- Every night of a season in the order they were opened:
-- { id, season, date, instanceID, size, difficulty, faction, ml, author, openedAt, closed, closedAt, closeId }.
-- A close counts for the night it names, or for the newest night opened before it that is still open; a close whose
-- night has not been merged yet stays in the ledger and counts once it has.
function Nights.List(L, season)
	local Lg = Ledger()
	local list, byId = {}, {}
	for _, e in ipairs(Lg.Sorted(L, function(e) return e.season == season and e.type == "NIGHT_OPENED" end)) do
		local p = readable(L, e)
		if p then
			local n = { id = e.id, season = season, date = p.date, instanceID = p.instanceID, size = p.size,
				difficulty = p.difficulty, faction = p.faction, ml = p.ml, author = e.author, openedAt = e.ts,
				closed = false }
			list[#list + 1] = n
			byId[e.id] = n
		end
	end
	for _, e in ipairs(Lg.Sorted(L, function(e) return e.season == season and e.type == "NIGHT_CLOSED" end)) do
		local p = readable(L, e)
		if p then
			local target = p.night and byId[p.night]
			if not p.night then
				for _, n in ipairs(list) do
					if not n.closed and Lg.Before(L.events[n.id], e) then target = n end
				end
			end
			if target and not target.closed then
				target.closed, target.closedAt, target.closeId = true, e.ts, e.id
			end
		end
	end
	return list
end

-- One night by the id of its NIGHT_OPENED, or nil.
function Nights.Get(L, id)
	local e = L.events[id]
	if not e or e.type ~= "NIGHT_OPENED" or e.season == nil then return nil end
	for _, n in ipairs(Nights.List(L, e.season)) do
		if n.id == id then return n end
	end
	return nil
end

-- The open night of a season (the newest opened, when merges left more than one open), or nil.
function Nights.Current(L, season)
	local best
	for _, n in ipairs(Nights.List(L, season)) do
		if not n.closed then best = n end
	end
	return best
end

-- True when `at` (an event) falls inside night `n`: after its opening and before its closing in canonical order.
local function inside(L, n, at)
	local Lg = Ledger()
	if not Lg.Before(L.events[n.id], at) then return false end
	if n.closed and not Lg.Before(at, L.events[n.closeId]) then return false end
	return true
end

-- The kills of the ledger, oldest first: { id, season, encounterID, difficulty, time, date, instanceID, size, author, ts,
-- night }. `night` is the night the kill belongs to (its `night` field, else the night open when it was written in the same instance), nil
-- for a kill outside any night. Inside a night, the first kill of an encounter counts and the same encounter written
-- again by another officer is dropped. opts = { season?, night? (id), encounterID? }.
function Nights.Kills(L, opts)
	opts = opts or {}
	local Lg = Ledger()
	local nightsOf = {}
	local function nightsOfSeason(season)
		if not nightsOf[season] then nightsOf[season] = Nights.List(L, season) end
		return nightsOf[season]
	end
	local out, seen = {}, {}
	for _, e in ipairs(Lg.Sorted(L, function(e)
		return e.type == "ENCOUNTER_KILLED" and (opts.season == nil or e.season == opts.season)
	end)) do
		local p = readable(L, e)
		if p and (opts.encounterID == nil or p.encounterID == opts.encounterID) then
			local night = p.night
			if not night and e.season ~= nil then
				for _, n in ipairs(nightsOfSeason(e.season)) do
					if inside(L, n, e) and (p.instanceID == nil or p.instanceID == n.instanceID) then night = n.id end
				end
			end
			local key = night and (night .. "#" .. p.encounterID)
			if (opts.night == nil or night == opts.night) and not (key and seen[key]) then
				if key then seen[key] = true end
				out[#out + 1] = { id = e.id, season = e.season, encounterID = p.encounterID, difficulty = p.difficulty,
					time = p.time, date = p.date, instanceID = p.instanceID, size = p.size, author = e.author, ts = e.ts,
					night = night }
			end
		end
	end
	return out
end

-- { [encounterID] = { kill, ... } }: every kill of an encounter in canonical order, inside a night or not (what the
-- Progress tab of M3-3b reads: the first kill of a boss is the oldest of these).
function Nights.KillsByEncounter(L, season)
	local out = {}
	for _, k in ipairs(Nights.Kills(L, { season = season })) do
		local list = out[k.encounterID]
		if not list then list = {}; out[k.encounterID] = list end
		list[#list + 1] = k
	end
	return out
end

local function applyLineup(states, p)
	for _, state in ipairs({ "RAID", "BENCH", "ABSENT" }) do
		for _, name in ipairs(p[state:lower()] or {}) do states[name] = state end
	end
end

-- The lineup of a night: { [member] = "RAID" | "BENCH" | "ABSENT" } for every member a LINEUP_CHANGED mentioned (a member
-- not in it is ABSENT). opts.at = an event: only the changes before it in canonical order count (the lineup at that moment).
function Nights.Lineup(L, nightId, opts)
	local Lg = Ledger()
	local night = L.events[nightId]
	local states = {}
	if not night then return states end
	local at = opts and opts.at
	for _, e in ipairs(Lg.Sorted(L, function(e)
		return e.type == "LINEUP_CHANGED" and e.season == night.season
	end)) do
		local p = readable(L, e)
		if p and p.night == nightId and (not at or Lg.Before(e, at)) then applyLineup(states, p) end
	end
	return states
end

-- The lists of a lineup: { raid = {sorted}, bench = {sorted}, absent = {sorted} } (absent = the explicit ones only).
function Nights.Lists(states)
	local out = { raid = {}, bench = {}, absent = {} }
	for name, state in pairs(states) do
		local list = out[state:lower()]
		if list then list[#list + 1] = name end
	end
	sort(out.raid); sort(out.bench); sort(out.absent)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Attendance

-- The pool at a moment: the members of the season who had joined by `ts`, play (not inactive) and belong to the night's
-- faction (a member without a faction counts for every night).
local function poolAt(L, rs, night, ts)
	local out = {}
	for name, m in pairs(rs.members) do
		local je = L.events[m.joined]
		if je and je.ts <= ts and m.status ~= "INACTIVE" and (not night.faction or not m.faction or m.faction == night.faction) then
			out[#out + 1] = name
		end
	end
	return out
end

local function snapshot(L, rs, night, states, ts)
	local raid, bench, absent, listed = {}, {}, {}, {}
	for name, state in pairs(states) do
		if state == "RAID" then raid[#raid + 1] = name; listed[name] = true
		elseif state == "BENCH" then bench[#bench + 1] = name; listed[name] = true end
	end
	for _, name in ipairs(poolAt(L, rs, night, ts)) do
		if not listed[name] then absent[#absent + 1] = name end
	end
	sort(raid); sort(bench); sort(absent)
	return { raid = raid, bench = bench, absent = absent }
end

-- The attendance of a season, per night and per boss:
--   { season, nights = { { night, kills = { { kill, raid, bench, absent } }, final = { raid, bench, absent },
--       played = { [member] = true }, benched = { [member] = true } } }, members = { [member] = { nights, played,
--       benched, bosses, possible } } }
-- `raid` / `bench` / `absent` are sorted lists of members at the moment of each kill (absent = the pool of that moment
-- that was neither in the raid nor benched); `final` is the lineup at the end. A member **played** a night when they were
-- in the raid at some moment of it, **benched** when they were benched and never played; `bosses` counts the kills
-- they attended and `possible` the kills they could have (they were in the pool, playing, of that faction).
-- opts = { night? = id }: one night only.
function Nights.Attendance(L, season, opts)
	opts = opts or {}
	local Lg = Ledger()
	local rs = Roster().State(L, season)
	local result = { season = season, nights = {}, members = {} }
	local lineups = {}
	for _, e in ipairs(Lg.Sorted(L, function(e) return e.type == "LINEUP_CHANGED" and e.season == season end)) do
		local p = readable(L, e)
		if p then
			local list = lineups[p.night]
			if not list then list = {}; lineups[p.night] = list end
			list[#list + 1] = { e = e, p = p }
		end
	end
	local function member(name)
		local m = result.members[name]
		if not m then
			m = { nights = 0, played = 0, benched = 0, bosses = 0, possible = 0 }
			result.members[name] = m
		end
		return m
	end
	for _, night in ipairs(Nights.List(L, season)) do
		if opts.night == nil or opts.night == night.id then
			local rec = { night = night, kills = {}, played = {}, benched = {}, everBench = {} }
			local states, evs, i = {}, lineups[night.id] or {}, 1
			local function advance(upTo)
				while evs[i] and (upTo == nil or Lg.Before(evs[i].e, upTo)) do
					applyLineup(states, evs[i].p)
					for _, name in ipairs(evs[i].p.raid or {}) do rec.played[name] = true end
					for _, name in ipairs(evs[i].p.bench or {}) do rec.everBench[name] = true end
					i = i + 1
				end
			end
			for _, kill in ipairs(Nights.Kills(L, { season = season, night = night.id })) do
				local ke = L.events[kill.id]
				advance(ke)
				local snap = snapshot(L, rs, night, states, ke.ts)
				snap.kill = kill
				rec.kills[#rec.kills + 1] = snap
				for _, name in ipairs(snap.raid) do member(name).bosses = member(name).bosses + 1; member(name).possible = member(name).possible + 1 end
				for _, name in ipairs(snap.bench) do member(name).possible = member(name).possible + 1 end
				for _, name in ipairs(snap.absent) do member(name).possible = member(name).possible + 1 end
			end
			advance(nil)
			rec.final = snapshot(L, rs, night, states, night.closedAt or math.huge)
			for name in pairs(rec.played) do
				local m = member(name)
				m.nights, m.played = m.nights + 1, m.played + 1
			end
			for name in pairs(rec.everBench) do
				if not rec.played[name] then
					rec.benched[name] = true
					local m = member(name)
					m.nights, m.benched = m.nights + 1, m.benched + 1
				end
			end
			rec.everBench = nil
			result.nights[#result.nights + 1] = rec
		end
	end
	return result
end

-- The nights each member played in the season: { [member] = n }. This is the `nights` table of Members.LateJoinCredits
-- (the "members with at least minNights nights" basis of the late joiners' initial credits, §3.5).
function Nights.Played(L, season)
	local out = {}
	for name, m in pairs(Nights.Attendance(L, season).members) do out[name] = m.played end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Writing (an officer, night.run)

local function seasonOpen(L, season)
	local s = Season().Get(L, season)
	if not s then return nil, "SEASON_UNKNOWN" end
	if s.closed then return nil, "SEASON_CLOSED" end
	return s
end

-- Opens an official night. draft = { author, ts, season, date, instanceID, difficulty, size?, faction?, ml? }; `size`
-- defaults to the pack's size for the instance and has to match it. Returns the NIGHT_OPENED event, or nil and a code:
-- "SEASON_UNKNOWN", "SEASON_CLOSED", "NOT_IN_PACK" (not an official raid of the season), "SIZE", "DIFFICULTY",
-- "NIGHT_ALREADY_OPEN" or a Ledger.Append code ("date", "faction", ...). `opts` goes to Ledger.Append (the trust gate).
function Nights.Open(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	local s, why = seasonOpen(L, draft.season)
	if not s then return nil, why end
	local packSize = Season().InstanceSize(s, draft.instanceID)
	if not packSize then return nil, "NOT_IN_PACK" end
	if draft.size ~= nil and draft.size ~= packSize then return nil, "SIZE" end
	if not Season().DIFFICULTIES[draft.difficulty] then return nil, "DIFFICULTY" end
	if Nights.Current(L, draft.season) then return nil, "NIGHT_ALREADY_OPEN" end
	return Ledger().Append(L, { author = draft.author, ts = draft.ts, season = draft.season, type = "NIGHT_OPENED",
		payload = { date = draft.date, instanceID = draft.instanceID, size = packSize, difficulty = draft.difficulty,
			faction = draft.faction, ml = draft.ml } }, opts)
end

-- Closes the open night of the season. draft = { author, ts, season }. Returns the NIGHT_CLOSED event, or nil and
-- "SEASON_UNKNOWN", "NO_NIGHT_OPEN" or a Ledger.Append code.
function Nights.Close(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	if not Season().Get(L, draft.season) then return nil, "SEASON_UNKNOWN" end
	local night = Nights.Current(L, draft.season)
	if not night then return nil, "NO_NIGHT_OPEN" end
	return Ledger().Append(L, { author = draft.author, ts = draft.ts, season = draft.season, type = "NIGHT_CLOSED",
		payload = { night = night.id } }, opts)
end

-- The last boss killed in a night up to time `ts` (an encounter id), or nil: the boss of reference of a lineup change.
local function lastBoss(L, season, nightId, ts)
	local best
	for _, k in ipairs(Nights.Kills(L, { season = season, night = nightId })) do
		if k.ts <= ts then best = k.encounterID end
	end
	return best
end

-- Changes the lineup of the open night. draft = { author, ts, season, raid? = {members}, bench?, absent? }: a member
-- goes to the state of the list they are in; the ones already in that state are left out, so only real changes are
-- written (one event for all of them). Every member has to be a main of the pool (an alt is resolved by the caller).
-- Returns the LINEUP_CHANGED event, or nil and a code: "SEASON_UNKNOWN", "NO_NIGHT_OPEN", "NOT_MEMBER", "NO_CHANGE" or
-- a Ledger.Append code. `opts` goes to Ledger.Append.
function Nights.SetLineup(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	if not Season().Get(L, draft.season) then return nil, "SEASON_UNKNOWN" end
	local night = Nights.Current(L, draft.season)
	if not night then return nil, "NO_NIGHT_OPEN" end
	local rs = Roster().State(L, draft.season)
	local states = Nights.Lineup(L, night.id)
	local payload, count, seen = { night = night.id }, 0, {}
	for _, state in ipairs({ "RAID", "BENCH", "ABSENT" }) do
		local key = state:lower()
		for _, name in ipairs(draft[key] or {}) do
			if not rs.members[name] then return nil, "NOT_MEMBER" end
			if not seen[name] then
				seen[name] = true
				if (states[name] or "ABSENT") ~= state then
					payload[key] = payload[key] or {}
					payload[key][#payload[key] + 1] = name
					count = count + 1
				end
			end
		end
	end
	if count == 0 then return nil, "NO_CHANGE" end
	for _, key in ipairs({ "raid", "bench", "absent" }) do
		if payload[key] then sort(payload[key]) end
	end
	payload.boss = lastBoss(L, draft.season, night.id, draft.ts)
	return Ledger().Append(L, { author = draft.author, ts = draft.ts, season = draft.season, type = "LINEUP_CHANGED",
		payload = payload }, opts)
end

-- Records a boss kill. draft = { author, ts, season, encounterID, difficulty?, time?, size?, date?, instanceID? }.
-- Inside the open night's instance it belongs to the night (`night` is written); with no night open, or in another
-- instance, it is a kill outside a night (M3-3b: the first kills of the Progress tab). A night's boss is recorded once:
-- "ALREADY_KILLED". Returns the ENCOUNTER_KILLED event, or nil and a code ("SEASON_UNKNOWN", "SEASON_CLOSED",
-- "ALREADY_KILLED" or a Ledger.Append code). `opts` goes to Ledger.Append.
function Nights.Kill(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	local s, why = seasonOpen(L, draft.season)
	if not s then return nil, why end
	local night = Nights.Current(L, draft.season)
	if night and draft.instanceID ~= nil and draft.instanceID ~= night.instanceID then night = nil end
	if night then
		if #Nights.Kills(L, { season = draft.season, night = night.id, encounterID = draft.encounterID }) > 0 then
			return nil, "ALREADY_KILLED"
		end
	end
	return Ledger().Append(L, { author = draft.author, ts = draft.ts, season = draft.season, type = "ENCOUNTER_KILLED",
		payload = { encounterID = draft.encounterID, difficulty = draft.difficulty, time = draft.time or draft.ts,
			date = draft.date, night = night and night.id or nil, instanceID = draft.instanceID or (night and night.instanceID),
			size = draft.size } }, opts)
end

if ns.addon then ns.addon.Nights = Nights end   -- also reachable from tests
