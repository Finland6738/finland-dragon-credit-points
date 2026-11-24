-- ReadinessNotifier: the notify button of the readiness tab (docs/ANALISI.md §4.2, ADR 0010, M8-3). Lua 5.1. The words and the
-- grouping are Domain/ReadinessNotice.lua's, the rows App/ReadinessCheck.lua's, the permission and the cooldown follow the
-- notice of the addon check (App/AddonNotice.lua, M3-6).
--
-- Send() is called by a click of someone `ReadinessCheck:CanManage()` allows (the tab asks for a confirmation first), never by
-- itself. It writes one short summary in /raid (the counts and the names grouped by what they lack) and one whisper to each
-- raider whose row is MISSING or WARN, listing what and where, in the language of the player who clicked and with the
-- guild's wording when the rules carry one (`readiness.texts`). Nothing is written to the ledger.
--
-- The messages leave one by one (PACE seconds apart: forty whispers in a row would be dropped by the chat) and never during
-- a boss fight or the chat lockdown: when the click comes then, the messages wait in a queue and leave after it (an
-- encounter end, or the next retry), unless they are older than QUEUE_MAX seconds. At most one notice every `notice.minutes`
-- minutes (the guild's M3-6 setting); the wait starts at the click and is cleared when a night opens.
-- Refused: "NOT_IN_RAID", a permission code, "NO_CHECK" (nobody asked the raid yet), "NOBODY" (nobody lacks anything that
-- was read), "THROTTLED" (plus the seconds left), "BUSY" (a notice is still leaving), "SEND_FAILED" (the game refused the
-- first message).
-- Every notice is logged (who, when, how many messages, how many left, whether it waited) in the character's data, in the
-- debug log and on the bus ("READINESS_NOTICE_SENT"); the log of a message holds its channel and size, never a name.
-- Not verified in the real client: SendChatMessage to RAID and WHISPER from a click, 40 whispers in a row, the queue.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Notifier = {}
ns.ReadinessNotifier, ns.modules.ReadinessNotifier = Notifier, Notifier

local type, ipairs, tostring = type, ipairs, tostring

Notifier.HISTORY_MAX = 30
Notifier.PACE = 0.4         -- seconds between two messages
Notifier.RETRY = 2          -- seconds between two looks at a blocked chat
Notifier.QUEUE_MAX = 600    -- a queued notice older than this is dropped (the table it described is stale)
Notifier.lastAt = nil       -- when the last notice was accepted
Notifier.queue = nil        -- { messages = { { text, chatType, target } }, at, entry } while a notice is leaving

local function log(level, code, ...) if ns.Log then ns.Log[level]("ReadinessNotifier", code, ...) end end
local function now() return ns.Compat.Now() end
local function L() return ns.L end
local function RC() return ns.ReadinessCheck end

function Notifier:Reset()
	self.lastAt, self.queue = nil, nil
end

-- The wording in the player's language: the locale keys the Domain module fills.
-- locale-key: READY_NOTICE_RAID READY_NOTICE_RAID_UNKNOWN READY_NOTICE_WHISPER READY_NOTICE_GROUP READY_PART_ENCHANT READY_PART_ITEM
function Notifier:Words()
	local l = L()
	return {
		raid = l["READY_NOTICE_RAID"], raidUnknown = l["READY_NOTICE_RAID_UNKNOWN"], whisper = l["READY_NOTICE_WHISPER"],
		group = l["READY_NOTICE_GROUP"], enchant = l["READY_PART_ENCHANT"], item = l["READY_PART_ITEM"],
		slot = function(n) return l["READY_SLOT_" .. tostring(n)] end,
		cat = function(code) return l["READY_CAT_" .. tostring(code)] end,
	}
end

-- The guild's wording (`readiness.texts` of the rules in force).
function Notifier:Texts()
	local rules = RC():Rules()
	return rules and rules.texts or nil
end

-- The notice the table would write now: { raid, whispers, counts }, or nil and a code ("NOBODY").
function Notifier:Preview()
	return ns.ReadinessNotice.Plan(RC():Rows(), self:Words(), self:Texts(), ns.GuildRanks and ns.GuildRanks.Me() or nil)
end

-- The minutes between two notices: the guild's `notice.minutes` (the rules' M3-6 section).
function Notifier:Minutes()
	local cfg = ns.AddonNotice and ns.AddonNotice:Config()
	return cfg and cfg.minutes or 5
end

-- Seconds before the next notice may leave (0 = now).
function Notifier:Wait()
	local minutes = self:Minutes()
	if not self.lastAt or minutes <= 0 then return 0 end
	local left = self.lastAt + minutes * 60 - now()
	return left > 0 and left or 0
end

-- true while a notice is still leaving (or waiting for the chat).
function Notifier:Busy() return self.queue ~= nil end

---------------------------------------------------------------------------------------------------------------------
-- The log

local function history()
	local c = ns.Config and ns.Config.char
	if type(c) ~= "table" then return nil end
	c.readinessNotices = type(c.readinessNotices) == "table" and c.readinessNotices or {}
	return c.readinessNotices
