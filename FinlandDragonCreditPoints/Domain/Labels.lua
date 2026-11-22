-- Labels: the optional label of a main-spec response and who chose it (docs/ANALISI.md §5.1, M7-2b). Pure Lua 5.1: it never
-- calls the game. The label (BiS, big upgrade, small upgrade, situational: Net/Protocol.lua Session.LABELS) is information for
-- the master looter and the council, never read by the rules (§3.3). The rules' section `responses` says who picks it:
--   labelMode   "auto"     the addon sets the label and the player cannot change it
--               "suggest"  the addon fills it in and the player may change it (the default)
--               "manual"   the player picks it, as before M7-2b
--
-- The suggestion is the data the addon already has: the item is on the player's best-in-slot list -> BIS; the main-spec
-- verdict of the item is a big upgrade -> BIG_UPGRADE; a small one -> SMALL_UPGRADE; anything else (no upgrade, not
-- comparable, not usable, no verdict) -> no label. SITUATIONAL is never suggested: it is the player's own judgement.
--
-- The origin says how the label came to be, so the master looter can tell them apart: AUTO (the addon's own suggestion, kept),
-- CHANGED (the addon had a suggestion and the player chose another label), MANUAL (the player chose, nothing was suggested).
-- A response with no label has no origin. It travels in the response (`lo`, Net/Protocol.lua) as a plain code.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Labels = {}
ns.Labels, ns.modules.Labels = Labels, Labels

local type, pairs, tostring, sort = type, pairs, tostring, table.sort

Labels.MODES = { "auto", "suggest", "manual" }   -- the order the Settings window lists them
Labels.DEFAULT_MODE = "suggest"
Labels.ORIGINS = { AUTO = true, CHANGED = true, MANUAL = true }

local VALID_MODE = { auto = true, suggest = true, manual = true }

function Labels.DefaultConfig()
	return { labelMode = Labels.DEFAULT_MODE }
end

local FIELDS = { labelMode = true }

-- Returns true, or false and a sorted list of codes.
function Labels.ValidateConfig(c)
	if type(c) ~= "table" then return false, { "responses" } end
	local p = {}
	if not VALID_MODE[c.labelMode] then p[#p + 1] = "labelMode" end
	for k in pairs(c) do
		if not FIELDS[k] then p[#p + 1] = "unknown:" .. tostring(k) end
	end
	sort(p)
	return #p == 0, p
end

-- The mode a client applies: the one the master looter's session says (the guild's rules in force when it opened). A
-- session that says nothing (an older client) is left as it was before M7-2b, the player's own choice.
function Labels.Mode(value)
	if VALID_MODE[value] then return value end
	return "manual"
end

-- The label the addon proposes for an item: `onWishlist` (the item is on the player's best-in-slot list) and `verdict` (a
-- main-spec result of Domain/UpgradeScore.lua, or nil). A code, or nil for no label.
function Labels.Suggest(onWishlist, verdict)
	if onWishlist == true then return "BIS" end
	if type(verdict) == "table" and verdict.usable ~= false then
		if verdict.verdict == "BIG" then return "BIG_UPGRADE" end
		if verdict.verdict == "SMALL" then return "SMALL_UPGRADE" end
	end
	return nil
end

-- A valid origin code, or nil.
function Labels.Origin(code)
	if type(code) == "string" and Labels.ORIGINS[code] then return code end
	return nil
end

-- The origin of `label` when the player picks it while the addon suggests `suggestion` (nil: nothing suggested).
function Labels.OriginOf(label, suggestion)
	if label == nil then return nil end
	if suggestion == nil then return "MANUAL" end
	return label == suggestion and "AUTO" or "CHANGED"
end

if ns.addon then ns.addon.Labels = Labels end   -- also reachable from tests
