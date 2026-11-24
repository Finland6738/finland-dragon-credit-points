-- RosterNet: the players' roster requests on the network (docs/ANALISI.md §6.1, §8.4, fix/roster-join). Lua 5.1. Built on
-- Net/Codec.lua and Net/Transport.lua like the other messages; the requests themselves are Domain/Roster.lua's, the
-- player's and the officers' sides App/RosterController.lua's.
--
--   RREQ  GUILD    { q, k, s, c?, m1?, m2?, o?, av?, n?, f?, mn? }   a player's request: q = the player's number for it
--                                   (the server time it was made), k = "J" (join the pool, or declare when already in it
--                                   without a declaration) or "A" (this character is an alt of `mn`), s = the season, c =
--                                   the class the client gives, m1 / m2 / o = the specs (MS1, MS2, OS), av = the weekdays,
--                                   n = the short note, f = the faction. The member (or the alt) is always the sender.
--   RACK  WHISPER  { q, st }        an officer's client to the player: st = "PENDING" (stored, or already stored) or the
--                                   code of the refusal (ALREADY_JOINED, SPEC_CLASS, NO_SEASON, ...)
--   RDEC  GUILD    { p, q, st }     an officer's decision on the request q of player p: st = "A" (approved) or "R"
--                                   (rejected). The other officers drop it from their inbox, the player sees it.
--
-- Why GUILD: a member cannot reach the OFFICER channel, and the officers are not a fixed list. Every client hears a RREQ,
-- only the clients whose own rank holds `roster.manage` store it (App/PermissionService.lua); the others drop it unread.
--
-- Trust (§8.4): the sender is the name the client gives with the message, never a field: a player only asks for their
-- own character (the member of a join, the alt of an alt link). A RACK or a RDEC counts only from a sender whose rank holds
-- `roster.manage` in the local guild roster. The request is checked again against the officer's ledger
-- (Roster.Receive) and written to the ledger only by an officer's approval.
-- Dedupe and throttling: the request id is "<sender>#<q>", so a request heard twice is stored once (Roster.Receive:
-- "DUPLICATE", answered "PENDING"); a player's new request for the same member replaces their pending one. A player sends
-- one request per RosterController.SEND_GAP seconds; an officer's client takes one request per sender per RECEIVE_GAP
-- seconds and drops the rest; the transport caps every type (RATE) and keeps the latest one waiting per key. A request
-- still waiting (no officer online, a chat lockdown) is sent again once RESEND_DELAY seconds after the next login.
--
-- Bus events: none of its own (App/RosterController.lua emits ROSTER_UPDATED and ROSTER_MY_REQUEST).
-- Sender names go to the controller only: never printed or logged here.
-- Not verified in the real client: GUILD and WHISPER addon messages between a member and the officers, their throttling.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local RosterNet = {}
ns.RosterNet, ns.modules.RosterNet = RosterNet, RosterNet

local type, ipairs, pairs, floor, match, tostring, tonumber = type, ipairs, pairs, math.floor, string.match, tostring,
	tonumber

RosterNet.RECEIVE_GAP = 5      -- seconds: an officer's client takes one request per sender in this
RosterNet.RESEND_DELAY = 20    -- seconds after the guild roster is read: a request still waiting goes out again
RosterNet.SEND_TTL = 3600      -- a request still waiting in the transport after this is dropped
RosterNet.ANSWER_TTL = 120     -- an answer still waiting after this is dropped
RosterNet.MAX_TEXT = 80        -- the longest note

local function now() return ns.Compat.Now() end
local function serverNow() return ns.Compat.ServerTime() end
local function me() return ns.GuildRanks and ns.GuildRanks.Me() or nil end
local function fullName(name) return ns.GuildRanks and ns.GuildRanks.FullName(name) or nil end
local function RC() return ns.RosterController end

local function newStats()
	return { sent = 0, resent = 0, heard = 0, stored = 0, refused = 0, ignored = 0, throttled = 0, answered = 0,
		decided = 0, decisions = 0, untrusted = 0, bad = 0 }
end

function RosterNet:Reset()
	self.heardAt = {}      -- [sender] = when this client last took a request from them
	self.resent = false
	self.stats = newStats()
end
RosterNet:Reset()

