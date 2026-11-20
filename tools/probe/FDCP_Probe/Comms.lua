-- S4 (M0-4): addon messages in raid. Counts, sequence numbers and delays only: never sender names or payload text.
-- Payload format: "<run>|<seq>|<sentServerTime>|<pad>"; <run> is a random id of this send run, so a client recognises
-- its own echoes and a second client reports the run it received (delivery, delays, losses, order).
local ADDON, P = ...

P.comms = { run = nil, seq = 0, sent = {}, lastEnd = nil }
local CHANNELS = { raid = "RAID", guild = "GUILD", officer = "OFFICER", whisper = "WHISPER", party = "PARTY" }
local BUCKETS = { "outside", "instance", "encounter", "after" }
local BURST = 30

local function Bucket()
    if IsEncounterInProgress and IsEncounterInProgress() then return "encounter" end
    if P.comms.lastEnd and GetTime and (GetTime() - P.comms.lastEnd) <= (P.AFTER_WINDOW or 10) then return "after" end
    if IsInInstance and select(1, IsInInstance()) then return "instance" end
    return "outside"
end

local function Store()
    local db = P.DB()
    db.comms = db.comms or { sent = {}, recv = {}, lockdown = {}, enc = {} }
    return db.comms
end

local function Inc(t, k, n) t[k] = (t[k] or 0) + (n or 1) end

local function ResultName(res)
    if P.IsSecret(res) then return "secret" end
    if type(res) == "number" and Enum and Enum.SendAddonMessageResult then
        for name, v in pairs(Enum.SendAddonMessageResult) do if v == res then return name end end
    end
    if res == nil then return "nil" end
    return tostring(res)
end

local function Lockdown()
    local a, b = "n/a", "n/a"
    if P.Has("C_ChatInfo.InChatMessagingLockdown") then
        local ok, v = pcall(C_ChatInfo.InChatMessagingLockdown); a = ok and tostring(v) or "err"
    end
    if P.Has("C_ChatInfo.AreOutgoingAddonChatMessagesRestricted") then
        local ok, v = pcall(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted); b = ok and tostring(v) or "err"
    end
    return a, b
end

local function Now() return GetServerTime and GetServerTime() or (time and time() or 0) end

