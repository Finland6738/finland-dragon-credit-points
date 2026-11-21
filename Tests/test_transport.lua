-- Transport (M1-6): the send queue over RAID, GUILD, OFFICER and WHISPER (docs/ANALISI.md §8.4, §11 risk 3):
-- validation, per-distribution gap, type rates, lockdown, restriction and encounter hold, keys, expiry, retries, the
-- guild stamp, the queue saved across /reload and logout, and the receive path. Adapted from Azeroth Accord
-- (Tests/test_transport.lua), same owner, GPL-3.0. Most tests replace the wire with a recorder so every timing is
-- exact; the last group runs through the real ChatThrottleLib and the mock client. The two-client delivery of a raid
-- (spike S4) is replayed by handing what one client sent to Mock.chat.Receive.
local function Tr() return FDCP.Transport end
local function Bus() return FDCP.Bus end
local function Codec() return FDCP.Codec end
-- the game is not built yet when this file loads: look the codes up when a test runs
local R = setmetatable({}, { __index = function(_, name) return Enum.SendAddonMessageResult[name] end })

-- Stand-ins for the types of the later steps; every test boots a fresh client, so each registers what it needs.
local function types()
	Codec():RegisterType("OPEN", { s = "string" })    -- the session protocol (M3): ALERT
	Codec():RegisterType("REC", { s = "string", r = "table" })
	Codec():RegisterType("SNAP", { d = "table" })     -- the credits snapshot to the guild: BULK
	Tr().PRIORITY.OPEN = "ALERT"
	Tr().PRIORITY.SNAP = "BULK"
end

local function rec(n) return { t = "REC", s = "ledger", r = { { id = "r" .. (n or 1) } } } end
local function open() return { t = "OPEN", s = "session-1" } end
local function hello() return { t = "HELLO", av = "0.1.0" } end

-- The addon's own presence messages (App/AddonCheck.lua says HELLO on entering a raid) would add to the counts here.
local function inRaid()
	Bus():Off(nil, FDCP.AddonCheck)
	Mock.group.Set{ raid = true, members = { { name = "Bryn" }, { name = "Corin" } } }
end

