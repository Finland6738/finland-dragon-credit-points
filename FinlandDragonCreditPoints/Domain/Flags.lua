-- Flags (M5-4): the council's two flags on an item being rolled (docs/ANALISI.md §5.2, §6). Pure Lua 5.1: it never calls
-- the game and never writes a sentence; it returns codes and the players they are about (Domain/Reasons.lua group FLAG
-- and the ML_FLAG_* locale keys give the words).
--
--   UPGRADE_IGNORED  a raider with the addon passes (or has not answered yet) on an item that is a *major* upgrade for
--                    their main spec: "passa per tenersi i crediti bassi in attesa del BiS".
--   POSSIBLE_WASTE   the first in line of the full-cost tier (MS) has a minor upgrade or none, another candidate of the
--                    same tier has a major one: "spreco palese". When both carry an item-level gain, the other's must be at
--                    least `wasteRatio` times the first's.
--
--   CHEAT            possible roll cheating (M7-5d, Domain/Cheat.lua): a `cause` says which of the four cases
--                    (GEAR_SWAP, UNEQUIPPED, UPGRADE_PASSED, OFFSPEC_HIDE) and the flag carries the evidence. The
--                    master looter or the council may add the `penalties.cheat` credits with one click.
--
-- Both look only at the main-spec badge (`m` of the SRESP `vd`), never at the off-spec one. A badge is the one the
-- raider's client computed (Domain/UpgradeScore.lua: the quality tiers of M7-5c against the gear of the fight). A piece
-- the player cannot use never counts. Flags inform the master looter and the council: they never change the winner, the
-- cost or the order (§3.6: the council acts with a reason, M5-5).
--
-- The settings live in the rules' `council` section (Domain/Rules.lua): `flags` (false: no flag at all), `wasteRatio`
-- (preset 2) and `verdicts`, who sees the verdicts and the flags besides the master looter: "council" (preset: whoever
-- holds council.member), "officers" (whoever sees the session's read-only window, award.confirm) or "ml" (the master
-- looter only).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Flags = {}
ns.Flags, ns.modules.Flags = Flags, Flags

local type, pairs, ipairs, tostring, sort = type, pairs, ipairs, tostring, table.sort
local huge = math.huge

Flags.CODES = { "UPGRADE_IGNORED", "CHEAT", "POSSIBLE_WASTE" }
Flags.VISIBILITY = { ml = true, council = true, officers = true }
Flags.RATIO_MIN, Flags.RATIO_MAX = 1, 100

-- The preset of the rules' `council` keys this module owns. A fresh copy on every call.
function Flags.DefaultConfig()
	return { flags = true, wasteRatio = 2, verdicts = "council" }
end

local function isNum(n) return type(n) == "number" and n == n and n > -huge and n < huge end

