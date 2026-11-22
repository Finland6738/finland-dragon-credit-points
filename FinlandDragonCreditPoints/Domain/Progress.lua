-- Progress: the first kill of every boss, per faction of the community site (docs/ANALISI.md §7.1,
-- docs/specs/site-export.md §3.3, §4, §5; M3-3b). Pure Lua 5.1: it never calls the game. It reads the fixed table of
-- Data/Instances.lua and the kills of Domain/Nights.lua; nothing is stored apart: like the credits, a first kill is
-- computed from the ledger every time.
--
-- The faction key. The site keeps one date per boss per faction under a key that is the guild's name on the site
-- (`Nebulah` for the Horde guild, `Nebulaa` for the Alliance one). The key of this guild comes from the rules' section
-- `site.factionName` (written by the GM with the other rules, CONFIG_CHANGED); while it is empty the client's faction
-- chooses the default (Progress.DEFAULT_KEYS). Another guild that uses the addon writes the name its own site uses.
--
-- Read from the ledger:
--   ENCOUNTER_KILLED{encounterID, date, ...}  a recorded kill (Domain/Nights.lua), inside an official night or outside
--       one (App/ProgressController.lua writes those). Recorded kills are this guild's: they count for its own key only.
--   PROGRESS_SET{encounterID, faction, date} or PROGRESS_SET{encounterID, faction, clear = true}  a first kill entered
--       by hand (one from before the addon, or the other faction's date seen on the site), or the correction of one.
--       `faction` is a site key. Guild-level (no season needed: a backfill may predate every season); permission
--       `progress.edit`, so it is in the audit like every event. For one boss and one key the **last** PROGRESS_SET in
--       canonical order is the value entered by hand: a correction replaces the earlier one (even with a later date,
--       a typo is fixed that way) and `clear` removes it.
--
-- The first kill of a boss for a key = the oldest date between the value entered by hand for that key and, for the
-- guild's own key, every recorded kill. So a later kill never moves a date forward, and a correction by hand can move
-- the date back but never past a kill the addon recorded.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Progress = {}
ns.Progress, ns.modules.Progress = Progress, Progress

local type, pairs, ipairs = type, pairs, ipairs
local floor, sort = math.floor, table.sort

local function Ledger() return ns.Ledger end
local function Nights() return ns.Nights end
local function Instances() return ns.Instances end

-- The site's keys of the two guilds of the community, by the client's faction token.
Progress.DEFAULT_KEYS = { Horde = "Nebulah", Alliance = "Nebulaa" }
Progress.KEY_MAX = 32

local function isInt(n) return type(n) == "number" and n == floor(n) and n > -math.huge and n < math.huge end

-- A site key: 1-32 characters, letters, digits, space, "_" and "-", starting with a letter or a digit (it becomes a
-- JSON key of progress.json and the `faction` of roster.json).
function Progress.ValidKey(s)
	return type(s) == "string" and #s >= 1 and #s <= Progress.KEY_MAX and s:match("^[%w][%w _%-]*$") ~= nil
end

---------------------------------------------------------------------------------------------------------------------
-- The rules' section "site" (Domain/Rules.lua): { factionName = "", extended = false } ("" = the default of the client's
-- faction). `extended` is the hidden switch of issue #3 (M6-4): the site export writes `start` and `kind` too. It is off, not in
-- the settings window, and only a rules change from the Guild Master turns it on.

function Progress.DefaultConfig()
	return { factionName = "", extended = false }
end

