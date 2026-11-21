-- Compat: the only door to the game API (docs/ANALISI.md §1, §8.1). Every call is guarded: a missing, failing or
-- restricted API turns one feature off, never the addon. Lua 5.1.
-- Adapted from Azeroth Accord (Core/Compat.lua), same owner, GPL-3.0: the guarded calls, secret values, restrictions,
-- chat lockdown, player, guild, group, time and encoding come from there; the loot window and master loot, the loot
-- method and threshold, the roll and loot message patterns, encounters, items and stats, specializations, guild ranks
-- and the calendar are new.
--
-- Names are checked against the Forever API dump (../WoW-Addons/docs/api.json, build 1.60.1.70170). Not in the dump,
-- so marked [verify] and always behind a fallback: the global GetLootMethod, GetItemInfo / GetItemStats /
-- GetItemInfoInstant (the dump has only C_Item.*), the global GetSpecialization* (only C_SpecializationInfo.*),
-- CanViewOfficerNote, GetGuildRosterLastOnline. The M0 spike results are not in yet (S1..S8): every call whose
-- behaviour the spike has to confirm degrades to nil / false / "unknown" without an error.
--
-- Rules: a secret value is never read, compared or concatenated; a result that is secret becomes nil and the call state
-- becomes "restricted". Item and player names are returned to callers (they need them) but never written into the
-- debug output.
local ADDON_NAME, ns = ...
ns = ns or {}
local Compat = {}
ns.Compat, ns.modules = Compat, ns.modules or {}
ns.modules.Compat = Compat

local AVAILABLE, MISSING, ERROR, RESTRICTED = "available", "missing", "error", "restricted"
Compat.AVAILABLE, Compat.MISSING, Compat.ERROR, Compat.RESTRICTED = AVAILABLE, MISSING, ERROR, RESTRICTED
-- A feature capability is "available", "missing", or "unknown": the client has the API but nothing has shown yet
-- whether the server fills it (the spike, M0, or the first real use settles it).
local UNKNOWN = "unknown"
Compat.UNKNOWN = UNKNOWN

local type, pcall, select, pairs, ipairs, tostring, tonumber, unpack = type, pcall, select, pairs, ipairs, tostring, tonumber, unpack
local min = math.min

---------------------------------------------------------------------------------------------------------------------
-- Resolve, secret values, guarded calls
---------------------------------------------------------------------------------------------------------------------

local function index(value, part) return value[part] end   -- one function for every step: no closure per lookup
local PARTS = {}                                              -- path -> its names, split once (the paths are a fixed set)

