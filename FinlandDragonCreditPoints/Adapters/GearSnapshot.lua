-- GearSnapshot: the gear the player wore during the boss fight (docs/ANALISI.md §5.1, M7-5c). Lua 5.1. The upgrade badge of
-- the popup compares the item with this snapshot, not with what the player wears when the loot is rolled: taking a piece
-- off after the kill does not make an item look like a bigger upgrade (M7-5d reads the same snapshot against cheating).
--
-- When: ENCOUNTER_START (the gear of the fight). A client that missed it (a /reload or a disconnection during the fight)
-- takes it at ENCOUNTER_END instead. A later pull replaces it. Everything goes through Core/Compat.lua and
-- Adapters/Inventory.lua (GetInventoryItemLink); the events ENCOUNTER_START(encounterID, encounterName, difficultyID,
-- groupSize) and ENCOUNTER_END were checked against the Forever API dump. A hidden encounter id is kept as nil.
--
-- The snapshot is the full links by slot (the item level and the quality are read from them again), kept in
-- FinlandDragonCreditPointsCharDB.gearSnapshot so a /reload between the kill and the roll keeps it:
--   { encounter = id | nil, at = server time, links = { [slot] = link } }
--
-- GearSnapshot.Take(encounterID)      takes one now and returns it
-- GearSnapshot.Current()              the snapshot, or nil when there is none or it is older than MAX_AGE
-- GearSnapshot.Pick(snap, encounterID, now)  pure: the snapshot to compare with for a session of `encounterID` (nil: the
--                                     player's current gear): fresh, and of that encounter when both ids are known
-- Bus event: "GEAR_SNAPSHOT_TAKEN"(snapshot).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local GearSnapshot = {}
ns.GearSnapshot, ns.modules.GearSnapshot = GearSnapshot, GearSnapshot

local type, pairs = type, pairs

GearSnapshot.MAX_AGE = 3600   -- seconds a snapshot stands for the loot of its boss
GearSnapshot.last = nil       -- the snapshot of this session (also in the character's saved data)

local function C() return ns.Compat end

local function store()
	local c = ns.Config and ns.Config.char
	if type(c) ~= "table" then return nil end
	return c
end

local function valid(snap)
	return type(snap) == "table" and type(snap.at) == "number" and type(snap.links) == "table"
end

-- The snapshot this client holds (memory first, then the saved one).
function GearSnapshot.Get()
	if valid(GearSnapshot.last) then return GearSnapshot.last end
	local c = store()
	if c and valid(c.gearSnapshot) then
		GearSnapshot.last = c.gearSnapshot
		return c.gearSnapshot
	end
	return nil
end

function GearSnapshot.Take(encounterID)
	local links = {}
	for slot, link in pairs(ns.Inventory.Links()) do links[slot] = link end
	local snap = { encounter = type(encounterID) == "number" and encounterID or nil, at = C().ServerTime(), links = links }
	GearSnapshot.last = snap
	local c = store()
	if c and not (ns.Config.IsReadOnly and ns.Config:IsReadOnly()) then c.gearSnapshot = snap end
	if ns.Bus then ns.Bus:Emit("GEAR_SNAPSHOT_TAKEN", snap) end
	return snap
end

-- Pure: is `snap` the gear to compare with for a session of `encounterID` at `now`?
function GearSnapshot.Pick(snap, encounterID, now)
	if not valid(snap) or type(now) ~= "number" then return nil end
	if now - snap.at > GearSnapshot.MAX_AGE or snap.at - now > 60 then return nil end
	if type(encounterID) == "number" and type(snap.encounter) == "number" and snap.encounter ~= encounterID then return nil end
	return snap
end

function GearSnapshot.Current(encounterID)
	return GearSnapshot.Pick(GearSnapshot.Get(), encounterID, C().ServerTime())
end

local function readId(encounterID)
	local id = C().Readable(encounterID)
	if type(id) ~= "number" or id ~= id or id <= 0 then return nil end
	return id
end

function GearSnapshot.OnEvent(_, event, encounterID)
	local id = readId(encounterID)
	if event == "ENCOUNTER_START" then
		GearSnapshot.Take(id)
	elseif event == "ENCOUNTER_END" then
		-- missed the start (a /reload during the fight): the gear at the end is the closest there is
		local fresh = GearSnapshot.Pick(GearSnapshot.Get(), id, C().ServerTime())
		if fresh then
			if id and fresh.encounter == nil then fresh.encounter = id end   -- the start's id was hidden
			return
		end
		GearSnapshot.Take(id)
	end
end

if ns.addon and CreateFrame then
	ns.addon.GearSnapshot = GearSnapshot   -- also reachable from tests
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("ENCOUNTER_START")
	frame:RegisterEvent("ENCOUNTER_END")
	frame:SetScript("OnEvent", GearSnapshot.OnEvent)
end
