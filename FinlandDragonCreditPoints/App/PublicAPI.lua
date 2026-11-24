-- PublicAPI: the public, read-only, versioned API other addons read (docs/ANALISI.md §8.6, ADR 0009, M8-1). Lua 5.1.
--
-- One global table, `FinlandDragonCreditPointsAPI`, whose name never changes. It is made for Azeroth Accord (the guild hub
-- of the same author) and open to any other addon. FDCP never depends on the reader and never reads its data: the API
-- only answers.
--
-- Rules:
-- * Read-only. Every getter builds a fresh copy (plain tables of strings, numbers and booleans), never an internal
--   table, so nothing a caller does can change FDCP's state. The API table itself ignores writes and hides its
--   metatable.
-- * Nothing raises. Every function runs protected; a wrong argument, data that is not on this client, or an internal
--   error gives nil (or an empty list where a list is expected).
-- * Versioned. `API_VERSION` is an integer bumped only on a breaking change (a field removed or changing meaning, a
--   function removed). New fields and functions do not bump it: a reader ignores what it does not know.
-- * Only what this client shows its player in FDCP's own windows. The source is the one the Credits tab uses: an
--   officer's client reads the guild's ledger (Net/Sync.lua), every other member's client the read-only credits table
--   an officer sent (Net/Snapshot.lua, ADR 0006). **Attendance and absences are never exposed** (officers only, §6),
--   nor the player's free roster note, the audit, the log or the council.
--
--   getter          officer's client (LEDGER)                       member's client (SNAPSHOT)
--   GetSeason       id, name, state, updated                        same, plus asOf (when the officer made it)
--   GetPool         every main of the season, every field           the playing mains (active, trial): name, faction,
--                                                                   class, role, ms1, status, alts; ms2, os, twin,
--                                                                   avail are nil (the table does not carry them)
--   GetCredits      credits and queue place                         same (the numbers of the snapshot)
--   GetNight        the open night and its raid / bench lists       nil (a member's client has no nights)
--   GetRules        the guild's rules (source GUILD)                the defaults of the Patto preset (source DEFAULT):
--                                                                   a member's client has no rules of its own
--
-- Change notifications: RegisterCallback(event, fn); fn(event) runs protected (a failing callback is counted and logged,
-- FDCP and the other callbacks go on). A timer checks once a second, only while there are callbacks, and compares what
-- the getters give: an event fires once per change, never for a change that only touched other data.
--
-- Not verified in the real client: another addon reading the table, the ticker's cost in a raid.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local PublicAPI = {}
ns.PublicAPI, ns.modules.PublicAPI = PublicAPI, PublicAPI

local type, pairs, ipairs, tostring, pcall, sort, concat = type, pairs, ipairs, tostring, pcall, table.sort, table.concat

PublicAPI.GLOBAL = "FinlandDragonCreditPointsAPI"
PublicAPI.API_VERSION = 1
PublicAPI.TICK = 1                  -- seconds between two checks for changes (only while there are callbacks)
PublicAPI.MAX_CALLBACKS = 32        -- per event
PublicAPI.EVENTS = { "READY", "SEASON_CHANGED", "POOL_CHANGED", "CREDITS_CHANGED", "NIGHT_CHANGED", "RULES_CHANGED" }
local IS_EVENT = {}
for _, e in ipairs(PublicAPI.EVENTS) do IS_EVENT[e] = true end

local function log(level, code, ...) if ns.Log then ns.Log[level]("API", code, ...) end end

---------------------------------------------------------------------------------------------------------------------
-- Copies

-- A deep copy of plain data: strings, numbers, booleans and tables of them (functions and userdata are dropped).
local function copy(v)
	local t = type(v)
	if t == "table" then
		local out = {}
		for k, x in pairs(v) do
			local tk = type(k)
			if tk == "string" or tk == "number" then out[k] = copy(x) end
		end
		return out
	end
	if t == "string" or t == "number" or t == "boolean" then return v end
	return nil
end
PublicAPI.Copy = copy

local function list(v)
	if type(v) ~= "table" then return nil end
	local out = {}
	for i, x in ipairs(v) do out[i] = copy(x) end
	return out
end

-- A deterministic text of plain data (the fingerprint the change check compares).
local function serialize(v, out)
	local t = type(v)
	if t == "table" then
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		sort(keys, function(a, b)
			if type(a) ~= type(b) then return type(a) < type(b) end
			return a < b
		end)
		out[#out + 1] = "{"
		for _, k in ipairs(keys) do
			out[#out + 1] = tostring(k)
			out[#out + 1] = "="
			serialize(v[k], out)
			out[#out + 1] = ","
		end
		out[#out + 1] = "}"
	else
		out[#out + 1] = t:sub(1, 1) .. tostring(v)
	end
	return out
end
function PublicAPI.Fingerprint(v) return concat(serialize(v, {})) end

---------------------------------------------------------------------------------------------------------------------
-- The source of the data

local function me() return ns.GuildRanks and ns.GuildRanks.Me() or nil end

-- True once FDCP knows who the player is and has read the guild roster (the permission service is ready): from then on
-- every getter answers from the right source. A player outside a guild never becomes ready.
function PublicAPI:IsReady()
	local PS = ns.PermissionService
	return PS ~= nil and PS:IsReady() == true and me() ~= nil
end

-- "LEDGER", L (an officer's client whose ledger has a season), "SNAPSHOT", snapshot (any other client that keeps the
-- table an officer sent), or nil (not ready, or no data on this client). The same choice as the Credits tab, except that
-- a client that is not an officer never reads a ledger of its own.
function PublicAPI:Source()
	if not self:IsReady() then return nil end
	local Snap = ns.Snapshot
	if Snap and Snap:IsOfficer() then
		local L = ns.NightController and ns.NightController:Ledger()
		if L and #ns.Season.List(L) > 0 then return "LEDGER", L end
	end
	local kept = Snap and Snap:Kept()
	if kept and type(kept.data) == "table" then return "SNAPSHOT", kept.data end
	return nil
end

-- The season a ledger shows: the open one, else the newest (the snapshot's rule, Domain/CreditSnapshot.lua).
local function ledgerSeason(L)
	local cur = ns.Season.Current(L)
	if cur then return cur end
	local all = ns.Season.List(L)
	return all[#all]
end

---------------------------------------------------------------------------------------------------------------------
-- Getters (internal: they may raise; the public table wraps them)

function PublicAPI:Version()
	local v = ns.Protocol and ns.Protocol.AddonVersion() or "dev"
	return tostring(v), self.API_VERSION
end

function PublicAPI:Season()
	local kind, src = self:Source()
	if kind == "LEDGER" then
		local s = ledgerSeason(src)
		if not s then return nil end
		local updated
		for _, n in ipairs(ns.Nights.List(src, s.id)) do
			if n.date and (not updated or n.date > updated) then updated = n.date end
		end
		return { id = s.id, name = s.label, state = s.closed and "CLOSED" or "OPEN", updated = updated }
	elseif kind == "SNAPSHOT" then
		return { id = src.s, name = src.sl, state = src.so and "OPEN" or "CLOSED", updated = src.up, asOf = src.ts }
	end
	return nil
end

local function poolEntry(m)
	return {
		name = m.member, faction = m.faction, class = m.class, role = m.role, ms1 = m.ms1, ms2 = m.ms2, os = m.os,
		status = m.status or "ACTIVE", alts = list(m.alts) or {}, twin = m.twin, avail = list(m.avail),
	}
end

local function snapshotEntry(r)
	return { name = r.m, faction = r.f, class = r.c, role = r.ro, ms1 = r.sp, status = r.st or "ACTIVE", alts = list(r.al) or {} }
end

-- The mains of the season's pool, sorted by name.
function PublicAPI:Pool()
	local kind, src = self:Source()
	local out = {}
	if kind == "LEDGER" then
		local s = ledgerSeason(src)
		if s then
			for _, m in pairs(ns.Roster.State(src, s.id).members) do out[#out + 1] = poolEntry(m) end
		end
	elseif kind == "SNAPSHOT" then
		for _, r in ipairs(src.r or {}) do out[#out + 1] = snapshotEntry(r) end
	end
	sort(out, function(a, b) return a.name < b.name end)
	return out
end

local function fullName(name)
	if type(name) ~= "string" or name == "" then return nil end
	return ns.GuildRanks and ns.GuildRanks.FullName(name) or name
end

-- The pool entry of a character (an alt gives its main, with `viaAlt`), or nil.
function PublicAPI:Member(name)
	name = fullName(name)
	if not name then return nil end
	for _, e in ipairs(self:Pool()) do
		if e.name == name then return e end
		for _, a in ipairs(e.alts) do
			if a == name then
				e.viaAlt = true
				return e
			end
		end
	end
	return nil
end

-- The credits table of the season as the Credits tab builds it, for one faction (nil = both).
local function creditRows(kind, src, faction)
	if kind == "LEDGER" then
		local s = ledgerSeason(src)
		local data = s and ns.CreditTable.Build(src, s.id, { faction = faction })
		return data and data.rows or {}
	elseif kind == "SNAPSHOT" then
		local data = ns.CreditSnapshot.Table(src, nil, faction)
		return data and data.rows or {}
	end
	return {}
end

-- { name (the main), credits, place, of, faction, viaAlt } for a character of the pool, or nil. `place` is the place in
-- the loot queue of the Credits tab (fewest credits first, then the name), counted among the playing mains of the
-- member's faction; `of` is how many they are. An inactive member has credits but no place.
function PublicAPI:Credits(name)
	local kind, src = self:Source()
	if not kind then return nil end
	local entry = self:Member(name)
	if not entry then return nil end
	local rows = creditRows(kind, src, entry.faction)
	for _, r in ipairs(rows) do
		if r.member == entry.name then
			return { name = entry.name, credits = r.total, place = r.rank, of = #rows, faction = entry.faction,
				viaAlt = entry.viaAlt == true }
		end
	end
	if kind == "LEDGER" then
		local s = ledgerSeason(src)
		local total = s and ns.Ledger.Credits(src, s.id)[entry.name]
		if total then
			return { name = entry.name, credits = total, of = #rows, faction = entry.faction, viaAlt = entry.viaAlt == true }
		end
	end
	return nil
end

-- Every playing main's credits and place, one list per call: { { name, credits, place, of, faction } ... }, by faction
-- then place.
function PublicAPI:CreditList()
	local kind, src = self:Source()
	local out, seen = {}, {}
	if not kind then return out end
	for _, faction in ipairs({ "Alliance", "Horde" }) do
		local rows = creditRows(kind, src, faction)
		for _, r in ipairs(rows) do
			if not seen[r.member] then
				seen[r.member] = true
				out[#out + 1] = { name = r.member, credits = r.total, place = r.rank, of = #rows, faction = r.faction }
			end
		end
	end
	-- a member without a faction (an older ledger) that no faction's table listed: from the whole table
	local all = creditRows(kind, src, nil)
	for _, r in ipairs(all) do
		if not seen[r.member] then
			seen[r.member] = true
			out[#out + 1] = { name = r.member, credits = r.total, place = r.rank, of = #all }
		end
	end
	return out
end

-- The open night: { id, date, instanceID, instance (name), size, difficulty, faction, raid = { names }, bench = { names } }
-- or nil. Only who is in the raid and who is on the bench: the absent list is attendance and stays with the officers.
function PublicAPI:Night()
	local kind, L = self:Source()
	if kind ~= "LEDGER" then return nil end
	local s = ns.Season.Current(L)
	local night = s and ns.Nights.Current(L, s.id)
	if not night then return nil end
	local lists = ns.Nights.Lists((ns.Nights.Lineup(L, night.id)))
	local inst = ns.Instances and ns.Instances.Get(night.instanceID)
	return {
		id = night.id, date = night.date, instanceID = night.instanceID, instance = inst and inst.name or nil,
		size = night.size, difficulty = night.difficulty, faction = night.faction,
		raid = list(lists.raid) or {}, bench = list(lists.bench) or {},
	}
end

-- A short summary of the loot rules, for a guild handbook page.
function PublicAPI:Rules()
	local kind, L = self:Source()
	local rules, preset, source
	if kind == "LEDGER" then
		local eventId
		rules, eventId = ns.Rules.Current(L)
		local e = eventId and L.events[eventId]
		local p = e and ns.Ledger.Payload(e)
		preset = p and p.preset or nil
		source = eventId and "GUILD" or "DEFAULT"
		if not eventId then preset = ns.Presets.DEFAULT end
	else
		if not self:IsReady() then return nil end
		rules, preset, source = ns.Rules.DefaultConfig(), ns.Presets.DEFAULT, "DEFAULT"
	end
	local matched = ns.Presets.Match(rules)
	local cost = rules.cost or {}
	local costs = {}
	for category, row in pairs(cost.matrix or {}) do
		costs[category] = {}
		for q, cell in pairs(row) do costs[category][q] = cell end
	end
	return {
		source = source,
		preset = matched or preset,
		custom = matched == nil,
		metric = rules.priority and rules.priority.metric,
		startCredits = rules.season and rules.season.startCredits,
		costs = costs,
		responseMultiplier = copy(cost.responseMultiplier),
		lateJoin = rules.members and rules.members.lateJoin and rules.members.lateJoin.method,
		bench = rules.bench and { effect = rules.bench.creditEffect, amount = rules.bench.creditAmount },
		penalties = rules.penalties and { absence = rules.penalties.absence, cheat = rules.penalties.cheat },
		awardMode = rules.session and rules.session.awardMode,
	}
end

---------------------------------------------------------------------------------------------------------------------
-- Callbacks

PublicAPI.callbacks = {}      -- [event] = { fn, ... } in the order they registered
PublicAPI.prints = {}         -- [event] = the fingerprint at the last check
PublicAPI.stats = { fired = 0, errors = 0, checks = 0 }

local WATCH = {
	READY = function(self) return self:IsReady() and "1" or "0" end,
	SEASON_CHANGED = function(self) return PublicAPI.Fingerprint(self:Season()) end,
	POOL_CHANGED = function(self) return PublicAPI.Fingerprint(self:Pool()) end,
	CREDITS_CHANGED = function(self) return PublicAPI.Fingerprint(self:CreditList()) end,
	NIGHT_CHANGED = function(self) return PublicAPI.Fingerprint(self:Night()) end,
	RULES_CHANGED = function(self) return PublicAPI.Fingerprint(self:Rules()) end,
}

local function fingerprint(self, event)
	local ok, fp = pcall(WATCH[event], self)
	return ok and fp or "!error"
end

-- Runs every callback of `event` protected. Returns how many ran.
function PublicAPI:Fire(event)
	local cbs = self.callbacks[event]
	if not cbs or #cbs == 0 then return 0 end
	local snapshot = {}
	for i, fn in ipairs(cbs) do snapshot[i] = fn end
	for _, fn in ipairs(snapshot) do
		local ok, err = pcall(fn, event)
		self.stats.fired = self.stats.fired + 1
		if not ok then
			self.stats.errors = self.stats.errors + 1
			log("warn", "CALLBACK_ERROR", event, ns.Log and ns.Log.Plain(tostring(err):sub(1, 80)) or "")
		end
	end
	return #snapshot
end

-- Compares what each watched getter gives now with the last check and fires the events that changed. Returns the list
-- of events fired.
function PublicAPI:Check()
	self.stats.checks = self.stats.checks + 1
	local fired = {}
	for _, event in ipairs(self.EVENTS) do
		local cbs = self.callbacks[event]
		if cbs and #cbs > 0 then
			local fp = fingerprint(self, event)
			if self.prints[event] ~= fp then
				self.prints[event] = fp
				fired[#fired + 1] = event
			end
		end
	end
	for _, event in ipairs(fired) do self:Fire(event) end
	return fired
end

-- A cheap key of everything the getters depend on: the check runs when it changes (or at least every 30 ticks).
function PublicAPI:Key()
	local kind, src = self:Source()
	local L = kind == "LEDGER" and src or nil
	local kept = ns.Snapshot and ns.Snapshot:Kept()
	local snap = kept and type(kept.data) == "table" and kept.data or nil
	return concat({
		tostring(self:IsReady()), tostring(kind), tostring(ns.Config and ns.Config.GuildKey and ns.Config:GuildKey()),
		tostring(L and ns.Ledger.Seen(L) or "-"), tostring(snap and snap.k or "-"), tostring(snap and snap.ts or "-"),
	}, "|")
end

function PublicAPI:Tick()
	local any = false
	for _, cbs in pairs(self.callbacks) do if #cbs > 0 then any = true break end end
	if not any then return end
	self.ticks = (self.ticks or 0) + 1
	local ok, key = pcall(self.Key, self)
	key = ok and key or "!error"
	if key ~= self.lastKey or self.ticks >= 30 then
		self.lastKey, self.ticks = key, 0
		self:Check()
	end
end

function PublicAPI:Start()
	if self.ticker then return true end
	if not (ns.Compat and ns.Compat.NewTicker) then return false end
	self.ticker = ns.Compat.NewTicker(self.TICK, function() PublicAPI:Tick() end)
	return self.ticker ~= nil
end

-- true, or nil and a code: "UNKNOWN_EVENT", "BAD_CALLBACK", "TOO_MANY". The same function twice is kept once.
function PublicAPI:Register(event, fn)
	if not IS_EVENT[event] then return nil, "UNKNOWN_EVENT" end
	if type(fn) ~= "function" then return nil, "BAD_CALLBACK" end
	local cbs = self.callbacks[event]
	if not cbs then cbs = {}; self.callbacks[event] = cbs end
	for _, f in ipairs(cbs) do if f == fn then return true end end
	if #cbs >= self.MAX_CALLBACKS then return nil, "TOO_MANY" end
	if #cbs == 0 then self.prints[event] = fingerprint(self, event) end   -- the state now: only later changes fire
	cbs[#cbs + 1] = fn
	self:Start()
	return true
end

-- true when it was registered.
function PublicAPI:Unregister(event, fn)
	local cbs = self.callbacks[event]
	if not cbs then return false end
	for i = #cbs, 1, -1 do
		if cbs[i] == fn then
			table.remove(cbs, i)
			return true
		end
	end
	return false
end

function PublicAPI:Reset()
	self.callbacks, self.prints, self.lastKey, self.ticks = {}, {}, nil, 0
	self.stats = { fired = 0, errors = 0, checks = 0 }
end

---------------------------------------------------------------------------------------------------------------------
-- The public table

-- Every public function works with a dot or a colon: API.GetSeason() and API:GetSeason() give the same.
local api = {}

local function public(name, fn, fallback)
	api[name] = function(...)
		local args = { ... }
		local first = 1
		if args[1] ~= nil and args[1] == PublicAPI.public then first = 2 end
		local ok, a, b = pcall(fn, PublicAPI, args[first], args[first + 1])
		if not ok then
			log("warn", "API_ERROR", name, ns.Log and ns.Log.Plain(tostring(a):sub(1, 80)) or "")
			if type(fallback) == "function" then return fallback() end
			return fallback
		end
		return a, b
	end
end

public("IsReady", function(self) return self:IsReady() end, false)
public("GetVersion", function(self) return self:Version() end, nil)
public("GetSource", function(self) return (self:Source()) end, nil)
public("GetSeason", function(self) return self:Season() end, nil)
public("GetPool", function(self) return self:Pool() end, function() return {} end)
public("GetMember", function(self, name) return self:Member(name) end, nil)
public("GetCredits", function(self, name) return self:Credits(name) end, nil)
public("GetCreditList", function(self) return self:CreditList() end, function() return {} end)
public("GetNight", function(self) return self:Night() end, nil)
public("GetRules", function(self) return self:Rules() end, nil)
public("GetEvents", function(self) return list(self.EVENTS) end, function() return {} end)
public("RegisterCallback", function(self, event, fn) return self:Register(event, fn) end, nil)
public("UnregisterCallback", function(self, event, fn) return self:Unregister(event, fn) end, false)

-- The table other addons see: the functions and API_VERSION; writes are ignored and the metatable is hidden.
local proxy = setmetatable({}, {
	__index = function(_, k)
		if k == "API_VERSION" then return PublicAPI.API_VERSION end
		return api[k]
	end,
	__newindex = function() end,
	__metatable = false,
})
PublicAPI.public = proxy
_G[PublicAPI.GLOBAL] = proxy

if ns.Bus then
	ns.Bus:On("GUILD_KEY_CHANGED", function() PublicAPI.lastKey = nil end, PublicAPI)
end
if ns.addon then
	ns.addon.PublicAPI = PublicAPI   -- also reachable from tests
	if ns.addon.AddDebugSection then
		ns.addon:AddDebugSection("API", function()
			local n = 0
			for _, cbs in pairs(PublicAPI.callbacks) do n = n + #cbs end
			local kind = PublicAPI:Source()
			return { ("API: v%d, source %s, %d callbacks, fired %d, errors %d"):format(   -- nolocale (debug output)
				PublicAPI.API_VERSION, tostring(kind or "none"), n, PublicAPI.stats.fired, PublicAPI.stats.errors) }
		end)
	end
end
