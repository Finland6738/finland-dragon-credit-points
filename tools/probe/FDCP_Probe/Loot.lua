-- S1 / S2 (M0-2): master loot and the loot window. Shapes and counts only: never item or player names, never GUIDs.
local ADDON, P = ...

P.loot = { snapshot = nil, give = nil, blocked = {} }

local function Call(fn, ...)
    if type(fn) ~= "function" then return false, "missing" end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return false, "error" end
    return true, a, b, c, d
end

-- Describes a GUID by shape: type, number of segments and (for creatures) the npc id, which maps a source to a boss.
-- The GUID itself is never stored.
local function GuidShape(guid)
    if P.IsSecret(guid) then return "secret" end
    if type(guid) ~= "string" then return type(guid) end
    local kind, n, npc = string.match(guid, "^(%a+)"), 1, nil
    for _ in string.gmatch(guid, "-") do n = n + 1 end
    if kind == "Creature" or kind == "Vehicle" then npc = select(6, strsplit("-", guid)) end
    return tostring(kind) .. "/" .. n .. (npc and ("/npc" .. tostring(npc)) or "")
end

local function LootMethod()
    if P.Has("C_PartyInfo.GetLootMethod") then
        local ok, m = Call(C_PartyInfo.GetLootMethod)
        if ok then
            local name = "?"
            if Enum and Enum.LootMethod then
                for k, v in pairs(Enum.LootMethod) do if v == m then name = k end end
            end
            return tostring(m) .. "(" .. name .. ")"
        end
    end
    return "n/a"
end

