-- SessionFSM: the loot session state machine (docs/ANALISI.md §3.4, §4, §4.1). Pure Lua 5.1: it never calls the game.
--
-- A session is one plain-data table (strings, numbers, booleans, tables): it is saved as it is in the SavedVariables
-- at every step, so a /reload or a disconnection resumes exactly where the master looter was (§4). The domain never
-- reads the clock: every input carries `ts` (the caller's time, seconds) and the timers are absolute deadlines that a
-- TICK input checks.
--
-- SessionFSM.Step(session, input, env) is the only way to change a session: it applies one input and then the
-- automatic phases (session.autoAdvance, session.awardMode "auto"), and returns ok, code, effects. A refused input
-- changes nothing. `effects` is a list of { type = code, ... } for the adapter (send the announcement, open the popup,
-- call GiveMasterLoot, ...): the session itself never acts.
--
-- The states (§4 diagram):
--   WAITING     after ENCOUNTER_END; LOOT_OPENED (the master looter opens the corpse) moves on, never during a chat
--               lockdown or a boss (LOCKDOWN{active})
--   COLLECTING  the items above the threshold with their proposed category and cost; the ML corrects them
--               (CORRECT_ITEM, REMOVE_ITEM) and starts the session (START)
--   ANNOUNCING  categories and costs went to the raid; between two items. OPEN_ROLL opens the roll of an item
--   ROLLING     a round is open: the first round of an item also collects the responses (RESPONSE); every round
--               collects rolls (ROLL). It closes on its timer or when everybody has rolled (autoAdvance) or by the ML
--               (CLOSE_ROUND)
--   COMPUTING   Domain/Priority.lua replays the rounds held so far and asks for the next one (a reroll among the
--               tied, the next tier, a free roll): autoAdvance opens it, otherwise the ML does (ADVANCE)
--   PROPOSAL    who, how much and why, written by the addon. CONFIRM writes ITEM_AWARDED in the ledger; REJECT puts the
--               item back (PENDING, REOPEN, NEXT_TIER, BANK, DISENCHANT); MODIFY changes the winner and/or the cost
--               with a mandatory reason code and comes back to PROPOSAL, flagged as an intervention
--   ENDED       END; deliveries are still recorded after the end (delayed delivery by trade, §4)
-- Item states: PENDING, ROLLING, COMPUTING, PROPOSAL, ASSIGNED (credits charged, ITEM_AWARDED written), DELIVERED
-- (GiveMasterLoot or a trade confirmed by CHAT_MSG_LOOT: DELIVERED input). PAUSE / RESUME stop and restart every
-- automatic phase (timers, auto-advance, the "auto" award window); the ML's own commands still work while paused.
--
-- §4.1: only raiders with the addon active roll. The raid (present, addon) is frozen on the item when its roll opens,
-- so a player who installs the addon and reloads comes back from the next item; a roll from a player without the
-- addon is kept in the round and Priority discards it as NO_ADDON (the ML sees it); a response from them is refused.
-- Credits are frozen on the item when its roll opens too (the ledger's credits of the season), so the result is the
-- one the raid rolled against and a resumed session computes the same thing. One item is in progress at a time:
-- the next roll opens only after the previous item is assigned, so its winner's credits are already charged.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local FSM = {}
ns.SessionFSM, ns.modules.SessionFSM = FSM, FSM

local type, pairs, ipairs, tostring, next = type, pairs, ipairs, tostring, next
local floor, sort, huge = math.floor, table.sort, math.huge

FSM.SCHEMA = 1
FSM.MAX_NOTE = 80   -- bytes of a response's note (the protocol's limit too)

FSM.STATES = { "WAITING", "COLLECTING", "ANNOUNCING", "ROLLING", "COMPUTING", "PROPOSAL", "ENDED" }
FSM.ITEM_STATES = { "PENDING", "ROLLING", "COMPUTING", "PROPOSAL", "ASSIGNED", "DELIVERED" }

-- The reason codes the master looter (or the council through the ML) gives when the result departs from the rule or an
-- item is corrected (§3.4, §3.6). Codes, never sentences: the locales give the words (M2-7).
FSM.ML_REASONS = {
	WRONG_CATEGORY = true,   -- the category or the cost was wrong (before the roll)
	COUNCIL_COST = true,     -- the council prices the item (an orange, a "council" cell)
	OBVIOUS_WASTE = true,    -- "spreco palese": another candidate instead of the first in line
	PASSED_TO_GAME = true,   -- "passa per fare il furbo": to a player who did not roll, full cost
	COUNCIL_VOTE = true,     -- the council's vote (awardMode "council")
	LEGENDARY = true,        -- a legendary chain piece
	MISTAKE = true,          -- a mistake by the ML or the addon
	OTHER = true,
}

-- What happens to a rejected item (§3.4 "Rifiuta").
FSM.REJECT_THEN = { PENDING = true, REOPEN = true, NEXT_TIER = true, BANK = true, DISENCHANT = true }

-- Proposal flags that do not stop an automatic award: everything else needs the ML.
FSM.INFO_FLAGS = { DISCARDED_ROLLS = true }

-- The inputs only the session's master looter may give.
local ML_ONLY = {
	CORRECT_ITEM = true, REMOVE_ITEM = true, START = true, OPEN_ROLL = true, CLOSE_ROUND = true, ADVANCE = true,
	CONFIRM = true, REJECT = true, MODIFY = true, CLOSE_VOTE = true, PAUSE = true, RESUME = true, END = true,
	DELIVERY = true,
}

-- The inputs that are not written in the session's log (frequent, and already visible in the rounds).
local QUIET = { ROLL = true, RESPONSE = true, TICK = true, SET_RAID = true, LOCKDOWN = true }

local MAX_AUTO_STEPS = 64

---------------------------------------------------------------------------------------------------------------------
-- Helpers

local function isName(s) return type(s) == "string" and s ~= "" and not s:find(":", 1, true) end
local function isCode(s) return type(s) == "string" and s:match("^[A-Z][A-Z0-9_]*$") ~= nil end
local function isNum(n) return type(n) == "number" and n == n and n > -huge and n < huge end
local function isInt(n) return isNum(n) and n == floor(n) end

local function copy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = copy(x) end
	return c
end
FSM.Copy = copy

local function sortedKeys(set)
	local list = {}
	for k in pairs(set) do list[#list + 1] = k end
	sort(list)
	return list
end

local function Rules() return ns.Rules end
local function Priority() return ns.Priority end
local function Pricing() return ns.Pricing end
local function Ledger() return ns.Ledger end

local function sessionRules(s) return s.rules.session end
local function priorityRules(s) return s.rules.priority end

local function log(s, entry)
	s.log[#s.log + 1] = entry
end

local function fx(effects, e)
	effects[#effects + 1] = e
end

-- The enabled responses of the priority rules: { [code] = tier }.
local function responseTiers(s)
	local out = {}
	for code, r in pairs(type(priorityRules(s).responses) == "table" and priorityRules(s).responses or {}) do
		if type(r) == "table" and type(r.tier) == "number" and r.enabled ~= false then out[code] = r.tier end
	end
	return out
end

local function firstTier(s)
	local best
	for _, t in pairs(responseTiers(s)) do
		if best == nil or t < best then best = t end
	end
	return best
end

-- The response with the lowest tier (the "full cost" response, MS in the preset).
local function fullCostResponse(s)
	local best, bestTier
	for code, t in pairs(responseTiers(s)) do
		if bestTier == nil or t < bestTier or (t == bestTier and code < best) then best, bestTier = code, t end
	end
	return best
end

local function current(s)
	return s.active and s.items[s.active] or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Items and prices

-- Prices an item for every response of the cost rules. Returns the Pricing.Base table and { [response] = cost|nil }.
local function priceItem(s, item)
	local cost = s.rules.cost
	if type(item.override) == "table" and item.itemID then
		cost = copy(cost)
		cost.overrides = cost.overrides or {}
		cost.overrides[item.itemID] = copy(item.override)
	end
	local base = Pricing().Base(item.info, cost, s.priceCtx)
	local costs = {}
	if base.tracked then
		for response in pairs(type(cost.responseMultiplier) == "table" and cost.responseMultiplier or {}) do
			costs[response] = Pricing().Price(item.info, response, cost, s.priceCtx).cost
		end
	end
	return base, costs
end

local function reprice(s, item)
	local base, costs = priceItem(s, item)
	item.category, item.council, item.costs = base.category, base.council == true or nil, costs
	item.priceSource = base.source
	return base
end

-- An item of LOOT_OPENED: { itemID, slot?, quality, classID?, subclassID?, equipLoc?, startsQuest?, boe? }.
local function newItem(s, raw)
	if type(raw) ~= "table" or not isInt(raw.itemID) or raw.itemID <= 0 then return nil, "item" end
	if raw.slot ~= nil and not isInt(raw.slot) then return nil, "slot" end
	local info = {
		itemID = raw.itemID, quality = raw.quality, classID = raw.classID, subclassID = raw.subclassID,
		equipLoc = raw.equipLoc, startsQuest = raw.startsQuest,
	}
	local item = { itemID = raw.itemID, slot = raw.slot, quality = raw.quality, boe = raw.boe == true or nil,
		info = info, state = "PENDING" }
	local base = reprice(s, item)
	if not base.tracked then return nil, "NOT_TRACKED" end
	return item
end

---------------------------------------------------------------------------------------------------------------------
-- Rounds and the award algorithm

local function eligible(s, item, player)
	if type(item.present) == "table" and item.present[player] ~= true then return false, "NOT_PRESENT" end
	if priorityRules(s).requireAddon and type(item.addon) == "table" and item.addon[player] ~= true then
		return false, "NO_ADDON"
	end
	return true
end

-- The priority rules for an item: the tiers skipped after a "next tier" reject are disabled.
local function priorityConfig(s, item)
	local config = priorityRules(s)
	if type(item.skipTiers) ~= "table" or next(item.skipTiers) == nil then return config end
	config = copy(config)
	for _, r in pairs(config.responses or {}) do
		if type(r) == "table" and item.skipTiers[r.tier] then r.enabled = false end
	end
	return config
end

local function evaluate(s, item)
	return Priority().Evaluate({
		responses = item.responses, rounds = item.rounds, credits = item.credits, nights = item.nights,
		present = item.present, addon = item.addon, boe = item.boe, costs = item.costs,
	}, priorityConfig(s, item))
end

local function newRound(s, kind, stage, tier, among, now, collect)
	local seconds = sessionRules(s).rollSeconds
	if type(seconds) ~= "number" then seconds = 30 end
	return { kind = kind, stage = stage, tier = tier, among = copy(among), collect = collect or nil, rolls = {},
		openedAt = now, deadline = now + seconds }
end

local function openRound(s, index, round, effects)
	local item = s.items[index]
	item.round = round
	item.next = nil
	item.state = "ROLLING"
	s.state = "ROLLING"
	if s.paused then
		round.remaining = round.deadline - round.openedAt
		round.deadline = nil
	end
	fx(effects, { type = "OPEN_ROUND", item = index, kind = round.kind, stage = round.stage, tier = round.tier,
		among = copy(round.among), collect = round.collect, deadline = round.deadline })
end

-- Opens the roll of an item: freezes the raid and the credits, opens the first round, which collects the responses.
local function openItem(s, index, now, env, effects)
	local item = s.items[index]
	item.opened = true
	item.hold = nil
	item.present = copy(s.raid.present)
	item.addon = copy(s.raid.addon)
	local credits = env.credits
	if type(credits) ~= "table" and env.ledger and Ledger() then credits = Ledger().Credits(env.ledger, s.season) end
	item.credits = copy(type(credits) == "table" and credits or {})
	item.nights = copy(type(env.nights) == "table" and env.nights or nil)
	item.responses, item.rounds, item.proposal, item.rule = {}, {}, nil, nil
	item.labels, item.notes, item.verdicts, item.equipped = nil, nil, nil, nil
	item.discarded, item.history, item.dropped, item.votes, item.voteClosed = nil, nil, nil, nil, nil
	item.intervention, item.autoAt, item.autoRemaining = nil, nil, nil
	s.active = index
	openRound(s, index, newRound(s, "ROLL", "TIER", firstTier(s), nil, now, true), effects)
end

-- True when every eligible player has done what the open round asks: in the first round, a response from everyone and a
-- roll from everyone whose response belongs to the round's tier; in the others, a roll from every player of `among`.
-- Unknown presence (no raid snapshot): never, the round waits for its timer or the ML.
local function allRolled(s, item)
	local round = item.round
	local cfg = priorityRules(s)
	local rollMin, rollMax = cfg.rollMin or 1, cfg.rollMax or 100
	local rolled = {}
	for _, r in ipairs(round.rolls) do
		if r.min == rollMin and r.max == rollMax then rolled[r.player] = true end
	end
	if round.among ~= nil then
		for _, p in ipairs(round.among) do
			if not rolled[p] then return false end
		end
		return true
	end
	if type(item.present) ~= "table" then return false end
	local tiers = responseTiers(s)
	for _, p in ipairs(sortedKeys(item.present)) do
		if eligible(s, item, p) then
			if round.collect then
				local response = item.responses[p]
				if response == nil then return false end
				if tiers[response] == round.tier and not rolled[p] then return false end
			elseif not rolled[p] then
				return false
			end
		end
	end
	return true
end

local function hasBlockingFlag(flags)
	for _, f in ipairs(flags or {}) do
		if not FSM.INFO_FLAGS[f] then return true end
	end
	return false
end

-- A proposal the addon may write without the ML: a winner, a cost, no flag that needs a look.
local function ready(p)
	return type(p) == "table" and p.winner ~= nil and p.cost ~= nil and not hasBlockingFlag(p.flags)
end
FSM.Ready = ready

local function setProposal(s, index, proposal, now, effects)
	local item = s.items[index]
	proposal = copy(proposal)
	proposal.flags = proposal.flags or {}
	proposal.reasons = proposal.reasons or {}
	if item.rejected and #item.rejected > 0 then proposal.flags[#proposal.flags + 1] = "AFTER_REJECT" end
	item.proposal = proposal
	item.rule = { kind = proposal.kind, winner = proposal.winner, cost = proposal.cost }
	item.intervention, item.votes, item.voteClosed, item.vote = nil, nil, nil, nil
	item.autoAt, item.autoRemaining = nil, nil
	item.state = "PROPOSAL"
	s.state = "PROPOSAL"
	local session = sessionRules(s)
	if session.awardMode == "auto" and ready(proposal) then
		local wait = type(session.interventionSeconds) == "number" and session.interventionSeconds or 0
		if s.paused then item.autoRemaining = wait else item.autoAt = now + wait end
	elseif session.awardMode == "council" then
		item.votes = {}
	end
	fx(effects, { type = "PROPOSAL", item = index, autoAt = item.autoAt })
end

-- Applies the result of Priority.Evaluate: the proposal, or the next round to hold.
local function applyResult(s, index, res, now, effects)
	local item = s.items[index]
	item.discarded, item.history = res.discarded, res.history
	if res.status == "PROPOSAL" then
		setProposal(s, index, res.proposal, now, effects)
		return
	end
	item.next = { kind = res.status, stage = res.stage, tier = res.tier, among = copy(res.among) }
	item.state = "COMPUTING"
	s.state = "COMPUTING"
	fx(effects, { type = "NEXT_ROUND", item = index, kind = res.status, stage = res.stage, tier = res.tier,
		among = copy(res.among) })
end

-- Closes the open round and computes. The first round of an item becomes Priority's first round only when Priority
-- asks for that tier first; otherwise (nobody of that tier can roll) its rolls are dropped, with the code TIER_EMPTY.
local function closeRound(s, index, now, effects)
	local item = s.items[index]
	local round = item.round
	item.round = nil
	round.closedAt = now
	round.deadline, round.remaining = nil, nil
	fx(effects, { type = "CLOSE_ROUND", item = index })
	local res
	if round.collect then
		round.collect = nil
		res = evaluate(s, item)
		if res.status ~= "PROPOSAL" and res.stage == "TIER" and res.tier == round.tier then
			item.rounds[#item.rounds + 1] = round
			res = evaluate(s, item)
		else
			item.dropped = { rolls = round.rolls, code = "TIER_EMPTY" }
		end
	else
		item.rounds[#item.rounds + 1] = round
		res = evaluate(s, item)
	end
	applyResult(s, index, res, now, effects)
end

local function advance(s, index, now, effects)
	local item = s.items[index]
	local n = item.next
	openRound(s, index, newRound(s, n.kind, n.stage, n.tier, n.among, now, false), effects)
end

---------------------------------------------------------------------------------------------------------------------
-- The award

local function targetOf(p)
	if p.target then return p.target end
	if p.kind == "BANK" then return "bank" end
	if p.kind == "DISENCHANT" then return "disenchant" end
	return "member"
end

-- Writes ITEM_AWARDED and assigns the item. Returns true, or nil and a code (nothing changed).
local function confirm(s, index, now, env, effects, auto)
	local item = s.items[index]
	local p = item.proposal
	if p.winner == nil then return nil, "NO_WINNER" end
	if p.cost == nil then return nil, "NO_COST" end
	if not env.ledger then return nil, "NO_LEDGER" end
	local payload = {
		target = targetOf(p), member = p.winner, item = item.itemID, cost = p.cost, response = p.response,
		tier = p.tier, roll = p.roll, reroll = p.reroll, credits = p.credits,
		reasons = copy(p.reasons), flags = copy(p.flags), rivals = copy(p.rivals),
		session = s.id, encounter = s.encounter,
		auto = auto or nil,
	}
	if item.intervention then
		payload.intervention = true
		payload.mlReason = item.intervention.reason
		payload.ruleWinner = item.rule.winner
		payload.ruleCost = item.rule.cost
	end
	if item.vote then payload.votes = copy(item.vote.tally) end
	local e, code = Ledger().Append(env.ledger, {
		author = s.ml, ts = now, season = s.season, type = "ITEM_AWARDED", payload = payload,
	}, env.opts)
	if not e then return nil, code end
	item.award = { event = e.id, member = p.winner, target = payload.target, cost = p.cost, ts = now }
	item.state = "ASSIGNED"
	item.autoAt, item.autoRemaining = nil, nil
	s.active = nil
	s.state = "ANNOUNCING"
	log(s, { ts = now, type = auto and "AUTO_CONFIRM" or "CONFIRM", by = s.ml, item = index, event = e.id })
	fx(effects, { type = "AWARDED", item = index, event = e.id, winner = p.winner, target = payload.target,
		cost = p.cost })
	fx(effects, { type = "DELIVER", item = index, slot = item.slot, winner = p.winner, target = payload.target })
	return true
end

-- The cost of an item for a player chosen by the ML: the cost of their response, or the full cost when they did not
-- answer (or passed): "assegnare d'ufficio a chi non ha rollato, con il costo pieno" (§3.6).
local function costFor(s, item, player)
	local response = item.responses and item.responses[player] or nil
	if response ~= nil and responseTiers(s)[response] ~= nil then return item.costs[response], response end
	return item.costs[fullCostResponse(s)], nil
end

-- Changes the proposal (the ML, or the council's vote): returns true, or nil and a code.
local function modify(s, index, by, now, change, effects)
	local item = s.items[index]
	local p = item.proposal
	local winner, cost, target = p.winner, p.cost, targetOf(p)
	local response, tier, roll, reasons = p.response, p.tier, p.roll, copy(p.reasons)
	local winnerChanged = change.winner ~= nil and change.winner ~= p.winner
	if winnerChanged or (change.target ~= nil and change.target ~= target) then
		target = change.target or "member"
		winner = change.winner
		if winner == nil and target ~= "member" then
			local cfg = priorityRules(s)
			winner = target == "bank" and cfg.bankCharacter or cfg.disenchanter
			if type(winner) ~= "string" or winner == "" then winner = nil end
		end
		if winner == nil then winner = p.winner end
		winnerChanged = winner ~= p.winner
		if target == "member" then
			cost, response = costFor(s, item, winner)
			tier = response and responseTiers(s)[response] or nil
		else
			cost, response, tier = 0, nil, nil
		end
		roll, reasons = nil, { "ML_CHOICE" }
	end
	if change.cost ~= nil then cost = change.cost end
	if winner == nil then return nil, "NO_WINNER" end

	local flags = {}
	for _, f in ipairs(p.flags) do
		if f ~= "OUT_OF_ORDER" and f ~= "COST_CHANGED" and f ~= "ML_DECIDED" then flags[#flags + 1] = f end
	end
	local rule = item.rule
	if rule.winner ~= nil and (winner ~= rule.winner or target ~= targetOf(rule)) then
		flags[#flags + 1] = "OUT_OF_ORDER"
	end
	if rule.cost ~= nil and cost ~= rule.cost then flags[#flags + 1] = "COST_CHANGED" end
	if rule.winner == nil or rule.cost == nil then flags[#flags + 1] = "ML_DECIDED" end

	local kind = p.kind
	if target == "bank" then kind = "BANK" elseif target == "disenchant" then kind = "DISENCHANT"
	elseif winnerChanged or kind ~= "AWARD" then kind = "AWARD" end
	item.proposal = {
		kind = kind, target = target, winner = winner, cost = cost, response = response, tier = tier, roll = roll,
		reroll = not winnerChanged and p.reroll or nil, credits = item.credits[winner] or 0,
		rivals = copy(p.rivals), reasons = reasons, flags = flags,
	}
	item.intervention = { by = by, ts = now, reason = change.reason }
	item.autoAt, item.autoRemaining = nil, nil
	if item.votes then item.voteClosed = true end
	fx(effects, { type = "PROPOSAL", item = index, modified = true })
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The automatic phases (session.autoAdvance, awardMode "auto"): run after every accepted input.

local function nextPending(s, includeHeld)
	for i, item in ipairs(s.items) do
		if item.state == "PENDING" and (includeHeld or not item.hold) then return i end
	end
	return nil
end

local function settle(s, now, env, effects)
	for _ = 1, MAX_AUTO_STEPS do
		if s.paused or s.state == "ENDED" then return end
		local auto = sessionRules(s).autoAdvance
		local item = current(s)
		if s.state == "ROLLING" then
			local round = item.round
			local expired = round.deadline ~= nil and now >= round.deadline
			if auto and (expired or allRolled(s, item)) then
				log(s, { ts = now, type = "AUTO_CLOSE", item = s.active, code = expired and "TIMER" or "ALL_ROLLED" })
				closeRound(s, s.active, now, effects)
			else
				if expired and not round.expired then
					round.expired = true
					fx(effects, { type = "TIMER_EXPIRED", item = s.active })
				end
				return
			end
		elseif s.state == "COMPUTING" then
			if not auto then return end
			log(s, { ts = now, type = "AUTO_ADVANCE", item = s.active })
			advance(s, s.active, now, effects)
		elseif s.state == "PROPOSAL" then
			if not (item.autoAt and now >= item.autoAt and ready(item.proposal) and not item.intervention) then return end
			local ok, code = confirm(s, s.active, now, env, effects, true)
			if not ok then
				item.autoAt = nil
				fx(effects, { type = "AUTO_FAILED", item = s.active, code = code })
				return
			end
		elseif s.state == "ANNOUNCING" then
			local index = auto and nextPending(s, false) or nil
			if not index then return end
			log(s, { ts = now, type = "AUTO_OPEN", item = index })
			openItem(s, index, now, env, effects)
		else
			return
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- The inputs

local H = {}

local function needState(s, ...)
	for i = 1, select("#", ...) do
		if s.state == select(i, ...) then return true end
	end
	return false
end

local function itemAt(s, index)
	if not isInt(index) then return nil end
	return s.items[index]
end

-- LOCKDOWN{active}: the chat lockdown or a boss encounter is on (the session waits).
function H.LOCKDOWN(s, input)
	if type(input.active) ~= "boolean" then return nil, "active" end
	s.lockdown = input.active
	return true
end

-- SET_RAID{present, addon}: who is in the raid and who has a compatible addon ({[player] = true}, nil = not known).
-- It applies to the items whose roll opens later (§4.1: "rientra dal pezzo dopo").
function H.SET_RAID(s, input)
	if s.state == "ENDED" then return nil, "ENDED" end
	if input.present ~= nil and type(input.present) ~= "table" then return nil, "present" end
	if input.addon ~= nil and type(input.addon) ~= "table" then return nil, "addon" end
	s.raid = { present = copy(input.present), addon = copy(input.addon) }
	return true
end

-- LOOT_OPENED{items = {...}, encounter?}: the ML opened the corpse; the items below the threshold are left out.
function H.LOOT_OPENED(s, input, env, effects)
	if s.state ~= "WAITING" then return nil, "BAD_STATE" end
	if s.lockdown then return nil, "LOCKDOWN" end
	if type(input.items) ~= "table" then return nil, "items" end
	local items, skipped = {}, {}
	for _, raw in ipairs(input.items) do
		local item, code = newItem(s, raw)
		if item then
			items[#items + 1] = item
		elseif code == "NOT_TRACKED" then
			skipped[#skipped + 1] = raw.itemID
		else
			return nil, code
		end
	end
	s.items, s.skipped = items, skipped
	if isInt(input.encounter) then s.encounter = input.encounter end
	s.state = "COLLECTING"
	fx(effects, { type = "COLLECTED", count = #items, skipped = copy(skipped) })
	return true
end

-- CORRECT_ITEM{index, category?, cost?, reason}: the ML (for the council) corrects an item before its roll opens
-- (session.lockCategoryOnOpen); `cost` is the base cost (the response multipliers still apply).
function H.CORRECT_ITEM(s, input, env, effects)
	if not needState(s, "COLLECTING", "ANNOUNCING", "ROLLING", "COMPUTING", "PROPOSAL") then return nil, "BAD_STATE" end
	local item = itemAt(s, input.index)
	if not item then return nil, "index" end
	if not FSM.ML_REASONS[input.reason] then return nil, "REASON_REQUIRED" end
	if item.state == "PROPOSAL" or item.state == "ASSIGNED" or item.state == "DELIVERED" then
		return nil, "ITEM_SETTLED"
	end
	if item.opened and sessionRules(s).lockCategoryOnOpen then return nil, "CATEGORY_LOCKED" end
	if input.category == nil and input.cost == nil then return nil, "NOTHING_CHANGED" end
	if input.category ~= nil and not ns.Classifier.IsCategory(input.category) then return nil, "category" end
	if input.cost ~= nil and (not isNum(input.cost) or input.cost < 0) then return nil, "cost" end
	local override = {}
	if input.cost ~= nil then override.cost = input.cost else override.category = input.category end
	item.override = override
	reprice(s, item)
	item.corrections = item.corrections or {}
	item.corrections[#item.corrections + 1] = { ts = input.ts, by = input.by, category = input.category,
		cost = input.cost, reason = input.reason }
	fx(effects, { type = "ITEM_CORRECTED", item = input.index, category = item.category, costs = copy(item.costs) })
	return true
end

-- REMOVE_ITEM{index}: the ML takes an item off the list before the session starts.
function H.REMOVE_ITEM(s, input)
	if s.state ~= "COLLECTING" then return nil, "BAD_STATE" end
	if not itemAt(s, input.index) then return nil, "index" end
	table.remove(s.items, input.index)
	return true
end

-- START: "Avvia sessione": the categories and costs go to the raid.
function H.START(s, input, env, effects)
	if s.state ~= "COLLECTING" then return nil, "BAD_STATE" end
	s.state = "ANNOUNCING"
	s.startedAt = input.ts
	local list = {}
	for i, item in ipairs(s.items) do
		list[i] = { item = i, itemID = item.itemID, category = item.category, costs = copy(item.costs),
			council = item.council }
	end
	fx(effects, { type = "ANNOUNCE_ITEMS", items = list })
	-- §4.1: "3 membri del raid non possono rollare", with the /raid reminder at hand.
	if type(s.raid.present) == "table" and type(s.raid.addon) == "table" and priorityRules(s).requireAddon then
		local missing = {}
		for _, p in ipairs(sortedKeys(s.raid.present)) do
			if s.raid.present[p] == true and s.raid.addon[p] ~= true then missing[#missing + 1] = p end
		end
		if #missing > 0 then fx(effects, { type = "NO_ADDON", players = missing }) end
	end
	return true
end

-- OPEN_ROLL{index?}: the ML opens the roll of an item (the first pending one by default).
function H.OPEN_ROLL(s, input, env, effects)
	if s.state ~= "ANNOUNCING" then
		if s.active then return nil, "ITEM_IN_PROGRESS" end
		return nil, "BAD_STATE"
	end
	local index = input.index
	if index == nil then index = nextPending(s, true) end
	local item = itemAt(s, index)
	if not item then return nil, "index" end
	if item.state ~= "PENDING" then return nil, "ITEM_NOT_PENDING" end
	openItem(s, index, input.ts, env, effects)
	return true
end

-- RESPONSE{player, response, label?, note?}: a raider's answer (MS, OS, ..., PASS), during the first round of the item
-- only, with the optional label (a code: BIS, BIG_UPGRADE ...; informative, never read by the rules, §3.3) and note
-- (at most FSM.MAX_NOTE bytes). The latest answer replaces the earlier one, label and note included; it cannot change
-- after the player rolled in that round. A label or a note that is not valid is dropped, the response still counts; a
-- pass carries neither. `verdict` ({ m, o? }: the upgrade verdicts of main-spec and off-spec, UpgradeScore.Pack) and
-- `equipped` (a list of "item:..." strings) are what the raider's client says about the piece (§5.1, M5-2): kept as given
-- for the master looter's table, a pass keeps them too (the "upgrade ignored" flag of M5-4 needs them), the rules never
-- read them.
function H.RESPONSE(s, input)
	local item = current(s)
	if s.state ~= "ROLLING" or not item.round.collect then return nil, "RESPONSES_CLOSED" end
	if not isName(input.player) then return nil, "player" end
	local response = input.response
	if response ~= "PASS" and responseTiers(s)[response] == nil then return nil, "BAD_RESPONSE" end
	local ok, code = eligible(s, item, input.player)
	if not ok then return nil, code end
	if item.responses[input.player] ~= nil then
		for _, r in ipairs(item.round.rolls) do
			if r.player == input.player then return nil, "RESPONSE_LOCKED" end
		end
	end
	item.responses[input.player] = response
	local label, note = input.label, input.note
	if response == "PASS" or type(label) ~= "string" or #label > 32 or not label:find("^[A-Z][A-Z0-9_]*$") then label = nil end
	if response == "PASS" or type(note) ~= "string" or note == "" or #note > FSM.MAX_NOTE then note = nil end
	item.labels, item.notes = item.labels or {}, item.notes or {}
	item.labels[input.player], item.notes[input.player] = label, note
	local verdict, equipped = input.verdict, input.equipped
	if type(verdict) ~= "table" or type(verdict.m) ~= "table" then verdict = nil end
	if type(equipped) ~= "table" or #equipped == 0 then equipped = nil end
	item.verdicts, item.equipped = item.verdicts or {}, item.equipped or {}
	item.verdicts[input.player], item.equipped[input.player] = copy(verdict), copy(equipped)
	return true
end

-- ROLL{player, value, min, max}: a /roll seen in the chat while a round is open. Every roll is kept: Priority decides
-- which are valid and lists the others with a code (NO_ADDON, NOT_1_100, DUPLICATE, ...), so the ML sees them.
function H.ROLL(s, input)
	local item = current(s)
	if s.state ~= "ROLLING" then return nil, "NO_ROUND_OPEN" end
	if not isName(input.player) then return nil, "player" end
	if not isNum(input.value) or not isNum(input.min) or not isNum(input.max) then return nil, "value" end
	local rolls = item.round.rolls
	rolls[#rolls + 1] = { player = input.player, value = input.value, min = input.min, max = input.max, ts = input.ts }
	return true
end

-- CLOSE_ROUND: the ML closes the open round now.
function H.CLOSE_ROUND(s, input, env, effects)
	if s.state ~= "ROLLING" then return nil, "BAD_STATE" end
	closeRound(s, s.active, input.ts, effects)
	return true
end

-- ADVANCE: the ML opens the round Priority asked for (a reroll, the next tier, a free roll).
function H.ADVANCE(s, input, env, effects)
	if s.state ~= "COMPUTING" then return nil, "BAD_STATE" end
	advance(s, s.active, input.ts, effects)
	return true
end

-- CONFIRM: the ML confirms the proposal: ITEM_AWARDED is written (env.ledger, env.opts = the trust gate).
function H.CONFIRM(s, input, env, effects)
	if s.state ~= "PROPOSAL" then return nil, "BAD_STATE" end
	local item = current(s)
	if sessionRules(s).awardMode == "council" and not item.voteClosed then return nil, "VOTE_OPEN" end
	return confirm(s, s.active, input.ts, env, effects, false)
end

-- REJECT{then?, reason?}: no charge; the item goes back: PENDING (the ML reopens it later; the default), REOPEN (a
-- fresh roll now), NEXT_TIER (the tiers up to the proposal's are skipped), BANK or DISENCHANT (the fallback).
function H.REJECT(s, input, env, effects)
	if s.state ~= "PROPOSAL" then return nil, "BAD_STATE" end
	local thenWhat = input["then"] or "PENDING"
	if not FSM.REJECT_THEN[thenWhat] then return nil, "then" end
	if input.reason ~= nil and not FSM.ML_REASONS[input.reason] then return nil, "reason" end
	local index, item = s.active, current(s)
	local p = item.proposal
	if thenWhat == "NEXT_TIER" and type(p.tier) ~= "number" then return nil, "NO_TIER" end
	item.rejected = item.rejected or {}
	item.rejected[#item.rejected + 1] = { ts = input.ts, winner = p.winner, cost = p.cost, kind = p.kind,
		["then"] = thenWhat, reason = input.reason }
	fx(effects, { type = "REJECTED", item = index, ["then"] = thenWhat })
	local now = input.ts
	if thenWhat == "PENDING" or thenWhat == "REOPEN" then
		item.state, item.proposal, item.rule, item.round, item.next = "PENDING", nil, nil, nil, nil
		item.responses, item.rounds = {}, {}
		item.labels, item.notes, item.verdicts, item.equipped = nil, nil, nil, nil
		item.skipTiers = nil
		item.hold = true
		s.active, s.state = nil, "ANNOUNCING"
		if thenWhat == "REOPEN" then openItem(s, index, now, env, effects) end
	elseif thenWhat == "NEXT_TIER" then
		item.skipTiers = item.skipTiers or {}
		for _, t in pairs(responseTiers(s)) do
			if t <= p.tier then item.skipTiers[t] = true end
		end
		item.rounds, item.proposal, item.rule = {}, nil, nil
		applyResult(s, index, evaluate(s, item), now, effects)
	else
		local cfg = priorityRules(s)
		local who = thenWhat == "BANK" and cfg.bankCharacter or cfg.disenchanter
		if type(who) ~= "string" or who == "" then who = nil end
		local flags = {}
		if who == nil then flags[1] = thenWhat == "BANK" and "NO_BANK_CHARACTER" or "NO_DISENCHANTER" end
		setProposal(s, index, {
			kind = thenWhat, winner = who, cost = 0,
			reasons = { thenWhat == "BANK" and "REJECTED_TO_BANK" or "REJECTED_TO_DISENCHANT" }, flags = flags,
		}, now, effects)
	end
	return true
end

-- MODIFY{winner?, cost?, target?, reason}: the ML changes the winner and/or the cost; the reason code is mandatory.
-- A new winner pays the cost of their own response, or the full cost without one, unless `cost` is given. The
-- proposal is flagged against the rule: OUT_OF_ORDER (another winner than the rule's), COST_CHANGED, ML_DECIDED (the
-- rule had no winner or no cost). It stays a proposal: the ML confirms it.
function H.MODIFY(s, input, env, effects)
	if s.state ~= "PROPOSAL" then return nil, "BAD_STATE" end
	if not FSM.ML_REASONS[input.reason] then return nil, "REASON_REQUIRED" end
	if input.winner ~= nil and not isName(input.winner) then return nil, "winner" end
	if input.cost ~= nil and (not isNum(input.cost) or input.cost < 0) then return nil, "cost" end
	if input.target ~= nil and input.target ~= "member" and input.target ~= "bank" and input.target ~= "disenchant" then
		return nil, "target"
	end
	if input.winner == nil and input.cost == nil and input.target == nil then return nil, "NOTHING_CHANGED" end
	return modify(s, s.active, input.by, input.ts, input, effects)
end

-- VOTE{by, choice}: a council member's vote (awardMode "council"); the adapter checks the council.member permission.
function H.VOTE(s, input)
	if s.state ~= "PROPOSAL" then return nil, "BAD_STATE" end
	local item = current(s)
	if sessionRules(s).awardMode ~= "council" then return nil, "NOT_COUNCIL_MODE" end
	if item.voteClosed then return nil, "VOTE_CLOSED" end
	if not isName(input.by) then return nil, "by" end
	if not isName(input.choice) then return nil, "choice" end
	item.votes[input.by] = input.choice
	return true
end

-- CLOSE_VOTE: the ML closes the council's vote. A strict majority decides; when it is not the rule's winner the
-- proposal changes with the reason COUNCIL_VOTE (flagged OUT_OF_ORDER). A tie or no vote changes nothing: the ML
-- modifies the proposal himself.
function H.CLOSE_VOTE(s, input, env, effects)
	if s.state ~= "PROPOSAL" then return nil, "BAD_STATE" end
	local item = current(s)
	if sessionRules(s).awardMode ~= "council" then return nil, "NOT_COUNCIL_MODE" end
	if item.voteClosed then return nil, "VOTE_CLOSED" end
	local tally = {}
	for _, choice in pairs(item.votes) do tally[choice] = (tally[choice] or 0) + 1 end
	local best, bestN, tie = nil, 0, false
	for _, choice in ipairs(sortedKeys(tally)) do
		if tally[choice] > bestN then best, bestN, tie = choice, tally[choice], false
		elseif tally[choice] == bestN then tie = true end
	end
	if best == nil then return nil, "NO_VOTES" end
	if tie then return nil, "VOTE_TIE" end
	item.vote = { winner = best, tally = tally }
	if best ~= item.proposal.winner then
		local ok, code = modify(s, s.active, input.by, input.ts, { winner = best, reason = "COUNCIL_VOTE" }, effects)
		if not ok then return nil, code end
	end
	item.voteClosed = true
	fx(effects, { type = "VOTE_CLOSED", item = s.active, winner = best })
	return true
end

-- PAUSE / RESUME: every automatic phase stops; the open timer and the auto-award window keep their remaining time.
function H.PAUSE(s, input, env, effects)
	if s.state == "ENDED" then return nil, "ENDED" end
	if s.paused then return nil, "PAUSED" end
	s.paused = true
	local item = current(s)
	if item and item.round and item.round.deadline then
		item.round.remaining = item.round.deadline - input.ts
		if item.round.remaining < 0 then item.round.remaining = 0 end
		item.round.deadline = nil
	end
	if item and item.autoAt then
		item.autoRemaining = item.autoAt - input.ts
		if item.autoRemaining < 0 then item.autoRemaining = 0 end
		item.autoAt = nil
	end
	fx(effects, { type = "PAUSED" })
	return true
end

function H.RESUME(s, input, env, effects)
	if not s.paused then return nil, "NOT_PAUSED" end
	s.paused = false
	local item = current(s)
	if item and item.round and item.round.remaining then
		item.round.deadline = input.ts + item.round.remaining
		item.round.remaining = nil
	end
	if item and item.autoRemaining then
		item.autoAt = input.ts + item.autoRemaining
		item.autoRemaining = nil
	end
	fx(effects, { type = "RESUMED" })
	return true
end

-- TICK: time passes (timers, the auto-award window); the work is done by the automatic phases.
function H.TICK() return true end

-- How an awarded item gets to its winner (M4-7, docs/ANALISI.md §4 "Consegna" and §11 risk 1): by master loot
-- (GiveMasterLoot, the receipt is read in CHAT_MSG_LOOT) or by trade (plan B, and the deferred delivery of a night rolled
-- at the end). The state machine only records where the delivery stands; the game calls are the controller's.
FSM.DELIVERY_METHODS = { MASTER = true, TRADE = true }
-- PENDING: nothing has been handed over yet (a trade to make, or a master loot call that did not go through: `code`
-- says why); GIVEN: GiveMasterLoot was called and the receipt has not been read yet.
FSM.DELIVERY_STATUSES = { PENDING = true, GIVEN = true }
-- How a delivery was seen to end: the loot message of the winner, a completed trade, or the master looter's own word.
FSM.DELIVERED_VIA = { LOOT = true, TRADE = true, MANUAL = true }

-- Who must receive the item of `index`: the winner, or the master looter for an item that goes to a bank or
-- disenchant character nobody is set for (`award.member` is nil then). Nil for an item not awarded.
function FSM.Recipient(s, index)
	local item = type(s) == "table" and type(s.items) == "table" and s.items[index] or nil
	if type(item) ~= "table" or type(item.award) ~= "table" then return nil end
	return item.award.member or s.ml
end

-- DELIVERY{index, method, status, code?, holder?}: where the delivery of an assigned item stands (the controller after
-- a Confirm, a retry, or a loot message that tells who holds the item). `code` is a Reasons DELIVERY code.
function H.DELIVERY(s, input, env, effects)
	local item = itemAt(s, input.index)
	if not item then return nil, "index" end
	if item.state ~= "ASSIGNED" then return nil, "NOT_ASSIGNED" end
	if not FSM.DELIVERY_METHODS[input.method] then return nil, "method" end
	if not FSM.DELIVERY_STATUSES[input.status] then return nil, "status" end
	if input.code ~= nil and not isCode(input.code) then return nil, "code" end
	if input.holder ~= nil and not isName(input.holder) then return nil, "holder" end
	local d = item.delivery or { attempts = 0 }
	d.method, d.status, d.code, d.at = input.method, input.status, input.code, input.ts
	if input.holder ~= nil then d.holder = input.holder end
	if input.status == "GIVEN" then d.attempts = (d.attempts or 0) + 1 end
	item.delivery = d
	fx(effects, { type = "DELIVERY", item = input.index, method = d.method, status = d.status, code = d.code })
	return true
end

-- DELIVERED{index, player, via?}: the item reached its winner (GiveMasterLoot, or a later trade, seen in CHAT_MSG_LOOT
-- or in the trade window, or the master looter's word).
function H.DELIVERED(s, input, env, effects)
	local item = itemAt(s, input.index)
	if not item then return nil, "index" end
	if item.state ~= "ASSIGNED" then return nil, "NOT_ASSIGNED" end
	if item.award.member ~= nil and input.player ~= item.award.member then return nil, "WRONG_PLAYER" end
	item.state = "DELIVERED"
	item.deliveredAt = input.ts
	item.deliveredVia = FSM.DELIVERED_VIA[input.via] and input.via or nil
	fx(effects, { type = "DELIVERED", item = input.index, via = item.deliveredVia })
	return true
end

-- END: the session is over; the items never rolled stay PENDING (listed in the effect), the undelivered ones can
-- still be delivered.
function H.END(s, input, env, effects)
	if s.state == "ENDED" then return nil, "ENDED" end
	if s.active then return nil, "ITEM_IN_PROGRESS" end
	s.state = "ENDED"
	s.endedAt = input.ts
	s.paused = false
	local unrolled, undelivered = {}, {}
	for i, item in ipairs(s.items) do
		if item.state == "PENDING" then unrolled[#unrolled + 1] = i end
		if item.state == "ASSIGNED" then undelivered[#undelivered + 1] = i end
	end
	fx(effects, { type = "ENDED", unrolled = unrolled, undelivered = undelivered })
	return true
end

FSM.INPUTS = sortedKeys(H)

---------------------------------------------------------------------------------------------------------------------
-- The public functions

-- A new session, in WAITING (after ENCOUNTER_END). params = { id, season, ml, ts, encounter?, rules?, priceCtx?,
-- present?, addon? }: `rules` is the whole configuration in force (Domain/Rules.lua; the defaults when nil), frozen on
-- the session; `priceCtx` = { raidSize, difficulty, lootThreshold } for Pricing. Returns the session, or nil and a
-- code ("id", "season", "ml", "ts", "RULES:<code>").
function FSM.New(params)
	if type(params) ~= "table" then return nil, "params" end
	if type(params.id) ~= "string" or params.id == "" then return nil, "id" end
	if not ((type(params.season) == "string" and params.season ~= "") or isInt(params.season)) then
		return nil, "season"
	end
	if not isName(params.ml) then return nil, "ml" end
	if not isNum(params.ts) then return nil, "ts" end
	local rules = Rules().WithDefaults(params.rules)
	local ok, problems = Rules().Validate(rules)
	if not ok then return nil, "RULES:" .. problems[1] end
	return {
		schema = FSM.SCHEMA,
		id = params.id, season = params.season, ml = params.ml, createdAt = params.ts,
		encounter = isInt(params.encounter) and params.encounter or nil,
		rules = { session = copy(rules.session), priority = copy(rules.priority), cost = copy(rules.cost) },
		priceCtx = copy(type(params.priceCtx) == "table" and params.priceCtx or {}),
		raid = { present = copy(params.present), addon = copy(params.addon) },
		state = "WAITING", paused = false, lockdown = false,
		items = {}, skipped = {}, active = nil, log = {},
	}
end

-- Adopts a saved session (after /reload). Returns the session and `readOnly` (written by a newer addon: Step refuses
-- every input), or nil and "session".
function FSM.Restore(t)
	if type(t) ~= "table" or type(t.items) ~= "table" or type(t.rules) ~= "table" then return nil, "session" end
	t.log = t.log or {}
	t.raid = t.raid or {}
	return t, (t.schema or 0) > FSM.SCHEMA
end

-- Applies one input, then the automatic phases. input = { type, ts, by?, ... } (see the handlers); env = { ledger,
-- opts (the trust gate of Ledger.Append), credits? ({[member] = n}; default: the ledger's credits of the season),
-- nights? }. Returns true, nil, effects; or nil, code, {} (nothing changed): "READ_ONLY", "UNKNOWN_INPUT", "ts",
-- "NOT_ML", "PAUSED", "ENDED" or the handler's code.
function FSM.Step(s, input, env)
	if type(s) ~= "table" or (s.schema or 0) > FSM.SCHEMA then return nil, "READ_ONLY", {} end
	if type(input) ~= "table" or not H[input.type] then return nil, "UNKNOWN_INPUT", {} end
	if not isNum(input.ts) then return nil, "ts", {} end
	if ML_ONLY[input.type] and input.by ~= s.ml then return nil, "NOT_ML", {} end
	if s.state == "ENDED" and input.type ~= "DELIVERED" and input.type ~= "DELIVERY" and input.type ~= "TICK" then
		return nil, "ENDED", {}
	end
	env = type(env) == "table" and env or {}
	local effects = {}
	local ok, code = H[input.type](s, input, env, effects)
	if not ok then return nil, code, {} end
	if not QUIET[input.type] then
		log(s, { ts = input.ts, type = input.type, by = input.by, item = input.index or s.active })
	end
	settle(s, input.ts, env, effects)
	return true, nil, effects
end

-- The item in progress (its index and table), or nil.
function FSM.Active(s)
	return s.active, current(s)
end

-- The items not delivered yet that have been assigned: { index, ... } (delayed delivery, §4).
function FSM.Undelivered(s)
	local list = {}
	for i, item in ipairs(s.items) do
		if item.state == "ASSIGNED" then list[#list + 1] = i end
	end
	return list
end

if ns.addon then ns.addon.SessionFSM = FSM end   -- also reachable from tests
