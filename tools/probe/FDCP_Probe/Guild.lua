-- S7 / S8 (M0-6): guild ranks, calendar raid events, locale and chat sending from a click.
-- Only counts, rank indexes and shapes are stored: never player, guild, rank or event names, never note texts.
local ADDON, P = ...

P.guild = { rosterAt = nil, rosterMs = nil, rosterEvents = 0 }

local function Safe(f, ...)
    if type(f) ~= "function" then return false, "missing" end
    local res = { pcall(f, ...) }
    if not res[1] then return false, P.IsSecret(res[2]) and "secret error" or tostring(res[2]) end
    table.remove(res, 1)
    return true, res
end

local function GuildApi(name)
    if C_GuildInfo and type(C_GuildInfo[name]) == "function" then return C_GuildInfo[name] end
    if type(_G[name]) == "function" then return _G[name] end
    return nil
end

local function Flag(v)
    if P.IsSecret(v) then return "secret" end
    return tostring(v)
end

P.Register("S7a", "S7", "Guild APIs exist", function()
    local names = { "IsInGuild", "IsGuildLeader", "GetGuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo", "GuildRoster",
        "GuildControlGetNumRanks", "GuildControlGetRankName", "IsGuildOfficer", "CanEditOfficerNote", "CanViewOfficerNote",
        "GetGuildRankOrder" }
    local missing, present = {}, {}
    for _, n in ipairs(names) do
        if GuildApi(n) then present[#present + 1] = n else missing[#missing + 1] = n end
    end
    local ev = _G.GUILD_ROSTER_UPDATE ~= nil
    local res = (#missing == 0) and "ok" or "partial"
    return res, "missing=" .. (#missing > 0 and table.concat(missing, ",") or "none")
        .. " C_GuildInfo.IsGuildOfficer=" .. tostring(P.Has("C_GuildInfo.IsGuildOfficer"))
        .. " C_GuildInfo.GuildRoster=" .. tostring(P.Has("C_GuildInfo.GuildRoster"))
end)

-- Own rank: role of this character (GM, officer or member) is reported by the owner in the notes; the probe records
-- the numbers: rank index (0 = guild master), rank count, the officer flags and the size of the loaded roster.
P.Register("S7b", "S7", "Own rank, rank count, officer flags (run as GM, officer and member)", function()
    local inGuild = GuildApi("IsInGuild")
    local ok, g = Safe(inGuild)
    if not ok or not g[1] then return "info", "not in a guild (IsInGuild=" .. tostring(ok and g[1] or g) .. ")" end
    local parts = {}
    local ok2, info = Safe(GuildApi("GetGuildInfo"), "player")
    local rankIndex = ok2 and info[3] or nil
    parts[#parts + 1] = "rankIndex=" .. Flag(rankIndex)
    local okN, n = Safe(GuildApi("GuildControlGetNumRanks"))
    parts[#parts + 1] = "ranks=" .. (okN and Flag(n[1]) or ("fail:" .. tostring(n)))
    local okR, rn = Safe(GuildApi("GuildControlGetRankName"), 1)
    parts[#parts + 1] = "rank1Name=" .. (okR and P.Shape(rn[1]) or ("fail:" .. tostring(rn)))
    for _, name in ipairs({ "IsGuildLeader", "IsGuildOfficer", "CanEditOfficerNote", "CanViewOfficerNote" }) do
        local o, v = Safe(GuildApi(name))
        parts[#parts + 1] = name .. "=" .. (o and Flag(v[1]) or ("fail:" .. tostring(v)))
    end
    local oi, vi = Safe(P.Has("C_GuildInfo.IsGuildOfficer") and C_GuildInfo.IsGuildOfficer or nil)
    parts[#parts + 1] = "C_GuildInfo.IsGuildOfficer=" .. (oi and Flag(vi[1]) or "missing")
    local okM, m = Safe(GuildApi("GetNumGuildMembers"))
    parts[#parts + 1] = "members=" .. (okM and (Flag(m[1]) .. "/online=" .. Flag(m[2])) or "fail")
    -- own row in the roster: rank index and the rank fields, never the name
    local rowRank = "none"
    if okM and type(m[1]) == "number" and not P.IsSecret(m[1]) then
        local me = UnitName and UnitName("player")
        for i = 1, m[1] do
            local o, r = Safe(GuildApi("GetGuildRosterInfo"), i)
            if o and r[1] and not P.IsSecret(r[1]) and me and (r[1] == me or tostring(r[1]):match("^([^%-]+)") == me) then
                rowRank = "row=" .. i .. " rankName=" .. P.Shape(r[2]) .. " rankIndex=" .. Flag(r[3]) .. " level=" .. Flag(r[4])
                break
            end
        end
    end
    parts[#parts + 1] = "ownRow[" .. rowRank .. "]"
    return "info", table.concat(parts, " ")
end)

-- Roster load: how long GuildRoster() takes until GUILD_ROSTER_UPDATE arrives.
function P.GuildRosterRequest()
    local f = GuildApi("GuildRoster")
    if not f then return P.Record("S7c", "fail", "GuildRoster missing") end
    P.guild.rosterAt = GetTime and GetTime() or 0
    P.guild.rosterMs = nil
    local ok, err = Safe(f)
    if not ok then return P.Record("S7c", "fail", "GuildRoster call failed: " .. tostring(err)) end
    return P.Record("S7c", "info", "requested, wait for GUILD_ROSTER_UPDATE and run S7c again")
end

P.Register("S7c", "S7", "Roster load timing (/fdcpp roster, then run S7c)", function()
    local g = P.guild
    if not g.rosterAt then return "info", "not run: /fdcpp roster" end
    if not g.rosterMs then return "partial", "no GUILD_ROSTER_UPDATE yet, events=" .. g.rosterEvents end
    local okM, m = Safe(GuildApi("GetNumGuildMembers"))
    return "ok", string.format("first update after %.0f ms, updates=%d members=%s", g.rosterMs, g.rosterEvents,
        okM and Flag(m[1]) or "?")
end)

-- S8a: locale.
P.Register("S8a", "S8", "GetLocale and the localized globals the addon will use", function()
    local ok, loc = Safe(GetLocale)
    local count = 0
    for _, g in ipairs({ "RANDOM_ROLL_RESULT", "LOOT_ITEM", "LOOT_ITEM_SELF", "GUILD", "RAID" }) do
        if type(_G[g]) == "string" then count = count + 1 end
    end
    return ok and "info" or "fail", "locale=" .. (ok and tostring(loc[1]) or tostring(loc)) .. " globalsPresent=" .. count .. "/5"
end)

-- S8b: calendar raid events. Counts only; titles are never read into the results.
P.Register("S8b", "S8", "Calendar: raid events readable, attendees count", function()
    local C = _G.C_Calendar
    if not C then return "fail", "C_Calendar missing" end
    local parts = {}
    for _, n in ipairs({ "OpenCalendar", "GetNumDayEvents", "GetDayEvent", "GetEventIndex", "GetNumInvites", "EventGetInvite",
        "GetMonthInfo", "GetDate" }) do
        parts[#parts + 1] = n .. "=" .. tostring(type(C[n]) == "function")
    end
    Safe(C.OpenCalendar)
    local ok, mi = Safe(C.GetMonthInfo)
    local month, today = ok and mi[1] and mi[1].month, nil
    local okD, d = Safe(C.GetDate)
    today = okD and d[1] and d[1].monthDay or nil
    local summary = { "monthInfo=" .. tostring(ok and type(mi[1])) }
    if month and today and type(C.GetNumDayEvents) == "function" then
        local oN, nEv = Safe(C.GetNumDayEvents, 0, today)
        local nEvents = oN and tonumber(nEv[1]) or 0
        local raid, withInvites = 0, 0
        for i = 1, nEvents do
            local oE, ev = Safe(C.GetDayEvent, 0, today, i)
            local e = oE and ev[1]
            if type(e) == "table" and not P.IsSecret(e.calendarType) then
                local isRaid = e.calendarType == "GUILD_EVENT" or e.calendarType == "PLAYER" or e.eventType == 0
                if isRaid then raid = raid + 1 end
                if C.OpenEvent and C.GetNumInvites then
                    local oo = Safe(C.OpenEvent, 0, today, i)
                    local oI, nI = Safe(C.GetNumInvites)
                    if oo and oI and tonumber(nI[1]) and tonumber(nI[1]) > 0 then withInvites = withInvites + 1 end
                end
            end
        end
        summary[#summary + 1] = "todayEvents=" .. nEvents .. " eventLikeRaid=" .. raid .. " withAttendees=" .. withInvites
    else
        summary[#summary + 1] = "today not readable"
    end
    return "info", table.concat(parts, " ") .. " " .. table.concat(summary, " ")
end)

-- S8c: SendChatMessage to RAID from the addon's own click vs from a slash command (no hardware event).
local function SendRaid(from)
    if type(SendChatMessage) ~= "function" and not (C_ChatInfo and C_ChatInfo.SendChatMessage) then
        return "fail", "SendChatMessage missing"
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local channel = IsInRaid and IsInRaid() and "RAID" or "PARTY"
    local ok, err = pcall(send, "FDCPP test (" .. from .. ")", channel)
    local blocked = P.guild.blocked or 0
    local entry = { from = from, channel = channel, ok = ok, err = ok and "" or (P.IsSecret(err) and "secret error" or tostring(err)),
        restricted = tostring(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and select(2, pcall(C_ChatInfo.InChatMessagingLockdown))) }
    P.guild.chat = P.guild.chat or {}
    P.guild.chat[from] = entry
    local db = P.DB()
    db.chat = db.chat or {}
    db.chat[from] = entry
    return ok and "info" or "fail", string.format("%s -> %s ok=%s lockdown=%s err=%s", from, channel, tostring(ok), entry.restricted, entry.err)
end

function P.ChatFromCommand()
    local r, d = SendRaid("command")
    return P.Record("S8c", r, d .. " (no hardware event; compare with the click)")
end

function P.ChatButton()
    if not P.guild.btn then
        local f = CreateFrame("Frame", "FDCPProbeChat", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(220, 90)
        f:SetPoint("CENTER", 0, 200)
        f.TitleText:SetText("FDCP Probe: chat")
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(160, 26)
        b:SetPoint("CENTER", 0, -10)
        b:SetText("Send to RAID")
        b:SetScript("OnClick", function()
            local r, d = SendRaid("click")
            P.Record("S8c", r, d)
            P.Print("S8c: " .. r .. " " .. d)
        end)
        P.guild.btn = f
    end
    P.guild.btn:Show()
end

P.Register("S8c", "S8", "Chat to RAID from a click vs a slash command (/fdcpp chat, /fdcpp chatbtn)", function()
    local c = P.guild.chat
    if not c then return "info", "not run: /fdcpp chat (command) and /fdcpp chatbtn then click" end
    local parts = {}
    for _, k in ipairs({ "command", "click" }) do
        local e = c[k]
        parts[#parts + 1] = k .. "=" .. (e and (tostring(e.ok) .. (e.ok and "" or (":" .. e.err))) or "not run")
    end
    return "info", table.concat(parts, " ")
end)

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
    if event == "GUILD_ROSTER_UPDATE" then
        local g = P.guild
        g.rosterEvents = g.rosterEvents + 1
        if g.rosterAt and not g.rosterMs and GetTime then g.rosterMs = (GetTime() - g.rosterAt) * 1000 end
    end
end)
pcall(frame.RegisterEvent, frame, "GUILD_ROSTER_UPDATE")
