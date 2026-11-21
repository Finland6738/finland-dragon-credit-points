-- Specs: the fixed table specID -> class, English name, role (docs/specs/site-export.md §3.1, §7; M3-3b). Lua 5.1, data
-- only.
--
-- A player's declaration stores specs as numeric ids (Domain/Roster.lua). The site wants the **English** spec name and
-- its own role word, and a client in another language gives translated names, so they come from here. Loading this file
-- plugs the table into Roster.SpecInfo: from then on the class and the role of a declaration are derived from the MS1
-- and every declared spec must belong to the declared class.
--
-- Only the nine classes of the game (Roster.CLASSES). [verify] on WoW Forever (spike S6): the ids are the client's
-- specIDs of the original game; the rogue's 260 is "Combat" as on the site.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Specs = {}
ns.Specs, ns.modules.Specs = Specs, Specs

local type, ipairs = type, ipairs

Specs.LIST = {
	{ id = 71, class = "WARRIOR", name = "Arms", role = "DAMAGER" },
	{ id = 72, class = "WARRIOR", name = "Fury", role = "DAMAGER" },
	{ id = 73, class = "WARRIOR", name = "Protection", role = "TANK" },
	{ id = 65, class = "PALADIN", name = "Holy", role = "HEALER" },
	{ id = 66, class = "PALADIN", name = "Protection", role = "TANK" },
	{ id = 70, class = "PALADIN", name = "Retribution", role = "DAMAGER" },
	{ id = 253, class = "HUNTER", name = "Beast Mastery", role = "DAMAGER" },
	{ id = 254, class = "HUNTER", name = "Marksmanship", role = "DAMAGER" },
	{ id = 255, class = "HUNTER", name = "Survival", role = "DAMAGER" },
	{ id = 259, class = "ROGUE", name = "Assassination", role = "DAMAGER" },
	{ id = 260, class = "ROGUE", name = "Combat", role = "DAMAGER" },
	{ id = 261, class = "ROGUE", name = "Subtlety", role = "DAMAGER" },
	{ id = 256, class = "PRIEST", name = "Discipline", role = "HEALER" },
	{ id = 257, class = "PRIEST", name = "Holy", role = "HEALER" },
	{ id = 258, class = "PRIEST", name = "Shadow", role = "DAMAGER" },
	{ id = 262, class = "SHAMAN", name = "Elemental", role = "DAMAGER" },
	{ id = 263, class = "SHAMAN", name = "Enhancement", role = "DAMAGER" },
	{ id = 264, class = "SHAMAN", name = "Restoration", role = "HEALER" },
	{ id = 62, class = "MAGE", name = "Arcane", role = "DAMAGER" },
	{ id = 63, class = "MAGE", name = "Fire", role = "DAMAGER" },
	{ id = 64, class = "MAGE", name = "Frost", role = "DAMAGER" },
	{ id = 265, class = "WARLOCK", name = "Affliction", role = "DAMAGER" },
	{ id = 266, class = "WARLOCK", name = "Demonology", role = "DAMAGER" },
	{ id = 267, class = "WARLOCK", name = "Destruction", role = "DAMAGER" },
	{ id = 102, class = "DRUID", name = "Balance", role = "DAMAGER" },
	{ id = 103, class = "DRUID", name = "Feral", role = "DAMAGER" },
	{ id = 104, class = "DRUID", name = "Guardian", role = "TANK" },
	{ id = 105, class = "DRUID", name = "Restoration", role = "HEALER" },
}

-- The site's role word for a role code (roster.json `role`).
Specs.SITE_ROLE = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }

local BY_ID = {}
for _, s in ipairs(Specs.LIST) do BY_ID[s.id] = s end

-- { id, class, name, role } of a specID, or nil (unknown spec).
function Specs.Get(specID)
	if type(specID) ~= "number" then return nil end
	return BY_ID[specID]
end

-- The specs of a class ("PRIEST"), in the table's order.
function Specs.OfClass(class)
	local out = {}
	for _, s in ipairs(Specs.LIST) do
		if s.class == class then out[#out + 1] = s end
	end
	return out
end

-- The site's words for a spec: class in lower case ("priest"), English name ("Holy"), role ("healer"); nil when unknown.
function Specs.Site(specID)
	local s = Specs.Get(specID)
	if not s then return nil end
	return { class = s.class:lower(), spec = s.name, role = Specs.SITE_ROLE[s.role] }
end

-- The roster's hook (Domain/Roster.lua): class and role of a declared spec.
if ns.Roster then ns.Roster.SpecInfo = Specs.Get end

if ns.addon then ns.addon.Specs = Specs end   -- also reachable from tests
