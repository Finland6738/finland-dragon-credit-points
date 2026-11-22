-- Snapshot: read-only credits for every member (docs/ANALISI.md §8.4, M6-6, ADR 0006). Lua 5.1.
--
-- Only the officers hold the ledger (Net/Sync.lua, M6-5). An officer's client sends the credits table of the current
-- season (Domain/CreditSnapshot.lua) to the whole guild; a member's client keeps the newest one it was given, saved with
-- the guild's data, and its Credits tab and loot popup read it.
--
-- The messages:
--   CSNAP   GUILD or WHISPER   the snapshot (the fields of CreditSnapshot), from an officer
--   CSNAPQ  GUILD              "who has a newer snapshot than mine?" k = the `k` of the kept one (0 = none)
--           WHISPER            "send me yours" (to the officer whose offer was best)
--   CSNAPO  WHISPER            the offer of an officer whose snapshot is newer: k
--
-- Broadcast: an officer's client plans a CSNAP on GUILD SEND_DELAY seconds (plus a few seconds of its own, by name, so
-- the officers do not all send together) after its ledger grew, never two within SEND_GAP; when it hears an officer's
-- CSNAP at least as new as its own ledger first, it drops its plan. Nothing is sent at login: the members ask.
-- Recovery: a member's client, START_DELAY seconds after its guild roster is read (login, /reload, joining the guild),
-- asks on GUILD; every officer whose ledger is newer offers by WHISPER; after OFFER_WAIT seconds the member asks the best
-- offer (largest `k`, then the name) by WHISPER, and the next one if no answer comes within REQUEST_TIMEOUT.
--
-- Trust ("signed", §8.4): the sender is the name the client gives with the message, never a field, and it must have
-- now, in the local guild roster, a rank that may write ledger events (Sync:Trusted, the same test as the officers'
-- sync). A snapshot from anybody else is ignored and counted; so is one heard before the roster is read (the member asks
-- again then). A snapshot is checked field by field (CreditSnapshot.Clean) and kept only when newer (CreditSnapshot.Newer):
-- an officer whose ledger is behind cannot take the members back.
--
-- Bus events: "CREDIT_SNAPSHOT"(from) when a newer snapshot was kept.
-- Not verified in the real client: GUILD and WHISPER addon messages between a member and an officer, their throttling.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Snapshot = {}
ns.Snapshot, ns.modules.Snapshot = Snapshot, Snapshot

local type, pairs, ipairs, sort, byte = type, pairs, ipairs, table.sort, string.byte

local function log(level, code, ...) if ns.Log then ns.Log[level]("Snapshot", code, ...) end end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

Snapshot.TICK = 1
Snapshot.SEND_DELAY = 30       -- after the officer's ledger grew: the broadcast
Snapshot.STAGGER = 10          -- 0..STAGGER-1 seconds more, by the officer's name
Snapshot.SEND_GAP = 60         -- never two broadcasts closer than this
Snapshot.START_DELAY = 8       -- after the member's roster is read: the request
Snapshot.OFFER_WAIT = 5        -- the offers heard within this are compared
Snapshot.REQUEST_TIMEOUT = 30  -- an asked officer who does not answer by then is passed over
Snapshot.ANSWER_GAP = 30       -- an officer answers the same member at most once in this (offer and snapshot each)

local function newStats()
	return { sent = 0, answered = 0, offered = 0, asked = 0, received = 0, kept = 0, older = 0, untrusted = 0, early = 0,
		bad = 0, dist = 0, cancelled = 0, timeouts = 0 }
end

function Snapshot:Reset()
	self.mem = nil             -- the kept snapshot when there is no guild data to save it in: { data, from, at }
	self.sendAt = nil          -- the planned broadcast
	self.lastSent = nil
	self.lastCount = nil       -- the officer's ledger count at the last pass
	self.request = nil         -- the member's recovery: { phase = "offers"|"asked", at, offers = { [name] = k }, peer }
	self.askAt = nil           -- when the member's request goes out
	self.answered = {}         -- [name .. type] = when an officer last answered that member
	self.active = nil          -- "officer" | "member" | nil
	self.stats = newStats()
