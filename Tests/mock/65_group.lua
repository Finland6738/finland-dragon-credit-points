-- Mock client, part 6c: the party or raid (Accord, M1.3).
--
-- Imitates: IsInGroup, IsInRaid, GetNumGroupMembers, GetRaidRosterInfo, UnitIsInMyGuild, and UnitGUID / UnitName /
-- UnitExists for party1..4 and raid1..40 (the player's own answers stay those of Tests/mock/60_client.lua).
-- Dump: IsInGroup, IsInRaid, GetNumGroupMembers, GetRaidRosterInfo are api.json globals; UnitIsInMyGuild and UnitGUID
-- are in the Unit system. Whether GUIDs are readable inside instances is M0 check S7: Mock.group.secretGUIDs = true
-- makes every other member's GUID and name a secret value (Mock.SECRET).
--
-- Configure (kept across Mock.Reload):
--   Mock.group.Set{ raid = false, members = { { name = "Ally", guid = "Player-1-...", inGuild = true, class = "MAGE",
--                   level = 60, subgroup = 1 }, ... } }   -- the OTHER members; fires GROUP_ROSTER_UPDATE
--   Mock.group.Leave()
--   Mock.group.invites     names given to C_PartyInfo.InviteUnit
local Mock, H = ...
local W = Mock.world

W.group = W.group or { raid = false, members = {}, secretGUIDs = false }
local group = W.group
Mock.group = group

-- C_PartyInfo.InviteUnit(name): records the invite (the client asks the server; nothing else happens here).
group.invites = group.invites or {}
C_PartyInfo = C_PartyInfo or {}
function C_PartyInfo.InviteUnit(name) group.invites[#group.invites + 1] = name end

function group.Set(config)
	group.raid = config.raid == true
	group.members = {}
	for i, m in ipairs(config.members or {}) do
		group.members[i] = { name = m.name or ("Member" .. i), guid = m.guid or string.format("Player-1-%08X", 0x2000 + i),
			inGuild = m.inGuild == true, class = m.class or "WARRIOR", level = m.level or 60, subgroup = m.subgroup or 1,
			realm = m.realm }
	end
	Mock.Fire("GROUP_ROSTER_UPDATE")
end

function group.Leave()
	group.raid, group.members = false, {}
	Mock.Fire("GROUP_ROSTER_UPDATE")
end

local function inGroup() return #group.members > 0 end

function IsInGroup() return inGroup() end
function IsInRaid() return inGroup() and group.raid end
function GetNumGroupMembers() return inGroup() and (#group.members + 1) or 0 end

-- The player is raid<n> at the end of the list, as the client may put them anywhere; party tokens never include them.
local function memberOf(unit)
	if type(unit) ~= "string" then return nil end
	local n = tonumber(unit:match("^party(%d)$"))
	if n and not group.raid then return group.members[n] end
	n = tonumber(unit:match("^raid(%d+)$"))
	if n and group.raid then
		if n == #group.members + 1 then return "player" end
		return group.members[n]
	end
	return nil
end

local playerGUID, playerName, playerExists = UnitGUID, UnitName, UnitExists

function UnitGUID(unit)
	local m = memberOf(unit)
	if m == "player" then return playerGUID("player") end
	if m then return group.secretGUIDs and Mock.SECRET or m.guid end
	return playerGUID(unit)
end

function UnitName(unit)
	local m = memberOf(unit)
	if m == "player" then return playerName("player") end
	if m then
		if group.secretGUIDs then return Mock.SECRET, nil end
		return m.name, m.realm
	end
	return playerName(unit)
end

function UnitExists(unit)
	if memberOf(unit) then return true end
	return playerExists(unit)
end

function UnitIsInMyGuild(unit)
	local m = memberOf(unit)
	if m == "player" then return IsInGuild() end
	if m then return m.inGuild and IsInGuild() end
	return unit == "player" and IsInGuild() or false
end

-- name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML
function GetRaidRosterInfo(index)
	if not group.raid then return nil end
	local m = memberOf("raid" .. index)
	if m == "player" then
		local p = W.player
		return p.name, 0, 1, p.level, p.classFile, p.classFile, "Orgrimmar", true, false, "NONE", false
	end
	if not m then return nil end
	if group.secretGUIDs then return Mock.SECRET end
	return m.name, 0, m.subgroup, m.level, m.class, m.class, "Orgrimmar", true, false, "NONE", false
end

function IsInInstance() return W.inInstance == true, W.inInstance and "party" or "none" end