end

-- The logged notices, oldest first: { ts, by, raid, whispers, names, sent, failed, queued, expired }.
function Notifier:History() return history() or {} end

local function record(self, entry)
	local h = history()
	if h and not (ns.Config and ns.Config:IsReadOnly()) then
		h[#h + 1] = entry
		while #h > self.HISTORY_MAX do table.remove(h, 1) end
	end
	log("info", "NOTICE", entry.raid, entry.whispers, entry.sent, entry.failed, entry.queued and 1 or 0, entry.expired and 1 or 0)
	if ns.Bus then ns.Bus:Emit("READINESS_NOTICE_SENT", entry) end
	return entry
end

---------------------------------------------------------------------------------------------------------------------
-- Leaving

local function blocked()
	local Compat = ns.Compat
	return Compat.Encounter.InProgress() or not Compat.Chat.CanSend()
end

local function finish(self, expired)
	local q = self.queue
	if not q then return end
	self.queue = nil
	q.entry.expired = expired or nil
	record(self, q.entry)
end

local function schedule(self, seconds)
	local q = self.queue
	if not q or q.timer then return end
	q.timer = true
	ns.Compat.After(seconds, function()
		if self.queue == q then
			q.timer = nil
			self:Pump()
		end
	end)
end

-- Writes the next message when the chat is free; otherwise looks again later. Called by Send, by the timer and when a
-- boss fight ends.
function Notifier:Pump()
	local q = self.queue
	if not q then return end
	if #q.messages == 0 then finish(self); return end
	if now() - q.at > self.QUEUE_MAX then finish(self, true); return end
	if blocked() then
		q.entry.queued = true
		schedule(self, self.RETRY)
		return
	end
	local msg = table.remove(q.messages, 1)
	if ns.Compat.Chat.Send(msg.text, msg.chatType, msg.target) then
		q.entry.sent = q.entry.sent + 1
		log("info", "SEND", ns.Log and ns.Log.Plain(msg.chatType), #msg.text)
	else
		q.entry.failed = q.entry.failed + 1
		log("warn", "SEND_FAILED", ns.Log and ns.Log.Plain(msg.chatType))
	end
	if #q.messages == 0 then finish(self) else schedule(self, self.PACE) end
end

-- Would a notice leave now? Returns the plan the table gives ({ raid, whispers, counts }), or nil, a code (see the top of the
-- file) and, for "THROTTLED", the seconds left. The tab asks this before it asks the player to confirm.
function Notifier:Check()
	local check = RC()
	local raid = ns.AddonCheck and ns.AddonCheck.raid
	if not raid or not raid.inRaid then return nil, "NOT_IN_RAID" end
	local ok, code = check:CanManage()
	if not ok then return nil, code end
	if self:Busy() then return nil, "BUSY" end
	if not check.request then return nil, "NO_CHECK" end
	local plan, why = self:Preview()
	if not plan then return nil, why end
	local wait = self:Wait()
	if wait > 0 then return nil, "THROTTLED", wait end
	return plan
end

-- Writes the notice. Returns the log entry (a table, `queued` when the chat made it wait), or nil and a code (see Check),
-- plus the seconds left for "THROTTLED". A notice that waits for the chat is logged when it ends.
function Notifier:Send()
	local plan, code, extra = self:Check()
	if not plan then return nil, code, extra end
	local messages = {}
	for _, line in ipairs(plan.raid) do messages[#messages + 1] = { text = line, chatType = "RAID" } end
	for _, w in ipairs(plan.whispers) do
		for _, line in ipairs(w.lines) do messages[#messages + 1] = { text = line, chatType = "WHISPER", target = w.name } end
	end
	local names = {}
	for _, w in ipairs(plan.whispers) do names[#names + 1] = w.name end
	local entry = { ts = ns.Compat.ServerTime(), by = ns.GuildRanks and ns.GuildRanks.Me() or nil, raid = #plan.raid,
		whispers = #plan.whispers, names = names, sent = 0, failed = 0 }
	self.queue = { messages = messages, at = now(), entry = entry }
	self.lastAt = now()
	self:Pump()
	if entry.sent == 0 and entry.failed > 0 then
		-- the game refused the very first message: nothing left, the click is not spent
		self.queue, self.lastAt = nil, nil
		return nil, "SEND_FAILED"
	end
	return entry
end

if ns.Bus then
	ns.Bus:On("NIGHT_OPENED", function() Notifier:Reset() end, Notifier)
	ns.Bus:On("ENCOUNTER_ENDED", function() Notifier:Pump() end, Notifier)
	ns.Bus:On("GROUP_SCANNED", function(_, snapshot)
		if type(snapshot) == "table" and not snapshot.inRaid and Notifier.queue then finish(Notifier, true) end
	end, Notifier)
end
if ns.addon then ns.addon.ReadinessNotifier = Notifier end   -- also reachable from tests
