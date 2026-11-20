-- Mock client, part 10: the guild ranks and the calendar (M1-3).
--
-- Imitates: GuildControlGetNumRanks, GuildControlGetRankName, C_GuildInfo.GetGuildRankOrder, and C_Calendar.{OpenCalendar,
-- GetMonthInfo, GetNumDayEvents, GetDayEvent, OpenEvent, CloseEvent, GetNumInvites, EventGetInvite}, plus the events
-- CALENDAR_UPDATE_EVENT_LIST and CALENDAR_OPEN_EVENT.
-- Dump files: C_Calendar and C_GuildInfo in ../WoW-Addons/docs/api/. GuildControlGetNumRanks / GetRankName are api.json
-- globals; the ranks come from Mock.guild (Tests/mock/50_guild.lua), so the rank table has one source.
--
-- Configure with Mock.calendar (kept across Mock.Reload):
--   Mock.calendar.Set{ month = { month=, year=, numDays=, firstWeekday= }, events = { [day] = { { title=, eventType=,
--       calendarType=, invites = { { name=, inviteStatus=, level=, className=, classFilename= } } } } } }
--   Mock.calendar.opened   true once OpenCalendar was called (reads before that return nothing, as in the client)
local Mock, H = ...
local W = Mock.world

-- Guild ranks: rankOrder is 1-based, the rank index (0 = Guild Master) is Mock.guild.ranks' key.
function GuildControlGetNumRanks()
	local guild = Mock.guild
	if not guild.name then return 0 end
	local n = 0
	for _ in pairs(guild.ranks) do n = n + 1 end
	return n
end
function GuildControlGetRankName(rankOrder)
	local guild = Mock.guild
	if not guild.name then return nil end
	return guild.ranks[rankOrder - 1]
end
function C_GuildInfo.GetGuildRankOrder(guid)
	local guild = Mock.guild
	if not guild.name then return nil end
	for _, m in ipairs(Mock.guild.Roster()) do
		if m.guid == guid then return m.rank + 1 end
	end
	return nil
end

W.calendar = W.calendar or { opened = false, month = { month = 11, year = 2026, numDays = 30, firstWeekday = 1 }, events = {},
	openEvent = nil }
local calendar = W.calendar
Mock.calendar = calendar

function calendar.Set(config)
	for k, v in pairs(config) do calendar[k] = v end
end

local TIME = { year = 2026, month = 11, monthDay = 20, hour = 20, minute = 0 }

C_Calendar = C_Calendar or {}
function C_Calendar.OpenCalendar()
	calendar.opened = true
	Mock.Fire("CALENDAR_UPDATE_EVENT_LIST")
end
function C_Calendar.GetMonthInfo(offset)
	if not calendar.opened then return nil end
	return CopyTable(calendar.month)
end
function C_Calendar.GetNumDayEvents(offset, day)
	if not calendar.opened then return 0 end
	return calendar.events[day] and #calendar.events[day] or 0
end
function C_Calendar.GetDayEvent(offset, day, index)
	local list = calendar.opened and calendar.events[day]
	local e = list and list[index]
	if not e then return nil end
	return { eventID = e.eventID or (day * 100 + index), title = e.title, isCustomTitle = true, startTime = CopyTable(TIME),
		endTime = CopyTable(TIME), calendarType = e.calendarType or "GUILD_EVENT", sequenceType = "", eventType = e.eventType or 0,
		inviteStatus = 0, modStatus = "" }
end
function C_Calendar.OpenEvent(offset, day, index)
	local list = calendar.opened and calendar.events[day]
	local e = list and list[index]
	calendar.openEvent = e
	if e then Mock.Fire("CALENDAR_OPEN_EVENT", "GUILD_EVENT") end
	return e ~= nil
end
function C_Calendar.CloseEvent() calendar.openEvent = nil end
function C_Calendar.GetNumInvites() return calendar.openEvent and #(calendar.openEvent.invites or {}) or 0 end
function C_Calendar.EventGetInvite(index)
	local e = calendar.openEvent
	local i = e and e.invites and e.invites[index]
	if not i then return nil end
	return { name = i.name, level = i.level or 60, className = i.className or "Warrior", classFilename = i.classFilename or "WARRIOR",
		inviteStatus = i.inviteStatus or 1, modStatus = "", inviteGuid = i.guid }
end
