-- Mock client, part 8: loot method, the loot window, master loot, rolls, encounters and the addon restrictions (M1-3).
--
-- Imitates: Enum.LootMethod, Enum.AddOnRestrictionType, C_PartyInfo.{GetLootMethod, SetLootMethod, IsLootMethodAvailable},
-- C_Loot.IsLegacyLootModeEnabled, IsMasterLooter, GetLootThreshold, GetNumLootItems, GetLootSlotLink, GetLootSlotInfo,
-- GetLootSlotType, GetLootSourceInfo, LootSlotHasItem, GetMasterLootCandidate, GiveMasterLoot, RandomRoll, the loot and roll
-- format globals (RANDOM_ROLL_RESULT, LOOT_ITEM...), IsEncounterInProgress, GetInstanceInfo, GetRaidDifficultyID,
-- UnitIsGroupLeader / UnitIsGroupAssistant, C_RestrictedActions.{GetAddOnRestrictionState, IsAddOnRestrictionActive},
-- the events LOOT_OPENED, LOOT_CLOSED, LOOT_SLOT_CLEARED, CHAT_MSG_SYSTEM, CHAT_MSG_LOOT, ENCOUNTER_START / END,
-- PARTY_LOOT_METHOD_CHANGED.
-- Dump files: C_PartyInfo, C_Loot, C_RestrictedActions in ../WoW-Addons/docs/api/. The global GetLootMethod and the enums
-- Enum.LootMethod / AddOnRestrictionType are NOT in the dump (the LSP types have LootMethod): the values here are the
-- retail ones and spike S1 / S3d reads the real ones. The shape of GetLootSlotInfo is the retail one unless
-- Mock.loot.legacySlotInfo = true (icon, name, quantity, quality, locked, isQuestItem).
--
-- Configure with Mock.loot (kept across Mock.Reload):
--   Mock.loot.Set{ method = "master", masterLooter = true, threshold = 3, legacy = true, slots = { { link=, name=, quantity=,
--       quality=, locked=, isQuest=, sources = { guid, qty, ... } }, ... }, candidates = { "Aurel", "Bryn", ... } }
--   Mock.loot.Open() / Close()        fire LOOT_OPENED / LOOT_CLOSED
--   Mock.loot.given                   { { slot=, candidate= } } recorded by GiveMasterLoot
--   Mock.loot.Roll(name, roll, lo, hi)  a roll message on CHAT_MSG_SYSTEM (secret when Mock.loot.secretMessages)
--   Mock.loot.Receive(name, link, count) a loot message on CHAT_MSG_LOOT (name nil = the player)
--   Mock.loot.rolls                   what RandomRoll was asked: { { lo, hi } }
--   Mock.encounter.Start(id, name) / End(id, name, success)   and Mock.encounter.inProgress
--   Mock.encounter.Set{ instance = { name=, type=, difficultyID=, difficultyName=, maxPlayers=, instanceID= }, raidDifficulty = n }
--   Mock.restrictions.Set{ Encounter = 1, ... }   the state per kind (0 = none); fires ADDON_RESTRICTION_STATE_CHANGED
local Mock, H = ...
local W = Mock.world

Enum.LootMethod = { FreeForAll = 0, RoundRobin = 1, Master = 2, Group = 3, NeedBeforeGreed = 4, Personal = 5 }
Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4 }
Enum.AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 }