end
Snapshot:Reset()

local function now() return ns.Compat.Now() end
local function serverNow() return ns.Compat.ServerTime() end
local function Sync() return ns.Sync end
local function fullName(sender) return ns.GuildRanks and ns.GuildRanks.FullName(sender) or nil end

function Snapshot:Ledger() return Sync() and Sync():Ledger() or nil end
function Snapshot:Me() return ns.GuildRanks and ns.GuildRanks.Me() end

-- True when the player is an officer here (a rank that writes ledger events, the roster read).
function Snapshot:IsOfficer()
	local PS = ns.PermissionService
	return PS ~= nil and PS:IsReady() and Sync() ~= nil and Sync():Trusted(self:Me(), self:Ledger())
end

---------------------------------------------------------------------------------------------------------------------
-- The kept snapshot

local function store()
	local data = ns.Config and ns.Config.GuildData and ns.Config:GuildData()
	if data and not ns.Config:IsReadOnly() then return data end
	return nil
end

-- { data = snapshot, from = "Name-Realm", at = server time received } or nil.
function Snapshot:Kept()
	local data = store()
	if data then return type(data.creditSnapshot) == "table" and data.creditSnapshot or nil end
	return self.mem
end

function Snapshot:Keep(snap, from)
	local rec = { data = snap, from = from, at = serverNow() }
	local data = store()
	if data then data.creditSnapshot = rec else self.mem = rec end
	return rec
end

local function keptK(self)
	local kept = self:Kept()
	return kept and kept.data and kept.data.k or 0
end

-- The snapshot the windows show: the kept one when this client is not an officer or its ledger has no season (an
-- officer reads its own ledger). nil = read the ledger.
function Snapshot:ForView()
	local kept = self:Kept()
	if not kept or type(kept.data) ~= "table" then return nil end
	local L = self:Ledger()
	if self:IsOfficer() and L and #ns.Season.List(L) > 0 then return nil end
	return kept
end

---------------------------------------------------------------------------------------------------------------------
-- Sending

local function send(dist, msg, opts)
	if not ns.Transport then return nil end
	return ns.Transport:Send(dist, msg, opts)
end

-- The message of a snapshot: its fields and the type.
local function message(snap)
	local msg = { t = "CSNAP" }
	for k, v in pairs(snap) do msg[k] = v end
	return msg
end

-- The officer's snapshot now (nil without a season).
function Snapshot:Make()
	local L = self:Ledger()
	if not L then return nil end
	return ns.CreditSnapshot.Build(L, serverNow())
end

-- Broadcasts the officer's snapshot on GUILD now. Returns true when it was queued.
function Snapshot:Broadcast()
	self.sendAt = nil
	local snap = self:Make()
	if not snap then return false end
	self.lastSent = now()
	local ok = send("GUILD", message(snap), { key = "CSNAP" })
	if ok then self.stats.sent = self.stats.sent + 1 end
	return ok ~= nil
end

-- A few seconds of delay of its own for each officer (so they do not all send in the same second).
local function stagger(name)
	local h = 0
	for i = 1, #(name or "") do h = (h * 31 + byte(name, i)) % 997 end
	return h % Snapshot.STAGGER
end
Snapshot.Stagger = stagger

function Snapshot:Plan(delay)
	local at = now() + (delay or self.SEND_DELAY) + stagger(self:Me())
	if not self.sendAt or at < self.sendAt then self.sendAt = at end
end

-- Answers once per ANSWER_GAP per member and message type.
local function mayAnswer(self, to, what)
	local key = to .. "|" .. what
	local t = now()
	if self.answered[key] and t - self.answered[key] < self.ANSWER_GAP then return false end
	self.answered[key] = t
	return true
end

