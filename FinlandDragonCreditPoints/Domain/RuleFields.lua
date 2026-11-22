-- RuleFields: the form of the guild's rules (docs/ANALISI.md §10, M7-2). Pure Lua 5.1: it never calls the game and never draws.
--
-- Rules.lua says what a valid configuration is; this file says which values of it the Guild Master edits from the Settings
-- window, how each one is read and written and what it is called (locale keys, never text). One field = one value of the
-- rules, found by a path ({ "session", "awardMode" }); the fields are grouped in pages the window lists on its left.
--
--   field = { id = "session.awardMode", page, path, kind, keys = { locale keys joined by " · " }, ... }
--   kind  "bool"                                                  true / false
--         "int" | "number"  min, max                              a whole number / a number
--         "cost"            min, max                              a number, or the word of the council ("council") where
--                                                                 the cell already is the council's (the legendary column)
--         "choice"          options = { { value, key } }          one of a list (`list = true`: a list of codes joined by ",")
--         "text"            max                                   a line of text (the wording of a notice)
--         "names"                                                 a list of character names, separated by commas
--
-- RuleFields.Get / Set read and write the value in a rules table (a copy the window edits), RuleFields.Parse turns what the
-- player typed into a value; the validity of the whole table is still Rules.Validate's, run before anything is written.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local RuleFields = {}
ns.RuleFields, ns.modules.RuleFields = RuleFields, RuleFields

local type, pairs, ipairs, tostring, tonumber, floor = type, pairs, ipairs, tostring, tonumber, math.floor

RuleFields.PAGES = { "session", "priority", "costs", "multipliers", "members", "council", "legendary", "messages", "upgrade", "site" }
RuleFields.COUNCIL_WORD = "council"   -- what a cost cell holds when the council decides (Domain/Pricing.lua)

local function opt(value, key) return { value = value, key = key } end

local AWARD_MODES = { opt("confirm", "RULEOPT_CONFIRM"), opt("auto", "RULEOPT_AUTO"), opt("council", "RULEOPT_COUNCIL") }
local METRICS = { opt("credits", "RULEOPT_CREDITS"), opt("creditsPerNight", "RULEOPT_CREDITS_PER_NIGHT"), opt("roll", "RULEOPT_ROLL") }
local TIE_BREAKS = { opt("roll,reroll", "RULEOPT_TIE_ROLL_REROLL"), opt("roll", "RULEOPT_TIE_ROLL"), opt("reroll", "RULEOPT_TIE_REROLL"),
	opt("", "RULEOPT_TIE_ML") }
local FALLBACKS = { opt("ml", "RULEOPT_ML"), opt("disenchant", "RULEOPT_DISENCHANT"), opt("freeroll", "RULEOPT_FREEROLL") }
local BOE_FALLBACKS = { opt("bank", "RULEOPT_BANK"), opt("offspec", "RULEOPT_OFFSPEC"), opt("disenchant", "RULEOPT_DISENCHANT"),
	opt("freeroll", "RULEOPT_FREEROLL") }
local LATE_METHODS = { opt("average", "SEASON_METHOD_AVERAGE"), opt("median", "SEASON_METHOD_MEDIAN"), opt("min", "SEASON_METHOD_MIN"),
	opt("zero", "SEASON_METHOD_ZERO"), opt("fixed", "SEASON_METHOD_FIXED") }
local ROUNDINGS = { opt("floor", "RULEOPT_FLOOR"), opt("round", "RULEOPT_ROUND"), opt("ceil", "RULEOPT_CEIL") }
local VERDICTS = { opt("ml", "RULEOPT_VIS_ML"), opt("council", "RULEOPT_VIS_COUNCIL"), opt("officers", "RULEOPT_VIS_OFFICERS") }
local LEGENDARY = { opt("council", "RULEOPT_COUNCIL"), opt("vote", "RULEOPT_VOTE"), opt("roll", "RULEOPT_ROLL"), opt("queue", "RULEOPT_QUEUE") }
local BENCH = { opt("none", "RULEOPT_NONE"), opt("bonus", "RULEOPT_BONUS"), opt("malus", "RULEOPT_MALUS") }

---------------------------------------------------------------------------------------------------------------------
-- The fields

-- locale-key: RULEF_CAT_WEAPON RULEF_CAT_OFFHAND RULEF_CAT_TRINKET RULEF_CAT_QUEST RULEF_CAT_JEWELRY RULEF_CAT_ARMOR RULEF_CAT_COSMETIC RULEF_CAT_OTHER
-- locale-key: RULEF_QUALITY_3 RULEF_QUALITY_4 RULEF_QUALITY_5 RULEF_MULT_SIZE_10 RULEF_MULT_SIZE_20 RULEF_MULT_SIZE_40
-- locale-key: RC_RESPONSE_MS RC_RESPONSE_OS RC_RESPONSE_TMOG
local FIELDS, BY_ID = {}, {}

