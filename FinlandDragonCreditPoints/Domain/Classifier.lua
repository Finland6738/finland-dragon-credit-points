-- Classifier: item -> cost category (docs/ANALISI.md §3.2). Pure Lua 5.1: it never calls the game.
--
-- The adapter reads C_Item.GetItemInfoInstant (through Core/Compat.lua) and passes plain numbers and strings:
--   item = { itemID = n, classID = n, subclassID = n, equipLoc = "INVTYPE_...", quality = n, startsQuest = bool }
-- `startsQuest` is the adapter's answer to "this item starts a quest" (the item's tooltip / quest info); the domain
-- only reads the flag.
--
-- The order of the rules, the first that answers wins:
--   1. quest item: classID is the Quest class, OR the item starts a quest, OR its itemID is in the season's token
--      list (the game does not always mark a piece of a chain as a quest item);
--   2. the "classID:subclassID" table (wands, shields, cosmetic armour, mounts, pets);
--   3. the equipLoc table (weapon, off-hand, trinket, jewellery, armour, cloak);
--   4. the classID table (recipes);
--   5. "other".
-- Every table is editable: Classify takes an optional table built from DefaultTable() and changed by the guild.
--
-- The quality threshold: an item whose quality is below the threshold is "not tracked" (it never enters a loot
-- session). The threshold follows the group's loot threshold (GetLootThreshold), which the adapter passes in; the
-- default is blue (RARE), the "green = not tracked" column of the §3.2 matrix.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Classifier = {}
ns.Classifier, ns.modules.Classifier = Classifier, Classifier

local type, pairs, tostring = type, pairs, tostring

-- The categories of the §3.2 matrix, in its row order. "cosmetic" is the row "recipes, mounts, cosmetics".
Classifier.CATEGORIES = { "weapon", "offhand", "trinket", "quest", "jewelry", "armor", "cosmetic", "other" }
Classifier.DEFAULT_CATEGORY = "other"

local KNOWN = {}
for _, c in ipairs(Classifier.CATEGORIES) do KNOWN[c] = true end

-- True for one of the category codes above.
function Classifier.IsCategory(c)
	return KNOWN[c] == true
end

-- Item quality ids (Enum.ItemQuality).
Classifier.QUALITY = { POOR = 0, COMMON = 1, UNCOMMON = 2, RARE = 3, EPIC = 4, LEGENDARY = 5 }
Classifier.DEFAULT_THRESHOLD = Classifier.QUALITY.RARE

-- Item class ids (Enum.ItemClass) the default tables use.
Classifier.CLASS = { WEAPON = 2, ARMOR = 4, RECIPE = 9, QUEST = 12, MISCELLANEOUS = 15 }

-- The editable classification tables. A fresh copy on every call, so a caller may change it freely.
function Classifier.DefaultTable()
	local C = Classifier.CLASS
	return {
		questClassID = C.QUEST,
		-- "classID:subclassID" -> category; checked before equipLoc.
		subclass = {
			[C.WEAPON .. ":19"] = "weapon",          -- wands
			[C.ARMOR .. ":6"] = "offhand",           -- shields
			[C.ARMOR .. ":5"] = "cosmetic",          -- cosmetic armour
			[C.MISCELLANEOUS .. ":2"] = "cosmetic",  -- companion pets
			[C.MISCELLANEOUS .. ":5"] = "cosmetic",  -- mounts
		},
		equipLoc = {
			INVTYPE_WEAPON = "weapon",
			INVTYPE_2HWEAPON = "weapon",
			INVTYPE_WEAPONMAINHAND = "weapon",
			INVTYPE_WEAPONOFFHAND = "weapon",
			INVTYPE_RANGED = "weapon",
			INVTYPE_RANGEDRIGHT = "weapon",       -- guns, crossbows, wands
			INVTYPE_THROWN = "weapon",
			INVTYPE_SHIELD = "offhand",
			INVTYPE_HOLDABLE = "offhand",
			INVTYPE_RELIC = "offhand",            -- librams, idols, totems: the ranged slot, priced like an off-hand
			INVTYPE_TRINKET = "trinket",
			INVTYPE_FINGER = "jewelry",
			INVTYPE_NECK = "jewelry",
			INVTYPE_HEAD = "armor",
			INVTYPE_SHOULDER = "armor",
			INVTYPE_CHEST = "armor",
			INVTYPE_ROBE = "armor",
			INVTYPE_WAIST = "armor",
			INVTYPE_LEGS = "armor",
			INVTYPE_FEET = "armor",
			INVTYPE_WRIST = "armor",
			INVTYPE_HAND = "armor",
			INVTYPE_CLOAK = "armor",
			INVTYPE_BODY = "cosmetic",            -- shirts
			INVTYPE_TABARD = "cosmetic",
		},
		-- classID -> category; checked last.
		class = {
			[C.RECIPE] = "cosmetic",
		},
	}
