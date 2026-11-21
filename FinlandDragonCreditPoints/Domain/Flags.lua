-- Flags (M5-4): the council's two flags on an item being rolled (docs/ANALISI.md §5.2, §6). Pure Lua 5.1: it never calls
-- the game and never writes a sentence; it returns codes and the players they are about (Domain/Reasons.lua group FLAG
-- and the ML_FLAG_* locale keys give the words).
--
--   UPGRADE_IGNORED  a raider with the addon passes (or has not answered yet) on an item that is a *big* upgrade for
--                    their main spec (MS1): "passa per tenersi i crediti bassi in attesa del BiS".
--   POSSIBLE_WASTE   the first in line of the full-cost tier (MS) has a small upgrade or none, another candidate of the
--                    same tier has a big one, at least `wasteRatio` times larger: "spreco palese".
--
-- Both look only at the main-spec verdict (`m` of the SRESP `vd`, §6: MS1 weights), never at the off-spec one. A verdict
-- is the one the raider's client computed (UpgradeScore, M5-2); "big" is checked again against the guild's thresholds
-- (rules section `upgrade`), so a verdict that says BIG with a percentage below the threshold does not raise a flag. A
-- piece the player cannot use never counts. Flags inform the master looter and the council: they never change the
-- winner, the cost or the order (§3.6: the council acts with a reason, M5-5).
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

Flags.CODES = { "UPGRADE_IGNORED", "POSSIBLE_WASTE" }
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

-- The thresholds of the rules' `upgrade` section (the presets for what is missing).
local function thresholds(upgrade)
	local d = U().DefaultConfig()
	upgrade = type(upgrade) == "table" and upgrade or {}
	local function pick(k)
		local v = upgrade[k]
		if isNum(v) then return v end
		return d[k]
	end
	return { big = pick("bigThreshold"), small = pick("smallThreshold"), ilvl = pick("ilvlBigThreshold") }
end

-- The main-spec verdict of a player's `vd` as UpgradeScore.Unpack gives it, or nil (none, damaged, not usable).
local function mainVerdict(vd)
	if type(vd) ~= "table" then return nil end
	local r = U().Unpack(vd.m)
	if not r or r.usable == false then return nil end
	if r.pct ~= nil and not isNum(r.pct) then return nil end
	return r
end
Flags.MainVerdict = mainVerdict

-- A big upgrade by the guild's thresholds: the verdict says BIG and, when it carries a percentage, the percentage
-- reaches the threshold of its basis (item level or stats). A BIG without percentage (an empty slot, or a worn piece
-- that scores 0) stays big.
local function isBig(r, t)
	if not r or r.verdict ~= "BIG" then return false end
	if r.pct == nil then return true end
	return r.pct >= (r.basis == "ILVL" and t.ilvl or t.big)
end
Flags.IsBig = function(r, upgrade) return isBig(r, thresholds(upgrade)) end

-- A small upgrade or none: below the big threshold of its basis.
local function isLow(r, t)
	if not r then return false end
	if r.verdict ~= "SMALL" and r.verdict ~= "NONE" then return false end
	if r.pct ~= nil and r.pct >= (r.basis == "ILVL" and t.ilvl or t.big) then return false end
	return true
end

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
--   credits, rolls, head          for the line (Flags.Line); `decided` = true when the rules have already chosen
--                                 (`head` is then the rules' winner, or nil / outside the line when the item went
--                                 elsewhere: no waste is said then),
-- }, upgrade = the rules' `upgrade` section (thresholds), council = the rules' `council` section.
-- Returns a list of { code, player, other?, response?, pct?, otherPct?, basis? }: UPGRADE_IGNORED by player name, then
-- POSSIBLE_WASTE. Empty when `council.flags` is false.
function Flags.Evaluate(input, upgrade, council)
	local out = {}
	if type(input) ~= "table" then return out end
	council = type(council) == "table" and council or Flags.DefaultConfig()
	if council.flags == false then return out end
	local ratio = isNum(council.wasteRatio) and council.wasteRatio or Flags.DefaultConfig().wasteRatio
	local t = thresholds(upgrade)
	local responses = type(input.responses) == "table" and input.responses or {}
	local verdicts = type(input.verdicts) == "table" and input.verdicts or {}
	local players = type(input.players) == "table" and input.players or nil

	-- Upgrade ignored: a pass (or no answer) on a big main-spec upgrade.
	local ignored = {}
	for p, vd in pairs(verdicts) do
		local response = responses[p]
		if type(p) == "string" and (players == nil or players[p]) and (response == nil or response == "PASS") then
			local r = mainVerdict(vd)
			if isBig(r, t) then
				ignored[#ignored + 1] = { code = "UPGRADE_IGNORED", player = p, response = response, pct = r.pct,
					basis = r.basis }
			end
		end
	end
	sort(ignored, function(a, b) return a.player < b.player end)
	for _, f in ipairs(ignored) do out[#out + 1] = f end

	-- Possible waste: the first in line has little or nothing, another main-spec candidate a big upgrade.
	local line = Flags.Line({ responses = responses, main = input.main or {}, players = players, credits = input.credits,
		rolls = input.rolls, head = input.head })
	local first = line[1]
	if first and input.decided and first ~= input.head then first = nil end
	local low = first and mainVerdict(verdicts[first]) or nil
	if first and isLow(low, t) then
		local best, bestR
		for i = 2, #line do
			local p = line[i]
			local r = mainVerdict(verdicts[p])
			if isBig(r, t) then
				local enough = low.pct == nil or low.pct <= 0 or r.pct == nil or r.pct >= ratio * low.pct
				if enough then
					local better = best == nil
						or (r.pct or huge) > (bestR.pct or huge)
						or ((r.pct or huge) == (bestR.pct or huge) and p < best)
					if better then best, bestR = p, r end
				end
			end
		end
		if best then
			out[#out + 1] = { code = "POSSIBLE_WASTE", player = first, other = best, pct = low.pct, otherPct = bestR.pct,
				basis = bestR.basis }
		end
	end
	return out
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
