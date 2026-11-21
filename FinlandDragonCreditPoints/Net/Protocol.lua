-- Protocol: the session protocol (docs/ANALISI.md §4, §4.1, §8.4): the addon presence check (M3-5) and the loot session
-- messages (M4-1, the second half of this file). Lua 5.1. Built on Net/Codec.lua and Net/Transport.lua;
-- App/AddonCheck.lua keeps the presence states, Domain/SessionFSM.lua the session.
--
--   HELLOQ { w? = { "Name-Realm", ... }, av, pv, pm }
--                                               "who runs the addon?" (`HELLO?` in the analysis; a type name is letters and
--                                               digits only). Without `w` every client in the raid answers; with it only
--                                               the members named (the newcomers of a raid join). The question carries the
--                                               asker's own HELLO fields: whoever asks is running the addon too.
--   HELLO  { av = "1.2.0", pv = 2, pm = 1, sq? } the answer: the addon version, the session protocol version the client
--                                               speaks and the oldest session protocol it still understands. `sq = true`
--                                               (M4-1): the client has no loot session in view (a login, a /reload, a
--                                               late join): the master looter of a running session whispers it SSTATE.
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

Protocol.VERSION = 3         -- the session protocol this client speaks (raise it when a session message changes);
                             -- 2 = the loot session messages of M4-1 (1 = the presence check of M3 only);
                             -- 3 = SRESP carries the upgrade verdicts and the worn pieces (M5-2): optional fields, so
                             --     a client of protocol 2 still understands every message and is understood
Protocol.MIN = 2             -- the oldest session protocol this client still understands
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
	hello.sq = Protocol.Session:NeedsState() or nil
	return ns.Transport:Send("RAID", hello, { key = "HELLO" })
end

-- Asks the raid who runs the addon. `names` (optional list of "Name-Realm") limits the question to them; more than
-- MAX_NAMES asks everybody. `onSent()` runs when the question really left (it may wait out a lockdown or a boss).
-- Returns the transport item, or nil plus a reason.
function Protocol:Ask(names, onSent)
	if not ns.Transport then return nil, "notransport" end
	local msg = Protocol.Mine()
	msg.t = "HELLOQ"
	msg.sq = Protocol.Session:NeedsState() or nil
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
		if msg.sq == true then Protocol.Session:OnSyncAsk({}, from) end
		return true
	end
	local names = Protocol.ReadAsk(msg)
	if names == false then s.bad = s.bad + 1 return false end
	s.asked = s.asked + 1
	local asker = Protocol.ReadHello(msg)
	if asker then emit("ADDON_HELLO", asker, from) end
	if msg.sq == true then Protocol.Session:OnSyncAsk({}, from) end
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

---------------------------------------------------------------------------------------------------------------------
-- The loot session on RAID (M4-1, docs/ANALISI.md §4, §8.4)
--
-- The master looter's client runs Domain/SessionFSM.lua (bound here with Session:Host); every other client keeps a
-- read-only copy of what the raid needs to see, the view (Session.view): the popup and the officers' read-only window
-- are drawn from it. The ML's effects become messages (Session:Publish); the members' answers become SessionFSM inputs
-- (bus event SESSION_INPUT, stepped by the controller of M4-4).
--
--   type     dist      fields (besides s = session id)              meaning
--   SOPEN    RAID      q, ml, e?, rt?, it = { {id, ca, cs, co?} }  session opened: the items with category and costs
--                                                                 per response (`cs`); `rt` = the responses on offer
--                                                                 with their tier ({ MS = 1, OS = 2 }, M4-6: what the
--                                                                 popup shows and who rolls in a tiered round); sent
--                                                                 again after a correction
--   SROLL    RAID      q, i, r, k, g?, tr?, am?, cl?, de?, rm?      round r of item i opened: kind, stage, tier, among (a
--                                                                 reroll), cl = it collects the responses, de = the
--                                                                 deadline in server time (rm = seconds left, paused)
--   SRESP    RAID      i, r, rs, lb?, n?, vd?, eq?                a member's response {response, label, note} to the
--                                                                 round r of item i: always the sender's own (the popup
--                                                                 of M4-6 sends the whole answer again at every change).
--                                                                 M5-2: vd = { m = verdict, o? = verdict } (main-spec and
--                                                                 off-spec; a verdict is { v, u?, c?, b?, p?, l? }, see
--                                                                 UpgradeScore.Pack) and eq = { "item:..." } (the worn
--                                                                 pieces it was compared with). Both are information for
--                                                                 the master looter; a damaged one is dropped and the
--                                                                 response still counts; an older client sends neither
--   SCLOSE   RAID      q, i, r                                    round closed
--   SPROP    RAID      q, i, k, tg, w?, c?, rs?, tr?, rc?, f?, m?  the proposal: who, how much, why (reason and flag
--                                                                 codes); m = modified by the ML
--   SRESULT  RAID      q, i, o, w?, c?, tg?, x?                   AWARDED (winner, cost, target), REJECTED (x = what
--                                                                 happens next) or DELIVERED
--   SPAUSE   RAID      q, p, de?, rm?                             paused (p = true) or resumed
--   SEND     RAID      q                                          session closed
--   SSYNCQ   RAID or   s?                                         "send me the session": after a /reload, on joining
--            WHISPER                                              the raid late (RAID), after a gap (WHISPER to the ML)
--   SSTATE   WHISPER   q, ml, e?, rt?, it (+ st, w, pc, tg), a?,  the whole view, for one member: the active item,
--                      rd?, pr?, pz?, en?, my?                    its round and proposal, paused, ended, the asker's
--                                                                 own response (`my` = { rs, lb?, n? })
--
-- Trust (§8.4): a response is always the sender's own: the ML takes the player from the sender the client gives, never
-- from a field; a response that names another player (`p`) is refused as forged and counted. Rolls never travel by
-- addon message: no message carries a roll and nothing read here ever becomes a ROLL input (rolls come from the chat,
-- M4-3). Control messages are taken only from the session's master looter (the sender of its SOPEN, who must name
-- himself in `ml`); a SOPEN from someone outside the raid is refused, and one from another player while a session
-- runs only when that player has `award.confirm`. Every control message carries `q`, the session's sequence number:
-- a repeat is ignored, a gap (a message lost, or expired while waiting out a long lockdown) asks the ML for SSTATE.
-- Everything goes through Net/Transport.lua: messages wait out a chat lockdown, an addon restriction and a boss
-- (plan B of §11: sessions open after ENCOUNTER_END), in order. Timers travel in server time (GetServerTime), which
-- every client shares, never in the local clock.
--
-- Bus events: "SESSION_INPUT"(input)          a SessionFSM input for the hosted session (RESPONSE), with ts
--             "SESSION_VIEW"(view, what, i, who) the view changed: what = OPENED, ITEMS, ROLL, CLOSED, PROPOSAL,
--                                             RESULT, PAUSE, ENDED, SYNCED, RESPONSE, CLEARED
--             "SESSION_REFUSED"(code, sender) a session message refused (FORGED, NOT_ML, NOT_IN_RAID, BUSY, ...)
local Session = {}
Protocol.Session = Session

