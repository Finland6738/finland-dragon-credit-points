-- Season: a pack of raids with one credit table (docs/ANALISI.md §2, §3.1, §6). Pure Lua 5.1: it never calls the game.
--
-- A season is read from the ledger, never stored apart: SEASON_OPENED{label?, instances, startCredits} opens it and
-- SEASON_CLOSED{} closes it; both carry the season id in the envelope (`season`). The pack is the list of instances
-- released with one content update, each with its size (10, 20 or 40): every instance of the pack, every size and both
-- difficulties (Normal and Veteran) share **one** credit table, the season's. The difficulty is recorded on the night
-- (M3) for the history, it never splits the credits. `startCredits` is what a member present from the start begins
-- with (the "Patto" preset: 0, everyone starts again each season); it is written in SEASON_OPENED, so changing the
-- configuration later never changes an open season.
--
-- One season is open at a time: Season.Open refuses while another is open and never reuses an id. Two officers who
-- open seasons concurrently (merged later) cannot be prevented offline: the first SEASON_OPENED of an id in canonical
-- order is the one that counts, and Season.Current is the newest opened season that is not closed.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Season = {}
ns.Season, ns.modules.Season = Season, Season

local type, pairs, ipairs = type, pairs, ipairs

local function Ledger() return ns.Ledger end

-- The difficulties a season covers, all on the same credit table (§3.1 `season.difficultyTables`: one table).
Season.DIFFICULTIES = { normal = true, veteran = true }

-- The season configuration of the "Patto" preset (§3.1). A fresh copy on every call.
function Season.DefaultConfig()
	return { startCredits = 0 }
end

local function copyInstances(list)
	local out = {}
	for i, inst in ipairs(list or {}) do out[i] = { id = inst.id, size = inst.size } end
	return out
end

-- Every season of the ledger: { [id] = { id, label, instances, startCredits, openedAt, opened, closedAt, closed } }.
-- `opened` / `closed` are the ids of the events that count (the first of each in canonical order).
function Season.All(L)
	local out = {}
	local Lg = Ledger()
	for _, e in ipairs(Lg.Sorted(L, function(e) return e.type == "SEASON_OPENED" end)) do
		local p = Lg.Readable(e) and Lg.Payload(e)
		if p and not out[e.season] then
			out[e.season] = {
				id = e.season, label = p.label, instances = copyInstances(p.instances),
				startCredits = p.startCredits, openedAt = e.ts, opened = e.id,
			}
		end
	end
	-- Closes in a second pass: a close counts even when officers' clocks put it before the opening. A close whose
	-- opening has not arrived yet waits in the ledger until the opening is merged.
	for _, e in ipairs(Lg.Sorted(L, function(e) return e.type == "SEASON_CLOSED" end)) do
		local s = out[e.season]
		if s and not s.closed and Lg.Readable(e) then s.closedAt, s.closed = e.ts, e.id end
	end
	return out
end

-- One season, or nil.
function Season.Get(L, id)
	return Season.All(L)[id]
end

function Season.IsOpen(L, id)
	local s = Season.Get(L, id)
	return s ~= nil and not s.closed
end

-- The open season (the newest opened, when merges left more than one open), or nil.
function Season.Current(L)
	local best
	for _, s in pairs(Season.All(L)) do
		if not s.closed then
			local e = L.events[s.opened]
			if not best or Ledger().Before(L.events[best.opened], e) then best = s end
		end
	end
	return best
end

-- Seasons sorted by opening (oldest first), for the history and the export.
function Season.List(L)
	local list = {}
	for _, s in pairs(Season.All(L)) do list[#list + 1] = s end
	table.sort(list, function(a, b) return Ledger().Before(L.events[a.opened], L.events[b.opened]) end)
	return list
end

-- Opens a season. draft = { author, ts, season = id, label?, instances = {{id, size}}, startCredits? }; startCredits
-- defaults to config.startCredits (Season.DefaultConfig when config is nil). Returns the event, or nil and a code:
-- "SEASON_EXISTS", "SEASON_ALREADY_OPEN" or a Ledger.Append code.
function Season.Open(L, draft, config)
	if type(draft) ~= "table" then return nil, "event" end
	config = config or Season.DefaultConfig()
	if Season.Get(L, draft.season) then return nil, "SEASON_EXISTS" end
	if Season.Current(L) then return nil, "SEASON_ALREADY_OPEN" end
	local start = draft.startCredits
	if start == nil then start = config.startCredits or 0 end
	return Ledger().Append(L, {
		author = draft.author, ts = draft.ts, season = draft.season, type = "SEASON_OPENED",
		payload = { label = draft.label, instances = copyInstances(draft.instances), startCredits = start },
	})
end

-- Closes an open season. draft = { author, ts, season }. Returns the event, or nil and "SEASON_UNKNOWN",
-- "SEASON_CLOSED" or a Ledger.Append code.
function Season.Close(L, draft)
	if type(draft) ~= "table" then return nil, "event" end
	local s = Season.Get(L, draft.season)
	if not s then return nil, "SEASON_UNKNOWN" end
	if s.closed then return nil, "SEASON_CLOSED" end
	return Ledger().Append(L, { author = draft.author, ts = draft.ts, season = draft.season, type = "SEASON_CLOSED",
		payload = {} })
end

-- The size of an instance of the season's pack, or nil when the instance is not in the pack.
function Season.InstanceSize(season, instanceID)
	for _, inst in ipairs(season and season.instances or {}) do
		if inst.id == instanceID then return inst.size end
	end
end

-- The credit table a night in `instanceID` at `difficulty` uses: the season's id for every instance of the pack and
-- both difficulties (one table). Returns the id, or nil and "NOT_IN_PACK" / "DIFFICULTY".
function Season.CreditTable(season, instanceID, difficulty)
	if not Season.InstanceSize(season, instanceID) then return nil, "NOT_IN_PACK" end
	if not Season.DIFFICULTIES[difficulty] then return nil, "DIFFICULTY" end
	return season.id
end

-- The number of official nights opened in the season (NIGHT_OPENED events, M3). A member who joins after the first
-- night is a late joiner (Members.Join).
function Season.NightCount(L, id)
	local n = 0
	for _, e in pairs(L.events) do
		if e.type == "NIGHT_OPENED" and e.season == id and Ledger().Readable(e) then n = n + 1 end
	end
	return n
end

if ns.addon then ns.addon.Season = Season end   -- also reachable from tests
