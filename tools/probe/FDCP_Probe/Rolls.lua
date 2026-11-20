-- S3 (M0-3): rolls, system messages and encounters. Counts and shapes only: never player names, roll texts or item links.
-- A chat message that is a secret value is only counted; it is never compared, matched or concatenated.
local ADDON, P = ...

P.rolls = { lastEnd = nil, started = nil, ownRoll = nil, restrictions = 0 }
P.AFTER_WINDOW = 10 -- seconds after ENCOUNTER_END that count as "after"

-- Builds a Lua pattern from a game format string (%s, %d, %1$s ...) so no chat pattern is ever written by hand.
-- Returns the pattern and the ordered list of conversions ("s" or "d"); nil for a missing or non-string format.
function P.BuildPattern(fmt)
    if type(fmt) ~= "string" then return nil end
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
local function Orders(fmt)
    local order, n = {}, 0
    for pos in fmt:gmatch("%%(%d*)%$?[sd]") do
        n = n + 1
        order[n] = tonumber(pos) or n
    end
    return order
end

-- Matches text against a game format; returns the captures in the format's argument order, or nil.
function P.MatchFormat(fmt, text)
    local pattern = P.BuildPattern(fmt)
    if not pattern then return nil end
    local caps = { text:match(pattern) }
    if #caps == 0 then return nil end
    local order, out = Orders(fmt), {}
    for i, v in ipairs(caps) do out[order[i] or i] = v end
    return out
end

