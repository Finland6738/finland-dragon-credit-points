-- Calendar: the official raid event of the game's calendar and who signed up to it (docs/ANALISI.md §2, §6, M3-4). Lua 5.1.
-- Everything goes through Core/Compat.lua (Compat.Calendar: C_Calendar.OpenCalendar, GetMonthInfo, GetNumDayEvents,
-- GetDayEvent, OpenEvent, CloseEvent, GetNumInvites, EventGetInvite); the names were checked against the Forever API dump
-- (C_Calendar in docs/api) and the event CALENDAR_UPDATE_EVENT_LIST. The addon only **reads** the calendar: it never
-- creates, edits or answers an event.
--
-- What it gives:
--   Calendar.Request()              asks the client to load the calendar (once is enough; the default UI does the same).
--   Calendar.RaidEvents(day)        the raid events of a realm day (a YYYYMMDD number): { { eventID, title, calendarType,
--                                   day, offset, index, guild } }, the guild's own events first.
--   Calendar.FindRaidEvent(day)     the one the night is linked to: the first of RaidEvents, or nil when there is none.
--   Calendar.Signups(event)         { [Name-Realm] = "yes" | "maybe" | "no" } for the invites of an event, with a count;
--                                   members who have not answered are not in it (they are still candidates).
--   "CALENDAR_LOADED"               a bus event on CALENDAR_UPDATE_EVENT_LIST (the calendar has data).
-- [verify S8b] in the real client: the event type of a raid (0 here, as in the retail enum), the statuses of an invite and
-- whether the guild's events are loaded without the calendar window having been opened. Until then the night opens
-- without a link and the bench proposal without sign-ups, which is a normal, supported case.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Calendar = {}
ns.Calendar, ns.modules.Calendar = Calendar, Calendar

local type, ipairs = type, ipairs
local floor = math.floor

local function C() return ns.Compat end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

-- [verify S8b] CalendarEventType: Raid = 0 in the retail enum.
Calendar.EVENT_RAID = 0
-- The kinds of event a night can be linked to: the guild's own, or one a player or a community created. Holidays,
-- lockouts and announcements are never a raid night.
Calendar.LINKABLE = { GUILD_EVENT = 1, PLAYER = 2, COMMUNITY_EVENT = 3 }
-- [verify S8b] CalendarStatus (retail): 0 invited, 1 available, 2 declined, 3 confirmed, 4 out, 5 standby, 6 signed up,
-- 7 not signed up, 8 tentative. What the rotation needs is three answers.
Calendar.STATUS = { [1] = "yes", [3] = "yes", [6] = "yes", [5] = "maybe", [8] = "maybe", [2] = "no", [4] = "no" }
Calendar.MAX_INVITES = 400

-- The months from the one the calendar shows to the one of `day` (YYYYMMDD); `shown` = { month, year }. 0 = the same month.
function Calendar.MonthOffset(shown, day)
	if type(shown) ~= "table" or type(shown.month) ~= "number" or type(shown.year) ~= "number" or type(day) ~= "number" then
		return nil
	end
	local year, month = floor(day / 10000), floor(day / 100) % 100
	if month < 1 or month > 12 then return nil end
	return (year * 12 + month) - (shown.year * 12 + shown.month)
end

Calendar.requested = false

-- Asks the client to load the calendar. Returns the call state ("available", "missing", ...).
function Calendar.Request()
	Calendar.requested = true
	return C().Calendar.Open()
end

-- The raid events of a realm day (a YYYYMMDD number), the guild's first: [{ eventID, title, calendarType, day, offset, index,
-- guild }]. Empty when the calendar is not loaded or the client says nothing; a title is only kept to show it, never stored.
function Calendar.RaidEvents(day)
	local out = {}
	if type(day) ~= "number" then return out end
	local offset = Calendar.MonthOffset(C().Calendar.MonthInfo(0), day)
	if not offset then return out end
	local dayOfMonth = day % 100
	for _, e in ipairs(C().Calendar.DayEvents(offset, dayOfMonth)) do
		if e.eventType == Calendar.EVENT_RAID and Calendar.LINKABLE[e.calendarType or ""] and type(e.eventID) == "number"
			and e.eventID > 0 and e.eventID == floor(e.eventID) then
			out[#out + 1] = { eventID = e.eventID, title = e.title, calendarType = e.calendarType, day = day, offset = offset,
				index = e.index, guild = e.calendarType == "GUILD_EVENT" }
		end
	end
	-- the guild's own events first, the others after, each group in the calendar's order (a stable partition)
	local guild = {}
	for _, e in ipairs(out) do if e.guild then guild[#guild + 1] = e end end
	for _, e in ipairs(out) do if not e.guild then guild[#guild + 1] = e end end
	return guild
end

-- The raid event a night of `day` is linked to: the first of RaidEvents, or nil (no event, or the calendar is not loaded).
-- A second result tells how many raid events the day has, so the officer can see when a link was a choice.
function Calendar.FindRaidEvent(day)
	local list = Calendar.RaidEvents(day)
	return list[1], #list
end

-- The sign-ups of an event of RaidEvents: { [Name-Realm] = "yes" | "maybe" | "no" }, and the number of invites read. The event
-- is opened in the client for the reading and closed again. Returns nil when the client does not open it.
function Calendar.Signups(event)
	if type(event) ~= "table" then return nil end
	local Cal = C().Calendar
	if not Cal.OpenEvent(event.offset, event.day % 100, event.index) then return nil end
	local out, read = {}, 0
	local n = Cal.NumInvites()
	if n > Calendar.MAX_INVITES then n = Calendar.MAX_INVITES end
	for i = 1, n do
		local invite = Cal.Invite(i)
		if invite then
			read = read + 1
			local full = ns.GuildRanks and ns.GuildRanks.FullName(invite.name) or invite.name
			local answer = Calendar.STATUS[invite.inviteStatus]
			if full and answer then out[full] = answer end
		end
	end
	Cal.CloseEvent()
	return out, read
end

function Calendar.OnEvent(_, event)
	if event == "CALENDAR_UPDATE_EVENT_LIST" then
		emit("CALENDAR_LOADED")
	elseif not Calendar.requested then   -- PLAYER_ENTERING_WORLD: the first time, load it
		Calendar.Request()
	end
end

if ns.addon and CreateFrame then
	ns.addon.Calendar = Calendar   -- also reachable from tests
	local frame = CreateFrame("Frame")
	for _, event in ipairs({ "CALENDAR_UPDATE_EVENT_LIST", "PLAYER_ENTERING_WORLD" }) do
		frame:RegisterEvent(event)
	end
	frame:SetScript("OnEvent", Calendar.OnEvent)
end
