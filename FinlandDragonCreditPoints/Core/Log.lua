-- Log: a ring buffer of the addon's own diagnostics (docs/ANALISI.md §8.1). Lua 5.1.
-- Entries hold a level, a module, a code and a few arguments. Debug output never shows names: a string argument is
-- printed as "<text>" unless the caller marks it harmless with Log.Plain (ids, enum words, state names).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Log = {}
ns.Log, ns.modules.Log = Log, Log

Log.LEVELS = { error = 1, warn = 2, info = 3, debug = 4 }
Log.NAMES = { "error", "warn", "info", "debug" }
Log.CAPACITY = 200

Log.threshold = Log.LEVELS.info   -- entries more verbose than this are dropped
Log.entries, Log.head, Log.count, Log.seq = {}, 0, 0, 0

local PLAIN = {}   -- the wrapper marks a string as free of names
function Log.Plain(s) return setmetatable({ s = tostring(s) }, PLAIN) end

function Log.SetLevel(level)
	local n = type(level) == "string" and Log.LEVELS[level] or level
	if type(n) ~= "number" or not Log.NAMES[n] then return false end
	Log.threshold = n
	return true
end

function Log.Clear()
	Log.entries, Log.head, Log.count = {}, 0, 0
end

-- Log.Add("warn", "Config", "SCHEMA_NEWER", Log.Plain("read only"), 3)
function Log.Add(level, module, code, ...)
	local n = Log.LEVELS[level]
	if not n or n > Log.threshold then return false end
	Log.seq = Log.seq + 1
	Log.head = Log.head % Log.CAPACITY + 1
	Log.entries[Log.head] = { seq = Log.seq, level = n, module = module, code = code, args = { ... }, n = select("#", ...) }
	if Log.count < Log.CAPACITY then Log.count = Log.count + 1 end
	return true
end

for _, name in ipairs(Log.NAMES) do
	Log[name] = function(module, code, ...) return Log.Add(name, module, code, ...) end
end

local function render(v)
	local t = type(v)
	if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
	if t == "string" then return "<text>" end
	if t == "table" and getmetatable(v) == PLAIN then return v.s end
	return "<" .. t .. ">"
end

-- The entries oldest first, as plain rows { seq, level, module, code, args }.
function Log.Entries()
	local out, first = {}, Log.count < Log.CAPACITY and 1 or Log.head % Log.CAPACITY + 1
	for i = 0, Log.count - 1 do
		out[#out + 1] = Log.entries[(first + i - 1) % Log.CAPACITY + 1]
	end
	return out
end

function Log.Format(e)
	local parts = {}
	for i = 1, e.n do parts[i] = render(e.args[i]) end
	return ("#%d [%s] %s %s%s"):format(e.seq, Log.NAMES[e.level], e.module, e.code,
		#parts > 0 and (" " .. table.concat(parts, " ")) or "")
end

-- The last `limit` entries as text lines (for a debug view).
function Log.Lines(limit)
	local all, lines = Log.Entries(), {}
	for i = math.max(1, #all - (limit or #all) + 1), #all do lines[#lines + 1] = Log.Format(all[i]) end
	return lines
end
