-- Announcer: what the master looter's client writes in /raid during a loot session (docs/ANALISI.md §4, §8.5; M4-8).
-- Lua 5.1. The texts and the splitting are Domain/Announce.lua (and Domain/Notice.lua for the tag and the 255 limit); the
-- guild's wording is the rules' section "announce" (only the Guild Master changes it: SaveConfig); the reason sentence is
-- composed from the reason codes (Domain/Reasons.lua). Everything is written in the GUILD language (Locale.GuildLanguage),
-- whatever language the master looter's client speaks, so the raid reads one language.
--
-- It listens to the session controller (Bus "SESSION_CHANGED"(session, effects)) and writes:
--   ANNOUNCE_ITEMS  (the session starts)        one line per item: link, category, cost. The guild rule: the category is
--                                               announced before the roll, and the first roll opens after this effect
--   ITEM_CORRECTED  (after the session started) one line: the item's new category and cost
--   AWARDED         (the ML confirmed)          one line: item, winner (or bank / disenchant), cost, reason sentence
-- Lines wait in a queue and go out through Flush(): never while a boss fight runs (Compat.Encounter), only when the
-- chat accepts them (Compat.Chat.CanSend: no lockdown, no addon restriction), a few per second, in order. A line that
-- cannot go out yet stays queued; the ticker of one second retries until the queue is empty. Outside a raid group nothing
-- is written (the popups and the window carry the same news). A line the game refuses five times in a row is dropped.
-- Bus events: "ANNOUNCE_SENT"(line), "ANNOUNCE_DROPPED"(count, code), "ANNOUNCE_CONFIG"(section).
-- Not verified in the real client: SendChatMessage to RAID from the master looter's click (the START and CONFIRM clicks)
-- and from the automatic award (no click), the chat lockdown around a boss.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Announcer = {}
ns.Announcer, ns.modules.Announcer = Announcer, Announcer

local type, ipairs, tostring = type, ipairs, tostring

Announcer.QUEUE_MAX = 60   -- lines waiting at most (a session of 20 items fits)
Announcer.BURST = 4        -- lines per flush: the chat throttles a longer burst
Announcer.MAX_FAILS = 5
Announcer.queue = {}
Announcer.fails = 0

local function log(level, code, ...) if ns.Log then ns.Log[level]("Announcer", code, ...) end end
local function Compat() return ns.Compat end

function Announcer:Reset()
	self.queue, self.fails = {}, 0
	self:Disarm()
end

-- The rules' section "announce" in force (the defaults without a ledger).
function Announcer:Config()
	local ledger = ns.NightController and ns.NightController:Ledger()   -- the guild's ledger, as the notice reads it
	local rules = ledger and ns.Rules.Current(ledger) or ns.Rules.DefaultConfig()
	return rules.announce
end

local function lang() return ns.Locale.GuildLanguage() end
local function text(key, ...)
	local s = ns.Locale.Text(lang(), key)
	if select("#", ...) > 0 then return s:format(...) end
	return s
end

---------------------------------------------------------------------------------------------------------------------
-- The words

-- The item as chat writes it: its link when the client knows the item, else "item #id" in the guild language.
-- locale-key: ANNOUNCE_ITEM_UNKNOWN
local function itemLink(itemID)
	local entry = ns.ItemCache and ns.ItemCache.Lookup(itemID)
	if entry and entry.link then return entry.link end
	return text("ANNOUNCE_ITEM_UNKNOWN", itemID)
end

-- locale-key: ML_CAT_WEAPON ML_CAT_OFFHAND ML_CAT_TRINKET ML_CAT_QUEST ML_CAT_JEWELRY ML_CAT_ARMOR ML_CAT_COSMETIC ML_CAT_OTHER
local function categoryName(category)
	return text("ML_CAT_" .. tostring(category):upper())
end

-- The response whose cost is the item's price: the lowest tier (main-spec in the preset), as the FSM prices a "full cost".
local function fullCost(session, item)
	local tiers = session.rules and session.rules.priority and session.rules.priority.responses
	local best, bestTier
	for code, r in pairs(type(tiers) == "table" and tiers or {}) do
		if type(r) == "table" and type(r.tier) == "number" and item.costs and item.costs[code] ~= nil
			and (bestTier == nil or r.tier < bestTier or (r.tier == bestTier and code < best)) then
			best, bestTier = code, r.tier
		end
	end
	if best then return item.costs[best] end
	return nil
end

-- locale-key: ANNOUNCE_COST_FREE ANNOUNCE_COST_ONE ANNOUNCE_COST_MANY ANNOUNCE_COST_COUNCIL
local function costPhrase(cost, council)
	local texts = { free = text("ANNOUNCE_COST_FREE"), one = text("ANNOUNCE_COST_ONE"), many = text("ANNOUNCE_COST_MANY"),
		council = text("ANNOUNCE_COST_COUNCIL") }
	local number = cost and ns.Locale.FormatNumber(cost, 2, lang()) or ""
	return ns.Announce.CostText(texts, cost, number, council)
end

