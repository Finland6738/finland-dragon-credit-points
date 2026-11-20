-- S5 / S6 (M0-5): items, stats, item levels and specializations. Item links and names are never stored:
-- only class ids, item levels, stat keys and numbers.
local ADDON, P = ...

P.items = { last = nil }

-- Resolves an API by name: C_Item.<name> first, then the global of the same name.
local function Api(name)
    if C_Item and type(C_Item[name]) == "function" then return C_Item[name] end
    if type(_G[name]) == "function" then return _G[name] end
    return nil
end
P.ItemApi = Api

local function Call(name, ...)
    local f = Api(name)
    if not f then return false, "missing" end
    local res = { pcall(f, ...) }
    if not res[1] then return false, P.IsSecret(res[2]) and "secret error" or tostring(res[2]) end
    table.remove(res, 1)
    return true, res
end

-- Equipped item link in the slot matching an equip location (first match for rings and trinkets).
local SLOTS = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_BODY = 4, INVTYPE_CHEST = 5, INVTYPE_ROBE = 5,
    INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11,
    INVTYPE_TRINKET = 13, INVTYPE_CLOAK = 15, INVTYPE_WEAPON = 16, INVTYPE_2HWEAPON = 16, INVTYPE_WEAPONMAINHAND = 16,
    INVTYPE_SHIELD = 17, INVTYPE_WEAPONOFFHAND = 17, INVTYPE_HOLDABLE = 17, INVTYPE_RANGED = 18, INVTYPE_RANGEDRIGHT = 18,
}
local function EquippedLink(equipLoc)
    local slot = SLOTS[equipLoc]
    if not slot or not GetInventoryItemLink then return nil end
    local ok, link = pcall(GetInventoryItemLink, "player", slot)
    if ok and type(link) == "string" and not P.IsSecret(link) then return link end
    return nil
end

local function StatsString(t)
    if type(t) ~= "table" then return "none" end
    local parts = {}
    for k, v in pairs(t) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ",") or "empty"
end

-- Numbers that appear in "+123 Stat" style tooltip lines, from C_TooltipInfo. Returns set, line count.
local function TooltipNumbers(link)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil, "C_TooltipInfo.GetHyperlink missing" end
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
    if not ok or type(data) ~= "table" then return nil, "no tooltip data" end
    local set, lines, secret = {}, 0, 0
    for _, line in ipairs(data.lines or {}) do
        lines = lines + 1
        local text = line.leftText
        if P.IsSecret(text) then secret = secret + 1
        elseif type(text) == "string" then
            for n in text:gmatch("%+?([%d,]+)%s") do
                local v = tonumber((n:gsub(",", "")))
                if v then set[v] = true end
            end
        end
    end
    return set, lines, secret
end