-- Replaces the wire with a recorder. `results` (optional) are the codes of the next sends, "hold" keeps a send
-- unanswered (call W.answer(n, code) later); anything left over answers Success.
local function fakeWire(results)
	types()
	local W = { calls = {}, results = results or {}, open = {} }
	Tr().wire = function(prio, text, dist, target, done)
		W.calls[#W.calls + 1] = { prio = prio, text = text, dist = dist, target = target, time = GetTime(), bytes = #text }
		local r = table.remove(W.results, 1)
		if r == "hold" then W.open[#W.calls] = done return end
		done(r == nil and R.Success or r)
	end
	function W.answer(n, code) W.open[n](code) W.open[n] = nil end
	function W.msg(n) return (Codec():Decode(W.calls[n].text)) end
	function W.types()
		local out = {}
		for i = 1, #W.calls do out[i] = W.msg(i).t end
		return out
	end
	return W
end

local function listen(event)
	local seen = {}
	Bus():On(event, function(_, ...) seen[#seen + 1] = { ... } end)
	return seen
end

describe("Send", function()
	it("rejects a bad distribution, shape, priority and whisper target", function()
		types()
		eq(select(2, Tr():Send("CHANNEL", open())), "dist", "no public channel")
		eq(select(2, Tr():Send("PARTY", open())), "dist")
		eq(select(2, Tr():Send("GUILD", "x")), "shape")
		eq(select(2, Tr():Send("GUILD", open(), { prio = "URGENT" })), "prio")
		eq(select(2, Tr():Send("WHISPER", open())), "target")
		eq(select(2, Tr():Send("WHISPER", open(), { target = "" })), "target")
		eq(Tr():Pending(), 0)
	end)

	it("rejects what the codec rejects and counts it", function()
		local item, why = Tr():Send("GUILD", { t = "WHAT" })
		isNil(item)
		contains(why, "encode: type")
		eq(Tr():Stats().encodeFailed, 1)
	end)

	it("hands the message to the wire with its priority, distribution and target", function()
		local W = fakeWire()
		inRaid()
		Tr():Send("WHISPER", open(), { target = "Friend-Realm" })
		Tr():Send("RAID", open())
		Tr():Send("OFFICER", rec(2))
		Tr():Send("GUILD", { t = "SNAP", d = { a = 1 } })
		Mock.Advance(1)
		eq(#W.calls, 4)
		eq(W.calls[1].dist, "WHISPER"); eq(W.calls[1].target, "Friend-Realm"); eq(W.calls[1].prio, "ALERT")
		eq(W.calls[2].dist, "RAID"); eq(W.calls[2].prio, "ALERT"); isNil(W.calls[2].target)
		eq(W.calls[3].dist, "OFFICER"); eq(W.calls[3].prio, "NORMAL")
		eq(W.calls[4].dist, "GUILD"); eq(W.calls[4].prio, "BULK")
		eq(W.msg(3).r[1].id, "r2")
	end)

	it("calls onSent once the wire says it went out; a failing callback goes to the error handler", function()
		fakeWire()
		local sent = 0
		Tr():Send("GUILD", rec(), { onSent = function() sent = sent + 1 end })
		Tr():Send("GUILD", rec(2), { onSent = function() error("callback broke") end })
		Mock.Advance(3)
		eq(sent, 1)
		eq(Tr():Stats().callbackErrors, 1)
		eq(#Mock.errors, 1)
		Mock.ClearErrors()
	end)

	it("Cancel withdraws a waiting message and the timer stops with an empty queue", function()
		fakeWire()
		Mock.chat.lockdown = true
		local why
		local item = Tr():Send("GUILD", rec(), { onFail = function(r) why = r end })
		truthy(Tr():Cancel(item))
		falsy(Tr():Cancel(item))
		eq(why, "cancelled")
		Mock.Advance(1)
		isNil(Tr().state.ticker)
	end)
end)

describe("pacing", function()
	it("sends one message per gap on each distribution, the distributions side by side", function()
		local W = fakeWire()
		for i = 1, 3 do Tr():Send("GUILD", rec(i)) end
		for _ = 1, 3 do Tr():Send("WHISPER", open(), { target = "F" }) end
		Mock.Advance(1.05)
		local guild, whisper = 0, 0
		for _, c in ipairs(W.calls) do if c.dist == "GUILD" then guild = guild + 1 else whisper = whisper + 1 end end
		eq(guild, 1, "one GUILD message in the first second")
		eq(whisper, 3, "the whispers do not wait for the guild gap")
		Mock.Advance(2.1)
		eq(#W.calls, 6)
		for i = 2, #W.calls do
			local a, b = W.calls[i - 1], W.calls[i]
			if a.dist == "GUILD" and b.dist == "GUILD" then truthy(b.time - a.time >= 1 - 1e-6) end
		end
	end)

	it("reads the gap as a setting", function()
		local W = fakeWire()
		Tr().GAP.GUILD = 5
		Tr():Send("GUILD", rec(1))
		Tr():Send("GUILD", rec(2))
		Mock.Advance(4)
		eq(#W.calls, 1)
		Mock.Advance(1.2)
		eq(#W.calls, 2)
	end)

	it("sends at most four HELLO a minute (Net/Protocol.lua sets the rate)", function()
		local W = fakeWire()
		for _ = 1, 6 do Tr():Send("GUILD", hello()) end
		Mock.Advance(30)
		eq(#W.calls, 4)
		Mock.Advance(35)
		eq(#W.calls, 6)
	end)

	it("gives the HELLO allowance back when the send fails", function()
		local W = fakeWire({ R.GeneralError })
		Tr():Send("GUILD", hello())
		Mock.Advance(2)
		Tr():Send("GUILD", hello())
		Mock.Advance(2)
		eq(#W.calls, 2)
	end)

	it("messages of one rate group count once", function()
		local W = fakeWire()
		Tr():Send("GUILD", hello(), { rateGroup = "g" })
		Tr():Send("OFFICER", hello(), { rateGroup = "g" })
		Mock.Advance(3)
		eq(#W.calls, 2)
	end)
end)

describe("lockdown, restrictions, encounters, keys and expiry", function()
	it("holds every message during a chat lockdown and releases them afterwards by priority", function()
		local W = fakeWire()
		inRaid()
		Mock.chat.lockdown = true
		Tr():Send("GUILD", rec())
		Tr():Send("GUILD", { t = "SNAP", d = {} })
		Tr():Send("RAID", open())
		Mock.Advance(30)
		eq(#W.calls, 0)
		eq(Tr():Pending(), 3)
		eq(Tr():Stats().held, "lockdown")
		Mock.chat.lockdown = false
		Mock.Advance(3)
		eq(#W.calls, 3)
		isNil(Tr():Stats().held)
		deepEq(W.types(), { "OPEN", "REC", "SNAP" })
	end)

	it("holds during an active addon restriction", function()
		local W = fakeWire()
		Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1 }
		local active = true
		C_RestrictedActions = { GetAddOnRestrictionState = function(kind) return (kind == 1 and active) and 1 or 0 end }
		Tr():Send("GUILD", rec())
		Mock.Advance(5)
		eq(#W.calls, 0)
		eq(Tr():Stats().held, "Encounter")
		active = false
		Mock.Advance(1)
		eq(#W.calls, 1)
	end)

	it("holds while a boss encounter runs and sends after ENCOUNTER_END", function()
		local W = fakeWire()
		inRaid()
		Mock.encounter.Start(1, "Boss")
		Tr():Send("RAID", open())
		Tr():Send("WHISPER", open(), { target = "P" })
		Mock.Advance(20)
		eq(#W.calls, 0)
		eq(Tr():Stats().held, "encounter")
		Mock.encounter.End(1, "Boss", true)
		Mock.Advance(1)
		eq(#W.calls, 2)
		isNil(Tr():Stats().held)
	end)

	it("reports the read-only state, holds, and releases", function()
		local W = fakeWire()
		local events = listen("TRANSPORT_READ_ONLY")
		Mock.chat.restricted = true
		Tr():Send("GUILD", rec())
		Mock.Advance(3)
		eq(#W.calls, 0)
		truthy(Tr():IsReadOnly())
		eq(#events, 1); eq(events[1][1], true)
		Mock.chat.restricted = false
		Mock.Advance(1)
		falsy(Tr():IsReadOnly())
		eq(#W.calls, 1)
		eq(events[2][1], false)
	end)

	it("keeps only the latest message per key", function()
		local W = fakeWire()
		Mock.chat.lockdown = true
		local replaced = {}
		local function opts() return { key = "REC|ledger", onFail = function(r) replaced[#replaced + 1] = r end } end
		Tr():Send("GUILD", rec(1), opts())
		Tr():Send("GUILD", rec(2), opts())
		Tr():Send("GUILD", rec(3), opts())
		eq(Tr():Pending(), 1)
		deepEq(replaced, { "replaced", "replaced" })
		eq(Tr():Stats().coalesced, 2)
		Mock.chat.lockdown = false
		Mock.Advance(1)
		eq(W.msg(1).r[1].id, "r3")
	end)

	it("drops BULK messages older than ten minutes and honours a caller's lifetime", function()
		fakeWire()
		Mock.chat.lockdown = true
		local why = {}
		Tr():Send("GUILD", { t = "SNAP", d = {} }, { onFail = function(r) why[#why + 1] = r end })
		Tr():Send("GUILD", rec(2))
		Tr():Send("GUILD", rec(3), { ttl = 30 })
		Mock.Advance(31)
		eq(Tr():Pending(), 2)
		Mock.Advance(570)
		eq(Tr():Pending(), 1)
		deepEq(why, { "expired" })
		eq(Tr():Stats().droppedBy.expired, 2)
	end)

	it("treats a lockdown refusal of the client as a wait, not a failure or a try", function()
		local W = fakeWire({ R.AddOnMessageLockdown, R.AddOnMessageLockdown })
		local sent = 0
		Tr():Send("GUILD", rec(), { onSent = function() sent = sent + 1 end })
		Mock.Advance(5)
		eq(#W.calls, 3)
		eq(sent, 1)
		eq(Tr():Stats().failed, 0)
		eq(Tr():Stats().retried, 0)
	end)

	it("is bounded: a full queue drops the oldest message of the lowest priority", function()
		fakeWire()
		Mock.chat.lockdown = true
		Tr().QUEUE_MAX = 2
		local why = {}
		Tr():Send("GUILD", { t = "SNAP", d = {} }, { onFail = function(r) why[#why + 1] = "1:" .. r end })
		Tr():Send("GUILD", rec(2))
		Tr():Send("GUILD", open())
		deepEq(why, { "1:overflow" })
		Tr():Send("GUILD", open())
		local refused, reason = Tr():Send("GUILD", { t = "SNAP", d = {} })
		isNil(refused); eq(reason, "full")
	end)
end)

describe("RAID messages", function()
	it("wait while the character is not in a raid and go out when it joins one", function()
		local W = fakeWire()
		Tr():Send("RAID", open())
		Mock.Advance(10)
		eq(#W.calls, 0)
		eq(Tr():Pending("RAID"), 1)
		Mock.group.Set{ raid = false, members = { { name = "Bryn" } } }   -- a party is not a raid
		Mock.Advance(2)
		eq(#W.calls, 0)
		inRaid()
		Mock.Advance(1)
		eq(#W.calls, 1)
		eq(W.calls[1].dist, "RAID")
	end)

	it("are dropped when their lifetime runs out (a stale session message never reaches the next raid)", function()
		fakeWire()
		local why
		Tr():Send("RAID", open(), { onFail = function(r) why = r end })
		Mock.Advance(Tr().TTL.RAID - 1)
		eq(Tr():Pending(), 1)
		Mock.Advance(2)
		eq(Tr():Pending(), 0)
		eq(why, "expired")
	end)

	it("a message to another distribution has no default lifetime", function()
		fakeWire()
		Mock.chat.lockdown = true
		Tr():Send("OFFICER", rec())
		Mock.Advance(3600)
		eq(Tr():Pending(), 1)
	end)
end)

describe("throttle results", function()
	it("retries after the delay and reports success", function()
		local W = fakeWire({ R.AddonMessageThrottle })
		local sent = 0
		Tr():Send("GUILD", rec(), { onSent = function() sent = sent + 1 end })
		Mock.Advance(10)
		eq(#W.calls, 2)
		truthy(W.calls[2].time - W.calls[1].time >= Tr().RETRY_DELAY - 1e-6)
		eq(sent, 1)
		local st = Tr():Stats()
		eq(st.throttled, 1); eq(st.retried, 1); eq(st.failed, 0); eq(st.sent, 1)
	end)

	it("gives up after three retries, and does not retry other errors", function()
		local W = fakeWire({ R.AddonMessageThrottle, R.AddonMessageThrottle, R.AddonMessageThrottle, R.AddonMessageThrottle, R.TargetOffline })
		local reasons = {}
		Tr():Send("GUILD", rec(), { onFail = function(r) reasons[#reasons + 1] = r end })
		Mock.Advance(60)
		eq(#W.calls, 4)
		Tr():Send("WHISPER", open(), { target = "Gone", onFail = function(r) reasons[#reasons + 1] = r end })
		Mock.Advance(10)
		deepEq(reasons, { "AddonMessageThrottle", "TargetOffline" })
		eq(Tr():Stats().failed, 2)
	end)

	it("reports a wire that never reached the client", function()
		types()
		local reason
		Tr().wire = function(_, _, _, _, done) done("nolib") end
		Tr():Send("GUILD", rec(), { onFail = function(r) reason = r end })
		Mock.Advance(1)
		eq(reason, "nolib")
	end)
end)

describe("the guild stamp", function()
	it("drops a message written for a guild the character has left for another", function()
		local W = fakeWire()
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		Mock.chat.lockdown = true
		local why
		Tr():Send("GUILD", rec(), { onFail = function(r) why = r end })
		Mock.guild.Set{ name = "Beta", myRank = 3 }
		Mock.chat.lockdown = false
		Mock.Advance(2)
		eq(#W.calls, 0)
		eq(why, "guild")
	end)

	it("a message waits while the guild is not known yet", function()
		local W = fakeWire()
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		Mock.Advance(2)   -- the roster request of Adapters/GuildRanks.lua is answered (it would restore the key below)
		Mock.chat.lockdown = true
		Tr():Send("GUILD", rec())
		local key = FDCP.Config.guildKey
		truthy(key)
		FDCP.Config.guildKey = nil
		Mock.chat.lockdown = false
		Mock.Advance(3)
		eq(#W.calls, 0)
		eq(Tr():Pending(), 1)
		FDCP.Config.guildKey = key
		Mock.Advance(1)
		eq(#W.calls, 1)
	end)
end)

describe("the saved queue", function()
	it("a message survives lockdown and /reload and goes out afterwards", function()
		types()
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		Mock.chat.lockdown = true
		Tr():Send("GUILD", rec(7), { key = "REC|7" })
		Tr():Send("WHISPER", open(), { target = "Friend-Realm" })
		Mock.Advance(5)
		eq(#Mock.chat.sent, 0)
		Mock.Reload()
		eq(#FinlandDragonCreditPointsCharDB.outbox, 0, "the outbox is emptied once restored")
		eq(Tr():Pending(), 2)
		eq(Tr():Stats().restored, 2)
		Mock.chat.lockdown = false
		Mock.Advance(10)
		local out = Mock.chat.SentWithPrefix("FDCP1")
		eq(#out, 2)
		local kinds = {}
		types()
		for _, e in ipairs(out) do kinds[Codec():Decode(e.message).t] = e.chatType end
		eq(kinds.REC, "GUILD")
		eq(kinds.OPEN, "WHISPER")
	end)

	it("a message survives a boss encounter and /reload during it", function()
		types()
		inRaid()
		Mock.encounter.Start(1, "Boss")
		Tr():Send("RAID", open())
		Mock.Advance(5)
		Mock.Reload()
		Bus():Off(nil, FDCP.AddonCheck)   -- the reloaded addon would say HELLO in the raid
		eq(Tr():Pending("RAID"), 1)
		Mock.Advance(5)
		eq(#Mock.chat.sent, 0, "still the same encounter")
		Mock.encounter.End(1, "Boss", true)
		Mock.Advance(2)
		local out = Mock.chat.SentWithPrefix("FDCP1")
		eq(#out, 1)
		eq(out[1].chatType, "RAID")
	end)

	it("keeps the key, so a newer message replaces the restored one", function()
		fakeWire()
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		Mock.chat.lockdown = true
		Tr():Send("GUILD", rec(1), { key = "K" })
		Mock.Reload()
		local W = fakeWire()
		Tr():Send("GUILD", rec(2), { key = "K" })
		Mock.chat.lockdown = false
		Mock.Advance(3)
		eq(#W.calls, 1)
		eq(W.msg(1).r[1].id, "r2")
	end)

	it("drops what was written for another guild, what expired and what is too old", function()
		types()
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		Mock.chat.lockdown = true
		Tr():Send("GUILD", rec(1))
		Tr():Send("GUILD", rec(2), { ttl = 60 })
		Mock.Fire("PLAYER_LOGOUT")
		eq(#FinlandDragonCreditPointsCharDB.outbox, 2)
		-- the game stays closed two minutes: the 60-second message is gone; the other goes to the guild it was for
		local box = {}
		for i, e in ipairs(FinlandDragonCreditPointsCharDB.outbox) do
			box[i] = {}
			for k, v in pairs(e) do box[i][k] = v end
			box[i].saved, box[i].born = e.saved - 120, e.born - 120
		end
		T.boot(function(M)
			M.guild.Set{ name = "Alpha", myRank = 3 }
			M.chat.lockdown = true
			FinlandDragonCreditPointsCharDB = { outbox = box }
		end)
		eq(Tr():Pending(), 1)
		Mock.guild.Set{ name = "Beta", myRank = 3 }
		Mock.chat.lockdown = false
		Mock.Advance(3)
		eq(#Mock.chat.SentWithPrefix("FDCP1"), 0)
		eq(Tr():Stats().droppedBy.guild, 1)
	end)

	it("a saved message older than a day is not sent again", function()
		types()
		Mock.guild.Set{ name = "Alpha", myRank = 3 }
		Mock.chat.lockdown = true
		Tr():Send("GUILD", rec(1))
		Mock.Fire("PLAYER_LOGOUT")
		Mock.SetServerTime(GetServerTime() + 2 * 86400)
		Mock.Reload()
		eq(Tr():Pending(), 0)
	end)

	it("ignores a damaged outbox", function()
		T.boot(function() FinlandDragonCreditPointsCharDB = { outbox = { "x", { dist = "CHANNEL", payload = "y" }, { dist = "GUILD" } } } end)
		eq(Tr():Pending(), 0)
		eq(#Mock.errors, 0)
	end)
end)

describe("receive path", function()
	local function text(t, fields) types() return Codec():Encode(t, fields) end

	it("decodes a message from AceComm and puts it on the Bus with the sender and the distribution", function()
		local seen = listen("NET_MESSAGE")
		truthy(Mock.chat.Receive("FDCP1", text("OPEN", { s = "x" }), "RAID", "Sender-Realm"))
		eq(#seen, 1)
		eq(seen[1][1].t, "OPEN"); eq(seen[1][1].s, "x")
		eq(seen[1][2], "Sender-Realm")
		eq(seen[1][3], "RAID")
		eq(Tr():Stats().received, 1)
	end)

	it("ignores its own echo on every distribution", function()
		local seen = listen("NET_MESSAGE")
		Mock.chat.Receive("FDCP1", text("OPEN", { s = "x" }), "GUILD", "Testchar-TestRealm")
		Mock.chat.Receive("FDCP1", text("OPEN", { s = "x" }), "RAID", "Testchar")
		Mock.chat.Receive("FDCP1", text("OPEN", { s = "x" }), "OFFICER", "Testchar")
		Mock.chat.Receive("FDCP1", text("OPEN", { s = "x" }), "WHISPER", "Testchar-TestRealm")
		eq(#seen, 0)
		eq(Tr():Stats().echoes, 4)
	end)

	it("a namesake on another realm is not the player", function()
		local seen = listen("NET_MESSAGE")
		Mock.chat.Receive("FDCP1", text("OPEN", { s = "x" }), "GUILD", "Testchar-OtherRealm")
		eq(#seen, 1)
	end)

	it("the first message or echo that arrives proves addon messages travel (spike S4)", function()
		local C = FDCP.Compat
		eq(C:Feature("addonMessages"), "unknown")
		Mock.chat.Receive("FDCP1", text("OPEN", { s = "x" }), "RAID", "Testchar")
		eq(C:Feature("addonMessages"), "available")
	end)

	it("a message from someone else also proves it", function()
		Mock.chat.Receive("FDCP1", text("OPEN", { s = "x" }), "OFFICER", "Officer-TestRealm")
		eq(FDCP.Compat:Feature("addonMessages"), "available")
	end)

	it("drops invalid, unknown and foreign-distribution messages silently", function()
		local seen = listen("NET_MESSAGE")
		Mock.ClearOutput()
		Mock.chat.Receive("FDCP1", "###", "GUILD", "S-R")
		Mock.chat.Receive("FDCP1", "1|LATER|AAAA", "GUILD", "S-R")
		Mock.chat.Receive("FDCP1", text("OPEN", { s = "x" }), "PARTY", "S-R")
		Mock.chat.Receive("FDCP1", "", "GUILD", "S-R")
		eq(#seen, 0)
		local st = Tr():Stats()
		eq(st.rxDropped, 4)
		eq(st.rxReasons.type, 1); eq(st.rxReasons.dist, 1)
		eq(#Mock.PlainOutput(), 0)
		eq(#Mock.errors, 0)
	end)

	it("announces a newer protocol once per session and does not deliver it", function()
		local seen, newer = listen("NET_MESSAGE"), listen("PROTOCOL_NEWER")
		local future = "2|OPEN|" .. C_EncodingUtil.EncodeBase64("\0" .. C_EncodingUtil.SerializeCBOR({ s = "x" }))
		Mock.chat.Receive("FDCP1", future, "RAID", "S-R")
		Mock.chat.Receive("FDCP1", future, "RAID", "S-R")
		eq(#seen, 0)
		eq(#newer, 1)
		eq(Tr():Stats().rxNewer, 2)
	end)

	it("a message of an unknown type or a newer version never reaches a handler, even among good ones", function()
		local seen = listen("NET_MESSAGE")
		Mock.chat.Receive("FDCP1", text("OPEN", { s = "a" }), "RAID", "S-R")
		Mock.chat.Receive("FDCP1", "1|FUTURE|" .. C_EncodingUtil.EncodeBase64("\0" .. C_EncodingUtil.SerializeCBOR({ q = 1 })), "RAID", "S-R")
		Mock.chat.Receive("FDCP1", "9|OPEN|" .. C_EncodingUtil.EncodeBase64("\0" .. C_EncodingUtil.SerializeCBOR({ s = "z" })), "RAID", "S-R")
		Mock.chat.Receive("FDCP1", text("OPEN", { s = "b" }), "RAID", "S-R")
		eq(#seen, 2)
		eq(seen[1][1].s, "a"); eq(seen[2][1].s, "b")
	end)

	it("never writes the sender anywhere it can be read", function()
		Mock.chat.Receive("FDCP1", text("OPEN", { s = "x" }), "GUILD", "Hidden-Realm")
		Mock.chat.Receive("FDCP1", "###", "GUILD", "Hidden-Realm")
		Mock.ClearOutput()
		Mock.Slash("/fdcp debug")
		local out = table.concat(Mock.PlainOutput(), "\n")
		contains(out, "Transport:")
		contains(out, "Codec:")
		falsy(out:find("Hidden", 1, true))
		falsy(table.concat(FDCP.Log.Lines(), "\n"):find("Hidden", 1, true))
	end)
end)

describe("through ChatThrottleLib and the mock client", function()
	local function warm() Mock.Advance(6) end   -- ChatThrottleLib clamps hard for five seconds after start-up

	it("sends RAID, GUILD, OFFICER and WHISPER messages with the FDCP1 prefix", function()
		types()
		Mock.guild.Set({ name = "G", myRank = 1 })
		inRaid()
		warm()
		local sent = {}
		Tr():Send("RAID", open(), { onSent = function() sent[#sent + 1] = "raid" end })
		Tr():Send("GUILD", rec(), { onSent = function() sent[#sent + 1] = "guild" end })
		Tr():Send("OFFICER", rec(2), { onSent = function() sent[#sent + 1] = "officer" end })
		Tr():Send("WHISPER", open(), { target = "Friend-Realm", onSent = function() sent[#sent + 1] = "whisper" end })
		Mock.Advance(3)
		local out = Mock.chat.SentWithPrefix("FDCP1")
		eq(#out, 4)
		local byType = {}
		for _, e in ipairs(out) do byType[e.chatType] = e end
		eq(byType.WHISPER.target, "Friend-Realm")
		eq(Codec():Decode(byType.RAID.message).t, "OPEN")
		eq(Codec():Decode(byType.OFFICER.message).r[1].id, "r2")
		eq(#sent, 4)
		truthy(C_ChatInfo.IsAddonMessagePrefixRegistered("FDCP1"))
	end)

	it("splits a long message like AceComm and AceComm puts it back together", function()
		types()
		Mock.guild.Set({ name = "G" })
		warm()
		local recs, seed = {}, 11
		for i = 1, 60 do
			seed = (seed * 1103515245 + 12345) % 2147483648
			recs[i] = { id = "r" .. i, author = "Player-1-" .. seed, rev = seed % 1000 }
		end
		Tr():Send("GUILD", { t = "REC", s = "ledger", r = recs })
		Mock.Advance(5)
		local out = Mock.chat.SentWithPrefix("FDCP1")
		truthy(#out >= 3, "chunks " .. #out)
		eq(out[1].message:sub(1, 1), "\1")
		eq(out[#out].message:sub(1, 1), "\3")
		for _, e in ipairs(out) do truthy(#e.prefix + #e.message <= 255) end
		eq(Tr():Stats().sent, 1)

		local seen = listen("NET_MESSAGE")
		for _, e in ipairs(out) do Mock.chat.Receive("FDCP1", e.message, "GUILD", "Other-Realm") end
		eq(#seen, 1)
		deepEq(seen[1][1].r, recs)
	end)

	it("a raid message sent while the lockdown lasts reaches the raid afterwards, once", function()
		types()
		inRaid()
		warm()
		Mock.chat.lockdown = true
		Tr():Send("RAID", open())
		Mock.Advance(10)
		eq(#Mock.chat.SentWithPrefix("FDCP1"), 0)
		Mock.chat.lockdown = false
		Mock.Advance(3)
		local out = Mock.chat.SentWithPrefix("FDCP1")
		eq(#out, 1)
		-- the other client receives it
		local seen = listen("NET_MESSAGE")
		Mock.chat.Receive("FDCP1", out[1].message, "RAID", "Corin-TestRealm")
		eq(#seen, 1)
		eq(seen[1][1].s, "session-1")
	end)

	it("Frame leaves room for the prefix", function()
		local L = 255 - #Tr().PREFIX
		eq(#Tr().Frame(("x"):rep(L)), 1)
		local chunks = Tr().Frame(("x"):rep(L + 1))
		eq(#chunks, 2)
		eq(#chunks[1], L)
		eq(chunks[1]:sub(1, 1), "\1")
		eq(chunks[2], "\3xx")
	end)

	it("reports a missing library as a failure", function()
		types()
		Mock.guild.Set({ name = "G" })
		local reason
		ChatThrottleLib = nil
		Tr():Send("GUILD", rec(), { onFail = function(r) reason = r end })
		Mock.Advance(2)
		eq(reason, "nolib")
		eq(#Mock.errors, 0)
	end)
end)
