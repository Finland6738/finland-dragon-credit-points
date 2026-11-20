-- Priority: who gets an item and why (docs/ANALISI.md §3.3, §3.4, §3.8). Pure Lua 5.1: it never calls the game.
--
-- Priority.Evaluate(state, config) is a pure function of what happened so far: the responses, the roll rounds in
-- the order they were held, the credits and the configuration. It replays the algorithm of §3.4 and returns either
-- the next round that must be rolled ("ROLL" for a tier or a free roll, "REROLL" among the tied only) or the
-- finished proposal ("PROPOSAL"). The session state machine (M2-6) appends the round it asked for and calls again,
-- so a reroll, the off-spec tier and the fallback are never decided outside this file.
--
-- The algorithm (§3.4):
--   for every tier, from the lowest:
--       candidates = the tier's responders with a valid roll in the tier's round
--       none: go to the next tier (a tier nobody answered needs no round)
--       order by (metric ascending, roll descending)
--       several at the top with the same metric and the same roll: reroll among them only, until one is alone
--   no tier has candidates: the fallback (BoE -> bank, otherwise disenchant / free roll / the master looter).
-- A BoE without main-spec candidates goes to `boeFallback` (preset "bank") instead of the off-spec tier, unless
-- `boeFallback` is "offspec" (§3.8).
--
-- A valid roll (§4, §4.1): a 1-100 roll (`min` 1, `max` 100, an integer value between them), the first 1-100 roll of
-- that player in the round (a roll with another range is discarded and does not use the player's turn), inside the
-- round's window when the round has `openedAt` / `closedAt`, from a character present in the raid, with the addon
-- active (when the state says who has it and `requireAddon` is on), and from a candidate of that round. Every other
-- roll is listed in `discarded` with a code.
--
-- Input:
--   state = {
--     responses = { [player] = "MS" | "OS" | "TMOG" | "PASS" },
--     rounds    = { { rolls = { { player = p, value = n, min = 1, max = 100, ts = t }, ... },
--                     openedAt = t, closedAt = t }, ... },        -- in the order they were held
--     credits   = { [player] = n },          -- missing = 0
--     nights    = { [player] = n },          -- nights played, for the "creditsPerNight" metric
--     present   = { [player] = true } | nil, -- nil: presence not checked
--     addon     = { [player] = true } | nil, -- nil: the addon check is not applied
--     boe       = true | nil,
--     costs     = { [response] = n } | nil,  -- the item's cost per response (Domain/Pricing.lua); nil: priced from
--     item, costConfig, priceCtx             -- `item` through Pricing.Price when that module is loaded
--   }
-- Output: { status, tier, among, round, proposal, history, discarded } (see Priority.Evaluate). Codes and numbers
-- only, never sentences: the locales turn the reason codes into words (M2-7).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Priority = {}
ns.Priority, ns.modules.Priority = Priority, Priority

local type, pairs, ipairs, tostring, setmetatable = type, pairs, ipairs, tostring, setmetatable
local floor, sort, abs = math.floor, table.sort, math.abs

Priority.METRICS = { "credits", "creditsPerNight", "roll" }
Priority.FALLBACKS = { "ml", "disenchant", "freeroll" }
Priority.BOE_FALLBACKS = { "bank", "offspec", "disenchant", "freeroll" }
Priority.TIE_BREAKS = { "roll", "reroll" }

-- The decision reason of each metric when the metric alone decided (the roll did not matter).
local METRIC_REASON = { credits = "LOWER_CREDITS", creditsPerNight = "LOWER_CREDITS_PER_NIGHT" }

-- The "Patto" preset (§3.1, §3.3, §3.4, §3.8). A fresh copy on every call.
function Priority.DefaultConfig()
	return {
		metric = "credits",              -- "credits" | "creditsPerNight" | "roll"
		tieBreak = { "roll", "reroll" }, -- in order; without "reroll" a full tie goes to the master looter
		maxRerolls = 5,                  -- reroll rounds in a row before the master looter decides
		rollMin = 1,
		rollMax = 100,
		requireAddon = true,             -- session.allowNoAddon = no (§4.1)
		responses = {
			MS = { tier = 1, reason = "MAIN_SPEC_TIER" },
			OS = { tier = 2, reason = "OFFSPEC_TIER" },
			TMOG = { tier = 3, reason = "TRANSMOG_TIER", enabled = false },
		},
		boeFallback = "bank",            -- "bank" | "offspec" | "disenchant" | "freeroll"
		fallback = "ml",                 -- "ml" | "disenchant" | "freeroll"
		bankCharacter = nil,             -- the guild bank character (§3.8)
		disenchanter = nil,
		freeRollCost = 0,
	}
end

local DEFAULT_CONFIG = Priority.DefaultConfig()
local EPSILON = 1e-9

local function contains(list, value)
	if type(list) ~= "table" then return false end
	for _, v in ipairs(list) do
		if v == value then return true end
	end
	return false
end

local function sortedKeys(set)
	local list = {}
	for k in pairs(set) do list[#list + 1] = k end
	sort(list)
	return list
end

local function copyList(list)
	local c = {}
	for i, v in ipairs(list) do c[i] = v end
	return c
end

-- The metric value of a player: lower is better.
local function metricOf(state, config, player)
	local metric = config.metric
	if metric == "roll" then return 0 end
	local credits = type(state.credits) == "table" and state.credits[player] or nil
	if type(credits) ~= "number" then credits = 0 end
	if metric == "creditsPerNight" then
		local nights = type(state.nights) == "table" and state.nights[player] or nil
		if type(nights) ~= "number" or nights < 1 then nights = 1 end
		return credits / nights
	end
	return credits
end

local function sameMetric(a, b)
	return abs(a - b) <= EPSILON
end

-- The cost of the winner's response, and whether the council prices it.
local function costOf(state, response)
	if type(state.costs) == "table" then
		local c = state.costs[response]
		if type(c) == "number" then return c end
		return nil
	end
	local Pricing = ns.Pricing
	if type(state.item) == "table" and Pricing then
		return Pricing.Price(state.item, response, state.costConfig, state.priceCtx).cost
	end
	return nil
end

-- The evaluation context: replays the rounds one by one.
local Run = {}
Run.__index = Run

local function newRun(state, config)
	return setmetatable({
		state = state,
		config = config,
		rounds = type(state.rounds) == "table" and state.rounds or {},
		nextRound = 1,
		history = {},
		discarded = {},
	}, Run)
end

local function isPresent(state, player)
	return type(state.present) ~= "table" or state.present[player] == true
end

local function hasAddon(state, config, player)
	if not config.requireAddon or type(state.addon) ~= "table" then return true end
	return state.addon[player] == true
end

-- Whether a player can take part in a round at all (present, addon).
function Run:CanRoll(player)
	return isPresent(self.state, player) and hasAddon(self.state, self.config, player)
end

function Run:Discard(roundIndex, player, code)
	self.discarded[#self.discarded + 1] = { round = roundIndex, player = player, code = code }
end

-- The valid rolls of one round: a list of { player, value } in arrival order, one per player. `among` is a set of
-- the round's candidates, or nil when anyone present can roll (free roll).
function Run:ValidRolls(roundIndex, round, among)
	local config = self.config
	local rollMin, rollMax = config.rollMin or 1, config.rollMax or 100
	local seen, valid = {}, {}
	local rolls = type(round) == "table" and type(round.rolls) == "table" and round.rolls or {}
	for _, r in ipairs(rolls) do
		local player = type(r) == "table" and r.player or nil
		local value = type(r) == "table" and r.value or nil
		if type(player) ~= "string" or player == "" then
			self:Discard(roundIndex, nil, "BAD_ROLL")
		elseif r.min ~= rollMin or r.max ~= rollMax then
			self:Discard(roundIndex, player, "NOT_1_100")
		elseif type(value) ~= "number" or value ~= floor(value) or value < rollMin or value > rollMax then
			self:Discard(roundIndex, player, "BAD_VALUE")
		elseif type(round.openedAt) == "number" and type(r.ts) == "number" and r.ts < round.openedAt then
			self:Discard(roundIndex, player, "BEFORE_OPEN")
		elseif type(round.closedAt) == "number" and type(r.ts) == "number" and r.ts > round.closedAt then
			self:Discard(roundIndex, player, "AFTER_CLOSE")
		elseif not isPresent(self.state, player) then
			self:Discard(roundIndex, player, "NOT_PRESENT")
		elseif not hasAddon(self.state, config, player) then
			self:Discard(roundIndex, player, "NO_ADDON")
		elseif among ~= nil and not among[player] then
			self:Discard(roundIndex, player, "NOT_ELIGIBLE")
		elseif seen[player] then
			self:Discard(roundIndex, player, "DUPLICATE")
		else
			seen[player] = true
			valid[#valid + 1] = { player = player, value = value }
		end
	end
	return valid
end

-- Takes the next round, or nil when it has not been held yet.
function Run:TakeRound()
	local i = self.nextRound
	local round = self.rounds[i]
	if round == nil then return nil, i end
	self.nextRound = i + 1
	return round, i
end

local function toSet(list)
	if list == nil then return nil end
	local s = {}
	for _, p in ipairs(list) do s[p] = true end
	return s
end

-- Plays one stage (a tier or a free roll) among `among` (a sorted list, or nil for anyone present).
-- Returns one of:
--   { need = "ROLL" | "REROLL", among = list }   the next round has not been held yet
--   { empty = true }                             nobody rolled validly
--   { winner = entry, reasons = {...}, ranking = list, rerolls = list }
--   { ml = true, flag = "TIE_UNRESOLVED" | "REROLL_LIMIT", among = list }
function Run:Stage(kind, tier, among, useMetric)
	local config = self.config
	local round, index = self:TakeRound()
	if round == nil then return { need = "ROLL", among = among } end
	local valid = self:ValidRolls(index, round, toSet(among))
	local entry = { kind = kind, tier = tier, round = index, among = among, valid = #valid }
	self.history[#self.history + 1] = entry
	if #valid == 0 then
		entry.outcome = "EMPTY"
		return { empty = true }
	end

	local ranking = {}
	for _, v in ipairs(valid) do
		local m = useMetric and metricOf(self.state, config, v.player) or 0
		ranking[#ranking + 1] = { player = v.player, roll = v.value, metric = m }
	end
	local byRoll = contains(config.tieBreak, "roll")
	sort(ranking, function(a, b)
		if not sameMetric(a.metric, b.metric) then return a.metric < b.metric end
		if byRoll and a.roll ~= b.roll then return a.roll > b.roll end
		return a.player < b.player
	end)

	local first = ranking[1]
	local tied = { first.player }
	for i = 2, #ranking do
		local r = ranking[i]
		if sameMetric(r.metric, first.metric) and (not byRoll or r.roll == first.roll) then
			tied[#tied + 1] = r.player
		end
	end

	if #tied == 1 then
		local reasons = {}
		local second = ranking[2]
		if second == nil then
			reasons[1] = "ONLY_CANDIDATE"
		elseif useMetric and config.metric ~= "roll" and not sameMetric(first.metric, second.metric) then
			reasons[1] = METRIC_REASON[config.metric] or "LOWER_CREDITS"
		else
			reasons[1] = "HIGHER_ROLL"
		end
		entry.outcome = "WINNER"
		return { winner = first, reasons = reasons, ranking = ranking, rerolls = {} }
	end

	sort(tied)
	entry.outcome = "TIE"
	entry.tied = copyList(tied)
	if not contains(config.tieBreak, "reroll") then
		return { ml = true, flag = "TIE_UNRESOLVED", among = tied, ranking = ranking }
	end
	return self:Reroll(kind, tier, tied, first, ranking)
end

-- Reroll rounds among the tied only, until one is alone (§3.4).
function Run:Reroll(kind, tier, group, first, ranking)
	local maxRerolls = self.config.maxRerolls
	if type(maxRerolls) ~= "number" or maxRerolls < 1 then maxRerolls = DEFAULT_CONFIG.maxRerolls end
	local rerolls, held = {}, 0
	while true do
		if held >= maxRerolls then
			return { ml = true, flag = "REROLL_LIMIT", among = group, ranking = ranking }
		end
		local round, index = self:TakeRound()
		if round == nil then return { need = "REROLL", among = group } end
		held = held + 1
		local valid = self:ValidRolls(index, round, toSet(group))
		local entry = { kind = "REROLL", tier = tier, round = index, among = group, valid = #valid }
		self.history[#self.history + 1] = entry
		if #valid == 0 then
			entry.outcome = "EMPTY"   -- nobody rerolled: the same group rerolls again
		else
			sort(valid, function(a, b)
				if a.value ~= b.value then return a.value > b.value end
				return a.player < b.player
			end)
			local top = {}
			for _, v in ipairs(valid) do
				if v.value == valid[1].value then top[#top + 1] = v.player end
			end
			rerolls[#rerolls + 1] = { round = index, rolls = valid }
			if #top == 1 then
				entry.outcome = "WINNER"
				local winner
				for _, r in ipairs(ranking) do
					if r.player == top[1] then winner = r end
				end
				return { winner = winner, reasons = { "REROLL_WON" }, ranking = ranking, rerolls = rerolls,
					reroll = valid[1].value }
			end
			sort(top)
			entry.outcome = "TIE"
			entry.tied = copyList(top)
			group = top
		end
	end
end

-- The tiers of the configuration, ascending: { { tier = n, responses = { [code] = cfg } } }.
local function configuredTiers(config)
	local byTier = {}
	for code, r in pairs(type(config.responses) == "table" and config.responses or {}) do
		if type(r) == "table" and type(r.tier) == "number" and r.enabled ~= false then
			byTier[r.tier] = byTier[r.tier] or {}
			byTier[r.tier][code] = r
		end
	end
	local tiers = {}
	for _, t in ipairs(sortedKeys(byTier)) do tiers[#tiers + 1] = { tier = t, responses = byTier[t] } end
	return tiers
end

local function flagsOf(run, extra)
	local flags = {}
	if extra then flags[#flags + 1] = extra end
	if #run.discarded > 0 then flags[#flags + 1] = "DISCARDED_ROLLS" end
	return flags
end

local function rivalsOf(ranking, winner)
	local rivals = {}
	for _, r in ipairs(ranking or {}) do
		if r.player ~= winner then
			rivals[#rivals + 1] = { player = r.player, metric = r.metric, roll = r.roll }
		end
	end
	return rivals
end

-- The result of a finished evaluation.
local function finish(run, proposal)
	return {
		status = "PROPOSAL",
		proposal = proposal,
		history = run.history,
		discarded = run.discarded,
		round = run.nextRound,
	}
end

local function need(run, what, kind, tier, among)
	return {
		status = what,          -- "ROLL" | "REROLL"
		stage = kind,           -- "TIER" | "FREE_ROLL"
		tier = tier,
		among = among,          -- sorted list of players, nil = anyone present (free roll)
		round = run.nextRound,  -- the index the new round will have in state.rounds
		history = run.history,
		discarded = run.discarded,
	}
end

-- An award to a winner of a stage.
local function award(run, res, response, tier, tierReason, extraReason, cost)
	local state = run.state
	local reasons = {}
	if tierReason then reasons[#reasons + 1] = tierReason end
	if extraReason then reasons[#reasons + 1] = extraReason end
	for _, r in ipairs(res.reasons) do reasons[#reasons + 1] = r end
	local flagExtra = nil
	if cost == nil then flagExtra = "COST_BY_COUNCIL" end
	local winner = res.winner
	local credits = type(state.credits) == "table" and state.credits[winner.player] or nil
	return finish(run, {
		kind = "AWARD",
		winner = winner.player,
		response = response,
		tier = tier,
		cost = cost,
		credits = type(credits) == "number" and credits or 0,
		metric = winner.metric,
		roll = winner.roll,
		reroll = res.reroll,
		rerolls = res.rerolls,
		rivals = rivalsOf(res.ranking, winner.player),
		reasons = reasons,
		flags = flagsOf(run, flagExtra),
	})
end

local function mlProposal(run, flag, among, reason)
	return finish(run, {
		kind = "ML",
		reasons = { reason or "FALLBACK_ML" },
		flags = flagsOf(run, flag),
		among = among,
		cost = nil,
	})
end

-- The fallback when no tier has candidates (or a BoE has no main-spec candidates).
local function fallback(run, mode, boe)
	local config = run.config
	if mode == "bank" then
		local bank = config.bankCharacter
		return finish(run, {
			kind = "BANK",
			winner = (type(bank) == "string" and bank ~= "") and bank or nil,
			cost = 0,
			reasons = { "BOE_BANK" },
			flags = flagsOf(run, (type(bank) ~= "string" or bank == "") and "NO_BANK_CHARACTER" or nil),
		})
	elseif mode == "disenchant" then
		local de = config.disenchanter
		return finish(run, {
			kind = "DISENCHANT",
			winner = (type(de) == "string" and de ~= "") and de or nil,
			cost = 0,
			reasons = { "FALLBACK_DISENCHANT" },
			flags = flagsOf(run, (type(de) ~= "string" or de == "") and "NO_DISENCHANTER" or nil),
		})
	elseif mode == "freeroll" then
		local res = run:Stage("FREE_ROLL", nil, nil, false)
		if res.need then return need(run, res.need, "FREE_ROLL", nil, res.among) end
		if res.winner then
			local cost = type(config.freeRollCost) == "number" and config.freeRollCost or 0
			return award(run, res, nil, nil, "FALLBACK_FREE_ROLL", nil, cost)
		end
		if res.ml then return mlProposal(run, res.flag, res.among) end
		return mlProposal(run, "FREE_ROLL_EMPTY")
	end
	return mlProposal(run)
end

-- The candidates of a tier: the players whose response belongs to it and who can roll, sorted.
local function tierCandidates(run, tierInfo)
	local list = {}
	for player, response in pairs(type(run.state.responses) == "table" and run.state.responses or {}) do
		if type(player) == "string" and tierInfo.responses[response] and run:CanRoll(player) then
			list[#list + 1] = player
		end
	end
	sort(list)
	return list
end

-- Evaluates the state (see the header). Returns:
--   status    "ROLL" (hold the round of `tier`, or the free roll when `stage` is "FREE_ROLL"),
--             "REROLL" (hold a reroll round among `among` only), or "PROPOSAL";
--   tier, among, stage, round   for ROLL / REROLL: what to hold next and the index it will have in state.rounds;
--   proposal  for PROPOSAL: { kind = "AWARD" | "BANK" | "DISENCHANT" | "ML", winner, response, tier, cost (nil when
--             the council prices it), credits, metric, roll, reroll, rerolls, rivals, reasons = {codes},
--             flags = {codes}, among (ML: the players still tied) };
--   history   one entry per round played: { kind, tier, round, among, valid, outcome, tied };
--   discarded { { round, player, code } }: NOT_1_100, BAD_VALUE, BAD_ROLL, BEFORE_OPEN, AFTER_CLOSE, NOT_PRESENT,
--             NO_ADDON, NOT_ELIGIBLE, DUPLICATE.
function Priority.Evaluate(state, config)
	state = type(state) == "table" and state or {}
	config = type(config) == "table" and config or DEFAULT_CONFIG
	local run = newRun(state, config)
	local tiers = configuredTiers(config)
	local mainTier = tiers[1] and tiers[1].tier or nil
	local boeFallback = config.boeFallback or "bank"

	for _, tierInfo in ipairs(tiers) do
		if state.boe and tierInfo.tier ~= mainTier and boeFallback ~= "offspec" then
			return fallback(run, boeFallback, true)
		end
		local among = tierCandidates(run, tierInfo)
		if #among > 0 then
			local res = run:Stage("TIER", tierInfo.tier, among, true)
			if res.need then return need(run, res.need, "TIER", tierInfo.tier, res.among) end
			if res.winner then
				local response = state.responses[res.winner.player]
				local tierReason = tierInfo.responses[response].reason
				return award(run, res, response, tierInfo.tier, tierReason, nil, costOf(state, response))
			end
			if res.ml then return mlProposal(run, res.flag, res.among, "TIE_ML") end
			-- empty: the next tier
		end
	end
	if state.boe and boeFallback ~= "offspec" then return fallback(run, boeFallback, true) end
	return fallback(run, config.fallback or "ml", false)
end

-- Checks a priority configuration. Returns true, or false plus a sorted list of codes.
function Priority.Validate(config)
	if type(config) ~= "table" then return false, { "config" } end
	local problems = {}
	if not contains(Priority.METRICS, config.metric) then problems[#problems + 1] = "metric" end
	if type(config.tieBreak) ~= "table" then
		problems[#problems + 1] = "tieBreak"
	else
		for _, t in ipairs(config.tieBreak) do
			if not contains(Priority.TIE_BREAKS, t) then problems[#problems + 1] = "tieBreak:" .. tostring(t) end
		end
	end
	if type(config.maxRerolls) ~= "number" or config.maxRerolls < 1 or config.maxRerolls ~= floor(config.maxRerolls) then
		problems[#problems + 1] = "maxRerolls"
	end
	if not contains(Priority.FALLBACKS, config.fallback) then problems[#problems + 1] = "fallback" end
	if not contains(Priority.BOE_FALLBACKS, config.boeFallback) then problems[#problems + 1] = "boeFallback" end
	if config.freeRollCost ~= nil and (type(config.freeRollCost) ~= "number" or config.freeRollCost < 0) then
		problems[#problems + 1] = "freeRollCost"
	end
	if type(config.responses) ~= "table" then
		problems[#problems + 1] = "responses"
	else
		local any = false
		for code, r in pairs(config.responses) do
			if type(r) ~= "table" or type(r.tier) ~= "number" or r.tier < 1 or r.tier ~= floor(r.tier) then
				problems[#problems + 1] = "responses:" .. tostring(code)
			elseif r.enabled ~= false then
				any = true
			end
		end
		if not any then problems[#problems + 1] = "responses:none" end
	end
	sort(problems)
	return #problems == 0, problems
end

if ns.addon then ns.addon.Priority = Priority end   -- also reachable from tests
