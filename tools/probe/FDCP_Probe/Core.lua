-- FDCP_Probe: spike probe (M0). Never distributed. Every call is wrapped in pcall, secret values are never compared,
-- the test prefix is FDCPP (never FDCP1), and player or guild names are never printed or stored (counts and shapes only).
local ADDON, P = ...
_G.FDCP_Probe = P

P.PREFIX = "FDCPP"
P.checks = {}      -- registry: id -> { id, area, title, fn }
P.order = {}       -- ids in registration order

local function Print(msg) print("|cff33ccffFDCPP|r " .. tostring(msg)) end
P.Print = Print

function P.DB()
    FDCP_ProbeDB = FDCP_ProbeDB or {}
    local db = FDCP_ProbeDB
    db.results = db.results or {}
    db.events = db.events or {}
    return db
end

function P.Build()
    local ok, version, build = pcall(GetBuildInfo)
    if ok then return tostring(version) .. "." .. tostring(build) end
    return "unknown"
end

-- A secret value must never be compared or concatenated; only its flag is recorded.
function P.IsSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, res = pcall(issecretvalue, v)
    return ok and res == true
end

-- Describes a value by shape only: type and, for strings and tables, a size. Never the content.
function P.Shape(v)
    if P.IsSecret(v) then return "secret" end
    local t = type(v)
    if t == "string" then return "string(" .. #v .. ")" end
    if t == "table" then
        local n = 0
        for _ in pairs(v) do n = n + 1 end
        return "table(" .. n .. ")"
    end
    if t == "number" or t == "boolean" then return tostring(v) end
    return t
end

-- Registers a check. fn(ctx) returns (result, details): result is "ok", "fail", "partial" or "info".
function P.Register(id, area, title, fn)
    if P.checks[id] then error("duplicate check id " .. tostring(id)) end
    P.checks[id] = { id = id, area = area, title = title, fn = fn }
    P.order[#P.order + 1] = id
end

function P.Record(id, result, details)
    local db = P.DB()
    db.results[id] = { id = id, result = result, details = details, build = P.Build(), time = time and time() or 0 }
    return db.results[id]
end

function P.Run(id)
    local c = P.checks[id]
    if not c then return nil, "unknown check" end
    local ok, result, details = pcall(c.fn, c)
    if not ok then result, details = "error", tostring(result) end
    return P.Record(id, result or "info", details and tostring(details) or "")
end

function P.RunAll()
    local n = 0
    for _, id in ipairs(P.order) do P.Run(id); n = n + 1 end
    return n
end

function P.Reset()
    local db = P.DB()
    db.results, db.events = {}, {}
end
