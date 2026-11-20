-- Codec: message <-> addon-message text (docs/ANALISI.md §8.4). Lua 5.1.
-- Adapted from Azeroth Accord (Net/Codec.lua), same owner, GPL-3.0. The wire format:
--
--   text    = "<version>|<TYPE>|" .. Base64( flag .. (flag == "\1" and Deflate(CBOR(body)) or CBOR(body)) )
--   message = { v = <version>, t = "<TYPE>", ...fields of body }
--
-- The version and the type are plain text, so a client reads them before decoding anything: a higher version or an
-- unknown type is ignored, never an error. Decode never raises: it returns the message, or nil plus a reason
-- ("size", "shape", "version", "newer", "type", "base64", "flag", "inflate", "cbor", "invalid"). Unknown fields are
-- kept untouched; deep validation of records belongs to the modules that own them (Protocol, Sync, ...).
--
-- The prefix carries the protocol version too ("FDCP1"): a later incompatible protocol takes the prefix "FDCP2" and
-- never reaches a client that only listens to "FDCP1". The version in the text header is the second guard.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Codec = {}
ns.Codec, ns.modules.Codec = Codec, Codec

local type, pairs, tostring, tonumber, floor = type, pairs, tostring, tonumber, math.floor
local sub, find, match = string.sub, string.find, string.match

Codec.PROTO = 1
Codec.PREFIX = "FDCP" .. Codec.PROTO
Codec.COMPRESS_OVER = 120   -- CBOR longer than this is deflated (when that makes it shorter)
Codec.MAX_DECODED = 16384   -- largest accepted CBOR after decompression
Codec.FLAG_RAW, Codec.FLAG_DEFLATE = "\0", "\1"
-- A Base64 body cannot be longer than the encoded largest message plus the flag byte; the header is a few bytes more.
Codec.MAX_BODY = floor((Codec.MAX_DECODED + 1) / 3 + 1) * 4
Codec.MAX_TEXT = Codec.MAX_BODY + 32

Codec.newerSeen = false     -- a message with a newer protocol version was received (shown once)
Codec.stats = { encoded = 0, decoded = 0, rejected = 0, unknown = 0 }
Codec.lastReject = nil      -- last rejection reason, for /fdcp debug

-- Required fields per message type: name -> Lua type. Unlisted fields are optional and never rejected. The session
-- protocol (M3) and the ledger sync (M5) add their types with Codec:RegisterType; M1-6 only knows the handshake.
Codec.SCHEMA = {
	HELLO = { av = "string" },   -- av = the addon version; who is running the addon, answered by the session opener
}

-- Adds a message type (or replaces its required fields). Type names are upper-case letters and digits.
function Codec:RegisterType(name, required)
	if type(name) ~= "string" or not match(name, "^[A-Z][A-Z0-9]*$") then return false end
	Codec.SCHEMA[name] = type(required) == "table" and required or {}
	return true
end

local function compat() return ns.Compat end

local function reject(reason)
	Codec.stats.rejected = Codec.stats.rejected + 1
	Codec.lastReject = reason
	return nil, reason
end

-- true, or false plus a reason. msg must be a table with a known `t` and the required fields of that type.
function Codec:Validate(msg)
	if type(msg) ~= "table" then return false, "shape" end
	local schema = type(msg.t) == "string" and Codec.SCHEMA[msg.t]
	if not schema then return false, "type" end
	for field, kind in pairs(schema) do
		if type(msg[field]) ~= kind then return false, "invalid" end
	end
	return true
end

-- Builds the text for message type `t` with `fields` (the fields `v` and `t` are set here). Returns the string, or nil
-- plus a reason.
function Codec:Encode(t, fields)
	local C = compat()
	if not C then return nil, "nocompat" end
	if fields ~= nil and type(fields) ~= "table" then return nil, "shape" end
	local msg = { t = t }
	for k, v in pairs(fields or {}) do msg[k] = v end
	msg.t = t
	local ok, reason = Codec:Validate(msg)
	if not ok then return nil, reason end
	local body = {}
	for k, v in pairs(msg) do
		if k ~= "t" and k ~= "v" then body[k] = v end
	end
	local cbor, err = C.CBOR.Encode(body)
	if not cbor then return nil, "cbor: " .. tostring(err) end
	if #cbor > Codec.MAX_DECODED then return nil, "size" end   -- a receiver would reject it
	local flag, packed = Codec.FLAG_RAW, cbor
	if #cbor > Codec.COMPRESS_OVER then
		local deflated = C.Compress.Deflate(cbor)
		if deflated and #deflated < #cbor then flag, packed = Codec.FLAG_DEFLATE, deflated end
	end
	local text, err2 = C.Base64.Encode(flag .. packed)
	if not text then return nil, "base64: " .. tostring(err2) end
	Codec.stats.encoded = Codec.stats.encoded + 1
	return Codec.PROTO .. "|" .. t .. "|" .. text
end

-- version, type, body of a text, or nil plus a reason. Reads only the plain-text header.
function Codec.Header(text)
	if type(text) ~= "string" or text == "" then return nil, "size" end
	local version, t, body = match(text, "^(%d+)|([A-Z][A-Z0-9]*)|(.*)$")
	if not version then return nil, "shape" end
	return tonumber(version), t, body
end

-- Returns the message table, or nil plus a reason. Never raises.
function Codec:Decode(text)
	local C = compat()
	if not C then return nil, "nocompat" end
	if type(text) ~= "string" or text == "" or #text > Codec.MAX_TEXT then return reject("size") end
	local version, t, body = Codec.Header(text)
	if not version then return reject(t) end
	if version < 1 then return reject("version") end
	if version > Codec.PROTO then
		Codec.newerSeen = true
		return reject("newer")
	end
	if not Codec.SCHEMA[t] then
		Codec.stats.unknown = Codec.stats.unknown + 1
		return reject("type")
	end
	if body == "" or #body > Codec.MAX_BODY or find(body, "[^A-Za-z0-9+/=]") then return reject("base64") end
	local raw = C.Base64.Decode(body)
	if not raw or raw == "" then return reject("base64") end
	local flag, packed = sub(raw, 1, 1), sub(raw, 2)
	if flag == Codec.FLAG_DEFLATE then
		packed = C.Compress.Inflate(packed)
		if not packed then return reject("inflate") end
	elseif flag ~= Codec.FLAG_RAW then
		return reject("flag")
	end
	if #packed == 0 or #packed > Codec.MAX_DECODED then return reject("size") end
	local msg = C.CBOR.Decode(packed)
	if type(msg) ~= "table" then return reject(msg == nil and "cbor" or "shape") end
	msg.v, msg.t = version, t
	local ok, reason = Codec:Validate(msg)
	if not ok then return reject(reason) end
	Codec.stats.decoded = Codec.stats.decoded + 1
	return msg
end

-- One-shot: true the first time after a newer version was seen, then false until another one arrives.
function Codec:ConsumeNewer()
	local seen = Codec.newerSeen
	Codec.newerSeen = false
	return seen
end

-- The numbers for /fdcp debug (the text is composed from locale keys in Net/Transport.lua).
function Codec:Stats()
	local s = Codec.stats
	return { proto = Codec.PROTO, encoded = s.encoded, decoded = s.decoded, rejected = s.rejected, unknown = s.unknown,
		lastReject = Codec.lastReject, newerSeen = Codec.newerSeen }
end