Session.CONTROL = { SOPEN = true, SROLL = true, SCLOSE = true, SPROP = true, SRESULT = true, SPAUSE = true, SEND = true }
Session.TYPES = { "SOPEN", "SROLL", "SRESP", "SCLOSE", "SPROP", "SRESULT", "SPAUSE", "SEND", "SSYNCQ", "SSTATE" }
Session.LABELS = { "BIS", "BIG_UPGRADE", "SMALL_UPGRADE", "SITUATIONAL" }   -- the preset labels (§3.3); any code passes
Session.OUTCOMES = { AWARDED = true, REJECTED = true, DELIVERED = true }
Session.TARGETS = { member = true, bank = true, disenchant = true }
Session.MAX_ITEMS = 16      -- items of one session (a boss drops far fewer)
Session.MAX_ID = 64         -- length of a session id
Session.MAX_NOTE = 80       -- bytes of a response's note
Session.MAX_CODES = 16      -- reason and flag codes of a proposal
Session.SYNC_RETRY = 5      -- seconds before a member asks again for a state that did not come
Session.SYNC_TRIES = 3      -- how many times it asks after a gap before waiting for the next message
Session.SYNC_COOLDOWN = 3   -- the ML sends one state per member per this many seconds
Session.STATE_TTL = 60      -- a whispered state or question older than this is dropped (it would be stale)

Session.stats = { published = 0, inputs = 0, forged = 0, stale = 0, refused = 0, gaps = 0, dups = 0, syncAsked = 0,
	syncServed = 0, synced = 0, bad = 0 }

local huge = math.huge

local function isInt(n, lo) return type(n) == "number" and n == floor(n) and n >= (lo or 0) and n <= 2147483647 end
local function isNum(n) return type(n) == "number" and n == n and n > -huge and n < huge end
local function isCode(s) return type(s) == "string" and #s <= 32 and match(s, "^[A-Z][A-Z0-9_]*$") ~= nil end
local function isKey(s) return type(s) == "string" and #s <= 32 and match(s, "^[%a][%w_]*$") ~= nil end   -- a category
local function isSid(s) return type(s) == "string" and s ~= "" and #s <= Session.MAX_ID end
local function nameOf(s) return type(s) == "string" and s ~= "" and #s <= 64 and fullName(s) or nil end
local function me() return ns.GuildRanks and ns.GuildRanks.Me() or nil end
local function now() return ns.Compat and ns.Compat.Now() or 0 end
local function serverNow() return ns.Compat and ns.Compat.ServerTime() or 0 end

local function copy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = copy(x) end
	return c
end

local function refuse(code, sender)
	local s = Session.stats
	if code == "FORGED" then s.forged = s.forged + 1
	elseif code == "STALE" then s.stale = s.stale + 1
	elseif code == "BAD" then s.bad = s.bad + 1
	else s.refused = s.refused + 1 end
	Session.lastRefused = code
	emit("SESSION_REFUSED", code, sender)
	return false, code
end

-- A list of codes (reasons, flags), or nil when damaged. nil stays nil.
local function codeList(l)
	if l == nil then return {} end
	if type(l) ~= "table" or #l > Session.MAX_CODES then return nil end
	local out = {}
	for i, c in ipairs(l) do
		if not isCode(c) then return nil end
		out[i] = c
	end
	return out
end

-- A list of names, normalized, or false when damaged; nil stays nil.
local function nameList(l)
	if l == nil then return nil end
	if type(l) ~= "table" or #l > Protocol.MAX_NAMES then return false end
	local out = {}
	for i, n in ipairs(l) do
		local full = nameOf(n)
		if not full then return false end
		out[i] = full
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Time: the domain's deadlines are in the local clock (Compat.Now, the session's ts); the wire carries server time.

