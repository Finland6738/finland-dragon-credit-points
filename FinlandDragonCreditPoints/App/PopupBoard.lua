-- PopupBoard: what the player's item popup shows, as plain data (docs/ANALISI.md §5.1, §6, M4-6). Lua 5.1, no frames: it
-- reads the loot session as this client sees it (the view of Net/Protocol.lua, the same on the master looter's client
-- and on every raider's), the player's own draft answer and the guild's credits this client knows, and returns one
-- `board` that UI/Windows/MemberLootPopup.lua draws and that the tests read. It decides nothing about the award: the
-- rules and the roll order are the master looter's; this only says what the player may do now.
--
-- Board = { cards = { card, ... } }   (one card per open round: the session runs one item at a time, so one card in
-- practice; the popup stacks as many as the board gives)
-- card = {
--   key ("<session>:<item>:<round>"), item (index), round (number), count (items in the session), itemID, category,
--   council (the cost is set by the council), cost (what the shown response pays; the full-cost response's before an
--   answer), encounter (boss id) | nil, boss (name) | nil,
--   kind ("ROLL" | "REROLL"), stage ("TIER" | "FREE_ROLL"), tier, collect (the round collects the responses),
--   offered = { { code, tier, cost } } (the responses on offer, best tier first; PASS is not in the list),
--   main (the code of the best tier: the one a label belongs to), labels = { codes } (the chips; nil in a round that
--   no longer collects the responses), labelsOn (a label can be set now: the answer is main-spec or still empty),
--   response, label, note (the player's own answer, nil before one),
--   canAnswer (response, label and note can still change), canRoll (the player rolls in this round), rolled,
--   hint = CHOOSE | UNUSABLE | PASSED | LATER | ROLL | ROLLED | REROLL | FREE | TURN (a locale hint, see the window),
--   upgrade (M5-2: the verdicts of this player for the item, UpgradeAdvisor.For: { ms, os | nil, specs, autoPass, equipped,
--   wire }; nil when the rules turn them off or the item's data is not loaded yet), preselect ("PASS" when the item cannot
--   be used, the rules ask for it and the player has not answered: the window shows it selected, nothing is sent),
--   remaining (seconds, nil without a timer), paused,
--   credits, position (the player's credits and estimated place in the queue, nil when this client does not know them),
--   rollMin, rollMax,
-- }
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local PB = {}
ns.PopupBoard, ns.modules.PopupBoard = PB, PB

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local max = math.max

PB.MAX_CARDS = 4
PB.LABELS = { "BIS", "BIG_UPGRADE", "SMALL_UPGRADE", "SITUATIONAL" }   -- Net/Protocol.lua Session.LABELS, the order of the chips
PB.MAX_NOTE = 80                  -- bytes of a note (the protocol's limit)
PB.ROLL_MIN, PB.ROLL_MAX = 1, 100 -- the range the rules count (Domain/Priority.lua rollMin / rollMax)
-- The tier of the usual responses, for a master looter whose session message does not say (an older client).
local DEFAULT_TIERS = { MS = 1, OS = 2, TMOG = 3 }

local function me() return ns.GuildRanks and ns.GuildRanks.Me() or nil end

-- A note cut to at most PB.MAX_NOTE bytes without splitting a UTF-8 character; control characters become spaces.
function PB.ClipNote(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("%c", " ")
	if #text > PB.MAX_NOTE then
		text = text:sub(1, PB.MAX_NOTE)
		local i = #text
		while i > 0 do   -- drop a character that was cut in the middle
			local b = text:byte(i)
			if b < 0x80 then break end
			if b >= 0xC0 then
				local need = b >= 0xF0 and 4 or b >= 0xE0 and 3 or 2
				if #text - i + 1 < need then text = text:sub(1, i - 1) end
				break
			end
			i = i - 1
		end
	end
	if text == "" then return nil end
	return text
end

-- The responses on offer for an item, best tier first: { { code, tier, cost } }.
function PB.Offered(view, item)
	local tiers = view and view.tiers
	if type(tiers) ~= "table" then
		tiers = {}
		for code in pairs(item and item.cs or {}) do tiers[code] = DEFAULT_TIERS[code] or 9 end
	end
	local list = {}
	for code, tier in pairs(tiers) do list[#list + 1] = { code = code, tier = tier, cost = item and item.cs and item.cs[code] } end
	table.sort(list, function(a, b)
		if a.tier ~= b.tier then return a.tier < b.tier end
		return a.code < b.code
	end)
	return list
end

-- The boss of an encounter id in the client's language (the Encounter Journal), else the table's English name; nil
-- when the id is not a boss of the guild's raids.
function PB.BossName(encounterID)
	if not ns.Instances or type(encounterID) ~= "number" then return nil end
	local _, boss = ns.Instances.OfEncounter(encounterID)
	if not boss then return nil end
	local E = ns.Compat and ns.Compat.Encounter
	local name = E and E.JournalName(boss.journalID, boss.encounterID)
	return name or boss.name
end

---------------------------------------------------------------------------------------------------------------------
-- The player's credits and place in the queue

PB.standing = nil   -- cache: { ledger, count, season, rows }

-- The player's credits and estimated place among the raid members who are in the guild's table: { credits, position },
-- or nil when this client has no ledger, no season or no row for the player. The place is `1 + the members in the
-- raid with fewer credits` (a tie is settled by the roll, hence "estimated"). `raid` is the last GROUP_SCANNED snapshot.
function PB.Standing(name, raid)
	local NC = ns.NightController
	local L = NC and NC:Ledger()
	if not L or not name or not ns.Season or not ns.CreditTable then return nil end
	local season = ns.Season.Current(L)
	if not season then return nil end
	local count = ns.Ledger.Count(L)
	local cache = PB.standing
	if not cache or cache.ledger ~= L or cache.count ~= count or cache.season ~= season.id then
		local built = ns.CreditTable.Build(L, season.id)
		cache = { ledger = L, count = count, season = season.id, rows = built and built.rows or {} }
		PB.standing = cache
	end
	local function isMine(row)
		if row.member == name then return true end
		for _, a in ipairs(row.alts or {}) do if a == name then return true end end
		return false
	end
	local inRaid = type(raid) == "table" and raid.inRaid and raid.complete and type(raid.members) == "table"
	local function counts(row)
		if not inRaid or isMine(row) then return true end
		if raid.members[row.member] then return true end
		for _, a in ipairs(row.alts or {}) do if raid.members[a] then return true end end
		return false
	end
	local mine
	for _, row in ipairs(cache.rows) do
		if isMine(row) then mine = row break end
	end
	if not mine then return nil end
	local position = 1
	for _, row in ipairs(cache.rows) do
		if row ~= mine and counts(row) and row.total < mine.total then position = position + 1 end
	end
	return { credits = mine.total, position = position }
end

---------------------------------------------------------------------------------------------------------------------
-- The board

-- Build(view, env): env = { me, now (the local clock), draft = { key, rs, lb, n } | nil (the answer being typed in the
-- round `key`), rolled = function(key), dismissed = function(key), standing = function() -> { credits, position },
-- upgrade = function(itemID) -> advice | nil (UpgradeAdvisor.For), wish = function(itemID) -> boolean (the BiS list) }.
function PB.Build(view, env)
	env = env or {}
	local board = { cards = {} }
	if type(view) ~= "table" or view.ended then return board end
	local round = view.round
	if not round or not view.items[round.i] then return board end
	local index = round.i
	local item = view.items[index]
	local key = view.s .. ":" .. index .. ":" .. round.r
	if env.dismissed and env.dismissed(key) then return board end

	local offered = PB.Offered(view, item)
	local tiers = {}
	for _, o in ipairs(offered) do tiers[o.code] = o.tier end
	local main = offered[1] and offered[1].code or nil

	-- the player's answer: the draft of this round, else what the session knows
	local answer = env.draft and env.draft.key == key and env.draft or nil
	local mine = answer or (view.responses[index] and view.responses[index][env.me or me()]) or nil
	local response = mine and (mine.rs) or nil
	local label, note = mine and mine.lb, mine and mine.n
	local tier = response and tiers[response] or nil

	local collect = round.cl == true
	local rolled = env.rolled and env.rolled(key) or false

	-- may the player roll in this round?
	local canRoll
	if round.k == "REROLL" then
		canRoll = false
		for _, p in ipairs(round.am or {}) do
			if p == (env.me or me()) then canRoll = true end
		end
	elseif round.g == "FREE_ROLL" then
		canRoll = true
	else
		canRoll = response ~= nil and response ~= "PASS" and tier ~= nil and (round.tr == nil or tier == round.tr)
	end
	-- a round that is not collecting responses is for the players who roll in it: the others see no card
	if not collect and not canRoll then return board end

	local advice = env.upgrade and env.upgrade(item.id) or nil
	local preselect = collect and not rolled and response == nil and advice and advice.autoPass and "PASS" or nil

	local hint
	if rolled then hint = "ROLLED"
	elseif round.k == "REROLL" then hint = "REROLL"
	elseif round.g == "FREE_ROLL" then hint = "FREE"
	elseif collect then
		if response == nil then hint = preselect and "UNUSABLE" or "CHOOSE"
		elseif response == "PASS" then hint = "PASSED"
		elseif canRoll then hint = "ROLL"
		else hint = "LATER" end
	else
		hint = "TURN"
	end

	local shown = response and response ~= "PASS" and response or main
	local cost = shown and item.cs and item.cs[shown] or nil
	local remaining = round.rm
	if round.deadline and not view.paused then remaining = max(0, round.deadline - (env.now or 0)) end

	local standing = env.standing and env.standing() or nil
	board.cards[1] = {
		key = key, item = index, round = round.r, count = #view.items, itemID = item.id, category = item.ca,
		council = item.co == true or cost == nil, cost = cost, encounter = view.e, boss = env.boss and env.boss(view.e) or nil,
		kind = round.k, stage = round.g, tier = round.tr, collect = collect, offered = offered, main = main,
		labels = collect and PB.LABELS or nil, labelsOn = collect and not rolled and (response == nil or response == main),
		response = response, label = label, note = note,
		canAnswer = collect and not rolled, canRoll = canRoll and not rolled, rolled = rolled, hint = hint,
		remaining = remaining, paused = view.paused == true, credits = standing and standing.credits or nil,
		position = standing and standing.position or nil, rollMin = PB.ROLL_MIN, rollMax = PB.ROLL_MAX,
		upgrade = advice, preselect = preselect,
		wish = env.wish and env.wish(item.id) == true or false,   -- on the player's own best-in-slot list (M5-3)
	}
	return board
end

if ns.addon then ns.addon.PopupBoard = PB end   -- also reachable from tests
