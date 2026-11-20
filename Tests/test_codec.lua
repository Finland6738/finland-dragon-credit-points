-- Codec (M1-6): the wire format "<version>|<TYPE>|<Base64 body>" of docs/ANALISI.md §8.4, round trips, compression,
-- and every way a received text can be malformed. Adapted from Azeroth Accord (Tests/test_codec.lua), same owner,
-- GPL-3.0. The message types of the later steps register themselves with Codec:RegisterType; the tests register
-- stand-ins in `setup` (every test boots a fresh client).
local function Codec() return FDCP.Codec end

local function setup()
	Codec():RegisterType("OPEN", { s = "string" })
	Codec():RegisterType("REC", { s = "string", r = "table" })
end

local function body(flag, tbl)
	return C_EncodingUtil.EncodeBase64(flag .. C_EncodingUtil.SerializeCBOR(tbl))
end

local SAMPLES = {
	HELLO = { av = "0.1.0" },
	OPEN = { s = "session-1", n = 3 },
	REC = { s = "ledger", r = { { id = "x", author = "Aurel-Realm", rev = 3, time = 1767225600 } } },
}

describe("round trips", function()
	for t, fields in pairs(SAMPLES) do
		it("round trips " .. t, function()
			setup()
			local text = Codec():Encode(t, fields)
			notNil(text)
			eq(text:sub(1, #t + 3), "1|" .. t .. "|")
			local msg = Codec():Decode(text)
			eq(msg.v, 1)
			eq(msg.t, t)
			for k, v in pairs(fields) do deepEq(msg[k], v) end
		end)
	end

	it("the prefix carries the protocol version", function()
		eq(Codec().PROTO, 1)
		eq(Codec().PREFIX, "FDCP1")
		eq(FDCP.Transport.PREFIX, "FDCP1")
	end)

	it("sends short messages raw and long ones compressed", function()
		setup()
		local short = Codec():Encode("HELLO", { av = "0.1.0" })
		local _, _, b = Codec().Header(short)
		eq(C_EncodingUtil.DecodeBase64(b):sub(1, 1), "\0")
		local recs = {}
		for i = 1, 40 do recs[i] = { id = "rec" .. i, author = "Aurel-Realm", rev = i, time = 1767225600 } end
		local long = Codec():Encode("REC", { s = "ledger", r = recs })
		local _, _, b2 = Codec().Header(long)
		eq(C_EncodingUtil.DecodeBase64(b2):sub(1, 1), "\1")
		eq(#Codec():Decode(long).r, 40)
	end)

	it("is ASCII-safe and has no separator after the header", function()
		setup()
		local text = Codec():Encode("REC", { s = "x", r = { { note = "a|b\0c" } } })
		matches(text, "^1|REC|[A-Za-z0-9+/=]+$")
		eq(Codec():Decode(text).r[1].note, "a|b\0c")
	end)

	it("does not modify the fields it is given", function()
		setup()
		local fields = { s = "ledger", r = { 1 } }
		Codec():Encode("REC", fields)
		deepEq(fields, { s = "ledger", r = { 1 } })
	end)

	it("keeps fields it does not know (a newer sender of the same version)", function()
		setup()
		local msg = Codec():Decode(Codec():Encode("OPEN", { s = "a", extra = { 1, 2 } }))
		deepEq(msg.extra, { 1, 2 })
	end)

	it("lets a module register its own type", function()
		truthy(Codec():RegisterType("PING", { n = "number" }))
		falsy(Codec():RegisterType("bad type"))
		falsy(Codec():RegisterType(12))
		eq(Codec():Decode(Codec():Encode("PING", { n = 4 })).n, 4)
		isNil(Codec():Encode("PING", {}))
	end)
end)

describe("encode errors", function()
	it("refuses unknown types and missing required fields", function()
		setup()
		local text, why = Codec():Encode("WHAT", {})
		isNil(text); eq(why, "type")
		text, why = Codec():Encode("REC", { s = "x" })
		isNil(text); eq(why, "invalid")
		text, why = Codec():Encode("HELLO", { av = 3 })
		isNil(text); eq(why, "invalid")
		text, why = Codec():Encode("REC", "nope")
		isNil(text); eq(why, "shape")
	end)

	it("refuses a message a receiver would reject for its size", function()
		setup()
		local big = {}
		for i = 1, 3000 do big[i] = ("%08d"):format(i) end
		local text, why = Codec():Encode("REC", { s = "x", r = big })
		isNil(text); eq(why, "size")
	end)
end)

describe("malformed input", function()
	local function decode(text) return select(2, Codec():Decode(text)) end

	it("rejects non-strings, empty and oversized texts", function()
		eq(decode(nil), "size")
		eq(decode(""), "size")
		eq(decode(("A"):rep(Codec().MAX_TEXT + 1)), "size")
	end)

	it("rejects a text without the header", function()
		eq(decode("hello"), "shape")
		eq(decode("1|rec|AAAA"), "shape")
		eq(decode("x|REC|AAAA"), "shape")
	end)

	it("ignores a newer version and an unknown type", function()
		setup()
		eq(decode("2|REC|" .. body("\0", { s = "x", r = {} })), "newer")
		eq(decode("1|LATER|" .. body("\0", {})), "type")
		eq(decode("0|REC|" .. body("\0", { s = "x", r = {} })), "version")
		eq(Codec().stats.unknown, 1)
	end)

	it("rejects bad Base64, a bad flag and broken compression", function()
		setup()
		eq(decode("1|REC|###"), "base64")
		eq(decode("1|REC|"), "base64")
		eq(decode("1|REC|" .. body("\9", { s = "x", r = {} })), "flag")
		eq(decode("1|REC|" .. C_EncodingUtil.EncodeBase64("\1not deflate")), "inflate")
	end)

	it("rejects broken or non-table CBOR and missing required fields", function()
		setup()
		eq(decode("1|REC|" .. C_EncodingUtil.EncodeBase64("\0\255\255")), "cbor")
		eq(decode("1|REC|" .. C_EncodingUtil.EncodeBase64("\0" .. C_EncodingUtil.SerializeCBOR("text"))), "shape")
		eq(decode("1|REC|" .. body("\0", { s = "x" })), "invalid")
	end)

	it("survives random garbage", function()
		setup()
		local seed = 7
		for _ = 1, 200 do
			local chars = {}
			for i = 1, 1 + seed % 60 do
				seed = (seed * 1103515245 + 12345) % 2147483648
				chars[i] = string.char(seed % 256)
			end
			local text = table.concat(chars)
			local ok = pcall(function() return Codec():Decode(text) end)
			truthy(ok)
			ok = pcall(function() return Codec():Decode("1|REC|" .. C_EncodingUtil.EncodeBase64(text)) end)
			truthy(ok)
		end
		eq(#Mock.errors, 0)
	end)

	it("flags a newer version once and counts rejections", function()
		Codec():Decode("3|HELLO|" .. body("\0", { av = "9" }))
		truthy(Codec():ConsumeNewer())
		falsy(Codec():ConsumeNewer())
		eq(Codec():Stats().rejected, 1)
		eq(Codec():Stats().lastReject, "newer")
	end)
end)
