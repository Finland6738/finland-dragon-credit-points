-- SessionController: runs a loot session on the master looter's client (docs/ANALISI.md §4, §4.1, §8.4, §11; M4-4).
-- Lua 5.1. The rules are in Domain/SessionFSM.lua (pure: inputs -> state + effects); this module is the glue with the
-- game and nothing else: it never decides who wins, what an item costs or when a round closes.
--
--   ENCOUNTER_ENDED (a kill)  -> a new session in WAITING, when this client is the master looter (Compat.Loot)
--   LOOT_COLLECTED            -> LOOT_OPENED (Adapters/LootSource.lua); held while the chat is locked down or a boss
--                                runs, and fed once it is over (plan B of §11: sessions open after ENCOUNTER_END)
--   lockdown changes          -> LOCKDOWN{active} (RollListener.Locked: a boss, an addon restriction, the chat lockdown)
--   GROUP_SCANNED, ADDON_CHECK_CHANGED -> SET_RAID (App/AddonCheck.lua: who is present, who has the addon, §4.1)
--   CHAT_MSG_SYSTEM rolls     -> ROLL (Adapters/RollListener.lua, attached to the hosted session)
--   SESSION_INPUT             -> RESPONSE (Net/Protocol.lua: the raiders' answers, always the sender's own)
--   a one-second ticker       -> TICK (round timers, the "auto" award window); never while rolls hidden by a lockdown
--                                still wait in the RollListener buffer, so a held roll is never left out of its round
--   the ML's commands         -> START, OPEN_ROLL, CLOSE_ROUND, ADVANCE, CONFIRM, REJECT, MODIFY, PAUSE, RESUME, END...
--
-- Every accepted input goes through Step: SessionFSM.Step with the guild's ledger and the permission gate (CONFIRM
-- writes ITEM_AWARDED with its reason and flag codes there), then the effects go to the raid (Protocol.Session:Publish)
-- and to the bus. The automatic phases (auto-advance, the reroll among the tied, the next tier, the off-spec tier) are
-- the FSM's own `settle`: the controller only feeds it the time.
--
-- Persistence: the session is one plain-data table kept in the guild's saved data (`session`), changed in place at every
-- transition, so a /reload or a disconnection finds it as it was: Resume() adopts it again (SessionFSM.Restore), hosts it
-- on the protocol (the raid's views resync from it) and attaches the roll listener. A session written by a newer addon
-- is resumed read-only.
--
-- Other officers: their client never runs the session; they see the master looter's view (Protocol.Session.view), read
-- only. View() returns it with `host = false`; every command answers NOT_HOST there.
--
-- Delivery (M4-7, Adapters/MasterLoot.lua): the DELIVER effect of a Confirm hands the item over in the same click, by
-- master loot when the game allows it (the receipt is the winner's loot message, LOOT_RECEIVED) and otherwise by trade
-- (plan B: the award stays in the ledger and the item sits in the "to deliver" list until a trade of this client
-- hands it over, TRADE_COMPLETED, or the master looter marks it). The items of an ended session that are still
-- undelivered when the next boss dies move to `carry` (an ended session of their own, saved with the guild data), so the
-- list survives the night (deferred delivery, §4).
--
-- Bus events: "SESSION_CHANGED"(session, effects) after every accepted input on the host (not a bare TICK);
--             "SESSION_DELIVER"(effect, item) when an award asks for the item to change hands (the controller delivers it);
--             "SESSION_HELD"(code) when a collection waits (LOCKDOWN) and "SESSION_STARTED"(session).
-- Not verified in the real client: the whole flow around a real boss (M4-9), master loot (spike S2), the roll messages
-- in an instance (S3) and the addon messages on RAID (S4).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local SC = {}
ns.SessionController, ns.modules.SessionController = SC, SC

local type, ipairs, pairs, tostring = type, ipairs, pairs, tostring

SC.TICK = 1   -- seconds between two TICK inputs while a session runs

local function F() return ns.SessionFSM end
local function C() return ns.Compat end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function log(level, code, ...) if ns.Log then ns.Log[level]("Session", code, ...) end end
local function me() return ns.GuildRanks and ns.GuildRanks.Me() or nil end
local function now() return C().Now() end

-- The inputs only the master looter gives (`by` is filled with the player's name).
local ML_INPUTS = {
	CORRECT_ITEM = true, REMOVE_ITEM = true, START = true, OPEN_ROLL = true, CLOSE_ROUND = true, ADVANCE = true,
	CONFIRM = true, REJECT = true, MODIFY = true, CLOSE_VOTE = true, PAUSE = true, RESUME = true, END = true,
	DELIVERED = true, DELIVERY = true,
}

function SC:Reset()
	if self.ticker then self.ticker:Cancel() end
	self.ticker = nil
	self.ledger, self.store, self.session, self.readOnly = nil, nil, nil, nil
	self.held, self.bound = nil, false
	if ns.RollListener and ns.RollListener.getSession then ns.RollListener:Detach() end
	if ns.Protocol and ns.Protocol.Session.host then ns.Protocol.Session:Host(nil) end
end

---------------------------------------------------------------------------------------------------------------------
-- The ledger and the saved session

-- Binds a ledger and the table the session is saved in (tests; nil, nil = the current guild's saved data), then
-- resumes the saved session if there is one. Returns the resumed session or nil.
function SC:Bind(ledger, store)
	self:Reset()
	self.ledger, self.store, self.bound = ledger, store, true
	return self:Resume()
end

function SC:Ledger()
	if self.ledger then return self.ledger end
	if ns.NightController then return ns.NightController:Ledger() end
	return nil
end

-- The table that keeps `session` (the guild's saved data), or nil.
function SC:Store()
	if self.store then return self.store end
	local data = ns.Config and ns.Config.GuildData and ns.Config:GuildData()
	if not data or (ns.Config.IsReadOnly and ns.Config:IsReadOnly()) then return nil end
	return data
end

local function gate()
	return ns.PermissionService and ns.PermissionService:Gate() or nil
end

function SC:Env()
	return { ledger = self:Ledger(), opts = gate() }
end

-- Adopts the saved session after a /reload, a disconnection or a guild change: hosts it, attaches the roll listener,
-- starts the ticker. Returns the session or nil.
function SC:Resume()
	local store = self:Store()
	local saved = store and store.session
	if type(saved) ~= "table" then return nil end
	local s, readOnly = F().Restore(saved)
	if not s then return nil end
	if s.ml ~= me() then return nil end   -- another character's session: this one is not its master looter
	self.session, self.readOnly = s, readOnly or nil
	self:Host()
	log("info", "RESUMED", ns.Log and ns.Log.Plain(s.state))
	return s
end

-- The hosted session (nil when this client runs none).
function SC:Current()
	if not self.bound and not self.session then
		self.bound = true
		self:Resume()
	end
	return self.session
end

function SC:IsHost()
	local s = self:Current()
	return s ~= nil and s.state ~= "ENDED"
end

---------------------------------------------------------------------------------------------------------------------
-- Hosting: the protocol, the roll listener, the ticker

function SC:Host()
	local s = self.session
	if ns.Protocol then ns.Protocol.Session:Host(s) end
	if ns.RollListener then
		if s and s.state ~= "ENDED" and not self.readOnly then
			ns.RollListener:Attach(function() return self.session end, function(input) return self:Step(input) end)
		else
			ns.RollListener:Detach()
		end
	end
	self:Arm()
end

-- The ticker runs while a session is not ended.
function SC:Arm()
	local s = self.session
	local want = s ~= nil and s.state ~= "ENDED" and not self.readOnly
	if want and not self.ticker then
		self.ticker = C().NewTicker(SC.TICK, function() self:Tick() end)
	elseif not want and self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Stepping

-- Applies one input to the hosted session: ts (the local clock) and, for the master looter's commands, `by` are filled
-- in. The effects go to the raid and the bus. Returns ok, code, effects (SessionFSM.Step), or nil, "NO_SESSION".
function SC:Step(input)
	local s = self:Current()
	if not s then return nil, "NO_SESSION", {} end
	if self.readOnly then return nil, "READ_ONLY", {} end
	if type(input) ~= "table" then return nil, "UNKNOWN_INPUT", {} end
	if input.ts == nil then input.ts = now() end
	if ML_INPUTS[input.type] and input.by == nil then input.by = me() end
	local ok, code, effects = F().Step(s, input, self:Env())
	if not ok then return nil, code, effects end
	if #effects > 0 then
		self:Apply(effects)
	elseif input.type ~= "TICK" then
		emit("SESSION_CHANGED", s, effects)   -- a roll, a response, the raid: the window draws the new candidates
	end
	return true, nil, effects
end

-- The effects of an accepted input.
function SC:Apply(effects)
	local s = self.session
	if ns.Protocol then ns.Protocol.Session:Publish(effects, s) end
	for _, e in ipairs(effects) do
		if e.type == "DELIVER" then
			emit("SESSION_DELIVER", e, s.items[e.item])
			self:Deliver(e.item)
		elseif e.type == "AWARDED" then
			log("info", "AWARDED", e.item, e.cost)
		elseif e.type == "AUTO_FAILED" then
			log("warn", "AUTO_FAILED", ns.Log and ns.Log.Plain(e.code))
		elseif e.type == "ENDED" then
			self:Host()   -- stops the listener and the ticker; the session stays saved for the late deliveries
		end
	end
	if self.store == nil then
		local store = self:Store()
		if store then store.sessionSavedAt = C().ServerTime() end
	end
	emit("SESSION_CHANGED", s, effects)
end

-- A command of the master looter's window: SC:Command("CONFIRM"), SC:Command("REJECT", { ["then"] = "BANK" }), ...
function SC:Command(kind, fields)
	local input = {}
	for k, v in pairs(type(fields) == "table" and fields or {}) do input[k] = v end
	input.type = kind
	return self:Step(input)
end

---------------------------------------------------------------------------------------------------------------------
-- Delivery (M4-7)

-- The ended session that keeps the undelivered items of earlier sessions (nil when there is none, or when it belongs to
-- another character: only its master looter may touch it).
function SC:Carry()
	local store = self:Store()
	local carry = store and store.carry
	if type(carry) ~= "table" or type(carry.items) ~= "table" or carry.ml ~= me() then return nil end
	return carry
end

-- The session a delivery row belongs to: "main" (the hosted one, the default) or "carry".
function SC:SessionOf(which)
	if which == "carry" then return self:Carry() end
	return self.session
end

-- Applies a delivery input to the hosted session or to the carried one. The carried one is not announced to the raid.
-- Returns ok, code, effects.
function SC:StepOn(which, input)
	if which ~= "carry" then return self:Step(input) end
	local carry = self:Carry()
	if not carry then return nil, "NO_SESSION", {} end
	if self.readOnly then return nil, "READ_ONLY", {} end
	if input.ts == nil then input.ts = now() end
	if input.by == nil then input.by = me() end
	local ok, code, effects = F().Step(carry, input, self:Env())
	if not ok then return nil, code, effects end
	emit("SESSION_CHANGED", self.session, effects)
	return true, nil, effects
end

-- Moves the awarded-but-undelivered items of `old` to the carried session, before a new session replaces it.
function SC:CarryOver(old)
	local store = self:Store()
	local list = F().Undelivered(old)
	if not store or #list == 0 then return end
	local carry = self:Carry()
	if not carry then
		carry = F().New({ id = "carry-" .. tostring(old.id), season = old.season, ml = old.ml, ts = now(), rules = old.rules })
		if not carry then return end
		carry.state = "ENDED"
		carry.endedAt = now()
		store.carry = carry
	end
	local kept = {}
	for _, item in ipairs(carry.items) do
		if item.state == "ASSIGNED" then kept[#kept + 1] = item end   -- the delivered ones are history, not a list to work from
	end
	for _, i in ipairs(list) do kept[#kept + 1] = F().Copy(old.items[i]) end
	carry.items = kept
	log("info", "CARRIED", #list)
end

-- Hands the awarded item `index` over. By master loot when the game allows it, otherwise it waits for a trade (plan B):
-- the delivery is recorded as GIVEN (the winner's loot message ends it) or PENDING with the DELIVERY code that says why
-- master loot was out. An item the winner already received (a loot message after the session opened) is delivered at
-- once. Returns ok, code, method: `code` is the DELIVERY code when it fell back to a trade, `method` is "MASTER", "TRADE"
-- or "LOOT" (already with the winner); nil and a refusal code when the item cannot be delivered (not awarded, no
-- session, read only).
function SC:Deliver(index, which)
	local sess = self:SessionOf(which)
	local item = sess and sess.items[index]
	if not item then return nil, "NO_SESSION" end
	if item.state ~= "ASSIGNED" then return nil, "NOT_ASSIGNED" end
	local ML = ns.MasterLoot
	local recipient = F().Recipient(sess, index)
	local holder = ML.Holder(item.itemID, sess.createdAt, false)
	if holder ~= nil and holder == recipient then
		ML.Holder(item.itemID, sess.createdAt, true)
		local ok, code = self:StepOn(which, { type = "DELIVERED", index = index, player = recipient, via = "LOOT" })
		return ok, code, "LOOT"
	end
	local given, code = ML.Give(item.itemID, item.slot, recipient)
	local ok, refusal
	if given then
		ok, refusal = self:StepOn(which, { type = "DELIVERY", index = index, method = "MASTER", status = "GIVEN" })
		return ok, refusal, "MASTER"
	end
	ok, refusal = self:StepOn(which, { type = "DELIVERY", index = index, method = "TRADE", status = "PENDING", code = code,
		holder = holder })
	return ok, ok and code or refusal, "TRADE"
end

-- The master looter's word that an item reached its winner (a trade the addon did not see, a message it did not read).
function SC:MarkDelivered(index, which)
	local sess = self:SessionOf(which)
	if not sess or not sess.items[index] then return nil, "NO_SESSION" end
	return self:StepOn(which, { type = "DELIVERED", index = index, player = F().Recipient(sess, index), via = "MANUAL" })
end

-- The "to deliver" list as the window shows it (App/SessionBoard.lua DeliveryRows): the carried items first, then the
-- hosted session's. Empty on a client that runs no session and keeps no carried item.
function SC:Deliveries()
	return ns.SessionBoard.DeliveryRows({ { which = "carry", session = self:Carry() }, { which = "main", session = self.session } },
		now())
end

-- The awarded items still to deliver: { { which, session, index, item } }, the carried ones first.
function SC:Undelivered()
	local out = {}
	for _, which in ipairs({ "carry", "main" }) do
		local sess = self:SessionOf(which)
		if sess then
			for _, i in ipairs(F().Undelivered(sess)) do
				out[#out + 1] = { which = which, session = sess, index = i, item = sess.items[i] }
			end
		end
	end
	return out
end

-- A loot message: it ends the delivery of an item that reached its winner, or tells who holds an item waiting for a
-- trade. The loot of the winner is also taken as the delivery when the item came to them some other way (the game's own
-- roll, a master loot call made by hand): the receipt is by item and player, so a second copy of the same item looted by
-- the same player is taken as the delivery of the first one.
function SC:OnLootReceived(entry)
	if type(entry) ~= "table" or entry.claimed or self.readOnly then return end
	local list = self:Undelivered()
	for _, row in ipairs(list) do
		if row.item.itemID == entry.itemID and F().Recipient(row.session, row.index) == entry.player then
			entry.claimed = true
			self:StepOn(row.which, { type = "DELIVERED", index = row.index, player = entry.player, via = "LOOT" })
			return
		end
	end
	for _, row in ipairs(list) do
		local d = row.item.delivery
		if row.item.itemID == entry.itemID and not (d and (d.holder or d.status == "GIVEN")) then
			entry.claimed = true
			self:StepOn(row.which, { type = "DELIVERY", index = row.index, method = d and d.method or "TRADE",
				status = d and d.status or "PENDING", code = d and d.code, holder = entry.player })
			return
		end
	end
end

-- A trade of this client that went through: the items given to their winner, or received by the master looter who won
-- them, are delivered.
function SC:OnTradeCompleted(info)
	if type(info) ~= "table" or self.readOnly then return end
	local function take(list, id)
		for i, v in ipairs(list or {}) do
			if v == id then table.remove(list, i) return true end
		end
		return false
	end
	local mine = me()
	for _, row in ipairs(self:Undelivered()) do
		local recipient = F().Recipient(row.session, row.index)
		local id = row.item.itemID
		if (recipient == info.partner and take(info.gave, id)) or (recipient == mine and take(info.got, id)) then
			self:StepOn(row.which, { type = "DELIVERED", index = row.index, player = recipient, via = "TRADE" })
		end
	end
end

-- The corpse was opened again: the items that waited for master loot are tried once more. Only the reasons that can pass
-- (the window was closed, the item or the winner was not in it) are retried; a call the game refused stays for the
-- master looter's own click.
local RETRY = { NO_WINDOW = true, NO_SLOT = true, NO_CANDIDATE = true }

function SC:RetryDeliveries()
	if self.readOnly or ns.MasterLoot.Plan() ~= "MASTER" then return end
	for _, row in ipairs(self:Undelivered()) do
		local d = row.item.delivery
		if d and d.status == "PENDING" and RETRY[d.code] then self:Deliver(row.index, row.which) end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- The game's side

-- True while a boss runs, an addon restriction is active or the chat is locked down.
function SC.Locked()
	if ns.RollListener and ns.RollListener.Locked then return ns.RollListener.Locked() end
	return false
end

-- Tells the session whether a lockdown is on (only when it changed), then feeds a held collection once it is over.
function SC:Refresh()
	local s = self.session
	if not s or s.state == "ENDED" or self.readOnly then return end
	local locked = SC.Locked()
	if s.lockdown ~= locked then self:Step({ type = "LOCKDOWN", active = locked }) end
	if not locked and self.held and s.state == "WAITING" then
		local collection = self.held
		self.held = nil
		self:OnLoot(collection)
	end
end

-- One tick: the lockdown, then the time (not while hidden rolls may still belong to the open round).
function SC:Tick()
	local s = self.session
	if not s or s.state == "ENDED" then return self:Arm() end
	self:Refresh()
	if ns.RollListener and ns.RollListener:Pending() > 0 then return end
	self:Step({ type = "TICK" })
end

-- The raid as AddonCheck sees it: who is present, who can roll.
function SC:SyncRaid()
	local s = self.session
	if not s or s.state == "ENDED" or self.readOnly or not ns.AddonCheck then return end
	local raid = ns.AddonCheck.raid
	if type(raid) ~= "table" or not raid.inRaid then return end
	local input = ns.AddonCheck:RaidInput()
	input.type = "SET_RAID"
	self:Step(input)
end

-- A new session after a boss kill, when this client is the master looter. info = the ENCOUNTER_ENDED table. Returns
-- the session or nil and a code: "NOT_A_KILL", "NOT_MASTER_LOOTER", "NOT_READY", "NO_SEASON", "SESSION_RUNNING" (an
-- item is still in progress in the previous one), or a SessionFSM.New code.
function SC:OnKill(info)
	if type(info) ~= "table" or not info.success then return nil, "NOT_A_KILL" end
	if not C().Loot.IsMasterLooter() then return nil, "NOT_MASTER_LOOTER" end
	local L, store, ml = self:Ledger(), self:Store(), me()
	if not L or not store or not ml then return nil, "NOT_READY" end
	local season = ns.Season.Current(L)
	if not season then return nil, "NO_SEASON" end
	local old = self:Current()
	if old and old.state ~= "ENDED" then
		if old.active then return nil, "SESSION_RUNNING" end
		if old.state ~= "WAITING" then   -- the ML moved on to the next boss: the last one ends, its pending items listed
			self:Step({ type = "END" })
		end
	end
	local ts, inst = now(), C().Encounter.Instance()
	local raid = ns.AddonCheck and ns.AddonCheck.raid
	local raidInput = ns.AddonCheck and type(raid) == "table" and raid.inRaid and ns.AddonCheck:RaidInput() or {}
	local s, code = F().New({
		id = tostring(season.id) .. "-" .. tostring(info.encounterID) .. "-" .. tostring(C().ServerTime()),
		season = season.id, ml = ml, ts = ts, encounter = info.encounterID,
		rules = ns.Rules.Current(L),
		priceCtx = {
			raidSize = info.groupSize or (inst and inst.maxPlayers) or nil,
			difficulty = ns.Nights and ns.Nights.DifficultyCode(info.difficultyID, inst and inst.difficultyName) or nil,
			lootThreshold = C().Loot.Threshold(),
		},
		present = raidInput.present, addon = raidInput.addon,
	})
	if not s then return nil, code end
	if self.store == nil and ns.Config and ns.Config.IsReadOnly and ns.Config:IsReadOnly() then return nil, "READ_ONLY" end
	if old then self:CarryOver(old) end
	store.session = s
	self.session, self.readOnly, self.held = s, nil, nil
	self:Host()
	log("info", "OPENED", info.encounterID)
	emit("SESSION_STARTED", s)
	self:Refresh()
	return s
end

-- LOOT_COLLECTED: the corpse's items become LOOT_OPENED; during a lockdown they wait. Returns ok, code.
function SC:OnLoot(collection)
	local s = self.session
	if not s or self.readOnly or s.state ~= "WAITING" or type(collection) ~= "table" then
		self:RetryDeliveries()   -- a corpse opened again: items waiting for it can be handed over now
		return nil, "NOT_WAITING"
	end
	if collection.encounter ~= nil and s.encounter ~= nil and collection.encounter ~= s.encounter then
		return nil, "OTHER_ENCOUNTER"
	end
	if SC.Locked() or s.lockdown then
		self.held = collection
		emit("SESSION_HELD", "LOCKDOWN")
		self:Refresh()
		return nil, "LOCKDOWN"
	end
	local input = ns.LootSource.ToInput(collection, now(), s.ml)
	input.encounter = input.encounter or s.encounter
	return self:Step(input)
end

-- SESSION_INPUT from the protocol: a raider's response.
function SC:OnInput(input)
	if type(input) ~= "table" or input.type ~= "RESPONSE" then return end
	self:Step(input)
end

---------------------------------------------------------------------------------------------------------------------
-- What the windows read

-- The session as the windows show it: on the master looter's client { host = true, session }, elsewhere the read-only
-- view of the raid's session { host = false, view } (only for who holds `award.confirm`, the officers: the raiders
-- see their popup). nil when there is nothing to show or the player may not see it.
function SC:View()
	local s = self:Current()
	if s then return { host = true, session = s, readOnly = self.readOnly } end
	local v = ns.Protocol and ns.Protocol.Session.view
	if not v then return nil end
	if ns.PermissionService and not ns.PermissionService:Can("award.confirm") then return nil end
	return { host = false, view = v, readOnly = true }
end

-- The class of a raid member as the roster knows it ("WARRIOR", ...), for the colour of a name; nil when unknown.
function SC:ClassOf(name)
	local L, season = self:Ledger(), nil
	if not L or not ns.Season or not ns.Roster then return nil end
	season = ns.Season.Current(L)
	if not season then return nil end
	if self.classCache == nil or self.classCacheSeason ~= season.id or self.classCacheAt ~= ns.Ledger.Count(L) then
		local map = {}
		for _, m in ipairs(ns.Roster.List(L, season.id, {})) do map[m.member] = m.class end
		self.classCache, self.classCacheSeason, self.classCacheAt = map, season.id, ns.Ledger.Count(L)
	end
	return self.classCache[name]
end

-- The board of the master looter's window (App/SessionBoard.lua): the session (or the read-only view) as plain data.
-- `selected` is the item index the window shows (nil: the one in progress). nil when there is nothing to show.
function SC:Board(selected)
	local view = self:View()
	if not view then return nil end
	local s = view.session
	return ns.SessionBoard.Build(view, {
		now = now(), held = self.held ~= nil, classOf = function(name) return self:ClassOf(name) end,
		rollSeconds = (s and s.rules and s.rules.session and s.rules.session.rollSeconds)
			or (ns.Rules and ns.Rules.DefaultConfig().session.rollSeconds),
	}, selected)
end

-- What MODIFY{change} would give (the Modify dialog's live difference from the rules); nothing is changed. Returns the
-- board proposal, or nil and the code the state machine would answer.
function SC:PreviewModify(change)
	local s = self:Current()
	if not s or self.readOnly then return nil, "NO_SESSION" end
	if type(change) ~= "table" then return nil, "UNKNOWN_INPUT" end
	local copy = {}
	for k, v in pairs(change) do copy[k] = v end
	copy.reason = copy.reason or "OTHER"   -- the reason is mandatory in the real input; the preview only shows the effect
	return ns.SessionBoard.Preview(s, copy, now(), me())
end

---------------------------------------------------------------------------------------------------------------------
-- Wiring

if ns.Bus then
	ns.Bus:On("ENCOUNTER_ENDED", function(_, info) SC:OnKill(info) end, SC)
	ns.Bus:On("LOOT_COLLECTED", function(_, collection) SC:OnLoot(collection) end, SC)
	ns.Bus:On("SESSION_INPUT", function(_, input) SC:OnInput(input) end, SC)
	ns.Bus:On("LOOT_RECEIVED", function(_, entry) SC:OnLootReceived(entry) end, SC)
	ns.Bus:On("TRADE_COMPLETED", function(_, info) SC:OnTradeCompleted(info) end, SC)
	ns.Bus:On("GROUP_SCANNED", function() SC:SyncRaid() end, SC)
	ns.Bus:On("ADDON_CHECK_CHANGED", function() SC:SyncRaid() end, SC)
	ns.Bus:On("GUILD_KEY_CHANGED", function()
		if SC.store == nil then
			SC:Reset()
			SC.bound = true
			SC:Resume()
		end
	end, SC)
end

if ns.addon then
	ns.addon.SessionController = SC   -- also reachable from tests
	if CreateFrame then
		local frame = CreateFrame("Frame")
		for _, e in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END", "ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_REGEN_ENABLED" }) do
			pcall(frame.RegisterEvent, frame, e)
		end
		frame:SetScript("OnEvent", function() SC:Refresh() end)
	end
	if ns.addon.AddDebugSection then
		ns.addon:AddDebugSection("Session", function()
			local s = SC.session
			return { ("Session: %s"):format(s and (tostring(s.state) .. ", " .. #s.items .. " items") or "none") }   -- nolocale (debug output)
		end)
	end
end
