-- Mock client, part 8b: the trade window (M4-7).
--
-- Imitates: GetTradePlayerItemLink, GetTradeTargetItemLink, the "NPC" unit of UnitName (the trade frame's own source of
-- the other player's name), the string ERR_TRADE_COMPLETE and the events TRADE_SHOW, TRADE_PLAYER_ITEM_CHANGED,
-- TRADE_TARGET_ITEM_CHANGED, TRADE_ACCEPT_UPDATE, TRADE_CLOSED, UI_INFO_MESSAGE.
-- Dump files: ../WoW-Addons/docs/api/Auction-Mail-Trade (the trade functions); the events and the string are checked by
-- name against api.json when the dump is there (ERR_TRADE_COMPLETE is a global string: not in the dump).
--
--   Mock.trade.Open(name, realm)      the trade window opens with that player (TRADE_SHOW)
--   Mock.trade.Put("player" | "target", link)   an item goes into the next free slot of that side
--   Mock.trade.Accept(playerAccepted, targetAccepted)   TRADE_ACCEPT_UPDATE(0/1, 0/1)
--   Mock.trade.Finish()               both accept and the trade goes through: UI_INFO_MESSAGE(ERR_TRADE_COMPLETE), then
--                                     the window closes (TRADE_CLOSED) with the items on their way
--   Mock.trade.Cancel()               the window closes without a trade (TRADE_CLOSED)
--   Mock.trade.done                   { { partner, gave = { link... }, got = { link... } } } the trades that went through
local Mock, H = ...
local W = Mock.world

ERR_TRADE_COMPLETE = "Trade complete."

W.trade = W.trade or { open = false, partner = nil, realm = nil, player = {}, target = {}, done = {} }
local trade = W.trade
Mock.trade = trade
trade.done = trade.done or {}

local function reset()
	trade.open, trade.partner, trade.realm, trade.player, trade.target = false, nil, nil, {}, {}
end

function trade.Open(name, realm)
	trade.open, trade.partner, trade.realm, trade.player, trade.target = true, name, realm, {}, {}
	Mock.Fire("TRADE_SHOW")
end

function trade.Put(side, link)
	local list = side == "player" and trade.player or trade.target
	list[#list + 1] = link
	Mock.Fire(side == "player" and "TRADE_PLAYER_ITEM_CHANGED" or "TRADE_TARGET_ITEM_CHANGED", #list)
end

function trade.Accept(playerAccepted, targetAccepted)
	Mock.Fire("TRADE_ACCEPT_UPDATE", playerAccepted or 0, targetAccepted or 0)
end

function trade.Finish()
	Mock.Fire("TRADE_ACCEPT_UPDATE", 1, 1)
	trade.done[#trade.done + 1] = { partner = trade.partner, gave = trade.player, got = trade.target }
	Mock.Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
	reset()
	Mock.Fire("TRADE_CLOSED")
end

function trade.Cancel()
	reset()
	Mock.Fire("TRADE_CLOSED")
end

function GetTradePlayerItemLink(slot) return trade.open and trade.player[slot] or nil end
function GetTradeTargetItemLink(slot) return trade.open and trade.target[slot] or nil end

local unitName = UnitName
function UnitName(unit)
	if unit == "NPC" or unit == "npc" then
		if trade.open then return trade.partner, trade.realm end
		return nil
	end
	return unitName(unit)
end
