-- MasterLoot: the game's side of the delivery of an awarded item (docs/ANALISI.md §4 "Consegna", §11 risk 1; M4-7). Lua 5.1.
--
-- Plan A, master loot: Confirm charges the credits and, in the same click, asks the game to hand the item over
-- (GiveMasterLoot(slot, candidateIndex)); the receipt is the winner's loot message in CHAT_MSG_LOOT. Plan B, when master
-- loot is not available (not the master looter, another loot method, the corpse closed, the winner not on the candidates
-- list, the game refusing the call): the award stays in the ledger and the item changes hands by trade; the addon only
-- watches the trades the player makes and learns who holds an item from the loot messages, it never starts, fills or
-- accepts a trade. Every call goes through Core/Compat.lua (Loot.*, Roll.ParseLoot, Trade.*); the API dump
-- (build 1.60.1.70170) has GiveMasterLoot, GetMasterLootCandidate, GetTradePlayerItemLink, GetTradeTargetItemLink and the
-- events CHAT_MSG_LOOT, TRADE_SHOW, TRADE_ACCEPT_UPDATE, TRADE_CLOSED, UI_INFO_MESSAGE. Whether an addon may call
-- GiveMasterLoot, what the trade events carry exactly and whether CHAT_MSG_LOOT is readable in an instance are spike
-- questions (S2c, S2d, S3e): none of that is verified in the real client.
--
-- The slot of an item can move (the loot window of some clients closes the gap a given item leaves), so the slot the
-- session saw is only a hint: the item is found again in the open loot window by its id before every call.
--
-- MasterLoot.Plan()                          "MASTER", or "TRADE" and the code that says why master loot is out
-- MasterLoot.FindSlot(itemID, hint)          the slot holding the item in the open loot window, or nil and NO_WINDOW / NO_SLOT
-- MasterLoot.FindCandidate(slot, name)       the candidate index of a player ("Name-Realm"), or nil and NO_CANDIDATE
-- MasterLoot.Give(itemID, hint, recipient)   true and the slot when the game was asked; nil and a DELIVERY code otherwise
--                                            (NO_MASTER_LOOT, NO_WINDOW, NO_SLOT, NO_CANDIDATE, CALL_FAILED)
-- MasterLoot.ParseReceipt(text)              { player ("Name-Realm"), itemID, link, count } of a loot message, or nil
-- MasterLoot.Holder(itemID, since, claim)    who received the item (a loot message after `since`), nil when nobody was seen
-- Bus events: "LOOT_RECEIVED"(entry { player, itemID, link, count, at, claimed? }) for every readable loot message of
--             an item; "TRADE_COMPLETED"(info { partner, gave = { itemID... }, got = { itemID... } }) when a trade of this
--             client went through.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local MasterLoot = { recent = {}, stats = { seen = 0, hidden = 0 } }
ns.MasterLoot, ns.modules.MasterLoot = MasterLoot, MasterLoot

local type, ipairs, remove = type, ipairs, table.remove

MasterLoot.RECENT = 60   -- loot messages kept to learn who holds an item

local function C() return ns.Compat end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function idOf(link) return ns.ItemCache and ns.ItemCache.IdFromLink(link) or nil end

local function fullName(name)
	if type(name) ~= "string" or name == "" then return nil end
	local GR = ns.GuildRanks
	return GR and GR.FullName(name) or name
end

---------------------------------------------------------------------------------------------------------------------
-- Master loot

-- "MASTER" when this client is the master looter of a master loot group; otherwise "TRADE" and NO_MASTER_LOOT.
function MasterLoot.Plan()
	local Loot = C().Loot
	if Loot.IsMasterLooter() and Loot.IsMasterLootMethod() then return "MASTER" end
	return "TRADE", "NO_MASTER_LOOT"
end

-- The slot of the open loot window that holds the item: the hint when it still does, else the first that does.
function MasterLoot.FindSlot(itemID, hint)
	local Loot = C().Loot
	if Loot.NumItems() == 0 then return nil, "NO_WINDOW" end
	local found
	for _, s in ipairs(Loot.Slots()) do
		if s.hasItem ~= false and idOf(s.link) == itemID then
			if s.slot == hint then return s.slot end
			found = found or s.slot
		end
	end
	if found then return found end
	return nil, "NO_SLOT"
end

-- The candidate index (what GiveMasterLoot takes) of a player in the slot's list.
function MasterLoot.FindCandidate(slot, name)
	local target = fullName(name)
	if target then
		for _, c in ipairs(C().Loot.Candidates(slot)) do
			if fullName(c.name) == target then return c.index end
		end
	end
	return nil, "NO_CANDIDATE"
end

