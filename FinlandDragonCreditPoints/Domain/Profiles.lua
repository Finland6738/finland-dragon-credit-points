-- Profiles: the personal profile as a shareable table (docs/ANALISI.md §10, M7-3). Pure Lua 5.1: it never calls the game.
--
-- A profile (AceDB, Core/Config.lua) holds the player's own settings: the look, the sounds, the language of the texts sent to
-- everyone, the roll countdown. The guild's rules are a different thing (Domain/Rules.lua + Domain/Presets.lua, written in the
-- ledger by the Guild Master) and have their own string (Domain/Backup.lua "CFG"). This module only builds, checks and compares
-- the table of the "PRF" string: { kind = "PRF", v, settings = { theme = "aurora", ... } }, so a player can paste his look on
-- Discord. Codes only; the text form is App/BackupService.lua's (the same "!FDCP:PRF:<v>:<base64>" envelope).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Profiles = {}
ns.Profiles, ns.modules.Profiles = Profiles, Profiles

local type, pairs, ipairs, sort = type, pairs, ipairs, table.sort

Profiles.V = 1
Profiles.NAME_MAX = 32
-- What a profile string carries, in the order of the window. `debug` and the minimap button stay out: they belong to the
-- machine, not to the look.
Profiles.KEYS = { "theme", "fontSource", "effects", "animations", "sounds", "guildLanguage", "rollSeconds" }

-- A profile name: 1 to NAME_MAX characters, no control character, not only spaces. true, or false and a code.
function Profiles.ValidName(name)
	if type(name) ~= "string" then return false, "NAME" end
	local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" or #name > Profiles.NAME_MAX or name:find("%c") then return false, "NAME" end
	return true
end

-- The table of a profile (the AceDB profile table or any table of the settings).
function Profiles.Export(profile)
	local settings = {}
	for _, key in ipairs(Profiles.KEYS) do
		if profile[key] ~= nil then settings[key] = profile[key] end
	end
	return { kind = "PRF", v = Profiles.V, settings = settings }
end

-- Checks a decoded table. `validate(name, value)` is Config.Validate (true, or false and a code). Returns the clean settings
-- (only the known keys), or nil and a code: "kind", "NEWER", "settings", "EMPTY" or "BAD:<key>:<code>".
function Profiles.Check(data, validate)
	if type(data) ~= "table" or data.kind ~= "PRF" then return nil, "kind" end
	if type(data.v) ~= "number" or data.v < 1 then return nil, "kind" end
	if data.v > Profiles.V then return nil, "NEWER" end
	if type(data.settings) ~= "table" then return nil, "settings" end
	local clean, n = {}, 0
	for _, key in ipairs(Profiles.KEYS) do
		local value = data.settings[key]
		if value ~= nil then
			local ok, code = validate(key, value)
			if not ok then return nil, "BAD:" .. key .. ":" .. tostring(code) end
			clean[key] = value
			n = n + 1
		end
	end
	if n == 0 then return nil, "EMPTY" end
	return clean
end

-- What applying `settings` over `current` would change: { { key, from, to } } in the order of KEYS (equal values are left out).
function Profiles.Diff(current, settings)
	local out = {}
	for _, key in ipairs(Profiles.KEYS) do
		local to = settings[key]
		if to ~= nil and current[key] ~= to then out[#out + 1] = { key = key, from = current[key], to = to } end
	end
	return out
end

-- The profile names sorted, the current one first.
function Profiles.Sorted(names, current)
	local list = {}
	for _, n in ipairs(names) do list[#list + 1] = n end
	sort(list, function(a, b)
		if (a == current) ~= (b == current) then return a == current end
		return a:lower() < b:lower()
	end)
	return list
end

if ns.addon then ns.addon.Profiles = Profiles end   -- also reachable from tests
