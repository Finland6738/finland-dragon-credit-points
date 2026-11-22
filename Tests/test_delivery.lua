-- Delivery (M4-7): Adapters/MasterLoot.lua and the delivery part of App/SessionController.lua on the mock client. Confirm
-- charges the credits and hands the item over in the same click: by master loot (GiveMasterLoot, the receipt is the
-- winner's loot message), or, when master loot is out (not the master looter, another loot method, the corpse closed,
-- the winner not on the candidates list), by trade, with the "to deliver" list of the master looter's window; an
-- undelivered item outlives its session (docs/ANALISI.md §4 "Consegna rimandata", §11 risk 1).
local function SC() return FDCP.SessionController end
local function Lg() return FDCP.Ledger end
local function Codec() return FDCP.Codec end
local function PS() return FDCP.Protocol.Session end
local function F() return FDCP.SessionFSM end
local function ML() return FDCP.MasterLoot end
local function W() return FDCP.MLSession end
local function MW() return FDCP.MainWindow end
local function L(key) return FDCP.L[key] end

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end
local MASTER = full("Dara")
local PLAYERS = { "Aurel", "Bryn", "Corin", "Dara" }
local BOSS_GUID = "Creature-0-3-2000-1-11502-0000A1B2C3"

local function link(id) return "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[Item " .. id .. "]|h|r" end

local ITEMS = {
	{ id = 19003, name = "Ring", equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0 },
	{ id = 19001, name = "Shoulders", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 4 },
	{ id = 19002, name = "Sword", equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7 },
}

local function setup(M)
	M.player.name, M.player.realm = "Dara", REALM
	for _, def in ipairs(ITEMS) do
		M.items.Add{ id = def.id, link = link(def.id), name = def.name, quality = 4, equipLoc = def.equipLoc,
			classID = def.classID, subclassID = def.subclassID }
	end
end

local function slotsOf(n)
	local slots = {}
	for i = 1, n do
		slots[i] = { link = link(ITEMS[i].id), name = ITEMS[i].name, quality = 4, sources = { BOSS_GUID, 1 } }
	end
	return slots
end

-- A ledger with season S1, the controller bound to it, the corpse of a boss with `n` items and master loot with the
-- four players as candidates (Aurel 1, Bryn 2, Corin 3, Dara 4).
local function bench(n)
	local b = { L = Lg().New(), store = {}, n = n or 3 }
	assert(FDCP.Season.Open(b.L, { author = MASTER, ts = 1, season = "S1", instances = { { id = 9001, size = 20 } } }))
	SC():Bind(b.L, b.store)
	SC().Env = function(self) return { ledger = self:Ledger() } end   -- the permission gate is tested in test_permissions.lua
	Mock.loot.Set{ method = "master", masterLooter = true, threshold = 3, slots = slotsOf(b.n),
		candidates = { "Aurel", "Bryn", "Corin", "Dara" } }
	function b.s() return SC().session end
	function b.item(i) return b.s().items[i] end
	function b.kill(id)
		Mock.encounter.Start(id or 601, "Boss")
		Mock.encounter.End(id or 601, "Boss", true)
		if SC().session then SC().session.rules.session.buttonRollsOnly = false end   -- typed rolls (M7-2d: test_button_rolls.lua)
	end
	function b.open()
		b.kill()
		Mock.loot.Open()
		local present = {}
		for _, p in ipairs(PLAYERS) do present[full(p)] = true end
		assert(SC():Step({ type = "SET_RAID", present = present, addon = present }))
		assert(SC():Command("START"))
	end
	-- The active item is won by `name`: the only main-spec answer and a roll, then the proposal (not confirmed).
	function b.win(name)
		local s = b.s()
		local msg = { s = s.id, i = s.active, r = s.net.rounds[s.active], rs = "MS" }
		if full(name) == MASTER then
			assert(PS():Respond("MS"))
		else
			Mock.chat.Receive("FDCP1", Codec():Encode("SRESP", msg), "RAID", name)
		end
		Mock.loot.Roll(name, 50, 1, 100)
		for _, p in ipairs(PLAYERS) do   -- everybody else passes, so the round ends at once
			if p ~= name then
				if full(p) == MASTER then
					PS():Respond("PASS")
				else
					msg.rs = "PASS"
					Mock.chat.Receive("FDCP1", Codec():Encode("SRESP", msg), "RAID", p)
				end
			end
		end
		return s.items[s.active]
	end
	-- Wins the active item for `name` and confirms.
	function b.award(name)
		local item = b.win(name)
		eq(item.state, "PROPOSAL", "the proposal for " .. name)
		eq(item.proposal.winner, full(name))
		assert(SC():Command("CONFIRM"))
		return item
	end
	return b