-- S1: presence and behaviour of the loot method APIs. Read-only; /fdcpp setml changes the method.
P.Register("S1a", "S1", "Loot method APIs and master looter state", function()
    local names = { "C_PartyInfo.GetLootMethod", "C_PartyInfo.SetLootMethod", "C_Loot.IsLegacyLootModeEnabled",
        "IsMasterLooter", "GetLootThreshold", "GetMasterLootCandidate", "GiveMasterLoot", "GetLootMethod",
        "SetLootMethod", "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo", "GetLootSourceInfo" }
    local present, missing = {}, {}
    for _, n in ipairs(names) do
        if P.Has(n) then present[#present + 1] = n else missing[#missing + 1] = n end
    end
    local parts = { "missing=" .. (#missing > 0 and table.concat(missing, ",") or "none") }
    parts[#parts + 1] = "method=" .. LootMethod()
    local ok, legacy = Call(P.Has("C_Loot.IsLegacyLootModeEnabled") and C_Loot.IsLegacyLootModeEnabled)
    parts[#parts + 1] = "legacyLoot=" .. (ok and tostring(legacy) or "n/a")
    local okm, ml = Call(IsMasterLooter)
    parts[#parts + 1] = "isMasterLooter=" .. (okm and tostring(ml) or "n/a")
    local okt, thr = Call(GetLootThreshold)
    parts[#parts + 1] = "threshold=" .. (okt and tostring(thr) or "n/a")
    parts[#parts + 1] = "raid=" .. tostring(IsInRaid()) .. " members=" .. tostring(GetNumGroupMembers())
        .. " leader=" .. tostring(UnitIsGroupLeader and UnitIsGroupLeader("player"))
    local ins, itype = IsInInstance()
    parts[#parts + 1] = "instance=" .. tostring(ins) .. "/" .. tostring(itype)
    local okd, diff = Call(GetRaidDifficultyID)
    parts[#parts + 1] = "raidDifficulty=" .. (okd and tostring(diff) or "n/a")
    return (#missing == 0) and "ok" or "partial", table.concat(parts, " ")
end)

-- S1: attempts to set master loot with the player as master looter. Only through /fdcpp setml (changes the group).
function P.SetMasterLoot()
    if not (P.Has("C_PartyInfo.SetLootMethod") and Enum and Enum.LootMethod and Enum.LootMethod.Master) then
        return P.Record("S1b", "fail", "C_PartyInfo.SetLootMethod or Enum.LootMethod.Master missing")
    end
    local before = LootMethod()
    local ok, err = pcall(C_PartyInfo.SetLootMethod, Enum.LootMethod.Master, "player")
    local after = LootMethod()
    local result = (ok and string.find(after, "Master", 1, true)) and "ok" or (ok and "partial" or "fail")
    local d = "before=" .. before .. " call=" .. (ok and "ok" or "error") .. " after=" .. after
        .. " raid=" .. tostring(IsInRaid()) .. " members=" .. tostring(GetNumGroupMembers())
        .. " raidDifficulty=" .. tostring(GetRaidDifficultyID and GetRaidDifficultyID())
        .. " (the method may change after a short delay: run /fdcpp run S1a again)"
    return P.Record("S1b", result, d)
end
P.Register("S1b", "S1", "Set master loot (run with /fdcpp setml in a raid; changes the group)", function()
    local r = P.DB().results["S1b"]
    if r then return r.result, r.details end
    return "info", "not run: use /fdcpp setml as raid leader (10, 20 and 40, Normal and Veteran)"
end)

-- S2: the loot window. Captured on LOOT_OPENED (shapes only) and described by S2a.
local function Capture()
    local s = { time = GetTime and GetTime() or 0, slots = {}, candidates = 0, method = LootMethod() }
    local ok, n = Call(GetNumLootItems)
    s.num = ok and n or -1
    for slot = 1, (type(s.num) == "number" and s.num or 0) do
        local e = { slot = slot }
        local okl, link = Call(GetLootSlotLink, slot)
        e.link = okl and P.Shape(link) or "err"
        local oki, icon, name, qty, quality, locked = Call(GetLootSlotInfo, slot)
        e.info = oki and ("icon=" .. P.Shape(icon) .. " name=" .. P.Shape(name) .. " qty=" .. P.Shape(qty)
            .. " quality=" .. P.Shape(quality) .. " locked=" .. P.Shape(locked)) or "err"
        local oks, g1, q1, g2 = Call(GetLootSourceInfo, slot)
        e.source = oks and (GuidShape(g1) .. " qty=" .. P.Shape(q1) .. (g2 and (" +" .. GuidShape(g2)) or "")) or "err"
        s.slots[#s.slots + 1] = e
    end
    local cands = 0
    if type(GetMasterLootCandidate) == "function" then
        for i = 1, 40 do
            local okc, name = Call(GetMasterLootCandidate, 1, i)
            if okc and name ~= nil then cands = cands + 1 end
        end
    end
    s.candidates = cands
    s.ml = select(2, Call(IsMasterLooter))
    P.loot.snapshot = s
    local db = P.DB()
    db.loot = db.loot or {}
    db.loot[#db.loot + 1] = s
    while #db.loot > 20 do table.remove(db.loot, 1) end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("OPEN_MASTER_LOOT_LIST")
frame:RegisterEvent("UPDATE_MASTER_LOOT_LIST")
frame:RegisterEvent("LOOT_SLOT_CLEARED")
frame:RegisterEvent("CHAT_MSG_LOOT")
pcall(frame.RegisterEvent, frame, "ADDON_ACTION_BLOCKED")
pcall(frame.RegisterEvent, frame, "ADDON_ACTION_FORBIDDEN")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "LOOT_OPENED" then
        pcall(Capture)
    elseif event == "LOOT_SLOT_CLEARED" or event == "CHAT_MSG_LOOT" then
        local g = P.loot.give
        if g and not g.done then
            g.events[#g.events + 1] = event .. "@+" .. string.format("%.2f", (GetTime() - g.time))
                .. (event == "CHAT_MSG_LOOT" and (" secret=" .. tostring(P.IsSecret((...)))) or "")
        end
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- Only the event name and the addon/function names are recorded (no player data).
        local a, fn = ...
        local db = P.DB()
        db.blocked = db.blocked or {}
        if #db.blocked < 50 then
            db.blocked[#db.blocked + 1] = event .. " addon=" .. P.Shape(a) .. " fn=" .. (P.IsSecret(fn) and "secret" or tostring(fn))
        end
    end
end)

P.Register("S2a", "S2", "Loot window readable (open a corpse's loot window first)", function()
    local s = P.loot.snapshot
    if not s then return "info", "no loot window captured yet: open a loot window (as master looter) then run again" end
    local out = { "method=" .. s.method, "numItems=" .. tostring(s.num), "candidates=" .. s.candidates,
        "isMasterLooter=" .. tostring(s.ml) }
    local bad = 0
    for _, e in ipairs(s.slots) do
        if e.link == "err" or e.info == "err" or e.source == "err" then bad = bad + 1 end
        out[#out + 1] = "[" .. e.slot .. "] link=" .. e.link .. " source=" .. e.source .. " " .. e.info
    end
    return (bad == 0 and s.num ~= -1) and "ok" or "partial", table.concat(out, " | ")
end)

P.Register("S2b", "S2", "Master loot candidates readable (open a loot window as master looter)", function()
    local s = P.loot.snapshot
    if not s then return "info", "no loot window captured yet" end
    local mode = (s.candidates > 0) and "ok" or "partial"
    return mode, "candidates=" .. s.candidates .. " isMasterLooter=" .. tostring(s.ml) .. " method=" .. s.method
end)

-- /fdcpp give <slot> <candidate#>: GiveMasterLoot on a TEST drop (hardware click from the slash command).
function P.Give(slot, cand)
    slot, cand = tonumber(slot), tonumber(cand)
    if not slot or not cand then return P.Print("usage: /fdcpp give <slot> <candidate#> (on a test drop)") end
    local g = { time = GetTime(), events = {}, done = false }
    P.loot.give = g
    local ok, err = pcall(GiveMasterLoot, slot, cand)
    local d = "slot=" .. slot .. " candidate=" .. cand .. " call=" .. (ok and "ok" or "error")
    if not ok then d = d .. " err=" .. (P.IsSecret(err) and "secret" or tostring(err)) end
    P.Record("S2c", ok and "partial" or "fail", d .. " (wait 2 s, then /fdcpp run S2c to see the events)")
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            g.done = true
            local ev = #g.events > 0 and table.concat(g.events, ",") or "none"
            P.Record("S2c", (ok and #g.events > 0) and "ok" or (ok and "partial" or "fail"), d .. " events=" .. ev)
            P.Print("S2c: " .. d .. " events=" .. ev)
        end)
    end
end
P.Register("S2c", "S2", "GiveMasterLoot from an addon command (use /fdcpp give <slot> <candidate#>)", function()
    local r = P.DB().results["S2c"]
    if r then return r.result, r.details end
    return "info", "not run: open a TEST drop as master looter, then /fdcpp give <slot> <candidate#>"
end)

P.Register("S2d", "S2", "ADDON_ACTION_BLOCKED / FORBIDDEN log", function()
    local b = P.DB().blocked or {}
    if #b == 0 then return "ok", "none recorded" end
    return "partial", #b .. " recorded: " .. table.concat(b, " | ")
end)