-- Checks one item link; the result is kept in P.items.last for S5b and S5c.
function P.ProbeItem(link)
    local r = { }
    local ok, res = Call("GetItemInfoInstant", link)
    if ok and res[1] ~= nil then
        r.instant = string.format("id=%s class=%s sub=%s equipLoc=%s", tostring(res[1]), tostring(res[4]),
            tostring(res[5]), tostring(res[3]))
        r.equipLoc = res[3]
        r.classID = res[4]
    else
        r.instant = "fail:" .. tostring(res)
    end
    ok, res = Call("GetItemInfo", link)
    r.cached = ok and res[1] ~= nil
    r.info = ok and res[1] ~= nil and string.format("level=%s minLevel=%s bindType=%s", tostring(res[4]), tostring(res[5]),
        tostring(res[14])) or ("miss(" .. tostring(ok and "nil" or res) .. ")")
    ok, res = Call("GetDetailedItemLevelInfo", link)
    r.ilvl = ok and string.format("effective=%s preview=%s base=%s", tostring(res[1]), tostring(res[2]), tostring(res[3]))
        or ("fail:" .. tostring(res))
    ok, res = Call("GetItemStats", link)
    r.stats = ok and StatsString(res[1]) or ("fail:" .. tostring(res))
    r.statTable = ok and type(res[1]) == "table" and res[1] or nil
    local eq = Api("IsEquippableItem")
    r.equippable = eq and select(2, pcall(eq, link)) or "missing"
    local equipped = EquippedLink(r.equipLoc)
    r.hasEquipped = equipped ~= nil
    if equipped then
        ok, res = Call("GetItemStatDelta", link, equipped)
        r.delta = ok and StatsString(res[1]) or ("fail:" .. tostring(res))
    else
        r.delta = "no equipped piece in the slot"
    end
    local spec = Api("DoesItemContainSpec")
    if spec and r.classID then
        local parts = {}
        for i = 1, (GetNumSpecializations and GetNumSpecializations() or 4) do
            local sid = GetSpecializationInfo and GetSpecializationInfo(i)
            local o, v = pcall(spec, link, select(3, UnitClass("player")), sid)
            parts[#parts + 1] = tostring(o and v)
        end
        r.containSpec = table.concat(parts, ",")
    else
        r.containSpec = "missing"
    end
    local si = Api("GetItemSpecInfo")
    if si then
        local o, v = pcall(si, link)
        r.specInfo = o and (type(v) == "table" and ("table(" .. #v .. ")") or tostring(v)) or ("fail:" .. tostring(v))
    else
        r.specInfo = "missing"
    end
    -- tooltip comparison (contextual bonuses: raid vs outside)
    local nums, lines, secret = TooltipNumbers(link)
    if nums and r.statTable then
        local match, miss = 0, 0
        for _, v in pairs(r.statTable) do
            if nums[v] then match = match + 1 else miss = miss + 1 end
        end
        r.tooltip = string.format("lines=%d secret=%d statsInTooltip=%d statsNotInTooltip=%d", lines, secret or 0, match, miss)
        r.tooltipMismatch = miss
    else
        r.tooltip = tostring(lines)
    end
    local _, itype = IsInInstance()
    r.context = (IsInInstance() and ("instance:" .. tostring(itype))) or "outside"
    P.items.last = r
    local db = P.DB()
    db.items = db.items or {}
    db.items[#db.items + 1] = { context = r.context, instant = r.instant, ilvl = r.ilvl, stats = r.stats,
        tooltip = r.tooltip, delta = r.delta }
    if #db.items > 40 then table.remove(db.items, 1) end
    return r
end

local function Last() return P.items.last end

P.Register("S5a", "S5", "Item APIs exist", function()
    local names = { "GetItemInfoInstant", "GetItemInfo", "GetDetailedItemLevelInfo", "GetItemStats", "GetItemStatDelta",
        "IsEquippableItem", "DoesItemContainSpec", "GetItemSpecInfo" }
    local missing = {}
    for _, n in ipairs(names) do if not Api(n) then missing[#missing + 1] = n end end
    local extra = { P.Has("C_TooltipInfo.GetHyperlink") and "" or "C_TooltipInfo.GetHyperlink",
        _G.ITEM_DATA_LOAD_RESULT ~= nil and "" or nil }
    for _, e in ipairs(extra) do if e ~= "" then missing[#missing + 1] = e end end
    if #missing == 0 then return "ok", "all present" end
    return "partial", "missing: " .. table.concat(missing, ",")
end)

P.Register("S5b", "S5", "Last item: instant info, cache, item levels (use /fdcpp item <link>)", function()
    local r = Last()
    if not r then return "info", "not run: /fdcpp item <item link>" end
    return "info", "context=" .. r.context .. " instant[" .. r.instant .. "] cached=" .. tostring(r.cached)
        .. " info[" .. r.info .. "] ilvl[" .. r.ilvl .. "] equippable=" .. tostring(r.equippable)
        .. " dataLoadEvents=" .. tostring(P.items.loadEvents or 0)
end)

P.Register("S5c", "S5", "Last item: stats, delta vs equipped, spec flags, tooltip comparison", function()
    local r = Last()
    if not r then return "info", "not run: /fdcpp item <item link>" end
    local res = (r.tooltipMismatch == nil and "info") or (r.tooltipMismatch == 0 and "ok" or "partial")
    return res, "context=" .. r.context .. " stats[" .. r.stats .. "] delta[" .. r.delta .. "] containSpec["
        .. r.containSpec .. "] specInfo=" .. r.specInfo .. " tooltip[" .. r.tooltip .. "]"
end)

P.Register("S6a", "S6", "Specialization APIs and the player's specializations", function()
    local info = C_SpecializationInfo
    local getSpec = (info and info.GetSpecialization) or GetSpecialization
    local getInfo = (info and info.GetSpecializationInfo) or GetSpecializationInfo
    local num = (info and info.GetNumSpecializations) or GetNumSpecializations
    if not getSpec or not getInfo then
        return "fail", "missing GetSpecialization=" .. tostring(getSpec ~= nil) .. " GetSpecializationInfo=" .. tostring(getInfo ~= nil)
    end
    local n = num and select(2, pcall(num)) or "?"
    local ok, cur = pcall(getSpec)
    local parts = {}
    for i = 1, tonumber(n) or 4 do
        local o, id, _, _, _, role = pcall(getInfo, i)
        if o and id then parts[#parts + 1] = i .. ":id=" .. tostring(id) .. ",role=" .. tostring(role) end
    end
    return (#parts > 0) and "ok" or "partial", "count=" .. tostring(n) .. " current=" .. tostring(ok and cur) .. " "
        .. table.concat(parts, " ")
end)

P.Register("S6b", "S6", "Other spec APIs (GetInspectSpecialization, GetSpecializationRole)", function()
    local names = { "GetInspectSpecialization", "GetSpecializationRole", "GetSpecializationInfoByID", "GetNumSpecializationsForClassID" }
    local parts = {}
    for _, n in ipairs(names) do
        parts[#parts + 1] = n .. "=" .. tostring((C_SpecializationInfo and C_SpecializationInfo[n] ~= nil) or _G[n] ~= nil)
    end
    return "info", table.concat(parts, " ")
end)

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
    if event == "ITEM_DATA_LOAD_RESULT" then P.items.loadEvents = (P.items.loadEvents or 0) + 1 end
end)
pcall(frame.RegisterEvent, frame, "ITEM_DATA_LOAD_RESULT")
