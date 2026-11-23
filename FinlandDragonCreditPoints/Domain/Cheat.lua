-- Cheat: roll-cheating detection and its penalty (docs/ANALISI.md §3.6, §5.2, owner rule of 2026-11-22, M7-5d). Pure Lua
-- 5.1: it never calls the game and never writes a sentence (Domain/Reasons.lua groups FLAG / CHEAT and the ML_CHEAT_*
-- locale keys give the words). Lowest credits wins, so the penalty **adds** credits (`penalties.cheat`, preset 2).
--
-- The four cases (the flag's `cause`):
--   GEAR_SWAP       a worn piece of the item's slot has a lower item level at roll time than during the fight (the gear
--                   snapshot of Adapters/GearSnapshot.lua): the player swapped gear to look under-geared;
--   UNEQUIPPED      the slot was filled during the fight and is empty at roll time: the player took the piece off;
--   UPGRADE_PASSED  a pass on an item that is a medium or major upgrade for the main spec (extends M5-4's UPGRADE_IGNORED,
--                   which is only for a major one and also for a missing answer: a missing answer is never cheating);
--   OFFSPEC_HIDE    the piece compared in that slot does not fit the declared main spec (MS1), and without it the item
--                   would be a medium or major upgrade: an off-spec piece hides the upgrade, and the player did not ask
--                   for the item with a full-cost (main) response.
--
-- The evidence comes from the player's own client: the `cg` of the SRESP (Net/Protocol.lua), built by
-- App/UpgradeAdvisor.lua: { g = { { s = slot, f = item level in the fight (0 = empty), n = item level now (0 = empty),
-- fi = item id in the fight, ni = item id now, x = 1 when the compared piece does not fit the main spec } }, h = the
-- packed main-spec badge without the unfitting pieces }. A modified client can lie: the flags are evidence for the master
-- looter and the council, never a verdict, and the master looter can cross-check the gear worn now by inspecting the
-- player (Cheat.CrossCheck, Adapters/InspectCheck.lua). Flags never change the winner, the cost or the order.
--
-- The penalty is a CREDITS_ADJUSTED{member, delta, reason = "CHEAT", cause, item, sid}: written by the master looter or a
-- council member with one click and a confirmation (Cheat.Apply through Council.Adjust and the permission gate), by
-- itself only when the rules say `penalties.autoApply`. Audited like any correction, voidable (AWARD_VOIDED). A member
-- already penalized for the same case on the same item of the same session (even voided: the officer took it back on
-- purpose) is never penalized again.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Cheat = {}
ns.Cheat, ns.modules.Cheat = Cheat, Cheat

local type, pairs, ipairs, floor, sort, tostring = type, pairs, ipairs, math.floor, table.sort, tostring

Cheat.REASON = "CHEAT"   -- the CREDITS_ADJUSTED reason (group CORRECTION of Domain/Reasons.lua)
Cheat.FLAG = "CHEAT"     -- the council flag (group FLAG); its `cause` is a code of group CHEAT
Cheat.CAUSES = { "GEAR_SWAP", "UNEQUIPPED", "UPGRADE_PASSED", "OFFSPEC_HIDE" }
Cheat.IS_CAUSE = { GEAR_SWAP = true, UNEQUIPPED = true, UPGRADE_PASSED = true, OFFSPEC_HIDE = true }
Cheat.DEFAULT_AMOUNT = 2
Cheat.MAX_SLOTS = 3       -- slots a `cg` names (a two-hander against both hands, a ring against the worse of two)
Cheat.MAX_LEVEL = 2000
Cheat.MAX_SID = 40

local ORDER = {}
for i, c in ipairs(Cheat.CAUSES) do ORDER[c] = i end