-- The reason sentence of a proposal: the sentences of its reason codes, in the guild language.
local function reasonSentence(reasons)
	local out = {}
	for _, code in ipairs(reasons or {}) do out[#out + 1] = ns.Reasons.Text("REASON", code, lang()) end
	return table.concat(out, " ")
end

-- The lines announcing item `index` of `session` (a list, possibly empty). `corrected` writes the correction wording.
-- locale-key: ANNOUNCE_ITEM ANNOUNCE_CORRECTED
function Announcer:ItemLines(session, index, corrected)
	local item = session.items[index]
	if not item then return {} end
	local cfg = self:Config()
	local default = text(corrected and "ANNOUNCE_CORRECTED" or "ANNOUNCE_ITEM")
	local template = corrected and default or ns.Announce.Template(cfg, "ITEM", default)
	return ns.Announce.Lines(ns.Announce.Fill(template, {
		item = itemLink(item.itemID), category = categoryName(item.category),
		cost = costPhrase(fullCost(session, item), item.council),
	}))
end

-- The lines announcing the result of item `index` (an AWARDED effect `e`).
-- locale-key: ANNOUNCE_RESULT ANNOUNCE_RESULT_BANK ANNOUNCE_RESULT_DISENCHANT
function Announcer:ResultLines(session, index, e)
	local item = session.items[index]
	if not item then return {} end
	local cfg = self:Config()
	local reason = ""
	if cfg.reason and item.proposal then reason = reasonSentence(item.proposal.reasons) end
	local default, kind = text("ANNOUNCE_RESULT"), "RESULT"
	local target = e and e.target
	if target == "bank" then
		default, kind = text("ANNOUNCE_RESULT_BANK"), nil
	elseif target == "disenchant" then
		default, kind = text("ANNOUNCE_RESULT_DISENCHANT"), nil
	end
	local template = kind and ns.Announce.Template(cfg, kind, default) or default
	return ns.Announce.Lines(ns.Announce.Fill(template, {
		item = itemLink(item.itemID), category = categoryName(item.category),
		winner = ns.Notice.ShortName(e and e.winner or "?"), cost = costPhrase(e and e.cost, false), reason = reason,
	}))
end

---------------------------------------------------------------------------------------------------------------------
-- The queue

function Announcer:Pending() return #self.queue end

function Announcer:Enqueue(lines)
	for _, line in ipairs(lines) do
		if #self.queue >= self.QUEUE_MAX then
			log("warn", "QUEUE_FULL")
			if ns.Bus then ns.Bus:Emit("ANNOUNCE_DROPPED", 1, "QUEUE_FULL") end
			break
		end
		self.queue[#self.queue + 1] = line
	end
	self:Flush()
end

function Announcer:Arm()
	if self.ticker then return end
	self.ticker = Compat().NewTicker(1, function() self:Flush() end)
end

function Announcer:Disarm()
	if self.ticker then self.ticker:Cancel() end
	self.ticker = nil
end

-- Writes the lines that may go out now. Returns the number written, or 0 and the reason it waited: "DISABLED" (the queue
-- is emptied), "NOT_IN_RAID" (emptied), "ENCOUNTER", "CHAT_BLOCKED" (kept for the ticker), "SEND_FAILED".
function Announcer:Flush()
	if #self.queue == 0 then self:Disarm(); return 0 end
	if not self:Config().enabled then self.queue = {}; self:Disarm(); return 0, "DISABLED" end
	local C = Compat()
	if not C.Group.InRaid() then self.queue = {}; self:Disarm(); return 0, "NOT_IN_RAID" end
	if C.Encounter.InProgress() then self:Arm(); return 0, "ENCOUNTER" end
	if not C.Chat.CanSend() then self:Arm(); return 0, "CHAT_BLOCKED" end
	local sent = 0
	while #self.queue > 0 and sent < self.BURST do
		local line = self.queue[1]
		if C.Chat.Send(line, "RAID") then
			table.remove(self.queue, 1)
			self.fails = 0
			sent = sent + 1
			if ns.Bus then ns.Bus:Emit("ANNOUNCE_SENT", line) end
		else
			self.fails = self.fails + 1
			if self.fails >= self.MAX_FAILS then
				log("warn", "DROPPED", #self.queue)
				if ns.Bus then ns.Bus:Emit("ANNOUNCE_DROPPED", #self.queue, "SEND_FAILED") end
				self.queue, self.fails = {}, 0
			end
			self:Arm()
			return sent, "SEND_FAILED"
		end
	end
	if #self.queue > 0 then self:Arm() else self:Disarm() end
	return sent
end

---------------------------------------------------------------------------------------------------------------------
-- The session

-- The effects of an accepted input of the hosted session.
function Announcer:OnSession(session, effects)
	if type(session) ~= "table" or type(effects) ~= "table" then return end
	if not self:Config().enabled then return end
	for _, e in ipairs(effects) do
		if e.type == "ANNOUNCE_ITEMS" then
			for _, entry in ipairs(e.items or {}) do self:Enqueue(self:ItemLines(session, entry.item)) end
		elseif e.type == "ITEM_CORRECTED" and session.startedAt ~= nil then
			self:Enqueue(self:ItemLines(session, e.item, true))
		elseif e.type == "AWARDED" then
			self:Enqueue(self:ResultLines(session, e.item, e))
		end
	end
end

-- The Guild Master edits the wording: `fields` is a table with some of enabled, itemText, resultText, reason. Returns true,
-- or nil and a code (App/AddonNotice.lua SaveSection; the field problem reads "ANNOUNCE:<field>").
function Announcer:SaveConfig(fields)
	local ok, section = ns.AddonNotice.SaveSection("announce", ns.Announce.ValidateConfig, fields)
	if not ok then return nil, section end
	if ns.Bus then ns.Bus:Emit("ANNOUNCE_CONFIG", section) end
	return true
end

if ns.Bus then
	ns.Bus:On("SESSION_CHANGED", function(_, session, effects) Announcer:OnSession(session, effects) end, Announcer)
end
if ns.addon then ns.addon.Announcer = Announcer end   -- also reachable from tests
