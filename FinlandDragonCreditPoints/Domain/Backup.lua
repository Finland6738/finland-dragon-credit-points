-- Backup: the configuration shared as a string, the full backup of the ledger and its restore, the end-of-season compaction
-- with its archive, and the size of the saved data (docs/ANALISI.md §7 "Importazione", §8.3, §11; M6-7). Pure Lua 5.1: it
-- never calls the game. The strings are made by App/BackupService.lua (CBOR, Deflate, Base64 through Core/Compat.lua);
-- this module builds and checks the tables inside them.
--
-- The three kinds of data, plain tables { kind, v, ... }:
--   CFG  { rules, preset? }                    the rules in force, without what belongs to one guild only (Backup.LOCAL:
--                                              the council's list of names and the site's faction name). An import keeps
--                                              the importing guild's own values of those, and is a CONFIG_CHANGED of the GM.
--   BAK  { ts, by, events, gone }              every event of the ledger (canonical order) and the tombstones of the
--                                              compactions: restored into an empty ledger it gives the same ledger.
--   ARC  { ts, by, season, label?, events }    every event of one season, taken just before its compaction: what leaves
--                                              the game stays in this string (the guild keeps it outside the game).
--
-- Restore is a merge (Ledger.Merge through the trust gate): it adds what is missing and never removes or overwrites an event,
-- so restoring twice, or a backup older than the ledger, changes nothing. Every restore is written as LEDGER_RESTORED
-- {kind, events, added, season?} (audited, guild-level).
--
-- Compaction: LEDGER_COMPACTED{types, removed, ms, nights} of a **closed** season (season.manage, the Guild Master by
-- default): the events of the season of the Ledger.COMPACTABLE types (the lineups) are removed from every ledger that holds
-- it (Domain/Ledger.lua, tombstones), and the payload keeps the attendance of every night: `ms` the members (sorted), per
-- night `n` (the night's id), `p` / `b` the indexes of who played / sat on the bench, `bo` / `po` pairs index, count of
-- the bosses attended / possible. Credits never depend on the removed events except through the bench effect
-- (Domain/Rotation.lua), which reads the kept attendance, so every total stays; the audit's events are never removed.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Backup = {}
ns.Backup, ns.modules.Backup = Backup, Backup

local type, pairs, ipairs, tostring, floor, sort = type, pairs, ipairs, tostring, math.floor, table.sort

local function Lg() return ns.Ledger end

Backup.V = 1                       -- the layout of the three kinds
Backup.KINDS = { CFG = true, BAK = true, ARC = true }
Backup.MAX_SUMMARY_NIGHTS = 400    -- nights a compaction summary may hold
Backup.MAX_SUMMARY_MEMBERS = 1000  -- members a compaction summary may hold

-- What belongs to one guild only: never exported, kept on import. Paths of the rules.
Backup.LOCAL = { { "council", "members" }, { "site", "factionName" } }

local function copy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = copy(x) end
	return c
end

local function isInt(n) return type(n) == "number" and n == floor(n) and n > -math.huge and n < math.huge end
local function isName(s) return type(s) == "string" and s ~= "" and not s:find(":", 1, true) end
local function isCode(s) return type(s) == "string" and s:match("^[A-Z][A-Z0-9_]*$") ~= nil end

---------------------------------------------------------------------------------------------------------------------
-- The configuration

-- The rules to share: the rules in force without the guild's own values. { kind = "CFG", v, rules, preset? }.
function Backup.Config(L)
	local rules, fromId = ns.Rules.Current(L)
	local defaults = ns.Rules.DefaultConfig()
	for _, path in ipairs(Backup.LOCAL) do
		local section = rules[path[1]]
		if type(section) == "table" then section[path[2]] = copy(defaults[path[1]][path[2]]) end
	end
	local preset
	if fromId then
		local p = Lg().Payload(L.events[fromId])
		preset = p and p.preset
	end
	return { kind = "CFG", v = Backup.V, rules = rules, preset = preset }
end

-- The rules an imported configuration would put in force in ledger L: the imported rules (filled with the defaults) with
-- L's own guild values. Returns { rules, preset?, changes = { leaf paths that differ from the rules in force } }, or nil
-- and a code: "INVALID:kind", "RULES:<code>", "preset".
function Backup.ImportedRules(L, data)
	if type(data) ~= "table" or data.kind ~= "CFG" or type(data.rules) ~= "table" then return nil, "INVALID:kind" end
	local current = ns.Rules.Current(L)
	local rules = ns.Rules.WithDefaults(data.rules)
	for _, path in ipairs(Backup.LOCAL) do
		local mine = current[path[1]] and current[path[1]][path[2]]
		if type(rules[path[1]]) == "table" then rules[path[1]][path[2]] = copy(mine) end
	end
	local ok, problems = ns.Rules.Validate(rules)
	if not ok then return nil, "RULES:" .. problems[1] end
	if data.preset ~= nil and not isCode(data.preset) then return nil, "preset" end
	return { rules = rules, preset = data.preset, changes = ns.Rules.Diff(current, rules) }
end

---------------------------------------------------------------------------------------------------------------------
-- Backup and archive

-- The full backup: { kind = "BAK", v, ts, by, events = { every event, canonical order }, gone = tombstones }.
function Backup.Full(L, meta)
	meta = meta or {}
	local events = {}
	for i, e in ipairs(Lg().Sorted(L)) do events[i] = copy(e) end
	return { kind = "BAK", v = Backup.V, ts = meta.ts, by = meta.by, events = events, gone = copy(L.gone or {}) }
end

-- The archive of a season: { kind = "ARC", v, ts, by, season, label?, events = { the season's events, canonical order } }.
-- nil and "SEASON_UNKNOWN" for a season the ledger does not have.
function Backup.Archive(L, season, meta)
	meta = meta or {}
	local s = ns.Season.Get(L, season)
	if not s then return nil, "SEASON_UNKNOWN" end
	local events = {}
	for i, e in ipairs(Lg().Sorted(L, function(x) return x.season == season end)) do events[i] = copy(e) end
	return { kind = "ARC", v = Backup.V, ts = meta.ts, by = meta.by, season = season, label = s.label, events = events }
end

-- Checks the shape of a decoded backup or archive (each event is checked again by the merge). true, or false and a code.
function Backup.Validate(data)
	if type(data) ~= "table" or not Backup.KINDS[data.kind] then return false, "kind" end
	if not isInt(data.v) or data.v < 1 then return false, "v" end
	if data.v > Backup.V then return false, "NEWER" end
	if data.kind == "CFG" then
		if type(data.rules) ~= "table" then return false, "rules" end
		return true
	end
	if type(data.events) ~= "table" then return false, "events" end
	for i, e in pairs(data.events) do
		if not isInt(i) or i < 1 or i > #data.events or type(e) ~= "table" then return false, "events" end
	end
	if data.ts ~= nil and type(data.ts) ~= "number" then return false, "ts" end
	if data.by ~= nil and not isName(data.by) then return false, "by" end
	if data.kind == "BAK" then
		if data.gone ~= nil and type(data.gone) ~= "table" then return false, "gone" end
		for author, list in pairs(data.gone or {}) do
			if not isName(author) or type(list) ~= "table" then return false, "gone" end
			for _, r in pairs(list) do
				if type(r) ~= "table" or not isInt(r[1]) or not isInt(r[2]) or r[1] < 1 or r[2] < r[1] or r[3] == nil then
					return false, "gone"
				end
			end
		end
	else
		if data.season == nil then return false, "season" end
	end
	return true
end

-- What a restore of `data` would bring: { kind, events = n, new = events not in L yet, by?, ts?, season? }.
function Backup.Preview(L, data)
	local new = 0
	for _, e in ipairs(data.events or {}) do
		if type(e) == "table" and type(e.id) == "string" and not L.events[e.id] then
			local author, seq = Lg().SplitId(e.id)
			if not (author and Lg().IsGone(L, author, seq)) then new = new + 1 end
		end
	end
	return { kind = data.kind, events = #(data.events or {}), new = new, by = data.by, ts = data.ts, season = data.season }
end

-- Restores a backup or an archive into L: a merge, nothing is removed or overwritten. opts.merge(L, events) does the merge
-- (the app passes the permission service's, with the trust gate); default Ledger.Merge(L, events, opts.gate). Then the
-- tombstones of a backup (only for seqs still missing, of a season whose compaction is in force). Returns the merge report
-- with `gone` = tombstones added, or nil and a code ("INVALID:<code>", "READ_ONLY").
function Backup.Restore(L, data, opts)
	opts = opts or {}
	local ok, code = Backup.Validate(data)
	if not ok or data.kind == "CFG" then return nil, "INVALID:" .. tostring(code or "kind") end
	local report, why
	if opts.merge then report, why = opts.merge(L, data.events) else report, why = Lg().Merge(L, data.events, opts.gate) end
	if not report then return nil, why end
	report.gone = 0
	if data.kind == "BAK" then
		for author, list in pairs(data.gone or {}) do
			for _, r in ipairs(list) do report.gone = report.gone + Lg().MarkGone(L, author, r[1], r[2], r[3]) end
		end
	end
	return report
end

-- The audit record of a restore: LEDGER_RESTORED{kind, events, added, season?}. draft = { author, ts, data, report }.
function Backup.RecordRestore(L, draft, opts)
	local data, report = draft.data, draft.report or {}
	return Lg().Append(L, { author = draft.author, ts = draft.ts, type = "LEDGER_RESTORED",
		payload = { kind = data.kind, events = #(data.events or {}), added = report.added or 0,
			season = data.kind == "ARC" and data.season or nil } }, opts)
end

---------------------------------------------------------------------------------------------------------------------
-- Compaction

-- The payload of a compaction of `season`: the attendance of every night (from Nights.Attendance, before anything is
-- removed) and the number of events it removes. Returns the payload and the count.
function Backup.Summary(L, season)
	local att = ns.Nights.Attendance(L, season)
	local index, ms = {}, {}
	local function idx(name)
		if not index[name] then
			ms[#ms + 1] = name
			index[name] = true
		end
	end
	for _, rec in ipairs(att.nights) do
		for name in pairs(rec.played) do idx(name) end
		for name in pairs(rec.benched) do idx(name) end
		for _, k in ipairs(rec.kills) do
			for _, list in ipairs({ k.raid, k.bench, k.absent }) do for _, name in ipairs(list) do idx(name) end end
		end
	end
	sort(ms)
	for i, name in ipairs(ms) do index[name] = i end
	local nights = {}
	for _, rec in ipairs(att.nights) do
		local p, b, bosses, possible = {}, {}, {}, {}
		for name in pairs(rec.played) do p[#p + 1] = index[name] end
		for name in pairs(rec.benched) do b[#b + 1] = index[name] end
		for _, k in ipairs(rec.kills) do
			for _, name in ipairs(k.raid) do
				bosses[name] = (bosses[name] or 0) + 1
				possible[name] = (possible[name] or 0) + 1
			end
			for _, name in ipairs(k.bench) do possible[name] = (possible[name] or 0) + 1 end
			for _, name in ipairs(k.absent) do possible[name] = (possible[name] or 0) + 1 end
		end
		local function pairsList(map)
			local names, out = {}, {}
			for name in pairs(map) do names[#names + 1] = name end
			sort(names)
			for _, name in ipairs(names) do out[#out + 1] = index[name]; out[#out + 1] = map[name] end
			return out
		end
		sort(p); sort(b)
		nights[#nights + 1] = { n = rec.night.id, p = p, b = b, bo = pairsList(bosses), po = pairsList(possible) }
	end
	local types, removed = {}, 0
	for t in pairs(Lg().COMPACTABLE) do types[#types + 1] = t end
	sort(types)
	for _, e in pairs(L.events) do
		if e.season == season and Lg().COMPACTABLE[e.type] then removed = removed + 1 end
	end
	return { types = types, removed = removed, ms = ms, nights = nights }, removed
end

-- Compacts a closed season: writes LEDGER_COMPACTED (the ledger then removes the events). draft = { author, ts, season }.
-- opts goes to Ledger.Append (the trust gate). Returns the event and the number of events removed, or nil and a code:
-- "SEASON_UNKNOWN", "SEASON_OPEN", "ALREADY_COMPACTED", "NOTHING_TO_COMPACT", "TOO_LARGE" or a Ledger.Append / gate code.
function Backup.Compact(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	local s = ns.Season.Get(L, draft.season)
	if not s then return nil, "SEASON_UNKNOWN" end
	if not s.closed then return nil, "SEASON_OPEN" end
	if Lg().Compactions(L)[draft.season] then return nil, "ALREADY_COMPACTED" end
	local payload, removed = Backup.Summary(L, draft.season)
	if removed == 0 then return nil, "NOTHING_TO_COMPACT" end
	if #payload.nights > Backup.MAX_SUMMARY_NIGHTS or #payload.ms > Backup.MAX_SUMMARY_MEMBERS then return nil, "TOO_LARGE" end
	local before = Lg().Count(L)
	local e, why = Lg().Append(L, { author = draft.author, ts = draft.ts, season = draft.season, type = "LEDGER_COMPACTED",
		payload = payload }, opts)
	if not e then return nil, why end
	return e, before + 1 - Lg().Count(L)
end

---------------------------------------------------------------------------------------------------------------------
-- The size of the saved data (/fdcp debug)

-- About how many bytes a value takes in the SavedVariables file (the client writes Lua: keys, quotes, commas, tabs).
local function estimate(v, depth)
	local t = type(v)
	if t == "string" then return #v + 3 end
	if t == "number" then return #tostring(v) + 1 end
	if t == "boolean" then return 6 end
	if t ~= "table" then return 4 end
	local n = 3 + depth
	for k, x in pairs(v) do
		n = n + depth + 1 + (type(k) == "string" and #k + 7 or #tostring(k) + 3) + estimate(x, depth + 1)
	end
	return n
end
Backup.Estimate = function(v) return estimate(v, 0) end

-- { events, gone, bytes, byType = { { type, count, bytes }, ... biggest first } } for the ledger L.
function Backup.Size(L)
	local byType, total, n = {}, 0, 0
	for _, e in pairs(L.events) do
		local b = estimate(e, 3) + #e.id + 7
		local row = byType[e.type]
		if not row then row = { type = e.type, count = 0, bytes = 0 }; byType[e.type] = row end
		row.count, row.bytes = row.count + 1, row.bytes + b
		total, n = total + b, n + 1
	end
	total = total + estimate(L.snapshots or {}, 2) + estimate(L.gone or {}, 2) + estimate(L.heads or {}, 2) * 2
	local list = {}
	for _, row in pairs(byType) do list[#list + 1] = row end
	sort(list, function(a, b) if a.bytes ~= b.bytes then return a.bytes > b.bytes end return a.type < b.type end)
	return { events = n, gone = Lg().GoneCount(L), bytes = total, byType = list }
end

---------------------------------------------------------------------------------------------------------------------
-- The ledger checks of the two new types

local function intList(list, max)
	if type(list) ~= "table" then return false end
	for i, x in pairs(list) do
		if not isInt(i) or i < 1 or i > #list or not isInt(x) or x < 0 or (max and x > max) then return false end
	end
	return true
end

ns.Ledger.CHECKS.LEDGER_COMPACTED = function(p)
	if type(p.types) ~= "table" or #p.types == 0 then return "types" end
	for _, t in pairs(p.types) do
		if not Lg().COMPACTABLE[t] then return "types" end
	end
	if not isInt(p.removed) or p.removed < 0 then return "removed" end
	if type(p.ms) ~= "table" or #p.ms > Backup.MAX_SUMMARY_MEMBERS then return "ms" end
	for i, name in pairs(p.ms) do
		if not isInt(i) or i < 1 or i > #p.ms or not isName(name) then return "ms" end
	end
	if type(p.nights) ~= "table" or #p.nights > Backup.MAX_SUMMARY_NIGHTS then return "nights" end
	for i, rec in pairs(p.nights) do
		if not isInt(i) or type(rec) ~= "table" or not Lg().SplitId(rec.n) then return "nights" end
		for _, k in ipairs({ "p", "b", "bo", "po" }) do
			if rec[k] ~= nil and not intList(rec[k]) then return "nights" end
		end
	end
end

ns.Ledger.CHECKS.LEDGER_RESTORED = function(p)
	if p.kind ~= "BAK" and p.kind ~= "ARC" then return "kind" end
	if not isInt(p.events) or p.events < 0 then return "events" end
	if not isInt(p.added) or p.added < 0 then return "added" end
end

if ns.addon then ns.addon.Backup = Backup end   -- also reachable from tests
