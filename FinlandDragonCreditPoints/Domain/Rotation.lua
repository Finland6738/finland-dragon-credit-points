-- Rotation: who the addon proposes to bench in a night, and what a bench does to the credits (docs/ANALISI.md §6, §3.1,
-- M3-4). Pure Lua 5.1: it never calls the game. It reads the pool from Domain/Roster.lua and the history of benches from
-- Domain/Nights.lua; nothing is stored apart and nothing is written here: the proposal is a **suggestion**, the master
-- looter decides the bench (guild rule) and writes it with the night's lineup (NightController:Bench / Open{bench}).
--
-- The guild's rule is that the rotation never penalizes: the preset's `bench.creditEffect` is "none" (somebody who plays
-- less accumulates fewer credits, so they already have the precedence). Other guilds can choose "bonus" or "malus"
-- (Rotation.CreditEffect), which the credits table of a later step adds to the ledger's credits.
--
-- The proposal (Rotation.Propose):
--   * Who is in the running (the candidates): the pool's mains that play (ACTIVE or TRIAL, not INACTIVE) and are of the
--     night's faction (a member without a faction counts for every night), minus the ones who are not coming: a calendar
--     sign-up of "no" (declined / out) and, unless `useAvailability = false`, a declared availability that leaves the
--     night's weekday out (a member with no declared days is available every day). They are not benched: they are not
--     there. `opts.exclude` is the list the master looter adds by hand.
--   * How many sit out: candidates minus the raid size (10, 20 or 40: the night's `size`); with fewer candidates than
--     places nobody is benched and `short` says how many places stay empty.
--   * Who sits out, in this order (the first that can be spared goes first): the volunteers (they asked for it), then
--     the members whose calendar answer is "maybe" (tentative / standby: they have not confirmed), then the ones with the
--     **fewest benches** in the season (so everybody sits out about as often), then the ones who **played the most**
--     nights, then the name (so the same ledger gives the same proposal on every client).
--   * Role minimums: a tank or a healer is skipped when benching them would leave the raid under `bench.minTanks` /
--     `bench.minHealers` (the numbers that exist among the candidates, if fewer). A member with no declared role counts
--     as a damage dealer. `opts.keep` members are never proposed. When the places cannot be filled without breaking a
--     minimum, the minimum gives way (a second pass over the same order) and `warnings` says so ("ROLE_TANK",
--     "ROLE_HEALER"); the master looter sees it.
--   The benches counted are the nights a member was benched and never played (Nights.Attendance), not counting the night
--   being planned (`opts.night`, an id): the proposal can be asked again after the bench is written and gives the same.
--
-- Reasons are codes (`why[name]`): "VOLUNTEER", "MAYBE", "ROTATION"; the locales give the words (M7-2).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Rotation = {}
ns.Rotation, ns.modules.Rotation = Rotation, Rotation

local type, pairs, ipairs, floor, sort = type, pairs, ipairs, math.floor, table.sort

local function Roster() return ns.Roster end
local function Nights() return ns.Nights end
local function Ledger() return ns.Ledger end
local function Rules() return ns.Rules end

Rotation.REASONS = { VOLUNTEER = true, MAYBE = true, ROTATION = true }
Rotation.EXCLUDED = { DECLINED = true, UNAVAILABLE = true, MANUAL = true }
Rotation.WARNINGS = { ROLE_TANK = true, ROLE_HEALER = true, TOO_MANY_KEPT = true }

-- The day of the week of "YYYY-MM-DD" as the roster's code ("MON" ... "SUN"), or nil for a date that is not one.
-- (Sakamoto's method; Lua 5.1 has no calendar of its own that is safe for every year.)
local OFFSETS = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
function Rotation.Weekday(date)
	if not Nights().ValidDate(date) then return nil end
	local y, m, d = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if m < 3 then y = y - 1 end
	local dow = (y + floor(y / 4) - floor(y / 100) + floor(y / 400) + OFFSETS[m] + d) % 7   -- 0 = Sunday
	local days = { [0] = "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" }
	return days[dow]
end

-- The bench configuration in force: the `bench` section of the rules, with the defaults for what is missing.
local function benchConfig(L, rules)
	local c = rules or Rules().Current(L)
	local d = Rules().DefaultConfig().bench
	local b = type(c) == "table" and type(c.bench) == "table" and c.bench or {}
	return { creditEffect = b.creditEffect or d.creditEffect, creditAmount = b.creditAmount or d.creditAmount,
		minTanks = b.minTanks or d.minTanks, minHealers = b.minHealers or d.minHealers }
end

---------------------------------------------------------------------------------------------------------------------
-- The history of benches

-- Per member of the season { played, benched } counted over the nights of the ledger: `played` the nights they were in the
-- raid at some moment, `benched` the ones they sat on the bench and never played. opts.except = a night id that does
-- not count (the night being planned). Only nights that have a lineup count, so an empty night adds nothing.
function Rotation.Counts(L, season, opts)
	local except = opts and opts.except
	local out = {}
	local att = Nights().Attendance(L, season)
	for _, rec in ipairs(att.nights) do
		if rec.night.id ~= except then
			for name in pairs(rec.played) do
				out[name] = out[name] or { played = 0, benched = 0 }
				out[name].played = out[name].played + 1
			end
			for name in pairs(rec.benched) do
				out[name] = out[name] or { played = 0, benched = 0 }
				out[name].benched = out[name].benched + 1
			end
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- The proposal

local function roleOf(m) return m.role == "TANK" and "TANK" or m.role == "HEALER" and "HEALER" or "DAMAGER" end

local function setOf(list)
	local s = {}
	for _, n in ipairs(type(list) == "table" and list or {}) do s[n] = true end
	return s
end

-- Proposes the bench of a night. opts = {
--   night?        the id of a NIGHT_OPENED: it gives the size, the faction and the date, and does not count in the history
--   size?, faction?, date?   what the night is, when there is no night yet (size defaults to the pool of the faction)
--   rules?        the rules in force (a whole configuration); the ledger's current ones when nil
--   signups?      { [member] = "yes" | "maybe" | "no" }  the calendar's answers (Adapters/Calendar.lua)
--   volunteers?   members who asked to sit out
--   keep?         members who must play: never proposed
--   exclude?      members who are not coming (by hand)
--   useAvailability?   false: the declared weekdays are not looked at (default true)
-- }
-- Returns { slots, candidates, raid = {sorted}, bench = {sorted}, why = { [member] = code }, excluded = { [member] = code },
-- short, warnings = { codes } }, or nil and a code: "SEASON_UNKNOWN", "NIGHT_UNKNOWN", "SIZE" (no valid size).
function Rotation.Propose(L, season, opts)
	opts = opts or {}
	if not ns.Season.Get(L, season) then return nil, "SEASON_UNKNOWN" end
	local size, faction, date, nightId = opts.size, opts.faction, opts.date, nil
	if opts.night ~= nil then
		local n = Nights().Get(L, opts.night)
		if not n or n.season ~= season then return nil, "NIGHT_UNKNOWN" end
		nightId = n.id
		size, faction, date = size or n.size, faction or n.faction, date or n.date
	end
	local rs = Roster().State(L, season)
	local cfg = benchConfig(L, opts.rules)
	local volunteers, keep, exclude = setOf(opts.volunteers), setOf(opts.keep), setOf(opts.exclude)
	local signups = type(opts.signups) == "table" and opts.signups or {}
	local weekday = opts.useAvailability ~= false and date and Rotation.Weekday(date) or nil
	local counts = Rotation.Counts(L, season, { except = nightId })

	local pool, excluded = {}, {}
	for name, m in pairs(rs.members) do
		if Roster().IsPlaying(m) and (not faction or not m.faction or m.faction == faction) then
			local why
			if exclude[name] then why = "MANUAL"
			elseif signups[name] == "no" then why = "DECLINED"
			elseif weekday and m.avail then
				local ok = false
				for _, d in ipairs(m.avail) do if d == weekday then ok = true end end
				if not ok then why = "UNAVAILABLE" end
			end
			if why then excluded[name] = why else pool[#pool + 1] = name end
		end
	end
	if size == nil then size = #pool end
	if type(size) ~= "number" or size ~= floor(size) or size <= 0 then return nil, "SIZE" end

	local result = { slots = size, candidates = #pool, raid = {}, bench = {}, why = {}, excluded = excluded, short = 0,
		warnings = {} }
	if #pool <= size then
		for _, name in ipairs(pool) do result.raid[#result.raid + 1] = name end
		sort(result.raid)
		result.short = size - #pool
		return result
	end

	-- who sits out first
	local order = {}
	for _, name in ipairs(pool) do
		if not keep[name] then
			local c = counts[name] or { played = 0, benched = 0 }
			order[#order + 1] = { name = name, role = roleOf(rs.members[name]), benched = c.benched, played = c.played,
				rank = volunteers[name] and 0 or signups[name] == "maybe" and 1 or 2 }
		end
	end
	sort(order, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		if a.benched ~= b.benched then return a.benched < b.benched end
		if a.played ~= b.played then return a.played > b.played end
		return a.name < b.name
	end)

	local left = { TANK = 0, HEALER = 0, DAMAGER = 0 }
	for _, name in ipairs(pool) do local r = roleOf(rs.members[name]); left[r] = left[r] + 1 end
	local need = { TANK = math.min(cfg.minTanks, left.TANK), HEALER = math.min(cfg.minHealers, left.HEALER), DAMAGER = 0 }
	local want = #pool - size
	local benched = {}
	local function take(o, why)
		benched[o.name] = true
		left[o.role] = left[o.role] - 1
		result.bench[#result.bench + 1] = o.name
		result.why[o.name] = why or (o.rank == 0 and "VOLUNTEER" or o.rank == 1 and "MAYBE" or "ROTATION")
	end
	for _, o in ipairs(order) do
		if #result.bench >= want then break end
		if left[o.role] - 1 >= need[o.role] then take(o) end
	end
	if #result.bench < want then   -- the minimums give way: the same order, over who is left
		for _, o in ipairs(order) do
			if #result.bench >= want then break end
			if not benched[o.name] then
				take(o)
				local w = o.role == "TANK" and "ROLE_TANK" or o.role == "HEALER" and "ROLE_HEALER" or nil
				if w and left[o.role] < need[o.role] then
					local seen = false
					for _, x in ipairs(result.warnings) do if x == w then seen = true end end
					if not seen then result.warnings[#result.warnings + 1] = w end
				end
			end
		end
	end
	if #result.bench < want then result.warnings[#result.warnings + 1] = "TOO_MANY_KEPT" end
	for _, name in ipairs(pool) do
		if not benched[name] then result.raid[#result.raid + 1] = name end
	end
	sort(result.raid); sort(result.bench); sort(result.warnings)
	return result
end

---------------------------------------------------------------------------------------------------------------------
-- The effect of a bench on the credits

-- The credit change a bench causes, per member: { [member] = delta } (nothing for a member who never sat out). With the
-- effect "none" (the guild's preset) it is empty. "bonus" helps the benched member in the queue: their credits go **down**
-- by `bench.creditAmount` for every bench (never below 0: someone at 0 already has the top priority); "malus" puts them
-- **up** by the same. The fewest credits win the roll (§3.3), so a bonus is a precedence, not a gift of loot.
-- `rules` = a whole configuration; the ledger's current rules when nil.
function Rotation.CreditEffect(L, season, rules)
	local cfg = benchConfig(L, rules)
	local out = {}
	if cfg.creditEffect == "none" or cfg.creditAmount == 0 then return out end
	local sign = cfg.creditEffect == "bonus" and -1 or 1
	for name, c in pairs(Rotation.Counts(L, season)) do
		if c.benched > 0 then out[name] = sign * cfg.creditAmount * c.benched end
	end
	return out
end

-- The credits the queue uses: the ledger's credits with the bench effect added (the same table as Ledger.Credits when the
-- effect is "none"). A member the ledger does not know gets no entry. Returns { [member] = n }.
function Rotation.Credits(L, season, rules)
	local credits = Ledger().Credits(L, season)
	for name, delta in pairs(Rotation.CreditEffect(L, season, rules)) do
		if credits[name] ~= nil then
			local v = credits[name] + delta
			if delta < 0 and v < 0 then v = 0 end
			credits[name] = v
		end
	end
	return credits
end

if ns.addon then ns.addon.Rotation = Rotation end   -- also reachable from tests