local function add(page, path, kind, keys, extra)
	local f = extra or {}
	f.page, f.path, f.kind, f.keys = page, path, kind, keys
	local id = {}
	for i, p in ipairs(path) do id[i] = tostring(p) end
	f.id = table.concat(id, ".")
	FIELDS[#FIELDS + 1] = f
	BY_ID[f.id] = f
	return f
end

-- session: the night and the session of loot (§3.1, §3.4, §4)
add("session", { "night", "requiresOfficialStart" }, "bool", { "RULEF_NIGHT_OFFICIAL_START" })
add("session", { "session", "awardMode" }, "choice", { "RULEF_AWARD_MODE" }, { options = AWARD_MODES })
add("session", { "session", "autoAdvance" }, "bool", { "RULEF_AUTO_ADVANCE" })
add("session", { "session", "lockCategoryOnOpen" }, "bool", { "RULEF_LOCK_CATEGORY" })
add("session", { "session", "interventionSeconds" }, "int", { "RULEF_INTERVENTION_SECONDS" }, { min = 0, max = 600 })
add("session", { "session", "rollSeconds" }, "int", { "RULEF_ROLL_SECONDS" }, { min = 5, max = 600 })
add("session", { "session", "buttonRollsOnly" }, "bool", { "RULEF_BUTTON_ROLLS_ONLY" })
add("session", { "session", "buttonRollWindow" }, "int", { "RULEF_BUTTON_ROLL_WINDOW" }, { min = 2, max = 60 })

-- priority: who wins (§3.3, §3.4, §3.8)
add("priority", { "priority", "metric" }, "choice", { "RULEF_METRIC" }, { options = METRICS })
add("priority", { "priority", "tieBreak" }, "choice", { "RULEF_TIE_BREAK" }, { options = TIE_BREAKS, list = true })
add("priority", { "priority", "maxRerolls" }, "int", { "RULEF_MAX_REROLLS" }, { min = 1, max = 20 })
add("priority", { "priority", "requireAddon" }, "bool", { "RULEF_REQUIRE_ADDON" })
add("priority", { "priority", "responses", "OS", "enabled" }, "bool", { "RULEF_RESPONSE_ENABLED", "RC_RESPONSE_OS" }, { enabledByDefault = true })
add("priority", { "priority", "fallback" }, "choice", { "RULEF_FALLBACK" }, { options = FALLBACKS })
add("priority", { "priority", "boeFallback" }, "choice", { "RULEF_BOE_FALLBACK" }, { options = BOE_FALLBACKS })
add("priority", { "priority", "freeRollCost" }, "number", { "RULEF_FREE_ROLL_COST" }, { min = 0, max = 100 })

-- costs: the matrix of the category and the quality (§3.2); the cells the default matrix has
local CATEGORIES = { "weapon", "offhand", "trinket", "quest", "jewelry", "armor", "cosmetic", "other" }
local QUALITIES = { 3, 4, 5 }
for _, category in ipairs(CATEGORIES) do
	for _, q in ipairs(QUALITIES) do
		local cell = ns.Pricing.DefaultCost().matrix[category][q]
		if cell ~= nil then
			add("costs", { "cost", "matrix", category, q }, "cost", { "RULEF_CAT_" .. category:upper(), "RULEF_QUALITY_" .. q },
				{ min = 0, max = 1000 })
		end
	end
end

-- multipliers: the factors on a base cost (§3.2)
for _, r in ipairs({ "MS", "OS", "TMOG" }) do
	add("multipliers", { "cost", "responseMultiplier", r }, "number", { "RULEF_MULT_RESPONSE", "RC_RESPONSE_" .. r }, { min = 0, max = 100 })
end
for _, s in ipairs({ 10, 20, 40 }) do
	add("multipliers", { "cost", "raidSizeMultiplier", s }, "number", { "RULEF_MULT_SIZE_" .. s }, { min = 0, max = 100 })
end
add("multipliers", { "cost", "difficultyMultiplier", "normal" }, "number", { "RULEF_MULT_DIFFICULTY_NORMAL" }, { min = 0, max = 100 })
add("multipliers", { "cost", "difficultyMultiplier", "veteran" }, "number", { "RULEF_MULT_DIFFICULTY_VETERAN" }, { min = 0, max = 100 })

-- members: late joiners and the start of a season (§3.1, §3.5)
add("members", { "members", "mainOnly" }, "bool", { "RULEF_MAIN_ONLY" })
add("members", { "members", "lateJoin", "method" }, "choice", { "RULEF_LATE_METHOD" }, { options = LATE_METHODS })
add("members", { "members", "lateJoin", "rounding" }, "choice", { "RULEF_LATE_ROUNDING" }, { options = ROUNDINGS })
add("members", { "members", "lateJoin", "decimals" }, "int", { "RULEF_LATE_DECIMALS" }, { min = 0, max = 2 })
add("members", { "members", "lateJoin", "minNights" }, "int", { "RULEF_LATE_MIN_NIGHTS" }, { min = 0, max = 100 })
add("members", { "members", "lateJoin", "fixed" }, "number", { "RULEF_LATE_FIXED" }, { min = 0, max = 1000 })
add("members", { "season", "startCredits" }, "number", { "RULEF_START_CREDITS" }, { min = 0, max = 1000 })
add("members", { "penalties", "absence" }, "number", { "RULEF_PENALTY_ABSENCE" }, { min = 0, max = 100 })   -- M7-5b
add("members", { "penalties", "autoApply" }, "bool", { "RULEF_PENALTY_AUTO_APPLY" })

-- council: the loot council (§3.6, §5.2)
add("council", { "council", "requirePresent" }, "bool", { "RULEF_COUNCIL_PRESENT" })
add("council", { "council", "vote" }, "bool", { "RULEF_COUNCIL_VOTE" })
add("council", { "council", "flags" }, "bool", { "RULEF_COUNCIL_FLAGS" })
add("council", { "council", "wasteRatio" }, "number", { "RULEF_COUNCIL_WASTE_RATIO" }, { min = 1, max = 100 })
add("council", { "council", "verdicts" }, "choice", { "RULEF_COUNCIL_VERDICTS" }, { options = VERDICTS })
add("council", { "council", "members" }, "names", { "RULEF_COUNCIL_MEMBERS" }, { wide = true, max = 10 })

-- legendary and bench (§3.7, §6)
add("legendary", { "legendary", "mode" }, "choice", { "RULEF_LEGENDARY_MODE" }, { options = LEGENDARY })
add("legendary", { "legendary", "chainPieceCost" }, "number", { "RULEF_LEGENDARY_CHAIN_COST" }, { min = 0, max = 1000 })
add("legendary", { "bench", "creditEffect" }, "choice", { "RULEF_BENCH_EFFECT" }, { options = BENCH })
add("legendary", { "bench", "creditAmount" }, "number", { "RULEF_BENCH_AMOUNT" }, { min = 0, max = 100 })
add("legendary", { "bench", "minTanks" }, "int", { "RULEF_BENCH_TANKS" }, { min = 0, max = 40 })
add("legendary", { "bench", "minHealers" }, "int", { "RULEF_BENCH_HEALERS" }, { min = 0, max = 40 })

-- messages: what the addon writes in /raid (§4, §4.1)
add("messages", { "notice", "text" }, "text", { "RULEF_NOTICE_TEXT" }, { wide = true, max = 120 })
add("messages", { "notice", "outdatedText" }, "text", { "RULEF_NOTICE_OUTDATED_TEXT" }, { wide = true, max = 120 })
add("messages", { "notice", "link" }, "text", { "RULEF_NOTICE_LINK" }, { wide = true, max = 80 })
add("messages", { "notice", "whisper" }, "bool", { "RULEF_NOTICE_WHISPER" })
add("messages", { "notice", "minutes" }, "int", { "RULEF_NOTICE_MINUTES" }, { min = 0, max = 60 })
add("messages", { "announce", "enabled" }, "bool", { "RULEF_ANNOUNCE_ENABLED" })
add("messages", { "announce", "itemText" }, "text", { "RULEF_ANNOUNCE_ITEM_TEXT" }, { wide = true, max = 200 })
add("messages", { "announce", "resultText" }, "text", { "RULEF_ANNOUNCE_RESULT_TEXT" }, { wide = true, max = 200 })
add("messages", { "announce", "reason" }, "bool", { "RULEF_ANNOUNCE_REASON" })

-- upgrade: the badge of the popup (§5.1; M7-5c: the stat-weight thresholds are gone, the rule is fixed)
add("upgrade", { "upgrade", "enabled" }, "bool", { "RULEF_UPGRADE_ENABLED" })
add("upgrade", { "upgrade", "autoPass" }, "bool", { "RULEF_UPGRADE_AUTO_PASS" })

-- site: the guild's key on the community site (§7.1)
add("site", { "site", "factionName" }, "text", { "RULEF_SITE_FACTION" }, { wide = true, max = 40 })
add("site", { "site", "extended" }, "bool", { "RULEF_SITE_EXTENDED" })

RuleFields.LIST = FIELDS

-- The fields of one page, in order.
function RuleFields.Page(page)
	local out = {}
	for _, f in ipairs(FIELDS) do
		if f.page == page then out[#out + 1] = f end
	end
	return out
end

function RuleFields.Field(id) return BY_ID[id] end

---------------------------------------------------------------------------------------------------------------------
-- Reading and writing

local function walk(rules, path, upTo)
	local node = rules
	for i = 1, upTo do
		if type(node) ~= "table" then return nil end
		node = node[path[i]]
	end
	return node
end

-- The value of a field in `rules`, as the window shows it: a boolean, a number, a code ("roll,reroll" for a list), a line of
-- text, "council" for a cell the council decides. nil when the rules lack it.
function RuleFields.Get(rules, field)
	local v = walk(rules, field.path, #field.path)
	if field.kind == "bool" then
		if v == nil and field.enabledByDefault then return true end
		return v == true
	elseif field.kind == "choice" and field.list then
		if type(v) ~= "table" then return nil end
		return table.concat(v, ",")
	elseif field.kind == "names" then
		if type(v) ~= "table" then return nil end
		return table.concat(v, ", ")
	end
	return v
end

-- Writes `value` (as Get returns it) into `rules` (a copy the window edits). Returns true, or false and "MISSING" (the rules
-- lack the table the value belongs in).
function RuleFields.Set(rules, field, value)
	local parent = walk(rules, field.path, #field.path - 1)
	if type(parent) ~= "table" then return false, "MISSING" end
	local key = field.path[#field.path]
	if field.kind == "choice" and field.list then
		local list = {}
		for code in tostring(value):gmatch("[^,]+") do list[#list + 1] = code end
		parent[key] = list
	elseif field.kind == "names" then
		parent[key] = RuleFields.SplitNames(value)
	elseif field.enabledByDefault then
		-- "enabled" is the absence of the flag (Domain/Priority.lua)
		if value == true then parent[key] = nil else parent[key] = false end
	else
		parent[key] = value
	end
	return true
end

-- "Aurel, Bryn" -> { "Aurel", "Bryn" } (commas, trimmed, empty ones dropped).
function RuleFields.SplitNames(text)
	local out = {}
	for part in tostring(text or ""):gmatch("[^,]+") do
		local name = part:match("^%s*(.-)%s*$")
		if name ~= "" then out[#out + 1] = name end
	end
	return out
end

-- What the player typed, as a value: the value, or nil and a code "NUMBER" (not a number), "INT" (not a whole number),
-- "RANGE" (outside min..max) or "TEXT" (too long). `councilWord` is the player's word for "the council decides".
function RuleFields.Parse(field, text, councilWord)
	text = tostring(text or "")
	local kind = field.kind
	if kind == "text" then
		if field.max and #text > field.max then return nil, "TEXT" end
		return text
	elseif kind == "names" then
		return text
	elseif kind == "int" or kind == "number" or kind == "cost" then
		local trimmed = text:match("^%s*(.-)%s*$")
		if kind == "cost" and trimmed ~= "" and (trimmed:lower() == RuleFields.COUNCIL_WORD
			or (type(councilWord) == "string" and councilWord ~= "" and trimmed:lower() == councilWord:lower())) then
			return RuleFields.COUNCIL_WORD
		end
		local n = tonumber((trimmed:gsub(",", ".")))
		if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil, "NUMBER" end
		if kind == "int" and n ~= floor(n) then return nil, "INT" end
		if (field.min and n < field.min) or (field.max and n > field.max) then return nil, "RANGE" end
		return n
	end
	return nil, "KIND"
end

-- The value as the edit box shows it.
function RuleFields.Format(field, value, councilWord)
	if value == nil then return "" end
	if value == RuleFields.COUNCIL_WORD and field.kind == "cost" then return councilWord or value end
	if type(value) == "number" then return (("%.4f"):format(value):gsub("0+$", ""):gsub("%.$", "")) end
	return tostring(value)
end

-- The page a validation code ("session.awardMode", "cost", "notice") belongs to, or nil.
function RuleFields.PageOfCode(code)
	local head = tostring(code):match("^[^:%.]+")
	for _, f in ipairs(FIELDS) do
		if f.path[1] == head then return f.page end
	end
	return nil
end

if ns.addon then ns.addon.RuleFields = RuleFields end   -- also reachable from tests