-- The localized formats of enUS (the client's globals): Compat builds its patterns from these, never by hand.
RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
LOOT_ITEM = "%s receives loot: %s."
LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED = "%s receives item: %s."
LOOT_ITEM_PUSHED_MULTIPLE = "%s receives item: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."

W.loot = W.loot or {
	method = "group", masterLooter = false, threshold = 2, legacy = true, slots = {}, candidates = {}, given = {}, rolls = {},
	secretMessages = false, legacySlotInfo = false, masterPartyID = nil,
}
local loot = W.loot
Mock.loot = loot
loot.given, loot.rolls = loot.given or {}, loot.rolls or {}

local METHODS = { freeforall = "FreeForAll", roundrobin = "RoundRobin", master = "Master", group = "Group",
	needbeforegreed = "NeedBeforeGreed", personal = "Personal" }

function loot.Set(config)
	for k, v in pairs(config) do loot[k] = v end
end

function loot.Open() Mock.Fire("LOOT_OPENED", false, false) end
function loot.Close() Mock.Fire("LOOT_CLOSED") end

-- Returns method, masterlooterPartyID, masterlooterRaidID like the client (the ids only for master loot).
local function currentMethod()
	return Enum.LootMethod[METHODS[loot.method]], loot.method == "master" and (loot.masterLooter and 0 or loot.masterPartyID) or nil,
		loot.method == "master" and (loot.masterLooter and 1 or nil) or nil
end

C_PartyInfo = C_PartyInfo or {}
function C_PartyInfo.GetLootMethod() return currentMethod() end
function C_PartyInfo.IsLootMethodAvailable(method)
	if method == Enum.LootMethod.Master then return loot.legacy end
	return true
end
function C_PartyInfo.SetLootMethod(method, lootMaster)
	for key, name in pairs(METHODS) do
		if Enum.LootMethod[name] == method then loot.method = key end
	end
	loot.masterLooter = loot.method == "master" and lootMaster ~= nil
	Mock.Fire("PARTY_LOOT_METHOD_CHANGED")
end
C_Loot = C_Loot or {}
function C_Loot.IsLegacyLootModeEnabled() return loot.legacy end

function IsMasterLooter() return loot.method == "master" and loot.masterLooter end
function GetLootThreshold() return loot.threshold end
function UnitIsGroupLeader(unit) return (unit == "player" or unit == nil) and W.group_leader ~= false end
function UnitIsGroupAssistant() return false end

-- The loot window.
function GetNumLootItems() return #loot.slots end
function GetLootSlotLink(slot) local s = loot.slots[slot]; return s and s.link end
function GetLootSlotType(slot) return loot.slots[slot] and 1 or 0 end
function LootSlotHasItem(slot) return loot.slots[slot] ~= nil end
function GetLootSlotInfo(slot)
	local s = loot.slots[slot]
	if not s then return nil end
	if loot.legacySlotInfo then
		return s.icon or 134400, s.name, s.quantity or 1, s.quality or 4, s.locked == true, s.isQuest == true
	end
	return s.icon or 134400, s.name, s.quantity or 1, 0, s.quality or 4, s.locked == true, s.isQuest == true
end
function GetLootSourceInfo(slot)
	local s = loot.slots[slot]
	if not s or not s.sources then return nil end
	return unpack(s.sources)
end

function GetMasterLootCandidate(slot, index)
	if not loot.slots[slot] or loot.method ~= "master" or not loot.masterLooter then return nil end
	return loot.candidates[index]
end
function GiveMasterLoot(slot, candidate)
	loot.given[#loot.given + 1] = { slot = slot, candidate = candidate }
	table.remove(loot.slots, slot)
	Mock.Fire("LOOT_SLOT_CLEARED", slot)
end

-- Rolls: the server answers on CHAT_MSG_SYSTEM.
function RandomRoll(lo, hi)
	loot.rolls[#loot.rolls + 1] = { lo = lo, hi = hi }
	loot.Roll(W.player.name, 50, lo, hi)
end
function loot.Roll(name, roll, lo, hi)
	local text = loot.secretMessages and Mock.SECRET or string.format(RANDOM_ROLL_RESULT, name, roll, lo, hi)
	Mock.Fire("CHAT_MSG_SYSTEM", text)
end
function loot.Receive(name, link, count)
	local text
	if loot.secretMessages then
		text = Mock.SECRET
	elseif name == nil then
		text = (count and count > 1) and string.format(LOOT_ITEM_SELF_MULTIPLE, link, count) or string.format(LOOT_ITEM_SELF, link)
	else
		text = (count and count > 1) and string.format(LOOT_ITEM_MULTIPLE, name, link, count) or string.format(LOOT_ITEM, name, link)
	end
	Mock.Fire("CHAT_MSG_LOOT", text)
end

-- Instances and encounters.
W.encounter = W.encounter or { inProgress = false, raidDifficulty = 14,
	instance = { name = "Test Raid", type = "raid", difficultyID = 14, difficultyName = "Normal", maxPlayers = 20, instanceID = 9001 } }
local encounter = W.encounter
Mock.encounter = encounter

function encounter.Set(config)
	for k, v in pairs(config) do encounter[k] = v end
end
function encounter.Start(id, name)
	encounter.inProgress = true
	Mock.Fire("ENCOUNTER_START", id or 1, name or "Boss", encounter.raidDifficulty, 20)
end
function encounter.End(id, name, success)
	encounter.inProgress = false
	Mock.Fire("ENCOUNTER_END", id or 1, name or "Boss", encounter.raidDifficulty, 20, success and 1 or 0)
end

function IsEncounterInProgress() return encounter.inProgress end
function GetRaidDifficultyID() return encounter.raidDifficulty end
function GetInstanceInfo()
	local i = encounter.instance
	return i.name, i.type, i.difficultyID, i.difficultyName, i.maxPlayers, 0, false, i.instanceID, 0
end

-- Addon restrictions: the state per kind (0 none).
W.restrictions = W.restrictions or {}
local restrictions = W.restrictions
Mock.restrictions = restrictions
function restrictions.Set(states)
	for kind in pairs(Enum.AddOnRestrictionType) do restrictions[kind] = states[kind] or 0 end
	Mock.Fire("ADDON_RESTRICTION_STATE_CHANGED")
end
local function kindName(value)
	for name, v in pairs(Enum.AddOnRestrictionType) do if v == value then return name end end
end
C_RestrictedActions = C_RestrictedActions or {}
function C_RestrictedActions.GetAddOnRestrictionState(kind) return restrictions[kindName(kind)] or 0 end
function C_RestrictedActions.IsAddOnRestrictionActive(kind) return (restrictions[kindName(kind)] or 0) > 0 end
