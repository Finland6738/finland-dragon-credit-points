-- Protocol: the first messages of the session protocol, the addon presence check (docs/ANALISI.md §4.1, §8.4, M3-5).
-- Lua 5.1. Built on Net/Codec.lua and Net/Transport.lua; App/AddonCheck.lua keeps the states.
--
--   HELLOQ { w? = { "Name-Realm", ... }, av, pv, pm }
--                                               "who runs the addon?" (`HELLO?` in the analysis; a type name is letters and
--                                               digits only). Without `w` every client in the raid answers; with it only
--                                               the members named (the newcomers of a raid join). The question carries the
--                                               asker's own HELLO fields: whoever asks is running the addon too.
--   HELLO  { av = "1.2.0", pv = 2, pm = 1 }     the answer: the addon version, the session protocol version the client
--                                               speaks and the oldest session protocol it still understands.
--
-- Both travel on RAID only (a HELLOQ or a HELLO from another distribution is ignored). A client also sends its HELLO by
-- itself when it enters a raid, and after a login or /reload inside one. Compatibility: two clients understand each
-- other when each one's `pv` is at least the other's `pm`. A client with a newer wire format uses another prefix
-- (FDCP2) and is never heard at all: it shows as "addon not active", like a client without the addon.
--
-- Bus events: "ADDON_HELLO"(info, sender) with info = { av, pv, pm } and sender as "Name-Realm";
--             "ADDON_HELLO_ASKED"(names or nil, sender) when a HELLOQ arrives (names = the `w` list, normalized).
-- Sender names go to the Bus only: never printed, stored or logged here.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Protocol = {}
ns.Protocol, ns.modules.Protocol = Protocol, Protocol

local type, ipairs, tostring, tonumber, floor = type, ipairs, tostring, tonumber, math.floor
local match, gmatch = string.match, string.gmatch

Protocol.VERSION = 1         -- the session protocol this client speaks (raise it when a session message changes)
Protocol.MIN = 1             -- the oldest session protocol this client still understands
Protocol.MAX_NAMES = 40      -- a HELLOQ names at most this many members; more means "everybody"
Protocol.MAX_VERSION_LEN = 32
Protocol.DEV_VERSION = "dev" -- the version of an unpackaged checkout (the TOC still says @project-version@)
Protocol.addonVersion = nil  -- set to force the version (tests, the network simulator)

local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function fullName(name) return ns.GuildRanks and ns.GuildRanks.FullName(name) or name end

---------------------------------------------------------------------------------------------------------------------
-- Versions

-- The addon's own version: the TOC `## Version` (C_AddOns.GetAddOnMetadata through Compat), DEV_VERSION when the TOC
-- was not packaged or the call is missing.
function Protocol.AddonVersion()
	if type(Protocol.addonVersion) == "string" then return Protocol.addonVersion end
	local value
	if ns.Compat then
		local state, v = ns.Compat.Call("C_AddOns.GetAddOnMetadata", ADDON_NAME, "Version")
		if state == ns.Compat.AVAILABLE then value = v end
	end
	if type(value) ~= "string" or value == "" or match(value, "^@") then return Protocol.DEV_VERSION end
	return value:sub(1, Protocol.MAX_VERSION_LEN)
end

