-- SelfCheck: the player's own readiness snapshot, read from the game (docs/ANALISI.md §4.2, ADR 0010, M8-2). Lua 5.1.
-- Everything goes through Core/Compat.lua, every name checked against the Forever API dump:
--   GetInventoryItemLink("player", slot)             Compat.Item.EquippedLinkState: the enchant is the link's 2nd field
--   C_Item.GetItemInfoInstant(link)                  Compat.Item.Instant: may the off hand / ranged item carry an enchant
--   C_UnitAuras.GetBuffDataByIndex("player", i)      Compat.Aura.PlayerBuffSpellIDs: the readiness buffs
--   C_Item.GetItemCount(itemID, false, false)        Compat.Item.Count: the bag counts of the configured item ids only
--   UnitClass("player"), the active specialization   Compat.Player.ClassFile, Compat.Spec.Active
--   InCombatLockdown, IsEncounterInProgress          Compat.InCombat, Compat.Encounter.InProgress: never read then
--
-- The snapshot is Domain/Readiness.lua's shape. Only the player's own data, and only what the check needs: the enchant
-- state of the enchantable slots (yes / no / unknown, never the enchant or the item), the readiness buff kinds, and the
-- count of each category asked, summed over the item ids of Data/Readiness.lua. Nothing else of the bags is read. A value
-- that is secret or cannot be read is "unknown", never guessed.
--
-- SelfCheck.Busy()          true in combat or during a boss encounter: the snapshot waits (Net/Readiness.lua)
-- SelfCheck.Build(cats)     the snapshot, with the counts of the categories `cats` (a list of codes; nil = all);
--                           nil and "BUSY" in combat or during an encounter
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local SelfCheck = {}
ns.SelfCheck, ns.modules.SelfCheck = SelfCheck, SelfCheck

local type, ipairs = type, ipairs

local function C() return ns.Compat end
local function D() return ns.ReadinessData end

SelfCheck.stats = { built = 0, busy = 0 }

function SelfCheck.Busy()
	return C().InCombat() or C().Encounter.InProgress()
end

-- The enchant state of every enchantable slot that holds an item.
local function readSlots()
	local out = {}
	for _, slot in ipairs(D().SLOTS) do
		local link, state = C().Item.EquippedLinkState(slot)
		if state ~= C().AVAILABLE then
			out[slot] = "UNKNOWN"
		elseif link then
			local able = D().Enchantable(slot, C().Item.Instant(link))
			if able == nil then
				out[slot] = "UNKNOWN"
			elseif able then
				local enchanted = ns.Readiness.EnchantOf(link)
				if enchanted == nil then out[slot] = "UNKNOWN"
				else out[slot] = enchanted and "YES" or "NO" end
			end
		end
	end
	return out
end

-- The readiness buff kinds active, and whether every aura could be read.
local function readBuffs()
	local ids, hidden = C().Aura.PlayerBuffSpellIDs()
	local buffs = {}
	if not ids then return buffs, false end
	for _, id in ipairs(ids) do
		local kind = D().BuffOf(id)
		if kind then buffs[kind] = true end
	end
	return buffs, hidden == 0
end

-- The count of each category asked (a category with an id that could not be counted is left out: unknown).
local function readCounts(cats)
	local counts = {}
	for _, c in ipairs(D().CATEGORIES) do
		local wanted = cats == nil
		if not wanted then
			for _, code in ipairs(cats) do if code == c.code then wanted = true break end end
		end
		if wanted then
			local total = 0
			for _, id in ipairs(c.items) do
				local n = C().Item.Count(id)
				if n == nil then total = nil break end
				total = total + n
			end
			counts[c.code] = total
		end
	end
	return counts
end

function SelfCheck.Build(cats)
	if SelfCheck.Busy() then
		SelfCheck.stats.busy = SelfCheck.stats.busy + 1
		return nil, "BUSY"
	end
	local active = C().Spec.Active()
	local buffs, known = readBuffs()
	local snap = {
		class = C().Player.ClassFile(), spec = active and active.id or nil,
		slots = readSlots(), buffs = buffs, buffsKnown = known, counts = readCounts(type(cats) == "table" and cats or nil),
	}
	if snap.class and not D().CLASSES[snap.class] then snap.class = nil end
	SelfCheck.stats.built = SelfCheck.stats.built + 1
	return snap
end

if ns.addon then ns.addon.SelfCheck = SelfCheck end   -- also reachable from tests
