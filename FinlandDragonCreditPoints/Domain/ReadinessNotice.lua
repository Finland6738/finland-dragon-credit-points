-- ReadinessNotice: the words of the readiness notify button (docs/ANALISI.md §4.2, ADR 0010, M8-3). Pure Lua 5.1: it never
-- calls the game and never reads a locale; the player's wording comes in as `words` (App/ReadinessNotice.lua fills it
-- from the locale keys and the guild's overrides).
--
-- The button writes two kinds of message, from the rows of the readiness table (App/ReadinessCheck.lua `Rows()`):
--   /raid     one short summary: how many raiders miss something, how many are low, how many are unknown, then the names
--             grouped by what they lack ("enchant hands: Bryn, Corin"), split over lines of at most 255 bytes
--   whisper   one per raider whose row is MISSING or WARN and who lacks something that was read, listing exactly what
--             and where: "[FDCP] Missing: enchant wrist, hands; potions 0/2; flask 0/1"
-- A raider whose row is UNKNOWN gets no whisper (nothing is known about the raider); a value that could not be read in
-- a row that is otherwise complete is not listed either.
--
-- words = { raid, raidUnknown, whisper, group, enchant, item, slot(n), cat(code) }
--   raid         "Readiness: {missing} missing, {low} low. Check your whispers."   ({missing} {low} {unknown} {total})
--   raidUnknown  the same with the unknown count, used when some raiders are UNKNOWN (and the guild has no text of its own)
--   whisper      "Missing: {list}"   ({list} the things, {name} the raider; a text without {list} gets it at its end)
--   group        "{what}: {names}"   one /raid line per thing that is lacking
--   enchant      "enchant {slots}"   one part of a whisper: the slots without an enchant
--   item         "{cat} {have}/{need}"   one part per consumable category
--   slot(n)      the name of an inventory slot, cat(code) the name of a consumable category
-- texts = the `readiness.texts` of the rules: { raid, whisper } ("" = the default of `words`).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local ReadinessNotice = {}
ns.ReadinessNotice, ns.modules.ReadinessNotice = ReadinessNotice, ReadinessNotice

local type, ipairs, tostring, sort, concat = type, ipairs, tostring, table.sort, table.concat

ReadinessNotice.LINE_MAX = 255    -- the chat limit, in bytes
ReadinessNotice.GROUPS_MAX = 8    -- the things named in the /raid summary (the most lacked first)
ReadinessNotice.TAG = "[FDCP] "

-- Fills {key} placeholders with the strings of `vars`; an unknown placeholder stays as it is. `|` never leaves: it would
-- start a chat escape.
local function fill(template, vars)
	local out = tostring(template):gsub("{(%w+)}", function(k)
		local v = vars[k]
		if v == nil then return nil end
		return tostring(v)
	end)
	return (out:gsub("|", ""))
end
ReadinessNotice.Fill = fill

local function short(name)
	return (tostring(name):match("^([^%-]+)")) or tostring(name)
end

-- The status of a row of the table (rows carry it at the top, results inside).
local function statusOf(row) return row.status or (row.result and row.result.status) end

