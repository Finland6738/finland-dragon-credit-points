-- Sync: the officers keep one ledger between them (docs/ANALISI.md §8.4, §0 point 2, M6-5). Lua 5.1.
--
-- Every officer's client holds the whole ledger (Domain/Ledger.lua): events are immutable, their id is author:seq, a merge
-- is a set union. The sync only adds events, it never overwrites one: an event already present with another content is a
-- CONFLICT, the stored one wins and the conflict is counted for /fdcp debug.
--
-- The messages, all on OFFICER (a message of these types from another channel is ignored):
--
--   LHEADS   h = { [author] = head }   "how far I have": per author the highest seq with every seq below it present
--                                      (Ledger.Heads), at most MAX_AUTHORS authors
--   LWANT    to, r = { {a, f, l}, … }  "send me these": seqs f..l of author a, asked to the officer `to` only
--   LEVENTS  e = { event, … }, to?, d?, g?  the events, a few per message; `to` = the officer who asked, `d` = last message
--                                      of the answer, `g` = { {a, f, l, season}, … } the seqs asked that a compaction removed
--                                      (M6-7: tombstones, nothing to send). Everybody who hears them merges them (a set union:
--                                      harmless twice); a tombstone is taken only for a seq still missing here, of a season
--                                      whose compaction this client already holds (Ledger.MarkGone)
--
-- The flow is a pull: a client announces its heads (START_DELAY after its guild roster is read, CHANGE_DELAY after its own
-- ledger grows, at least every HEARTBEAT seconds, never twice within ANNOUNCE_GAP, never while its ledger is empty: it
-- learns by listening), every officer who hears heads above its own asks the one who has the most it lacks (one request
-- at a time, REQUEST_TIMEOUT to answer, then it asks again, maybe someone else), and an officer who hears heads below its
-- own announces its heads so the other can ask.
--
-- Trust (§8.4, §3.9): a sync message counts only from an officer: the sender, read from the client (never a field), must
-- have now, in the local guild roster, a rank that may write ledger events (the loosest permission of the table in force).
-- Every event then goes through the permission gate one by one: it enters only if its author had the rank its type
-- requires when it was written (PermissionService:Merge, Permissions.Gate). A refused event is not stored and is not
-- asked again (it is remembered as refused until the permission table changes or the guild roster does); events the gate
-- cannot decide yet wait in the permission service's queue.
--
-- Authors this client never saw (M3-1: the rank history is local, never exchanged): an officer who left the guild before
-- this client read its first roster would make every one of their events NOT_IN_GUILD here, and two officers' ledgers
-- would never converge. Such an author (no record at all in the local rank history) is vouched for by the officer who
-- relays the event: the event is judged with the relayer's rank, so an officer can only bring in what they could have
-- written themselves, and a member can bring in nothing. An author the history knows is always judged by their own rank.
--
-- Budgets: at most MAX_REPLY events per request, SERVE_BUDGET events served per window, MSG_BYTES of text per message
-- (Transport splits it into 255-byte chunks), LHEADS / LWANT limited per minute by the transport (Transport.RATE),
-- LEVENTS sent BULK (after the session protocol and the announcements; dropped after Transport.BULK_TTL in a queue).
--
-- Bus events: "LEDGER_SYNCED"{ from, added, refused, pending, conflict } after a merge that changed something.
-- Not verified in the real client: OFFICER addon messages (who receives them, the throttling of long texts) and the CBOR
-- of C_EncodingUtil on the payloads of the ledger.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Sync = {}
ns.Sync, ns.modules.Sync = Sync, Sync

local type, pairs, ipairs, tostring, floor, sort, concat = type, pairs, ipairs, tostring, math.floor, table.sort, table.concat

local function log(level, code, ...) if ns.Log then ns.Log[level]("Sync", code, ...) end end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