-- A local deadline as a server-time second (nil stays nil).
function Session.ToServer(deadline, t, st)
	if not isNum(deadline) then return nil end
	return floor((st or serverNow()) + (deadline - (t or now())) + 0.5)
end

-- A server-time deadline as a local one.
function Session.FromServer(de, t, st)
	if not isNum(de) then return nil end
	return (t or now()) + (de - (st or serverNow()))
end

---------------------------------------------------------------------------------------------------------------------
-- Reading messages (never trusted: every field is checked, nothing raises)

-- The items of a SOPEN or a SSTATE: { [i] = { id, ca, cs, co, st?, w?, pc?, tg? } }, or nil when damaged.
local function readItems(list, withState)
	if type(list) ~= "table" or #list > Session.MAX_ITEMS then return nil end
	local items = {}
	for i, raw in ipairs(list) do
		if type(raw) ~= "table" or not isInt(raw.id, 1) then return nil end
		if raw.ca ~= nil and not isKey(raw.ca) then return nil end
		local costs = {}
		if raw.cs ~= nil then
			if type(raw.cs) ~= "table" then return nil end
			for response, cost in pairs(raw.cs) do
				if not isCode(response) or not isNum(cost) or cost < 0 then return nil end
				costs[response] = cost
			end
		end
		local item = { id = raw.id, ca = raw.ca, cs = costs, co = raw.co == true or nil, st = "PENDING" }
		if withState then
			if raw.st ~= nil and not isCode(raw.st) then return nil end
			item.st = raw.st or "PENDING"
			if raw.w ~= nil then item.w = nameOf(raw.w) if not item.w then return nil end end
			if raw.pc ~= nil and not isNum(raw.pc) then return nil end
			if raw.tg ~= nil and not Session.TARGETS[raw.tg] then return nil end
			item.pc, item.tg = raw.pc, raw.tg
		end
		items[i] = item
	end
	return items
end

-- The responses on offer of a SOPEN or a SSTATE: { [code] = tier }, or false when damaged; nil (an older client) stays nil.
local function readTiers(t)
	if t == nil then return nil end
	if type(t) ~= "table" then return false end
	local out, n = {}, 0
	for code, tier in pairs(t) do
		n = n + 1
		if n > 8 or not isCode(code) or not isInt(tier, 1) then return false end
		out[code] = tier
	end
	return out
end

-- The round of a SROLL (or the `rd` of a SSTATE), with its local deadline; nil when damaged.
local function readRound(m, items)
	if type(m) ~= "table" or not isInt(m.i, 1) or not items[m.i] or not isInt(m.r, 1) or not isCode(m.k) then return nil end
	if m.g ~= nil and not isCode(m.g) then return nil end
	if m.tr ~= nil and not isInt(m.tr) then return nil end
	if m.de ~= nil and not isInt(m.de) then return nil end
	if m.rm ~= nil and (not isNum(m.rm) or m.rm < 0) then return nil end
	local among = nameList(m.am)
	if among == false then return nil end
	return { i = m.i, r = m.r, k = m.k, g = m.g, tr = m.tr, am = among, cl = m.cl == true or nil, de = m.de, rm = m.rm,
		deadline = Session.FromServer(m.de) }
end

-- The proposal of a SPROP (or the `pr` of a SSTATE); nil when damaged.
local function readProposal(m, items)
	if type(m) ~= "table" or not isInt(m.i, 1) or not items[m.i] or not isCode(m.k) then return nil end
	if not Session.TARGETS[m.tg] then return nil end
	local winner
	if m.w ~= nil then winner = nameOf(m.w) if not winner then return nil end end
	if m.c ~= nil and (not isNum(m.c) or m.c < 0) then return nil end
	if m.rs ~= nil and not isCode(m.rs) then return nil end
	if m.tr ~= nil and not isInt(m.tr) then return nil end
	local reasons, flags = codeList(m.rc), codeList(m.f)
	if not reasons or not flags then return nil end
	return { i = m.i, k = m.k, tg = m.tg, w = winner, c = m.c, rs = m.rs, tr = m.tr, rc = reasons, f = flags,
		m = m.m == true or nil }
end

Session.MAX_LINKS = 4       -- worn pieces named by a response
Session.MAX_LINK = 120      -- bytes of one "item:..." string

-- One verdict of a SRESP `vd`: { v, u?, c?, b?, p?, l? } checked field by field, or nil when damaged.
local function readVerdict(t)
	if type(t) ~= "table" or not isCode(t.v) then return nil end
	local out = { v = t.v }
	if t.u ~= nil then
		if t.u ~= false then return nil end
		out.u = false
	end
	if t.c ~= nil then
		if not isCode(t.c) then return nil end
		out.c = t.c
	end
	if t.b ~= nil then
		if not isCode(t.b) then return nil end
		out.b = t.b
	end
	if t.p ~= nil then
		if not isNum(t.p) or t.p ~= floor(t.p) or t.p < -100000 or t.p > 100000 then return nil end
		out.p = t.p
	end
	if t.l ~= nil then
		if not isNum(t.l) or t.l ~= floor(t.l) or t.l < -2000 or t.l > 2000 then return nil end
		out.l = t.l
	end
	return out