local function isInt(n, lo, hi) return type(n) == "number" and n == floor(n) and n >= lo and n <= hi end
local function isNum(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end

local IMPORTANT = { MEDIUM = true, MAJOR = true }
local HIDDEN = { MINOR = true, NONE = true, NOT_COMPARABLE = true }

---------------------------------------------------------------------------------------------------------------------
-- The wire

-- A packed badge { v, u?, c?, l? } checked field by field (the `h` of a `cg`), or nil.
local function readBadge(t)
	if type(t) ~= "table" or type(t.v) ~= "string" then return nil end
	local U = ns.UpgradeScore
	if U and not U.VALID_VERDICT[t.v] then return nil end
	local out = { v = t.v }
	if t.u ~= nil then if t.u ~= false then return nil end out.u = false end
	if t.c ~= nil then if type(t.c) ~= "string" or not t.c:match("^[A-Z][A-Z0-9_]*$") then return nil end out.c = t.c end
	if t.l ~= nil then if not isInt(t.l, -Cheat.MAX_LEVEL, Cheat.MAX_LEVEL) then return nil end out.l = t.l end
	return out
end

-- The `cg` of a SRESP checked field by field: a fresh copy, or nil when absent or damaged (the response still counts).
function Cheat.ReadGear(cg)
	if type(cg) ~= "table" then return nil end
	local out = { g = {} }
	if cg.g ~= nil then
		if type(cg.g) ~= "table" or #cg.g > Cheat.MAX_SLOTS then return nil end
		for i, e in ipairs(cg.g) do
			if type(e) ~= "table" or not isInt(e.s, 1, 19) then return nil end
			local c = { s = e.s }
			for _, k in ipairs({ "f", "n" }) do
				if e[k] ~= nil then
					if not isInt(e[k], 0, Cheat.MAX_LEVEL) then return nil end
					c[k] = e[k]
				end
			end
			for _, k in ipairs({ "fi", "ni" }) do
				if e[k] ~= nil then
					if not isInt(e[k], 1, 2147483647) then return nil end
					c[k] = e[k]
				end
			end
			if e.x ~= nil then
				if e.x ~= 1 then return nil end
				c.x = 1
			end
			out.g[i] = c
		end
	end
	if cg.h ~= nil then
		out.h = readBadge(cg.h)
		if not out.h then return nil end
	end
	if #out.g == 0 and not out.h then return nil end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Detection

-- The cheating flags of one player on one item. input = {
--   player, response (nil = no answer yet), main = {[code] = true} (the full-cost responses),
--   verdict = the main-spec badge as UpgradeScore.Unpack gives it (or nil), gear = a Cheat.ReadGear table (or nil),
-- }. Returns a list of { code = "CHEAT", player, cause, slot?, fight?, now?, fightItem?, nowItem?, shown? (the
-- main-spec badge's tier), ilvl?, honest? (the tier without the unfitting piece) } in Cheat.CAUSES order, at most one per cause.
function Cheat.Detect(input)
	local out = {}
	if type(input) ~= "table" or type(input.player) ~= "string" then return out end
	local p, response = input.player, input.response
	local gear = type(input.gear) == "table" and input.gear or {}
	local entries = type(gear.g) == "table" and gear.g or {}
	local seen = {}
	local function add(f)
		if seen[f.cause] then return end
		seen[f.cause] = true
		f.code, f.player = Cheat.FLAG, p
		out[#out + 1] = f
	end
	-- 1 and 2: the gear at roll time against the gear of the fight (only when the fight's is known)
	for _, e in ipairs(entries) do
		if e.f ~= nil and e.n ~= nil and e.f > 0 then
			if e.n == 0 then
				add({ cause = "UNEQUIPPED", slot = e.s, fight = e.f, now = 0, fightItem = e.fi })
			elseif e.n < e.f then
				add({ cause = "GEAR_SWAP", slot = e.s, fight = e.f, now = e.n, fightItem = e.fi, nowItem = e.ni })
			end
		end
	end
	-- 3: a pass on a medium or major main-spec upgrade
	local v = input.verdict
	local usable = type(v) == "table" and v.usable ~= false
	if response == "PASS" and usable and IMPORTANT[v.verdict] then
		add({ cause = "UPGRADE_PASSED", shown = v.verdict, ilvl = isNum(v.ilvlDelta) and v.ilvlDelta or nil })
	end
	-- 4: an off-spec piece hides the upgrade
	local main = type(input.main) == "table" and input.main or {}
	local U = ns.UpgradeScore
	local honest = gear.h and U and U.Unpack(gear.h) or nil
	if response ~= nil and not main[response] and usable and HIDDEN[v.verdict] and honest and honest.usable ~= false
		and IMPORTANT[honest.verdict] then
		for _, e in ipairs(entries) do
			if e.x == 1 then
				add({ cause = "OFFSPEC_HIDE", slot = e.s, nowItem = e.ni or e.fi, fightItem = e.fi, shown = v.verdict,
					honest = honest.verdict, ilvl = isNum(honest.ilvlDelta) and honest.ilvlDelta or nil })
				break
			end
		end
	end
	sort(out, function(a, b) return ORDER[a.cause] < ORDER[b.cause] end)
	return out
end

-- The flags of every player of an item. input = { responses, verdicts = {[p] = { m, o? }}, gear = {[p] = cg},
-- main, players = {[p] = true} | nil }. Sorted by player, then cause.
function Cheat.Evaluate(input)
	local out = {}
	if type(input) ~= "table" then return out end
	local responses = type(input.responses) == "table" and input.responses or {}
	local verdicts = type(input.verdicts) == "table" and input.verdicts or {}
	local gear = type(input.gear) == "table" and input.gear or {}
	local players = type(input.players) == "table" and input.players or nil
	local U = ns.UpgradeScore
	local names, seen = {}, {}
	local function note(p)
		if type(p) == "string" and not seen[p] and (players == nil or players[p]) then seen[p] = true; names[#names + 1] = p end
	end
	for p in pairs(verdicts) do note(p) end
	for p in pairs(gear) do note(p) end
	sort(names)
	for _, p in ipairs(names) do
		local vd = verdicts[p]
		local verdict = type(vd) == "table" and U and U.Unpack(vd.m) or nil
		for _, f in ipairs(Cheat.Detect({ player = p, response = responses[p], main = input.main, verdict = verdict,
			gear = gear[p] })) do
			out[#out + 1] = f
		end
	end
	return out
end

-- The master looter's cross-check of the gear worn now (an inspection, Adapters/InspectCheck.lua). gear = a Cheat.ReadGear
-- table, seen = {[slot] = item level (0 = empty)}. Returns "MATCH", "MISMATCH" (a slot the player reported differs from
-- what the inspection saw) or nil (nothing to compare).
function Cheat.CrossCheck(gear, seen)
	if type(gear) ~= "table" or type(gear.g) ~= "table" or type(seen) ~= "table" then return nil end
	local compared = false
	for _, e in ipairs(gear.g) do
		local level = seen[e.s]
		if e.n ~= nil and type(level) == "number" then
			compared = true
			if level ~= e.n then return "MISMATCH" end
		end
	end
	return compared and "MATCH" or nil
end

---------------------------------------------------------------------------------------------------------------------
-- The penalty

-- The key of one penalty: member, case, item and session.
function Cheat.Key(member, cause, item, sid)
	return tostring(member) .. "|" .. tostring(cause) .. "|" .. tostring(item) .. "|" .. tostring(sid)
end

-- The penalties already written: {[Cheat.Key] = event id} (voided ones included).
function Cheat.Applied(L)
	local Lg = ns.Ledger
	local out = {}
	for _, e in ipairs(Lg.Sorted(L, function(e) return e.type == "CREDITS_ADJUSTED" end)) do
		local p = Lg.Readable(e) and Lg.Payload(e)
		if p and p.reason == Cheat.REASON then
			local k = Cheat.Key(p.member, p.cause, p.item, p.sid)
			if not out[k] then out[k] = e.id end
		end
	end
	return out
end

-- The amount of the rules' `penalties` section (preset 2; 0 = the penalty is off).
function Cheat.Amount(penalties)
	local a = type(penalties) == "table" and penalties.cheat or nil
	if not isNum(a) then return Cheat.DEFAULT_AMOUNT end
	return a
end

-- Writes one penalty: draft = { author, ts, season, member, cause, item?, sid?, amount }. Through Council.Adjust and the
-- trust gate (`opts`). Returns the event, or nil and a code: "cause", "BAD_DELTA" (amount 0 or off), "DUPLICATE", or
-- Council.Adjust's.
function Cheat.Apply(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	if not Cheat.IS_CAUSE[draft.cause] then return nil, "cause" end
	local amount = draft.amount
	if not isNum(amount) or amount <= 0 then return nil, "BAD_DELTA" end
	local item = isInt(draft.item, 1, 2147483647) and draft.item or nil
	local sid = type(draft.sid) == "string" and draft.sid ~= "" and #draft.sid <= Cheat.MAX_SID and draft.sid or nil
	if Cheat.Applied(L)[Cheat.Key(draft.member, draft.cause, item, sid)] then return nil, "DUPLICATE" end
	return ns.Council.Adjust(L, { author = draft.author, ts = draft.ts, season = draft.season, member = draft.member,
		delta = amount, reason = Cheat.REASON, cause = draft.cause, item = item, sid = sid }, opts)
end

if ns.addon then ns.addon.Cheat = Cheat end   -- also reachable from tests
