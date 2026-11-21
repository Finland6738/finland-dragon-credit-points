-- Rules: the guild's loot rules as one configuration (docs/ANALISI.md §3, §10). Pure Lua 5.1: it never calls the game.
--
-- The configuration has one section per area of §3; the sections of the earlier modules are theirs, unchanged:
--   night     { requiresOfficialStart }                                   §3.1
--   members   Domain/Members.lua (mainOnly, lateJoin)                     §3.1, §3.5
--   season    { startCredits }                                            §3.1 (Domain/Season.lua)
--   cost      Domain/Pricing.lua (matrix, multipliers, overrides, tokens) §3.2
--   priority  Domain/Priority.lua (metric, tie-breaks, responses, BoE and other fallbacks, addon required)  §3.3-§3.4, §3.8
--   session   { awardMode, autoAdvance, lockCategoryOnOpen, interventionSeconds, rollSeconds }                  §3.4, §4
--   council   { requirePresent, vote, flags, wasteRatio, verdicts, members }   §3.6, §5.2 (the rank is the permission
--             council.member; flags, wasteRatio and verdicts are Domain/Flags.lua's, M5-4; members, the explicit list
--             that replaces the rank when it is not empty, is Domain/Council.lua's, M5-5)
--   legendary { mode, chainPieceCost }                                    §3.7
--   bench     { creditEffect, creditAmount, minTanks, minHealers }        §3.1, §6 (Domain/Rotation.lua)
--   site      Domain/Progress.lua { factionName }: the guild's key on the community site   §7.1 (M3-3b)
--   notice    Domain/Notice.lua { text, outdatedText, link, whisper, minutes }: the /raid notice (no addon)  §4.1 (M3-6)
--   announce  Domain/Announce.lua { enabled, itemText, resultText, reason }: category, cost and result in /raid  §4 (M4-8)
--   upgrade   Domain/UpgradeScore.lua { enabled, autoPass, useStats, bigThreshold, smallThreshold, ilvlBigThreshold }: the upgrade verdict of the popup  §5.1 (M5-2)
-- Rules.DefaultConfig() is the "Patto" preset (§3.1); Domain/Presets.lua builds the others from it.
--
-- The rules live in the ledger, never apart: CONFIG_CHANGED{rules, preset?, confirmed?} carries the whole validated
-- configuration (not a diff), so the rules in force when an event was written are the payload of the last
-- CONFIG_CHANGED before it (Rules.Current). Only the Guild Master writes it (permission config.rules, fixed at rank
-- index 0: Domain/Permissions.lua); while a season is open Rules.Change refuses without `confirmed` (§10), and the flag
-- stays in the event for the audit.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Rules = {}
ns.Rules, ns.modules.Rules = Rules, Rules

local type, pairs, ipairs, tostring, floor, sort = type, pairs, ipairs, tostring, math.floor, table.sort

local function Ledger() return ns.Ledger end

Rules.SECTIONS = { "night", "members", "season", "cost", "priority", "session", "council", "legendary", "bench", "site", "notice", "announce", "upgrade" }
Rules.AWARD_MODES = { confirm = true, auto = true, council = true }
Rules.LEGENDARY_MODES = { council = true, vote = true, roll = true, queue = true }
Rules.BENCH_EFFECTS = { none = true, bonus = true, malus = true }

local function copy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = copy(x) end
	return c
end
Rules.Copy = copy

local function isNum(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function isCode(s) return type(s) == "string" and s:match("^[A-Z][A-Z0-9_]*$") ~= nil end

-- The "Patto" preset (§3.1): every section, a fresh copy on every call.
function Rules.DefaultConfig()
	return {
		night = { requiresOfficialStart = true },
		members = ns.Members.DefaultConfig(),
		season = ns.Season.DefaultConfig(),
		cost = ns.Pricing.DefaultCost(),
		priority = ns.Priority.DefaultConfig(),
		session = {
			awardMode = "confirm",       -- "confirm" | "auto" | "council"
			autoAdvance = true,          -- the addon opens the reroll, the next tier and the fallback by itself (§3.4)
			lockCategoryOnOpen = true,   -- the category cannot change once the roll is open
			interventionSeconds = 30,    -- the window before an "auto" award is written
			rollSeconds = 30,            -- the timer of a roll round (Domain/SessionFSM.lua)
		},
		council = { requirePresent = true, vote = false, flags = true, wasteRatio = 2, verdicts = "council", members = {} },   -- Flags (M5-4), Council (M5-5)
		legendary = { mode = "council", chainPieceCost = 2 },
		bench = { creditEffect = "none", creditAmount = 1, minTanks = 2, minHealers = 4 },
		site = ns.Progress.DefaultConfig(),
		notice = ns.Notice.DefaultConfig(),
		announce = ns.Announce.DefaultConfig(),
		upgrade = ns.UpgradeScore.DefaultRules(),
	}
end

-- Fills what is missing from the defaults, two levels deep: a missing section, a missing key of a section; it never
-- goes inside a key that is present (a matrix row or a response list the guild wrote stays as written). For rules
-- written by an older version of the addon, which lack a newer section or key. Returns a new table.
function Rules.WithDefaults(config)
	local out = copy(type(config) == "table" and config or {})
	for name, section in pairs(Rules.DefaultConfig()) do
		if type(out[name]) ~= "table" then
			out[name] = section
		else
			for k, v in pairs(section) do
				if out[name][k] == nil then out[name][k] = v end
			end
		end
	end
	return out
end

local function add(problems, code) problems[#problems + 1] = code end

local function sub(problems, prefix, ok, codes)
	if ok then return end
	if type(codes) == "table" then
		for _, c in ipairs(codes) do add(problems, prefix .. "." .. c) end
	else
		add(problems, prefix .. "." .. tostring(codes))
	end
end

local function bool(problems, code, v)
	if type(v) ~= "boolean" then add(problems, code) end
end

-- Checks a whole configuration: every section present and valid (through the checks of the modules that own them).
-- Returns true, or false plus a sorted list of codes "<section>" or "<section>.<field>".
function Rules.Validate(config)
	if type(config) ~= "table" then return false, { "config" } end
	local problems = {}
	for _, name in ipairs(Rules.SECTIONS) do
		if type(config[name]) ~= "table" then add(problems, name) end
	end
	for k in pairs(config) do
		local known = false
		for _, name in ipairs(Rules.SECTIONS) do
			if k == name then known = true end
		end
		if not known then add(problems, "unknown:" .. tostring(k)) end
	end
	local c = config
	if type(c.night) == "table" then bool(problems, "night.requiresOfficialStart", c.night.requiresOfficialStart) end
	if type(c.members) == "table" then sub(problems, "members", ns.Members.Validate(c.members)) end
	if type(c.season) == "table" and (not isNum(c.season.startCredits) or c.season.startCredits < 0) then
		add(problems, "season.startCredits")
	end
	if type(c.cost) == "table" then sub(problems, "cost", ns.Pricing.Validate(c.cost)) end
	if type(c.priority) == "table" then sub(problems, "priority", ns.Priority.Validate(c.priority)) end
	local s = c.session
	if type(s) == "table" then
		if not Rules.AWARD_MODES[s.awardMode] then add(problems, "session.awardMode") end
		bool(problems, "session.autoAdvance", s.autoAdvance)
		bool(problems, "session.lockCategoryOnOpen", s.lockCategoryOnOpen)
		local w = s.interventionSeconds
		if type(w) ~= "number" or w ~= floor(w) or w < 0 or w > 600 then add(problems, "session.interventionSeconds") end
		local r = s.rollSeconds
		if type(r) ~= "number" or r ~= floor(r) or r < 5 or r > 600 then add(problems, "session.rollSeconds") end
	end
	if type(c.council) == "table" then
		bool(problems, "council.requirePresent", c.council.requirePresent)
		bool(problems, "council.vote", c.council.vote)
		for _, code in ipairs(ns.Flags.ValidateConfig(c.council)) do add(problems, code) end
		for _, code in ipairs(ns.Council.ValidateConfig(c.council)) do add(problems, code) end
	end
	local lg = c.legendary
	if type(lg) == "table" then
		if not Rules.LEGENDARY_MODES[lg.mode] then add(problems, "legendary.mode") end
		if not isNum(lg.chainPieceCost) or lg.chainPieceCost < 0 then add(problems, "legendary.chainPieceCost") end
	end
	local b = c.bench
	if type(b) == "table" then
		if not Rules.BENCH_EFFECTS[b.creditEffect] then add(problems, "bench.creditEffect") end
		if not isNum(b.creditAmount) or b.creditAmount < 0 or b.creditAmount > 100 then add(problems, "bench.creditAmount") end
		for _, k in ipairs({ "minTanks", "minHealers" }) do
			if type(b[k]) ~= "number" or b[k] ~= floor(b[k]) or b[k] < 0 or b[k] > 40 then add(problems, "bench." .. k) end
		end
	end
	if type(c.site) == "table" then sub(problems, "site", ns.Progress.ValidateConfig(c.site)) end
	if type(c.notice) == "table" then sub(problems, "notice", ns.Notice.ValidateConfig(c.notice)) end
	if type(c.announce) == "table" then sub(problems, "announce", ns.Announce.ValidateConfig(c.announce)) end
	if type(c.upgrade) == "table" then sub(problems, "upgrade", ns.UpgradeScore.ValidateRules(c.upgrade)) end
	sort(problems)
	return #problems == 0, problems
end

-- The leaf paths that differ between two configurations ("cost.matrix.weapon.4"), sorted: what a CONFIG_CHANGED
-- changed, for the audit.
function Rules.Diff(a, b)
	local out, seen = {}, {}
	local function walk(x, y, path)
		if type(x) == "table" and type(y) == "table" then
			local keys = {}
			for k in pairs(x) do keys[k] = true end
			for k in pairs(y) do keys[k] = true end
			for k in pairs(keys) do
				walk(x[k], y[k], path == "" and tostring(k) or (path .. "." .. tostring(k)))
			end
		elseif x ~= y and not seen[path] then
			seen[path] = true
			out[#out + 1] = path
		end
	end
	walk(a, b, "")
	sort(out)
	return out
end

-- The rules in force: from the last CONFIG_CHANGED before `at` (an event, or nil for now), or the defaults when there
-- is none. Returns the rules (a fresh table, filled with the defaults) and the id of the event they come from (nil for
-- the defaults).
function Rules.Current(L, at)
	local e = Ledger().LatestBefore(L, "CONFIG_CHANGED", at)
	if not e then return Rules.DefaultConfig(), nil end
	return Rules.WithDefaults(Ledger().Payload(e).rules), e.id
end

-- Writes a CONFIG_CHANGED. draft = { author, ts, rules, preset?, confirmed? }; `preset` is the code of the preset the
-- rules started from (Domain/Presets.lua), `confirmed` the GM's explicit confirmation, required while a season is open.
-- opts goes to Ledger.Append (the trust gate: only the GM). Returns the event, or nil and a code: "RULES:<code>",
-- "preset", "UNCHANGED", "CONFIRM_REQUIRED" or a Ledger.Append / gate code.
function Rules.Change(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	local rules = Rules.WithDefaults(draft.rules)
	local ok, problems = Rules.Validate(rules)
	if not ok then return nil, "RULES:" .. problems[1] end
	if draft.preset ~= nil and not isCode(draft.preset) then return nil, "preset" end
	if #Rules.Diff(Rules.Current(L), rules) == 0 then return nil, "UNCHANGED" end
	local confirmed = draft.confirmed == true
	if ns.Season and ns.Season.Current(L) and not confirmed then return nil, "CONFIRM_REQUIRED" end
	return Ledger().Append(L, {
		author = draft.author, ts = draft.ts, type = "CONFIG_CHANGED",
		payload = { rules = rules, preset = draft.preset, confirmed = confirmed or nil },
	}, opts)
end

-- The payload check of CONFIG_CHANGED (Ledger.Check).
ns.Ledger.CHECKS.CONFIG_CHANGED = function(p)
	if type(p.rules) ~= "table" or not Rules.Validate(Rules.WithDefaults(p.rules)) then return "rules" end
	if p.preset ~= nil and not isCode(p.preset) then return "preset" end
	if p.confirmed ~= nil and type(p.confirmed) ~= "boolean" then return "confirmed" end
end

if ns.addon then ns.addon.Rules = Rules end   -- also reachable from tests
