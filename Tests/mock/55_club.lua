-- Mock client, part 6b: the guild seen through C_Club (Accord, M1.3).
--
-- Imitates: C_Club.GetGuildClubId, GetClubMembers, GetMemberInfo, GetClubInfo, SendBattleTagFriendRequest.
-- Dump files: ../WoW-Addons/docs/api/Guild-Social-Chat/C_Club.md; the fields of ClubMemberInfo (profession1ID/Name/Rank,
-- profession2..., discordInfo, guid, bnetAccountId, lastOnline*, guildRankOrder) are in the dump; DiscordChatInfo's
-- fields are not, so the mock gives { username = ... } [verify S2].
--
-- Members come from the guild mock (Tests/mock/50_guild.lua): Mock.guild.Roster(). Whether the server FILLS the fields
-- Accord hopes for is the open question of M0 check S2, so it is a switch (kept across Mock.Reload):
--   Mock.club.fill = { professions = false, discord = false, guid = true, bnet = false }
--   Mock.club.friendRequests   member ids passed to SendBattleTagFriendRequest
local Mock, H = ...
local W = Mock.world

W.club = W.club or { fill = { professions = false, discord = false, guid = true, bnet = false }, friendRequests = {} }
local club = W.club
Mock.club = club

local GUILD_CLUB_ID = 9001
local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8,
	WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12, EVOKER = 13 }

C_Club = {}

function C_Club.GetGuildClubId()
	if not IsInGuild() then return nil end
	return GUILD_CLUB_ID
end

function C_Club.GetClubInfo(clubId)
	if clubId ~= GUILD_CLUB_ID or not IsInGuild() then return nil end
	local roster = Mock.guild.Roster()
	return { clubId = clubId, name = (GetGuildInfo("player")), description = "", broadcast = "", clubType = 2, avatarId = 0,
		memberCount = #roster }
end

-- Member ids are 1..n, the roster order.
function C_Club.GetClubMembers(clubId)
	if clubId ~= GUILD_CLUB_ID or not IsInGuild() then return {} end
	local ids = {}
	for i in ipairs(Mock.guild.Roster()) do ids[i] = i end
	return ids
end

function C_Club.GetMemberInfo(clubId, memberId)
	if clubId ~= GUILD_CLUB_ID then return nil end
	local m = Mock.guild.Roster()[memberId]
	if not m then return nil end
	local fill = club.fill
	local info = {
		isSelf = m.me == true, memberId = memberId, name = m.name, presence = m.online and 1 or 0, clubType = 2,
		classID = CLASS_IDS[m.class], level = m.level, zone = m.zone, memberNote = m.note, guildRankOrder = m.rank + 1,
	}
	if fill.guid then info.guid = m.guid end
	if fill.bnet then info.bnetAccountId = 100 + memberId end
	if not m.online then
		local t = m.lastOnline or { 0, 0, 1, 0 }
		info.lastOnlineYear, info.lastOnlineMonth, info.lastOnlineDay, info.lastOnlineHour = t[1], t[2], t[3], t[4]
	end
	if fill.professions and m.professions then
		for i = 1, 2 do
			local p = m.professions[i]
			if p then
				info["profession" .. i .. "ID"], info["profession" .. i .. "Name"], info["profession" .. i .. "Rank"] = p.id, p.name, p.rank
			end
		end
	end
	if fill.discord and m.discord then info.discordInfo = { username = m.discord } end
	return info
end

function C_Club.SendBattleTagFriendRequest(clubId, memberId)
	club.friendRequests[#club.friendRequests + 1] = memberId
end