Sync.TYPES = { "LHEADS", "LWANT", "LEVENTS" }
Sync.DIST = "OFFICER"
Sync.TICK = 1                -- seconds between two passes of the timer
Sync.START_DELAY = 5         -- after the guild roster is read: the first announcement
Sync.CHANGE_DELAY = 3        -- after the ledger grew or a peer showed it lacks events: the next announcement
Sync.ANNOUNCE_GAP = 20       -- never two announcements closer than this
Sync.HEARTBEAT = 300         -- an announcement at least this often
Sync.REQUEST_TIMEOUT = 60    -- an answer that does not end by then frees the request
Sync.PEER_TTL = 1800         -- heads heard longer ago than this are forgotten
Sync.MAX_AUTHORS = 200       -- authors in one LHEADS
Sync.MAX_RANGES = 20         -- ranges in one LWANT
Sync.MAX_REPLY = 200         -- events served for one request (the asker asks again for the rest)
Sync.MAX_PER_MSG = 25        -- events in one LEVENTS
Sync.MSG_BYTES = 1800        -- encoded text of one LEVENTS (several events are packed until this)
Sync.SERVE_BUDGET = { 600, 300 }   -- at most 600 events served every 300 seconds

local function newStats()
	return { announced = 0, asked = 0, served = 0, servedEvents = 0, received = 0, added = 0, refused = 0, pending = 0,
		conflicts = 0, untrusted = 0, dist = 0, bad = 0, overBudget = 0, timeouts = 0, gone = 0 }
end

---------------------------------------------------------------------------------------------------------------------
-- State

function Sync:Reset()
	self.peers = {}            -- [name] = { h = heads, at = now }
	self.refused = {}          -- [id] = code: refused by the gate, not asked again
	self.request = nil         -- { peer, at, want }: the request waiting for its answer
	self.announceAt = nil      -- when the next announcement is due (nil = none planned)
	self.lastAnnounce = nil    -- when the last one went out
	self.lastSig = nil         -- the heads at the last pass (a change plans an announcement)
	self.served = {}           -- { {at, n}, ... } inside the SERVE_BUDGET window
	self.active = false
	self.stats = newStats()
end
Sync:Reset()

local function now() return ns.Compat.Now() end
local function serverNow() return ns.Compat.ServerTime() end
local function Lg() return ns.Ledger end
local function PS() return ns.PermissionService end

function Sync:Ledger()
	local NC = ns.NightController
	local L = NC and NC:Ledger()
	if not L or (L.schema or 0) > Lg().SCHEMA then return nil end
	return L
end

function Sync:Me() return ns.GuildRanks and ns.GuildRanks.Me() end

-- "Name-Realm" of a sender as the client gives it (nil for anything else).
local function fullName(sender)
	return ns.GuildRanks and ns.GuildRanks.FullName(sender) or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Trust

-- The loosest permission that writes a ledger event, under the table in force: holding it makes an officer here.
local function writerPermission(L)
	local P = ns.Permissions
	local t = P.Current(L)
	local best, rank
	for _, p in pairs(P.EVENT_PERMISSION) do
		if not P.FIXED[p] and (not rank or t[p] > rank or (t[p] == rank and p < best)) then best, rank = p, t[p] end
	end
	return best or "night.run"
end

-- True when `name` may take part in the sync now: in the local guild roster with a rank that may write ledger events.
function Sync:Trusted(name, L)
	L = L or self:Ledger()
	if not name or not L or not PS() then return false end
	local rank = PS():RankAt(name)
	if rank == nil or rank == false then return false end
	return ns.Permissions.Can(rank, writerPermission(L), (ns.Permissions.Current(L)))
end

-- The gate for events relayed by `relayer`: Permissions.Gate over the local rank history, where an author the history
-- has never seen is judged with the relayer's rank (see the header).
function Sync:Gate(relayer)
	local P, service = ns.Permissions, PS()
	return P.Gate(function(author, ts)
		local h = service:History()
		local rank = P.RankAt(h, author, ts)
		if rank == false and h.loaded and not h.members[author] and relayer then
			return P.RankAt(h, relayer, serverNow())
		end
		return rank
	end)
