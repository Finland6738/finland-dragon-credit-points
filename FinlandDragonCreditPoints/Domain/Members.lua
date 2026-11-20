-- Members: the season's pool of mains, their alts and the late joiners (docs/ANALISI.md §2, §3.1, §3.5, §6). Pure Lua
-- 5.1: it never calls the game.
--
-- Read from the ledger, never stored apart:
--   MEMBER_JOINED{member, faction?, initialCredits, rule, basis?}  a main enters the season's pool. The first one of a
--       member in canonical order counts (as in Ledger.Credits). `initialCredits` is computed **once**, when the member
--       joins, and written in the event, so it stays stable when the roster average changes later (§3.5). `rule` says
--       how it was computed (a code, see Members.RULES) and `basis` how many members the computation used.
--   MEMBER_LINKED_ALT{alt, main, faction?}  an alt is linked to a main of the same season; it has no credits of its
--       own: an award won with an alt goes to the main (Members.Resolve). The first link of an alt counts; a link whose
--       main is not a member, whose alt is a member, or whose faction differs from the main's is ignored.
--
-- Only the declared main counts (`mainOnly`, preset on). One main per faction: a main and its alts are one group with
-- one faction; a player who plays both factions has a second main in the other faction, with its own credits (§6).
-- The faction a character belongs to is the client's UnitFactionGroup token ("Horde" / "Alliance"), read by the
-- adapter; it may be missing (a guild of one faction does not need it).
--
-- Late joiners (§3.5): a member who joins after the season's first official night gets `lateJoin.method` of the
-- credits of the basis ("members with at least `minNights` nights in the season", of the same faction when the joiner
-- declares one), rounded with `lateJoin.rounding` to `lateJoin.decimals` places. Methods: `average` (preset), `median`,
-- `min`, `zero`, `fixed` (`lateJoin.fixed`). An empty basis gives the season's `startCredits`. A member who joins
-- before the first night starts with `startCredits`.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Members = {}
ns.Members, ns.modules.Members = Members, Members

local type, pairs, ipairs, floor, ceil, sort = type, pairs, ipairs, math.floor, math.ceil, table.sort

local function Ledger() return ns.Ledger end
local function Season() return ns.Season end

Members.METHODS = { average = true, median = true, min = true, zero = true, fixed = true }
Members.ROUNDINGS = { floor = true, round = true, ceil = true }

-- The codes written in MEMBER_JOINED.rule.
Members.RULES = {
	START = "START",               -- joined before the first night: the season's startCredits
	AVERAGE = "AVERAGE", MEDIAN = "MEDIAN", MIN = "MIN", ZERO = "ZERO", FIXED = "FIXED",
	EMPTY_BASIS = "EMPTY_BASIS",   -- late, but nobody in the basis: the season's startCredits
}

-- The members configuration of the "Patto" preset (§3.1, §3.5). A fresh copy on every call.
function Members.DefaultConfig()
	return {
		mainOnly = true,
		lateJoin = { method = "average", rounding = "floor", decimals = 0, minNights = 1, fixed = 0 },
	}
end