-- "C_PartyInfo.GetLootMethod" -> the value in the global table, or nil. Never raises.
function Compat.Resolve(path)
	if type(path) ~= "string" or path == "" then return nil end
	local parts = PARTS[path]
	if not parts then
		parts = {}
		for part in path:gmatch("[^.]+") do parts[#parts + 1] = part end
		PARTS[path] = parts
	end
	local value = _G
	for i = 1, #parts do
		if type(value) ~= "table" then return nil end
		local ok, nextValue = pcall(index, value, parts[i])
		if not ok then return nil end
		value = nextValue
	end
	return value
end
local Resolve = Compat.Resolve

-- A secret value can be passed around but not read, compared or used in arithmetic: never look inside one.
-- The client functions are looked up on every call (they may appear late, tests replace them).
function Compat.IsSecret(value)
	if value == nil then return false end
	-- a check that itself fails counts as "secret": never read what cannot be proven readable
	if issecretvalue then
		local ok, secret = pcall(issecretvalue, value)
		if not ok or secret then return true end
	end
	if canaccessvalue then
		local ok, canAccess = pcall(canaccessvalue, value)
		if not ok or not canAccess then return true end
	end
	if type(value) == "table" and issecrettable then
		local ok, secret = pcall(issecrettable, value)
		if not ok or secret then return true end
	end
	return false
end
local IsSecret = Compat.IsSecret

-- The value, or nil when the client hides it.
function Compat.Readable(value)
	if IsSecret(value) then return nil end
	return value
end

local function restrictedMessage(message)
	message = tostring(message):lower()
	return message:find("restrict", 1, true) or message:find("secret", 1, true) or message:find("forbidden", 1, true)
		or message:find("blocked", 1, true) or message:find("lockdown", 1, true)
end

-- Runs fn(...) under pcall. Returns state, detail, count, values-table. A secret result is dropped (nil) and the
-- state becomes restricted; an error that talks about restrictions is restricted, any other error is error.
local function run(fn, ...)
	if type(fn) ~= "function" then return MISSING, "not a function", 0, {} end
	local packed = { pcall(fn, ...) }
	local n = #packed
	if not packed[1] then
		local message = IsSecret(packed[2]) and "secret error" or tostring(packed[2])
		return restrictedMessage(message) and RESTRICTED or ERROR, message:sub(1, 120), 0, {}
	end
	local state, values, count = AVAILABLE, {}, n - 1
	for i = 1, count do
		local v = packed[i + 1]
		if IsSecret(v) then state, v = RESTRICTED, nil end
		values[i] = v
	end
	return state, state == RESTRICTED and "secret value" or nil, count, values
end

-- Compat.Call("C_PartyInfo.GetLootMethod", ...) -> state, value1, value2, ...
function Compat.Call(path, ...)
	local state, _, count, values = run(Resolve(path), ...)
	return state, unpack(values, 1, count)
end

-- First value only when the call is available, else nil (plus the state as second result).
local function first(path, ...)
	local state, _, _, values = run(Resolve(path), ...)
	if state == AVAILABLE then return values[1], state end
	return nil, state
end

-- Every value when the call is available (a table and the count), else nil, 0, state.
local function all(path, ...)
	local state, _, count, values = run(Resolve(path), ...)
	if state == AVAILABLE then return values, count, state end
	return nil, 0, state
end

-- Every value of a call that ran, secret ones as nil (a table and the count, plus the state, "restricted" when
-- something was hidden), or nil, 0, state when it did not run. For rows where one hidden field must not hide the rest.
local function readable(path, ...)
	local state, _, count, values = run(Resolve(path), ...)
	if state == AVAILABLE or (state == RESTRICTED and count > 0) then return values, count, state end
	return nil, 0, state
end

-- A copy of the readable plain fields of a table the client gave (secret fields and nested secret tables dropped).
-- Nested tables are copied one level deep; anything deeper is dropped.
local function readableCopy(t, depth)
	if type(t) ~= "table" or IsSecret(t) then return nil end
	depth = depth or 0
	local out = {}
	for k, v in pairs(t) do
		if not IsSecret(k) and not IsSecret(v) then
			if type(v) == "table" then
				if depth < 1 then out[k] = readableCopy(v, depth + 1) end
			elseif type(v) ~= "function" and type(v) ~= "userdata" then
				out[k] = v
			end
		end
	end
	return out
end
Compat.ReadableCopy = readableCopy

local function str(v) return type(v) == "string" and v ~= "" and v or nil end
local function num(v) return type(v) == "number" and v == v and v or nil end

-- The named fields of the enum Enum.<name>, as value -> name (nil when the client has no such enum).
local function enumNames(name)
	local t = Resolve("Enum." .. name)
	if type(t) ~= "table" then return nil end
	local out = {}
	for key, value in pairs(t) do
		if type(key) == "string" and type(value) == "number" then out[value] = key end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Player
---------------------------------------------------------------------------------------------------------------------
local Player = {}
Compat.Player = Player

function Player.Faction()
	local v = first("UnitFactionGroup", "player")
	if v == "Horde" or v == "Alliance" then return v end
	return nil
end

-- The character name without the realm, nil when unknown.
function Player.Name()
	return str((first("UnitName", "player")))
end

-- Normalized realm name (no spaces), falling back to GetRealmName without spaces.
function Player.Realm()
	local v = first("GetNormalizedRealmName")
	if not str(v) then
		v = first("GetRealmName")
		if type(v) == "string" then v = v:gsub("[%s%-']", "") end
	end
	return str(v)
end

function Player.GUID()
	return str((first("UnitGUID", "player")))
end

function Player.Level()
	return num((first("UnitLevel", "player")))
end

function Player.ClassID()
	local values = all("UnitClass", "player")
	return values and num(values[3]) or nil
end

function Player.ClassFile()
	local values = all("UnitClass", "player")
	return values and str(values[2]) or nil
end

-- "enUS", "itIT", ... (the game's locale); "enUS" when the client does not say.
function Player.Locale()
	return str((first("GetLocale"))) or "enUS"
end

---------------------------------------------------------------------------------------------------------------------
-- Guild: the player's guild, its roster and its ranks (spike S7)
---------------------------------------------------------------------------------------------------------------------
local Guild = {}
Compat.Guild = Guild
Guild.MAX_ROSTER = 1000   -- a guild has at most 1000 members

function Guild.InGuild()
	local v, state = first("IsInGuild")
	if state == AVAILABLE then return v and true or false end
	return false
end

function Guild.GuildName()
	return str((first("GetGuildInfo", "player")))
end

-- guildName, rankName, rankIndex (0 = Guild Master), or nil.
function Guild.PlayerRank()
	local values = all("GetGuildInfo", "player")
	if values and type(values[1]) == "string" then return values[1], values[2], values[3] end
	return nil
end

-- The guild's own realm on connected realms (the 4th result of GetGuildInfo), nil when the client does not say.
function Guild.GuildRealm()
	local values = all("GetGuildInfo", "player")
	return values and str(values[4]) or nil
end

function Guild.IsGuildLeader()
	local v, state = first("IsGuildLeader")
	if state == AVAILABLE then return v and true or false end
	local _, _, rankIndex = Guild.PlayerRank()
	return rankIndex == 0
end

-- Officer: the client says so, or the player leads the guild.
function Guild.IsOfficer()
	if Guild.IsGuildLeader() then return true end
	local v, state = first("C_GuildInfo.IsGuildOfficer")
	return state == AVAILABLE and v and true or false
end

-- The client's "may edit officer notes" right (C_GuildInfo.CanEditOfficerNote; the old global when the namespace lacks
-- it [verify]): one of the game's signs of an officer. false when the client does not say.
function Guild.CanEditOfficerNote()
	local v, state = first("C_GuildInfo.CanEditOfficerNote")
	if state ~= AVAILABLE then v, state = first("CanEditOfficerNote") end
	return state == AVAILABLE and v and true or false
end

-- Asks the server for a fresh roster (GUILD_ROSTER_UPDATE follows). Returns the call state.
function Guild.RequestRoster()
	local _, state = first("C_GuildInfo.GuildRoster")
	return state
end

-- total, online (0, 0 when unknown).
function Guild.RosterCount()
	local values = all("GetNumGuildMembers")
	if values and type(values[1]) == "number" then return values[1], num(values[2]) or 0 end
	return 0, 0
end

-- One roster row: { name, rankName, rankIndex, level, classFile, zone, note, officerNote, online, guid } or nil.
-- A hidden field is nil, the row stays.
function Guild.RosterRow(i)
	local values = readable("GetGuildRosterInfo", i)
	if not values or type(values[1]) ~= "string" then return nil end
	return {
		name = values[1], rankName = str(values[2]), rankIndex = num(values[3]), level = num(values[4]),
		classFile = str(values[11]), zone = str(values[6]), note = str(values[7]), officerNote = str(values[8]),
		online = values[9] and true or false, guid = str(values[17]),
	}
end

-- Every roster row (at most MAX_ROSTER).
function Guild.Roster()
	local rows = {}
	if not Guild.InGuild() then return rows end
	local total = min((Guild.RosterCount()), Guild.MAX_ROSTER)
	for i = 1, total do
		local row = Guild.RosterRow(i)
		if row then rows[#rows + 1] = row end
	end
	return rows
end

local function shortName(name)
	return ((name:match("^[^%-]+") or name):lower())
end

-- The rank index (0 = Guild Master) of the roster member called `name` ("Name" or "Name-Realm", compared without the
-- realm and the case), or nil while the roster is not loaded or has no such member. Permissions read ranks from here,
-- never from a message.
function Guild.MemberRankIndex(name)
	if type(name) ~= "string" or name == "" or not Guild.InGuild() then return nil end
	local want = shortName(name)
	local total = min((Guild.RosterCount()), Guild.MAX_ROSTER)
	for i = 1, total do
		local row = Guild.RosterRow(i)
		if row and shortName(row.name) == want then return row.rankIndex end
	end
	return nil
end

-- How many ranks the guild has (0 without a guild or when the client does not say).
function Guild.NumRanks()
	return num((first("GuildControlGetNumRanks"))) or 0
end

-- The name of a rank by its index (0 = Guild Master); GuildControlGetRankName is 1-based.
function Guild.RankName(rankIndex)
	if type(rankIndex) ~= "number" then return nil end
	return str((first("GuildControlGetRankName", rankIndex + 1)))
end

-- Every rank: { { index (0 = Guild Master), name }, ... } in rank order; an empty list when the client says nothing.
function Guild.Ranks()
	local out = {}
	for i = 0, min(Guild.NumRanks(), 10) - 1 do
		local name = Guild.RankName(i)
		if name then out[#out + 1] = { index = i, name = name } end
	end
	return out
end

-- The permission flags of a rank (a table of booleans by position), or nil [verify S7b: which flag is which].
function Guild.RankFlags(rankIndex)
	if type(rankIndex) ~= "number" then return nil end
	return readableCopy((first("C_GuildInfo.GuildControlGetRankFlags", rankIndex + 1)))
end

-- true when members of rank `rankIndex` read officer chat: the Guild Master, or a rank with the "officer chat listen"
-- flag, the third [verify S7b]. nil when the client does not say.
Guild.OFFICER_LISTEN_FLAG = 3
function Guild.RankIsOfficer(rankIndex)
	if type(rankIndex) ~= "number" then return nil end
	if rankIndex == 0 then return true end
	local flags = Guild.RankFlags(rankIndex)
	if not flags then return nil end
	return flags[Guild.OFFICER_LISTEN_FLAG] == true
end

-- The rank index of the guild member with this GUID (C_GuildInfo.GetGuildRankOrder, 1-based in the client), or nil.
function Guild.RankIndexByGUID(guid)
	if type(guid) ~= "string" then return nil end
	local order = num((first("C_GuildInfo.GetGuildRankOrder", guid)))
	return order and (order - 1) or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Group and raid (spike S7: names and GUIDs may be secret inside an instance)
---------------------------------------------------------------------------------------------------------------------
local Group = {}
Compat.Group = Group

function Group.InRaid() return (first("IsInRaid")) and true or false end
function Group.InGroup() return (first("IsInGroup")) and true or false end

-- Members of the group including the player (0 when alone or unknown).
function Group.Size() return num((first("GetNumGroupMembers"))) or 0 end

-- true when the group counts as a guild group (InGuildParty: enough guild members in it), false when it does not, nil
-- when the client does not say (missing, failing or hidden). [verify] on WoW Forever: the share of guild members the
-- server requires. M3-3b records a first kill outside an official night only in a guild group.
function Group.InGuildParty()
	local v, state = first("InGuildParty")
	if state == AVAILABLE then return v and true or false end
	return nil
end

function Group.IsLeader() return (first("UnitIsGroupLeader", "player")) and true or false end
function Group.IsAssistant() return (first("UnitIsGroupAssistant", "player")) and true or false end

-- The unit tokens of the other members: raid1..raidN (without the player) or party1..party4.
function Group.Units()
	local units, n = {}, Group.Size()
	if n <= 1 then return units end
	if Group.InRaid() then
		local me = Player.GUID()
		for i = 1, min(n, 40) do
			local unit = "raid" .. i
			local guid = str((first("UnitGUID", unit)))
			if guid == nil or guid ~= me then units[#units + 1] = unit end
		end
	else
		for i = 1, min(n - 1, 4) do units[#units + 1] = "party" .. i end
	end
	return units
end

-- What the addon may know of one unit: { unit, guid, name, inGuild } with nil for anything secret or missing.
function Group.Member(unit)
	local guid = str((first("UnitGUID", unit)))
	local values = readable("UnitName", unit)
	local name = values and str(values[1]) or nil
	if name and values and str(values[2]) then name = name .. "-" .. values[2] end
	local isIn, state = first("UnitIsInMyGuild", unit)
	local inGuild = nil
	if state == AVAILABLE then inGuild = isIn and true or false end
	return { unit = unit, guid = guid, name = name, inGuild = inGuild }
end

-- The other members of the group: a list of Group.Member tables (secret ones kept with nil fields, so a count is
-- honest about what could not be read).
function Group.Members()
	local out = {}
	for _, unit in ipairs(Group.Units()) do out[#out + 1] = Group.Member(unit) end
	return out
end

-- GetRaidRosterInfo(i) as a table: { name, rank, subgroup, level, classFile, zone, online, isDead }; nil when missing.
function Group.RaidRosterRow(i)
	local values = readable("GetRaidRosterInfo", i)
	if not values or not str(values[1]) then return nil end
	return { name = values[1], rank = num(values[2]), subgroup = num(values[3]), level = num(values[4]), classFile = str(values[6]),
		zone = str(values[7]), online = values[8] and true or false, isDead = values[9] and true or false }
end

---------------------------------------------------------------------------------------------------------------------
-- Instance and encounters (spike S3d: the restriction state around a boss)
---------------------------------------------------------------------------------------------------------------------
local Encounter = {}
Compat.Encounter = Encounter

-- true while a boss encounter runs. A failing or hidden answer counts as "in progress" (the safe side: sessions open
-- after ENCOUNTER_END, never during); a missing function means no encounter can be known: false.
function Encounter.InProgress()
	local v, state = first("IsEncounterInProgress")
	if state == AVAILABLE then return v and true or false end
	return state == RESTRICTED or state == ERROR
end

-- true inside an instance, plus its type ("party", "raid", ...).
function Encounter.InInstance()
	local values = all("IsInInstance")
	if not values then return false, nil end
	return values[1] and true or false, str(values[2])
end

-- { name, type, difficultyID, difficultyName, maxPlayers, instanceID } of the current instance, nil when unknown.
function Encounter.Instance()
	local v = readable("GetInstanceInfo")
	if not v or not str(v[1]) then return nil end
	return { name = v[1], type = str(v[2]), difficultyID = num(v[3]), difficultyName = str(v[4]), maxPlayers = num(v[5]),
		instanceID = num(v[8]) }
end

function Encounter.RaidDifficultyID()
	return num((first("GetRaidDifficultyID")))
end

-- The name of a boss in the client's language from the Encounter Journal (EJ_GetEncounterInfo(journalID)), or nil.
-- With `encounterID` (the DungeonEncounter id of ENCOUNTER_END) the journal entry must say it is that encounter (its
-- 7th value), so a wrong journal id in a fixed table never shows another boss's name.
function Encounter.JournalName(journalID, encounterID)
	if type(journalID) ~= "number" then return nil end
	local v = readable("EJ_GetEncounterInfo", journalID)
	if not v or not str(v[1]) then return nil end
	if encounterID ~= nil and num(v[7]) ~= nil and v[7] ~= encounterID then return nil end
	return v[1]
end

-- The name of an instance in the client's language from the Encounter Journal (EJ_GetInstanceInfo(journalInstanceID)),
-- or nil. With `instanceID` the journal entry must name the same map when it says one (its 10th value).
function Encounter.JournalInstanceName(journalInstanceID, instanceID)
	if type(journalInstanceID) ~= "number" then return nil end
	local v = readable("EJ_GetInstanceInfo", journalInstanceID)
	if not v or not str(v[1]) then return nil end
	if instanceID ~= nil and num(v[10]) ~= nil and v[10] ~= instanceID then return nil end
	return v[1]
end

-- The cover of an instance from the Encounter Journal (EJ_GetInstanceInfo(journalInstanceID): the 4th value, the button
-- image, else the 3rd, the background), a file id or a path, or nil when the client has none (the window then draws a
-- generated cover).
function Encounter.JournalInstanceCover(journalInstanceID)
	if type(journalInstanceID) ~= "number" then return nil end
	local v = readable("EJ_GetInstanceInfo", journalInstanceID)
	if not v then return nil end
	for _, i in ipairs({ 4, 3 }) do
		local img = v[i]
		if (type(img) == "number" and img > 0) or (type(img) == "string" and img ~= "") then
			if not IsSecret(img) then return img end
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- Chat restrictions and lockdown (docs/ANALISI.md §1, §11 risk 3)
---------------------------------------------------------------------------------------------------------------------
local Chat = {}
Compat.Chat = Chat

-- The addon restriction kinds of Enum.AddOnRestrictionType that matter (names as in the retail enum; one the client
-- does not have is skipped, not an error).
Compat.RESTRICTION_KINDS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }

-- true while the client blocks outgoing chat messages (the messages must wait in the queue).
function Chat.InChatLockdown()
	local v, state = first("C_ChatInfo.InChatMessagingLockdown")
	if state == AVAILABLE then return v and true or false end
	return state == RESTRICTED or state == ERROR   -- cannot tell: stay on the safe side
end

-- true when the addon is read only: outgoing addon chat messages are restricted.
function Chat.OutgoingAddonRestricted()
	local v, state = first("C_ChatInfo.AreOutgoingAddonChatMessagesRestricted")
	if state == AVAILABLE then return v and true or false end
	return state == RESTRICTED or state == ERROR
end

-- active, state for one kind ("Combat", ...). Missing enum or function: false, nil (nothing can be known and nothing
-- is restricted). An error or a secret state counts as active (safe side). Falls back to IsAddOnRestrictionActive.
function Chat.RestrictionActive(kind)
	local types = Resolve("Enum.AddOnRestrictionType")
	local value = type(types) == "table" and types[kind] or nil
	if value == nil then return false, nil end
	local state, callState = first("C_RestrictedActions.GetAddOnRestrictionState", value)
	if callState == AVAILABLE and type(state) == "number" then return state > 0, state end
	if callState == RESTRICTED or callState == ERROR then return true, nil end
	local active, activeState = first("C_RestrictedActions.IsAddOnRestrictionActive", value)
	if activeState == AVAILABLE then return active and true or false, nil end
	return activeState ~= MISSING, nil
end

-- The first active restriction kind, or nil.
function Chat.RestrictionAny()
	for _, kind in ipairs(Compat.RESTRICTION_KINDS) do
		if (Chat.RestrictionActive(kind)) then return kind end
	end
	return nil
end

-- Writes `text` to a chat channel ("RAID", "WHISPER" with a target). true, or false and the state of the call.
function Chat.Send(text, chatType, target)
	local state = Compat.Call("C_ChatInfo.SendChatMessage", text, chatType, nil, target)
	return state == AVAILABLE, state
end

-- Sending is allowed: no lockdown, no restriction, not read only.
function Chat.CanSend()
	return not Chat.InChatLockdown() and not Chat.OutgoingAddonRestricted() and Chat.RestrictionAny() == nil
end

-- true while the player is in combat lockdown (UI changes are blocked); false when the function is missing.
function Compat.InCombat()
	return (first("InCombatLockdown")) and true or false
end

---------------------------------------------------------------------------------------------------------------------
-- Loot method, master looter and threshold (spike S1)
---------------------------------------------------------------------------------------------------------------------
local Loot = {}
Compat.Loot = Loot

local LOOT_METHOD_KEYS = {   -- Enum.LootMethod names -> the keys this addon uses
	FreeForAll = "freeforall", RoundRobin = "roundrobin", Master = "master", Group = "group", NeedBeforeGreed = "needbeforegreed",
	Personal = "personal",
}
-- The legacy GetLootMethod strings, lower-cased [verify: the global is not in the dump].
local LEGACY_METHODS = { freeforall = "freeforall", roundrobin = "roundrobin", master = "master", group = "group",
	needbeforegreed = "needbeforegreed", personal = "personal" }

-- The loot method as a key ("master", "group", "personal", ...), the master looter's party id (nil unless master loot)
-- and raid id; nil when the client does not say. C_PartyInfo.GetLootMethod first, the legacy global as a fallback.
function Loot.Method()
	local v = readable("C_PartyInfo.GetLootMethod")
	if v and v[1] ~= nil then
		local names = enumNames("LootMethod")
		local key = type(v[1]) == "number" and names and names[v[1]] and LOOT_METHOD_KEYS[names[v[1]]] or nil
		if key then return key, num(v[2]), num(v[3]) end
	end
	local legacy = readable("GetLootMethod")
	if legacy and type(legacy[1]) == "string" and LEGACY_METHODS[legacy[1]:lower()] then
		return LEGACY_METHODS[legacy[1]:lower()], num(legacy[2]), num(legacy[3])
	end
	return nil
end

function Loot.IsMasterLootMethod()
	return Loot.Method() == "master"
end

-- true when the player is the master looter; false when not or when the client does not say.
function Loot.IsMasterLooter()
	return (first("IsMasterLooter")) and true or false
end

-- The quality that opens the master loot / group loot rolls (0 poor .. 6), nil when unknown.
function Loot.Threshold()
	return num((first("GetLootThreshold")))
end

-- true when the client runs the legacy loot rules (master loot is possible), false when it does not, nil when unknown
-- [verify S1a].
function Loot.LegacyMode()
	local v, state = first("C_Loot.IsLegacyLootModeEnabled")
	if state ~= AVAILABLE then return nil end
	return v and true or false
end

-- true when the client says this loot method can be chosen, nil when it does not say [verify S1b].
function Loot.MethodAvailable(key)
	local names = enumNames("LootMethod")
	if not names then return nil end
	for value, name in pairs(names) do
		if LOOT_METHOD_KEYS[name] == key then
			local v, state = first("C_PartyInfo.IsLootMethodAvailable", value)
			if state ~= AVAILABLE then return nil end
			return v and true or false
		end
	end
	return nil
end

-- Asks the client to switch the loot method (the party leader's act). Returns the call state; nothing here checks
-- that the group really changed: read Loot.Method() after the PARTY_LOOT_METHOD_CHANGED event.
function Loot.SetMethod(key, masterLooterName)
	local names = enumNames("LootMethod")
	if not names then return MISSING end
	for value, name in pairs(names) do
		if LOOT_METHOD_KEYS[name] == key then
			local _, state = first("C_PartyInfo.SetLootMethod", value, masterLooterName)
			return state
		end
	end
	return MISSING
end

---------------------------------------------------------------------------------------------------------------------
-- The loot window and master loot candidates (spike S2)
---------------------------------------------------------------------------------------------------------------------
Loot.MAX_CANDIDATES = 40

function Loot.NumItems()
	return num((first("GetNumLootItems"))) or 0
end

-- The slot as a plain table: { slot, link, icon, name, quantity, quality, locked, isQuestItem, isCurrency, hasItem,
-- sources = { { guid, quantity }, ... } }; nil for an empty slot or when nothing can be read. A hidden field is nil.
-- GetLootSlotInfo has two shapes [verify S2a]: retail (icon, name, quantity, currencyID, quality, locked, isQuestItem)
-- and the older (icon, name, quantity, quality, locked, isQuestItem): the fifth value is a boolean in the older one.
function Loot.Slot(slot)
	if type(slot) ~= "number" then return nil end
	local link = str((first("GetLootSlotLink", slot)))
	local v = readable("GetLootSlotInfo", slot)
	if not link and not (v and str(v[2])) then return nil end
	local out = { slot = slot, link = link, sources = {} }
	if v then
		out.icon, out.name, out.quantity = v[1], str(v[2]), num(v[3])
		if type(v[5]) == "boolean" then
			out.quality, out.locked, out.isQuestItem = num(v[4]), v[5], v[6] and true or false
		else
			out.isCurrency = num(v[4]) ~= nil and num(v[4]) > 0
			out.quality, out.locked, out.isQuestItem = num(v[5]), v[6] and true or false, v[7] and true or false
		end
	end
	local has, hasState = first("LootSlotHasItem", slot)
	if hasState == AVAILABLE then out.hasItem = has and true or false end
	local sources = readable("GetLootSourceInfo", slot)
	if sources then
		for i = 1, #sources - 1, 2 do
			local guid = str(sources[i])
			if guid then out.sources[#out.sources + 1] = { guid = guid, quantity = num(sources[i + 1]) or 1 } end
		end
	end
	return out
end

-- Every readable slot of the open loot window, in slot order.
function Loot.Slots()
	local out = {}
	for slot = 1, min(Loot.NumItems(), 100) do
		local s = Loot.Slot(slot)
		if s then out[#out + 1] = s end
	end
	return out
end

-- The master loot candidates of a slot: { { index, name }, ... } (index is what GiveMasterLoot takes), empty when the
-- client gives none (not the master looter, no window open) [verify S2b].
function Loot.Candidates(slot)
	local out = {}
	if type(slot) ~= "number" then return out end
	for i = 1, Loot.MAX_CANDIDATES do
		local values = readable("GetMasterLootCandidate", slot, i)
		if not values then break end   -- a missing or failing API will not get better at the next index
		if str(values[1]) then out[#out + 1] = { index = i, name = values[1] } end
	end
	return out
end

-- Gives the slot's item to the candidate with this index (the master looter's act, from a click or command)
-- [verify S2c: whether an addon may call it]. Returns the call state.
function Loot.Give(slot, candidateIndex)
	if type(slot) ~= "number" or type(candidateIndex) ~= "number" then return MISSING end
	local _, state = first("GiveMasterLoot", slot, candidateIndex)
	return state
end

---------------------------------------------------------------------------------------------------------------------
-- Rolls and loot messages: patterns built from the game's globals, never written by hand (spike S3)
---------------------------------------------------------------------------------------------------------------------
local Roll = {}
Compat.Roll = Roll

-- Builds a Lua pattern from a game format string (%s, %d, %1$s ...). Returns the pattern and the ordered list of
-- conversions ("s" or "d"), or nil for a missing or non-string format.
function Roll.BuildPattern(fmt)
	if type(fmt) ~= "string" or IsSecret(fmt) then return nil end
	local out, kinds, i = { "^" }, {}, 1
	while i <= #fmt do
		local c = fmt:sub(i, i)
		if c == "%" then
			local spec = fmt:match("^%%%d*%$?[sd]", i)
			if spec then
				local conv = spec:sub(-1)
				kinds[#kinds + 1] = conv
				out[#out + 1] = (conv == "d") and "(%-?%d+)" or "(.-)"
				i = i + #spec
			else
				out[#out + 1] = "%%"
				i = i + (fmt:sub(i + 1, i + 1) == "%" and 2 or 1)
			end
		elseif c:match("[%^%$%(%)%.%[%]%*%+%-%?]") then
			out[#out + 1] = "%" .. c
			i = i + 1
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
	out[#out + 1] = "$"
	return table.concat(out), kinds
end

-- Argument position of each conversion (1, 2 ... or the explicit %2$s number).
local function orders(fmt)
	local order, n = {}, 0
	for pos in fmt:gmatch("%%(%d*)%$?[sd]") do
		n = n + 1
		order[n] = tonumber(pos) or n
	end
	return order
end

-- Matches text against a game format; returns the captures in the format's argument order, or nil. Secret or
-- non-string text never matches (and is never looked at).
function Roll.Match(fmt, text)
	if type(text) ~= "string" or IsSecret(text) then return nil end
	local pattern = Roll.BuildPattern(fmt)
	if not pattern then return nil end
	local caps = { text:match(pattern) }
	if #caps == 0 then return nil end
	local order, out = orders(fmt), {}
	for i, v in ipairs(caps) do out[order[i] or i] = v end
	return out
end

-- The roll result in a CHAT_MSG_SYSTEM text: { player, roll, min, max } or nil (also for secret text: the second
-- result is "secret" then, so a caller can tell a hidden message from an unrelated one).
function Roll.Parse(text)
	if IsSecret(text) then return nil, "secret" end
	local caps = Roll.Match(_G.RANDOM_ROLL_RESULT, text)
	if not caps then return nil end
	local roll, lo, hi = tonumber(caps[2]), tonumber(caps[3]), tonumber(caps[4])
	if not (caps[1] and roll and lo and hi) then return nil end
	return { player = caps[1], roll = roll, min = lo, max = hi }
end

-- Rolls once, server side (the result comes back as a system message). Returns the call state.
function Roll.Send(lo, hi)
	if type(lo) ~= "number" or type(hi) ~= "number" or lo > hi then return MISSING end
	local _, state = first("RandomRoll", lo, hi)
	return state
end

-- The loot message globals and what each tells: kind, whether the receiver is the player, a quantity capture.
Roll.LOOT_FORMATS = {
	{ "LOOT_ITEM_SELF_MULTIPLE", self = true, count = true }, { "LOOT_ITEM_SELF", self = true },
	{ "LOOT_ITEM_PUSHED_SELF_MULTIPLE", self = true, count = true }, { "LOOT_ITEM_PUSHED_SELF", self = true },
	{ "LOOT_ITEM_MULTIPLE", count = true }, { "LOOT_ITEM" },
	{ "LOOT_ITEM_PUSHED_MULTIPLE", count = true }, { "LOOT_ITEM_PUSHED" },
}

-- A CHAT_MSG_LOOT text: { kind (the global's name), player (nil for the player's own), link, count } or nil. The
-- longer "multiple" formats are tried first. Secret text: nil, "secret".
function Roll.ParseLoot(text)
	if IsSecret(text) then return nil, "secret" end
	for _, def in ipairs(Roll.LOOT_FORMATS) do
		local fmt = _G[def[1]]
		local caps = Roll.Match(fmt, text)
		if caps then
			local out = { kind = def[1], link = caps[def.self and 1 or 2], count = 1 }
			if not def.self then out.player = caps[1] end
			if def.count then out.count = tonumber(caps[def.self and 2 or 3]) or 1 end
			if out.link then return out end
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- Items and stats (spike S5): C_Item.* first, the old globals as the fallback [verify, not in the dump]
---------------------------------------------------------------------------------------------------------------------
local Item = {}
Compat.Item = Item

local function itemCall(name, ...)
	local v = all("C_Item." .. name, ...)
	if not v then v = all(name, ...) end
	return v
end

-- { name, link, quality, level, minLevel, type, subType, stackCount, equipLoc, icon, sellPrice, classID, subclassID,
-- bindType } of an item the client has loaded (an id, a link or a name), else nil: ask with Item.Request.
function Item.Info(item)
	if item == nil then return nil end
	local v = itemCall("GetItemInfo", item)
	if not v or not str(v[1]) then return nil end
	return { name = v[1], link = str(v[2]), quality = num(v[3]), level = num(v[4]), minLevel = num(v[5]), type = str(v[6]),
		subType = str(v[7]), stackCount = num(v[8]), equipLoc = str(v[9]), icon = v[10], sellPrice = num(v[11]),
		classID = num(v[12]), subclassID = num(v[13]), bindType = num(v[14]) }
end

-- What the client knows without loading the item: { itemID, type, subType, equipLoc, icon, classID, subClassID }.
function Item.Instant(item)
	if item == nil then return nil end
	local v = itemCall("GetItemInfoInstant", item)
	if not v or not num(v[1]) then return nil end
	return { itemID = v[1], type = str(v[2]), subType = str(v[3]), equipLoc = str(v[4]), icon = v[5], classID = num(v[6]),
		subClassID = num(v[7]) }
end

-- The item level of an item or link, including its upgrades (spike S5b: also inside the raid): the actual level, or nil.
function Item.Level(item)
	if item == nil then return nil end
	local v = all("C_Item.GetDetailedItemLevelInfo", item)
	return v and num(v[1]) or nil
end

-- The stats of an item link as a plain table { ITEM_MOD_... = number }, or nil [verify S5c: bonus stats of raid gear].
function Item.Stats(link)
	if type(link) ~= "string" then return nil end
	local v = itemCall("GetItemStats", link)
	local t = v and readableCopy(v[1])
	if not t then return nil end
	local out = {}
	for k, n in pairs(t) do if type(k) == "string" and num(n) then out[k] = n end end
	return out
end

-- What changes when item 2 replaces item 1: { ITEM_MOD_... = difference }, nil when the client does not say
-- [verify S5c]. Both links must be strings.
function Item.StatDelta(link1, link2)
	if type(link1) ~= "string" or type(link2) ~= "string" then return nil end
	local v = all("C_Item.GetItemStatDelta", link1, link2)
	local t = v and readableCopy(v[1])
	if not t then return nil end
	local out = {}
	for k, n in pairs(t) do if type(k) == "string" and num(n) then out[k] = n end end
	return out
end

-- true / false when the client says the item can be equipped, nil when it does not.
function Item.IsEquippable(item)
	if item == nil then return nil end
	local v, state = first("C_Item.IsEquippableItem", item)
	if state ~= AVAILABLE then
		v, state = first("IsEquippableItem", item)
		if state ~= AVAILABLE then return nil end
	end
	return v and true or false
end

-- true / false when the item's spec list contains the class and specialization, nil when the client does not say.
function Item.ContainsSpec(item, classID, specID)
	if item == nil or type(classID) ~= "number" or type(specID) ~= "number" then return nil end
	local v, state = first("C_Item.DoesItemContainSpec", item, classID, specID)
	if state ~= AVAILABLE then return nil end
	return v and true or false
end

-- The specialization ids the item is for (C_Item.GetItemSpecInfo), a list of numbers, or nil.
function Item.SpecInfo(item)
	if item == nil then return nil end
	local t = readableCopy((first("C_Item.GetItemSpecInfo", item)))
	if not t then return nil end
	local out = {}
	for _, id in ipairs(t) do if num(id) then out[#out + 1] = id end end
	return out
end

-- The link of the item in an inventory slot of the player (1 head .. 19), nil when empty or hidden.
function Item.EquippedLink(slot)
	if type(slot) ~= "number" then return nil end
	return str((first("GetInventoryItemLink", "player", slot)))
end

-- Asks the client to load an item; GET_ITEM_INFO_RECEIVED comes when it has. Returns the call state.
function Item.Request(itemID)
	if not num(itemID) then return MISSING end
	local _, state = first("C_Item.RequestLoadItemDataByID", itemID)
	return state
end

---------------------------------------------------------------------------------------------------------------------
-- Specializations (spike S6)
---------------------------------------------------------------------------------------------------------------------
local Spec = {}
Compat.Spec = Spec

-- How many specializations the player's class has (0 when unknown).
function Spec.Count()
	local n = num((first("GetNumSpecializations")))
	if n then return n end
	local classID = Player.ClassID()
	return classID and num((first("C_SpecializationInfo.GetNumSpecializationsForClassID", classID))) or 0
end

-- The active specialization index (1..n), nil when the client does not say or none is chosen.
function Spec.Index()
	local v = first("C_SpecializationInfo.GetSpecialization")
	if v == nil then v = first("GetSpecialization") end   -- [verify: not in the dump]
	v = num(v)
	if v and v >= 1 then return v end
	return nil
end

-- { index, id, name, role, primaryStat, icon } of a specialization index, nil when the client does not say.
function Spec.Info(index)
	if type(index) ~= "number" then return nil end
	local v = all("C_SpecializationInfo.GetSpecializationInfo", index)
	if not v then v = all("GetSpecializationInfo", index) end   -- [verify: not in the dump]
	if not v or not num(v[1]) then return nil end
	return { index = index, id = v[1], name = str(v[2]), icon = v[4], role = str(v[5]), primaryStat = num(v[6]) }
end

-- The player's active specialization: Spec.Info of Spec.Index(), or nil.
function Spec.Active()
	local index = Spec.Index()
	return index and Spec.Info(index) or nil
end

-- "TANK", "HEALER" or "DAMAGER" for a specialization index, or nil.
function Spec.Role(index)
	if type(index) ~= "number" then return nil end
	local role = str((first("GetSpecializationRole", index)))
	if role then return role end
	local info = Spec.Info(index)
	return info and info.role or nil
end

-- The specialization id of another unit once inspected (C_SpecializationInfo.GetInspectSpecialization), nil when unknown
-- (the client answers 0 before the inspect data is in) [verify S6b].
function Spec.Inspect(unit)
	if type(unit) ~= "string" then return nil end
	local id = num((first("C_SpecializationInfo.GetInspectSpecialization", unit)))
	if id and id > 0 then return id end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- Calendar (spike S8b): the official raid event. Reading needs the calendar opened once (Calendar.Open).
---------------------------------------------------------------------------------------------------------------------
local Calendar = {}
Compat.Calendar = Calendar

-- Asks the client to load the calendar (C_Calendar.OpenCalendar). Returns the call state.
function Calendar.Open()
	local _, state = first("C_Calendar.OpenCalendar")
	return state
end

-- { month, year, numDays, firstWeekday } of the month `offset` months from the one shown, or nil.
function Calendar.MonthInfo(offset)
	return readableCopy((first("C_Calendar.GetMonthInfo", num(offset) or 0)))
end

-- The events of a day: { { index (the client's), eventID, title, calendarType, eventType, startTime, endTime, inviteStatus, modStatus }, ... }.
-- `offset` is the month relative to the shown one (0 = this month), `day` the day of the month. Empty when the client
-- says nothing (calendar not loaded, API missing, hidden).
function Calendar.DayEvents(offset, day)
	local out = {}
	offset, day = num(offset), num(day)
	if not offset or not day then return out end
	local n = num((first("C_Calendar.GetNumDayEvents", offset, day))) or 0
	for i = 1, min(n, 50) do
		local e = readableCopy((first("C_Calendar.GetDayEvent", offset, day, i)))
		if e and str(e.title) then
			out[#out + 1] = { index = i, eventID = e.eventID, title = e.title, calendarType = str(e.calendarType), eventType = e.eventType,
				startTime = e.startTime, endTime = e.endTime, inviteStatus = e.inviteStatus, modStatus = str(e.modStatus) }
		end
	end
	return out
end

-- Opens an event of a day for reading its invites (the calendar's selected event); true when the client did.
function Calendar.OpenEvent(offset, day, index)
	local v, state = first("C_Calendar.OpenEvent", num(offset) or 0, num(day) or 1, num(index) or 1)
	return state == AVAILABLE and v == true
end

function Calendar.CloseEvent()
	local _, state = first("C_Calendar.CloseEvent")
	return state
end

-- How many invites the open event has (0 when none is open or the client does not say).
function Calendar.NumInvites()
	return num((first("C_Calendar.GetNumInvites"))) or 0
end

-- The invite `i` of the open event: { name, level, className, classFilename, inviteStatus, modStatus, guid }, or nil.
function Calendar.Invite(i)
	if type(i) ~= "number" then return nil end
	local t = readableCopy((first("C_Calendar.EventGetInvite", i)))
	if not t or not str(t.name) then return nil end
	return { name = t.name, level = num(t.level), className = str(t.className), classFilename = str(t.classFilename),
		inviteStatus = t.inviteStatus, modStatus = str(t.modStatus), guid = str(t.inviteGuid) }
end

---------------------------------------------------------------------------------------------------------------------
-- Time, timers and encoding
---------------------------------------------------------------------------------------------------------------------
function Compat.ServerTime()
	local v = first("GetServerTime")
	if type(v) == "number" then return v end
	return time()
end

-- The realm's calendar day as a number YYYYMMDD (C_DateAndTime.GetCurrentCalendarTime is the server's own calendar);
-- the UTC date of the server time when the client does not say.
function Compat.ServerDay()
	local t = first("C_DateAndTime.GetCurrentCalendarTime")
	if type(t) == "table" and num(t.year) and num(t.month) and num(t.monthDay) then
		return t.year * 10000 + t.month * 100 + t.monthDay
	end
	return tonumber(date("!%Y%m%d", Compat.ServerTime()))
end

-- Monotonic seconds with sub-second precision (GetTime); the wall clock when the client function is missing.
function Compat.Now()
	local v = first("GetTime")
	if type(v) == "number" then return v end
	return time()
end

-- C_Timer wrappers. After(seconds, fn) -> true when scheduled. NewTimer / NewTicker -> a handle with :Cancel(), or nil
-- when timers are not available (the caller must cope: no timer, no sending).
function Compat.After(seconds, fn)
	local state = Compat.Call("C_Timer.After", seconds, fn)
	return state == AVAILABLE
end

function Compat.NewTimer(seconds, fn)
	local state, handle = Compat.Call("C_Timer.NewTimer", seconds, fn)
	if state == AVAILABLE and type(handle) == "table" then return handle end
	return nil
end

function Compat.NewTicker(seconds, fn)
	local state, handle = Compat.Call("C_Timer.NewTicker", seconds, fn)
	if state == AVAILABLE and type(handle) == "table" then return handle end
	return nil
end

local function enum(name, key)
	local t = Resolve("Enum." .. name)
	return type(t) == "table" and t[key] or nil
end

-- Encoding wrappers: value, or nil plus an error text (never raise).
local function encoding(path, ...)
	local state, detail, _, values = run(Resolve("C_EncodingUtil." .. path), ...)
	if state == AVAILABLE and values[1] ~= nil then return values[1] end
	return nil, state == AVAILABLE and "no result" or (state .. (detail and (": " .. detail) or ""))
end

Compat.CBOR = {
	Encode = function(value) return encoding("SerializeCBOR", value) end,
	Decode = function(text) return encoding("DeserializeCBOR", text) end,
}
Compat.Compress = {
	Deflate = function(text) return encoding("CompressString", text, enum("CompressionMethod", "Deflate"), enum("CompressionLevel", "Default")) end,
	Inflate = function(text) return encoding("DecompressString", text, enum("CompressionMethod", "Deflate")) end,
}
Compat.Base64 = {
	Encode = function(text) return encoding("EncodeBase64", text) end,
	Decode = function(text) return encoding("DecodeBase64", text) end,
}

---------------------------------------------------------------------------------------------------------------------
-- Build, API probe and feature capabilities
---------------------------------------------------------------------------------------------------------------------
function Compat.BuildInfo()
	local values = all("GetBuildInfo") or {}
	return {
		version = tostring(values[1] or "?"), build = tostring(values[2] or "?"), interface = tonumber(values[4]) or 0,
		projectID = WOW_PROJECT_ID, isForever = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT,
	}
end

-- API definitions: { id, group, path, call = true to call it, args = {...}, restrictedWhenTrue, note, table }.
-- Functions with side effects (GiveMasterLoot, RandomRoll, SetLootMethod, OpenCalendar, queries) are only checked for
-- existence, never called by the probe.
local CAPS = {
	{ "loot.GetLootMethod", "loot", "C_PartyInfo.GetLootMethod", call = true },
	{ "loot.GetLootMethodLegacy", "loot", "GetLootMethod", note = "[verify] fallback, not in the dump" },
	{ "loot.SetLootMethod", "loot", "C_PartyInfo.SetLootMethod", note = "[verify S1b]" },
	{ "loot.IsLegacyLootModeEnabled", "loot", "C_Loot.IsLegacyLootModeEnabled", call = true },
	{ "loot.IsMasterLooter", "loot", "IsMasterLooter", call = true },
	{ "loot.GetLootThreshold", "loot", "GetLootThreshold", call = true },
	{ "loot.GetNumLootItems", "loot", "GetNumLootItems", call = true },
	{ "loot.GetLootSlotLink", "loot", "GetLootSlotLink", note = "[verify S2a]" },
	{ "loot.GetLootSlotInfo", "loot", "GetLootSlotInfo", note = "[verify S2a] return shape" },
	{ "loot.GetLootSourceInfo", "loot", "GetLootSourceInfo", note = "[verify S2a]" },
	{ "loot.GetMasterLootCandidate", "loot", "GetMasterLootCandidate", note = "[verify S2b]" },
	{ "loot.GiveMasterLoot", "loot", "GiveMasterLoot", note = "[verify S2c] from an addon" },
	{ "roll.RandomRoll", "roll", "RandomRoll", note = "[verify S3b]" },
	{ "roll.RANDOM_ROLL_RESULT", "roll", "RANDOM_ROLL_RESULT", string = true },
	{ "roll.LOOT_ITEM", "roll", "LOOT_ITEM", string = true },
	{ "roll.LOOT_ITEM_SELF", "roll", "LOOT_ITEM_SELF", string = true },
	{ "encounter.IsEncounterInProgress", "encounter", "IsEncounterInProgress", call = true },
	{ "encounter.GetInstanceInfo", "encounter", "GetInstanceInfo", call = true },
	{ "encounter.GetRaidDifficultyID", "encounter", "GetRaidDifficultyID", call = true },
	{ "encounter.EJ_GetEncounterInfo", "encounter", "EJ_GetEncounterInfo", note = "[verify] journal ids of the pack" },
	{ "encounter.EJ_GetInstanceInfo", "encounter", "EJ_GetInstanceInfo", note = "[verify] journal ids of the pack" },
	{ "item.C_Item.GetItemInfo", "item", "C_Item.GetItemInfo" },
	{ "item.C_Item.GetItemInfoInstant", "item", "C_Item.GetItemInfoInstant" },
	{ "item.C_Item.GetDetailedItemLevelInfo", "item", "C_Item.GetDetailedItemLevelInfo", note = "[verify S5b]" },
	{ "item.C_Item.GetItemStats", "item", "C_Item.GetItemStats", note = "[verify S5c]" },
	{ "item.C_Item.GetItemStatDelta", "item", "C_Item.GetItemStatDelta", note = "[verify S5c]" },
	{ "item.C_Item.IsEquippableItem", "item", "C_Item.IsEquippableItem" },
	{ "item.C_Item.DoesItemContainSpec", "item", "C_Item.DoesItemContainSpec", note = "[verify S5c]" },
	{ "item.C_Item.GetItemSpecInfo", "item", "C_Item.GetItemSpecInfo", note = "[verify S5c]" },
	{ "item.C_Item.RequestLoadItemDataByID", "item", "C_Item.RequestLoadItemDataByID" },
	{ "item.GetInventoryItemLink", "item", "GetInventoryItemLink" },
	{ "spec.GetSpecialization", "spec", "C_SpecializationInfo.GetSpecialization", call = true, note = "[verify S6a]" },
	{ "spec.GetSpecializationInfo", "spec", "C_SpecializationInfo.GetSpecializationInfo", note = "[verify S6a]" },
	{ "spec.GetNumSpecializations", "spec", "GetNumSpecializations", call = true },
	{ "spec.GetInspectSpecialization", "spec", "C_SpecializationInfo.GetInspectSpecialization", note = "[verify S6b]" },
	{ "guild.IsInGuild", "guild", "IsInGuild", call = true },
	{ "guild.GetGuildInfo", "guild", "GetGuildInfo", call = true, args = { "player" } },
	{ "guild.IsGuildLeader", "guild", "IsGuildLeader", call = true },
	{ "guild.IsGuildOfficer", "guild", "C_GuildInfo.IsGuildOfficer", call = true },
	{ "guild.CanEditOfficerNote", "guild", "C_GuildInfo.CanEditOfficerNote", call = true },
	{ "guild.GetNumGuildMembers", "guild", "GetNumGuildMembers", call = true },
	{ "guild.GetGuildRosterInfo", "guild", "GetGuildRosterInfo" },
	{ "guild.GuildRoster", "guild", "C_GuildInfo.GuildRoster" },
	{ "guild.GuildControlGetNumRanks", "guild", "GuildControlGetNumRanks", call = true, note = "[verify S7b]" },
	{ "guild.GuildControlGetRankName", "guild", "GuildControlGetRankName", note = "[verify S7b]" },
	{ "guild.GuildControlGetRankFlags", "guild", "C_GuildInfo.GuildControlGetRankFlags", note = "[verify S7b] which flag is which" },
	{ "guild.GetGuildRankOrder", "guild", "C_GuildInfo.GetGuildRankOrder" },
	{ "group.IsInGroup", "group", "IsInGroup", call = true },
	{ "group.IsInRaid", "group", "IsInRaid", call = true },
	{ "group.GetNumGroupMembers", "group", "GetNumGroupMembers", call = true },
	{ "group.GetRaidRosterInfo", "group", "GetRaidRosterInfo", note = "[verify] secret values in instances" },
	{ "group.UnitIsGroupLeader", "group", "UnitIsGroupLeader", call = true, args = { "player" } },
	{ "group.UnitIsInMyGuild", "group", "UnitIsInMyGuild" },
	{ "group.InGuildParty", "group", "InGuildParty", call = true, note = "[verify] guild group on Forever" },
	{ "player.UnitGUID", "player", "UnitGUID", call = true, args = { "player" } },
	{ "player.UnitClass", "player", "UnitClass", call = true, args = { "player" } },
	{ "player.GetLocale", "player", "GetLocale", call = true, note = "[verify S8a]" },
	{ "calendar.OpenCalendar", "calendar", "C_Calendar.OpenCalendar", note = "[verify S8b]" },
	{ "calendar.GetMonthInfo", "calendar", "C_Calendar.GetMonthInfo" },
	{ "calendar.GetNumDayEvents", "calendar", "C_Calendar.GetNumDayEvents" },
	{ "calendar.GetDayEvent", "calendar", "C_Calendar.GetDayEvent", note = "[verify S8b]" },
	{ "calendar.OpenEvent", "calendar", "C_Calendar.OpenEvent" },
	{ "calendar.EventGetInvite", "calendar", "C_Calendar.EventGetInvite", note = "[verify S8b] attendees" },
	{ "chat.InChatMessagingLockdown", "chat", "C_ChatInfo.InChatMessagingLockdown", call = true, restrictedWhenTrue = true },
	{ "chat.AreOutgoingAddonChatMessagesRestricted", "chat", "C_ChatInfo.AreOutgoingAddonChatMessagesRestricted", call = true, restrictedWhenTrue = true },
	{ "chat.SendAddonMessage", "chat", "C_ChatInfo.SendAddonMessage" },
	{ "chat.RegisterAddonMessagePrefix", "chat", "C_ChatInfo.RegisterAddonMessagePrefix" },
	{ "time.GetServerTime", "time", "GetServerTime", call = true },
	{ "time.GetTime", "time", "GetTime", call = true },
	{ "time.NewTicker", "time", "C_Timer.NewTicker" },
	{ "time.After", "time", "C_Timer.After" },
	{ "secret.issecretvalue", "secret", "issecretvalue" },
	{ "secret.canaccessvalue", "secret", "canaccessvalue" },
	{ "restriction.GetAddOnRestrictionState", "restriction", "C_RestrictedActions.GetAddOnRestrictionState" },
	{ "restriction.AddOnRestrictionType", "restriction", "Enum.AddOnRestrictionType", table = true },
	{ "encoding.SerializeCBOR", "encoding", "C_EncodingUtil.SerializeCBOR" },
	{ "encoding.DeserializeCBOR", "encoding", "C_EncodingUtil.DeserializeCBOR" },
	{ "encoding.CompressString", "encoding", "C_EncodingUtil.CompressString" },
	{ "encoding.DecompressString", "encoding", "C_EncodingUtil.DecompressString" },
	{ "encoding.EncodeBase64", "encoding", "C_EncodingUtil.EncodeBase64" },
	{ "encoding.DecodeBase64", "encoding", "C_EncodingUtil.DecodeBase64" },
}
Compat.CAPABILITY_DEFS = CAPS

local function probeOne(def)
	local value = Resolve(def[3])
	if def.table then
		if type(value) == "table" then return AVAILABLE, nil end
		return MISSING, nil
	end
	if def.string then
		if type(value) == "string" and not IsSecret(value) then return AVAILABLE, nil end
		return MISSING, nil
	end
	if type(value) ~= "function" then return MISSING, nil end
	if not def.call then return AVAILABLE, def.note end
	local state, detail, _, values = run(value, unpack(def.args or {}))
	local result = values[1]
	if state == AVAILABLE then
		if def.restrictedWhenTrue and result == true then return RESTRICTED, "active now" end
		if type(result) == "boolean" then detail = "returns " .. tostring(result) elseif def.note then detail = def.note end
	end
	return state, detail
end

-- The feature capabilities FDCP depends on, in report order. Each is { state, detail }: "available", "missing" or
-- "unknown" (the client has the API but nothing has confirmed yet that the server fills it). Probe sets what the
-- client can tell at login; later steps refine them with Compat:SetFeature (the loot window when the first one opens,
-- the roll messages when the first one is read, the transport when a RAID message comes back, ...).
Compat.FEATURES = { "masterLoot", "lootWindow", "rollMessages", "lootMessages", "encounterState", "itemStats", "itemStatDelta",
	"specialization", "guildRanks", "calendarRaid", "groupRoster", "addonMessages" }

local function hasAll(...)
	for i = 1, select("#", ...) do
		if type(Resolve((select(i, ...)))) ~= "function" then return false end
	end
	return true
end

local function probeFeatures()
	local f = {}
	local function set(id, state, detail) f[id] = { state = state, detail = detail } end

	if hasAll("IsMasterLooter", "GiveMasterLoot", "GetMasterLootCandidate") and (hasAll("C_PartyInfo.GetLootMethod") or hasAll("GetLootMethod")) then
		local method = Loot.Method()
		if method == "master" then
			set("masterLoot", AVAILABLE, "the group uses master loot")
		else
			set("masterLoot", UNKNOWN, "APIs present, no master loot group seen yet (S1, S2)")
		end
	else
		set("masterLoot", MISSING, "master loot API missing")
	end

	if hasAll("GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo", "GetLootSourceInfo") then
		set("lootWindow", UNKNOWN, "no loot window read yet (S2a)")
	else
		set("lootWindow", MISSING, "loot window API missing")
	end

	if hasAll("RandomRoll") and Roll.BuildPattern(_G.RANDOM_ROLL_RESULT) then
		set("rollMessages", UNKNOWN, "no roll message read yet (S3c)")
	else
		set("rollMessages", MISSING, "RandomRoll or RANDOM_ROLL_RESULT missing")
	end

	if Roll.BuildPattern(_G.LOOT_ITEM) and Roll.BuildPattern(_G.LOOT_ITEM_SELF) then
		set("lootMessages", UNKNOWN, "no loot message read yet (S3e)")
	else
		set("lootMessages", MISSING, "LOOT_ITEM globals missing")
	end

	local _, encounterState = first("IsEncounterInProgress")
	if encounterState == AVAILABLE then
		set("encounterState", AVAILABLE)
	elseif encounterState == MISSING then
		set("encounterState", MISSING, "IsEncounterInProgress missing")
	else
		set("encounterState", UNKNOWN, "IsEncounterInProgress " .. encounterState)
	end

	if hasAll("C_Item.GetItemInfo", "C_Item.GetItemInfoInstant", "C_Item.GetItemStats") then
		set("itemStats", UNKNOWN, "bonus stats of raid gear unverified (S5c)")
	else
		set("itemStats", MISSING, "C_Item stats API missing")
	end
	if hasAll("C_Item.GetItemStatDelta") then
		set("itemStatDelta", UNKNOWN, "delta against the equipped item unverified (S5c)")
	else
		set("itemStatDelta", MISSING, "C_Item.GetItemStatDelta missing")
	end

	if hasAll("C_SpecializationInfo.GetSpecialization", "C_SpecializationInfo.GetSpecializationInfo") or hasAll("GetSpecialization", "GetSpecializationInfo") then
		if Spec.Active() then
			set("specialization", AVAILABLE, "own specialization readable")
		else
			set("specialization", UNKNOWN, "own specialization not readable now (S6a)")
		end
	else
		set("specialization", MISSING, "specialization API missing")
	end

	if hasAll("GuildControlGetNumRanks", "GuildControlGetRankName", "GetGuildInfo") then
		if Guild.InGuild() and Guild.NumRanks() > 0 then
			set("guildRanks", AVAILABLE, "ranks readable")
		else
			set("guildRanks", UNKNOWN, "no guild or no ranks read yet (S7b)")
		end
	else
		set("guildRanks", MISSING, "guild rank API missing")
	end

	if hasAll("C_Calendar.GetNumDayEvents", "C_Calendar.GetDayEvent", "C_Calendar.OpenCalendar") then
		set("calendarRaid", UNKNOWN, "no raid event read yet (S8b)")
	else
		set("calendarRaid", MISSING, "calendar API missing")
	end

	if hasAll("IsInRaid", "GetRaidRosterInfo", "UnitGUID", "GetNumGroupMembers") then
		set("groupRoster", UNKNOWN, "not read inside an instance yet")
	else
		set("groupRoster", MISSING, "group API missing")
	end

	if hasAll("C_ChatInfo.SendAddonMessage", "C_ChatInfo.RegisterAddonMessagePrefix") then
		set("addonMessages", UNKNOWN, "no RAID message delivered yet (S4)")
	else
		set("addonMessages", MISSING, "addon message API missing")
	end
	return f
end

-- Fills Compat.caps ({ [id] = { id, group, state, detail } } and Compat.capOrder) and Compat.features from the client
-- as it is now. Features already refined by a module (Compat:SetFeature) keep their state.
function Compat:Probe()
	self.caps, self.capOrder = {}, {}
	local function set(id, group, state, detail)
		self.caps[id] = { id = id, group = group, state = state, detail = detail }
		self.capOrder[#self.capOrder + 1] = id
	end
	for _, def in ipairs(CAPS) do
		local state, detail = probeOne(def)
		set(def[1], def[2], state, detail)
	end
	-- One entry per restriction kind: restricted while the client says the restriction is active.
	for _, kind in ipairs(self.RESTRICTION_KINDS) do
		local types = Resolve("Enum.AddOnRestrictionType")
		local state, detail = MISSING, nil
		if type(types) == "table" and types[kind] ~= nil then
			local active, value = Chat.RestrictionActive(kind)
			state, detail = active and RESTRICTED or AVAILABLE, value and ("state " .. tostring(value)) or nil
		end
		set("restriction." .. kind, "restriction", state, detail)
	end
	-- A CBOR + Base64 round trip proves the encoding chain works as a whole.
	local encoded = Compat.CBOR.Encode({ a = 1 })
	local text = encoded and Compat.Base64.Encode(encoded)
	local decoded = text and Compat.CBOR.Decode(Compat.Base64.Decode(text) or "")
	set("encoding.roundTrip", "encoding", (type(decoded) == "table" and decoded.a == 1) and AVAILABLE or
		((self.caps["encoding.SerializeCBOR"].state == MISSING or self.caps["encoding.EncodeBase64"].state == MISSING) and MISSING or ERROR))
	local features = probeFeatures()
	self.features = self.features or {}
	for id, value in pairs(features) do
		local old = self.features[id]
		if not (old and old.refined) then self.features[id] = value end
	end
	self.probed = true
	return self.caps
end

function Compat:State(id)
	local c = self.caps and self.caps[id]
	return c and c.state or nil
end

function Compat:IsAvailable(id)
	return self:State(id) == AVAILABLE
end

-- The state of a feature capability ("available", "missing", "unknown") or nil before the first probe.
function Compat:Feature(id)
	local f = self.features and self.features[id]
	return f and f.state or nil
end

-- A module that learned whether a feature works records it here (the probe at the next login keeps it until then).
-- Returns true when the state changed; FEATURE_CHANGED(id, state) goes on the Bus once it exists (M1-4).
function Compat:SetFeature(id, state, detail)
	self.features = self.features or {}
	local old = self.features[id]
	self.features[id] = { state = state, detail = detail, refined = true }
	local changed = not old or old.state ~= state
	if changed and ns.Bus then ns.Bus:Emit("FEATURE_CHANGED", id, state) end
	return changed
end

-- Text lines for /fdcp debug. No player names, no guild names, no item names: the build, the project, each feature and
-- each API. The headings come from the locale; the ids and states are technical words.
function Compat:DebugLines()
	if not self.probed then self:Probe() end
	local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })
	local build = Compat.BuildInfo()
	local lines = {
		L["DEBUG_CLIENT"]:format(build.version, build.build, build.interface, tostring(build.projectID),
			build.isForever and L["DEBUG_FOREVER"] or ""),
		L["DEBUG_FEATURES"],
	}
	for _, id in ipairs(Compat.FEATURES) do
		local f = self.features[id] or { state = "?" }
		lines[#lines + 1] = ("  [%s] %s%s"):format(f.state, id, f.detail and (" - " .. f.detail) or "")
	end
	local counts = { [AVAILABLE] = 0, [MISSING] = 0, [RESTRICTED] = 0, [ERROR] = 0 }
	local rows = {}
	for _, id in ipairs(self.capOrder) do
		local c = self.caps[id]
		counts[c.state] = (counts[c.state] or 0) + 1
		rows[#rows + 1] = ("  [%s] %s%s"):format(c.state, id, c.detail and (" - " .. c.detail) or "")
	end
	lines[#lines + 1] = L["DEBUG_APIS"]:format(counts[AVAILABLE], counts[MISSING], counts[RESTRICTED], counts[ERROR])
	for _, row in ipairs(rows) do lines[#lines + 1] = row end
	return lines
end

local FDCP = ns.addon
if FDCP then
	FDCP.Compat = Compat   -- also reachable from tests

	-- /fdcp debug: re-probes the client (it may have changed since login) and prints the capability table.
	local commands = FDCP.commands
	commands[#commands + 1] = {
		name = "debug", helpKey = "HELP_DEBUG",
		handler = function(self)
			Compat:Probe()
			for _, line in ipairs(Compat:DebugLines()) do self:Print(line) end
			for _, line in ipairs(self:DebugSectionLines()) do self:Print(line) end   -- the lines of the other modules
		end,
	}

	-- The probe at login, once the game has loaded every other addon and the player's data (the client answers more
	-- then than at file load).
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:SetScript("OnEvent", function() Compat:Probe() end)
end