-- The member's request on GUILD.
function Snapshot:Ask()
	self.askAt = nil
	local ok = send("GUILD", { t = "CSNAPQ", k = keptK(self) }, { key = "CSNAPQ" })
	if not ok then return false end
	self.request = { phase = "offers", at = now(), offers = {} }
	self.stats.asked = self.stats.asked + 1
	return true
end

-- The best offer not yet tried: the largest k, then the name.
local function bestOffer(offers)
	local names = {}
	for name in pairs(offers) do names[#names + 1] = name end
	sort(names)
	local best
	for _, name in ipairs(names) do
		if not best or offers[name] > offers[best] then best = name end
	end
	return best
end

-- Asks the best offer by WHISPER; ends the request when there is none.
function Snapshot:Pick()
	local req = self.request
	if not req then return false end
	local peer = bestOffer(req.offers)
	if not peer then
		self.request = nil
		return false
	end
	req.offers[peer] = nil
	req.phase, req.peer, req.at = "asked", peer, now()
	send("WHISPER", { t = "CSNAPQ", k = keptK(self) }, { target = peer })
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Receiving

-- Takes a snapshot from `from` (already trusted). Returns true when it was kept.
function Snapshot:Take(msg, from)
	self.stats.received = self.stats.received + 1
	local snap, why = ns.CreditSnapshot.Clean(msg)
	if not snap then
		self.stats.bad = self.stats.bad + 1
		log("warn", "BAD", ns.Log and ns.Log.Plain(why))
		return false
	end
	local kept = self:Kept()
	if not ns.CreditSnapshot.Newer(snap, kept and kept.data, serverNow()) then
		self.stats.older = self.stats.older + 1
		return false
	end
	self:Keep(snap, from)
	self.stats.kept = self.stats.kept + 1
	emit("CREDIT_SNAPSHOT", from)
	return true
end

local TYPES = { CSNAP = true, CSNAPQ = true, CSNAPO = true }

-- NET_MESSAGE handler. Returns true when the message was one of the snapshot's.
function Snapshot:OnMessage(msg, sender, dist)
	if type(msg) ~= "table" or not TYPES[msg.t] then return false end
	local t = msg.t
	local fromGuild, fromWhisper = dist == "GUILD", dist == "WHISPER"
	if not (fromGuild or fromWhisper) or (t == "CSNAPO" and not fromWhisper) then
		self.stats.dist = self.stats.dist + 1
		return true
	end
	local from = fullName(sender)
	if not from then return true end
	local PS = ns.PermissionService
	if not (PS and PS:IsReady()) then
		self.stats.early = self.stats.early + 1
		return true
	end
	local L = self:Ledger()
	local officer = self:IsOfficer()
	if t == "CSNAPQ" then
		-- a member's request: only an officer answers, whoever asks (a member may read the credits)
		if not officer or not L then return true end
		local theirs = type(msg.k) == "number" and msg.k or 0
		local mine = ns.Ledger.Seen(L)
		if #ns.Season.List(L) == 0 then return true end
		if fromGuild then
			-- offer only what is newer than the member's; a whispered request is answered anyway (it named this officer)
			if mine > theirs and mayAnswer(self, from, "O") then
				send("WHISPER", { t = "CSNAPO", k = mine }, { target = from })
				self.stats.offered = self.stats.offered + 1
			end
		elseif mayAnswer(self, from, "S") then
			local snap = self:Make()
			if snap then
				send("WHISPER", message(snap), { target = from, prio = "BULK" })
				self.stats.answered = self.stats.answered + 1
			end
		end
		return true
	end
	-- CSNAP and CSNAPO count only from an officer
	if not Sync() or not Sync():Trusted(from, L) then
		self.stats.untrusted = self.stats.untrusted + 1
		log("warn", "UNTRUSTED", ns.Log and ns.Log.Plain(t))
		return true
	end
	if t == "CSNAPO" then
		local req = self.request
		if req and req.phase == "offers" and type(msg.k) == "number" and msg.k > keptK(self) then req.offers[from] = msg.k end
		return true
	end
	-- CSNAP: an officer who planned a broadcast drops it when this one is at least as new as its ledger
	if self.sendAt and L and type(msg.k) == "number" and msg.k >= ns.Ledger.Seen(L) then
		self.sendAt = nil
		self.stats.cancelled = self.stats.cancelled + 1
	end
	self:Take(msg, from)
	local req = self.request
	if req and fromWhisper and req.peer == from then self.request = nil end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The timer

function Snapshot:Tick()
	local PS = ns.PermissionService
	if not (PS and PS:IsReady() and self:Me()) then
		self.active = nil
		return
	end
	local t = now()
	local role = self:IsOfficer() and "officer" or "member"
	if role ~= self.active then
		self.active = role
		self.sendAt, self.request, self.askAt = nil, nil, nil
		self.lastCount = nil
		if role == "member" then self.askAt = t + self.START_DELAY end
	end
	if role == "officer" then
		local L = self:Ledger()
		local count = L and ns.Ledger.Seen(L) or 0
		if self.lastCount and count ~= self.lastCount then self:Plan(self.SEND_DELAY) end
		self.lastCount = count
		if self.sendAt and t >= self.sendAt and (not self.lastSent or t - self.lastSent >= self.SEND_GAP) then
			self:Broadcast()
		end
		return
	end
	if self.askAt and t >= self.askAt then self:Ask() end
	local req = self.request
	if req and req.phase == "offers" and t - req.at >= self.OFFER_WAIT then
		self:Pick()
	elseif req and req.phase == "asked" and t - req.at >= self.REQUEST_TIMEOUT then
		self.stats.timeouts = self.stats.timeouts + 1
		self:Pick()
	end
end

function Snapshot:Start()
	if self.ticker then return true end
	if not (ns.addon and ns.Compat and ns.Compat.NewTicker) then return false end
	self.ticker = ns.Compat.NewTicker(self.TICK, function() Snapshot:Tick() end)
	return self.ticker ~= nil
end

function Snapshot:Stats()
	local out = {}
	for k, v in pairs(self.stats) do out[k] = v end
	out.role = self.active
	out.k = keptK(self)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Wiring

if ns.Codec then
	ns.Codec:RegisterType("CSNAP", { k = "number", r = "table" })
	ns.Codec:RegisterType("CSNAPQ", { k = "number" })
	ns.Codec:RegisterType("CSNAPO", { k = "number" })
end
if ns.Transport then
	ns.Transport.PRIORITY.CSNAP = "BULK"
	ns.Transport.PRIORITY.CSNAPQ = "NORMAL"
	ns.Transport.PRIORITY.CSNAPO = "NORMAL"
	ns.Transport.RATE.CSNAP = { 4, 60 }
	ns.Transport.RATE.CSNAPQ = { 4, 60 }
	ns.Transport.RATE.CSNAPO = { 20, 60 }
end
if ns.Bus then
	ns.Bus:On("NET_MESSAGE", function(_, msg, sender, dist) Snapshot:OnMessage(msg, sender, dist) end, Snapshot)
	ns.Bus:On("GUILD_KEY_CHANGED", function() Snapshot:Reset() end, Snapshot)
	ns.Bus:On("GUILD_RANKS_READY", function() Snapshot:Start() end, Snapshot)
end
if ns.addon then
	ns.addon.Snapshot = Snapshot   -- also reachable from tests
	if ns.addon.AddDebugSection then
		ns.addon:AddDebugSection("Snapshot", function()
			local s = Snapshot:Stats()
			return { ("Snapshot: %s, kept k=%d, sent %d, answered %d, received %d, kept %d, older %d, untrusted %d, bad %d"):format(   -- nolocale (debug output)
				s.role or "off", s.k, s.sent, s.answered, s.received, s.kept, s.older, s.untrusted, s.bad) }   -- nolocale
		end)
	end
end