end

-- The `vd` of a SRESP: { m, o? } or nil (absent or damaged).
local function readVerdicts(vd)
	if type(vd) ~= "table" then return nil end
	local m = readVerdict(vd.m)
	if not m then return nil end
	local o
	if vd.o ~= nil then
		o = readVerdict(vd.o)
		if not o then return nil end
	end
	return { m = m, o = o }
end

-- The `eq` of a SRESP: a short list of item strings, or nil (absent or damaged). The text is a plain "item:123:..."
-- string, never a hyperlink: nothing in it can carry markup.
local function readLinks(eq)
	if type(eq) ~= "table" or #eq == 0 or #eq > Session.MAX_LINKS then return nil end
	local out = {}
	for i, link in ipairs(eq) do
		if type(link) ~= "string" or #link > Session.MAX_LINK or not match(link, "^item:%d+[%-%d:]*$") then return nil end
		out[i] = link
	end
	return out
end
Session.ReadVerdicts, Session.ReadLinks = readVerdicts, readLinks

-- A SRESP from `from`: { s, i, r, rs, lb, n, vd?, eq? }, or nil and a code ("FORGED" when it names another player).
function Session.ReadResponse(msg, from)
	if type(msg) ~= "table" or not from then return nil, "BAD" end
	if msg.p ~= nil and nameOf(msg.p) ~= from then return nil, "FORGED" end
	if not isSid(msg.s) or not isInt(msg.i, 1) or not isInt(msg.r, 1) or not isCode(msg.rs) then return nil, "BAD" end
	if msg.lb ~= nil and not isCode(msg.lb) then return nil, "BAD" end
	if msg.n ~= nil and (type(msg.n) ~= "string" or #msg.n > Session.MAX_NOTE) then return nil, "BAD" end
	return { s = msg.s, i = msg.i, r = msg.r, rs = msg.rs, lb = msg.lb, n = msg.n ~= "" and msg.n or nil,
		vd = readVerdicts(msg.vd), eq = readLinks(msg.eq) }
end

---------------------------------------------------------------------------------------------------------------------
-- The master looter's side: the hosted session, its effects as messages, the members' answers as inputs

Session.host = nil   -- the SessionFSM session this client runs (the master looter), bound by the controller

local function net(s)
	if type(s.net) ~= "table" then s.net = {} end
	s.net.seq = isInt(s.net.seq) and s.net.seq or 0
	if type(s.net.rounds) ~= "table" then s.net.rounds = {} end
	return s.net
end

local function nextSeq(s)
	local n = net(s)
	n.seq = n.seq + 1
	return n.seq
end

local function targetOf(p)
	if p.target then return p.target end
	if p.kind == "BANK" then return "bank" end
	if p.kind == "DISENCHANT" then return "disenchant" end
	return "member"
end

-- The responses on offer with their tier: the enabled ones of the priority rules ({ MS = 1, OS = 2 }).
local function wireTiers(s)
	local out = {}
	local responses = s.rules and s.rules.priority and s.rules.priority.responses
	for code, r in pairs(type(responses) == "table" and responses or {}) do
		if type(r) == "table" and type(r.tier) == "number" and r.enabled ~= false then out[code] = r.tier end
	end
	return out
end

local function wireItem(item, withState)
	local w = { id = item.itemID, ca = item.category, cs = copy(item.costs), co = item.council or nil }
	if withState then
		w.st = item.state
		if item.award then w.w, w.pc, w.tg = item.award.member, item.award.cost, item.award.target end
	end
	return w
end

local function wireItems(s, withState)
	local list = {}
	for i, item in ipairs(s.items) do list[i] = wireItem(item, withState) end
	return list
end

local function wireRound(s, index, t, st)
	local item = s.items[index]
	local round = item and item.round
	if not round then return nil end
	return { i = index, r = net(s).rounds[index] or 1, k = round.kind, g = round.stage, tr = round.tier,
		am = copy(round.among), cl = round.collect or nil, de = Session.ToServer(round.deadline, t, st),
		rm = round.remaining }
end

local function wireProposal(s, index)
	local item = s.items[index]
	local p = item and item.proposal
	if not p then return nil end
	return { i = index, k = p.kind, tg = targetOf(p), w = p.winner, c = p.cost, rs = p.response, tr = p.tier,
		rc = copy(p.reasons), f = copy(p.flags), m = item.intervention and true or nil }
end

-- The message for one SessionFSM effect, or nil (the effects the raid does not need: COLLECTED, NEXT_ROUND, DELIVER,
-- NO_ADDON, TIMER_EXPIRED, AUTO_FAILED, VOTE_CLOSED; ITEM_CORRECTED before the session was announced).
function Session.MessageFor(s, e)
	local t = e.type
	local n = net(s)
	if t == "ANNOUNCE_ITEMS" or (t == "ITEM_CORRECTED" and n.open) then
		n.open = true
		return { t = "SOPEN", ml = s.ml, e = s.encounter, rt = wireTiers(s), it = wireItems(s, false) }
	elseif t == "OPEN_ROUND" then
		n.rounds[e.item] = (n.rounds[e.item] or 0) + 1
		local item = s.items[e.item]
		local remaining = e.deadline == nil and item and item.round and item.round.remaining or nil
		return { t = "SROLL", i = e.item, r = n.rounds[e.item], k = e.kind, g = e.stage, tr = e.tier, am = copy(e.among),
			cl = e.collect or nil, de = Session.ToServer(e.deadline), rm = remaining }
	elseif t == "CLOSE_ROUND" then
		return { t = "SCLOSE", i = e.item, r = n.rounds[e.item] or 1 }
	elseif t == "PROPOSAL" then
		local p = wireProposal(s, e.item)
		if p then p.t = "SPROP" end
		return p
	elseif t == "AWARDED" then
		return { t = "SRESULT", i = e.item, o = "AWARDED", w = e.winner, c = e.cost, tg = e.target }
	elseif t == "REJECTED" then
		return { t = "SRESULT", i = e.item, o = "REJECTED", x = e["then"] }
	elseif t == "DELIVERED" then
		return { t = "SRESULT", i = e.item, o = "DELIVERED" }
	elseif t == "PAUSED" or t == "RESUMED" then
		local round = s.active and s.items[s.active] and s.items[s.active].round
		return { t = "SPAUSE", p = t == "PAUSED", de = round and Session.ToServer(round.deadline) or nil,
			rm = round and round.remaining or nil }
	elseif t == "ENDED" then
		return { t = "SEND" }
	end
	return nil
end

-- Binds the session this client runs as master looter (nil unbinds). Its view is rebuilt from it at once, so a /reload
-- of the ML resumes the view with the saved session. Returns true, or nil and "session".
function Session:Host(s)
	if s ~= nil and (type(s) ~= "table" or not isSid(s.id) or type(s.items) ~= "table") then return nil, "session" end
	self.host = s
	self.served = {}
	if s then
		local n = net(s)
		if n.open then self:ApplyState(Session.StateFor(s, me()), fullName(s.ml), true) end
	end
	return true
end

-- Sends the messages for `effects` (the third result of SessionFSM.Step) of the hosted session, in order, and applies
-- them to this client's own view (the client never hands a RAID message back to its sender). Returns how many.
function Session:Publish(effects, s)
	s = s or self.host
	if type(s) ~= "table" or type(effects) ~= "table" then return 0 end
	local count = 0
	for _, e in ipairs(effects) do
		local msg = type(e) == "table" and Session.MessageFor(s, e) or nil
		if msg then
			msg.s, msg.q = s.id, nextSeq(s)
			self:OnControl(copy(msg), fullName(s.ml), true)
			if ns.Transport then ns.Transport:Send("RAID", msg, { prio = "ALERT" }) end
			count = count + 1
		end
	end
	self.stats.published = self.stats.published + count
	return count
end

-- The SSTATE of session `s` for `asker` ("Name-Realm"): the whole view, with the asker's own response to the open item.
function Session.StateFor(s, asker)
	local t, st = now(), serverNow()
	local msg = { t = "SSTATE", s = s.id, q = net(s).seq, ml = s.ml, e = s.encounter, rt = wireTiers(s), it = wireItems(s, true),
		a = s.active, pz = s.paused or nil, en = s.state == "ENDED" or nil }
	local item = s.active and s.items[s.active]
	if item then
		msg.rd = wireRound(s, s.active, t, st)
		if s.state == "PROPOSAL" then msg.pr = wireProposal(s, s.active) end
		if asker and type(item.responses) == "table" and item.responses[asker] ~= nil then
			msg.my = { rs = item.responses[asker], lb = item.labels and item.labels[asker] or nil,
				n = item.notes and item.notes[asker] or nil }
		end
	end
	return msg
end

-- SSYNCQ at the ML: the asker gets SSTATE by whisper (once per SYNC_COOLDOWN seconds), while the session is announced
-- and not ended.
function Session:OnSyncAsk(msg, from)
	local s = self.host
	if not s or not net(s).open or s.state == "ENDED" then return false end
	if msg.s ~= nil and msg.s ~= s.id then return false end
	if from == fullName(s.ml) then return false end
	local t = now()
	local last = self.served[from]
	if last and t - last < Session.SYNC_COOLDOWN then return false end
	self.served[from] = t
	self.stats.syncServed = self.stats.syncServed + 1
	if ns.Transport then
		ns.Transport:Send("WHISPER", Session.StateFor(s, from), { target = from, key = "SSTATE:" .. from, prio = "ALERT",
			ttl = Session.STATE_TTL })
	end
	return true
end

-- SRESP: the ML turns it into a RESPONSE input for the open round (the player is the sender); every client notes it in
-- its view (the officers' read-only window).
function Session:OnResponse(msg, from, own)
	local r, code = Session.ReadResponse(msg, from)
	if not r then return refuse(code, from) end
	local s = self.host
	if s and s.id == r.s then
		if r.i ~= s.active or r.r ~= (net(s).rounds[r.i] or 1) then return refuse("STALE", from) end
		self.stats.inputs = self.stats.inputs + 1
		emit("SESSION_INPUT", { type = "RESPONSE", ts = now(), player = from, response = r.rs, label = r.lb,
			note = r.n, verdict = r.vd, equipped = r.eq })
	end
	local v = self.view
	if v and v.s == r.s and v.round and v.round.i == r.i and v.round.r == r.r and v.round.cl then
		v.responses[r.i] = v.responses[r.i] or {}
		v.responses[r.i][from] = { rs = r.rs, lb = r.lb, n = r.n, vd = r.vd, eq = r.eq }
		if from == me() then v.mine[r.i] = r.rs end
		emit("SESSION_VIEW", v, "RESPONSE", r.i, from)
	end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Every client's side: the view

Session.view = nil   -- { s, q, ml, e, items, a, round, proposal, paused, ended, mine = {[i] = rs}, responses }
Session.raid = nil   -- the last GROUP_SCANNED snapshot

local function changed(v, what, index, who) emit("SESSION_VIEW", v, what, index, who) end

-- May `from` open a session on this client: a raid member (when the raid roster is fully read), and while another
-- master looter's session runs, only a player with `award.confirm`. Returns true, or false and a code.
function Session:CanOpen(from)
	local raid = self.raid
	if from ~= me() and type(raid) == "table" and raid.inRaid and raid.complete and type(raid.members) == "table"
		and not raid.members[from] then
		return false, "NOT_IN_RAID"
	end
	local v = self.view
	if v and not v.ended and v.ml ~= from then
		local PS = ns.PermissionService
		if PS and PS:Can("award.confirm", from) then return true end
		return false, "BUSY"
	end
	return true
end

-- Asks the ML (`target`, by whisper) or the raid for the whole state. A gap asks again every SYNC_RETRY seconds, at
-- most SYNC_TRIES times, until a SSTATE arrives. Returns the transport item or nil and a reason.
function Session:RequestSync(target, tries)
	local t = now()
	if self.syncAt and t - self.syncAt < Session.SYNC_RETRY then return nil, "WAIT" end
	if not ns.Transport then return nil, "notransport" end
	self.syncAt = t
	self.stats.syncAsked = self.stats.syncAsked + 1
	local msg = { t = "SSYNCQ", s = self.view and self.view.s or nil }
	local item, why
	if target then
		item, why = ns.Transport:Send("WHISPER", msg, { target = target, key = "SSYNCQ", prio = "ALERT",
			ttl = Session.STATE_TTL })
	else
		item, why = ns.Transport:Send("RAID", msg, { key = "SSYNCQ", prio = "ALERT" })
	end
	tries = (tries or 1) + 1
	if target and tries <= Session.SYNC_TRIES and ns.Compat then
		local token = {}
		self.syncToken = token
		ns.Compat.After(Session.SYNC_RETRY, function()
			if self.syncToken == token and self.syncAt == t then self:RequestSync(target, tries) end
		end)
	end
	return item, why
end

local function newView(msg, ml, items, tiers)
	return { s = msg.s, q = msg.q, ml = ml, e = isInt(msg.e) and msg.e or nil, items = items, tiers = tiers, mine = {},
		responses = {} }
end

-- Applies a SSTATE (from the ML, or built locally by Session:Host). Returns true, or false and a code.
function Session:ApplyState(msg, from, own)
	if type(msg) ~= "table" or not isSid(msg.s) or not isInt(msg.q) then return refuse("BAD", from) end
	local ml = nameOf(msg.ml)
	if not ml or ml ~= from then return refuse("NOT_ML", from) end
	local v = self.view
	if v and v.s == msg.s then
		if v.ml ~= from then return refuse("NOT_ML", from) end
		if msg.q < v.q then return refuse("STALE", from) end
	elseif not own then
		local ok, code = self:CanOpen(from)
		if not ok then return refuse(code, from) end
	end
	local items = readItems(msg.it, true)
	if not items then return refuse("BAD", from) end
	local tiers = readTiers(msg.rt)
	if tiers == false then return refuse("BAD", from) end
	local nv = newView(msg, ml, items, tiers)
	if msg.a ~= nil then
		if not isInt(msg.a, 1) or not items[msg.a] then return refuse("BAD", from) end
		nv.a = msg.a
	end
	if msg.rd ~= nil then
		nv.round = readRound(msg.rd, items)
		if not nv.round then return refuse("BAD", from) end
	end
	if msg.pr ~= nil then
		nv.proposal = readProposal(msg.pr, items)
		if not nv.proposal then return refuse("BAD", from) end
	end
	if nv.a and type(msg.my) == "table" and isCode(msg.my.rs) then
		local my = msg.my
		nv.mine[nv.a] = my.rs
		nv.responses[nv.a] = { [me() or "?"] = { rs = my.rs, lb = isCode(my.lb) and my.lb or nil,
			n = type(my.n) == "string" and #my.n <= Session.MAX_NOTE and my.n ~= "" and my.n or nil } }
	end
	if v and v.s == msg.s and nv.a and v.responses[nv.a] and nv.round and v.round and v.round.r == nv.round.r then
		nv.responses[nv.a] = v.responses[nv.a]   -- what this client heard of the same round stays
	end
	nv.paused = msg.pz == true or nil
	nv.ended = msg.en == true or nil
	self.view = nv
	self.syncAt, self.syncToken = nil, nil
	if not own then self.stats.synced = self.stats.synced + 1 end
	changed(nv, "SYNCED")
	return true
end

-- A control message (SOPEN ... SEND) from `from`. `own` = the ML applying its own message.
function Session:OnControl(msg, from, own)
	local v = self.view
	if msg.t == "SOPEN" then
		if not isSid(msg.s) or not isInt(msg.q, 1) then return refuse("BAD", from) end
		local ml = nameOf(msg.ml)
		if not ml or ml ~= from then return refuse("NOT_ML", from) end
		local items = readItems(msg.it, false)
		if not items then return refuse("BAD", from) end
		local tiers = readTiers(msg.rt)
		if tiers == false then return refuse("BAD", from) end
		if v and v.s == msg.s then
			if v.ml ~= from then return refuse("NOT_ML", from) end
			if msg.q <= v.q then self.stats.dups = self.stats.dups + 1 return false, "DUP" end
			if msg.q > v.q + 1 then
				self.stats.gaps = self.stats.gaps + 1
				self:RequestSync(v.ml)
				return false, "GAP"
			end
			for i, item in ipairs(items) do   -- a correction: the states stay
				local old = v.items[i]
				if old then item.st, item.w, item.pc, item.tg = old.st, old.w, old.pc, old.tg end
			end
			v.items, v.q = items, msg.q
			if tiers then v.tiers = tiers end
			changed(v, "ITEMS")
			return true
		end
		if not own then
			local ok, code = self:CanOpen(from)
			if not ok then return refuse(code, from) end
		end
		self.view = newView(msg, ml, items, tiers)
		self.syncAt, self.syncToken = nil, nil
		if msg.q > 1 and not own then self:RequestSync(ml) end   -- earlier messages were missed
		changed(self.view, "OPENED")
		return true
	end

	if not isSid(msg.s) or not isInt(msg.q, 1) then return refuse("BAD", from) end
	if not v or v.s ~= msg.s then
		-- a session this client does not know (it reloaded, or joined late and missed the state): ask its sender
		if not own and from and (not v or v.ended or v.ml == from) then self:RequestSync(from) end
		return false, "UNKNOWN_SESSION"
	end
	if v.ml ~= from then return refuse("NOT_ML", from) end
	if msg.q <= v.q then self.stats.dups = self.stats.dups + 1 return false, "DUP" end
	if msg.q > v.q + 1 then
		self.stats.gaps = self.stats.gaps + 1
		self:RequestSync(v.ml)
		return false, "GAP"
	end

	local t = msg.t
	local index = msg.i
	if t ~= "SPAUSE" and t ~= "SEND" and (not isInt(index, 1) or not v.items[index]) then return refuse("BAD", from) end
	local item = index and v.items[index]
	local what
	if t == "SROLL" then
		local round = readRound(msg, v.items)
		if not round then return refuse("BAD", from) end
		if round.cl then v.responses[index], v.mine[index] = {}, nil end
		v.a, v.round, v.proposal = index, round, nil
		item.st = "ROLLING"
		what = "ROLL"
	elseif t == "SCLOSE" then
		if not isInt(msg.r, 1) then return refuse("BAD", from) end
		if v.round and v.round.i == index and v.round.r == msg.r then v.round = nil end
		item.st = "COMPUTING"
		what = "CLOSED"
	elseif t == "SPROP" then
		local p = readProposal(msg, v.items)
		if not p then return refuse("BAD", from) end
		v.a, v.proposal, v.round = index, p, nil
		item.st = "PROPOSAL"
		what = "PROPOSAL"
	elseif t == "SRESULT" then
		if not Session.OUTCOMES[msg.o] then return refuse("BAD", from) end
		if msg.o == "AWARDED" then
			local winner = msg.w ~= nil and nameOf(msg.w) or nil
			if (msg.w ~= nil and not winner) or (msg.c ~= nil and not isNum(msg.c))
				or (msg.tg ~= nil and not Session.TARGETS[msg.tg]) then
				return refuse("BAD", from)
			end
			item.st, item.w, item.pc, item.tg = "ASSIGNED", winner, msg.c, msg.tg
			v.a, v.round, v.proposal = nil, nil, nil
		elseif msg.o == "REJECTED" then
			if not isCode(msg.x) then return refuse("BAD", from) end
			v.proposal = nil
			if msg.x == "PENDING" or msg.x == "REOPEN" then
				item.st, v.a, v.round = "PENDING", nil, nil
			elseif msg.x == "NEXT_TIER" then
				item.st = "COMPUTING"
			end
		else
			item.st = "DELIVERED"
		end
		what = "RESULT"
	elseif t == "SPAUSE" then
		if type(msg.p) ~= "boolean" then return refuse("BAD", from) end
		if msg.de ~= nil and not isInt(msg.de) then return refuse("BAD", from) end
		if msg.rm ~= nil and (not isNum(msg.rm) or msg.rm < 0) then return refuse("BAD", from) end
		v.paused = msg.p or nil
		if v.round then
			v.round.de, v.round.rm, v.round.deadline = msg.de, msg.rm, Session.FromServer(msg.de)
		end
		what = "PAUSE"
	elseif t == "SEND" then
		v.ended, v.a, v.round, v.proposal, v.paused = true, nil, nil, nil, nil
		what = "ENDED"
	end
	v.q = msg.q
	changed(v, what, index)
	return true
end

-- The view's open round, as the popup needs it: { item, round, kind, tier, collect, remaining (seconds, nil when
-- paused or no timer), mine (this player's response) } or nil.
function Session:OpenRound()
	local v = self.view
	if not v or v.ended or not v.round then return nil end
	local r = v.round
	local remaining = r.rm
	if r.deadline and not v.paused then remaining = math.max(0, r.deadline - now()) end
	return { item = r.i, round = r.r, kind = r.k, tier = r.tr, among = r.am, collect = r.cl == true,
		remaining = remaining, mine = v.mine[r.i], info = v.items[r.i] }
end

-- This player's own answer to item `index` as this client knows it: { rs, lb, n } (a copy), or nil. The popup of M4-6 draws it.
function Session:MyAnswer(index)
	local v = self.view
	local mine = me()
	local a = v and mine and v.responses[index] and v.responses[index][mine]
	if not a then return nil end
	return { rs = a.rs, lb = a.lb, n = a.n }
end

-- This player's response {response, label, note} to the open round of the view. `extra` (optional) = { vd, eq }: the
-- upgrade verdicts and the worn pieces of UpgradeAdvisor (M5-2); a damaged one is left out. Returns the transport item
-- (or true for the ML, whose own answer is also taken at once), or nil and a code: NO_SESSION, RESPONSES_CLOSED,
-- BAD_RESPONSE, BAD_LABEL, BAD_NOTE, or the transport's reason.
function Session:Respond(response, label, note, extra)
	local v = self.view
	if not v or v.ended then return nil, "NO_SESSION" end
	local round = v.round
	if not round or not round.cl then return nil, "RESPONSES_CLOSED" end
	if not isCode(response) then return nil, "BAD_RESPONSE" end
	if label ~= nil and not isCode(label) then return nil, "BAD_LABEL" end
	if note ~= nil and (type(note) ~= "string" or #note > Session.MAX_NOTE) then return nil, "BAD_NOTE" end
	if note == "" then note = nil end
	local msg = { t = "SRESP", s = v.s, i = round.i, r = round.r, rs = response, lb = label, n = note }
	if type(extra) == "table" then
		msg.vd, msg.eq = readVerdicts(extra.vd), readLinks(extra.eq)
	end
	local item, why
	if ns.Transport then
		-- the latest answer waiting wins (a player who changes their mind during a lockdown sends one message)
		item, why = ns.Transport:Send("RAID", msg, { prio = "ALERT", key = "SRESP" })
		if not item then return nil, why end
	end
	local mine = me()
	if mine then self:OnResponse(msg, mine, true) end   -- the client never hands a RAID message back to its sender
	return item or true
end

-- True when this client has no session in view and does not run one: its HELLO asks for the state (`sq`).
function Session:NeedsState()
	return not self.host and (not self.view or self.view.ended == true)
end

-- GROUP_SCANNED: leaving the raid forgets the view of a session this client does not run. Entering one (a login, a
-- /reload, a late join) needs no message of its own: the HELLO sent then carries `sq` (Protocol:Announce).
function Session:OnGroup(snapshot)
	if type(snapshot) ~= "table" then return end
	local before = self.raid
	self.raid = snapshot
	if not snapshot.inRaid and before and before.inRaid and not self.host and self.view then
		self.view = nil
		changed(nil, "CLEARED")
	end
end

-- NET_MESSAGE handler for the session types. Returns true when the message was taken.
function Session:OnMessage(msg, sender, dist)
	if type(msg) ~= "table" then return false end
	local t = msg.t
	if not (Session.CONTROL[t] or t == "SRESP" or t == "SSYNCQ" or t == "SSTATE") then return false end
	local from = fullName(sender)
	if not from then return refuse("BAD", sender) end
	if t == "SSTATE" then
		if dist ~= "WHISPER" then return refuse("DIST", from) end
		return self:ApplyState(msg, from, false)
	end
	if t == "SSYNCQ" then
		if dist ~= "RAID" and dist ~= "WHISPER" then return refuse("DIST", from) end
		return self:OnSyncAsk(msg, from)
	end
	if dist ~= "RAID" then return refuse("DIST", from) end
	if t == "SRESP" then return self:OnResponse(msg, from, false) end
	return self:OnControl(msg, from, false)
end

function Session:Reset()
	self.host, self.view, self.raid, self.served = nil, nil, nil, {}
	self.syncAt, self.syncToken, self.lastRefused = nil, nil, nil
	for k in pairs(self.stats) do self.stats[k] = 0 end
end
Session.served = {}

if ns.Codec then
	ns.Codec:RegisterType("HELLOQ", {})
	-- HELLO keeps the M1-6 required field (av); pv and pm are checked by Protocol.ReadHello.
	for _, t in ipairs(Session.TYPES) do
		-- every session message names its session; the deep checks are the readers' above
		ns.Codec:RegisterType(t, t == "SSYNCQ" and {} or { s = "string" })
	end
end
if ns.Transport then
	-- answers must keep up with the questions (a night open, then the joins): a few a minute, the latest one waiting wins
	ns.Transport.RATE.HELLO = { 4, 60 }
	ns.Transport.RATE.HELLOQ = { 4, 60 }
	ns.Transport.PRIORITY.HELLOQ = "NORMAL"
	-- the session goes first; a member asks for the state a few times a minute at most
	for _, t in ipairs(Session.TYPES) do ns.Transport.PRIORITY[t] = "ALERT" end
	ns.Transport.RATE.SSYNCQ = { 4, 60 }
end
if ns.Bus then
	ns.Bus:On("NET_MESSAGE", function(_, msg, sender, dist)
		if not Protocol:OnMessage(msg, sender, dist) then Session:OnMessage(msg, sender, dist) end
	end, Protocol)
	ns.Bus:On("GROUP_SCANNED", function(_, snapshot) Session:OnGroup(snapshot) end, Session)
end
if ns.addon then ns.addon.Protocol = Protocol end   -- also reachable from tests
