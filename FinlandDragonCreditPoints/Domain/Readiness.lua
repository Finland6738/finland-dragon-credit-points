-- Readiness: the raid readiness check, its rules and its verdicts (docs/ANALISI.md §4.2, ADR 0010, M8-2). Pure Lua 5.1:
-- it never calls the game; the tables of slots, consumables and buffs are Data/Readiness.lua's.
--
-- Every raider's own client describes itself in a small snapshot (Adapters/SelfCheck.lua builds it, Net/Readiness.lua
-- carries it to the master looter who asked); this file says what a snapshot is, how it travels and what it means against
-- the guild's requirements. Readiness is self-reported and transient (ADR 0010): nothing of it enters the ledger, the
-- credits, the backup or the public API.
--
-- The snapshot (what the domain reads):
--   { class = "HUNTER" | nil, spec = specID | nil,
--     slots  = { [inventory slot] = "YES" | "NO" | "UNKNOWN" }   only the slots that hold an item able to carry an
--              enchant (an empty slot, a held-in-off-hand item or a wand is not listed: nothing to enchant there)
--     buffs  = { [BUFF_KIND] = true }   the readiness buffs active (WELL_FED, FLASK, ELIXIR)
--     buffsKnown = bool                  false when one aura or more could not be read (then a buff that is not listed
--                                        may still be active)
--     counts = { [CATEGORY] = n }         the bag count of the category's item ids; a category not listed is unknown }
--
-- The rules (section `readiness` of Domain/Rules.lua, written by the Guild Master like every rule):
--   { enabled = bool,
--     slots = { { slot, classes?, roles?, mana? }, ... }   the slots that must carry an enchant
--     needs = { { cat, min, classes?, roles?, mana? }, ... }  the consumables, with a minimum count (0 = not required) }
--   A requirement applies to a raider when every filter it has matches: `classes` (class files), `roles` (TANK, HEALER,
--   DAMAGER; a raider whose role is unknown is not concerned by a requirement with roles), `mana` (true: only the classes
--   that use mana, false: only the others). Two requirements of one category that both apply: the larger minimum wins.
--
-- The verdict of a raider (Readiness.Evaluate):
--   { status = "OK" | "WARN" | "MISSING" | "UNKNOWN",
--     enchants = { { slot, status = "MISSING" | "UNKNOWN" }, ... }         in the order of the rules
--     items    = { { cat, status = "WARN" | "MISSING" | "UNKNOWN", have = n | nil, need = n }, ... } }
--   A category is met when an active buff of its kinds is seen or the bags hold at least the minimum; WARN = some but
--   fewer than the minimum; MISSING = none and no buff; UNKNOWN = the count (or, with none in the bags, the auras) could
--   not be read. The raider's status: UNKNOWN without a snapshot (no addon, no answer), else MISSING when anything is
--   missing, WARN when anything is low or could not be read, OK otherwise.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Readiness = {}
ns.Readiness, ns.modules.Readiness = Readiness, Readiness

local type, pairs, ipairs, next, tonumber, floor, sort = type, pairs, ipairs, next, tonumber, math.floor, table.sort
local match = string.match

local function D() return ns.ReadinessData end

Readiness.WIRE_VERSION = 1      -- `rv` of a RDY: raise it when the meaning of a field changes (new fields stay optional)
Readiness.STATUSES = { "OK", "WARN", "MISSING", "UNKNOWN" }
Readiness.MAX_SLOT_RULES = 16
Readiness.MAX_NEEDS = 24
Readiness.MAX_MIN = 10000       -- the largest minimum count (ammunition is counted by the piece)
Readiness.MAX_COUNT = 1000000   -- a reported count above this is damaged
Readiness.MAX_FILTER = 9        -- classes or roles in one filter

local function copy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = copy(x) end
	return c
end

local function isInt(n, lo, hi) return type(n) == "number" and n == floor(n) and n >= lo and n <= hi end

---------------------------------------------------------------------------------------------------------------------
-- The rules

-- The guild's requirements before the Guild Master changes them (reversible defaults, docs/ANALISI.md §4.2): the
-- enchants that every raid enchanter can make (chest, feet, wrist, hands, back, weapons; the hunter's scope), the
-- raid consumables for everyone, water for the mana users, ammunition and pet food for the hunters. Head, shoulder and
-- legs (reputation and raid enchants) are off: the Guild Master adds them. A fresh copy on every call.
function Readiness.DefaultConfig()
	return {
		enabled = true,
		slots = {
			{ slot = 5 }, { slot = 8 }, { slot = 9 }, { slot = 10 }, { slot = 15 }, { slot = 16 }, { slot = 17 },
			{ slot = 18, classes = { "HUNTER" } },
		},
		needs = {
			{ cat = "FOOD_BUFF", min = 1 },
			{ cat = "FOOD", min = 5 },
			{ cat = "WATER", min = 10, mana = true },
			{ cat = "POTION", min = 2 },
			{ cat = "FLASK", min = 1 },
			{ cat = "AMMO", min = 1000, classes = { "HUNTER" } },
			{ cat = "PET_FOOD", min = 10, classes = { "HUNTER" } },
		},
	}
end

local function filterProblems(problems, prefix, r)
	if r.classes ~= nil then
		if type(r.classes) ~= "table" or #r.classes == 0 or #r.classes > Readiness.MAX_FILTER then
			problems[#problems + 1] = prefix .. ".classes"
		else
			for _, c in ipairs(r.classes) do
				if not D().CLASSES[c] then problems[#problems + 1] = prefix .. ".classes" break end
			end
		end
	end
	if r.roles ~= nil then
		if type(r.roles) ~= "table" or #r.roles == 0 or #r.roles > 3 then
			problems[#problems + 1] = prefix .. ".roles"
		else
			for _, role in ipairs(r.roles) do
				if not D().ROLES[role] then problems[#problems + 1] = prefix .. ".roles" break end
			end
		end
	end
	if r.mana ~= nil and type(r.mana) ~= "boolean" then problems[#problems + 1] = prefix .. ".mana" end
end

-- Checks the section. Returns true, or false plus the list of problem codes ("enabled", "slots", "slots.3.slot",
-- "needs.2.cat", ...), as Rules.Validate expects them.
function Readiness.ValidateConfig(c)
	local problems = {}
	if type(c) ~= "table" then return false, { "config" } end
	if type(c.enabled) ~= "boolean" then problems[#problems + 1] = "enabled" end
	if type(c.slots) ~= "table" or #c.slots > Readiness.MAX_SLOT_RULES then
		problems[#problems + 1] = "slots"
	else
		for i, r in ipairs(c.slots) do
			local prefix = "slots." .. i
			if type(r) ~= "table" then
				problems[#problems + 1] = prefix
			else
				if not (isInt(r.slot, 1, 19) and D().IS_SLOT[r.slot]) then problems[#problems + 1] = prefix .. ".slot" end
				filterProblems(problems, prefix, r)
			end
		end
	end
	if type(c.needs) ~= "table" or #c.needs > Readiness.MAX_NEEDS then
		problems[#problems + 1] = "needs"
	else
		for i, r in ipairs(c.needs) do
			local prefix = "needs." .. i
			if type(r) ~= "table" then
				problems[#problems + 1] = prefix
			else
				if not D().Category(r.cat) then problems[#problems + 1] = prefix .. ".cat" end
				if not isInt(r.min, 0, Readiness.MAX_MIN) then problems[#problems + 1] = prefix .. ".min" end
				filterProblems(problems, prefix, r)
			end
		end
	end
	sort(problems)
	return #problems == 0, problems
end

local function contains(list, v)
	for _, x in ipairs(list) do if x == v then return true end end
	return false
end

-- Does requirement `r` apply to `who` ({ class, role })?
function Readiness.Applies(r, who)
	who = who or {}
	if r.classes ~= nil and not (who.class and contains(r.classes, who.class)) then return false end
	if r.roles ~= nil and not (who.role and contains(r.roles, who.role)) then return false end
	if r.mana ~= nil then
		if not who.class then return false end
		if (D().MANA[who.class] == true) ~= r.mana then return false end
	end
	return true
end

-- The categories a readiness check asks the raiders to count: every category with a minimum above 0, in the order of
-- Data/Readiness.lua. Empty when the check is off.
function Readiness.Categories(config)
	local wanted = {}
	if type(config) == "table" and config.enabled ~= false and type(config.needs) == "table" then
		for _, r in ipairs(config.needs) do
			if type(r) == "table" and type(r.min) == "number" and r.min > 0 then wanted[r.cat] = true end
		end
	end
	local out = {}
	for _, c in ipairs(D().CATEGORIES) do
		if wanted[c.code] then out[#out + 1] = c.code end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Links

-- Does an item link carry a permanent enchant? The second field of "item:id:enchant:..." (0 or empty: none).
-- true / false, or nil when `link` is not an item link.
function Readiness.EnchantOf(link)
	if type(link) ~= "string" then return nil end
	local id, rest = match(link, "item:(%d+)(.*)")
	if not id then return nil end
	local enchant = match(rest, "^:(%-?%d*)")
	if enchant == nil or enchant == "" then return false end
	local n = tonumber(enchant)
	return n ~= nil and n > 0
end

---------------------------------------------------------------------------------------------------------------------
-- The verdict

local RANK = { OK = 0, UNKNOWN = 1, WARN = 1, MISSING = 2 }

-- The verdict of a raider (see the top of the file). `snap` may be nil (no addon, no answer yet); `who` = { class, role }
-- (the class defaults to the snapshot's own). `config` is the `readiness` section of the rules.
function Readiness.Evaluate(snap, config, who)
	local result = { status = "UNKNOWN", enchants = {}, items = {} }
	if type(snap) ~= "table" then return result end
	config = type(config) == "table" and config or Readiness.DefaultConfig()
	who = { class = (who and who.class) or snap.class, role = who and who.role or nil }
	result.class, result.role = who.class, who.role
	local worst = 0
	local function note(status) if RANK[status] > worst then worst = RANK[status] end end
	-- enchants
	local seen = {}
	for _, r in ipairs(config.slots or {}) do
		if not seen[r.slot] and Readiness.Applies(r, who) then
			seen[r.slot] = true
			local st = snap.slots and snap.slots[r.slot]
			if st == "NO" then
				result.enchants[#result.enchants + 1] = { slot = r.slot, status = "MISSING" }
				note("MISSING")
			elseif st == "UNKNOWN" then
				result.enchants[#result.enchants + 1] = { slot = r.slot, status = "UNKNOWN" }
				note("UNKNOWN")
			end
		end
	end
	-- consumables: the largest minimum of the requirements that apply, per category
	local need = {}
	for _, r in ipairs(config.needs or {}) do
		if type(r.min) == "number" and r.min > 0 and Readiness.Applies(r, who) then
			if not need[r.cat] or r.min > need[r.cat] then need[r.cat] = r.min end
		end
	end
	for _, c in ipairs(D().CATEGORIES) do
		local min = need[c.code]
		if min then
			local buffed = false
			for _, kind in ipairs(c.buffs or {}) do
				if snap.buffs and snap.buffs[kind] then buffed = true end
			end
			local have = snap.counts and snap.counts[c.code]
			local status
			if buffed or (have and have >= min) then
				status = "OK"
			elseif have == nil then
				status = "UNKNOWN"
			elseif have > 0 then
				status = "WARN"
			elseif c.buffs and snap.buffsKnown == false then
				status = "UNKNOWN"   -- none in the bags, but a buff of the category may be active and hidden
			else
				status = "MISSING"
			end
			if status ~= "OK" then
				result.items[#result.items + 1] = { cat = c.code, status = status, have = have, need = min }
				note(status)
			end
		end
	end
	result.status = worst == 2 and "MISSING" or worst == 1 and "WARN" or "OK"
	return result
end

-- How many raiders are in each status: { total, OK, WARN, MISSING, UNKNOWN } of a list of verdicts.
function Readiness.Summary(results)
	local s = { total = 0, OK = 0, WARN = 0, MISSING = 0, UNKNOWN = 0 }
	for _, r in ipairs(results or {}) do
		local st = type(r) == "table" and (r.status or (r.result and r.result.status))
		if s[st] then
			s[st] = s[st] + 1
			s.total = s.total + 1
		end
	end
	return s
end

---------------------------------------------------------------------------------------------------------------------
-- The wire (RDY, Net/Readiness.lua)
--
--   RDY { q, rv, c?, sp?, ey?, en?, eu?, b?, bu?, n? }
--     q  the request it answers          rv  Readiness.WIRE_VERSION
--     c  the class file                   sp  the active specID
--     ey / en / eu  the slots with an enchanted item / an item without enchant / an item that could not be read
--     b  the buff kinds active            bu  true: one aura or more could not be read
--     n  { [CATEGORY] = count } of the categories asked (0 included; a category not listed could not be counted)
-- Nothing else travels: no item link, no item id, no name, no other bag content.

local function slotList(slots, value)
	local out = {}
	for _, s in ipairs(D().SLOTS) do
		if slots[s] == value then out[#out + 1] = s end
	end
	return #out > 0 and out or nil
end

-- The fields of a RDY for snapshot `snap` (without `t` and `q`).
function Readiness.Pack(snap)
	local m = { rv = Readiness.WIRE_VERSION }
	if type(snap) ~= "table" then return m end
	m.c, m.sp = snap.class, snap.spec
	local slots = snap.slots or {}
	m.ey, m.en, m.eu = slotList(slots, "YES"), slotList(slots, "NO"), slotList(slots, "UNKNOWN")
	local b = {}
	for _, kind in ipairs(D().BUFF_KINDS) do
		if snap.buffs and snap.buffs[kind] then b[#b + 1] = kind end
	end
	if #b > 0 then m.b = b end
	if snap.buffsKnown == false then m.bu = true end
	if type(snap.counts) == "table" and next(snap.counts) ~= nil then m.n = copy(snap.counts) end
	return m
end

-- The snapshot of a received RDY, checked field by field; nil when damaged. Unknown buff kinds and categories (a newer
-- addon's) are dropped, not refused.
function Readiness.Read(msg)
	if type(msg) ~= "table" or not isInt(msg.rv, 1, 1000) then return nil end
	local snap = { slots = {}, buffs = {}, buffsKnown = msg.bu ~= true, counts = {} }
	if msg.c ~= nil then
		if not D().CLASSES[msg.c] then return nil end
		snap.class = msg.c
	end
	if msg.sp ~= nil then
		if not isInt(msg.sp, 1, 100000) then return nil end
		snap.spec = msg.sp
	end
	for field, value in pairs({ ey = "YES", en = "NO", eu = "UNKNOWN" }) do
		local list = msg[field]
		if list ~= nil then
			if type(list) ~= "table" or #list > #D().SLOTS then return nil end
			for _, s in ipairs(list) do
				if not (isInt(s, 1, 19) and D().IS_SLOT[s]) or snap.slots[s] then return nil end
				snap.slots[s] = value
			end
		end
	end
	if msg.b ~= nil then
		if type(msg.b) ~= "table" or #msg.b > 8 then return nil end
		local known = {}
		for _, kind in ipairs(D().BUFF_KINDS) do known[kind] = true end
		for _, kind in ipairs(msg.b) do
			if type(kind) ~= "string" then return nil end
			if known[kind] then snap.buffs[kind] = true end
		end
	end
	if msg.n ~= nil then
		if type(msg.n) ~= "table" then return nil end
		local keys = 0
		for cat, count in pairs(msg.n) do
			keys = keys + 1
			if keys > 32 or type(cat) ~= "string" or not isInt(count, 0, Readiness.MAX_COUNT) then return nil end
			if D().Category(cat) then snap.counts[cat] = count end
		end
	end
	return snap
end

if ns.addon then ns.addon.Readiness = Readiness end   -- also reachable from tests
