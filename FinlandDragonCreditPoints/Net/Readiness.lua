-- ReadinessNet: the messages of the raid readiness check (docs/ANALISI.md §4.2, §8.4, ADR 0010, M8-2). Lua 5.1.
-- Built on Net/Codec.lua and Net/Transport.lua like the session protocol; the snapshot is Adapters/SelfCheck.lua's, its
-- wire form and its checks Domain/Readiness.lua's; App/ReadinessCheck.lua keeps the master looter's table.
--
--   RDYQ  RAID      { q, rv, k? }   "readiness check": q = the request (the asker's server time), rv = the wire version,
--                                   k = the consumable categories to count (codes of Data/Readiness.lua; none = all)
--   RDY   WHISPER   { q, rv, ... }  the answer, to the asker only: the fields of Readiness.Pack (enchant state per slot,
--                                   buff kinds, the counts of the categories asked). Never an item, a link or a name.
--
-- Both are new message types, outside the loot session: a client older than M8-2 drops them unread (an unknown type), so
-- it shows as "unknown" in the table; the session protocol (Protocol.VERSION) does not change. `rv` versions the fields
-- of RDY (Domain/Readiness.lua WIRE_VERSION).
--
-- Who is answered (trust, §8.4): the asker is the sender the client gives, never a field. A raider answers a RDYQ that came
-- on RAID from a member of its own raid who is the raid leader, an assistant or the master looter, or whose guild rank
-- holds `raid.addonCheck` (the officers, App/PermissionService.lua); anything else is refused and counted.
-- When: never in combat and never during a boss encounter (Adapters/SelfCheck.lua). A request heard then waits, checked
-- again every RETRY seconds, and is dropped after DEFER_TTL; a newer request replaces it.
-- Throttling: the asker sends one RDYQ per REQUEST_GAP seconds at most (App/ReadinessCheck.lua refuses sooner); a raider
-- answers the same asker once per ANSWER_GAP seconds; the transport caps both types (RATE) and keeps only the latest
-- answer waiting per asker (key RDY:<asker>); a message that waits longer than SEND_TTL is dropped, so a stale answer
-- is never sent later (not even from the transport's saved outbox after a logout). A RDY is never stored by the raider and never written to the ledger.
--
-- Bus events: "READINESS_ASKED"(q, asker)          a request was taken (the asker's own included)
--             "READINESS_REPLY"(snapshot, from, q) a raider's snapshot (the asker's own one too, without a message)
-- Sender names go to the Bus only: never printed, stored or logged here.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local ReadinessNet = {}
ns.ReadinessNet, ns.modules.ReadinessNet = ReadinessNet, ReadinessNet

local type, ipairs, pairs, floor, match = type, ipairs, pairs, math.floor, string.match

ReadinessNet.REQUEST_GAP = 30   -- seconds between two requests of the asker
ReadinessNet.ANSWER_GAP = 20    -- seconds between two answers to the same asker
ReadinessNet.RETRY = 2          -- seconds between two tries of an answer that waits for the end of combat
ReadinessNet.DEFER_TTL = 180    -- an answer still waiting after this is dropped
ReadinessNet.MAX_CATS = 16      -- categories in a RDYQ
ReadinessNet.SEND_TTL = 60      -- a RDYQ or RDY still waiting in the transport (a lockdown) after this is dropped

local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function now() return ns.Compat.Now() end
local function me() return ns.GuildRanks and ns.GuildRanks.Me() or nil end
local function fullName(name) return ns.GuildRanks and ns.GuildRanks.FullName(name) or nil end

local function newStats()
	return { asked = 0, heard = 0, answered = 0, deferred = 0, expired = 0, throttled = 0, refused = 0, replies = 0, bad = 0 }
end

function ReadinessNet:Reset()
	self.pending = nil     -- the answer waiting: { q, to, cats, at, own }
	self.answered = {}     -- [asker] = when this client last answered them
	self.timer = false
	self.stats = newStats()
end
ReadinessNet:Reset()

local function isCode(s) return type(s) == "string" and #s <= 32 and match(s, "^[A-Z][A-Z0-9_]*$") ~= nil end
local function isQ(q) return type(q) == "number" and q == floor(q) and q >= 0 and q <= 2147483647 end

-- The categories of a RDYQ: a list of codes, nil for "all", false when damaged.
function ReadinessNet.ReadCats(k)
	if k == nil then return nil end
	if type(k) ~= "table" or #k > ReadinessNet.MAX_CATS then return false end
	local out = {}
	for i, code in ipairs(k) do
		if not isCode(code) then return false end
		out[i] = code
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Trust

-- May `asker` ("Name-Realm") ask this client? true, or false and a code: "NOT_IN_RAID", "NOT_ALLOWED".
function ReadinessNet.MayAsk(asker)
	local AC = ns.AddonCheck
	local raid = AC and AC.raid
	local row = raid and raid.inRaid and raid.members[asker]
	if not row then return false, "NOT_IN_RAID" end
	if (type(row.raidRank) == "number" and row.raidRank >= 1) or row.isML then return true end
	local PS = ns.PermissionService
	if PS and PS:Can("raid.addonCheck", asker) then return true end
	return false, "NOT_ALLOWED"
end

---------------------------------------------------------------------------------------------------------------------
-- The answer

local function arm(self)
	if self.timer then return end
	self.timer = true
	ns.Compat.After(self.RETRY, function()
		self.timer = false
		self:Try()
	end)
end

-- Builds and sends the waiting answer, or waits again (combat, encounter). Returns true when it went out.
function ReadinessNet:Try()
	local p = self.pending
	if not p then return false end
	if now() - p.at > self.DEFER_TTL then
		self.pending = nil
		self.stats.expired = self.stats.expired + 1
		return false
	end
	local snap = ns.SelfCheck.Build(p.cats)
	if not snap then
		if not p.waited then
			p.waited = true
			self.stats.deferred = self.stats.deferred + 1
		end
		arm(self)
		return false
	end
	self.pending = nil
	if p.own then
		emit("READINESS_REPLY", snap, p.to, p.q)
		return true
	end
	local msg = ns.Readiness.Pack(snap)
	msg.t, msg.q = "RDY", p.q
	if not ns.Transport then return false end
	local item = ns.Transport:Send("WHISPER", msg, { target = p.to, key = "RDY:" .. p.to, ttl = self.SEND_TTL })
	if item then
		self.answered[p.to] = now()
		self.stats.answered = self.stats.answered + 1
	end
	return item ~= nil
end

-- A request taken: `q`, the categories, the asker; `own` = this client asked (no message back, no trust check).
function ReadinessNet:Take(q, cats, asker, own)
	if not own then
		local last = self.answered[asker]
		if last and now() - last < self.ANSWER_GAP then
			self.stats.throttled = self.stats.throttled + 1
			return false, "THROTTLED"
		end
	end
	self.pending = { q = q, to = asker, cats = cats, at = now(), own = own or nil }
	emit("READINESS_ASKED", q, asker)
	self:Try()
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Asking

-- Sends a readiness check `q` (default: the server time) to the raid for the categories `cats` (a list of codes) and
-- takes the asker's own snapshot. Returns q, or nil plus a reason (the transport's). The gap and the permission are
-- App/ReadinessCheck.lua's.
function ReadinessNet:Ask(cats, q)
	if not ns.Transport then return nil, "notransport" end
	q = isQ(q) and q or floor(ns.Compat.ServerTime())
	local msg = { t = "RDYQ", q = q, rv = ns.Readiness.WIRE_VERSION }
	if type(cats) == "table" then msg.k = cats end
	local item, why = ns.Transport:Send("RAID", msg, { key = "RDYQ", ttl = self.SEND_TTL })
	if not item then return nil, why end
	self.stats.asked = self.stats.asked + 1
	local mine = me()
	if mine then self:Take(q, msg.k, mine, true) end
	return q
end

---------------------------------------------------------------------------------------------------------------------
-- Receiving

-- NET_MESSAGE handler for RDYQ and RDY. Returns true when the message was one of them.
function ReadinessNet:OnMessage(msg, sender, dist)
	if type(msg) ~= "table" or (msg.t ~= "RDYQ" and msg.t ~= "RDY") then return false end
	local s = self.stats
	local from = fullName(sender)
	if not from or not isQ(msg.q) then s.bad = s.bad + 1 return true end
	if msg.t == "RDYQ" then
		if dist ~= "RAID" then s.bad = s.bad + 1 return true end
		local cats = ReadinessNet.ReadCats(msg.k)
		if cats == false then s.bad = s.bad + 1 return true end
		s.heard = s.heard + 1
		if from == me() then return true end   -- an echo: the asker already took its own
		local ok = ReadinessNet.MayAsk(from)
		if not ok then s.refused = s.refused + 1 return true end
		self:Take(msg.q, cats, from, false)
		return true
	end
	if dist ~= "WHISPER" then s.bad = s.bad + 1 return true end
	local snap = ns.Readiness.Read(msg)
	if not snap then s.bad = s.bad + 1 return true end
	s.replies = s.replies + 1
	emit("READINESS_REPLY", snap, from, msg.q)
	return true
end

function ReadinessNet:Stats()
	local out = {}
	for k, v in pairs(self.stats) do out[k] = v end
	out.waiting = self.pending ~= nil
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Wiring

if ns.Codec then
	ns.Codec:RegisterType("RDYQ", { q = "number" })
	ns.Codec:RegisterType("RDY", { q = "number" })
end
if ns.Transport then
	ns.Transport.PRIORITY.RDYQ = "NORMAL"
	ns.Transport.PRIORITY.RDY = "NORMAL"
	ns.Transport.RATE.RDYQ = { 3, 60 }
	ns.Transport.RATE.RDY = { 6, 60 }
end
if ns.Bus then
	ns.Bus:On("NET_MESSAGE", function(_, msg, sender, dist) ReadinessNet:OnMessage(msg, sender, dist) end, ReadinessNet)
end
if ns.addon then
	ns.addon.ReadinessNet = ReadinessNet   -- also reachable from tests
	if ns.addon.AddDebugSection then
		ns.addon:AddDebugSection("ReadinessNet", function()
			local s = ReadinessNet:Stats()
			return { ("Readiness: asked %d, heard %d, answered %d, deferred %d, expired %d, throttled %d, refused %d, replies %d, bad %d"):format(   -- nolocale (debug output)
				s.asked, s.heard, s.answered, s.deferred, s.expired, s.throttled, s.refused, s.replies, s.bad) }   -- nolocale
		end)
	end
end
