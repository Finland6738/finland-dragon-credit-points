-- Locale boot (M1-5, docs/ANALISI.md §8.5): every language file registers its strings here, so the addon can show the
-- personal language and also build texts in the guild language. Lua 5.1.
-- AceLocale only keeps the language of the client; the personal override and the guild language need several at once, so
-- every language is also kept in `strings`. AceLocale still receives the client's language (other Ace modules read it).
-- Adding a language = one file Locale/<code>.lua that starts with `local L = select(2, ...).NewLocale("<code>", "<Name>")`
-- plus one line in both TOC files.
local ADDON_NAME, ns = ...
ns = ns or {}

local Locale = {}
ns.Locale, ns.modules = Locale, ns.modules or {}
ns.modules.Locale = Locale

local BASE = "enUS"
local strings = {}    -- code -> { KEY = text }
local languages = {}  -- registration order: { code = "itIT", name = "Italiano" }

local function clientLanguage()
	local code = GetLocale and GetLocale() or BASE
	return code == "enGB" and BASE or code
end

-- Called by a language file; returns the table to fill with `L["KEY"] = "text"`.
function ns.NewLocale(code, name)
	local store = strings[code]
	if not store then
		store = {}
		strings[code] = store
		languages[#languages + 1] = { code = code, name = name or code }
	end
	local ace   -- AceLocale's table, only for the client's language (and the base, which fills missing keys)
	local acelocale = LibStub and LibStub("AceLocale-3.0", true)
	if acelocale and (code == clientLanguage() or code == BASE) then
		ace = acelocale:NewLocale(ADDON_NAME, code, code == BASE)
	end
	return setmetatable({}, { __newindex = function(_, key, text)
		store[key] = text
		if ace then ace[key] = text end
	end })
end

local active = clientLanguage()

-- A language is available when its file is in the TOC.
function Locale.Has(code) return strings[code] ~= nil end
function Locale.Languages() return languages end
-- The tables of every language, for tests and tools.
function Locale._strings() return strings end
function Locale.Base() return BASE end
function Locale.Active() return strings[active] and active or BASE end
function Locale.Client() return clientLanguage() end

-- Switches the language of ns.L. An unknown code falls back to the client's language, then to English.
function Locale.SetActive(code)
	if code and strings[code] then active = code
	elseif strings[clientLanguage()] then active = clientLanguage()
	else active = BASE end
	return active
end

-- The text of `key` in `code`: that language, else English, else the key itself (never an empty string).
function Locale.Text(code, key)
	local s = strings[code]
	local text = s and s[key]
	if text == nil then text = strings[BASE] and strings[BASE][key] end
	if text == nil then return tostring(key) end
	return text
end

-- ns.L: one stable table whose lookups follow the active language, so `local L = ns.L` stays valid after a switch.
ns.L = setmetatable({}, { __index = function(_, key) return Locale.Text(active, key) end })

-- Texts for everyone (guild language): `Locale.Guild(key, ...)` formats with the language the GM chose.
function Locale.GuildLanguage()
	local code = ns.Config and ns.Config.Get and ns.Config:Get("guildLanguage")
	return strings[code] and code or BASE
end

function Locale.Guild(key, ...)
	local text = Locale.Text(Locale.GuildLanguage(), key)
	if select("#", ...) > 0 then return text:format(...) end
	return text
end

-- locale-key: NUMBER_DECIMAL NUMBER_GROUP DATE_SHORT DATE_LONG DATETIME (read by name below)
-- Number and date formatting follow the language (the separators and patterns are keys of the language file).
-- A language is optional: the active one by default; pass Locale.GuildLanguage() for text sent to everyone.
function Locale.FormatNumber(value, maxDecimals, code)
	code = code or active
	maxDecimals = maxDecimals or 2
	local text = ("%." .. maxDecimals .. "f"):format(value)
	if text:find("%.") then text = text:gsub("0+$", ""):gsub("%.$", "") end
	local negative = text:sub(1, 1) == "-"
	if negative then text = text:sub(2) end
	local int, frac = text:match("^(%d+)%.?(%d*)$")
	if not int then return text end
	local group = Locale.Text(code, "NUMBER_GROUP")
	if group ~= "" then
		int = int:reverse():gsub("(%d%d%d)", "%1" .. group:reverse()):reverse()
		if int:sub(1, #group) == group then int = int:sub(#group + 1) end
	end
	local out = frac ~= "" and (int .. Locale.Text(code, "NUMBER_DECIMAL") .. frac) or int
	return (negative and "-" or "") .. out
end

-- kind: "DATE_SHORT" (day and month), "DATE_LONG" (with year) or "DATETIME" (date and time).
function Locale.FormatDate(timestamp, kind, code)
	local dateFn = date or (os and os.date)
	if not dateFn then return "" end
	return dateFn(Locale.Text(code or active, kind or "DATE_SHORT"), timestamp)
end