-- Sends one message and records the result by context. Returns the result name.
local function SendOne(channel, target, pad)
    local c = P.comms
    c.seq = c.seq + 1
    local head = string.format("%s|%d|%d|", c.run, c.seq, Now())
    local payload = head .. (pad and string.rep("x", math.max(0, pad - #head)) or "")
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, P.PREFIX, payload, channel, target)
    local name = ok and ResultName(res) or "error"
    local s, b = Store(), Bucket()
    local key = b .. "." .. channel .. "." .. name
    Inc(s.sent, key)
    local ld, rs = Lockdown()
    s.lockdown[b .. ".lockdown=" .. ld .. ",restricted=" .. rs] = (s.lockdown[b .. ".lockdown=" .. ld .. ",restricted=" .. rs] or 0) + 1
    return name
end

local function Channel(arg)
    local word, target = string.match(arg or "", "^(%S*)%s*(.-)$")
    local ch = CHANNELS[string.lower(word or "")]
    return ch, (target ~= "" and target or nil)
end

-- /fdcpp ping raid|guild|officer|whisper <name> [n]: n numbered messages (default 5).
function P.Ping(arg, n, size)
    if not P.Has("C_ChatInfo.SendAddonMessage") then return P.Record("S4b", "fail", "SendAddonMessage missing") end
    local ch, target = Channel(arg)
    if not ch then return P.Record("S4b", "fail", "channel must be raid, guild, officer, party or whisper <name>") end
    if ch == "WHISPER" then
        local who, count = string.match(target or "", "^(%S+)%s*(%d*)$")
        target = who; n = tonumber(count) or n
        if not target then return P.Record("S4b", "fail", "whisper needs a target name") end
    end
    if ch ~= "WHISPER" then n = tonumber(target) or n; target = nil end
    local c = P.comms
    c.run = string.format("%04x", math.random(0, 65535))
    c.seq = 0
    local pad = size -- total payload size in bytes, or nil for the bare header
    local counts, first = {}, nil
    for _ = 1, n or 5 do
        local r = SendOne(ch, target, pad)
        counts[r] = (counts[r] or 0) + 1
        first = first or r
    end
    local parts = {}
    for k, v in pairs(counts) do parts[#parts + 1] = k .. "=" .. v end
    table.sort(parts)
    local ld, rs = Lockdown()
    local ok = counts.Success == (n or 5)
    return P.Record("S4b", ok and "ok" or "partial", string.format("run=%s channel=%s bucket=%s messages=%d results: %s lockdown=%s restricted=%s",
        c.run, ch, Bucket(), n or 5, table.concat(parts, ","), ld, rs))
end

-- /fdcpp pingbig raid: one message with a 255-byte payload (the limit); /fdcpp burst raid: 30 messages in a loop.
function P.PingBig(arg)
    return P.Ping(arg, 1, 255)
end
function P.PingBurst(arg) return P.Ping(arg, BURST) end

local function OnAddon(prefix, text, channel)
    if prefix ~= P.PREFIX then return end
    local s, b = Store(), Bucket()
    local r = s.recv
    Inc(r, b .. ".received")
    if P.IsSecret(text) then Inc(r, b .. ".secret"); return end
    if type(text) ~= "string" then Inc(r, b .. ".nonString"); return end
    local run, seq, sent = text:match("^(%x+)|(%d+)|(%d+)|")
    if not run then Inc(r, b .. ".unparsed"); return end
    if run == P.comms.run then Inc(r, b .. ".ownEcho"); return end
    seq, sent = tonumber(seq), tonumber(sent)
    local entry = s.runs and s.runs[run]
    s.runs = s.runs or {}
    entry = s.runs[run] or { count = 0, min = seq, max = seq, maxDelay = 0, sumDelay = 0, outOfOrder = 0, last = 0, bucket = b }
    s.runs[run] = entry
    entry.count = entry.count + 1
    entry.min, entry.max = math.min(entry.min, seq), math.max(entry.max, seq)
    local d = math.max(0, Now() - (sent or 0))
    entry.sumDelay, entry.maxDelay = entry.sumDelay + d, math.max(entry.maxDelay, d)
    if seq < entry.last then entry.outOfOrder = entry.outOfOrder + 1 end
    entry.last = seq
    Inc(r, b .. ".readable")
end

local frame = CreateFrame("Frame")
P.commsFrame = frame
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then pcall(OnAddon, ...)
    elseif event == "ENCOUNTER_START" then P.comms.lastEnd = nil
    elseif event == "ENCOUNTER_END" then P.comms.lastEnd = GetTime()
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        local s = Store(); Inc(s.enc, "restrictionChanges")
        local ld, rs = Lockdown()
        s.enc[string.format("change@%.1f lockdown=%s restricted=%s", GetTime and GetTime() or 0, ld, rs)] = 1
    end
end)
for _, e in ipairs({ "CHAT_MSG_ADDON", "ENCOUNTER_START", "ENCOUNTER_END", "ADDON_RESTRICTION_STATE_CHANGED" }) do
    pcall(frame.RegisterEvent, frame, e)
end

local function Sorted(t, filter)
    local out = {}
    for k, v in pairs(t) do if not filter or filter(k) then out[#out + 1] = k .. "=" .. tostring(v) end end
    table.sort(out)
    return out
end

P.Register("S4a", "S4", "Prefix registers and lockdown APIs", function()
    local have = P.Has("C_ChatInfo.RegisterAddonMessagePrefix") and P.Has("C_ChatInfo.SendAddonMessage")
    if not have then return "fail", "API missing" end
    local res = C_ChatInfo.RegisterAddonMessagePrefix(P.PREFIX)
    local reg = P.Has("C_ChatInfo.IsAddonMessagePrefixRegistered") and tostring(C_ChatInfo.IsAddonMessagePrefixRegistered(P.PREFIX)) or "n/a"
    local ld, rs = Lockdown()
    return "info", "register=" .. tostring(res) .. " registered=" .. reg .. " lockdownApi=" .. tostring(P.Has("C_ChatInfo.InChatMessagingLockdown"))
        .. " restrictedApi=" .. tostring(P.Has("C_ChatInfo.AreOutgoingAddonChatMessagesRestricted"))
        .. " lockdown=" .. ld .. " restricted=" .. rs .. " bucket=" .. Bucket()
end)

P.Register("S4b", "S4", "Last send (use /fdcpp ping, pingbig, burst)", function()
    local r = P.DB().results["S4b"]
    if r then return r.result, r.details end
    return "info", "not run: /fdcpp ping raid|guild|officer|party|whisper <name> [n]"
end)

-- The answer to S4: send results per context and channel, lockdown states seen, what this client received per context.
P.Register("S4c", "S4", "Sent results and lockdown per context; received messages", function()
    local s = Store()
    local sent = Sorted(s.sent)
    local ld = Sorted(s.lockdown)
    local recv = Sorted(s.recv)
    local okRaid = false
    for _, b in ipairs(BUCKETS) do
        if (s.sent[b .. ".RAID.Success"] or 0) > 0 then okRaid = true end
    end
    return okRaid and "ok" or "info", "sent: " .. (#sent > 0 and table.concat(sent, ",") or "none")
        .. " | lockdown: " .. (#ld > 0 and table.concat(ld, ",") or "none")
        .. " | received: " .. (#recv > 0 and table.concat(recv, ",") or "none")
end)

-- Delivery on the second client: per received run, count, sequence range, losses, order, delays in seconds.
P.Register("S4d", "S4", "Received runs: delivery, losses, order, delays", function()
    local s = Store()
    local parts = {}
    for run, e in pairs(s.runs or {}) do
        local expected = e.max - e.min + 1
        parts[#parts + 1] = string.format("run %s [%s]: got=%d range=%d-%d lost=%d outOfOrder=%d delay avg=%.1fs max=%ds", run, e.bucket,
            e.count, e.min, e.max, math.max(0, expected - e.count), e.outOfOrder, e.sumDelay / math.max(1, e.count), e.maxDelay)
    end
    table.sort(parts)
    return "info", #parts > 0 and table.concat(parts, " | ") or "no foreign run received yet (the second client sends with /fdcpp ping)"
end)

P.Register("S4e", "S4", "C_EncodingUtil CBOR + Deflate + Base64 round trip", function()
    if not (P.Has("C_EncodingUtil.SerializeCBOR") and P.Has("C_EncodingUtil.CompressString") and P.Has("C_EncodingUtil.EncodeBase64")) then
        return "fail", "C_EncodingUtil missing"
    end
    local value = { v = 1, kind = "session", items = { 1, 2, 3, 4, 5 }, note = string.rep("credit", 20) }
    local ok, err = pcall(function()
        local cbor = C_EncodingUtil.SerializeCBOR(value)
        local packed = C_EncodingUtil.CompressString(cbor)
        local text = C_EncodingUtil.EncodeBase64(packed)
        local back = C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecompressString(C_EncodingUtil.DecodeBase64(text)))
        P.comms.codec = string.format("cbor=%d deflate=%d base64=%d", #cbor, #packed, #text)
        assert(type(back) == "table" and back.v == 1 and back.kind == "session" and #back.items == 5 and back.note == value.note, "round trip differs")
        P.comms.codecOk = #text <= 255
    end)
    if not ok then return "fail", tostring(err) end
    return "ok", P.comms.codec .. " roundTrip=true fitsIn255=" .. tostring(P.comms.codecOk)
end)
