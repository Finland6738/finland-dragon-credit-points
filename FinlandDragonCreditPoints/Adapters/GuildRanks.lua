-- GuildRanks: the game's guild ranks for the permission service (docs/ANALISI.md §3.9, M3-1). Lua 5.1.
-- Everything goes through Core/Compat.lua (Compat.Guild); the names were checked against the Forever API dump:
-- IsGuildLeader, GetGuildInfo, GetNumGuildMembers, GetGuildRosterInfo, GuildControlGetNumRanks, GuildControlGetRankName
-- (api.json globals), C_GuildInfo.GuildRoster, C_GuildInfo.IsGuildOfficer, C_GuildInfo.CanEditOfficerNote, and the events
-- GUILD_ROSTER_UPDATE, GUILD_RANKS_UPDATE, PLAYER_GUILD_UPDATE.
--
-- What it answers: is the player the Guild Master (rank index 0), the rank index of a member, the rank names and their
-- count, and whether the game itself calls the player an officer (shown only: permissions use rank indexes, never the
-- game's officer flag).
--
-- The roster arrives asynchronously: at login GetNumGuildMembers is 0 until the server answers C_GuildInfo.GuildRoster.
-- The adapter asks for it on PLAYER_ENTERING_WORLD and again every RETRY seconds until a roster that contains the player
-- has been read. Every roster or rank event schedules one scan DEBOUNCE seconds later (the client fires them in bursts);
-- a scan that reads a roster emits "GUILD_ROSTER_SCANNED"(snapshot) on the bus, where App/PermissionService.lua takes it.
-- A snapshot is plain data:
--   { members = { ["Name-Realm"] = rankIndex }, complete = bool, me = "Name-Realm", myRank = n, gm = "Name-Realm"|nil,
--     ranks = { "Guild Master", "Officer", ... } (by position, index + 1; empty when the client does not say) }
-- `complete` is false when a row could not be read (a hidden field): then a missing name does not mean "left the guild".
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local GuildRanks = {}
ns.GuildRanks, ns.modules.GuildRanks = GuildRanks, GuildRanks

local type, pairs, ipairs, min = type, pairs, ipairs, math.min

GuildRanks.DEBOUNCE = 1   -- seconds between a roster event and the scan
GuildRanks.RETRY = 15     -- seconds between roster requests until the first roster is read

local function C() return ns.Compat end

-- "Name-Realm" with the realm written without spaces, dashes or apostrophes (as GetNormalizedRealmName does); a name
-- without a realm gets the player's realm. nil for anything that is not a name.
function GuildRanks.FullName(name)
	if type(name) ~= "string" or name == "" then return nil end
	local base, realm = name:match("^([^%-]+)%-(.+)$")
	if not base then base, realm = name, C().Player.Realm() end
	if not realm or realm == "" then return nil end
	return base .. "-" .. (realm:gsub("[%s%-']", ""))
end

-- The player as "Name-Realm", nil when the client does not say yet.
function GuildRanks.Me()
	return GuildRanks.FullName(C().Player.Name())
end

-- True when the player leads the guild: the player's rank index is 0 (GetGuildInfo), or IsGuildLeader says so when the
-- rank is not readable.
function GuildRanks.SelfIsGM()
	local _, _, rankIndex = C().Guild.PlayerRank()
	if type(rankIndex) == "number" then return rankIndex == 0 end
	return C().Guild.IsGuildLeader()
end

-- The player's rank index (0 = Guild Master), nil without a guild or when the client does not say.
function GuildRanks.SelfRank()
	local _, _, rankIndex = C().Guild.PlayerRank()
	if type(rankIndex) == "number" then return rankIndex end
	return nil
end

-- True when the game calls the player an officer (C_GuildInfo.IsGuildOfficer, the officer-note right, or GM).
function GuildRanks.SelfIsOfficer()
	local G = C().Guild
	return G.IsOfficer() or G.CanEditOfficerNote()
end

-- The rank index of a member ("Name" or "Name-Realm"), nil while the roster is not loaded or without that member.
function GuildRanks.RankOf(name)
	return C().Guild.MemberRankIndex(name)
end

function GuildRanks.NumRanks() return C().Guild.NumRanks() end
function GuildRanks.RankName(rankIndex) return C().Guild.RankName(rankIndex) end

-- The rank names by position (index + 1); an empty list when a name is missing (a partial list would look like a
-- deleted rank).
function GuildRanks.RankNames()
	local ranks, n = C().Guild.Ranks(), GuildRanks.NumRanks()
	if #ranks ~= n then return {} end
	local out = {}
	for i, r in ipairs(ranks) do
		if r.index ~= i - 1 then return {} end
		out[i] = r.name
	end
	return out
end

-- Reads the whole roster. nil while it is not loaded: no guild, no rows yet, or the player not in it.
function GuildRanks.Scan()
	local G = C().Guild
	if not G.InGuild() then return nil end
	local total = min((G.RosterCount()), G.MAX_ROSTER)
	if total <= 0 then return nil end
	local me = GuildRanks.Me()
	local members, gm, read = {}, nil, 0
	local IsRank = ns.Permissions.IsRank
	for i = 1, total do
		local row = G.RosterRow(i)
		local full = row and GuildRanks.FullName(row.name)
		if full and IsRank(row.rankIndex) then
			members[full] = row.rankIndex
			read = read + 1
			if row.rankIndex == 0 then gm = full end
		end
	end
	if not me or members[me] == nil then return nil end
	return { members = members, complete = read == total, me = me, myRank = members[me], gm = gm,
		ranks = GuildRanks.RankNames() }
end

---------------------------------------------------------------------------------------------------------------------
-- Events: request, debounce, scan

GuildRanks.seen = false      -- a roster was read this session
GuildRanks.scheduled = false

function GuildRanks.ScanNow()
	GuildRanks.scheduled = false
	local snapshot = GuildRanks.Scan()
	if not snapshot then return nil end
	GuildRanks.seen = true
	if ns.Bus then ns.Bus:Emit("GUILD_ROSTER_SCANNED", snapshot) end
	return snapshot
end

-- One scan DEBOUNCE seconds from now, however many events come in between (at once when timers are missing).
function GuildRanks.Schedule()
	if GuildRanks.scheduled then return end
	GuildRanks.scheduled = true
	if not C().After(GuildRanks.DEBOUNCE, GuildRanks.ScanNow) then GuildRanks.ScanNow() end
end

-- Asks for the roster, and again every RETRY seconds while no roster was read and the player is in a guild.
function GuildRanks.Request()
	if GuildRanks.seen or not C().Guild.InGuild() then return end
	C().Guild.RequestRoster()
	if not GuildRanks.retrying then
		GuildRanks.retrying = C().After(GuildRanks.RETRY, function()
			GuildRanks.retrying = false
			GuildRanks.Request()
		end)
	end
end

function GuildRanks.OnEvent(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		GuildRanks.Request()
	elseif event == "PLAYER_GUILD_UPDATE" then
		-- joined, left or changed guild: the next roster is a new one
		if not C().Guild.InGuild() then GuildRanks.seen = false end
		GuildRanks.Request()
		GuildRanks.Schedule()
	else   -- GUILD_ROSTER_UPDATE, GUILD_RANKS_UPDATE
		GuildRanks.Schedule()
	end
end

if ns.addon and CreateFrame then
	ns.addon.GuildRanks = GuildRanks   -- also reachable from tests
	local frame = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE", "GUILD_RANKS_UPDATE" }) do
		frame:RegisterEvent(event)
	end
	frame:SetScript("OnEvent", GuildRanks.OnEvent)
end