-- Checks the keys of the `council` section this module owns: a list of problem codes ("council.<field>"), empty when
-- valid.
function Flags.ValidateConfig(c)
	local p = {}
	if type(c) ~= "table" then return { "council" } end
	if type(c.flags) ~= "boolean" then p[#p + 1] = "council.flags" end
	local r = c.wasteRatio
	if not isNum(r) or r < Flags.RATIO_MIN or r > Flags.RATIO_MAX then p[#p + 1] = "council.wasteRatio" end
	if not Flags.VISIBILITY[c.verdicts] then p[#p + 1] = "council.verdicts" end
	return p
end

---------------------------------------------------------------------------------------------------------------------
-- Verdicts

local function U() return ns.UpgradeScore end

-- The main-spec verdict of a player's `vd` as UpgradeScore.Unpack gives it, or nil (none, damaged, not usable, or the
-- BIG / SMALL of a client older than M7-5c).
local function mainVerdict(vd)
	if type(vd) ~= "table" then return nil end
	local r = U().Unpack(vd.m)
	if not r or r.usable == false then return nil end
	if r.ilvlDelta ~= nil and not isNum(r.ilvlDelta) then return nil end
	return r
end
Flags.MainVerdict = mainVerdict

-- A major upgrade.
local function isBig(r) return r ~= nil and r.verdict == "MAJOR" end
Flags.IsBig = isBig

-- A minor upgrade or none.
local function isLow(r) return r ~= nil and (r.verdict == "MINOR" or r.verdict == "NONE") end

---------------------------------------------------------------------------------------------------------------------
-- The line

-- The candidates of the full-cost tier in line order: `head` first (the rules' winner once the proposal is written),
-- then fewer credits, then the higher roll, then the name. input = { responses = {[p] = code}, main = {[code] = true},
-- players = {[p] = true} | nil (who may count; nil = everybody who answered), credits = {[p] = n}, rolls = {[p] = n},
-- head = p | nil }.
function Flags.Line(input)
	local out = {}
	local players = input.players
	for p, code in pairs(type(input.responses) == "table" and input.responses or {}) do
		if type(p) == "string" and input.main and input.main[code] and (players == nil or players[p]) then
			out[#out + 1] = p
		end
	end
	local credits = type(input.credits) == "table" and input.credits or {}
	local rolls = type(input.rolls) == "table" and input.rolls or {}
	local head = input.head
	sort(out, function(a, b)
		if a == head then return b ~= head end
		if b == head then return false end
		local ca, cb = credits[a] or 0, credits[b] or 0
		if ca ~= cb then return ca < cb end
		local ra, rb = rolls[a] or -1, rolls[b] or -1
		if ra ~= rb then return ra > rb end
		return a < b
	end)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- The flags

-- The flags of one item. input = {
--   responses = {[p] = code}   the answers so far ("PASS" included; a player without one has not answered),
--   verdicts  = {[p] = { m, o? }}  the wire verdicts of the SRESP (only `m` is read),
--   main      = {[code] = true}    the responses of the full-cost tier (MS in the preset),
--   players   = {[p] = true} | nil who may count (present with the addon); nil = everybody,
--   gear      = {[p] = cg}        the roll-cheating evidence of the SRESP (Domain/Cheat.lua ReadGear), optional,
--   credits, rolls, head          for the line (Flags.Line); `decided` = true when the rules have already chosen
--                                 (`head` is then the rules' winner, or nil / outside the line when the item went
--                                 elsewhere: no waste is said then),
-- }, council = the rules' `council` section (the second argument, the `upgrade` section, is not read since M7-5c).
-- Returns a list of { code, player, other?, response?, ilvl?, otherIlvl? }: UPGRADE_IGNORED by player name, then CHEAT
-- (by player, then cause; with the fields of Cheat.Detect), then POSSIBLE_WASTE. Empty when `council.flags` is false.
function Flags.Evaluate(input, _, council)
	local out = {}
	if type(input) ~= "table" then return out end
	council = type(council) == "table" and council or Flags.DefaultConfig()
	if council.flags == false then return out end
	local ratio = isNum(council.wasteRatio) and council.wasteRatio or Flags.DefaultConfig().wasteRatio
	local responses = type(input.responses) == "table" and input.responses or {}
	local verdicts = type(input.verdicts) == "table" and input.verdicts or {}
	local players = type(input.players) == "table" and input.players or nil

	-- Upgrade ignored: a pass (or no answer) on a big main-spec upgrade.
	local ignored = {}
	for p, vd in pairs(verdicts) do
		local response = responses[p]
		if type(p) == "string" and (players == nil or players[p]) and (response == nil or response == "PASS") then
			local r = mainVerdict(vd)
			if isBig(r) then
				ignored[#ignored + 1] = { code = "UPGRADE_IGNORED", player = p, response = response, ilvl = r.ilvlDelta }
			end
		end
	end
	sort(ignored, function(a, b) return a.player < b.player end)
	for _, f in ipairs(ignored) do out[#out + 1] = f end

	-- Possible roll cheating (M7-5d): the four cases of Domain/Cheat.lua. A pass on a major upgrade is already the
	-- UPGRADE_IGNORED above (Flags.CheatCause makes it the case UPGRADE_PASSED): no second flag for it.
	if ns.Cheat then
		local passed = {}
		for _, f in ipairs(ignored) do if f.response == "PASS" then passed[f.player] = true end end
		for _, f in ipairs(ns.Cheat.Evaluate({ responses = responses, verdicts = verdicts, gear = input.gear,
			main = input.main, players = players })) do
			if not (f.cause == "UPGRADE_PASSED" and passed[f.player]) then out[#out + 1] = f end
		end
	end

	-- Possible waste: the first in line has little or nothing, another main-spec candidate a big upgrade.
	local line = Flags.Line({ responses = responses, main = input.main or {}, players = players, credits = input.credits,
		rolls = input.rolls, head = input.head })
	local first = line[1]
	if first and input.decided and first ~= input.head then first = nil end
	local low = first and mainVerdict(verdicts[first]) or nil
	if first and isLow(low) then
		local best, bestR
		for i = 2, #line do
			local p = line[i]
			local r = mainVerdict(verdicts[p])
			if isBig(r) then
				local mine, theirs = low.ilvlDelta, r.ilvlDelta
				local enough = mine == nil or mine <= 0 or theirs == nil or theirs >= ratio * mine
				if enough then
					local better = best == nil
						or (theirs or huge) > (bestR.ilvlDelta or huge)
						or ((theirs or huge) == (bestR.ilvlDelta or huge) and p < best)
					if better then best, bestR = p, r end
				end
			end
		end
		if best then
			out[#out + 1] = { code = "POSSIBLE_WASTE", player = first, other = best, ilvl = low.ilvlDelta,
				otherIlvl = bestR.ilvlDelta }
		end
	end
	return out
end

-- The roll-cheating case a flag stands for (M7-5d), or nil: a CHEAT flag's cause, and UPGRADE_PASSED for an
-- UPGRADE_IGNORED that is a pass (a missing answer is never cheating).
function Flags.CheatCause(f)
	if type(f) ~= "table" then return nil end
	if f.code == "CHEAT" then return f.cause end
	if f.code == "UPGRADE_IGNORED" and f.response == "PASS" then return "UPGRADE_PASSED" end
	return nil
end

-- The distinct codes of a list of flags, in order.
function Flags.Codes(list)
	local out, seen = {}, {}
	for _, f in ipairs(list or {}) do
		if not seen[f.code] then seen[f.code] = true; out[#out + 1] = f.code end
	end
	return out
end

-- The flags that name a player (as the flagged one or as the other candidate): {[player] = { code, ... }}.
function Flags.ByPlayer(list)
	local out = {}
	local function add(p, code)
		if not p then return end
		out[p] = out[p] or {}
		for _, c in ipairs(out[p]) do if c == code then return end end
		out[p][#out[p] + 1] = code
	end
	for _, f in ipairs(list or {}) do
		add(f.player, f.code)
		add(f.other, f.code)
	end
	return out
end

-- May a client see the verdicts and the flags? who = { ml = true } (the master looter: always), or { council = bool
-- (holds council.member), officer = bool (holds award.confirm) } under the rules' council.verdicts.
function Flags.MaySee(council, who)
	if type(who) ~= "table" then return false end
	if who.ml then return true end
	local v = type(council) == "table" and council.verdicts or "council"
	if v == "officers" then return who.officer == true end
	if v == "council" then return who.council == true end
	return false
end

if ns.addon then ns.addon.Flags = Flags end   -- also reachable from tests
