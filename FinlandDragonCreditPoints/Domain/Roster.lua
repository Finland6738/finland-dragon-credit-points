-- Roster: the season's pool with its declarations, officer corrections, mains and alts (docs/ANALISI.md §6, §3.1). Pure
-- Lua 5.1: it never calls the game. It sits on top of Domain/Members.lua (who is in the pool, the alt links, the
-- credits) and Domain/Season.lua; nothing here counts credits.
--
-- Read from the ledger, never stored apart:
--   MEMBER_JOINED{member, faction?, initialCredits, rule, basis?, <declaration>}  a main enters the pool (Members). Since
--       M3-2 it may carry the player's **declaration**: class, role, ms1 (required by Roster.Join), ms2, os, status,
--       avail, note, twin (all optional in the payload, so a member written by Members.Join alone is still valid and
--       shows as "undeclared").
--   ROSTER_CHANGED{member, set?, clear?, reason?}  an officer's correction of a member's declaration or status
--       (roster.manage). `set` holds the fields that take a new value, `clear` the optional ones that go away. It is the
--       **only** way a declaration changes during the season.
--   MEMBER_LINKED_ALT{alt, main, faction?}  an alt of a main (Members.LinkAlt, roster.manage); an alt never has credits.
--
-- The declaration (the player's roster entry, §6):
--   class   the nine classes of the site (WARRIOR ... DRUID, the client's classFile)
--   role    TANK | HEALER | DAMAGER (the client's role tokens); the role of the MS1
--   ms1     the main spec (a specID, required): the "Main-spec" button of the popup, the council's "ignored upgrade" flag
--   ms2     the second spec (specID): the "Off-spec" button (tier 2, 0 credits). **MS1 = MS and MS2 = OS for the loot**
--   os      the spec the player would like to play (specID): roster information only, it gives no right to roll (§3.1)
--   status  ACTIVE | TRIAL | INACTIVE (the site's "Raider" / "Trial"; an inactive member keeps credits and is not exported)
--   avail   the weekdays the player can raid (MON ... SUN), and `note`, a short free note of the player (at most 80
--           characters): data written by the player, never a sentence of the addon
--   twin    the member's main of the **other faction** (the same player): one main per faction per player (§6)
--
-- Who writes what. The ledger accepts MEMBER_JOINED, MEMBER_LINKED_ALT and ROSTER_CHANGED only from `roster.manage`
-- (Domain/Permissions.lua), so a raider cannot write a declaration or an alt link: the player **asks**
-- (Roster.RequestJoin / Roster.RequestAlt, plain data outside the ledger, sent to the officers by the transport of
-- M6) and an officer **approves** (Roster.Approve), which writes the event; Roster.Reject drops the request. A
-- declaration cannot change mid-season: Roster.Join of a member already in the pool answers ALREADY_JOINED and the
-- only event that changes it is a ROSTER_CHANGED of an officer (Roster.Change).
--
-- Specs: the addon knows a spec by its numeric id. Roster.SpecInfo(specID) -> { class, role } is a hook for the fixed
-- table of Data/Specs.lua (M3-3b); while it is nil the class and the role have to be declared as they are, with it the
-- class and role are derived from the MS1 and every spec must belong to the declared class.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Roster = {}
ns.Roster, ns.modules.Roster = Roster, Roster

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local floor, sort, concat = math.floor, table.sort, table.concat

local function Ledger() return ns.Ledger end
local function Season() return ns.Season end
local function Members() return ns.Members end

Roster.CLASSES = {
	WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
	SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true,
}
Roster.ROLES = { TANK = true, HEALER = true, DAMAGER = true }
Roster.STATUSES = { ACTIVE = true, TRIAL = true, INACTIVE = true }
Roster.DAYS = { "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN" }
local DAY_INDEX = {}
for i, d in ipairs(Roster.DAYS) do DAY_INDEX[d] = i end

Roster.NOTE_MAX = 80
Roster.MAX_REQUESTS = 500   -- requests waiting for an officer, per request table

-- The fields of a declaration, in the order they are shown; the ones an officer may clear again (ms1 and the
-- class / role / status always have a value).
Roster.FIELDS = { "class", "role", "ms1", "ms2", "os", "status", "avail", "note", "twin" }
Roster.CLEARABLE = { ms2 = true, os = true, avail = true, note = true, twin = true }
local IS_FIELD = {}
for _, f in ipairs(Roster.FIELDS) do IS_FIELD[f] = true end

-- The text of the site's "rank" column for a status ("Raider" / "Trial"), nil for an inactive member (not exported).
Roster.SITE_RANK = { ACTIVE = "Raider", TRIAL = "Trial" }

-- Set by Data/Specs.lua (M3-3b): specID -> { class = "PRIEST", role = "HEALER" } or nil for an unknown spec.
Roster.SpecInfo = nil

local function isName(s) return type(s) == "string" and s ~= "" and not s:find(":", 1, true) end
local function isSpec(n) return type(n) == "number" and n == floor(n) and n > 0 and n < 2 ^ 31 end

local function copyList(list)
	local out = {}
	for i, v in ipairs(list) do out[i] = v end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Field checks (shared by the ledger check, the writers and the requests)

-- True when `v` is a valid value for declaration field `k` (structure only: no pool, no spec table).
local function validField(k, v)
	if k == "class" then return type(v) == "string" and Roster.CLASSES[v] == true
	elseif k == "role" then return type(v) == "string" and Roster.ROLES[v] == true
	elseif k == "status" then return type(v) == "string" and Roster.STATUSES[v] == true
	elseif k == "ms1" or k == "ms2" or k == "os" then return isSpec(v)
	elseif k == "twin" then return isName(v)
	elseif k == "note" then
		return type(v) == "string" and v ~= "" and #v <= Roster.NOTE_MAX and not v:find("%c")
	elseif k == "avail" then
		if type(v) ~= "table" or #v == 0 or #v > #Roster.DAYS then return false end
		local seen = {}
		for i, d in pairs(v) do
			if type(i) ~= "number" or i < 1 or i > #v or not DAY_INDEX[d] or seen[d] then return false end
			seen[d] = true
		end
		return true
	end
	return false
end

-- Checks the declaration fields of a table (a payload or a `set`): returns the first field at fault, or nil.
local function badField(t)
	for k, v in pairs(t) do
		if IS_FIELD[k] and not validField(k, v) then return k end
	end
end

-- The weekdays in week order, so two declarations of the same days compare equal.
local function sortedDays(list)
	local out = copyList(list)
	sort(out, function(a, b) return DAY_INDEX[a] < DAY_INDEX[b] end)
	return out
end

-- The ledger checks (Ledger.Check): MEMBER_JOINED keeps its own checks and adds the declaration's; ROSTER_CHANGED is new.
do
	local CHECKS = Ledger().CHECKS
	local base = CHECKS.MEMBER_JOINED
	CHECKS.MEMBER_JOINED = function(p)
		local bad = base(p) or badField(p)
		if bad then return bad end
	end
	CHECKS.ROSTER_CHANGED = function(p)
		if not isName(p.member) then return "member" end
		if p.reason ~= nil and not (type(p.reason) == "string" and p.reason:match("^[A-Z][A-Z0-9_]*$")) then
			return "reason"
		end
		local setN, clearN = 0, 0
		if p.set ~= nil then
			if type(p.set) ~= "table" then return "set" end
			for k in pairs(p.set) do
				if not IS_FIELD[k] then return "set" end
				setN = setN + 1
			end
			local bad = badField(p.set)
			if bad then return "set." .. bad end
		end
		if p.clear ~= nil then
			if type(p.clear) ~= "table" then return "clear" end
			local seen = {}
			for i, k in pairs(p.clear) do
				if type(i) ~= "number" or i < 1 or i > #p.clear or not Roster.CLEARABLE[k] or seen[k] then
					return "clear"
				end
				if p.set and p.set[k] ~= nil then return "clear" end
				seen[k] = true
				clearN = clearN + 1
			end
		end
		if setN + clearN == 0 then return "set" end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- The declaration against the spec table

-- Completes and checks a declaration (a table of fields): with Roster.SpecInfo the class and the role are derived from
-- the MS1 and every spec has to exist and belong to the class; without it the class and the role must be declared.
-- Returns a new table, or nil and a code: "MS1_REQUIRED", "CLASS_REQUIRED", "ROLE_REQUIRED", "DUPLICATE_SPEC",
-- "SPEC_UNKNOWN", "SPEC_CLASS", "ROLE_MISMATCH" or "DECLARATION:<field>".
function Roster.Complete(decl)
	if type(decl) ~= "table" then return nil, "DECLARATION:decl" end
	local out = {}
	for _, f in ipairs(Roster.FIELDS) do
		if decl[f] ~= nil then out[f] = decl[f] end
	end
	local bad = badField(out)
	if bad then return nil, "DECLARATION:" .. bad end
	if out.ms1 == nil then return nil, "MS1_REQUIRED" end
	if out.ms2 == out.ms1 or out.os == out.ms1 or (out.os ~= nil and out.os == out.ms2) then
		return nil, "DUPLICATE_SPEC"
	end
	if out.avail then out.avail = sortedDays(out.avail) end
	out.status = out.status or "ACTIVE"
	local info = Roster.SpecInfo
	if info then
		local first = info(out.ms1)
		if not first then return nil, "SPEC_UNKNOWN" end
		out.class = out.class or first.class
		out.role = out.role or first.role
		for _, f in ipairs({ "ms1", "ms2", "os" }) do
			if out[f] then
				local s = info(out[f])
				if not s then return nil, "SPEC_UNKNOWN" end
				if s.class ~= out.class then return nil, "SPEC_CLASS" end
			end
		end
		if first.role ~= out.role then return nil, "ROLE_MISMATCH" end
	else
		if not out.class then return nil, "CLASS_REQUIRED" end
		if not out.role then return nil, "ROLE_REQUIRED" end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- The pool with its declarations, folded from the ledger

local function applyChange(m, p)
	for k, v in pairs(p.set or {}) do
		if k == "avail" then m.avail = sortedDays(v) else m[k] = v end
	end
	for _, k in ipairs(p.clear or {}) do m[k] = nil end
end

-- { members = { [name] = entry }, alts = { [alt] = main } } for a season, where an entry is
-- { member, faction, class, role, ms1, ms2, os, status, avail, note, twin, declared, initialCredits, alts,
--   joined (event id), changes (number of ROSTER_CHANGED applied), changedAt (ts of the last) }.
-- A declaration is read from the member's first MEMBER_JOINED (the one Members counts); the officers' ROSTER_CHANGED
-- events apply on top of it in canonical order. A change for a name outside the pool is ignored. `twin` is kept only
-- when the pair is valid (both members, factions known and different, nobody claimed by two mains).
function Roster.State(L, season)
	local Lg = Ledger()
	local ms = Members().State(L, season)
	local members = {}
	for name, m in pairs(ms.members) do
		local p = Lg.Payload(L.events[m.joined]) or {}
		local e = {
			member = name, faction = m.faction, initialCredits = m.initialCredits, alts = m.alts, joined = m.joined,
			class = p.class, role = p.role, ms1 = p.ms1, ms2 = p.ms2, os = p.os, status = p.status or "ACTIVE",
			avail = p.avail and sortedDays(p.avail) or nil, note = p.note, twin = p.twin, changes = 0,
		}
		members[name] = e
	end
	for _, ev in ipairs(Lg.Sorted(L, function(x) return x.season == season and x.type == "ROSTER_CHANGED" end)) do
		local p = Lg.Readable(ev) and Lg.Payload(ev)
		local m = p and members[p.member]
		if m then
			applyChange(m, p)
			m.changes, m.changedAt = m.changes + 1, ev.ts
		end
	end
	-- twins: a claim counts when the target is a member of the other faction and neither main is paired already; the
	-- members are taken in the order they joined, so the same ledger gives the same pairs on every client.
	local order = {}
	for name, m in pairs(members) do order[#order + 1] = { name = name, ev = L.events[m.joined] } end
	sort(order, function(a, b) return Lg.Before(a.ev, b.ev) end)
	local paired = {}
	for _, o in ipairs(order) do
		local m = members[o.name]
		local t = m.twin and members[m.twin]
		if t and o.name ~= m.twin and m.faction and t.faction and m.faction ~= t.faction
			and not paired[o.name] and not paired[m.twin] then
			paired[o.name], paired[m.twin] = m.twin, o.name
		end
	end
	for name, m in pairs(members) do
		m.twin = paired[name]
		m.declared = m.ms1 ~= nil
	end
	return { members = members, alts = ms.alts }
end

-- One member of the pool (a main), or nil.
function Roster.Get(L, season, name)
	return Roster.State(L, season).members[name]
end

local function playing(m) return m.status == "ACTIVE" or m.status == "TRIAL" end
Roster.IsPlaying = playing

-- The pool as a list sorted by class then name (the site's order). opts = { status? = "ACTIVE" | "TRIAL" | "INACTIVE",
-- playing? = true (active and trial: the ones the site exports), faction?, role?, class? }.
function Roster.List(L, season, opts)
	opts = opts or {}
	local list = {}
	for _, m in pairs(Roster.State(L, season).members) do
		if (opts.status == nil or m.status == opts.status)
			and (not opts.playing or playing(m))
			and (opts.faction == nil or m.faction == opts.faction)
			and (opts.role == nil or m.role == opts.role)
			and (opts.class == nil or m.class == opts.class) then
			list[#list + 1] = m
		end
	end
	sort(list, function(a, b)
		if (a.class or "") ~= (b.class or "") then return (a.class or "") < (b.class or "") end
		return a.member < b.member
	end)
	return list
end

-- The members who play (active or trial) per role: { TANK = n, HEALER = n, DAMAGER = n, total = n, trial = n,
-- undeclared = n }, for one faction when given.
function Roster.Counts(L, season, faction)
	local c = { TANK = 0, HEALER = 0, DAMAGER = 0, total = 0, trial = 0, undeclared = 0 }
	for _, m in ipairs(Roster.List(L, season, { playing = true, faction = faction })) do
		c.total = c.total + 1
		if m.status == "TRIAL" then c.trial = c.trial + 1 end
		if m.role then c[m.role] = c[m.role] + 1 else c.undeclared = c.undeclared + 1 end
	end
	return c
end

-- The members of the pool the site's roster.json lists: playing mains with their site rank. [{ entry..., rank }]
function Roster.SitePlayers(L, season, faction)
	local out = {}
	for _, m in ipairs(Roster.List(L, season, { playing = true, faction = faction })) do
		if m.declared and m.class and m.role then
			local row = {}
			for k, v in pairs(m) do row[k] = v end
			row.rank = Roster.SITE_RANK[m.status]
			out[#out + 1] = row
		end
	end
	return out
end

-- Who holds the credits of a character: the main (an alt never has credits of its own) and the main's current
-- credits. Returns the main's name, the credits and `viaAlt` (true when `name` is an alt), or nil and "NOT_MEMBER".
function Roster.CreditHolder(L, season, name, config)
	local main, why = Members().Resolve(L, season, name, config)
	if not main then return nil, why end
	local credits = Ledger().Credits(L, season)
	local m = Members().Get(L, season, main)
	return main, credits[main] or (m and m.initialCredits) or 0, main ~= name
end

---------------------------------------------------------------------------------------------------------------------
-- Checks that need the pool

local function seasonOpen(L, season)
	local s = Season().Get(L, season)
	if not s then return nil, "SEASON_UNKNOWN" end
	if s.closed then return nil, "SEASON_CLOSED" end
	return s
end

-- A twin claim of `member` (faction `faction`) on `twin`, against the pool `state`. Returns nil or a code:
-- "TWIN_SELF", "TWIN_UNKNOWN" (not in the pool), "FACTION_REQUIRED", "TWIN_FACTION" (same faction: one main per
-- faction), "TWIN_TAKEN" (that main already has another twin).
local function twinProblem(state, member, faction, twin)
	if twin == nil then return nil end
	if twin == member then return "TWIN_SELF" end
	local t = state.members[twin]
	if not t then return "TWIN_UNKNOWN" end
	if not faction or not t.faction then return "FACTION_REQUIRED" end
	if faction == t.faction then return "TWIN_FACTION" end
	if t.twin and t.twin ~= member then return "TWIN_TAKEN" end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- Writing (an officer, roster.manage)

-- A main joins the pool with its declaration. draft = { author, ts, season, member, faction?, nights?, late?, class?,
-- role?, ms1, ms2?, os?, status?, avail?, note?, twin? }. Members.Join does the rest (the initial credits of a late
-- joiner included). Returns the MEMBER_JOINED event, or nil and a code of Roster.Complete, "TWIN_*", "FACTION_REQUIRED"
-- or one of Members.Join. `config` is the members configuration, `opts` goes to Ledger.Append (the trust gate).
function Roster.Join(L, draft, config, opts)
	if type(draft) ~= "table" then return nil, "event" end
	local s, why = seasonOpen(L, draft.season)
	if not s then return nil, why end
	local decl, code = Roster.Complete(draft)
	if not decl then return nil, code end
	local state = Roster.State(L, draft.season)
	if state.members[draft.member] then return nil, "ALREADY_JOINED" end
	local bad = twinProblem(state, draft.member, draft.faction, decl.twin)
	if bad then return nil, bad end
	local d = {
		author = draft.author, ts = draft.ts, season = draft.season, member = draft.member, faction = draft.faction,
		nights = draft.nights, late = draft.late, decl = decl,
	}
	return Members().Join(L, d, config, opts)
end

-- An officer corrects a member's declaration or status. draft = { author, ts, season, member, set = {field = value},
-- clear = {field, ...}, reason? = code }. Only what really changes is written. Setting the MS1 without a role takes the
-- new spec's role when the spec table is known. Returns the ROSTER_CHANGED event, or nil and a code: "SEASON_UNKNOWN",
-- "SEASON_CLOSED", "member", "NOT_MEMBER", "IS_ALT", "UNCHANGED", "DECLARATION:<field>", a Roster.Complete code, "TWIN_*"
-- or a Ledger.Append code. `opts` goes to Ledger.Append (the gate: roster.manage).
function Roster.Change(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	local s, why = seasonOpen(L, draft.season)
	if not s then return nil, why end
	if not isName(draft.member) then return nil, "member" end
	local state = Roster.State(L, draft.season)
	local cur = state.members[draft.member]
	if not cur then
		if state.alts[draft.member] then return nil, "IS_ALT" end
		return nil, "NOT_MEMBER"
	end
	local set, clear = {}, {}
	for k, v in pairs(draft.set or {}) do
		if not IS_FIELD[k] then return nil, "DECLARATION:" .. tostring(k) end
		set[k] = v
	end
	local bad = badField(set)
	if bad then return nil, "DECLARATION:" .. bad end
	for _, k in ipairs(draft.clear or {}) do
		if not Roster.CLEARABLE[k] then return nil, "DECLARATION:" .. tostring(k) end
		if set[k] ~= nil then return nil, "DECLARATION:" .. k end
		clear[#clear + 1] = k
	end
	if set.ms1 and set.role == nil and Roster.SpecInfo then
		local info = Roster.SpecInfo(set.ms1)
		if info then set.role = info.role end
	end
	-- the declaration as it would be after the change
	local merged = {}
	for _, f in ipairs(Roster.FIELDS) do merged[f] = cur[f] end
	local probe = { set = set, clear = clear }
	applyChange(merged, probe)
	local ok, code = Roster.Complete(merged)
	if not ok then return nil, code end
	if set.twin ~= nil then
		local problem = twinProblem(state, cur.member, cur.faction, set.twin)
		if problem then return nil, problem end
	end
	-- only what changes
	local diffSet, diffClear = {}, {}
	local nSet, nClear = 0, 0
	for k, v in pairs(set) do
		local same = cur[k] == v
		if k == "avail" and cur.avail then same = concat(cur.avail, ",") == concat(sortedDays(v), ",") end
		if not same then diffSet[k] = (k == "avail") and sortedDays(v) or v; nSet = nSet + 1 end
	end
	for _, k in ipairs(clear) do
		if cur[k] ~= nil then diffClear[#diffClear + 1] = k; nClear = nClear + 1 end
	end
	if nSet + nClear == 0 then return nil, "UNCHANGED" end
	sort(diffClear)
	return Ledger().Append(L, {
		author = draft.author, ts = draft.ts, season = draft.season, type = "ROSTER_CHANGED",
		payload = { member = draft.member, set = nSet > 0 and diffSet or nil, clear = nClear > 0 and diffClear or nil,
			reason = draft.reason },
	}, opts)
end

-- Sets a member's status (ACTIVE | TRIAL | INACTIVE). draft = { author, ts, season, member, status, reason? }.
function Roster.SetStatus(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	if not (type(draft.status) == "string" and Roster.STATUSES[draft.status]) then return nil, "DECLARATION:status" end
	return Roster.Change(L, { author = draft.author, ts = draft.ts, season = draft.season, member = draft.member,
		set = { status = draft.status }, reason = draft.reason }, opts)
end

-- An alt of a main (Members.LinkAlt), written by an officer. draft = { author, ts, season, alt, main, faction? }.
function Roster.LinkAlt(L, draft, opts)
	return Members().LinkAlt(L, draft, opts)
end

---------------------------------------------------------------------------------------------------------------------
-- Requests: what a player asks, what an officer approves

-- A new table of requests, plain data the service saves with the guild's data:
-- { seq = n, items = { [id] = { id, kind = "JOIN" | "ALT", season, from, ts, state = "PENDING" | "APPROVED" |
-- "REJECTED", ... } } }. A JOIN request carries the declaration fields and `member`/`faction`, an ALT request `alt` and
-- `main` (and the alt's `faction`). Nothing in it is a ledger event: the pool does not change until an officer approves.
function Roster.NewRequests() return { seq = 0, items = {} } end

local function pendingCount(R)
	local n = 0
	for _, r in pairs(R.items) do
		if r.state == "PENDING" then n = n + 1 end
	end
	return n
end

local function pendingFor(R, kind, season, key)
	for _, r in pairs(R.items) do
		if r.state == "PENDING" and r.kind == kind and r.season == season
			and (r.kind == "JOIN" and r.member == key or r.kind == "ALT" and r.alt == key) then
			return r
		end
	end
end

-- Checks a request against the ledger. Returns the clean request (a new table, without id and state), or nil and a
-- code: "event", "from", "kind", "SEASON_*", "member" / "alt" / "main", "ALREADY_JOINED", "IS_ALT", "MAIN_UNKNOWN",
-- "ALT_IS_MAIN", "ALREADY_LINKED", "FACTION_MISMATCH", or the codes of Roster.Complete and the twin checks.
local function checkRequest(L, req, config)
	if type(req) ~= "table" then return nil, "event" end
	if not isName(req.from) then return nil, "from" end
	if req.kind ~= "JOIN" and req.kind ~= "ALT" then return nil, "kind" end
	if type(req.ts) ~= "number" or req.ts < 0 then return nil, "ts" end
	local s, why = seasonOpen(L, req.season)
	if not s then return nil, why end
	local state = Roster.State(L, req.season)
	local out = { kind = req.kind, season = req.season, from = req.from, ts = req.ts }
	if req.faction ~= nil and not Ledger().FACTIONS[req.faction] then return nil, "faction" end
	if req.kind == "JOIN" then
		if not isName(req.member) then return nil, "member" end
		if state.members[req.member] then return nil, "ALREADY_JOINED" end
		if state.alts[req.member] and (config or Members().DefaultConfig()).mainOnly then return nil, "IS_ALT" end
		local decl, code = Roster.Complete(req)
		if not decl then return nil, code end
		local bad = twinProblem(state, req.member, req.faction, decl.twin)
		if bad then return nil, bad end
		out.member, out.faction = req.member, req.faction
		for k, v in pairs(decl) do out[k] = v end
	else
		if not isName(req.alt) or req.alt == req.main then return nil, "alt" end
		if not isName(req.main) then return nil, "main" end
		local main = state.members[req.main]
		if not main then return nil, "MAIN_UNKNOWN" end
		if state.members[req.alt] then return nil, "ALT_IS_MAIN" end
		if state.alts[req.alt] then return nil, "ALREADY_LINKED" end
		if req.faction and main.faction and req.faction ~= main.faction then return nil, "FACTION_MISMATCH" end
		out.alt, out.main, out.faction = req.alt, req.main, req.faction
	end
	return out
end

-- Stores a request (a new one from the player, or one received from another client by the transport). `req.id`, when
-- present, is kept (a request received twice is stored once: "DUPLICATE"); a player's second request for the same
-- member or alt replaces his own pending one, another player's gets "REQUEST_PENDING". Returns the stored request, or
-- nil and a code of checkRequest, "REQUEST_LIMIT", "DUPLICATE" or "REQUEST_PENDING".
function Roster.Receive(R, L, req, config)
	if type(R) ~= "table" then return nil, "event" end
	local clean, code = checkRequest(L, req, config)
	if not clean then return nil, code end
	if req.id ~= nil then
		if type(req.id) ~= "string" or req.id == "" then return nil, "id" end
		if R.items[req.id] then return nil, "DUPLICATE" end
		clean.id = req.id
	end
	local key = clean.kind == "JOIN" and clean.member or clean.alt
	local old = pendingFor(R, clean.kind, clean.season, key)
	if old then
		if old.from ~= clean.from then return nil, "REQUEST_PENDING" end
		R.items[old.id] = nil
	elseif pendingCount(R) >= Roster.MAX_REQUESTS then
		return nil, "REQUEST_LIMIT"
	end
	if not clean.id then
		R.seq = R.seq + 1
		clean.id = clean.from .. "#" .. R.seq
	end
	clean.state = "PENDING"
	R.items[clean.id] = clean
	return clean
end

-- The player asks to join the pool with a declaration. req = { from, ts, season, member, faction?, <declaration> }.
function Roster.RequestJoin(R, L, req, config)
	if type(req) ~= "table" then return nil, "event" end
	local r = {}
	for k, v in pairs(req) do r[k] = v end
	r.kind, r.id = "JOIN", nil
	return Roster.Receive(R, L, r, config)
end

-- The player declares an alt of a main. req = { from, ts, season, alt, main, faction? }.
function Roster.RequestAlt(R, L, req, config)
	if type(req) ~= "table" then return nil, "event" end
	local r = {}
	for k, v in pairs(req) do r[k] = v end
	r.kind, r.id = "ALT", nil
	return Roster.Receive(R, L, r, config)
end

-- The pending requests of a season (all when nil), oldest first: the officers' inbox.
function Roster.Pending(R, season)
	local list = {}
	for _, r in pairs(R.items) do
		if r.state == "PENDING" and (season == nil or r.season == season) then list[#list + 1] = r end
	end
	sort(list, function(a, b)
		if a.ts ~= b.ts then return a.ts < b.ts end
		return a.id < b.id
	end)
	return list
end

-- An officer approves a request: the event is written (a MEMBER_JOINED with the declaration or a MEMBER_LINKED_ALT)
-- and the request is marked APPROVED. draft = { author, ts, nights?, late? } (the officer; nights and late go to the
-- late-joiner rule of Members.Join). Returns the event, or nil and "REQUEST_UNKNOWN", "REQUEST_CLOSED" or the code
-- of the writer (the request stays pending: the officer may reject it).
function Roster.Approve(R, L, id, draft, config, opts)
	local r = type(R) == "table" and R.items[id]
	if not r then return nil, "REQUEST_UNKNOWN" end
	if r.state ~= "PENDING" then return nil, "REQUEST_CLOSED" end
	if type(draft) ~= "table" then return nil, "event" end
	local e, code
	if r.kind == "JOIN" then
		local d = { author = draft.author, ts = draft.ts, season = r.season, member = r.member, faction = r.faction,
			nights = draft.nights, late = draft.late }
		for _, f in ipairs(Roster.FIELDS) do d[f] = r[f] end
		e, code = Roster.Join(L, d, config, opts)
	else
		e, code = Members().LinkAlt(L, { author = draft.author, ts = draft.ts, season = r.season, alt = r.alt,
			main = r.main, faction = r.faction }, opts)
	end
	if not e then return nil, code end
	r.state, r.by, r.decidedAt, r.event = "APPROVED", draft.author, draft.ts, e.id
	return e
end

-- An officer rejects a request. Returns true, or nil and "REQUEST_UNKNOWN" / "REQUEST_CLOSED".
function Roster.Reject(R, id, by, ts)
	local r = type(R) == "table" and R.items[id]
	if not r then return nil, "REQUEST_UNKNOWN" end
	if r.state ~= "PENDING" then return nil, "REQUEST_CLOSED" end
	r.state, r.by, r.decidedAt = "REJECTED", by, ts
	return true
end

-- Drops the requests that are no longer pending (approved and rejected ones) older than `before` (a time), and the
-- pending ones of a season that is no longer open. Returns how many were dropped.
function Roster.Prune(R, L, before)
	local n = 0
	for id, r in pairs(R.items) do
		local s = Season().Get(L, r.season)
		local stale = (r.state ~= "PENDING" and (r.decidedAt or 0) < (before or 0)) or not s or s.closed
		if stale then
			R.items[id] = nil
			n = n + 1
		end
	end
	return n
end

---------------------------------------------------------------------------------------------------------------------
-- Import from the guild note (optional): a suggestion, never a write

local function normalize(s)
	return " " .. (tostring(s):lower():gsub("[^%a%d]+", " ")) .. " "
end

local ROLE_WORDS = {
	tank = "TANK", heal = "HEALER", healer = "HEALER", healing = "HEALER", dps = "DAMAGER", damage = "DAMAGER",
}
local STATUS_WORDS = { trial = "TRIAL", prova = "TRIAL", inactive = "INACTIVE", inattivo = "INACTIVE" }

-- Reads a guild note as a roster suggestion. `specs` = { { id, class, name, role }, ... } is the spec table (English
-- names); opts = { class? = the character's class from the guild roster }. The specs named in the note, in the order
-- they appear, are the suggestion for MS1, MS2 and OS; a class word, a role word (tank / healer / dps) and "trial" /
-- "inactive" (also "prova" / "inattivo") are understood. A name shared by two classes ("Holy") is resolved with the
-- class (the roster's, or the one the note names) and is left out, and listed in `ambiguous`, when the class is not
-- known. Returns { class?, role?, ms1?, ms2?, os?, status?, ambiguous = {names} }; pass it to Roster.Join after the officer
-- has read it.
function Roster.ParseNote(note, specs, opts)
	opts = opts or {}
	local out = { ambiguous = {} }
	if type(note) ~= "string" or note == "" then return out end
	local text = normalize(note)

	local class = opts.class and Roster.CLASSES[opts.class] and opts.class or nil
	if not class then
		local found, n = nil, 0
		for c in pairs(Roster.CLASSES) do
			if text:find(normalize(c), 1, true) then found, n = c, n + 1 end
		end
		if n == 1 then class = found end
	end

	-- the spec names that appear, with their position; the longest name wins an overlap
	local byName = {}
	for _, s in ipairs(specs or {}) do
		local key = normalize(s.name)
		byName[key] = byName[key] or {}
		byName[key][#byName[key] + 1] = s
	end
	local hits = {}
	for key, list in pairs(byName) do
		local from = 1
		while true do
			local a, b = text:find(key, from, true)
			if not a then break end
			hits[#hits + 1] = { pos = a, last = b, len = b - a, key = key, list = list }
			from = a + 1
		end
	end
	sort(hits, function(x, y)
		if x.pos ~= y.pos then return x.pos < y.pos end
		return x.len > y.len
	end)
	local picked, lastEnd = {}, 0
	for _, h in ipairs(hits) do
		if h.pos >= lastEnd then
			picked[#picked + 1] = h
			lastEnd = h.last
		end
	end

	local ids, seen = {}, {}
	for _, h in ipairs(picked) do
		local cands = {}
		for _, s in ipairs(h.list) do
			if class == nil or s.class == class then cands[#cands + 1] = s end
		end
		if #cands == 1 then
			if not seen[cands[1].id] then
				seen[cands[1].id] = true
				ids[#ids + 1] = cands[1]
			end
		elseif #cands > 1 then
			out.ambiguous[#out.ambiguous + 1] = h.key:match("^%s*(.-)%s*$")
		end
	end
	if ids[1] then out.ms1 = ids[1].id end
	if ids[2] then out.ms2 = ids[2].id end
	if ids[3] then out.os = ids[3].id end
	out.class = class or (ids[1] and ids[1].class) or nil

	for word in text:gmatch("%S+") do
		if ROLE_WORDS[word] and not out.role then out.role = ROLE_WORDS[word] end
		if STATUS_WORDS[word] and not out.status then out.status = STATUS_WORDS[word] end
	end
	if not out.role and ids[1] then out.role = ids[1].role end
	sort(out.ambiguous)
	return out
end

if ns.addon then ns.addon.Roster = Roster end   -- also reachable from tests
