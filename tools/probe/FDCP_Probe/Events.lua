-- Event recorder: event name, time, encounter state, restriction state, secret flags. Never names or message text.
local ADDON, P = ...

P.recording = true
P.MAX_EVENTS = 500
local watched = {
    "ENCOUNTER_START", "ENCOUNTER_END", "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED", "OPEN_MASTER_LOOT_LIST",
    "UPDATE_MASTER_LOOT_LIST", "CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT", "CHAT_MSG_ADDON", "ADDON_ACTION_BLOCKED",
    "ADDON_ACTION_FORBIDDEN", "ADDON_RESTRICTION_STATE_CHANGED", "GROUP_ROSTER_UPDATE", "ITEM_DATA_LOAD_RESULT",
}

local frame = CreateFrame("Frame")
P.eventFrame = frame

local function RestrictionState()
    if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState and Enum and Enum.AddOnRestrictionType then
        local out = {}
        for name, value in pairs(Enum.AddOnRestrictionType) do
            local ok, state = pcall(C_RestrictedActions.GetAddOnRestrictionState, value)
            out[#out + 1] = name .. "=" .. (ok and tostring(state) or "err")
        end
        table.sort(out)
        return table.concat(out, ";")
    end
    return "n/a"
end

function P.LogEvent(event, ...)
    if not P.recording then return end
    local db = P.DB()
    local secrets = {}
    for i = 1, select("#", ...) do
        if P.IsSecret((select(i, ...))) then secrets[#secrets + 1] = i end
    end
    if #db.events >= P.MAX_EVENTS then table.remove(db.events, 1) end
    db.events[#db.events + 1] = {
        event = event,
        time = GetTime and GetTime() or 0,
        encounter = IsEncounterInProgress and IsEncounterInProgress() or false,
        restriction = RestrictionState(),
        args = select("#", ...),
        secretArgs = table.concat(secrets, ","),
    }
end

frame:SetScript("OnEvent", function(_, event, ...) pcall(P.LogEvent, event, ...) end)
for _, e in ipairs(watched) do pcall(frame.RegisterEvent, frame, e) end