-- What a row lacks and could be read: { enchants = { slot, ... }, items = { { cat, have, need, status } ... } }.
-- Enchants that could not be read and categories that could not be counted are left out.
function ReadinessNotice.Lacks(row)
	local out = { enchants = {}, items = {} }
	local result = type(row) == "table" and row.result
	if type(result) ~= "table" then return out end
	for _, e in ipairs(result.enchants or {}) do
		if e.status == "MISSING" then out.enchants[#out.enchants + 1] = e.slot end
	end
	for _, it in ipairs(result.items or {}) do
		if it.status == "MISSING" or it.status == "WARN" then
			out.items[#out.items + 1] = { cat = it.cat, have = it.have or 0, need = it.need, status = it.status }
		end
	end
	return out
end

-- The raiders a notice writes to: rows MISSING or WARN that lack something readable. Sorted by name.
function ReadinessNotice.Recipients(rows)
	local out = {}
	for _, row in ipairs(rows or {}) do
		local st = statusOf(row)
		if st == "MISSING" or st == "WARN" then
			local lacks = ReadinessNotice.Lacks(row)
			if #lacks.enchants > 0 or #lacks.items > 0 then out[#out + 1] = row end
		end
	end
	sort(out, function(a, b) return a.name < b.name end)
	return out
end

-- { missing, low, unknown, total } as the /raid line counts them: the recipients by status, the UNKNOWN rows.
function ReadinessNotice.Counts(rows)
	local c = { missing = 0, low = 0, unknown = 0, total = 0, whispers = 0 }
	for _, row in ipairs(rows or {}) do
		c.total = c.total + 1
		if statusOf(row) == "UNKNOWN" then c.unknown = c.unknown + 1 end
	end
	for _, row in ipairs(ReadinessNotice.Recipients(rows)) do
		c.whispers = c.whispers + 1
		if statusOf(row) == "MISSING" then c.missing = c.missing + 1 else c.low = c.low + 1 end
	end
	return c
end

-- The parts of one raider's whisper, in order: the enchants as one part, then a part per category.
function ReadinessNotice.Parts(row, words)
	local lacks = ReadinessNotice.Lacks(row)
	local parts = {}
	if #lacks.enchants > 0 then
		local names = {}
		for i, slot in ipairs(lacks.enchants) do names[i] = words.slot(slot) end
		parts[#parts + 1] = fill(words.enchant, { slots = concat(names, ", ") })
	end
	for _, it in ipairs(lacks.items) do
		parts[#parts + 1] = fill(words.item, { cat = words.cat(it.cat), have = it.have, need = it.need })
	end
	return parts
end

-- Packs `parts` into lines of at most LINE_MAX bytes: `build(listText)` is the whole line for a list of parts.
local function pack(parts, build)
	local lines, current = {}, {}
	for _, part in ipairs(parts) do
		current[#current + 1] = part
		if #build(concat(current, "; ")) > ReadinessNotice.LINE_MAX and #current > 1 then
			current[#current] = nil
			lines[#lines + 1] = build(concat(current, "; "))
			current = { part }
		end
	end
	if #current > 0 then lines[#lines + 1] = build(concat(current, "; ")) end
	for i, line in ipairs(lines) do
		if #line > ReadinessNotice.LINE_MAX then lines[i] = line:sub(1, ReadinessNotice.LINE_MAX) end
	end
	return lines
end

local function textOf(texts, key, default)
	local own = type(texts) == "table" and texts[key]
	return (type(own) == "string" and own ~= "") and own or default
end

-- The whisper lines of one raider (usually one; more only when the list does not fit in 255 bytes), or nil when the
-- raider lacks nothing that was read.
function ReadinessNotice.Whisper(row, words, texts)
	local parts = ReadinessNotice.Parts(row, words)
	if #parts == 0 then return nil end
	local template = textOf(texts, "whisper", words.whisper)
	if not template:find("{list}", 1, true) then template = template .. " {list}" end
	local name = short(row.name)
	return pack(parts, function(list)
		return ReadinessNotice.TAG .. fill(template, { list = list, name = name })
	end)
end

-- The /raid lines: the summary, then the names grouped by what they lack (at most GROUPS_MAX things, the most lacked
-- first). nil and "NOBODY" when no raider lacks anything.
function ReadinessNotice.Raid(rows, words, texts)
	local who = ReadinessNotice.Recipients(rows)
	if #who == 0 then return nil, "NOBODY" end
	local c = ReadinessNotice.Counts(rows)
	local own = textOf(texts, "raid", nil)
	local template = own or ((c.unknown > 0 and words.raidUnknown) or words.raid)
	local lines = { ReadinessNotice.TAG .. fill(template, { missing = c.missing, low = c.low, unknown = c.unknown, total = c.total }) }
	-- the names by thing
	local groups, order = {}, {}
	local function add(key, label, name)
		local g = groups[key]
		if not g then
			g = { label = label, names = {}, order = #order + 1 }
			groups[key], order[#order + 1] = g, g
		end
		g.names[#g.names + 1] = name
	end
	for _, row in ipairs(who) do
		local lacks = ReadinessNotice.Lacks(row)
		for _, slot in ipairs(lacks.enchants) do
			add("E" .. slot, fill(words.enchant, { slots = words.slot(slot) }), row.name)
		end
		for _, it in ipairs(lacks.items) do add("C" .. it.cat, words.cat(it.cat), row.name) end
	end
	sort(order, function(a, b)
		if #a.names ~= #b.names then return #a.names > #b.names end
		return a.order < b.order
	end)
	for i = 1, math.min(#order, ReadinessNotice.GROUPS_MAX) do
		local g = order[i]
		local template = ReadinessNotice.TAG .. fill(words.group, { what = g.label, names = "{names}" })
		local out = ns.Notice.Compose(template, g.names)
		for _, line in ipairs(out or {}) do lines[#lines + 1] = line end
	end
	return lines
end

-- The whole notice: { raid = { lines }, whispers = { { name, lines } }, counts }, or nil and a code ("NOBODY"). `self` is the
-- name of the player who writes it: named in /raid like the others, but never whispered (the game refuses it; the player
-- reads the table).
function ReadinessNotice.Plan(rows, words, texts, self)
	local raid, why = ReadinessNotice.Raid(rows, words, texts)
	if not raid then return nil, why end
	local plan = { raid = raid, whispers = {}, counts = ReadinessNotice.Counts(rows) }
	for _, row in ipairs(ReadinessNotice.Recipients(rows)) do
		if row.name ~= self then
			local lines = ReadinessNotice.Whisper(row, words, texts)
			if lines then plan.whispers[#plan.whispers + 1] = { name = row.name, lines = lines } end
		end
	end
	plan.counts.whispers = #plan.whispers
	return plan
end

-- How many chat messages a plan writes.
function ReadinessNotice.Size(plan)
	local n = #plan.raid
	for _, w in ipairs(plan.whispers) do n = n + #w.lines end
	return n
end

if ns.addon then ns.addon.ReadinessNotice = ReadinessNotice end   -- also reachable from tests
