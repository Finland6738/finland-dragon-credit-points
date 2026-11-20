-- Registry of checks. M0-1 ships the baseline ones; M0-2 .. M0-6 add the spike areas (S1 .. S8).
local ADDON, P = ...

local function Has(path)
    local cur = _G
    for part in string.gmatch(path, "[^%.]+") do
        if type(cur) ~= "table" then return false end
        cur = cur[part]
        if cur == nil then return false end
    end
    return true
end
P.Has = Has

P.Register("B1", "base", "Client build, interface and locale", function()
    local _, _, _, interface = GetBuildInfo()
    return "info", "build=" .. P.Build() .. " interface=" .. tostring(interface) .. " locale=" .. tostring(GetLocale())
end)

P.Register("B2", "base", "Guarded APIs exist (secret values, restrictions, chat lockdown)", function()
    local names = { "issecretvalue", "C_RestrictedActions", "C_ChatInfo.RegisterAddonMessagePrefix",
        "C_ChatInfo.InChatMessagingLockdown", "C_ChatInfo.SendAddonMessage", "C_EncodingUtil", "C_Item.GetItemInfo",
        "C_PartyInfo.GetLootMethod", "C_Loot", "C_Calendar", "C_GuildInfo", "IsEncounterInProgress" }
    local missing = {}
    for _, n in ipairs(names) do if not Has(n) then missing[#missing + 1] = n end end
    if #missing == 0 then return "ok", "all " .. #names .. " present" end
    return "partial", "missing: " .. table.concat(missing, ",")
end)

P.Register("B3", "base", "Group and instance context (counts only)", function()
    local inInstance, instanceType = IsInInstance()
    return "info", "instance=" .. tostring(inInstance) .. " type=" .. tostring(instanceType)
        .. " raid=" .. tostring(IsInRaid()) .. " members=" .. tostring(GetNumGroupMembers())
        .. " encounter=" .. tostring(IsEncounterInProgress and IsEncounterInProgress())
end)

P.Register("B4", "base", "Test addon message prefix registers", function()
    if not Has("C_ChatInfo.RegisterAddonMessagePrefix") then return "fail", "API missing" end
    local res = C_ChatInfo.RegisterAddonMessagePrefix(P.PREFIX)
    return "info", "RegisterAddonMessagePrefix(" .. P.PREFIX .. ")=" .. tostring(res)
end)