end

describe("master loot: the item is handed over by Confirm and the loot message ends the delivery", function()
	before_boot(setup)

	it("calls GiveMasterLoot with the winner's candidate index in the same click, then waits for the receipt", function()
		local b = bench()
		b.open()
		local item = b.award("Bryn")
		deepEq(Mock.loot.given, { { slot = 1, candidate = 2 } })
		eq(item.state, "ASSIGNED", "credits are charged, the item is not delivered yet")
		eq(item.delivery.method, "MASTER")
		eq(item.delivery.status, "GIVEN")
		eq(item.delivery.attempts, 1)
		isNil(item.delivery.code)
		local rows = SC():Deliveries()
		eq(#rows, 1)
		eq(rows[1].status, "GIVEN")
		eq(rows[1].text, FDCP.Reasons.Text("DELIVERY", "GIVEN"))
		eq(#Lg().Sorted(b.L, function(e) return e.type == "ITEM_AWARDED" end), 1)

		Mock.loot.Receive("Bryn", link(19003))
		eq(item.state, "DELIVERED")
		eq(item.deliveredVia, "LOOT")
		eq(#SC():Deliveries(), 0)
		eq(PS().view.items[1].st, "DELIVERED", "the raid's view follows")
	end)

	it("finds the item again when the loot window closed the gap of the first one", function()
		local b = bench()
		b.open()
		b.award("Bryn")
		Mock.loot.Receive("Bryn", link(19003))
		b.award("Corin")   -- the Shoulders were slot 2 and are slot 1 now
		deepEq(Mock.loot.given, { { slot = 1, candidate = 2 }, { slot = 1, candidate = 3 } })
		Mock.loot.Receive("Corin", link(19001))
		eq(b.item(2).state, "DELIVERED")
	end)

	it("matches the candidate of another realm by its full name", function()
		local b = bench()
		Mock.loot.Set{ candidates = { "Aurel-Otherrealm", "Bryn" } }
		b.open()
		b.win("Bryn")
		assert(SC():Command("CONFIRM"))
		deepEq(Mock.loot.given, { { slot = 1, candidate = 2 } })
	end)

	it("takes the master looter's own loot message as the receipt when they win the item", function()
		local b = bench()
		b.open()
		local item = b.award("Dara")
		deepEq(Mock.loot.given, { { slot = 1, candidate = 4 } })
		Mock.loot.Receive(nil, link(19003))   -- "You receive loot"
		eq(item.state, "DELIVERED")
		eq(item.award.member, MASTER)
	end)

	it("keeps waiting when the message is another player's or another item's, or hidden", function()
		local b = bench()
		b.open()
		local item = b.award("Bryn")
		Mock.loot.Receive("Corin", link(19003))   -- someone else received that item: the holder, not the receipt
		Mock.loot.Receive("Bryn", link(19001))    -- another item
		eq(item.state, "ASSIGNED")
		Mock.loot.Set{ secretMessages = true }
		Mock.loot.Receive("Bryn", link(19003))
		eq(item.state, "ASSIGNED", "a hidden message is never read")
		eq(ML().stats.hidden, 1)
		Mock.loot.Set{ secretMessages = false }
		Mock.loot.Receive("Bryn", link(19003))
		eq(item.state, "DELIVERED")
	end)

	it("says 'no loot message seen' once the wait is over, and the master looter can mark it by hand", function()
		local b = bench()
		b.open()
		local item = b.award("Bryn")
		eq(SC():Deliveries()[1].noReceipt, false)
		Mock.Advance(FDCP.SessionBoard.RECEIPT_WAIT + 1)
		local row = SC():Deliveries()[1]
		eq(row.noReceipt, true)
		eq(row.text, FDCP.Reasons.Text("DELIVERY", "NO_RECEIPT"))
		assert(SC():MarkDelivered(1))
		eq(item.state, "DELIVERED")
		eq(item.deliveredVia, "MANUAL")
		eq(#SC():Deliveries(), 0)
	end)
end)

describe("master loot that cannot hand the item over: it falls back to a trade", function()
	before_boot(setup)

	it("the winner is not on the candidates list: the award stays, the item waits for a trade", function()
		local b = bench()
		Mock.loot.Set{ candidates = { "Bryn", "Corin" } }
		b.open()
		local item = b.award("Aurel")
		eq(#Mock.loot.given, 0)
		eq(item.state, "ASSIGNED")
		eq(item.delivery.method, "TRADE")
		eq(item.delivery.status, "PENDING")
		eq(item.delivery.code, "NO_CANDIDATE")
		eq(#Lg().Sorted(b.L, function(e) return e.type == "ITEM_AWARDED" end), 1, "credits are charged all the same")
		eq(SC():Deliveries()[1].text, FDCP.Reasons.Text("DELIVERY", "NO_CANDIDATE"))
	end)

	it("the game refuses the call: the same, with CALL_FAILED", function()
		local b = bench()
		b.open()
		GiveMasterLoot = function() error("ADDON_ACTION_FORBIDDEN: blocked") end
		local item = b.award("Aurel")
		eq(item.delivery.method, "TRADE")
		eq(item.delivery.code, "CALL_FAILED")
		eq(item.state, "ASSIGNED")
	end)

	it("the APIs are missing: master loot is out", function()
		local b = bench()
		b.open()
		GiveMasterLoot = nil
		local item = b.award("Aurel")
		eq(item.delivery.code, "NO_MASTER_LOOT")
	end)

	it("another loot method (plan B): no call, a trade, and the list says why", function()
		local b = bench()
		b.open()
		Mock.loot.Set{ method = "group", masterLooter = false }
		local item = b.award("Aurel")
		eq(#Mock.loot.given, 0)
		eq(item.delivery.method, "TRADE")
		eq(item.delivery.code, "NO_MASTER_LOOT")
		eq(item.state, "ASSIGNED")
	end)

	it("the corpse is closed: the item waits, and goes by itself when the corpse opens again", function()
		local b = bench()
		b.open()
		Mock.loot.Set{ slots = {} }   -- the window is closed
		local item = b.award("Aurel")
		eq(item.delivery.code, "NO_WINDOW")
		eq(#Mock.loot.given, 0)
		Mock.loot.Set{ slots = slotsOf(3) }
		Mock.loot.Open()   -- the ML opens the body again: LOOT_COLLECTED while the session runs retries the delivery
		deepEq(Mock.loot.given, { { slot = 1, candidate = 1 } })
		eq(item.delivery.method, "MASTER")
		eq(item.delivery.status, "GIVEN")
		Mock.loot.Receive("Aurel", link(19003))
		eq(item.state, "DELIVERED")
	end)

	it("a refused call is not retried by itself, but the 'hand over now' click tries again", function()
		local b = bench()
		b.open()
		local give = GiveMasterLoot
		GiveMasterLoot = function() error("ADDON_ACTION_FORBIDDEN: blocked") end
		local item = b.award("Aurel")
		eq(item.delivery.code, "CALL_FAILED")
		Mock.loot.Open()
		eq(item.delivery.code, "CALL_FAILED")
		GiveMasterLoot = give
		local ok, code, method = SC():Deliver(1)
		truthy(ok)
		eq(method, "MASTER")
		isNil(code)
		deepEq(Mock.loot.given, { { slot = 1, candidate = 1 } })
		eq(item.delivery.attempts, 1)
	end)

	it("refuses to deliver an item that is not awarded or does not exist", function()
		local b = bench()
		b.open()
		local ok, code = SC():Deliver(1)
		falsy(ok); eq(code, "NOT_ASSIGNED")
		ok, code = SC():Deliver(9)
		falsy(ok); eq(code, "NO_SESSION")
		ok, code = SC():MarkDelivered(9)
		falsy(ok); eq(code, "NO_SESSION")
		ok, code = SC():MarkDelivered(1)
		falsy(ok); eq(code, "NOT_ASSIGNED")
	end)
end)

describe("plan B: the item changes hands by trade", function()
	before_boot(setup)

	-- Master loot is out: the winner gets the item from a trade. The loot messages tell who holds it.
	local function planB(b)
		b.open()
		Mock.loot.Set{ method = "group", masterLooter = false }
	end

	it("learns who holds the item from the loot message, and ends the delivery when the trade goes through", function()
		local b = bench()
		planB(b)
		local item = b.award("Aurel")
		eq(item.delivery.code, "NO_MASTER_LOOT")
		Mock.loot.Receive(nil, link(19003))   -- the master looter looted it: "You receive loot"
		eq(item.delivery.holder, MASTER)
		eq(SC():Deliveries()[1].text,
			FDCP.Reasons.Text("DELIVERY", "NO_MASTER_LOOT") .. " " .. FDCP.Reasons.Text("DELIVERY", "HOLDER"):format("Dara"))

		Mock.trade.Open("Aurel")
		Mock.trade.Put("player", link(19003))
		Mock.trade.Accept(1, 0)
		eq(item.state, "ASSIGNED", "nothing happens until the trade goes through")
		Mock.trade.Finish()
		eq(item.state, "DELIVERED")
		eq(item.deliveredVia, "TRADE")
		eq(#SC():Deliveries(), 0)
	end)

	it("a cancelled trade, another partner or another item deliver nothing", function()
		local b = bench()
		planB(b)
		local item = b.award("Aurel")
		Mock.trade.Open("Aurel")
		Mock.trade.Put("player", link(19003))
		Mock.trade.Cancel()
		eq(item.state, "ASSIGNED")
		Mock.trade.Open("Bryn")
		Mock.trade.Put("player", link(19003))
		Mock.trade.Finish()
		eq(item.state, "ASSIGNED", "the item went to someone else")
		Mock.trade.Open("Aurel")
		Mock.trade.Put("player", link(19001))
		Mock.trade.Finish()
		eq(item.state, "ASSIGNED", "another item")
		Mock.trade.Open("Aurel")
		Mock.trade.Put("target", link(19003))   -- the winner hands it back: not a delivery to them
		Mock.trade.Finish()
		eq(item.state, "ASSIGNED")
	end)

	it("the trade is read from the client's own message when the accept update is missed", function()
		local b = bench()
		planB(b)
		local item = b.award("Aurel")
		Mock.trade.Open("Aurel")
		Mock.trade.Put("player", link(19003))
		Mock.Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
		Mock.trade.Cancel()   -- TRADE_CLOSED right after the complete message
		eq(item.state, "DELIVERED")
	end)

	it("a winner that is the master looter receives the item from the holder in a trade", function()
		local b = bench()
		planB(b)
		local item = b.award("Dara")
		Mock.trade.Open("Corin")
		Mock.trade.Put("target", link(19003))
		Mock.trade.Finish()
		eq(item.state, "DELIVERED")
		eq(item.deliveredVia, "TRADE")
	end)

	it("a winner who already looted the item (a message after the session opened) is delivered when it is awarded", function()
		local b = bench()
		planB(b)
		Mock.loot.Receive("Aurel", link(19003))   -- nothing is awarded yet: the message is only remembered
		eq(#SC():Deliveries(), 0)
		local item = b.award("Aurel")
		eq(item.state, "DELIVERED")
		eq(item.deliveredVia, "LOOT")
		eq(#Mock.loot.given, 0)
	end)

	it("a loot message from before the session does not count", function()
		local b = bench()
		Mock.loot.Receive("Aurel", link(19003))
		Mock.Advance(5)
		planB(b)
		local item = b.award("Aurel")
		eq(item.state, "ASSIGNED")
	end)

	it("a holder is learned once per item, and only for an item waiting for a trade", function()
		local b = bench()
		planB(b)
		local item = b.award("Aurel")
		Mock.loot.Receive("Corin", link(19003))
		eq(item.delivery.holder, full("Corin"))
		Mock.loot.Receive("Bryn", link(19003))
		eq(item.delivery.holder, full("Corin"), "the first message stays")
	end)
end)

describe("deferred delivery: the night is rolled and the items are handed over later", function()
	before_boot(setup)

	it("an ended session's undelivered items move to the next session's carry and are delivered by trade", function()
		local b = bench(2)
		b.open()
		Mock.loot.Set{ method = "group", masterLooter = false }
		b.award("Aurel")
		b.award("Bryn")
		assert(SC():Command("END"))
		eq(b.s().state, "ENDED")
		eq(#SC():Deliveries(), 2)

		Mock.loot.Set{ method = "master", masterLooter = true, slots = {} }
		b.kill(602)   -- the next boss: a new session
		local s2 = b.s()
		eq(s2.state, "WAITING")
		truthy(s2.encounter == 602)
		truthy(b.store.carry, "the carried session is saved with the guild data")
		local rows = SC():Deliveries()
		eq(#rows, 2)
		eq(rows[1].which, "carry")
		eq(rows[1].recipient, full("Aurel"))
		eq(rows[2].recipient, full("Bryn"))

		Mock.trade.Open("Bryn")
		Mock.trade.Put("player", link(19001))
		Mock.trade.Finish()
		eq(#SC():Deliveries(), 1)
		eq(b.store.carry.items[2].state, "DELIVERED")
		eq(b.store.carry.items[2].deliveredVia, "TRADE")

		assert(SC():MarkDelivered(1, "carry"))
		eq(#SC():Deliveries(), 0)
	end)

	it("keeps the list across a /reload and merges later sessions into it", function()
		local b = bench(1)
		b.open()
		Mock.loot.Set{ method = "group", masterLooter = false }
		b.award("Aurel")
		assert(SC():Command("END"))
		Mock.loot.Set{ method = "master", masterLooter = true, slots = {} }
		b.kill(602)
		eq(#SC():Deliveries(), 1)
		-- the saved data comes back after a /reload: the carried session and the new one are found again
		local saved = b.store
		SC():Bind(b.L, saved)
		eq(#SC():Deliveries(), 1)
		eq(SC():Deliveries()[1].which, "carry")
		-- an unrelated boss later: the new session carries nothing, the old item stays
		assert(SC():Command("END"))
		b.kill(603)
		eq(#SC():Deliveries(), 1)
	end)

	it("a carried item can be handed over by master loot when its corpse is open", function()
		local b = bench(1)
		b.open()
		Mock.loot.Set{ slots = {} }
		b.award("Aurel")
		assert(SC():Command("END"))
		b.kill(602)
		Mock.loot.Set{ slots = slotsOf(1) }
		local ok, _, method = SC():Deliver(1, "carry")
		truthy(ok)
		eq(method, "MASTER")
		deepEq(Mock.loot.given, { { slot = 1, candidate = 1 } })
		Mock.loot.Receive("Aurel", link(19003))
		eq(#SC():Deliveries(), 0)
	end)

	it("a character that is not the master looter of a carried session never touches it", function()
		local b = bench(1)
		b.open()
		Mock.loot.Set{ slots = {} }
		b.award("Aurel")
		assert(SC():Command("END"))
		b.kill(602)
		eq(#SC():Deliveries(), 1)
		Mock.player.name = "Corin"
		eq(#SC():Deliveries(), 0)
		local ok, code = SC():MarkDelivered(1, "carry")
		falsy(ok); eq(code, "NO_SESSION")
	end)
end)

describe("the adapter", function()
	before_boot(setup)

	it("reads the receipt from the client's own loot format, in English and in Italian", function()
		local en = ML().ParseReceipt("Bryn receives loot: " .. link(19003) .. ".")
		deepEq(en, { player = full("Bryn"), itemID = 19003, link = link(19003), count = 1 })
		en = ML().ParseReceipt("You receive loot: " .. link(19001) .. ".")
		eq(en.player, MASTER)
		eq(en.itemID, 19001)
		LOOT_ITEM = "%s riceve il bottino: %s."
		LOOT_ITEM_SELF = "Ricevi il bottino: %s."
		local it = ML().ParseReceipt("Bryn riceve il bottino: " .. link(19003) .. ".")
		eq(it.player, full("Bryn"))
		eq(it.itemID, 19003)
		eq(ML().ParseReceipt("Ricevi il bottino: " .. link(19002) .. ".").player, MASTER)
		isNil(ML().ParseReceipt("Bryn receives loot: " .. link(19003) .. "."), "the English line is not an Italian client's message")
		isNil(ML().ParseReceipt("Bryn riceve il bottino: Mana Potion."), "no item link")
		isNil(ML().ParseReceipt(42))
	end)

	it("plans master loot only for the master looter of a master loot group", function()
		bench()
		eq(ML().Plan(), "MASTER")
		Mock.loot.Set{ masterLooter = false }
		local plan, code = ML().Plan()
		eq(plan, "TRADE"); eq(code, "NO_MASTER_LOOT")
		Mock.loot.Set{ masterLooter = true, method = "personal" }
		plan, code = ML().Plan()
		eq(plan, "TRADE"); eq(code, "NO_MASTER_LOOT")
	end)

	it("finds an item in the loot window by its id, preferring the slot it was seen in", function()
		bench()
		eq(ML().FindSlot(19001, 2), 2)
		eq(ML().FindSlot(19001, 3), 2, "the hint no longer holds it")
		local slot, code = ML().FindSlot(19999, 1)
		isNil(slot); eq(code, "NO_SLOT")
		Mock.loot.Set{ slots = {} }
		slot, code = ML().FindSlot(19001, 1)
		isNil(slot); eq(code, "NO_WINDOW")
	end)

	it("finds a candidate by full name, whatever the realm suffix", function()
		bench()
		eq(ML().FindCandidate(1, full("Bryn")), 2)
		eq(ML().FindCandidate(1, "Bryn"), 2)
		local index, code = ML().FindCandidate(1, full("Nobody"))
		isNil(index); eq(code, "NO_CANDIDATE")
		index, code = ML().FindCandidate(1, nil)
		isNil(index); eq(code, "NO_CANDIDATE")
	end)

	it("tells a holder by the newest unclaimed message after a time, and forgets the oldest messages", function()
		bench()
		Mock.loot.Receive("Corin", link(19003))
		Mock.Advance(10)
		local since = FDCP.Compat.Now()
		Mock.loot.Receive("Bryn", link(19003))
		eq(ML().Holder(19003, since, false), full("Bryn"))
		eq(ML().Holder(19003, since, true), full("Bryn"))
		isNil(ML().Holder(19003, since, false), "claimed")
		eq(ML().Holder(19003, nil, false), full("Corin"))
		isNil(ML().Holder(19002, nil, false))
		for _ = 1, ML().RECENT + 5 do Mock.loot.Receive("Aurel", link(19002)) end
		eq(#ML().recent, ML().RECENT)
	end)

	it("a trade is only read once it went through, and an empty one is nothing", function()
		bench()
		local trades = {}
		FDCP.Bus:On("TRADE_COMPLETED", function(_, info) trades[#trades + 1] = info end)
		Mock.trade.Open("Corin", "Otherrealm")
		Mock.trade.Put("player", link(19003))
		Mock.trade.Put("target", link(19001))
		Mock.trade.Cancel()
		eq(#trades, 0)
		Mock.trade.Open("Corin", "Otherrealm")
		Mock.trade.Finish()
		eq(#trades, 0, "nothing was traded")
		Mock.trade.Open("Corin", "Otherrealm")
		Mock.trade.Put("player", link(19003))
		Mock.trade.Put("target", link(19001))
		Mock.trade.Finish()
		eq(#trades, 1)
		eq(trades[1].partner, "Corin-Otherrealm")
		deepEq(trades[1].gave, { 19003 })
		deepEq(trades[1].got, { 19001 })
		isNil(ML().trade, "the window state is forgotten")
	end)

	it("does not raise when the trade APIs are missing, hidden or failing", function()
		bench()
		for _, mode in ipairs({ "missing", "error", "secret" }) do
			local players, targets, partner = GetTradePlayerItemLink, GetTradeTargetItemLink, UnitName
			if mode == "missing" then
				GetTradePlayerItemLink, GetTradeTargetItemLink = nil, nil
			elseif mode == "error" then
				GetTradePlayerItemLink = function() error("boom") end
				GetTradeTargetItemLink = function() error("boom") end
			else
				GetTradePlayerItemLink = function() return Mock.SECRET end
				GetTradeTargetItemLink = function() return Mock.SECRET end
			end
			Mock.trade.Open("Corin")
			Mock.trade.Accept(1, 1)
			Mock.trade.Cancel()
			GetTradePlayerItemLink, GetTradeTargetItemLink, UnitName = players, targets, partner
		end
	end)
end)

describe("the state machine's delivery inputs", function()
	before_boot(setup)

	it("records where a delivery stands and refuses what makes no sense", function()
		local b = bench()
		b.open()
		local s = b.s()
		local function step(input)
			input.ts, input.by = 100, MASTER
			return F().Step(s, input, {})
		end
		local ok, code = step({ type = "DELIVERY", index = 1, method = "TRADE", status = "PENDING" })
		falsy(ok); eq(code, "NOT_ASSIGNED", "nothing awarded yet")
		b.award("Aurel")
		ok, code = step({ type = "DELIVERY", index = 1, method = "MAIL", status = "PENDING" })
		falsy(ok); eq(code, "method")
		ok, code = step({ type = "DELIVERY", index = 1, method = "TRADE", status = "DONE" })
		falsy(ok); eq(code, "status")
		ok, code = step({ type = "DELIVERY", index = 1, method = "TRADE", status = "PENDING", code = "lower" })
		falsy(ok); eq(code, "code")
		ok, code = step({ type = "DELIVERY", index = 9, method = "TRADE", status = "PENDING" })
		falsy(ok); eq(code, "index")
		ok, code = F().Step(s, { type = "DELIVERY", index = 1, method = "TRADE", status = "PENDING", ts = 100, by = full("Aurel") }, {})
		falsy(ok); eq(code, "NOT_ML")
		ok, code = step({ type = "DELIVERED", index = 1, player = full("Bryn") })
		falsy(ok); eq(code, "WRONG_PLAYER")
		ok = step({ type = "DELIVERED", index = 1, player = full("Aurel"), via = "SOMETHING" })
		truthy(ok)
		isNil(s.items[1].deliveredVia, "an unknown way is not recorded")
		ok, code = step({ type = "DELIVERED", index = 1, player = full("Aurel") })
		falsy(ok); eq(code, "NOT_ASSIGNED", "a second receipt does nothing")
	end)

	it("takes deliveries after the session ended, and says who must receive the item", function()
		local b = bench(1)
		b.open()
		Mock.loot.Set{ method = "group", masterLooter = false }
		b.award("Aurel")
		assert(SC():Command("END"))
		local s = b.s()
		eq(F().Recipient(s, 1), full("Aurel"))
		isNil(F().Recipient(s, 2), "an item not awarded has no recipient")
		eq(F().Recipient({ ml = MASTER, items = { { award = {} } } }, 1), MASTER, "a bank with nobody set: the master looter")
		local ok = F().Step(s, { type = "DELIVERY", index = 1, method = "TRADE", status = "PENDING", ts = 100, by = MASTER }, {})
		truthy(ok)
		ok = F().Step(s, { type = "DELIVERED", index = 1, player = full("Aurel"), ts = 101, via = "TRADE" }, {})
		truthy(ok)
		eq(s.items[1].state, "DELIVERED")
		deepEq(F().Undelivered(s), {})
	end)
end)

describe("the to-deliver tab of the master looter's window", function()
	before_boot(setup)

	local function d() return W().deliverUI end
	local function open(b)
		b.open()
		Mock.loot.Set{ method = "group", masterLooter = false }
		MW():Open("loot")
		W().root.sub:Select("deliver")
	end

	it("is a second sub-tab, empty at first", function()
		local b = bench()
		open(b)
		truthy(d().pane:IsShown())
		falsy(W().ui.pane:IsShown())
		falsy(d().give:IsShown())
		falsy(d().mark:IsShown())
		eq(#d().table:GetData(), 0)
	end)

	it("lists the awarded items with where they stand, and the header counts them", function()
		local b = bench()
		open(b)
		b.award("Aurel")
		eq(#d().table:GetData(), 1)
		local row = d().table:GetData()[1]
		eq(row.recipient, full("Aurel"))
		eq(row.text, FDCP.Reasons.Text("DELIVERY", "NO_MASTER_LOOT"))
		truthy(d().give:IsShown())
		truthy(d().mark:IsShown())
		eq(W().ui.status:GetText():find(L("ML_TO_DELIVER_ONE"), 1, true) ~= nil, true)
	end)

	it("'Hand over now' tries master loot from the click, and says what happened", function()
		local b = bench()
		open(b)
		b.award("Aurel")
		d().give:Click()
		eq(d().message:GetText(), FDCP.Reasons.Text("DELIVERY", "NO_MASTER_LOOT"), "master loot is still out")
		Mock.loot.Set{ method = "master", masterLooter = true }
		d().give:Click()
		eq(d().message:GetText(), L("ML_DELIVER_NOW_GIVEN"))
		deepEq(Mock.loot.given, { { slot = 1, candidate = 1 } })
		falsy(d().give:IsShown(), "handed over: only the loot message is missing")
		truthy(d().mark:IsShown())
		Mock.loot.Receive("Aurel", link(19003))
		eq(#d().table:GetData(), 0)
		falsy(d().mark:IsShown())
	end)

	it("'Mark as delivered' is the master looter's word", function()
		local b = bench()
		open(b)
		b.award("Aurel")
		d().mark:Click()
		eq(b.item(1).state, "DELIVERED")
		eq(b.item(1).deliveredVia, "MANUAL")
		eq(#d().table:GetData(), 0)
	end)

	it("a row click selects which item the buttons act on", function()
		local b = bench()
		open(b)
		b.award("Aurel")
		b.award("Bryn")
		eq(#d().table:GetData(), 2)
		eq(W().deliverSel.index, 1)
		W():SelectDelivery(d().table:GetData()[2])
		eq(W().deliverSel.index, 2)
		d().mark:Click()
		eq(b.item(2).state, "DELIVERED")
		eq(b.item(1).state, "ASSIGNED")
		eq(W().deliverSel.index, 1, "the selection moves to the item that is left")
	end)

	it("every visible text of the tab is in both languages", function()
		for _, key in ipairs({ "ML_SUBTAB_DELIVER", "ML_DELIVER_EYEBROW", "ML_DELIVER_TITLE", "ML_DELIVER_HELP", "ML_DELIVER_EMPTY",
			"ML_COL_ITEM", "ML_COL_WINNER", "ML_COL_STATUS", "ML_GIVE", "ML_MARK_DELIVERED", "ML_DELIVER_NOW_GIVEN",
			"ML_DELIVER_NOW_ALREADY", "ML_TO_DELIVER_ONE", "ML_TO_DELIVER_N" }) do
			for _, lang in ipairs({ "enUS", "itIT" }) do
				local text = FDCP.Locale.Text(lang, key)
				truthy(text ~= key and text ~= "", lang .. " " .. key)
			end
		end
		for _, code in ipairs({ "NO_MASTER_LOOT", "NO_WINDOW", "NO_SLOT", "NO_CANDIDATE", "CALL_FAILED", "GIVEN", "TRADE", "HOLDER",
			"NO_RECEIPT" }) do
			for _, lang in ipairs({ "enUS", "itIT" }) do
				local key = FDCP.Reasons.Key("DELIVERY", code)
				truthy(FDCP.Locale.Text(lang, key) ~= key, lang .. " " .. code)
			end
		end
	end)
end)

