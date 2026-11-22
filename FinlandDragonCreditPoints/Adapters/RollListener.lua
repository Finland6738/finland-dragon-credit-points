-- RollListener: the server-side /roll results read from the system chat (docs/ANALISI.md §0 point 3, §4 "Roll", §4.1,
-- §11 risk 2; M4-3). Lua 5.1.
--
-- A roll is never made up by an addon: the popup's Roll button calls RandomRoll(1, 100) and the server writes the result
-- in CHAT_MSG_SYSTEM with the client's global string RANDOM_ROLL_RESULT ("%s rolls %d (%d-%d)" in English,
-- "%s ottiene %d (%d-%d)" in Italian, ...). The pattern is built from that global by Compat.Roll (never written by hand), so
-- every client language reads its own messages. RANDOM_ROLL_RESULT is a global string: the Forever API dump lists
-- functions and events only (CHAT_MSG_SYSTEM and ADDON_RESTRICTION_STATE_CHANGED are there), so a client without it simply
-- reads no roll [verify S3a in game].
--
-- The listener only reads and classifies; Domain/SessionFSM.lua decides. Every roll seen while a round is open goes to the
-- session as a ROLL input (the session keeps them all and Domain/Priority.lua discards the invalid ones with a code, so
-- the master looter sees them, §4.1 "roll scartato: addon non attivo"). The listener's own classification is the same
-- one, made at once for the window and the log:
--   VALID        1-100, the first valid roll of that player in the open round, present, addon active
--   NO_ROUND     no round was open (too early, or between two rounds): not given to the session
--   BEFORE_OPEN  read after the round opened but rolled before (a message held by the lockdown, see below)
--   AFTER_CLOSE  rolled after the round closed (same)
--   NOT_1_100    another range (/roll 50, /roll 1-1000): it does not use the player's turn
--   BAD_VALUE    a value outside the range
--   NOT_PRESENT  not a member of the raid frozen on the item
--   NO_ADDON     in the raid without the addon active ("addon not active", §4.1)
--   NOT_ELIGIBLE not one of the players of a reroll
--   DUPLICATE    a second valid roll of the same player in the same round: only the first counts
--   NOT_FROM_BUTTON  (M7-2d, rule session.buttonRollsOnly) no click on the popup's Roll button came with it: typed by hand
-- The order of the checks is the one of Priority (a roll with another range does not make a later one a duplicate).
--
-- Rolls only from the button (M7-2d, docs/ANALISI.md §4.1, §8.4). The game cannot tell a typed /roll from RandomRoll
-- called by a click, so a click on the popup's Roll button first sends a roll intent (SRINT, Net/Protocol.lua: item,
-- round, nonce; no value) and then calls RandomRoll. With the rule on, a roll that would be VALID counts only when an
-- intent of the same player for the same round goes with it:
--   * an intent that arrived first matches when it is not older than the window (session.buttonRollWindow) before the
--     roll, or a lockdown was seen since it arrived (the roll waited in the chat);
--   * a roll that arrived first waits for its intent (the addon message is often slower than the system message) up to
--     the window, counted only while there is no lockdown (the intent waits out the sender's lockdown in its queue);
--   * one intent per player per round: it is used up by the roll; a second intent (another nonce) is counted as a
--     DUPLICATE and ignored; a repeat of the same nonce is ignored; an intent without a roll does nothing;
--   * a roll still without an intent when its wait ends goes to the session marked `nb`: Priority discards it as
--     NOT_FROM_BUTTON and it does not use the player's turn (a click afterwards still counts);
--   * a client of an older session protocol (its HELLO says pv < INTENT_PROTOCOL) cannot send intents: its rolls are
--     judged as before M7-2d (`legacy` in the log).
-- With the rule off, or for a session saved before M7-2d, nothing changes. The player's own client also reads its own
-- roll: typed by hand during an open round of a session with the rule on, it prints a warning (POPUP_ROLL_TYPED) and
-- emits ROLL_TYPED. The game's /roll command is never touched.
-- Names are written as the ledger writes them ("Name-Realm", GuildRanks.FullName): the message gives "Name" for the
-- player's own realm.
--
-- Secret values: a CHAT_MSG_SYSTEM text that the client hides (inside an instance or during an encounter, spike S3) is
-- never read, compared or matched. Plan B (§11 risk 2): it is kept in a buffer with the time it arrived and read again
-- once the lockdown ends (ADDON_RESTRICTION_STATE_CHANGED, ENCOUNTER_END, PLAYER_REGEN_ENABLED, or a one-second recheck
-- while something waits). A message that is still hidden after the lockdown is dropped and counted (`hidden`): nothing
-- tells whether it was a roll. The arrival time is the roll's time, so a held roll is judged against the round it was
-- made in. [verify S3c in game: whether a hidden message becomes readable after the lockdown]
--
-- RollListener.Parse(text)                -> { player, value, min, max } or nil, "secret" | nil
-- RollListener.Classify(session, roll, ts) -> code (above); pure, reads the session's active item and open round
-- RollListener:Attach(getSession, step)   starts listening for a session: getSession() returns the session table (the
--                                            controller's, also after a /reload), step(input) applies an input and
--                                            returns ok, code (SessionFSM.Step through the controller)
-- RollListener:Detach()                    stops; the buffer is cleared
-- RollListener:OnSystemMessage(text)       the CHAT_MSG_SYSTEM handler (tests call it too)
-- RollListener:Flush()                     reads the held messages when the lockdown is over; returns how many were read
-- RollListener:Pending()                   how many hidden messages and rolls waiting for their intent wait (the
--                                            controller does not close a round while rolls may still be held)
-- RollListener:OnIntent(intent)            a roll intent { player, i, r, n, ts } (bus event ROLL_INTENT, M7-2d)
-- RollListener:Expire()                    gives up on the rolls whose intent did not come in time (NOT_FROM_BUTTON)
-- RollListener:Stats()                     { seen, fed, refused, held, hidden, dropped, intents, intentDups, waited,
--                                            byCode = { [code] = n } }
-- RollListener.log                         the last LOG_SIZE entries { player, value, min, max, ts, code, refused?, held?,
--                                            button?, legacy? } (held: read after the lockdown; button: an intent went
--                                            with it; legacy: an older client, judged without intent)
-- Bus events: "ROLL_SEEN"(entry) for every roll read while a session is attached (a roll waiting for its intent is
--             seen once it is decided); "ROLL_TYPED"(roll) on the player's own client for their own typed roll.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local RollListener = { log = {}, buffer = {}, waiting = {}, intents = {} }
ns.RollListener, ns.modules.RollListener = RollListener, RollListener

local type, ipairs, pairs, floor, remove = type, ipairs, pairs, math.floor, table.remove

RollListener.LOG_SIZE = 200      -- rolls kept for the window and the debug output
RollListener.MAX_BUFFER = 200    -- hidden messages held during one lockdown (the oldest go first)
RollListener.RECHECK = 1         -- seconds between two reads of the buffer while it is not empty
RollListener.MIN, RollListener.MAX = 1, 100
RollListener.INTENT_PROTOCOL = 6 -- the session protocol that sends roll intents (Net/Protocol.lua, M7-2d)

local function C() return ns.Compat end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

local function newStats()
	return { seen = 0, fed = 0, refused = 0, held = 0, hidden = 0, dropped = 0, intents = 0, intentDups = 0, waited = 0,
		byCode = {} }
end
RollListener.stats = newStats()

local function fullName(name)
	if type(name) ~= "string" or name == "" then return nil end
	local GR = ns.GuildRanks
	return GR and GR.FullName(name) or name
end

function RollListener.Parse(text)
	local roll, why = C().Roll.Parse(text)
	if not roll then return nil, why end
	local player = fullName(roll.player)
	if not player then return nil end
	return { player = player, value = roll.roll, min = roll.min, max = roll.max }
end

-- The rules of a session for rolls: the range and whether the addon is required (the Priority defaults otherwise).
local function rollRules(s)
	local p = type(s.rules) == "table" and type(s.rules.priority) == "table" and s.rules.priority or {}
	local requireAddon = p.requireAddon
	if requireAddon == nil then requireAddon = true end
	return p.rollMin or RollListener.MIN, p.rollMax or RollListener.MAX, requireAddon
end

local function isValidValue(v, lo, hi)
	return type(v) == "number" and v == floor(v) and v >= lo and v <= hi
end

-- The open round of a session and its item, or nil.
local function openRound(s)
	if type(s) ~= "table" or s.state ~= "ROLLING" or type(s.items) ~= "table" then return nil end
	local item = s.items[s.active]
	if type(item) ~= "table" or type(item.round) ~= "table" then return nil end
	return item.round, item
end

function RollListener.Classify(s, roll, ts)
	local round, item = openRound(s)
	if not round then return "NO_ROUND" end
	local lo, hi, requireAddon = rollRules(s)
	local player = roll.player
	if roll.min ~= lo or roll.max ~= hi then return "NOT_1_100" end
	if not isValidValue(roll.value, lo, hi) then return "BAD_VALUE" end
	if type(ts) == "number" and type(round.openedAt) == "number" and ts < round.openedAt then return "BEFORE_OPEN" end
	if type(ts) == "number" and type(round.closedAt) == "number" and ts > round.closedAt then return "AFTER_CLOSE" end
	if type(item.present) == "table" and item.present[player] ~= true then return "NOT_PRESENT" end
	if requireAddon and type(item.addon) == "table" and item.addon[player] ~= true then return "NO_ADDON" end
	if type(round.among) == "table" and #round.among > 0 then
		local listed = false
		for _, p in ipairs(round.among) do if p == player then listed = true break end end
		if not listed then return "NOT_ELIGIBLE" end
	end
	for _, r in ipairs(type(round.rolls) == "table" and round.rolls or {}) do
		if r.player == player and not r.nb and r.min == lo and r.max == hi and isValidValue(r.value, lo, hi)
			and not (type(r.ts) == "number" and type(round.openedAt) == "number" and r.ts < round.openedAt) then
			return "DUPLICATE"
		end
	end
	return "VALID"
end

local function record(self, entry)
	local log = self.log
	log[#log + 1] = entry
	while #log > self.LOG_SIZE do remove(log, 1) end
	local by = self.stats.byCode
	by[entry.code] = (by[entry.code] or 0) + 1
end

-- Hands a decided roll to the session (`nb`: no click went with it, M7-2d), then logs and announces it.
local function feed(self, entry, nb)
	local stats = self.stats
	if entry.code ~= "NO_ROUND" and self.step then
		local ok, code = self.step({ type = "ROLL", ts = entry.ts, player = entry.player, value = entry.value,
			min = entry.min, max = entry.max, nb = nb or nil })
		if ok then
			stats.fed = stats.fed + 1
		else
			entry.refused = code or "REFUSED"
			stats.refused = stats.refused + 1
		end
	end
	record(self, entry)
	emit("ROLL_SEEN", entry)
end

-- The number of the open round of the active item as the raid knows it (Net/Protocol.lua's SROLL `r`).
local function roundNumber(s)
	local n = type(s.net) == "table" and type(s.net.rounds) == "table" and s.net.rounds[s.active]
	return type(n) == "number" and n or 1
end

-- Is the rule on for this session, and its window (SessionFSM.ButtonRolls)?
local function buttonRule(s)
	local FSM = ns.SessionFSM
	if not FSM or not FSM.ButtonRolls then return false, 10 end
	return FSM.ButtonRolls(s)
end

-- An older client that sends no roll intents (its HELLO, App/AddonCheck.lua).
local function legacy(player)
	local AC = ns.AddonCheck
	local reply = AC and type(AC.replies) == "table" and AC.replies[player]
	return type(reply) == "table" and type(reply.pv) == "number" and reply.pv < RollListener.INTENT_PROTOCOL
end

-- The unused intent of `player` for round (sid, i, r) that may go with a roll read at `ts`, or nil.
local function findIntent(self, player, sid, i, r, ts, window)
	local intent = self.intents[player]
	if type(intent) ~= "table" or intent.used or intent.sid ~= sid or intent.i ~= i or intent.r ~= r then return nil end
	if ts - intent.ts <= window then return intent end
	if self.lockSeenAt and self.lockSeenAt >= intent.ts then return intent end   -- the roll waited out a lockdown
	return nil
end

local function markLock(self, isLocked)
	if isLocked then self.lockSeenAt = C().Now() end
end

-- One readable message that arrived at `ts`.
local function handle(self, text, ts, held)
	local roll = RollListener.Parse(text)
	if not roll then return false end
	local s = self.getSession and self.getSession()
	if type(s) ~= "table" then return false end
	local stats = self.stats
	stats.seen = stats.seen + 1
	local entry = { player = roll.player, value = roll.value, min = roll.min, max = roll.max, ts = ts,
		code = RollListener.Classify(s, roll, ts), held = held or nil }
	if entry.code == "VALID" then
		local on, window = buttonRule(s)
		if on and legacy(roll.player) then
			entry.legacy = true
		elseif on then
			local i, r = s.active, roundNumber(s)
			local intent = findIntent(self, roll.player, s.id, i, r, ts, window)
			if intent then
				intent.used, entry.button = true, true
			else
				-- the intent may still be on its way: the roll waits for it (Expire gives up)
				local waiting = self.waiting
				waiting[#waiting + 1] = { entry = entry, sid = s.id, i = i, r = r, deadline = C().Now() + window,
					window = window }
				stats.waited = stats.waited + 1
				self:EnsureTicker()
				return true
			end
		end
	end
	feed(self, entry)
	return true
end

-- The lockdown that hides the chat: a boss, an active addon restriction or the chat lockdown.
local function locked()
	local Compat = C()
	if Compat.Encounter.InProgress() then return true end
	if Compat.Chat.RestrictionAny() ~= nil then return true end
	return Compat.Chat.InChatLockdown() and true or false
end
RollListener.Locked = locked

local function stopTicker(self)
	if self.ticker then self.ticker:Cancel() self.ticker = nil end
end

-- The one-second recheck runs while hidden messages or rolls waiting for their intent are held.
function RollListener:EnsureTicker()
	if self.ticker or (#self.buffer == 0 and #self.waiting == 0) then return end
	self.ticker = C().NewTicker(self.RECHECK, function()
		self:Flush()
		self:Expire()
	end)
end

local function maybeStop(self)
	if #self.buffer == 0 and #self.waiting == 0 then stopTicker(self) end
end

-- The player's own roll on their own client (M7-2d): typed by hand during an open round of a session with the rule on,
-- it prints a warning. Nothing is blocked: the game's /roll stays the game's.
function RollListener:CheckOwn(text)
	local GR, P = ns.GuildRanks, ns.Protocol
	if not GR or not P or not P.Session or type(text) ~= "string" then return end
	local roll = RollListener.Parse(text)
	if not roll or roll.player ~= GR.Me() or roll.min ~= self.MIN or roll.max ~= self.MAX then return end
	if P.Session:TakeClick() ~= false then return end
	if ns.addon and ns.addon.Print and ns.L then ns.addon:Print(ns.L["POPUP_ROLL_TYPED"]) end
	emit("ROLL_TYPED", roll)
end

function RollListener:OnSystemMessage(text)
	if not C().IsSecret(text) then self:CheckOwn(text) end
	if not self.getSession then return end
	local ts = C().Now()
	if C().IsSecret(text) then
		markLock(self, true)
		local buffer = self.buffer
		buffer[#buffer + 1] = { text = text, ts = ts }
		self.stats.held = self.stats.held + 1
		while #buffer > self.MAX_BUFFER do
			remove(buffer, 1)
			self.stats.dropped = self.stats.dropped + 1
		end
		self:EnsureTicker()
		return
	end
	if type(text) ~= "string" then return end
	handle(self, text, ts)
end

function RollListener:Flush()
	local buffer = self.buffer
	if #buffer == 0 then maybeStop(self) return 0 end
	local isLocked, read, keep = locked(), 0, {}
	markLock(self, isLocked)
	for _, e in ipairs(buffer) do
		if C().IsSecret(e.text) then
			if isLocked then
				keep[#keep + 1] = e
			else
				self.stats.hidden = self.stats.hidden + 1
			end
		elseif type(e.text) == "string" then
			if handle(self, e.text, e.ts, true) then read = read + 1 end
		end
	end
	self.buffer = keep
	maybeStop(self)
	return read
end

-- A roll intent (M7-2d): { player, i, r, n, ts } for the hosted session's open round (Net/Protocol.lua checked the
-- session, the item and the round; the player is the sender). Returns true when it was taken, false for a repeat or a
-- second intent (DUPLICATE).
function RollListener:OnIntent(intent)
	local s = self.getSession and self.getSession()
	if type(s) ~= "table" or type(intent) ~= "table" or type(intent.player) ~= "string" then return false end
	local player = intent.player
	local ts = type(intent.ts) == "number" and intent.ts or C().Now()
	markLock(self, locked())
	local prev = self.intents[player]
	if type(prev) == "table" and prev.sid == s.id and prev.i == intent.i and prev.r == intent.r then
		if prev.n ~= intent.n then
			self.stats.intentDups = self.stats.intentDups + 1
			local by = self.stats.byCode
			by.DUPLICATE_INTENT = (by.DUPLICATE_INTENT or 0) + 1
		end
		return false
	end
	local mine = { sid = s.id, i = intent.i, r = intent.r, n = intent.n, ts = ts }
	self.intents[player] = mine
	self.stats.intents = self.stats.intents + 1
	-- a roll of the same round that came first and waits for it
	local keep, matched = {}, false
	for _, w in ipairs(self.waiting) do
		local e = w.entry
		if e.player == player and w.sid == mine.sid and w.i == mine.i and w.r == mine.r then
			if not matched then
				matched, mine.used, e.button = true, true, true
				feed(self, e)
			else
				-- a second roll of the player in that round: judged again now that the first one counts (DUPLICATE)
				e.code = RollListener.Classify(s, e, e.ts)
				local typed = e.code == "VALID"   -- the first one was refused: this one still has no click of its own
				if typed then e.code = "NOT_FROM_BUTTON" end
				feed(self, e, typed)
			end
		else
			keep[#keep + 1] = w
		end
	end
	self.waiting = keep
	maybeStop(self)
	return true
end

-- Gives up on the rolls whose intent did not come within their window (counted only while there is no lockdown): they
-- go to the session as NOT_FROM_BUTTON. Returns how many were given up.
function RollListener:Expire()
	if #self.waiting == 0 then maybeStop(self) return 0 end
	local t, isLocked = C().Now(), locked()
	markLock(self, isLocked)
	local keep, n = {}, 0
	for _, w in ipairs(self.waiting) do
		if isLocked then
			if w.deadline < t + w.window then w.deadline = t + w.window end   -- the window starts again after the lockdown
			keep[#keep + 1] = w
		elseif t >= w.deadline then
			w.entry.code = "NOT_FROM_BUTTON"
			feed(self, w.entry, true)
			n = n + 1
		else
			keep[#keep + 1] = w
		end
	end
	self.waiting = keep
	maybeStop(self)
	return n
end

function RollListener:Pending() return #self.buffer + #self.waiting end

function RollListener:Stats()
	local s, by = self.stats, {}
	for k, v in pairs(s.byCode) do by[k] = v end
	return { seen = s.seen, fed = s.fed, refused = s.refused, held = s.held, hidden = s.hidden, dropped = s.dropped,
		intents = s.intents, intentDups = s.intentDups, waited = s.waited, byCode = by }
end

function RollListener:Attach(getSession, step)
	if type(getSession) ~= "function" then return nil, "getSession" end
	if step ~= nil and type(step) ~= "function" then return nil, "step" end
	self.getSession, self.step = getSession, step
	return true
end

function RollListener:Detach()
	self.getSession, self.step = nil, nil
	self.buffer, self.waiting, self.intents = {}, {}, {}
	stopTicker(self)
end

-- Tests and /reload: forget everything.
function RollListener:Reset()
	self:Detach()
	self.log, self.stats, self.lockSeenAt = {}, newStats(), nil
end

function RollListener:OnEvent(event, ...)
	if event == "CHAT_MSG_SYSTEM" then
		self:OnSystemMessage((...))
	else   -- ADDON_RESTRICTION_STATE_CHANGED, ENCOUNTER_END, PLAYER_REGEN_ENABLED
		if #self.buffer > 0 then self:Flush() end
		if #self.waiting > 0 then self:Expire() end
	end
end

if ns.Bus then
	ns.Bus:On("ROLL_INTENT", function(_, intent) RollListener:OnIntent(intent) end, RollListener)
end

if ns.addon and CreateFrame then
	ns.addon.RollListener = RollListener   -- also reachable from tests
	local frame = CreateFrame("Frame")
	for _, e in ipairs({ "CHAT_MSG_SYSTEM", "ADDON_RESTRICTION_STATE_CHANGED", "ENCOUNTER_END", "PLAYER_REGEN_ENABLED" }) do
		pcall(frame.RegisterEvent, frame, e)
	end
	frame:SetScript("OnEvent", function(_, event, ...) RollListener:OnEvent(event, ...) end)
end
