-- Diagnostics: the bug report (docs/ANALISI.md §11, M7-4). `/fdcp debug` opens it in a selectable window; the text is what a
-- player pastes into a GitHub issue. It holds the addon and client versions, the capability table, the lines of every
-- module (queue, ledger size, ...), the addon's own diagnostics log and the last errors the addon raised. It never holds a
-- name: every string argument is already "<text>" in the log, error messages lose their quoted strings and paths, and a last
-- pass removes every name the addon knows (the player, the guild, the pool of the season). Lua 5.1; no frames here.
local ADDON_NAME, ns = ...
ns = ns or {}
local Diagnostics = {}
ns.Diagnostics = Diagnostics
if ns.addon then ns.addon.Diagnostics = Diagnostics end   -- also reachable from tests

local L = ns.L

Diagnostics.MAX_ERRORS = 10
Diagnostics.LOG_LINES = 40
Diagnostics.errors = {}
Diagnostics.seen = 0

---------------------------------------------------------------------------------------------------------------------
-- Errors

-- An error message with nothing personal left: the file and line, the words, no quoted text and no folders.
function Diagnostics.CleanError(msg)
	local s = tostring(msg or ""):match("^[^\n]*") or ""
	s = s:gsub("\\", "/")
	s = s:gsub("[%w%._%-%s/]*/AddOns/", "")           -- the folders up to AddOns/
	s = s:gsub('"[^"]*"', "<text>"):gsub("'[^']*'", "<text>")
	return s:sub(1, 160)
end

-- True when the error comes from this addon's files.
function Diagnostics.IsOurs(msg)
	local s = tostring(msg or ""):gsub("\\", "/")
	return s:find("FinlandDragonCreditPoints/", 1, true) ~= nil or s:find(ADDON_NAME .. "/", 1, true) ~= nil
end

-- Remembers an error of the addon: the cleaned message and how many times it came. Returns true when it was one of ours.
function Diagnostics.Record(msg)
	if not Diagnostics.IsOurs(msg) then return false end
	local clean = Diagnostics.CleanError(msg)
	Diagnostics.seen = Diagnostics.seen + 1
	for _, e in ipairs(Diagnostics.errors) do
		if e.text == clean then e.count = e.count + 1; e.last = Diagnostics.seen; return true end
	end
	table.insert(Diagnostics.errors, { text = clean, count = 1, last = Diagnostics.seen })
	if #Diagnostics.errors > Diagnostics.MAX_ERRORS then table.remove(Diagnostics.errors, 1) end
	if ns.Log then ns.Log.error("Diagnostics", "LUA_ERROR", ns.Log.Plain(clean)) end
	return true
end

-- Wraps the game's error handler once: our errors are noted, then the handler goes on as before (the game's own display).
function Diagnostics:Install()
	if self.installed or not seterrorhandler or not geterrorhandler then return false end
	local previous = geterrorhandler()
	self.installed = true
	seterrorhandler(function(msg)
		pcall(Diagnostics.Record, msg)
		if previous then return previous(msg) end
	end)
	return true
end

function Diagnostics:ClearErrors() self.errors, self.seen = {}, 0 end

---------------------------------------------------------------------------------------------------------------------
-- The report

-- The names the report must never show: the player, the guild, the pool of the season and the guild's roster names.
local function knownNames()
	local names, seen = {}, {}
	local function add(n)
		if type(n) ~= "string" or #n < 2 or seen[n] then return end
		seen[n] = true
		names[#names + 1] = n
		local short = n:match("^([^%-]+)%-")
		if short and #short >= 2 and not seen[short] then seen[short] = true; names[#names + 1] = short end
	end
	local C = ns.Compat
	if C then
		pcall(function() add(C.Player.Name()); add(C.Player.Realm()); add(C.Guild.GuildName()); add(C.Guild.GuildRealm()) end)
		pcall(function() for _, row in ipairs(C.Guild.Roster() or {}) do add(row.name) end end)
	end
	pcall(function()
		local rc = ns.RosterController
		local led, season = rc and rc:Ledger(), rc and rc:Season()
		if led and season then
			for _, m in ipairs(ns.Members.Roster(led, season)) do add(m.member) end
		end
	end)
	table.sort(names, function(a, b) return #a > #b end)   -- the longest first: "Aurel-Camelot" before "Aurel"
	return names
end

-- Removes every known name from a text (a plain match, case-sensitive).
function Diagnostics.Scrub(text, names)
	for _, name in ipairs(names or {}) do
		local out, from = {}, 1
		while true do
			local a, b = text:find(name, from, true)
			if not a then break end
			out[#out + 1] = text:sub(from, a - 1)
			out[#out + 1] = "<name>"
			from = b + 1
		end
		out[#out + 1] = text:sub(from)
		text = table.concat(out)
	end
	return text
end

-- The report as a list of lines. Every section is guarded: a failing one is left out, the rest stays.
-- locale-key: DIAG_TITLE DIAG_VERSION DIAG_LEDGER DIAG_LOG DIAG_LOG_NONE DIAG_ERRORS DIAG_ERRORS_NONE DIAG_ERROR_LINE
function Diagnostics:Lines()
	local lines = { L["DIAG_TITLE"] }
	local function add(t) for _, v in ipairs(t or {}) do lines[#lines + 1] = v end end
	local version = ns.Protocol and ns.Protocol.AddonVersion() or "dev"
	lines[#lines + 1] = L["DIAG_VERSION"]:format(version, ns.Protocol and ns.Protocol.VERSION or 0, tostring(ns.Locale and ns.Locale.Active and ns.Locale.Active() or "?"))
	if ns.Compat then
		pcall(function() ns.Compat:Probe(); add(ns.Compat:DebugLines()) end)
	end
	pcall(function()
		local rc = ns.RosterController
		local led = rc and rc:Ledger()
		if led then
			local s = ns.Ledger.Stats(led)
			lines[#lines + 1] = L["DIAG_LEDGER"]:format(s.events, s.unreadable)
		end
	end)
	if ns.addon and ns.addon.DebugSectionLines then add(ns.addon:DebugSectionLines()) end
	lines[#lines + 1] = L["DIAG_ERRORS"]
	if #self.errors == 0 then
		lines[#lines + 1] = "  " .. L["DIAG_ERRORS_NONE"]
	else
		for _, e in ipairs(self.errors) do lines[#lines + 1] = L["DIAG_ERROR_LINE"]:format(e.count, e.text) end
	end
	lines[#lines + 1] = L["DIAG_LOG"]
	local log = ns.Log and ns.Log.Lines(self.LOG_LINES) or {}
	if #log == 0 then lines[#lines + 1] = "  " .. L["DIAG_LOG_NONE"] end
	for _, line in ipairs(log) do lines[#lines + 1] = "  " .. line end
	return lines
end

-- The report as one text, with the names scrubbed out.
function Diagnostics:Text()
	local text = table.concat(self:Lines(), "\n")
	return (Diagnostics.Scrub(text, knownNames()))
end

-- /fdcp debug chat: the report in the chat frame.
function Diagnostics:PrintToChat()
	for line in self:Text():gmatch("[^\n]+") do ns.addon:Print(line) end
end

if ns.addon then
	Diagnostics:Install()
end
