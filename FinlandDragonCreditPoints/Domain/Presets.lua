-- Presets: ready-made loot rules a Guild Master starts from (docs/ANALISI.md §10). Pure Lua 5.1: it never calls the game.
--
-- Every preset is a whole configuration of Domain/Rules.lua, built from the "Patto" defaults with a few changes; the
-- GM picks one and edits it, and the rules are written in the ledger with Rules.Change (CONFIG_CHANGED keeps the
-- preset's code for the audit). Codes, never names: the locales give the names (M2-7, M7-2).
--   PATTO         the guild's regulation (§3.1): fewest credits wins, then the roll, then a reroll among the tied;
--                 off-spec only when nobody needs it for main-spec and free; late joiners at the floor of the average.
--   ROLL_ONLY     "Solo roll": the highest roll wins, nothing costs credits (main-spec still before off-spec).
--   LOOT_COUNCIL  "Loot council puro": the council decides every item by vote, nothing costs credits; the addon still
--                 shows its proposal and the rolls as a hint.
--   EPGP_SIMPLE   "EPGP semplice": credits are the gear points and the nights played the effort, so the lowest credits
--                 per night played wins; costs as in Patto; late joiners at the average.
-- Every preset passes Rules.Validate; the rank permissions are not part of a preset (Domain/Permissions.lua).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Presets = {}
ns.Presets, ns.modules.Presets = Presets, Presets

local type, pairs, ipairs = type, pairs, ipairs

Presets.ORDER = { "PATTO", "ROLL_ONLY", "LOOT_COUNCIL", "EPGP_SIMPLE" }
Presets.DEFAULT = "PATTO"

-- Every number of a cost matrix and every response multiplier set to 0 (cells "council" stay: a legendary is still
-- the council's).
local function free(cost)
	for _, row in pairs(cost.matrix) do
		for q, cell in pairs(row) do
			if type(cell) == "number" then row[q] = 0 end
		end
	end
	for r in pairs(cost.responseMultiplier) do cost.responseMultiplier[r] = 0 end
	cost.overrides = {}
end

local BUILD = {
	PATTO = function(r) return r end,
	ROLL_ONLY = function(r)
		r.priority.metric = "roll"
		free(r.cost)
		r.members.lateJoin.method = "zero"
		r.legendary.mode = "roll"
		r.priority.fallback = "freeroll"
		return r
	end,
	LOOT_COUNCIL = function(r)
		r.session.awardMode = "council"
		r.council.vote = true
		free(r.cost)
		r.members.lateJoin.method = "zero"
		r.legendary.mode = "vote"
		return r
	end,
	EPGP_SIMPLE = function(r)
		r.priority.metric = "creditsPerNight"
		return r
	end,
}

-- True for a preset code.
function Presets.Has(code)
	return BUILD[code] ~= nil
end

-- The rules of a preset (a fresh table), or nil and "UNKNOWN_PRESET".
function Presets.Get(code)
	local build = BUILD[code]
	if not build then return nil, "UNKNOWN_PRESET" end
	return build(ns.Rules.DefaultConfig())
end

-- The preset whose rules equal `rules` exactly, or nil (the GM changed something after picking it).
function Presets.Match(rules)
	for _, code in ipairs(Presets.ORDER) do
		if #ns.Rules.Diff(Presets.Get(code), rules) == 0 then return code end
	end
	return nil
end

-- Writes the rules of a preset in the ledger: Rules.Change with { author, ts, confirmed? } and the preset's code.
function Presets.Apply(L, code, draft, opts)
	local rules, err = Presets.Get(code)
	if not rules then return nil, err end
	draft = draft or {}
	return ns.Rules.Change(L, { author = draft.author, ts = draft.ts, confirmed = draft.confirmed, rules = rules,
		preset = code }, opts)
end

if ns.addon then ns.addon.Presets = Presets end   -- also reachable from tests