-- Returns true, or false and a list of codes.
function Progress.ValidateConfig(c)
	if type(c) ~= "table" then return false, { "site" } end
	local problems = {}
	if not (c.factionName == "" or Progress.ValidKey(c.factionName)) then problems[#problems + 1] = "factionName" end
	if c.extended ~= nil and type(c.extended) ~= "boolean" then problems[#problems + 1] = "extended" end
	for k in pairs(c) do
		if k ~= "factionName" and k ~= "extended" then problems[#problems + 1] = "unknown:" .. tostring(k) end
	end
	sort(problems)
	return #problems == 0, problems
end

-- The guild's key on the site: the rules' factionName when set, else the default of the client's faction ("Horde" /
-- "Alliance"), else nil (no faction known: nothing can be keyed yet).
function Progress.FactionKey(rules, faction)
	local name = type(rules) == "table" and type(rules.site) == "table" and rules.site.factionName or nil
	if Progress.ValidKey(name) then return name end
	return Progress.DEFAULT_KEYS[faction]
end

---------------------------------------------------------------------------------------------------------------------
-- Ledger check (tightens Domain/Ledger.lua's)

Ledger().CHECKS.PROGRESS_SET = function(p)
	if not isInt(p.encounterID) or p.encounterID <= 0 then return "encounterID" end
	if not Progress.ValidKey(p.faction) then return "faction" end
	if p.clear ~= nil then
		if p.clear ~= true then return "clear" end
		if p.date ~= nil then return "date" end
	elseif not Nights().ValidDate(p.date) then
		return "date"
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Reading

local function readable(e)
	local Lg = Ledger()
	return Lg.Readable(e) and Lg.Payload(e) or nil
end

-- The values entered by hand: { [key] = { [encounterID] = { date, id, author, ts } } }, from the last PROGRESS_SET of
-- every boss and key in canonical order (a cleared one is absent).
function Progress.Manual(L)
	local out = {}
	for _, e in ipairs(Ledger().Sorted(L, function(e) return e.type == "PROGRESS_SET" end)) do
		local p = readable(e)
		if p then
			local byKey = out[p.faction]
			if not byKey then byKey = {}; out[p.faction] = byKey end
			if p.clear then
				byKey[p.encounterID] = nil
			else
				byKey[p.encounterID] = { date = p.date, id = e.id, author = e.author, ts = e.ts }
			end
		end
	end
	return out
end

-- True when the ledger holds a recorded kill (ENCOUNTER_KILLED) of the encounter, inside a night or not.
function Progress.HasKill(L, encounterID)
	for _, e in pairs(L.events) do
		if e.type == "ENCOUNTER_KILLED" then
			local p = readable(e)
			if p and p.encounterID == encounterID then return true end
		end
	end
	return false
end

local function better(cur, date, source)
	if not cur then return true end
	if date < cur.date then return true end
	return date == cur.date and cur.source == "SET" and source == "KILL"   -- same day: the recorded kill is the proof
end

-- The first kill of every encounter for site key `key`: { [encounterID] = { date, source = "KILL" | "SET", id } }.
-- `own` = this is the guild's own key: the recorded kills count too; for any other key only the values entered by hand.
-- `manual` = Progress.Manual(L) when the caller has it already.
function Progress.FirstKills(L, key, own, manual)
	local out = {}
	manual = manual or Progress.Manual(L)
	for enc, m in pairs(manual[key] or {}) do out[enc] = { date = m.date, source = "SET", id = m.id } end
	if own then
		for _, k in ipairs(Nights().Kills(L)) do
			if Nights().ValidDate(k.date) and better(out[k.encounterID], k.date, "KILL") then
				out[k.encounterID] = { date = k.date, source = "KILL", id = k.id }
			end
		end
	end
	return out
end

-- The keys to show: the guild's own first, then the other community guild's default key when the own key is one of the
-- defaults, then every other key a PROGRESS_SET named, sorted.
function Progress.Keys(L, own, manual)
	manual = manual or Progress.Manual(L)
	local keys, seen = {}, {}
	local function add(k)
		if k and not seen[k] then seen[k] = true; keys[#keys + 1] = k end
	end
	add(own)
	local isDefault = false
	for _, k in pairs(Progress.DEFAULT_KEYS) do
		if k == own then isDefault = true end
	end
	local rest = {}
	if isDefault then
		for _, k in pairs(Progress.DEFAULT_KEYS) do
			if not seen[k] then rest[#rest + 1] = k end
		end
	end
	for k, byEnc in pairs(manual) do
		if not seen[k] and next(byEnc) ~= nil then rest[#rest + 1] = k end
	end
	sort(rest)
	for _, k in ipairs(rest) do add(k) end
	return keys
end

-- The progress of every instance of the fixed table, for the Progress tab (M3-8b) and the export (M6-4):
--   { own, keys = { own, ... }, instances = { { instanceID, journalInstanceID, slug, name, size, total, counts = { [key] = n },
--       bosses = { { index, encounterID, name, localName, first = { [key] = { date, source, id } } } } } } }
-- `name` is the table's English name (the site's); `localName` the name in the client's language when opts.localName
-- (function(boss, instance) -> string or nil, the controller's lookup through Compat) gives one, else the English name.
-- opts = { keys? = list (default Progress.Keys), localName? }.
function Progress.Build(L, own, opts)
	opts = opts or {}
	local manual = Progress.Manual(L)
	local keys = opts.keys or Progress.Keys(L, own, manual)
	local firsts = {}
	for _, k in ipairs(keys) do firsts[k] = Progress.FirstKills(L, k, k == own, manual) end
	local result = { own = own, keys = keys, instances = {} }
	for _, inst in ipairs(Instances().LIST) do
		local rec = { instanceID = inst.instanceID, journalInstanceID = inst.journalInstanceID, slug = inst.slug, name = inst.name, size = inst.size,
			total = #inst.bosses, counts = {}, bosses = {} }
		if opts.localName then rec.localName = opts.localName(nil, inst) end
		rec.localName = rec.localName or inst.name
		for _, k in ipairs(keys) do rec.counts[k] = 0 end
		for i, boss in ipairs(inst.bosses) do
			local b = { index = i, encounterID = boss.encounterID, name = boss.name, first = {} }
			b.localName = opts.localName and opts.localName(boss, inst) or boss.name
			for _, k in ipairs(keys) do
				local f = firsts[k][boss.encounterID]
				if f then
					b.first[k] = f
					rec.counts[k] = rec.counts[k] + 1
				end
			end
			rec.bosses[i] = b
		end
		result.instances[#result.instances + 1] = rec
	end
	return result
end

---------------------------------------------------------------------------------------------------------------------
-- Writing (an officer with progress.edit)

-- Enters or corrects a first kill by hand. draft = { author, ts, encounterID, faction, date, today?, season? }: the
-- encounter must be a boss of the fixed table, `faction` a site key, `date` "YYYY-MM-DD" not after `today` (the realm's
-- day, when given). Returns the PROGRESS_SET event, or nil and a code: "UNKNOWN_ENCOUNTER", "faction", "date",
-- "FUTURE", "UNCHANGED" or a Ledger.Append code (the gate's "RANK_TOO_LOW" included). `opts` goes to Ledger.Append.
function Progress.Set(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	if not Instances().OfEncounter(draft.encounterID) then return nil, "UNKNOWN_ENCOUNTER" end
	if not Progress.ValidKey(draft.faction) then return nil, "faction" end
	if not Nights().ValidDate(draft.date) then return nil, "date" end
	if Nights().ValidDate(draft.today) and draft.date > draft.today then return nil, "FUTURE" end
	local cur = (Progress.Manual(L)[draft.faction] or {})[draft.encounterID]
	if cur and cur.date == draft.date then return nil, "UNCHANGED" end
	return Ledger().Append(L, { author = draft.author, ts = draft.ts, season = draft.season, type = "PROGRESS_SET",
		payload = { encounterID = draft.encounterID, faction = draft.faction, date = draft.date } }, opts)
end

-- Removes the value entered by hand for a boss and a key. draft = { author, ts, encounterID, faction, season? }.
-- Returns the PROGRESS_SET event, or nil and "NOTHING_TO_CLEAR", "faction" or a Ledger.Append code. A recorded kill
-- stays: only what was entered by hand is cleared.
function Progress.Clear(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	if not Progress.ValidKey(draft.faction) then return nil, "faction" end
	if not (Progress.Manual(L)[draft.faction] or {})[draft.encounterID] then return nil, "NOTHING_TO_CLEAR" end
	return Ledger().Append(L, { author = draft.author, ts = draft.ts, season = draft.season, type = "PROGRESS_SET",
		payload = { encounterID = draft.encounterID, faction = draft.faction, clear = true } }, opts)
end

if ns.addon then ns.addon.Progress = Progress end   -- also reachable from tests
