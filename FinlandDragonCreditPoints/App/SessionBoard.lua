-- SessionBoard: what the master looter's session window shows, as plain data (docs/ANALISI.md §4, §9.3 point 3, M4-5).
-- Lua 5.1, no frames and no game calls: it reads the hosted session (Domain/SessionFSM.lua's table) or, on another
-- officer's client, the read-only view of Net/Protocol.lua, and returns one `board` table that UI/Windows/MLSession.lua
-- draws and that the tests read. It decides nothing: who wins, what an item costs and which buttons the rules allow come
-- from the session (the "actions" only say which inputs the state machine would accept now). Every sentence is a locale
-- key (Domain/Reasons.lua for the codes), never text written here.
--
-- Board = {
--   host (true on the master looter's client), readOnly, state ("WAITING" ... "ENDED"), paused, lockdown, held (a
--   collection waits for the lockdown to end), encounter, count,
--   items = { { index, itemID, quality, equipLoc, category, council, cost (the full-cost response), costs, state, active,
--               hold, winner, paid, target, rejected } },
--   active (index of the item in progress), selected (index the window shows: `selected`, else the active one, else the
--   first item waiting, else the first),
--   round = { kind, stage, tier, among, collect, remaining, total, expired, rolls } | nil   (the selected item's open round),
--   candidates = { { player, name, class, credits, response, label, note, tier, roll, flag = { group, code }, proposed,
--                    inRound, upgrade, upgradeMS, upgradeOS, equipped } }   (label = the declared label code, note = the
--                    player's note, safe to draw: M4-6; upgrade = the verdict the player's client sent for the spec of the
--                    answer, upgradeMS / upgradeOS = both, each { verdict, usable, code, basis, pct, ilvlDelta } as
--                    UpgradeScore.Unpack gives it, nil without one; equipped = the worn pieces' item strings: M5-2)
--                 (host only: the view carries no list of candidates),
--   proposal = { kind, target, winner, cost, response, tier, roll, credits, reasons, flags, modified, mlReason,
--                ruleWinner, ruleCost, autoIn } | nil   (the selected item's proposal, or its award once assigned),
--   pool = { names } (everybody the selected item's roll counted as present: who the master looter can pick instead),
--   missing = { names }  (raid members who cannot roll: no addon, §4.1) | nil,
--   actions = { start, openRoll, closeRound, advance, confirm, reject, modify, correct, remove, pause, resume, finish },
-- }
-- The "to deliver" list of M4-7 is not part of the board (it outlives the session): SB.DeliveryRows gives its rows,
-- { which ("main" or "carry"), index, itemID, quality, winner, recipient, target, paid, method, status ("PENDING" or
-- "GIVEN"), code, holder, attempts, waiting (seconds since the call), noReceipt, text }, through SessionController:Deliveries().
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local SB = {}
ns.SessionBoard, ns.modules.SessionBoard = SB, SB

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local max, min, floor = math.max, math.min, math.floor

-- The reasons the master looter can give (SessionFSM.ML_REASONS) in the order the dialogs list them. COUNCIL_VOTE is
-- written by the vote itself, never picked by hand.
SB.REASONS = { "OBVIOUS_WASTE", "PASSED_TO_GAME", "COUNCIL_COST", "WRONG_CATEGORY", "LEGENDARY", "MISTAKE", "OTHER" }
-- What a rejected item can become (SessionFSM.REJECT_THEN), the default first.
SB.REJECT_OPTIONS = { "PENDING", "REOPEN", "NEXT_TIER", "BANK", "DISENCHANT" }
-- The badge of each item state (a locale key each).
-- locale-key: ML_BADGE_PENDING ML_BADGE_HELD ML_BADGE_ROLLING ML_BADGE_COMPUTING ML_BADGE_PROPOSAL ML_BADGE_ASSIGNED ML_BADGE_DELIVERED
SB.BADGES = {
	PENDING = { key = "ML_BADGE_PENDING", tone = "neutral" }, HELD = { key = "ML_BADGE_HELD", tone = "warn" },
	ROLLING = { key = "ML_BADGE_ROLLING", tone = "accent" }, COMPUTING = { key = "ML_BADGE_COMPUTING", tone = "warn" },
	PROPOSAL = { key = "ML_BADGE_PROPOSAL", tone = "ok" }, ASSIGNED = { key = "ML_BADGE_ASSIGNED", tone = "ok" },
	DELIVERED = { key = "ML_BADGE_DELIVERED", tone = "neutral" },
}

local function L() return ns.L end

SB.RECEIPT_WAIT = 20   -- seconds after a master loot call before "no loot message seen" is said

-- "Aurel-Realm" -> "Aurel"
local function short(name) return (tostring(name):gsub("%-.*$", "")) end
SB.Short = short

local function num(n)
	if type(n) ~= "number" then return tostring(n) end
	if n == floor(n) then return ("%d"):format(n) end
	return (("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", ""))
end

---------------------------------------------------------------------------------------------------------------------
-- Words

-- "1 credit", "2 credits", "no cost set" (a cost the council still has to fix).
-- locale-key: ML_CREDITS_ONE ML_CREDITS_N ML_COST_UNSET
function SB.CreditsText(cost)
	if cost == nil then return L()["ML_COST_UNSET"] end
	if cost == 1 then return L()["ML_CREDITS_ONE"] end
	return L()["ML_CREDITS_N"]:format(num(cost))
end

-- The sentence of a refused action: the window's own codes, then the refusals of Domain/Reasons.lua, then the code.
-- locale-key: ML_ERR_NO_SESSION ML_ERR_NOT_HOST ML_ERR_BAD_COST ML_ERR_OTHER
function SB.ErrorText(code)
	local own = "ML_ERR_" .. tostring(code)
	if L()[own] ~= own then return L()[own] end
	local key = ns.Reasons and ns.Reasons.Key("REFUSAL", code)
	if key and L()[key] ~= key then return L()[key] end
	return L()["ML_ERR_OTHER"]:format(tostring(code))
end

-- "Proposal: Bryn, 1 credit. Same credits as the others, highest roll."
-- locale-key: ML_PROPOSAL ML_PROPOSAL_NOBODY ML_PROPOSAL_AWARDED
function SB.ProposalText(p)
	if type(p) ~= "table" then return "" end
	local R = ns.Reasons
	local who
	if p.target == "bank" or p.target == "disenchant" then
		who = R.Text("KIND", p.target == "bank" and "BANK" or "DISENCHANT")
		if p.winner then who = who .. " (" .. short(p.winner) .. ")" end
	elseif p.winner then
		who = short(p.winner)
	else
		return L()["ML_PROPOSAL_NOBODY"]:format(table.concat(R.List("REASON", p.reasons), " "))
	end
	return L()["ML_PROPOSAL"]:format(who, SB.CreditsText(p.cost), table.concat(R.List("REASON", p.reasons), " "))
end

-- "Awarded to Bryn for 1 credit." (an item already assigned)
function SB.AwardText(item)
	if type(item) ~= "table" or not item.winner then return "" end
	local who = item.winner
	if item.target == "bank" or item.target == "disenchant" then
		who = ns.Reasons.Text("KIND", item.target == "bank" and "BANK" or "DISENCHANT") .. " (" .. short(who) .. ")"
	else
		who = short(who)
	end
	return L()["ML_PROPOSAL_AWARDED"]:format(who, SB.CreditsText(item.paid))
end

-- The sentences of a proposal's flags (what the master looter has to look at).
function SB.FlagTexts(p)
	return p and ns.Reasons.List("FLAG", p.flags) or {}
end

-- How a modified proposal departs from the rules: "Out of line: Bryn was first in line, Corin instead."
-- locale-key: ML_DIFF_OUT_OF_ORDER ML_DIFF_COST
function SB.DiffTexts(p)
	local out = {}
	if type(p) ~= "table" or not p.modified then return out end
	if p.ruleWinner and p.winner and (p.winner ~= p.ruleWinner) then
		out[#out + 1] = L()["ML_DIFF_OUT_OF_ORDER"]:format(short(p.ruleWinner), short(p.winner))
	end
	if p.ruleCost ~= nil and p.cost ~= nil and p.cost ~= p.ruleCost then
		out[#out + 1] = L()["ML_DIFF_COST"]:format(SB.CreditsText(p.cost), SB.CreditsText(p.ruleCost))
	end
	return out
end

-- The sentence of a delivery code (Domain/Reasons.lua group DELIVERY), or "" for none.
function SB.DeliveryCodeText(code)
	if code == nil then return "" end
	return ns.Reasons.Text("DELIVERY", code)
end

-- Where a delivery stands, in words: "Handed over: waiting for the loot message.", "To hand over by trade. Held by
-- Corin." Built from the row of `deliveries`.
function SB.DeliveryText(row)
	if type(row) ~= "table" then return "" end
	local R = ns.Reasons
	local parts = {}
	if row.status == "GIVEN" then
		parts[1] = R.Text("DELIVERY", row.noReceipt and "NO_RECEIPT" or "GIVEN")
	else
		parts[1] = R.Text("DELIVERY", row.code or "TRADE")
	end
	if row.holder then parts[#parts + 1] = R.Text("DELIVERY", "HOLDER"):format(short(row.holder)) end
	return table.concat(parts, " ")
end

-- The "to deliver" rows of the sessions given, in order: { { which, session }, ... }.
function SB.DeliveryRows(sessions, now)
	local out = {}
	local FSM = ns.SessionFSM
	for _, entry in ipairs(sessions) do
		local s = entry.session
		for _, i in ipairs(s and FSM.Undelivered(s) or {}) do
			local item, d = s.items[i], s.items[i].delivery
			local row = { which = entry.which, index = i, itemID = item.itemID, quality = item.quality, category = item.category,
				equipLoc = item.info and item.info.equipLoc, winner = item.award.member, recipient = FSM.Recipient(s, i),
				target = item.award.target, paid = item.award.cost, method = d and d.method or "TRADE",
				status = d and d.status or "PENDING", code = d and d.code, holder = d and d.holder, attempts = d and d.attempts or 0 }
			if row.status == "GIVEN" and d.at and now then
				row.waiting = max(0, now - d.at)
				row.noReceipt = row.waiting >= SB.RECEIPT_WAIT
			end
			row.text = SB.DeliveryText(row)
			out[#out + 1] = row
		end
	end
	return out
end

-- The short badge of an item.
function SB.Badge(item)
	local b = SB.BADGES[item.hold and item.state == "PENDING" and "HELD" or item.state] or SB.BADGES.PENDING
	return L()[b.key], b.tone
end

---------------------------------------------------------------------------------------------------------------------
-- The hosted session

local function responseTiers(s)
	local out = {}
	local responses = s.rules and s.rules.priority and s.rules.priority.responses
	for code, r in pairs(type(responses) == "table" and responses or {}) do
		if type(r) == "table" and type(r.tier) == "number" and r.enabled ~= false then out[code] = r.tier end
	end
	return out
end

-- The response of the lowest tier (the one that pays the full cost), the one the list shows the cost of.
local function costResponse(s)
	local best, bestTier
	for code, tier in pairs(responseTiers(s)) do
		if bestTier == nil or tier < bestTier or (tier == bestTier and code < best) then best, bestTier = code, tier end
	end
	return best
end

local function hostItem(s, i, item, response)
	local out = { index = i, itemID = item.itemID, quality = item.quality, equipLoc = item.info and item.info.equipLoc,
		category = item.category, council = item.council, costs = item.costs, state = item.state, active = s.active == i,
		hold = item.hold, boe = item.boe, rejected = item.rejected and #item.rejected or 0,
		cost = response and item.costs and item.costs[response] or nil }
	if item.award then out.winner, out.paid, out.target = item.award.member, item.award.cost, item.award.target end
	return out
end

local function hostRound(s, item, now)
	local r = item.round
	if not r then return nil end
	local total = s.rules and s.rules.session and s.rules.session.rollSeconds
	if type(total) ~= "number" or total <= 0 then total = 30 end
	local remaining = r.remaining
	if r.deadline then remaining = max(0, r.deadline - now) end
	return { kind = r.kind, stage = r.stage, tier = r.tier, among = r.among, collect = r.collect, remaining = remaining,
		total = total, expired = r.expired, rolls = #(r.rolls or {}) }
end

local function hostProposal(item, now)
	local p = item.proposal
	if not p then return nil end
	local target = p.target or (p.kind == "BANK" and "bank") or (p.kind == "DISENCHANT" and "disenchant") or "member"
	local autoIn
	if item.autoAt then autoIn = max(0, item.autoAt - now) end
	return { kind = p.kind, target = target, winner = p.winner, cost = p.cost, response = p.response, tier = p.tier,
		roll = p.roll, credits = p.credits, reasons = p.reasons or {}, flags = p.flags or {},
		modified = item.intervention ~= nil, mlReason = item.intervention and item.intervention.reason,
		ruleWinner = item.rule and item.rule.winner, ruleCost = item.rule and item.rule.cost, autoIn = autoIn }
end

-- The roll a player shows in the table: their first roll in the newest round that has one (a reroll replaces the roll
-- of the tied). Rolls outside the rules' range are not shown (Priority discards them).
local function rollOf(item, player, rollMin, rollMax)
	local rounds = {}
	for _, r in ipairs(item.rounds or {}) do rounds[#rounds + 1] = r end
	if item.round then rounds[#rounds + 1] = item.round end
	for i = #rounds, 1, -1 do
		for _, r in ipairs(rounds[i].rolls or {}) do
			if r.player == player and r.min == rollMin and r.max == rollMax then return r.value end
		end
	end
	return nil
end

local function hasRolled(item, player)
	local function seen(round)
		for _, r in ipairs(round and round.rolls or {}) do
			if r.player == player then return true end
		end
		return false
	end
	for _, r in ipairs(item.rounds or {}) do if seen(r) then return true end end
	return seen(item.round)
end

-- A player's note as text that is safe to draw: no escape sequences ("|" is doubled), no control characters.
function SB.SafeNote(text)
	if type(text) ~= "string" or text == "" then return nil end
	return (text:gsub("%c", " "):gsub("|", "||"))
end

local function hostCandidates(s, item, proposal, env)
	if type(item.credits) ~= "table" then return {} end   -- the roll has not opened: nothing frozen yet
	local priority = s.rules and s.rules.priority or {}
	local rollMin, rollMax = priority.rollMin or 1, priority.rollMax or 100
	local tiers = responseTiers(s)
	local names = {}
	for p in pairs(item.responses or {}) do names[p] = true end
	for _, r in ipairs(item.rounds or {}) do for _, x in ipairs(r.rolls or {}) do names[x.player] = true end end
	for _, x in ipairs(item.round and item.round.rolls or {}) do names[x.player] = true end
	if item.state == "ROLLING" and type(item.present) == "table" then   -- who has not answered yet
		for p in pairs(item.present) do
			if item.present[p] == true and (not priority.requireAddon or type(item.addon) ~= "table" or item.addon[p] == true) then
				names[p] = true
			end
		end
	end
	local discards = {}
	for _, d in ipairs(item.discarded or {}) do
		if discards[d.player] == nil then discards[d.player] = d.code end
	end
	local among
	if item.round and item.round.among then
		among = {}
		for _, p in ipairs(item.round.among) do among[p] = true end
	end
	local out = {}
	for p in pairs(names) do
		local response = item.responses and item.responses[p] or nil
		local verdicts = item.verdicts and item.verdicts[p]
		local U = ns.UpgradeScore
		local upMS = verdicts and U and U.Unpack(verdicts.m) or nil
		local upOS = verdicts and verdicts.o and U and U.Unpack(verdicts.o) or nil
		local row = { player = p, name = short(p), class = env.classOf and env.classOf(p) or nil,
			credits = item.credits[p] or 0, response = response, tier = response and tiers[response] or nil,
			label = item.labels and item.labels[p] or nil, note = SB.SafeNote(item.notes and item.notes[p]),
			roll = rollOf(item, p, rollMin, rollMax), proposed = proposal ~= nil and proposal.winner == p,
			inRound = among == nil or among[p] == true, upgradeMS = upMS, upgradeOS = upOS,
			upgrade = response == "OS" and (upOS or upMS) or upMS,
			equipped = item.equipped and item.equipped[p] or nil }
		local rolled = hasRolled(item, p)
		if rolled and priority.requireAddon and type(item.addon) == "table" and item.addon[p] ~= true then
			row.flag = { group = "DISCARD", code = "NO_ADDON" }
		elseif discards[p] then
			row.flag = { group = "DISCARD", code = discards[p] }
		end
		out[#out + 1] = row
	end
	table.sort(out, function(a, b)
		local ta, tb = a.tier or 99, b.tier or 99
		if ta ~= tb then return ta < tb end
		if a.credits ~= b.credits then return a.credits < b.credits end
		local ra, rb = a.roll or -1, b.roll or -1
		if ra ~= rb then return ra > rb end
		return a.player < b.player
	end)
	return out
end

local function missingPlayers(s)
	if not (s.rules and s.rules.priority and s.rules.priority.requireAddon) then return nil end
	local present, addon = s.raid and s.raid.present, s.raid and s.raid.addon
	if type(present) ~= "table" or type(addon) ~= "table" then return nil end
	local list = {}
	for p in pairs(present) do
		if present[p] == true and addon[p] ~= true then list[#list + 1] = p end
	end
	table.sort(list)
	return list
end

local function pickSelected(items, active, selected)
	if selected and items[selected] then return selected end
	if active then return active end
	for _, it in ipairs(items) do if it.state == "PENDING" and not it.hold then return it.index end end
	return #items > 0 and 1 or nil
end

local function hostActions(s, sel, item)
	local a = {}
	local st = s.state
	local ended = st == "ENDED"
	local rules = s.rules and s.rules.session or {}
	local activeSel = sel ~= nil and s.active == sel
	a.start = st == "COLLECTING" and #s.items > 0
	a.remove = st == "COLLECTING" and sel ~= nil
	a.openRoll = st == "ANNOUNCING" and item ~= nil and item.state == "PENDING"
	a.closeRound = st == "ROLLING" and activeSel
	a.advance = st == "COMPUTING" and activeSel
	local p = item and item.proposal
	local inProposal = st == "PROPOSAL" and activeSel and p ~= nil
	a.reject, a.modify = inProposal, inProposal
	a.confirm = inProposal and p.winner ~= nil and p.cost ~= nil
		and (rules.awardMode ~= "council" or item.voteClosed == true)
	a.correct = item ~= nil and not ended and (st == "COLLECTING" or st == "ANNOUNCING" or st == "ROLLING" or st == "COMPUTING")
		and (item.state == "PENDING" or item.state == "ROLLING" or item.state == "COMPUTING")
		and not (item.opened and rules.lockCategoryOnOpen)
	a.pause = not ended and not s.paused
	a.resume = not ended and s.paused == true
	a.finish = not ended and s.active == nil
	return a
end

local function buildHost(s, env, selected, readOnly)
	local response = costResponse(s)
	local items = {}
	for i, item in ipairs(s.items) do items[i] = hostItem(s, i, item, response) end
	local sel = pickSelected(items, s.active, selected)
	local item = sel and s.items[sel] or nil
	local now = env.now or 0
	local b = { host = true, readOnly = readOnly or nil, state = s.state, paused = s.paused == true,
		lockdown = s.lockdown == true, held = env.held == true, encounter = s.encounter, count = #items, items = items,
		active = s.active, selected = sel, missing = missingPlayers(s) }
	if item then
		b.round = hostRound(s, item, now)
		b.proposal = hostProposal(item, now)
		b.candidates = hostCandidates(s, item, b.proposal, env)
		b.pool = {}
		for p in pairs(type(item.present) == "table" and item.present or {}) do
			if item.present[p] == true then b.pool[#b.pool + 1] = p end
		end
		table.sort(b.pool)
		b.selectedItem = items[sel]
	else
		b.candidates, b.pool = {}, {}
	end
	b.actions = readOnly and {} or hostActions(s, sel, item)
	return b
end

---------------------------------------------------------------------------------------------------------------------
-- The read-only view (another officer's client)

local function buildView(v, env, selected)
	local items = {}
	for i, it in ipairs(v.items or {}) do
		local cost
		for _, c in pairs(it.cs or {}) do if cost == nil or c > cost then cost = c end end
		items[i] = { index = i, itemID = it.id, category = it.ca, council = it.co, costs = it.cs, cost = cost, state = it.st,
			active = v.a == i, winner = it.w, paid = it.pc, target = it.tg, rejected = 0 }
	end
	local sel = pickSelected(items, v.a, selected)
	local state = v.ended and "ENDED" or (v.proposal and "PROPOSAL") or (v.round and "ROLLING") or "ANNOUNCING"
	local b = { host = false, readOnly = true, state = state, paused = v.paused == true, encounter = v.e, count = #items,
		items = items, active = v.a, selected = sel, candidates = {}, actions = {},
		selectedItem = sel and items[sel] or nil }
	if v.round and sel == v.round.i then
		local remaining = v.round.rm
		if v.round.deadline and not v.paused then remaining = max(0, v.round.deadline - (env.now or 0)) end
		local total = env.rollSeconds or 30
		b.round = { kind = v.round.k, stage = v.round.g, tier = v.round.tr, among = v.round.am, collect = v.round.cl,
			remaining = remaining, total = total }
	end
	local p = v.proposal
	if p and sel == p.i then
		b.proposal = { kind = p.k, target = p.tg, winner = p.w, cost = p.c, response = p.rs, tier = p.tr,
			reasons = p.rc or {}, flags = p.f or {}, modified = p.m }
	end
	return b
end

---------------------------------------------------------------------------------------------------------------------
-- Entry point

-- `view` is SessionController:View(): { host = true, session } or { host = false, view }. env = { now, classOf(name),
-- held, rollSeconds }. `selected` = the item index the window shows (nil: follow the session). nil without a view.
function SB.Build(view, env, selected)
	if type(view) ~= "table" then return nil end
	env = type(env) == "table" and env or {}
	if view.host then return buildHost(view.session, env, selected, view.readOnly) end
	return buildView(view.view, env, selected)
end

-- The proposal a modification would give, as a board proposal (the dialog's live difference); nil and a code when the
-- state machine would refuse it.
function SB.Preview(session, change, now, by)
	local FSM = ns.SessionFSM
	local copy = FSM.Copy(session)
	local input = {}
	for k, v in pairs(change) do input[k] = v end
	input.type, input.ts, input.by = "MODIFY", now, by or session.ml
	local ok, code = FSM.Step(copy, input, {})
	if not ok then return nil, code end
	local item = copy.items[copy.active]
	return hostProposal(item, now)
end

if ns.addon then ns.addon.SessionBoard = SB end   -- also reachable from tests