function MasterLoot.Give(itemID, hint, recipient)
	local plan, code = MasterLoot.Plan()
	if plan ~= "MASTER" then return nil, code end
	local slot, why = MasterLoot.FindSlot(itemID, hint)
	if not slot then return nil, why end
	local index, notFound = MasterLoot.FindCandidate(slot, recipient)
	if not index then return nil, notFound end
	local state = C().Loot.Give(slot, index)
	if state ~= C().AVAILABLE then
		return nil, state == C().MISSING and "NO_MASTER_LOOT" or "CALL_FAILED"
	end
	return true, slot
end

---------------------------------------------------------------------------------------------------------------------
-- Loot messages: the receipt, and who holds an item

function MasterLoot.ParseReceipt(text)
	local r, why = C().Roll.ParseLoot(text)
	if not r then return nil, why end
	local id = idOf(r.link)
	if not id then return nil end
	local player = r.player and fullName(r.player) or (ns.GuildRanks and ns.GuildRanks.Me()) or nil
	if not player then return nil end
	return { player = player, itemID = id, link = r.link, count = r.count or 1 }
end

function MasterLoot:OnLootMessage(text)
	local entry, why = MasterLoot.ParseReceipt(text)
	if not entry then
		if why == "secret" then self.stats.hidden = self.stats.hidden + 1 end
		return nil
	end
	self.stats.seen = self.stats.seen + 1
	entry.at = C().Now()
	local recent = self.recent
	recent[#recent + 1] = entry
	while #recent > self.RECENT do remove(recent, 1) end
	emit("LOOT_RECEIVED", entry)
	return entry
end

-- Who received the item in a loot message after `since` (the newest not yet claimed). `claim` marks the message as used.
function MasterLoot.Holder(itemID, since, claim)
	local recent = MasterLoot.recent
	for i = #recent, 1, -1 do
		local e = recent[i]
		if e.itemID == itemID and not e.claimed and (since == nil or e.at >= since) then
			if claim then e.claimed = true end
			return e.player
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- The trade window: what the player gave and got, once the trade went through

local function snapshot(trade)
	local Trade = C().Trade
	trade.partner = trade.partner or fullName(Trade.Partner())
	local gave, got = {}, {}
	for _, link in ipairs(Trade.PlayerItems()) do gave[#gave + 1] = idOf(link) end
	for _, link in ipairs(Trade.TargetItems()) do got[#got + 1] = idOf(link) end
	trade.gave, trade.got = gave, got
end

-- The events of a trade, in order: TRADE_SHOW, item changes, TRADE_ACCEPT_UPDATE, [UI_INFO_MESSAGE complete],
-- TRADE_CLOSED. The items are read while the window is open (they are gone once the trade goes through); a trade counts
-- when both sides had accepted or the client said it was complete [verify S2d: the order of the last two events].
function MasterLoot:OnTradeEvent(event, ...)
	if event == "TRADE_SHOW" then
		self.trade = { agreed = false }
		snapshot(self.trade)
		return
	end
	if event == "TRADE_CLOSED" then
		local trade = self.trade
		self.trade = nil
		if trade and (trade.agreed or trade.complete) and trade.partner and (#trade.gave + #trade.got) > 0 then
			emit("TRADE_COMPLETED", { partner = trade.partner, gave = trade.gave, got = trade.got })
			return true
		end
		return
	end
	if event == "UI_INFO_MESSAGE" then
		local _, message = ...
		if self.trade and C().Trade.IsCompleteMessage(message) then self.trade.complete = true end
		return
	end
	local trade = self.trade
	if not trade then
		trade = { agreed = false }   -- a window opened before the addon looked: start from what is there
		self.trade = trade
	end
	if trade.agreed then return end
	snapshot(trade)
	if event == "TRADE_ACCEPT_UPDATE" then
		local playerAccepted, targetAccepted = ...
		trade.agreed = playerAccepted == 1 and targetAccepted == 1
	end
end

function MasterLoot:Reset()
	self.recent, self.trade = {}, nil
	self.stats = { seen = 0, hidden = 0 }
end

function MasterLoot:OnEvent(event, ...)
	if event == "CHAT_MSG_LOOT" then
		self:OnLootMessage((...))
	else
		self:OnTradeEvent(event, ...)
	end
end

if ns.addon and CreateFrame then
	ns.addon.MasterLoot = MasterLoot   -- also reachable from tests
	local frame = CreateFrame("Frame")
	for _, e in ipairs({ "CHAT_MSG_LOOT", "TRADE_SHOW", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED",
		"TRADE_ACCEPT_UPDATE", "TRADE_CLOSED", "UI_INFO_MESSAGE" }) do
		pcall(frame.RegisterEvent, frame, e)
	end
	frame:SetScript("OnEvent", function(_, event, ...) MasterLoot:OnEvent(event, ...) end)
end
