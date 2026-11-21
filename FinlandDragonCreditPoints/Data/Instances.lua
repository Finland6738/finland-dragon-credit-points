-- Instances: the fixed table of the raids of the pack (docs/specs/site-export.md §3.3, §7; M3-3b). Lua 5.1, data only.
--
-- The client names instances and bosses in its own language and knows nothing of the community site's slugs and order,
-- so the export (M6-4) and the Progress tab (M3-8b) read them from here: per raid the client's `instanceID`, the site's
-- slug, the **English** name exactly as the site's `content/games/wow-forever/progress.json` writes it, the size, and
-- the bosses in the site's order with the `encounterID` of ENCOUNTER_END (the DungeonEncounter id) and the English name.
-- `journalInstanceID` / `journalID` are the Encounter Journal's ids, used only to show the names in the client's language
-- (Compat.Encounter.JournalName checks that the journal entry is the same encounter, else the English name stays).
--
-- [verify] on WoW Forever (spike): the instance ids (GetInstanceInfo 8th value), the encounter ids of ENCOUNTER_END and
-- the journal ids are the ones of the original game until a real kill confirms them. A wrong encounter id only means
-- the kill is recorded under an id the table does not list (it is still in the ledger, and a fixed table maps it later).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Instances = {}
ns.Instances, ns.modules.Instances = Instances, Instances

local type, ipairs = type, ipairs

-- In the site's order (the site numbers instances and bosses as they come).
Instances.LIST = {
	{
		instanceID = 409, slug = "mc", name = "Molten Core", size = 40, journalInstanceID = 741,
		bosses = {
			{ encounterID = 663, journalID = 1519, name = "Lucifron" },
			{ encounterID = 664, journalID = 1520, name = "Magmadar" },
			{ encounterID = 665, journalID = 1521, name = "Gehennas" },
			{ encounterID = 666, journalID = 1522, name = "Garr" },
			{ encounterID = 667, journalID = 1523, name = "Shazzrah" },
			{ encounterID = 668, journalID = 1524, name = "Baron Geddon" },
			{ encounterID = 669, journalID = 1525, name = "Sulfuron Harbinger" },
			{ encounterID = 670, journalID = 1526, name = "Golemagg" },
			{ encounterID = 671, journalID = 1527, name = "Majordomo Executus" },
			{ encounterID = 672, journalID = 1528, name = "Ragnaros" },
		},
	},
	{
		-- the site writes the name with a typographic apostrophe: kept as it is, so the merge finds the same instance
		instanceID = 249, slug = "ony", name = "Onyxia\226\128\153s Lair", size = 40, journalInstanceID = 760,
		bosses = {
			{ encounterID = 1084, journalID = 1651, name = "Onyxia" },
		},
	},
}

local BY_ID, BY_SLUG, BY_ENCOUNTER = {}, {}, {}

-- (Re)builds the indexes; a test that swaps LIST calls it again.
function Instances.Index()
	BY_ID, BY_SLUG, BY_ENCOUNTER = {}, {}, {}
	for _, inst in ipairs(Instances.LIST) do
		BY_ID[inst.instanceID] = inst
		BY_SLUG[inst.slug] = inst
		for i, boss in ipairs(inst.bosses) do
			BY_ENCOUNTER[boss.encounterID] = { instance = inst, boss = boss, index = i }
		end
	end
end
Instances.Index()

-- The instance of a client instanceID, or nil (not a raid of the table).
function Instances.Get(instanceID)
	if type(instanceID) ~= "number" then return nil end
	return BY_ID[instanceID]
end

-- The instance of a site slug ("mc"), or nil.
function Instances.BySlug(slug)
	if type(slug) ~= "string" then return nil end
	return BY_SLUG[slug]
end

-- The instance, the boss and the boss's position (1-based, the site's order) of an encounter id, or nil.
function Instances.OfEncounter(encounterID)
	if type(encounterID) ~= "number" then return nil end
	local hit = BY_ENCOUNTER[encounterID]
	if not hit then return nil end
	return hit.instance, hit.boss, hit.index
end

if ns.addon then ns.addon.Instances = Instances end   -- also reachable from tests