local LOOT_GLOBALS = { "LOOT_ITEM", "LOOT_ITEM_SELF", "LOOT_ITEM_MULTIPLE", "LOOT_ITEM_SELF_MULTIPLE",
    "LOOT_ITEM_PUSHED", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_BONUS_ROLL", "LOOT_ITEM_BONUS_ROLL_SELF" }
local BUCKETS = { "outside", "instance", "encounter", "after" }

-- Context of a message: during an encounter, shortly after ENCOUNTER_END, inside an instance between bosses, outside.
local function Bucket()
    if IsEncounterInProgress and IsEncounterInProgress() then return "encounter" end
    if P.rolls.lastEnd and GetTime and (GetTime() - P.rolls.lastEnd) <= P.AFTER_WINDOW then return "after" end
    if IsInInstance and select(1, IsInInstance()) then return "instance" end
    return "outside"
end

local function Counts()
    local db = P.DB()
    db.rolls = db.rolls or {}
    return db.rolls
end

local function Tally(bucket, key)
    local c = Counts()
    c[bucket] = c[bucket] or {}
    c[bucket][key] = (c[bucket][key] or 0) + 1
end

local function OnSystem(text)
    local b = Bucket()
    Tally(b, "system")
    if P.IsSecret(text) then Tally(b, "systemSecret"); return end
    if type(text) ~= "string" then Tally(b, "systemOther"); return end
    if P.MatchFormat(_G.RANDOM_ROLL_RESULT, text) then
        Tally(b, "rollReadable")
        if P.rolls.ownRoll and GetTime and (GetTime() - P.rolls.ownRoll) < 3 then Tally(b, "rollNearOwn") end
    end
end

local function OnLoot(text)
    local b = Bucket()
    Tally(b, "loot")
    if P.IsSecret(text) then Tally(b, "lootSecret"); return end
    if type(text) ~= "string" then return end
    for _, g in ipairs(LOOT_GLOBALS) do
        if P.MatchFormat(_G[g], text) then Tally(b, "loot:" .. g); return end
    end
    Tally(b, "lootUnmatched")
end

local frame = CreateFrame("Frame")
P.rollFrame = frame
frame:SetScript("OnEvent", function(_, event, ...)
    local first = ...
    if event == "CHAT_MSG_SYSTEM" then pcall(OnSystem, first)
    elseif event == "CHAT_MSG_LOOT" then pcall(OnLoot, first)
    elseif event == "ENCOUNTER_START" then P.rolls.started, P.rolls.lastEnd = GetTime(), nil
    elseif event == "ENCOUNTER_END" then P.rolls.lastEnd = GetTime()
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then P.rolls.restrictions = P.rolls.restrictions + 1 end
end)
for _, e in ipairs({ "CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT", "ENCOUNTER_START", "ENCOUNTER_END",
    "ADDON_RESTRICTION_STATE_CHANGED" }) do pcall(frame.RegisterEvent, frame, e) end

-- /fdcpp roll: rolls 1-100 once; S3c then shows whether the system message came back readable.
function P.Roll()
    if not P.Has("RandomRoll") then return P.Record("S3b", "fail", "RandomRoll missing") end
    local ok, err = pcall(RandomRoll, 1, 100)
    P.rolls.ownRoll = GetTime()
    local d = "bucket=" .. Bucket() .. " call=" .. (ok and "ok" or "error")
    if not ok then d = d .. " err=" .. (P.IsSecret(err) and "secret" or tostring(err)) end
    return P.Record("S3b", ok and "partial" or "fail", d .. " (see S3c for whether the roll message was readable)")
end

P.Register("S3a", "S3", "Roll and loot message patterns built from the game globals", function()
    local fmt = _G.RANDOM_ROLL_RESULT
    if type(fmt) ~= "string" then return "fail", "RANDOM_ROLL_RESULT missing" end
    local _, kinds = P.BuildPattern(fmt)
    local sample = string.format(fmt, "Aurel", 42, 1, 100)
    local caps = P.MatchFormat(fmt, sample)
    local selfTest = caps ~= nil and caps[1] == "Aurel" and caps[2] == "42" and caps[3] == "1" and caps[4] == "100"
    local present, missing = 0, {}
    for _, g in ipairs(LOOT_GLOBALS) do
        if type(_G[g]) == "string" then present = present + 1 else missing[#missing + 1] = g end
    end
    return selfTest and "ok" or "fail", "rollFormat=string(" .. #fmt .. ") conversions=" .. #kinds
        .. " selfTest=" .. tostring(selfTest) .. " lootGlobals=" .. present
        .. " missing=" .. (#missing > 0 and table.concat(missing, ",") or "none")
end)

P.Register("S3b", "S3", "Own roll (use /fdcpp roll)", function()
    local r = P.DB().results["S3b"]
    if r then return r.result, r.details end
    return "info", "not run: /fdcpp roll calls RandomRoll(1, 100)"
end)

-- The answer to S3: per context, how many system messages arrived, how many were secret, how many were readable rolls.
P.Register("S3c", "S3", "System messages and rolls per context (secret or readable)", function()
    local c = Counts()
    local parts, secretSeen, readable = {}, false, 0
    for _, b in ipairs(BUCKETS) do
        local t = c[b] or {}
        parts[#parts + 1] = string.format("%s: system=%d secret=%d rolls=%d near-own=%d", b, t.system or 0,
            t.systemSecret or 0, t.rollReadable or 0, t.rollNearOwn or 0)
        if (t.systemSecret or 0) > 0 then secretSeen = true end
        readable = readable + (t.rollReadable or 0)
    end
    local result = readable > 0 and not secretSeen and "ok" or (readable > 0 and "partial" or "info")
    return result, table.concat(parts, " | ")
end)

P.Register("S3d", "S3", "Restriction state and encounter timeline", function()
    local have = P.Has("C_RestrictedActions.GetAddOnRestrictionState")
    local n, enc, parts = 0, 0, {}
    for _, e in ipairs(P.DB().events or {}) do
        if e.event == "ADDON_RESTRICTION_STATE_CHANGED" then n = n + 1 end
        if e.event == "ENCOUNTER_START" or e.event == "ENCOUNTER_END" then
            enc = enc + 1
            parts[#parts + 1] = (e.event == "ENCOUNTER_START" and "S" or "E") .. string.format("@%.0f", e.time or 0)
        end
    end
    local d = "api=" .. tostring(have) .. " restrictionChanges=" .. n .. " (live=" .. P.rolls.restrictions .. ")"
        .. " encounterEvents=" .. enc .. (#parts > 0 and (" timeline=" .. table.concat(parts, ",")) or "")
    return have and "info" or "partial", d
end)

P.Register("S3e", "S3", "CHAT_MSG_LOOT messages matched by the LOOT_ITEM patterns", function()
    local c, parts, total, unmatched, secret = Counts(), {}, 0, 0, 0
    for _, b in ipairs(BUCKETS) do
        local t = c[b] or {}
        total = total + (t.loot or 0)
        unmatched = unmatched + (t.lootUnmatched or 0)
        secret = secret + (t.lootSecret or 0)
        for k, v in pairs(t) do
            if k:sub(1, 5) == "loot:" then parts[#parts + 1] = b .. "." .. k:sub(6) .. "=" .. v end
        end
    end
    table.sort(parts)
    local r = total == 0 and "info" or ((unmatched == 0 and secret == 0) and "ok" or "partial")
    return r, "messages=" .. total .. " secret=" .. secret .. " unmatched=" .. unmatched
        .. (#parts > 0 and (" " .. table.concat(parts, ",")) or "")
end)