end

-- Is this client syncing? Its ledger is open and writable, its roster read, and the player an officer.
function Sync:IsActive()
	local L = self:Ledger()
	return L ~= nil and PS() ~= nil and PS():IsReady() and self:Trusted(self:Me(), L)
end

---------------------------------------------------------------------------------------------------------------------
-- What this client has and lacks

-- The heads as a string, to notice a change cheaply.
local function signature(heads)
	local list = {}
	for a, h in pairs(heads) do list[#list + 1] = a .. "=" .. h end
	sort(list)
	return concat(list, ",")
end

-- True when seq `s` of `author` needs nothing from a peer: present, refused by the gate, or waiting in the gate's queue.
local function settled(self, L, author, s)
	local id = Lg().MakeId(author, s)
	if L.events[id] or self.refused[id] or Lg().IsGone(L, author, s) then return true end
	local queued = PS() and PS().queued and PS().queued[L]
	return queued ~= nil and queued[id] == true
end

-- The ranges this client lacks below the heads `h` of a peer: { {a, f, l}, ... } (authors in order), at most MAX_RANGES
-- ranges and MAX_REPLY seqs. Returns the list and the number of seqs.
function Sync:Wanted(L, h)
	local authors = {}
	for a, top in pairs(h) do
		if type(a) == "string" and type(top) == "number" and top == floor(top) and top > (L.heads[a] or 0) then
			authors[#authors + 1] = a
		end
	end
	sort(authors)
	local ranges, count = {}, 0
	for _, a in ipairs(authors) do
		local s, top = (L.heads[a] or 0) + 1, h[a]
		while s <= top and count < self.MAX_REPLY and #ranges < self.MAX_RANGES do
			if settled(self, L, a, s) then
				s = s + 1
			else
				local f = s
				while s <= top and count < self.MAX_REPLY and not settled(self, L, a, s) do
					s = s + 1
					count = count + 1
				end
				ranges[#ranges + 1] = { a, f, s - 1 }
			end
		end
	end
	return ranges, count
end

-- True when the peer's heads `h` lack something this ledger has (it should hear our heads and ask).
local function behind(L, h)
	for a, mine in pairs(L.heads) do
		if mine > (type(h[a]) == "number" and h[a] or 0) then return true end
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------
-- Sending

local function send(msg, opts)
	if not ns.Transport then return nil, "transport" end
	return ns.Transport:Send(Sync.DIST, msg, opts)
end

-- Announces the heads now. Returns true when the message was queued. An empty ledger has nothing to offer: it is not
-- announced (the client learns by listening to the others' heads, at the latest at their next heartbeat).
function Sync:Announce()
	local L = self:Ledger()
	if not L then return false end
	local h, n = {}, 0
	for a, top in pairs(L.heads) do
		if top > 0 and n < self.MAX_AUTHORS then
			h[a] = top
			n = n + 1
		end
	end
	self.announceAt = nil
	self.lastAnnounce = now()
	if n == 0 then return false end
	local ok = send({ t = "LHEADS", h = h }, { key = "LHEADS" })
	if ok then self.stats.announced = self.stats.announced + 1 end
	return ok ~= nil
end

-- Plans an announcement `delay` seconds from now (an earlier plan stays).
function Sync:Plan(delay)
	local at = now() + (delay or self.CHANGE_DELAY)
	if not self.announceAt or at < self.announceAt then self.announceAt = at end
end

-- Asks the peer that has the most this client lacks. Returns true when a request went out.
function Sync:Ask()
	if self.request then return false end
	local L = self:Ledger()
	if not L then return false end
	local t = now()
	local names = {}
	for name in pairs(self.peers) do names[#names + 1] = name end
	sort(names)
	local best, bestRanges, bestCount
	for _, name in ipairs(names) do
		local peer = self.peers[name]
		if t - peer.at > self.PEER_TTL or not self:Trusted(name, L) then
			self.peers[name] = nil
		else
			local ranges, count = self:Wanted(L, peer.h)
			if count > 0 and (not bestCount or count > bestCount) then best, bestRanges, bestCount = name, ranges, count end
		end
	end
	if not best then return false end
	local ok = send({ t = "LWANT", to = best, r = bestRanges })
	if not ok then return false end
	self.request = { peer = best, at = t, count = bestCount }
	self.stats.asked = self.stats.asked + 1
	return true
end

-- The wire form of an event: the id is author:seq, so it does not travel.
local function wire(e)
	return { a = e.author, s = e.seq, ts = e.ts, se = e.season, ty = e.type, v = e.v, p = e.payload }
end

local function unwire(w)
	if type(w) ~= "table" or type(w.a) ~= "string" or type(w.s) ~= "number" then return nil end
	return { id = Lg().MakeId(w.a, w.s), author = w.a, seq = w.s, ts = w.ts, season = w.se, type = w.ty, v = w.v,
		payload = w.p }
end
Sync.Wire, Sync.Unwire = wire, unwire

-- Splits wire events into LEVENTS messages of at most MAX_PER_MSG events and MSG_BYTES of text. `gone` = tombstone ranges
-- (M6-7), carried by the last message.
function Sync:Pack(list, to, gone)
	local msgs, i = {}, 1
	while i <= #list do
		local n = math.min(self.MAX_PER_MSG, #list - i + 1)
		while true do
			local chunk = {}
			for k = 0, n - 1 do chunk[#chunk + 1] = list[i + k] end
			local text = ns.Codec:Encode("LEVENTS", { e = chunk, to = to, d = true })
			if n == 1 or (text and #text <= self.MSG_BYTES) then
				msgs[#msgs + 1] = { t = "LEVENTS", e = chunk, to = to }
				i = i + n
				break
			end
			n = floor(n / 2)
		end
	end
	if #msgs == 0 then msgs[1] = { t = "LEVENTS", e = {}, to = to } end
	msgs[#msgs].d = true
	if gone and #gone > 0 then msgs[#msgs].g = gone end
	return msgs
end

-- Events still allowed by the serving budget now.
local function budgetLeft(self, t)
	local count, window = self.SERVE_BUDGET[1], self.SERVE_BUDGET[2]
	local kept, used = {}, 0
	for _, s in ipairs(self.served) do
		if t - s.at < window then
			kept[#kept + 1] = s
			used = used + s.n
		end
	end
	self.served = kept
	return count - used
end

-- Answers a request of `from`: the events asked that this ledger has, up to MAX_REPLY and the budget.
function Sync:Serve(L, from, ranges)
	local t = now()
	local left = math.min(self.MAX_REPLY, budgetLeft(self, t))
	if left <= 0 then
		self.stats.overBudget = self.stats.overBudget + 1
		return false
	end
	local list, gone = {}, {}
	for i, r in ipairs(ranges) do
		if i > self.MAX_RANGES then break end
		local a, f, l = type(r) == "table" and r[1], type(r) == "table" and r[2], type(r) == "table" and r[3]
		if type(a) == "string" and type(f) == "number" and type(l) == "number" and f >= 1 and l >= f then
			local s = floor(f)
			while s <= l and #list < left do
				local e = L.events[Lg().MakeId(a, s)]
				if e then list[#list + 1] = wire(e) end
				s = s + 1
			end
			for _, g in ipairs(Lg().GoneRanges(L, a, floor(f), s - 1)) do
				if #gone < self.MAX_RANGES then gone[#gone + 1] = { a, g[1], g[2], g[3] } end
			end
		end
		if #list >= left then break end
	end
	for _, msg in ipairs(self:Pack(list, from, gone)) do send(msg) end
	self.served[#self.served + 1] = { at = t, n = #list }
	self.stats.served = self.stats.served + 1
	self.stats.servedEvents = self.stats.servedEvents + #list
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Receiving

local function addedPermissions(L, before, events)
	for _, e in ipairs(events) do
		if e.type == "PERMISSIONS_CHANGED" and L.events[e.id] and not before[e.id] then return true end
	end
	return false
end

-- Takes the tombstones of an LEVENTS (M6-7): only seqs missing here, of a season whose compaction this ledger holds.
function Sync:TakeGone(L, gone)
	local n = 0
	for i, g in ipairs(type(gone) == "table" and gone or {}) do
		if i > self.MAX_RANGES then break end
		if type(g) == "table" and type(g[1]) == "string" and type(g[2]) == "number" and type(g[3]) == "number" then
			n = n + Lg().MarkGone(L, g[1], g[2], g[3], g[4])
		end
	end
	self.stats.gone = self.stats.gone + n
	return n
end

-- Merges the events of an LEVENTS from `from` through the gate. Returns the Ledger.Merge report.
function Sync:Take(L, from, list)
	local events, present = {}, {}
	for i, w in ipairs(list) do
		if i > self.MAX_PER_MSG * 2 then break end
		local e = unwire(w)
		if e then
			events[#events + 1] = e
			present[e.id] = L.events[e.id] ~= nil
		else
			self.stats.bad = self.stats.bad + 1
		end
	end
	local report = PS():Merge(L, events, self:Gate(from))
	if not report then return nil end
	for _, r in ipairs(report.refused) do self.refused[r.id] = r.code end
	if #report.invalid > 0 then self.stats.bad = self.stats.bad + #report.invalid end
	self.stats.received = self.stats.received + #events
	self.stats.added = self.stats.added + report.added
	self.stats.refused = self.stats.refused + #report.refused
	self.stats.pending = self.stats.pending + #report.pending
	self.stats.conflicts = self.stats.conflicts + #report.conflict
	if #report.refused > 0 then log("warn", "REFUSED", #report.refused, ns.Log and ns.Log.Plain(report.refused[1].code)) end
	if #report.conflict > 0 then log("warn", "CONFLICT", #report.conflict) end
	if report.added > 0 and addedPermissions(L, present, events) then self.refused = {} end
	if report.added > 0 or #report.refused > 0 or #report.pending > 0 then
		emit("LEDGER_SYNCED", { from = from, added = report.added, refused = #report.refused, pending = #report.pending,
			conflict = #report.conflict })
	end
	return report
end

-- NET_MESSAGE handler. Returns true when the message was a sync message.
function Sync:OnMessage(msg, sender, dist)
	if type(msg) ~= "table" then return false end
	local t = msg.t
	if t ~= "LHEADS" and t ~= "LWANT" and t ~= "LEVENTS" then return false end
	if dist ~= self.DIST then
		self.stats.dist = self.stats.dist + 1
		return true
	end
	local L = self:Ledger()
	if not L or not self:IsActive() then return true end
	local from = fullName(sender)
	if not from or not self:Trusted(from, L) then
		self.stats.untrusted = self.stats.untrusted + 1
		log("warn", "UNTRUSTED", ns.Log and ns.Log.Plain(t))
		return true
	end
	local me = self:Me()
	if t == "LHEADS" then
		if type(msg.h) ~= "table" then
			self.stats.bad = self.stats.bad + 1
			return true
		end
		self.peers[from] = { h = msg.h, at = now() }
		if behind(L, msg.h) then self:Plan(self.CHANGE_DELAY) end
		self:Ask()
	elseif t == "LWANT" then
		if msg.to == me and type(msg.r) == "table" then self:Serve(L, from, msg.r) end
	else
		if type(msg.e) ~= "table" then
			self.stats.bad = self.stats.bad + 1
			return true
		end
		self:Take(L, from, msg.e)
		if msg.g ~= nil then self:TakeGone(L, msg.g) end
		local req = self.request
		if msg.d and msg.to == me and req and req.peer == from then
			self.request = nil
			self:Ask()   -- more to fetch (the rest of a long gap, or from someone else)
		end
	end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The timer

function Sync:Tick()
	local active = self:IsActive()
	if not active then
		self.active = false
		return
	end
	local t = now()
	local L = self:Ledger()
	if not self.active then
		self.active = true
		self.lastSig = signature(L.heads)
		self:Plan(self.START_DELAY)
	end
	local sig = signature(L.heads)
	if sig ~= self.lastSig then
		self.lastSig = sig
		self:Plan(self.CHANGE_DELAY)
	end
	if self.request and t - self.request.at > self.REQUEST_TIMEOUT then
		self.stats.timeouts = self.stats.timeouts + 1
		self.peers[self.request.peer] = nil   -- it did not answer: ask someone else, or wait for its next heads
		self.request = nil
	end
	local gapOk = not self.lastAnnounce or t - self.lastAnnounce >= self.ANNOUNCE_GAP
	if self.announceAt and t >= self.announceAt and gapOk then
		self:Announce()
	elseif self.lastAnnounce and t - self.lastAnnounce >= self.HEARTBEAT then
		self:Announce()
	end
	self:Ask()
end

-- Starts the timer (once). Returns true when it runs.
function Sync:Start()
	if self.ticker then return true end
	if not (ns.addon and ns.Compat and ns.Compat.NewTicker) then return false end
	self.ticker = ns.Compat.NewTicker(self.TICK, function() Sync:Tick() end)
	return self.ticker ~= nil
end

-- The numbers for /fdcp debug and the tests.
function Sync:Stats()
	local out = {}
	for k, v in pairs(self.stats) do out[k] = v end
	local n = 0
	for _ in pairs(self.peers) do n = n + 1 end
	out.peers = n
	out.waiting = self.request ~= nil
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Wiring

if ns.Codec then
	ns.Codec:RegisterType("LHEADS", { h = "table" })
	ns.Codec:RegisterType("LWANT", { to = "string", r = "table" })
	ns.Codec:RegisterType("LEVENTS", { e = "table" })
end
if ns.Transport then
	ns.Transport.PRIORITY.LHEADS = "NORMAL"
	ns.Transport.PRIORITY.LWANT = "NORMAL"
	ns.Transport.PRIORITY.LEVENTS = "BULK"
	ns.Transport.RATE.LHEADS = { 3, 60 }
	ns.Transport.RATE.LWANT = { 10, 60 }
end
if ns.Bus then
	ns.Bus:On("NET_MESSAGE", function(_, msg, sender, dist) Sync:OnMessage(msg, sender, dist) end, Sync)
	ns.Bus:On("GUILD_KEY_CHANGED", function() Sync:Reset() end, Sync)
	-- a new roster or permission table may turn a refused event into an accepted one: ask again
	ns.Bus:On("GUILD_RANK_HISTORY_CHANGED", function() Sync.refused = {} end, Sync)
	-- the timer starts once a guild roster has been read (before that the client cannot be an officer here)
	ns.Bus:On("GUILD_RANKS_READY", function() Sync:Start() end, Sync)
end
if ns.addon then
	ns.addon.Sync = Sync   -- also reachable from tests
	if ns.addon.AddDebugSection then
		ns.addon:AddDebugSection("Sync", function()
			local s = Sync:Stats()
			return { ("Sync: %s, peers %d, asked %d, served %d (%d events), added %d, refused %d, conflicts %d, untrusted %d, gone %d"):format(   -- nolocale (debug output)
				Sync.active and "on" or "off", s.peers, s.asked, s.served, s.servedEvents, s.added, s.refused,   -- nolocale
				s.conflicts, s.untrusted, s.gone) }
		end)
	end
end
