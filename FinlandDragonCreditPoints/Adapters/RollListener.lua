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
-- The order of the checks is the one of Priority (a roll with another range does not make a later one a duplicate).
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
-- RollListener:Pending()                   how many hidden messages wait (the controller does not close a round while
--                                            rolls may still be held)
-- RollListener:Stats()                     { seen, fed, refused, held, hidden, dropped, byCode = { [code] = n } }
-- RollListener.log                         the last LOG_SIZE entries { player, value, min, max, ts, code, refused?, held? }
--                                            (held: read after the lockdown)
-- Bus event: "ROLL_SEEN"(entry) for every roll read while a session is attached.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local RollListener = { log = {}, buffer = {} }
ns.RollListener, ns.modules.RollListener = RollListener, RollListener

local type, ipairs, pairs, floor, remove = type, ipairs, pairs, math.floor, table.remove

RollListener.LOG_SIZE = 200      -- rolls kept for the window and the debug output
RollListener.MAX_BUFFER = 200    -- hidden messages held during one lockdown (the oldest go first)
RollListener.RECHECK = 1         -- seconds between two reads of the buffer while it is not empty
RollListener.MIN, RollListener.MAX = 1, 100

local function C() return ns.Compat end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

local function newStats() return { seen = 0, fed = 0, refused = 0, held = 0, hidden = 0, dropped = 0, byCode = {} } end
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
		if r.player == player and r.min == lo and r.max == hi and isValidValue(r.value, lo, hi)
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
	if entry.code ~= "NO_ROUND" and self.step then
		local ok, code = self.step({ type = "ROLL", ts = ts, player = roll.player, value = roll.value, min = roll.min,
			max = roll.max })
		if ok then
			stats.fed = stats.fed + 1
		else
			entry.refused = code or "REFUSED"
			stats.refused = stats.refused + 1
		end
	end
	record(self, entry)
	emit("ROLL_SEEN", entry)
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

local function ensureTicker(self)
	if self.ticker or #self.buffer == 0 then return end
	self.ticker = C().NewTicker(self.RECHECK, function() self:Flush() end)
end

function RollListener:OnSystemMessage(text)
	if not self.getSession then return end
	local ts = C().Now()
	if C().IsSecret(text) then
		local buffer = self.buffer
		buffer[#buffer + 1] = { text = text, ts = ts }
		self.stats.held = self.stats.held + 1
		while #buffer > self.MAX_BUFFER do
			remove(buffer, 1)
			self.stats.dropped = self.stats.dropped + 1
		end
		ensureTicker(self)
		return
	end
	if type(text) ~= "string" then return end
	handle(self, text, ts)
end

function RollListener:Flush()
	local buffer = self.buffer
	if #buffer == 0 then stopTicker(self) return 0 end
	local isLocked, read, keep = locked(), 0, {}
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
	if #keep == 0 then stopTicker(self) end
	return read
end

function RollListener:Pending() return #self.buffer end

function RollListener:Stats()
	local s, by = self.stats, {}
	for k, v in pairs(s.byCode) do by[k] = v end
	return { seen = s.seen, fed = s.fed, refused = s.refused, held = s.held, hidden = s.hidden, dropped = s.dropped,
		byCode = by }
end

function RollListener:Attach(getSession, step)
	if type(getSession) ~= "function" then return nil, "getSession" end
	if step ~= nil and type(step) ~= "function" then return nil, "step" end
	self.getSession, self.step = getSession, step
	return true
end

function RollListener:Detach()
	self.getSession, self.step = nil, nil
	self.buffer = {}
	stopTicker(self)
end

-- Tests and /reload: forget everything.
function RollListener:Reset()
	self:Detach()
	self.log, self.stats = {}, newStats()
end

function RollListener:OnEvent(event, ...)
	if event == "CHAT_MSG_SYSTEM" then
		self:OnSystemMessage((...))
	elseif #self.buffer > 0 then   -- ADDON_RESTRICTION_STATE_CHANGED, ENCOUNTER_END, PLAYER_REGEN_ENABLED
		self:Flush()
	end
end

if ns.addon and CreateFrame then
	ns.addon.RollListener = RollListener   -- also reachable from tests
	local frame = CreateFrame("Frame")
	for _, e in ipairs({ "CHAT_MSG_SYSTEM", "ADDON_RESTRICTION_STATE_CHANGED", "ENCOUNTER_END", "PLAYER_REGEN_ENABLED" }) do
		pcall(frame.RegisterEvent, frame, e)
	end
	frame:SetScript("OnEvent", function(_, event, ...) RollListener:OnEvent(event, ...) end)
end