local function isQ(q) return type(q) == "number" and q == floor(q) and q >= 0 and q <= 2147483647 end
local function isSeason(s) return (type(s) == "string" and s ~= "" and #s <= 32) or isQ(s) end
local function isCode(s) return type(s) == "string" and #s <= 40 and match(s, "^[A-Z][A-Z0-9_:a-z]*$") ~= nil end

---------------------------------------------------------------------------------------------------------------------
-- Wire form

-- The message of a request (the fields of Roster.RequestJoin / RequestAlt; the member and the alt are not carried: they
-- are the sender).
function RosterNet.Wire(req, q)
	local msg = { t = "RREQ", q = q, k = req.kind == "ALT" and "A" or "J", s = req.season, f = req.faction }
	if req.kind == "ALT" then
		msg.mn = req.main
	else
		msg.c, msg.m1, msg.m2, msg.o, msg.av, msg.n = req.class, req.ms1, req.ms2, req.os, req.avail, req.note
	end
	return msg
end

-- The request of a RREQ from `from` (a table for Roster.Receive), or nil when the message is damaged.
function RosterNet.Read(msg, from)
	if type(msg) ~= "table" or not isQ(msg.q) or not isSeason(msg.s) or not from then return nil end
	if msg.k ~= "J" and msg.k ~= "A" then return nil end
	local req = { id = from .. "#" .. msg.q, from = from, season = msg.s, ts = floor(serverNow()) }
	if msg.f == "Horde" or msg.f == "Alliance" then req.faction = msg.f end
	if msg.k == "A" then
		local main = type(msg.mn) == "string" and #msg.mn <= 64 and fullName(msg.mn) or nil
		if not main then return nil end
		req.kind, req.alt, req.main = "ALT", from, main
		return req
	end
	req.kind, req.member = "JOIN", from
	req.class = type(msg.c) == "string" and #msg.c <= 16 and msg.c or nil
	req.ms1, req.ms2, req.os = msg.m1, msg.m2, msg.o
	if type(msg.av) == "table" then
		local days = {}
		for i, d in ipairs(msg.av) do
			if i > 7 or type(d) ~= "string" then return nil end
			days[i] = d
		end
		req.avail = days
	end
	if msg.n ~= nil then
		if type(msg.n) ~= "string" or #msg.n > RosterNet.MAX_TEXT then return nil end
		req.note = msg.n
	end
	return req
end

-- The stored form of a request written on this client (an officer's own request).
function RosterNet.Request(req, from, q)
	return RosterNet.Read(RosterNet.Wire(req, q), from)
end

---------------------------------------------------------------------------------------------------------------------
-- Sending

local function send(dist, msg, opts)
	if not ns.Transport then return nil, "notransport" end
	return ns.Transport:Send(dist, msg, opts)
end

-- Sends the player's request (the fields of Roster.RequestJoin / RequestAlt) to the guild's officers. Returns q and the
-- message, or nil and a code (the transport's).
function RosterNet:Send(req, q)
	q = isQ(q) and q or floor(serverNow())
	local msg = RosterNet.Wire(req, q)
	local item, why = send("GUILD", msg, { key = "RREQ", ttl = self.SEND_TTL,
		onSent = function() if RC() then RC():OnSent(q) end end })
	if not item then return nil, why end
	self.stats.sent = self.stats.sent + 1
	return q, msg
end

-- Sends the player's waiting request again (the same q: the officers who stored it answer PENDING). true when it went
-- to the transport.
function RosterNet:Resend()
	local rc = RC()
	local rec = rc and rc:MyRequest()
	if not rec or type(rec.wire) ~= "table" then return false end
	if rec.state ~= "SENDING" and rec.state ~= "SENT" and rec.state ~= "PENDING" then return false end
	local status = rc:MyStatus()
	if not status or status.season ~= rec.season or (status.request and status.request.state == "APPROVED") then
		return false
	end
	local item = send("GUILD", rec.wire, { key = "RREQ", ttl = self.SEND_TTL,
		onSent = function() rc:OnSent(rec.q) end })
	if item then self.stats.resent = self.stats.resent + 1 end
	return item ~= nil
end

-- An officer's decision on request `id` ("<player>#<q>"), told to the guild: `state` = "APPROVED" | "REJECTED".
function RosterNet:Decide(id, state)
	local p, q = match(tostring(id), "^(.+)#(%d+)$")
	q = tonumber(q)
	if not p or not isQ(q) then return nil, "id" end
	local item, why = send("GUILD", { t = "RDEC", p = p, q = q, st = state == "APPROVED" and "A" or "R" },
		{ key = "RDEC:" .. id, ttl = self.SEND_TTL })
	if item then self.stats.decided = self.stats.decided + 1 end
	return item, why
end

local function answer(self, to, q, st)
	local item = send("WHISPER", { t = "RACK", q = q, st = st }, { target = to, key = "RACK:" .. to, ttl = self.ANSWER_TTL })
	if item then self.stats.answered = self.stats.answered + 1 end
	return item
end

---------------------------------------------------------------------------------------------------------------------
-- Receiving

-- True when this client's own rank holds `roster.manage` (an officer's client keeps the requests).
local function officerHere()
	local rc = RC()
	return rc ~= nil and rc:Can("roster.manage") == true
end

local function trusted(from)
	local PS = ns.PermissionService
	return PS ~= nil and PS:Can("roster.manage", from) == true
end

-- Codes of Roster.Receive that say nothing to the player: this client cannot decide (yet), or the request is already
-- there.
local SILENT = { PENDING = true, NOT_READY = true, RANK_TOO_LOW = true, NOT_GM = true, NOT_IN_GUILD = true,
	REQUEST_LIMIT = true }

function RosterNet:OnRequest(msg, from)
	local s = self.stats
	if not officerHere() then s.ignored = s.ignored + 1 return end
	local last = self.heardAt[from]
	if last and now() - last < self.RECEIVE_GAP then s.throttled = s.throttled + 1 return end
	self.heardAt[from] = now()
	local req = RosterNet.Read(msg, from)
	if not req then s.bad = s.bad + 1 return end
	s.heard = s.heard + 1
	local r, code = RC():Receive(req)
	if r or code == "DUPLICATE" then
		if r then s.stored = s.stored + 1 end
		answer(self, from, msg.q, "PENDING")
		return
	end
	s.refused = s.refused + 1
	if not SILENT[code] and isCode(code) then answer(self, from, msg.q, code) end
end

-- NET_MESSAGE handler for RREQ, RACK and RDEC. Returns true when the message was one of them.
function RosterNet:OnMessage(msg, sender, dist)
	if type(msg) ~= "table" or (msg.t ~= "RREQ" and msg.t ~= "RACK" and msg.t ~= "RDEC") then return false end
	local s = self.stats
	local from = fullName(sender)
	if not from or not isQ(msg.q) then s.bad = s.bad + 1 return true end
	if from == me() then return true end   -- an echo
	if msg.t == "RREQ" then
		if dist ~= "GUILD" then s.bad = s.bad + 1 return true end
		self:OnRequest(msg, from)
		return true
	end
	if msg.t == "RACK" then
		if dist ~= "WHISPER" or not isCode(msg.st) then s.bad = s.bad + 1 return true end
		if not trusted(from) then s.untrusted = s.untrusted + 1 return true end
		if RC() then RC():OnAnswer(msg.q, msg.st) end
		return true
	end
	-- RDEC
	local p = type(msg.p) == "string" and #msg.p <= 64 and fullName(msg.p) or nil
	if dist ~= "GUILD" or not p or (msg.st ~= "A" and msg.st ~= "R") then s.bad = s.bad + 1 return true end
	if not trusted(from) then s.untrusted = s.untrusted + 1 return true end
	s.decisions = s.decisions + 1
	local state = msg.st == "A" and "APPROVED" or "REJECTED"
	local rc = RC()
	if not rc then return true end
	if p == me() then rc:OnAnswer(msg.q, state) end
	if officerHere() then rc:Closed(p .. "#" .. msg.q, state, from) end
	return true
end

function RosterNet:Stats()
	local out = {}
	for k, v in pairs(self.stats) do out[k] = v end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Wiring

if ns.Codec then
	ns.Codec:RegisterType("RREQ", { q = "number", k = "string" })
	ns.Codec:RegisterType("RACK", { q = "number", st = "string" })
	ns.Codec:RegisterType("RDEC", { q = "number", p = "string", st = "string" })
end
if ns.Transport then
	ns.Transport.PRIORITY.RREQ = "NORMAL"
	ns.Transport.PRIORITY.RACK = "NORMAL"
	ns.Transport.PRIORITY.RDEC = "NORMAL"
	ns.Transport.RATE.RREQ = { 3, 60 }
	ns.Transport.RATE.RACK = { 10, 60 }
	ns.Transport.RATE.RDEC = { 20, 60 }
end
if ns.Bus then
	ns.Bus:On("NET_MESSAGE", function(_, msg, sender, dist) RosterNet:OnMessage(msg, sender, dist) end, RosterNet)
	ns.Bus:On("GUILD_RANKS_READY", function()
		if RosterNet.resent then return end
		RosterNet.resent = true
		ns.Compat.After(RosterNet.RESEND_DELAY, function() RosterNet:Resend() end)
	end, RosterNet)
	ns.Bus:On("GUILD_KEY_CHANGED", function() RosterNet:Reset() end, RosterNet)
end
if ns.addon then
	ns.addon.RosterNet = RosterNet   -- also reachable from tests
	if ns.addon.AddDebugSection then
		ns.addon:AddDebugSection("RosterNet", function()
			local s = RosterNet:Stats()
			return { ("Roster requests: sent %d, resent %d, heard %d, stored %d, refused %d, ignored %d, throttled %d, answered %d, decided %d, decisions %d, untrusted %d, bad %d"):format(   -- nolocale (debug output)
				s.sent, s.resent, s.heard, s.stored, s.refused, s.ignored, s.throttled, s.answered, s.decided, s.decisions,   -- nolocale
				s.untrusted, s.bad) }
		end)
	end
end
