-- Ledger: the guild's register of events, the only source of truth for credits (docs/ANALISI.md §0 point 2, §7,
-- §8.3). Pure Lua 5.1: it never calls the game. Every function takes the ledger table first; the table holds only
-- strings, numbers, booleans and tables, so it is saved as it is in FinlandDragonCreditPointsDB.
--
-- Events are immutable: { id, author, seq, ts, season, type, v, payload }.
--   author   the character that wrote it ("Name-Realm"); seq = that author's sequence, 1, 2, 3, ...
--   id       author .. ":" .. seq, unique per author, so two officers never collide and a merge is a set union
--   ts       seconds (the caller's clock: the domain never reads the time)
--   season   the season id; nil only for guild-level types (CONFIG_CHANGED, PERMISSIONS_CHANGED)
--   v        the schema version of the payload; older payloads are upgraded on read (Ledger.UPGRADES), a newer
--            version or an unknown type is kept and forwarded (officer sync) but ignored by the computations
--   payload  codes and numbers, never sentences
--
-- Corrections are compensating events, never deletions: AWARD_VOIDED{ref, reason} cancels an ITEM_AWARDED or a
-- CREDITS_ADJUSTED, CREDITS_ADJUSTED{member, delta, reason} moves credits by hand. A voided event is still in the
-- ledger (the audit shows it); a void cannot be voided (write the event again instead).
--
-- Credits are computed, never stored: for a season, credits[member] = initial credits of the member's first
-- MEMBER_JOINED (0 without one) + the cost of every ITEM_AWARDED to the member that is not voided + every
-- CREDITS_ADJUSTED delta that is not voided. The result does not depend on the order the events arrived in.
--
-- Officer sync (M6) exchanges high-water marks: Ledger.Heads gives, per author, the highest seq such that every seq
-- from 1 to it is present; Ledger.Since gives the events a peer with given heads lacks; Ledger.Gaps the seqs still
-- missing. Snapshots cover exactly the events up to the heads at the time they were taken, so the events that arrive
-- later (in any order, even older ones) are always in the tail: snapshot + tail = full ledger.
--
-- Trust (§3.9, §8.4, M2-5): Append and Merge take an optional gate, opts.accept(L, e) -> true | false, code. The
-- gate of Domain/Permissions.lua (Permissions.Gate) accepts an event only when its author had the rank its type
-- requires when it was written, and CONFIG_CHANGED / PERMISSIONS_CHANGED only from the Guild Master. A refused event
-- is not stored (it leaves a hole in its author's sequence, so a later sync asks for it again); an event whose
-- author's rank is not known yet (the guild roster loads asynchronously) comes back as "PENDING" for the caller to
-- queue and merge again. Without a gate every valid event is stored, as before M2-5.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Ledger = {}
ns.Ledger, ns.modules.Ledger = Ledger, Ledger

local type, pairs, ipairs, tostring, tonumber, next = type, pairs, ipairs, tostring, tonumber, next
local floor, sort, huge = math.floor, table.sort, math.huge

Ledger.SCHEMA = 1           -- the layout of the ledger table itself
Ledger.MAX_SNAPSHOTS = 3    -- older snapshots are dropped (the events never are)
Ledger.DECIMALS = 2         -- credits are rounded to this many places, as Pricing rounds costs

-- The event types of §8.3 and the current payload version of each. `guild` = the type has no season.
Ledger.TYPES = {
	SEASON_OPENED = { v = 1 },
	SEASON_CLOSED = { v = 1 },
	MEMBER_JOINED = { v = 1 },
	MEMBER_LINKED_ALT = { v = 1 },
	NIGHT_OPENED = { v = 1 },
	NIGHT_CLOSED = { v = 1 },
	ROSTER_CHANGED = { v = 1 },
	ENCOUNTER_KILLED = { v = 1 },
	PROGRESS_SET = { v = 1 },
	DROP_SEEN = { v = 1 },
	ITEM_AWARDED = { v = 1 },
	AWARD_VOIDED = { v = 1 },
	CREDITS_ADJUSTED = { v = 1 },
	LEGENDARY_PROJECT_OPENED = { v = 1 },
	LEGENDARY_PROJECT_PAID = { v = 1 },
	LEGENDARY_PROJECT_CLOSED = { v = 1 },
	CONFIG_CHANGED = { v = 1, guild = true },
	PERMISSIONS_CHANGED = { v = 1, guild = true },
}

-- The types an AWARD_VOIDED may cancel.
Ledger.VOIDABLE = { ITEM_AWARDED = true, CREDITS_ADJUSTED = true }

-- The targets of an ITEM_AWARDED: only "member" moves credits.
Ledger.TARGETS = { member = true, bank = true, disenchant = true, ml = true }

-- Payload upgrades: UPGRADES[type][v] = function(payload) -> payload of version v + 1 (a new table, the stored
-- event is never changed). Empty while every type is at version 1; a schema change adds its step here.
Ledger.UPGRADES = {}

---------------------------------------------------------------------------------------------------------------------
-- Helpers

local function isCode(s) return type(s) == "string" and s:match("^[A-Z][A-Z0-9_]*$") ~= nil end
local function isName(s) return type(s) == "string" and s ~= "" and not s:find(":", 1, true) end
local function isInt(n) return type(n) == "number" and n == floor(n) and n > -huge and n < huge end
local function isNum(n) return type(n) == "number" and n == n and n > -huge and n < huge end
local function isSeason(s) return (type(s) == "string" and s ~= "") or isInt(s) end

function Ledger.MakeId(author, seq) return author .. ":" .. seq end

-- Splits an id into author and seq (nil when it is not an id).
function Ledger.SplitId(id)
	if type(id) ~= "string" then return nil end
	local author, seq = id:match("^(.+):(%d+)$")
	if not author then return nil end
	return author, tonumber(seq)
end

local function round(x)
	local p = 10 ^ Ledger.DECIMALS
	if x < 0 then return -floor(-x * p + 0.5) / p end
	return floor(x * p + 0.5) / p
end
Ledger.Round = round

-- Only plain data in a payload: strings, finite numbers, booleans and tables of them (string or number keys).
local function plainData(v, depth)
	local t = type(v)
	if t == "string" or t == "boolean" then return true end
	if t == "number" then return isNum(v) end
	if t ~= "table" or depth > 6 then return false end
	for k, x in pairs(v) do
		local tk = type(k)
		if not (tk == "string" or (tk == "number" and isNum(k))) then return false end
		if not plainData(x, depth + 1) then return false end
	end
	return true
end

local function copy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = copy(x) end
	return c
end

local function deepEqual(a, b)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, x in pairs(a) do
		if not deepEqual(x, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

local function codeList(list)
	if list == nil then return true end
	if type(list) ~= "table" then return false end
	for _, c in pairs(list) do
		if not isCode(c) then return false end
	end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Payload checks of the types the computations read (current version). The others only need plain data; their
-- steps (M2-4 seasons, M3 nights, M3-3b progress, M6 legendaries) tighten them.

local CHECKS = {}
Ledger.CHECKS = CHECKS   -- later modules (Rules, Permissions) register the checks of their own types here

-- The factions a member may declare (the client's UnitFactionGroup tokens).
Ledger.FACTIONS = { Horde = true, Alliance = true }
-- The raid sizes of a season's pack (§2, §6).
Ledger.RAID_SIZES = { [10] = true, [20] = true, [40] = true }

CHECKS.MEMBER_JOINED = function(p)
	if not isName(p.member) then return "member" end
	if p.initialCredits ~= nil and not isNum(p.initialCredits) then return "initialCredits" end
	if p.faction ~= nil and not Ledger.FACTIONS[p.faction] then return "faction" end
	if p.rule ~= nil and not isCode(p.rule) then return "rule" end
	if p.basis ~= nil and (not isInt(p.basis) or p.basis < 0) then return "basis" end
end

CHECKS.MEMBER_LINKED_ALT = function(p)
	if not isName(p.alt) then return "alt" end
	if not isName(p.main) then return "main" end
	if p.alt == p.main then return "alt" end
	if p.faction ~= nil and not Ledger.FACTIONS[p.faction] then return "faction" end
end

-- SEASON_OPENED{label?, instances = {{id, size}, ...}, startCredits}: the pack of raids of the season (one credit
-- table for every instance, size and difficulty). `label` is the name the GM gives the season (data, not text).
CHECKS.SEASON_OPENED = function(p)
	if p.label ~= nil and (type(p.label) ~= "string" or p.label == "") then return "label" end
	if type(p.instances) ~= "table" or #p.instances == 0 then return "instances" end
	local seen = {}
	for i, inst in pairs(p.instances) do
		if not isInt(i) or i < 1 or i > #p.instances then return "instances" end
		if type(inst) ~= "table" or not isInt(inst.id) or inst.id <= 0 or seen[inst.id] then return "instances" end
		if not Ledger.RAID_SIZES[inst.size] then return "instances" end
		seen[inst.id] = true
	end
	if not isNum(p.startCredits) or p.startCredits < 0 then return "startCredits" end
end

CHECKS.ITEM_AWARDED = function(p)
	local target = p.target or "member"
	if not Ledger.TARGETS[target] then return "target" end
	if target == "member" and not isName(p.member) then return "member" end
	if not isInt(p.item) or p.item <= 0 then return "item" end
	if not isNum(p.cost) or p.cost < 0 then return "cost" end
	if p.response ~= nil and not isCode(p.response) then return "response" end
	if not codeList(p.reasons) then return "reasons" end
	if not codeList(p.flags) then return "flags" end
end

CHECKS.CREDITS_ADJUSTED = function(p)
	if not isName(p.member) then return "member" end
	if not isNum(p.delta) or p.delta == 0 then return "delta" end
	if not isCode(p.reason) then return "reason" end
end

CHECKS.AWARD_VOIDED = function(p)
	if not Ledger.SplitId(p.ref) then return "ref" end
	if not isCode(p.reason) then return "reason" end
end

CHECKS.ENCOUNTER_KILLED = function(p)
	if not isInt(p.encounterID) or p.encounterID <= 0 then return "encounterID" end
	if p.date ~= nil and not (type(p.date) == "string" and p.date:match("^%d%d%d%d%-%d%d%-%d%d$")) then return "date" end
end

CHECKS.PROGRESS_SET = function(p)
	if not isInt(p.encounterID) or p.encounterID <= 0 then return "encounterID" end
	if not (type(p.date) == "string" and p.date:match("^%d%d%d%d%-%d%d%-%d%d$")) then return "date" end
	if p.faction ~= nil and (type(p.faction) ~= "string" or p.faction == "") then return "faction" end
end

-- Checks the envelope of an event (and its payload when the type and version are known). Returns true, or false and
-- a code: "event", "id", "author", "seq", "ts", "type", "v", "season", "payload" or "payload:<field>".
function Ledger.Check(e)
	if type(e) ~= "table" then return false, "event" end
	if not isName(e.author) then return false, "author" end
	if not isInt(e.seq) or e.seq < 1 then return false, "seq" end
	if e.id ~= Ledger.MakeId(e.author, e.seq) then return false, "id" end
	if not isNum(e.ts) or e.ts < 0 then return false, "ts" end
	if not isCode(e.type) then return false, "type" end
	if not isInt(e.v) or e.v < 1 then return false, "v" end
	if type(e.payload) ~= "table" or not plainData(e.payload, 0) then return false, "payload" end
	local spec = Ledger.TYPES[e.type]
	if spec and spec.guild then
		if e.season ~= nil and not isSeason(e.season) then return false, "season" end
	elseif not isSeason(e.season) then
		-- An unknown type from a newer addon must carry a season or be guild-level: accept both, check the value.
		if spec or e.season ~= nil then return false, "season" end
	end
	if spec and e.v <= spec.v then
		-- Without an upgrade step the payload cannot be read: the event is kept (for sync) but never read.
		local payload = Ledger.Payload(e)
		local check = CHECKS[e.type]
		local bad = payload and check and check(payload)
		if bad then return false, "payload:" .. bad end
	end
	return true
end

-- The payload of an event at the current version of its type, or nil when the type is unknown, the version is
-- newer than this addon's, or an upgrade step is missing. The stored event is never modified.
function Ledger.Payload(e)
	local spec = Ledger.TYPES[e.type]
	if not spec or e.v > spec.v then return nil end
	local payload, v = e.payload, e.v
	while v < spec.v do
		local step = Ledger.UPGRADES[e.type] and Ledger.UPGRADES[e.type][v]
		if not step then return nil end
		payload = step(copy(payload))
		v = v + 1
	end
	return payload
end

-- True when the computations read this event (known type, readable version, valid).
local function readable(e)
	return Ledger.Payload(e) ~= nil and (Ledger.Check(e))
end
Ledger.Readable = readable

---------------------------------------------------------------------------------------------------------------------
-- The ledger table

-- Makes a new ledger, or adopts a saved one (fills the missing fields). Returns the ledger and `readOnly`: true when
-- the table was written by a newer addon (schema above Ledger.SCHEMA); then nothing may be appended or merged.
function Ledger.Open(t)
	t = type(t) == "table" and t or {}
	t.schema = t.schema or Ledger.SCHEMA
	t.events = t.events or {}      -- [id] = event
	t.heads = t.heads or {}        -- [author] = contiguous high-water mark
	t.top = t.top or {}            -- [author] = highest seq present
	t.snapshots = t.snapshots or {}
	return t, t.schema > Ledger.SCHEMA
end

function Ledger.New() return (Ledger.Open({})) end

function Ledger.Get(L, id) return L.events[id] end

function Ledger.Count(L)
	local n = 0
	for _ in pairs(L.events) do n = n + 1 end
	return n
end

local function advanceHead(L, author)
	local h = L.heads[author] or 0
	while L.events[Ledger.MakeId(author, h + 1)] do h = h + 1 end
	L.heads[author] = h
end

-- Stores an event that passed the checks. Returns "ADDED", "DUPLICATE" or "CONFLICT" (same id, other content: the
-- stored one wins, nothing changes).
local function store(L, e)
	local old = L.events[e.id]
	if old then
		if deepEqual(old, e) then return "DUPLICATE" end
		return "CONFLICT"
	end
	L.events[e.id] = copy(e)
	if e.seq > (L.top[e.author] or 0) then L.top[e.author] = e.seq end
	if e.seq == (L.heads[e.author] or 0) + 1 then advanceHead(L, e.author) end
	return "ADDED"
end

-- The canonical order of events: time, then author, then sequence. Deterministic on every client.
local function before(a, b)
	if a.ts ~= b.ts then return a.ts < b.ts end
	if a.author ~= b.author then return a.author < b.author end
	return a.seq < b.seq
end
Ledger.Before = before

-- All events (or those for which keep(e) is true) in canonical order.
function Ledger.Sorted(L, keep)
	local list = {}
	for _, e in pairs(L.events) do
		if not keep or keep(e) then list[#list + 1] = e end
	end
	sort(list, before)
	return list
end

-- The last readable event of type `typ` that comes before `at` in canonical order (`at` = an event, stored or not, or
-- nil for "now": the last of all). Rules and permissions in force when an event was written come from here.
function Ledger.LatestBefore(L, typ, at)
	local best
	for _, e in pairs(L.events) do
		if e.type == typ and (at == nil or before(e, at)) and readable(e) and (not best or before(best, e)) then
			best = e
		end
	end
	return best
end

-- Writes a new event of `author`: draft = { author, type, ts, season, payload }. The sequence is the author's next
-- one. A void must reference an event of this ledger that is voidable and not voided yet. opts.accept is the trust
-- gate (see the header). Returns the stored event, or nil and a code ("READ_ONLY", a Ledger.Check code,
-- "UNKNOWN_TYPE", "REF_MISSING", "REF_NOT_VOIDABLE", "ALREADY_VOIDED", or the gate's code, "PENDING" included).
function Ledger.Append(L, draft, opts)
	if (L.schema or 0) > Ledger.SCHEMA then return nil, "READ_ONLY" end
	if type(draft) ~= "table" then return nil, "event" end
	local spec = Ledger.TYPES[draft.type]
	if not spec then return nil, "UNKNOWN_TYPE" end
	if not isName(draft.author) then return nil, "author" end
	local seq = (L.top[draft.author] or 0) + 1
	local e = {
		id = Ledger.MakeId(draft.author, seq), author = draft.author, seq = seq, ts = draft.ts,
		season = draft.season, type = draft.type, v = spec.v, payload = copy(draft.payload or {}),
	}
	local ok, code = Ledger.Check(e)
	if not ok then return nil, code end
	if e.type == "AWARD_VOIDED" then
		local ref = L.events[e.payload.ref]
		if not ref then return nil, "REF_MISSING" end
		if not Ledger.VOIDABLE[ref.type] then return nil, "REF_NOT_VOIDABLE" end
		if Ledger.IsVoided(L, ref.id) then return nil, "ALREADY_VOIDED" end
	end
	if opts and opts.accept then
		local accepted, why = opts.accept(L, e)
		if not accepted then return nil, why or "REFUSED" end
	end
	store(L, e)
	return L.events[e.id]
end

-- Merges events from another ledger or a peer, in any order, any number of times. Invalid events are refused, an
-- event already present changes nothing. The new events are stored in canonical order, so with a gate (opts.accept,
-- see the header) a PERMISSIONS_CHANGED of the batch is in force for the later events of the same batch. Returns a
-- report { added, duplicate, conflict = {ids}, invalid = {codes}, refused = {{id, code}}, pending = {events} }, or
-- nil and "READ_ONLY". `pending` are the events the gate could not decide yet (the caller queues them).
function Ledger.Merge(L, events, opts)
	if (L.schema or 0) > Ledger.SCHEMA then return nil, "READ_ONLY" end
	local report = { added = 0, duplicate = 0, conflict = {}, invalid = {}, refused = {}, pending = {} }
	local valid = {}
	for _, e in pairs(events or {}) do
		local ok, code = Ledger.Check(e)
		if not ok then
			report.invalid[#report.invalid + 1] = code
		else
			valid[#valid + 1] = e
		end
	end
	sort(valid, before)
	local accept = opts and opts.accept
	for _, e in ipairs(valid) do
		local accepted, why = true, nil
		if accept and not L.events[e.id] then accepted, why = accept(L, e) end
		if accepted then
			local r = store(L, e)
			if r == "ADDED" then
				report.added = report.added + 1
			elseif r == "DUPLICATE" then
				report.duplicate = report.duplicate + 1
			else
				report.conflict[#report.conflict + 1] = e.id
			end
		elseif why == "PENDING" then
			report.pending[#report.pending + 1] = e
		else
			report.refused[#report.refused + 1] = { id = e.id, code = why or "REFUSED" }
		end
	end
	sort(report.conflict)
	return report
end

---------------------------------------------------------------------------------------------------------------------
-- Sync helpers (M6): high-water marks per author

-- { [author] = h }: every seq from 1 to h of that author is present.
function Ledger.Heads(L)
	return copy(L.heads)
end

-- The events a peer with `heads` lacks (seq above its mark for that author), in canonical order.
function Ledger.Since(L, heads)
	heads = heads or {}
	return Ledger.Sorted(L, function(e) return e.seq > (heads[e.author] or 0) end)
end

-- { [author] = { missing seqs, ascending } } for every author with holes below its highest seq.
function Ledger.Gaps(L)
	local gaps = {}
	for author, top in pairs(L.top) do
		local h = L.heads[author] or 0
		if top > h then
			local list = {}
			for s = h + 1, top do
				if not L.events[Ledger.MakeId(author, s)] then list[#list + 1] = s end
			end
			gaps[author] = list
		end
	end
	return gaps
end

---------------------------------------------------------------------------------------------------------------------
-- The computation (a fold over the events)

-- The fold state, plain data so it can be stored in a snapshot:
--   seasons[season] = { spent = {[member] = n}, joined = {[member] = {ts, author, seq, credits}} }
--   voided[ref] = id of the first void (canonical order) that cancelled it
local function newState()
	return { seasons = {}, voided = {} }
end

local function seasonOf(state, season)
	local s = state.seasons[season]
	if not s then
		s = { spent = {}, joined = {} }
		state.seasons[season] = s
	end
	return s
end

local function addSpent(state, season, member, amount)
	local s = seasonOf(state, season)
	s.spent[member] = (s.spent[member] or 0) + amount
end

-- The credits an event moves, as (member, amount), or nil.
local function effect(e, payload)
	if e.type == "ITEM_AWARDED" then
		if (payload.target or "member") == "member" and payload.cost ~= 0 then return payload.member, payload.cost end
	elseif e.type == "CREDITS_ADJUSTED" then
		return payload.member, payload.delta
	end
end

-- Folds `events` (canonical order) into `state`. `covered(e)` is true for the events already folded into the state
-- (the snapshot's), so a void in the tail can take back an award the snapshot counted.
local function fold(L, state, events, covered)
	local applied = {}
	local function wasApplied(ref)
		return applied[ref.id] or (covered(ref) and readable(ref))
	end
	for _, e in ipairs(events) do
		local payload = readable(e) and Ledger.Payload(e)
		if payload then
			if e.type == "MEMBER_JOINED" then
				local s = seasonOf(state, e.season)
				local cur = s.joined[payload.member]
				if not cur or before(e, cur) then
					s.joined[payload.member] = { ts = e.ts, author = e.author, seq = e.seq,
						credits = payload.initialCredits or 0 }
				end
			elseif Ledger.VOIDABLE[e.type] then
				local member, amount = effect(e, payload)
				if not state.voided[e.id] then
					applied[e.id] = true
					if member then addSpent(state, e.season, member, amount) end
				end
			elseif e.type == "AWARD_VOIDED" then
				local refId = payload.ref
				local prior = state.voided[refId]
				if not prior then
					state.voided[refId] = e.id
					local ref = L.events[refId]
					if ref and Ledger.VOIDABLE[ref.type] and wasApplied(ref) then
						local member, amount = effect(ref, Ledger.Payload(ref))
						if member then addSpent(state, ref.season, member, -amount) end
					end
				end
			end
		end
	end
	return state
end

local function coveredBy(heads)
	return function(e) return e.seq <= (heads[e.author] or 0) end
end

-- Takes a snapshot of the state over the events up to the current heads (the contiguous ones). `ts` is stored for
-- the UI. Keeps the newest Ledger.MAX_SNAPSHOTS. Returns the snapshot.
function Ledger.TakeSnapshot(L, ts)
	local heads = copy(L.heads)
	local covered = coveredBy(heads)
	local state = fold(L, newState(), Ledger.Sorted(L, covered), function() return false end)
	local snap = { ts = ts, heads = heads, count = 0, state = state }
	for _, e in pairs(L.events) do
		if covered(e) then snap.count = snap.count + 1 end
	end
	L.snapshots[#L.snapshots + 1] = snap
	while #L.snapshots > Ledger.MAX_SNAPSHOTS do table.remove(L.snapshots, 1) end
	return snap
end

-- The full state: from the newest snapshot plus the tail, or from scratch with opts.full.
function Ledger.State(L, opts)
	local snap = not (opts and opts.full) and L.snapshots[#L.snapshots] or nil
	if not snap then
		return fold(L, newState(), Ledger.Sorted(L), function() return false end)
	end
	local covered = coveredBy(snap.heads)
	local tail = Ledger.Sorted(L, function(e) return not covered(e) end)
	return fold(L, copy(snap.state), tail, covered)
end

-- Credits of a season: { [member] = n }, rounded to Ledger.DECIMALS places. opts.full ignores the snapshots.
function Ledger.Credits(L, season, opts)
	local s = Ledger.State(L, opts).seasons[season]
	local out = {}
	if not s then return out end
	for member, j in pairs(s.joined) do out[member] = j.credits end
	for member, n in pairs(s.spent) do out[member] = (out[member] or 0) + n end
	for member, n in pairs(out) do out[member] = round(n) end
	return out
end

-- True when an AWARD_VOIDED that can be read cancels the event `id` (whatever order they arrived in).
function Ledger.IsVoided(L, id)
	for _, e in pairs(L.events) do
		if e.type == "AWARD_VOIDED" then
			local p = readable(e) and Ledger.Payload(e)
			if p and p.ref == id then return true end
		end
	end
	return false
end

-- The first kill of every encounter: { [encounterID] = "YYYY-MM-DD" }, the oldest date among ENCOUNTER_KILLED (with
-- a date) and PROGRESS_SET (of `faction` when given) events, for the Progress export (docs/specs/site-export.md).
function Ledger.FirstKills(L, faction)
	local out = {}
	for _, e in pairs(L.events) do
		local p = (e.type == "ENCOUNTER_KILLED" or e.type == "PROGRESS_SET") and readable(e) and Ledger.Payload(e)
		if p and p.date and (e.type == "ENCOUNTER_KILLED" or faction == nil or p.faction == nil or p.faction == faction) then
			local cur = out[p.encounterID]
			if not cur or p.date < cur then out[p.encounterID] = p.date end
		end
	end
	return out
end

-- Counts for the UI and the audit: { events, unreadable } (unknown types or newer versions kept for sync).
function Ledger.Stats(L)
	local n, unreadable = 0, 0
	for _, e in pairs(L.events) do
		n = n + 1
		if not readable(e) then unreadable = unreadable + 1 end
	end
	return { events = n, unreadable = unreadable }
end

if ns.addon then ns.addon.Ledger = Ledger end   -- also reachable from tests