end

local DEFAULT_TABLE = Classifier.DefaultTable()

-- True when the item starts a quest, is of the Quest class, or is one of the season's tokens.
-- `tokens` is a set { [itemID] = true } (a list of ids works too).
function Classifier.IsQuestItem(item, tokens, tbl)
	tbl = tbl or DEFAULT_TABLE
	if type(item) ~= "table" then return false end
	if item.classID ~= nil and item.classID == tbl.questClassID then return true end
	if item.startsQuest == true then return true end
	if type(tokens) == "table" and item.itemID ~= nil then
		if tokens[item.itemID] == true then return true end
		for _, id in ipairs(tokens) do
			if id == item.itemID then return true end
		end
	end
	return false
end

-- The category of an item, plus the code of the rule that decided it:
-- "QUEST", "SUBCLASS", "EQUIPLOC", "CLASS" or "DEFAULT".
function Classifier.Classify(item, tokens, tbl)
	tbl = tbl or DEFAULT_TABLE
	if type(item) ~= "table" then return Classifier.DEFAULT_CATEGORY, "DEFAULT" end
	if Classifier.IsQuestItem(item, tokens, tbl) then return "quest", "QUEST" end
	if item.classID ~= nil and item.subclassID ~= nil and tbl.subclass then
		local c = tbl.subclass[tostring(item.classID) .. ":" .. tostring(item.subclassID)]
		if c then return c, "SUBCLASS" end
	end
	if type(item.equipLoc) == "string" and item.equipLoc ~= "" and tbl.equipLoc then
		local c = tbl.equipLoc[item.equipLoc]
		if c then return c, "EQUIPLOC" end
	end
	if item.classID ~= nil and tbl.class then
		local c = tbl.class[item.classID]
		if c then return c, "CLASS" end
	end
	return Classifier.DEFAULT_CATEGORY, "DEFAULT"
end

-- True when an item of this quality enters loot sessions: quality >= threshold (the group's loot threshold).
-- An unknown quality is not tracked.
function Classifier.IsTracked(quality, threshold)
	if type(quality) ~= "number" then return false end
	if type(threshold) ~= "number" then threshold = Classifier.DEFAULT_THRESHOLD end
	return quality >= threshold
end

-- Every category a table can produce must be a known one: returns true, or false plus a list of problem codes
-- ("<section>:<key>").
function Classifier.Validate(tbl)
	local problems = {}
	if type(tbl) ~= "table" then return false, { "table" } end
	for _, section in ipairs({ "subclass", "equipLoc", "class" }) do
		local s = tbl[section]
		if s ~= nil and type(s) ~= "table" then
			problems[#problems + 1] = section
		elseif s then
			for k, c in pairs(s) do
				if not KNOWN[c] then problems[#problems + 1] = section .. ":" .. tostring(k) end
			end
		end
	end
	table.sort(problems)
	return #problems == 0, problems
end

if ns.addon then ns.addon.Classifier = Classifier end   -- also reachable from tests
