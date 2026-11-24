-- Group: the raid group and the end of a boss encounter, for the night controller (docs/ANALISI.md §6, M3-3). Lua 5.1.
-- Everything goes through Core/Compat.lua (Compat.Group); the names were checked against the Forever API dump:
-- IsInRaid, GetNumGroupMembers, GetRaidRosterInfo (api.json globals) and the events GROUP_ROSTER_UPDATE, ENCOUNTER_END and
-- PLAYER_ENTERING_WORLD.
--
-- What it gives: a snapshot of the raid, and two bus events.
--   Group.Snapshot() -> { inRaid, size, members = { ["Name-Realm"] = { subgroup, online, classFile, level, raidRank,
--     isML? } }, read,
--     complete, me }. `complete` is false when a row could not be read (a secret name inside an instance, spike S7): then a
--     name that is missing does not mean "left the raid". Names are written as the ledger writes them (GuildRanks.FullName).
--   "GROUP_SCANNED"(snapshot)  one scan DEBOUNCE seconds after a group event (the client fires them in bursts).
--   "ENCOUNTER_ENDED"(info)  info = { encounterID, name?, difficultyID, groupSize, success = bool } from ENCOUNTER_END; an
--     event whose numbers are hidden by the client is dropped (never read, never compared).
-- Reading the roster at the moment of ENCOUNTER_END is the controller's job (it calls Group.Snapshot() itself, so the lineup
-- is the one of the kill and not the one of a debounced scan).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Group = {}
ns.Group, ns.modules.Group = Group, Group

local type, ipairs, min = type, ipairs, math.min

Group.DEBOUNCE = 1       -- seconds between a group event and the scan
Group.MAX_RAID = 40

local function C() return ns.Compat end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

-- Reads the raid now. Outside a raid group: { inRaid = false, size, members = {}, read = 0, complete = false } (a party or
-- nobody: the roster says nothing about who is in a raid).
function Group.Snapshot()
	local G = C().Group
	local me = ns.GuildRanks and ns.GuildRanks.Me()
	if not G.InRaid() then
		return { inRaid = false, size = G.Size(), members = {}, read = 0, complete = false, me = me }
	end
	local size = min(G.Size(), Group.MAX_RAID)
	local members, read = {}, 0
	for i = 1, size do
		local row = G.RaidRosterRow(i)
		local full = row and ns.GuildRanks and ns.GuildRanks.FullName(row.name)
		if full then
			members[full] = { subgroup = row.subgroup, online = row.online, classFile = row.classFile, level = row.level,
				raidRank = row.rank, isML = row.isML or nil }
			read = read + 1
		end
	end
	return { inRaid = true, size = size, members = members, read = read, complete = read == size, me = me }
end

Group.scheduled = false

function Group.ScanNow()
	Group.scheduled = false
	local snapshot = Group.Snapshot()
	emit("GROUP_SCANNED", snapshot)
	return snapshot
end

-- One scan DEBOUNCE seconds from now, however many events come in between (at once when timers are missing).
function Group.Schedule()
	if Group.scheduled then return end
	Group.scheduled = true
	if not C().After(Group.DEBOUNCE, Group.ScanNow) then Group.ScanNow() end
end

-- ENCOUNTER_END(encounterID, encounterName, difficultyID, groupSize, success): a hidden number drops the event.
function Group.EncounterInfo(encounterID, name, difficultyID, groupSize, success)
	local R = C().Readable
	local id, diff, size, ok = R(encounterID), R(difficultyID), R(groupSize), R(success)
	if type(id) ~= "number" or id <= 0 or id ~= id then return nil end
	if type(ok) ~= "number" and type(ok) ~= "boolean" then return nil end
	local label = R(name)
	return { encounterID = id, name = type(label) == "string" and label or nil,
		difficultyID = type(diff) == "number" and diff or nil, groupSize = type(size) == "number" and size or nil,
		success = ok == true or ok == 1 }
end

function Group.OnEvent(_, event, ...)
	if event == "ENCOUNTER_END" then
		local info = Group.EncounterInfo(...)
		if info then
			emit("ENCOUNTER_ENDED", info)
		elseif ns.Log then
			ns.Log.warn("Group", "ENCOUNTER_UNREADABLE")
		end
	else   -- GROUP_ROSTER_UPDATE, PLAYER_ENTERING_WORLD
		Group.Schedule()
	end
end

if ns.addon and CreateFrame then
	ns.addon.Group = Group   -- also reachable from tests
	local frame = CreateFrame("Frame")
	for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "ENCOUNTER_END" }) do
		frame:RegisterEvent(event)
	end
	frame:SetScript("OnEvent", Group.OnEvent)
end
