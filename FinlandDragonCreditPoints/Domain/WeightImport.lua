-- WeightImport: reads and writes a stat-weight string in a Pawn-like format (docs/ANALISI.md §5.1 point 3, §13 question
-- 8, M5-3). Pure domain code: it never calls the game. The format is public and simple, `( Pawn: v1: "Name": Strength=1,
-- Agility=0.5, CritRating=0.8 )`; the bare form `Strength=1, Agility=0.5` is accepted too, and the short codes of
-- Data/StatWeights.lua (`STR=1, CRIT=0.8`). The stat names are the ones such strings use; they are mapped to the codes the
-- upgrade score weighs. Nothing of any other addon's code is used.
--
-- WeightImport.Parse(text) -> { weights = { CODE = number }, name = string | nil, ignored = { "Name", ... } }
--                           or nil, code, detail. Codes: EMPTY, TOO_LONG, BAD_FORMAT (detail: the piece that is not
--                           `Stat=number`), BAD_VALUE (detail: the stat whose number is not usable), NO_STATS (nothing the
--                           score knows). A stat name the score does not know is not an error: it is listed in `ignored`
--                           (such strings carry sockets, gems and others), and the import is refused only when no stat is known.
-- WeightImport.Format(weights, name) -> the string again, in canonical order (what /fdcp weights show prints).
-- WeightImport.Sanitize(row) -> a clean copy of a saved row (numbers only, known codes only), or nil when empty.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local WeightImport = {}
ns.WeightImport, ns.modules.WeightImport = WeightImport, WeightImport

local type, tonumber, pairs, ipairs, sort = type, tonumber, pairs, ipairs, table.sort

WeightImport.MAX_LENGTH = 2000
WeightImport.MAX_WEIGHT = 1000

-- The stat names of the format, in the order Format writes them: { name, code }.
WeightImport.NAMES = {
	{ "Strength", "STR" }, { "Agility", "AGI" }, { "Stamina", "STA" }, { "Intellect", "INT" }, { "Spirit", "SPI" },
	{ "Ap", "AP" }, { "Rap", "RAP" }, { "SpellDamage", "SP" }, { "Healing", "HEAL" },
	{ "CritRating", "CRIT" }, { "HitRating", "HIT" }, { "HasteRating", "HASTE" }, { "ExpertiseRating", "EXPERTISE" },
	{ "ArmorPenetration", "ARPEN" }, { "MasteryRating", "MASTERY" }, { "Versatility", "VERS" }, { "Mp5", "MP5" },
	{ "Dps", "DPS" }, { "Armor", "ARMOR" }, { "DefenseRating", "DEF" }, { "DodgeRating", "DODGE" },
	{ "ParryRating", "PARRY" }, { "BlockRating", "BLOCK" }, { "BlockValue", "BLOCKVALUE" },
}
-- Other spellings of the same stats.
local ALIASES = { ATTACKPOWER = "AP", RANGEDATTACKPOWER = "RAP", SPELLPOWER = "SP", HEALINGPOWER = "HEAL", ARMORPEN = "ARPEN" }
-- Fields of such strings that are not stats and carry no weight.
local META = { CLASS = true, SPEC = true, ALPHA = true, BETA = true, GEMQUALITYLEVEL = true, METAGEMS = true }

local BY_NAME, CODES, ORDER = {}, {}, {}
for i, pair in ipairs(WeightImport.NAMES) do
	BY_NAME[pair[1]:upper()] = pair[2]
	CODES[pair[2]] = pair[1]
	ORDER[pair[2]] = i
end
for k, code in pairs(ALIASES) do BY_NAME[k] = code end
for code in pairs(CODES) do BY_NAME[code] = code end   -- the short codes

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function number(text)
	if not (text:match("^[-+]?%d+%.?%d*$") or text:match("^[-+]?%.%d+$")) then return nil end
	local n = tonumber(text)
	if n == nil or n ~= n or n > WeightImport.MAX_WEIGHT or n < -WeightImport.MAX_WEIGHT then return nil end
	return n
end

function WeightImport.Parse(text)
	if type(text) ~= "string" then return nil, "EMPTY" end
	text = trim(text)
	if text == "" then return nil, "EMPTY" end
	if #text > WeightImport.MAX_LENGTH then return nil, "TOO_LONG" end
	local name, body = nil, text
	if text:sub(1, 1) == "(" then
		if text:sub(-1) ~= ")" then return nil, "BAD_FORMAT", text:sub(1, 20) end
		local rest = trim(text:sub(2, -2)):match("^[Pp][Aa][Ww][Nn]%s*:%s*(.*)$")
		if not rest then return nil, "BAD_FORMAT", text:sub(1, 20) end
		rest = rest:gsub("^[vV]%d+%s*:%s*", "")
		local n, after = rest:match('^"([^"]*)"%s*:%s*(.*)$')
		if not n then return nil, "BAD_FORMAT", rest:sub(1, 20) end
		name, body = n, after
		if name == "" then name = nil end
	end
	local weights, ignored, any = {}, {}, false
	for chunk in (body .. ","):gmatch("([^,]*),") do
		chunk = trim(chunk)
		if chunk ~= "" then
			local key, value = chunk:match("^([%w_]+)%s*=%s*(.-)$")
			if not key then return nil, "BAD_FORMAT", chunk:sub(1, 30) end
			local upper = key:upper()
			if not META[upper] then
				local n = number(value)
				if n == nil then return nil, "BAD_VALUE", key end   -- a damaged string, known stat or not
				local code = BY_NAME[upper]
				if code then weights[code], any = n, true else ignored[#ignored + 1] = key end
			end
		end
	end
	if not any then return nil, "NO_STATS" end
	sort(ignored)
	return { weights = weights, name = name, ignored = ignored }
end

function WeightImport.Format(weights, name)
	local codes = {}
	for code, v in pairs(weights or {}) do
		if CODES[code] and type(v) == "number" and v == v then codes[#codes + 1] = code end
	end
	sort(codes, function(a, b) return ORDER[a] < ORDER[b] end)
	local parts = {}
	for _, code in ipairs(codes) do parts[#parts + 1] = CODES[code] .. "=" .. ("%g"):format(weights[code]) end
	local clean = (tostring(name or ""):gsub('"', ""))
	return ('( Pawn: v1: "%s": %s )'):format(clean, table.concat(parts, ", "))
end

function WeightImport.Sanitize(row)
	if type(row) ~= "table" then return nil end
	local out, any = {}, false
	for code, v in pairs(row) do
		if CODES[code] and type(v) == "number" and v == v and v <= WeightImport.MAX_WEIGHT and v >= -WeightImport.MAX_WEIGHT then
			out[code], any = v, true
		end
	end
	return any and out or nil
end

if ns.addon then ns.addon.WeightImport = WeightImport end   -- also reachable from tests