-- "v1.2.3", "1.2", "1.2.3-beta2" -> { 1, 2, 3 }; nil for anything else ("dev").
function Protocol.ParseVersion(s)
	if type(s) ~= "string" then return nil end
	local core = match(s, "^v?(%d+[%.%d]*)")
	if not core or match(core, "%.%.") then return nil end
	local parts = {}
	for n in gmatch(core, "%d+") do parts[#parts + 1] = tonumber(n) end
	return parts
end

-- -1, 0 or 1 as version a is older, equal or newer than b; nil when either is not a release version.
function Protocol.CompareVersions(a, b)
	local pa, pb = Protocol.ParseVersion(a), Protocol.ParseVersion(b)
	if not pa or not pb then return nil end
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then return x < y and -1 or 1 end
	end
	return 0
end

-- This client's HELLO fields.
function Protocol.Mine()
	return { av = Protocol.AddonVersion(), pv = Protocol.VERSION, pm = Protocol.MIN }
end

-- true when the clients of `a` and `b` ({ pv, pm }) understand each other.
function Protocol.Compatible(a, b)
	return type(a) == "table" and type(b) == "table" and a.pv >= b.pm and b.pv >= a.pm
end

-- The state of a client that answered `info`, seen from `mine` (default: this client): "ACTIVE" (compatible, same or
-- newer version), "OUTDATED" (compatible, an older version: it rolls and is asked to update) or "INCOMPATIBLE" (it cannot
-- roll from the addon, like a client without it).
function Protocol.Classify(info, mine)
	mine = mine or Protocol.Mine()
	if not Protocol.Compatible(info, mine) then return "INCOMPATIBLE" end
	if Protocol.CompareVersions(info.av, mine.av) == -1 then return "OUTDATED" end
	return "ACTIVE"
end

-- The fields of a received HELLO, checked: { av, pv, pm } or nil.
function Protocol.ReadHello(msg)
	if type(msg) ~= "table" or type(msg.av) ~= "string" or msg.av == "" or #msg.av > Protocol.MAX_VERSION_LEN then return nil end
	local pv, pm = msg.pv, msg.pm
	if type(pv) ~= "number" or pv ~= floor(pv) or pv < 1 then return nil end
	if pm == nil then pm = pv end
	if type(pm) ~= "number" or pm ~= floor(pm) or pm < 1 or pm > pv then return nil end
	return { av = msg.av, pv = pv, pm = pm }
end

-- The names of a received HELLOQ, normalized ("Name-Realm"): a list, nil for "everybody", false when damaged.
function Protocol.ReadAsk(msg)
	local w = type(msg) == "table" and msg.w
	if w == nil then return nil end
	if type(w) ~= "table" or #w > Protocol.MAX_NAMES then return false end
	local names = {}
	for _, name in ipairs(w) do
		local full = type(name) == "string" and fullName(name)
		if not full then return false end
		names[#names + 1] = full
	end
	return names
end

---------------------------------------------------------------------------------------------------------------------
-- Sending

-- Sends this client's HELLO to the raid (the latest one waiting wins). Returns the transport item or nil, reason.
function Protocol:Announce()
	if not ns.Transport then return nil, "notransport" end
	local hello = Protocol.Mine()
	hello.t = "HELLO"
	return ns.Transport:Send("RAID", hello, { key = "HELLO" })
end

-- Asks the raid who runs the addon. `names` (optional list of "Name-Realm") limits the question to them; more than
-- MAX_NAMES asks everybody. `onSent()` runs when the question really left (it may wait out a lockdown or a boss).
-- Returns the transport item, or nil plus a reason.
function Protocol:Ask(names, onSent)
	if not ns.Transport then return nil, "notransport" end
	local msg = Protocol.Mine()
	msg.t = "HELLOQ"
	if type(names) == "table" and #names > 0 and #names <= Protocol.MAX_NAMES then msg.w = names end
	return ns.Transport:Send("RAID", msg, { key = msg.w and nil or "HELLOQ", onSent = onSent })
end

---------------------------------------------------------------------------------------------------------------------
-- Receiving

Protocol.stats = { asked = 0, answered = 0, hellos = 0, bad = 0 }

-- NET_MESSAGE handler for HELLOQ and HELLO. Returns true when the message was taken.
function Protocol:OnMessage(msg, sender, dist)
	if type(msg) ~= "table" or (msg.t ~= "HELLOQ" and msg.t ~= "HELLO") then return false end
	local s = Protocol.stats
	local from = fullName(sender)
	if dist ~= "RAID" or not from then s.bad = s.bad + 1 return false end
	if msg.t == "HELLO" then
		local info = Protocol.ReadHello(msg)
		if not info then s.bad = s.bad + 1 return false end
		s.hellos = s.hellos + 1
		emit("ADDON_HELLO", info, from)
		return true
	end
	local names = Protocol.ReadAsk(msg)
	if names == false then s.bad = s.bad + 1 return false end
	s.asked = s.asked + 1
	local asker = Protocol.ReadHello(msg)
	if asker then emit("ADDON_HELLO", asker, from) end
	local me = ns.GuildRanks and ns.GuildRanks.Me()
	local mine = names == nil
	for _, name in ipairs(names or {}) do
		if name == me then mine = true break end
	end
	emit("ADDON_HELLO_ASKED", names, from)
	if mine then
		s.answered = s.answered + 1
		Protocol:Announce()
	end
	return true
end

if ns.Codec then
	ns.Codec:RegisterType("HELLOQ", {})
	-- HELLO keeps the M1-6 required field (av); pv and pm are checked by Protocol.ReadHello.
end
if ns.Transport then
	-- answers must keep up with the questions (a night open, then the joins): a few a minute, the latest one waiting wins
	ns.Transport.RATE.HELLO = { 4, 60 }
	ns.Transport.RATE.HELLOQ = { 4, 60 }
	ns.Transport.PRIORITY.HELLOQ = "NORMAL"
end
if ns.Bus then
	ns.Bus:On("NET_MESSAGE", function(_, msg, sender, dist) Protocol:OnMessage(msg, sender, dist) end, Protocol)
end
if ns.addon then ns.addon.Protocol = Protocol end   -- also reachable from tests