local function isName(s) return type(s) == "string" and s ~= "" and not s:find(":", 1, true) end
local function isNum(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end

-- Checks a members configuration. Returns true, or false and the field at fault.
function Members.Validate(config)
	if type(config) ~= "table" then return false, "config" end
	if type(config.mainOnly) ~= "boolean" then return false, "mainOnly" end
	local lj = config.lateJoin
	if type(lj) ~= "table" then return false, "lateJoin" end
	if not Members.METHODS[lj.method] then return false, "lateJoin.method" end
	if not Members.ROUNDINGS[lj.rounding] then return false, "lateJoin.rounding" end
	if type(lj.decimals) ~= "number" or lj.decimals ~= floor(lj.decimals) or lj.decimals < 0 or lj.decimals > 2 then
		return false, "lateJoin.decimals"
	end
	if type(lj.minNights) ~= "number" or lj.minNights ~= floor(lj.minNights) or lj.minNights < 0 then
		return false, "lateJoin.minNights"
	end
	if not isNum(lj.fixed) or lj.fixed < 0 then return false, "lateJoin.fixed" end
	return true
end

-- Rounds `x` to `decimals` places with `mode` (floor | round | ceil). A tiny epsilon keeps 0.1 + 0.2 style noise from
-- moving a value across a boundary (2.9999999 floors to 3, not 2).
function Members.Round(x, mode, decimals)
	local p = 10 ^ (decimals or 0)
	local v = x * p
	local eps = 1e-7
	if mode == "ceil" then
		v = ceil(v - eps)
	elseif mode == "round" then
		v = floor(v + 0.5 + eps)
	else
		v = floor(v + eps)
	end
	return v / p
end

---------------------------------------------------------------------------------------------------------------------
-- The pool, folded from the ledger

-- { members = { [name] = { member, faction, initialCredits, rule, basis, joinedAt, joined, alts = {sorted} } },
--   alts = { [alt] = main } } for a season.
function Members.State(L, season)
	local Lg = Ledger()
	local members, alts = {}, {}
	for _, e in ipairs(Lg.Sorted(L, function(e) return e.season == season and e.type == "MEMBER_JOINED" end)) do
		local p = Lg.Readable(e) and Lg.Payload(e)
		if p and not members[p.member] then
			members[p.member] = {
				member = p.member, faction = p.faction, initialCredits = p.initialCredits or 0, rule = p.rule,
				basis = p.basis, joinedAt = e.ts, joined = e.id, alts = {},
			}
		end
	end
	for _, e in ipairs(Lg.Sorted(L, function(e) return e.season == season and e.type == "MEMBER_LINKED_ALT" end)) do
		local p = Lg.Readable(e) and Lg.Payload(e)
		local main = p and members[p.main]
		if main and not members[p.alt] and not alts[p.alt]
			and (p.faction == nil or main.faction == nil or p.faction == main.faction) then
			alts[p.alt] = p.main
			main.alts[#main.alts + 1] = p.alt
		end
	end
	for _, m in pairs(members) do sort(m.alts) end
	return { members = members, alts = alts }
end

-- One member (a main), or nil.
function Members.Get(L, season, name)
	return Members.State(L, season).members[name]
end

-- The main that holds the credits of `name` in the season: the name itself for a main, its main for a linked alt
-- (with mainOnly; without it every character counts on its own). Returns the name, or nil and "NOT_MEMBER".
function Members.Resolve(L, season, name, config)
	config = config or Members.DefaultConfig()
	local state = Members.State(L, season)
	if state.members[name] then return name end
	if state.alts[name] then
		if config.mainOnly == false then return name end
		return state.alts[name]
	end
	return nil, "NOT_MEMBER"
end

-- The pool with credits, sorted by credits then name (the priority order of the Credits tab):
-- { { member, faction, credits, initialCredits, rule, alts }, ... }.
function Members.Roster(L, season)
	local state = Members.State(L, season)
	local credits = Ledger().Credits(L, season)
	local list = {}
	for name, m in pairs(state.members) do
		list[#list + 1] = { member = name, faction = m.faction, credits = credits[name] or m.initialCredits,
			initialCredits = m.initialCredits, rule = m.rule, alts = m.alts }
	end
	sort(list, function(a, b)
		if a.credits ~= b.credits then return a.credits < b.credits end
		return a.member < b.member
	end)
	return list
end

---------------------------------------------------------------------------------------------------------------------
-- Late joiners

-- The initial credits of a late joiner, as (value, rule, basis). opts = { faction?, nights? = {[member] = n},
-- exclude? = name }. `nights` comes from the lineup (M3); without it every member of the pool is in the basis. The
-- season's current credits are read from the ledger, so the value is the one of the moment it is called.
function Members.LateJoinCredits(L, season, config, opts)
	config = config or Members.DefaultConfig()
	opts = opts or {}
	local lj = config.lateJoin
	local s = Season().Get(L, season)
	local start = s and s.startCredits or 0
	if lj.method == "zero" then return 0, Members.RULES.ZERO, 0 end
	if lj.method == "fixed" then return lj.fixed, Members.RULES.FIXED, 0 end

	local state = Members.State(L, season)
	local credits = Ledger().Credits(L, season)
	local values = {}
	for name, m in pairs(state.members) do
		local nights = opts.nights and (opts.nights[name] or 0)
		local inBasis = name ~= opts.exclude
			and (nights == nil or nights >= lj.minNights)
			and (opts.faction == nil or m.faction == nil or m.faction == opts.faction)
		if inBasis then values[#values + 1] = credits[name] or m.initialCredits end
	end
	local n = #values
	if n == 0 then return start, Members.RULES.EMPTY_BASIS, 0 end
	sort(values)
	local x, rule
	if lj.method == "min" then
		x, rule = values[1], Members.RULES.MIN
	elseif lj.method == "median" then
		if n % 2 == 1 then x = values[(n + 1) / 2] else x = (values[n / 2] + values[n / 2 + 1]) / 2 end
		rule = Members.RULES.MEDIAN
	else
		local sum = 0
		for _, v in ipairs(values) do sum = sum + v end
		x, rule = sum / n, Members.RULES.AVERAGE
	end
	return Members.Round(x, lj.rounding, lj.decimals), rule, n
end

---------------------------------------------------------------------------------------------------------------------
-- Writing

-- A main joins the season's pool. draft = { author, ts, season, member, faction?, nights?, late? }: `late` forces the
-- late-joiner rule on or off (default: on once the season has an official night). Returns the MEMBER_JOINED event, or
-- nil and a code: "SEASON_UNKNOWN", "SEASON_CLOSED", "member", "ALREADY_JOINED", "IS_ALT", "CONFIG:<field>" or a
-- Ledger.Append code.
function Members.Join(L, draft, config)
	if type(draft) ~= "table" then return nil, "event" end
	config = config or Members.DefaultConfig()
	local okConfig, field = Members.Validate(config)
	if not okConfig then return nil, "CONFIG:" .. field end
	local s = Season().Get(L, draft.season)
	if not s then return nil, "SEASON_UNKNOWN" end
	if s.closed then return nil, "SEASON_CLOSED" end
	if not isName(draft.member) then return nil, "member" end
	local state = Members.State(L, draft.season)
	if state.members[draft.member] then return nil, "ALREADY_JOINED" end
	if state.alts[draft.member] and config.mainOnly then return nil, "IS_ALT" end

	local late = draft.late
	if late == nil then late = Season().NightCount(L, draft.season) > 0 end
	local initial, rule, basis
	if late then
		initial, rule, basis = Members.LateJoinCredits(L, draft.season, config,
			{ faction = draft.faction, nights = draft.nights, exclude = draft.member })
	else
		initial, rule = s.startCredits, Members.RULES.START
	end
	return Ledger().Append(L, {
		author = draft.author, ts = draft.ts, season = draft.season, type = "MEMBER_JOINED",
		payload = { member = draft.member, faction = draft.faction, initialCredits = initial, rule = rule,
			basis = basis },
	})
end

-- Links an alt to a main of the season. draft = { author, ts, season, alt, main, faction? }. Returns the
-- MEMBER_LINKED_ALT event, or nil and a code: "SEASON_UNKNOWN", "SEASON_CLOSED", "alt", "main", "MAIN_UNKNOWN",
-- "ALT_IS_MAIN", "ALREADY_LINKED", "FACTION_MISMATCH" or a Ledger.Append code.
function Members.LinkAlt(L, draft)
	if type(draft) ~= "table" then return nil, "event" end
	local s = Season().Get(L, draft.season)
	if not s then return nil, "SEASON_UNKNOWN" end
	if s.closed then return nil, "SEASON_CLOSED" end
	if not isName(draft.alt) or draft.alt == draft.main then return nil, "alt" end
	if not isName(draft.main) then return nil, "main" end
	local state = Members.State(L, draft.season)
	local main = state.members[draft.main]
	if not main then return nil, "MAIN_UNKNOWN" end
	if state.members[draft.alt] then return nil, "ALT_IS_MAIN" end
	if state.alts[draft.alt] then return nil, "ALREADY_LINKED" end
	if draft.faction and main.faction and draft.faction ~= main.faction then return nil, "FACTION_MISMATCH" end
	return Ledger().Append(L, {
		author = draft.author, ts = draft.ts, season = draft.season, type = "MEMBER_LINKED_ALT",
		payload = { alt = draft.alt, main = draft.main, faction = draft.faction },
	})
end

if ns.addon then ns.addon.Members = Members end   -- also reachable from tests
