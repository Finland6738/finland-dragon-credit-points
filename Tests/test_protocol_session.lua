-- The loot session protocol on RAID (M4-1): Net/Protocol.lua (Protocol.Session), docs/ANALISI.md §4, §8.4. The first
-- groups run on one client (the messages, the readers, the trust rules); the scenarios run on the network simulator
-- (Tests/sim/sim.lua): a master looter running Domain/SessionFSM.lua, raiders answering from their views, a forged
-- response, a /reload of a raider and of the master looter, a late joiner, a chat lockdown, a lockdown long enough to
-- lose messages, a boss encounter.
local function P() return FDCP.Protocol end
local function S() return FDCP.Protocol.Session end
local function Codec() return FDCP.Codec end

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end

-- Items (Pricing, preset Patto): the ring costs 1, the sword 2.
local RING = { itemID = 19003, slot = 1, classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER", quality = 4 }
local SWORD = { itemID = 19002, slot = 3, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON", quality = 4 }

-- The decoded addon messages a client sent, oldest first: { msg, chatType, target }.
local function sentMessages(M)
	local out = {}
	for _, e in ipairs(M.chat.SentWithPrefix("FDCP1")) do
		local text = e.message
		if text:byte(1) == 4 then text = text:sub(2) end   -- AceComm escape byte
		local msg = FDCP and Codec():Decode(text)
		if msg then out[#out + 1] = { msg = msg, chatType = e.chatType, target = e.target } end
	end
	return out
end

local function count(list, t)
	local n = 0
	for _, e in ipairs(list) do if e.msg.t == t then n = n + 1 end end
	return n
end

local function types(list)
	local out = {}
	for _, e in ipairs(list) do out[#out + 1] = e.msg.t end
	return out
end

local function manual()
	local r = FDCP.Rules.DefaultConfig()
	r.session.autoAdvance = false
	return r
end

describe("session messages on one client", function()
	before_boot(function(M) M.player.name, M.player.realm = "Aurel", REALM end)

	local function receive(t, fields, sender, dist)
		return Mock.chat.Receive("FDCP1", Codec():Encode(t, fields), dist or "RAID", sender)
	end

	local function raid(names)
		local members = {}
		for i, n in ipairs(names) do members[i] = { name = n } end
		Mock.group.Set{ raid = true, members = members }
	end

	local function open(sender, q, extra)
		local fields = { s = "S1-1", q = q or 1, ml = sender, it = { { id = 19003, ca = "armor", cs = { MS = 1, OS = 0.5 } } } }
		for k, v in pairs(extra or {}) do fields[k] = v end
		receive("SOPEN", fields, sender)
	end

	it("speaks protocol 3 (and still understands 2): the presence check plus the session messages", function()
		eq(P().VERSION, 3)
		eq(P().MIN, 2)
		for _, t in ipairs(S().TYPES) do truthy(Codec().SCHEMA[t], t .. " is registered") end
		eq(#S().TYPES, 10)
		for _, t in ipairs(S().TYPES) do
			falsy(t:find("ROLL") and t ~= "SROLL", "no message carries a roll")
		end
	end)

	it("time travels in server time, never in the local clock", function()
		eq(S().ToServer(130, 100, 5000), 5030)
		eq(S().FromServer(5030, 7, 5000), 37)
		isNil(S().ToServer(nil, 100, 5000))
		isNil(S().FromServer(nil))
	end)

	it("maps every SessionFSM effect the raid needs to a message, and leaves the others out", function()
		local s = { id = "S1-1", ml = full("Aurel"), encounter = 601, state = "ANNOUNCING", items = {
			{ itemID = 19003, category = "armor", costs = { MS = 1, OS = 0.5 }, state = "PENDING" },
		} }
		local M = S().MessageFor
		isNil(M(s, { type = "ITEM_CORRECTED", item = 1 }), "before the announcement the raid knows nothing")
		local open = M(s, { type = "ANNOUNCE_ITEMS" })
		eq(open.t, "SOPEN"); eq(open.ml, full("Aurel")); eq(open.e, 601)
		deepEq(open.it, { { id = 19003, ca = "armor", cs = { MS = 1, OS = 0.5 } } })
		eq(M(s, { type = "ITEM_CORRECTED", item = 1 }).t, "SOPEN", "a correction after it is sent again")
		local roll = M(s, { type = "OPEN_ROUND", item = 1, kind = "ROLL", stage = "TIER", tier = 1, collect = true,
			deadline = FDCP.Compat.Now() + 30 })
		eq(roll.t, "SROLL"); eq(roll.r, 1); eq(roll.cl, true); eq(roll.tr, 1)
		eq(roll.de, FDCP.Compat.ServerTime() + 30)
		eq(M(s, { type = "OPEN_ROUND", item = 1, kind = "REROLL", stage = "TIER", tier = 1, among = { "A" } }).r, 2)
		deepEq(M(s, { type = "CLOSE_ROUND", item = 1 }), { t = "SCLOSE", i = 1, r = 2 })
		s.items[1].proposal = { kind = "AWARD", winner = full("Bryn"), cost = 1, response = "MS", tier = 1, roll = 77,
			reasons = { "HIGHEST_ROLL" }, flags = {} }
		local prop = M(s, { type = "PROPOSAL", item = 1 })
		eq(prop.t, "SPROP"); eq(prop.w, full("Bryn")); eq(prop.tg, "member"); deepEq(prop.rc, { "HIGHEST_ROLL" })
		isNil(prop.ro, "the roll is not sent")
		eq(M(s, { type = "AWARDED", item = 1, winner = full("Bryn"), cost = 1, target = "member" }).o, "AWARDED")
		eq(M(s, { type = "REJECTED", item = 1, ["then"] = "PENDING" }).x, "PENDING")
		eq(M(s, { type = "DELIVERED", item = 1 }).o, "DELIVERED")
		eq(M(s, { type = "PAUSED" }).p, true)
		eq(M(s, { type = "RESUMED" }).p, false)
		eq(M(s, { type = "ENDED" }).t, "SEND")
		for _, kind in ipairs({ "COLLECTED", "NEXT_ROUND", "DELIVER", "NO_ADDON", "TIMER_EXPIRED", "AUTO_FAILED",
			"VOTE_CLOSED" }) do
			isNil(M(s, { type = kind, item = 1 }), kind)
		end
	end)

	it("announces the responses on offer with their tier, and the view keeps them (M4-6)", function()
		local rules = FDCP.Rules.DefaultConfig()
		local s = { id = "S1-1", ml = full("Aurel"), encounter = 601, state = "ANNOUNCING", rules = rules, items = {
			{ itemID = 19003, category = "armor", costs = { MS = 1, OS = 0.5, TMOG = 0 }, state = "PENDING" },
		} }
		local msg = S().MessageFor(s, { type = "ANNOUNCE_ITEMS" })
		deepEq(msg.rt, { MS = 1, OS = 2 }, "only the enabled responses, with their tier")
		rules.priority.responses.TMOG.enabled = true
		deepEq(S().MessageFor(s, { type = "ANNOUNCE_ITEMS" }).rt, { MS = 1, OS = 2, TMOG = 3 })
		raid({ "Bryn" })
		Mock.Advance(3)
		open(full("Bryn"), 1, { rt = { MS = 1, OS = 2 } })
		deepEq(S().view.tiers, { MS = 1, OS = 2 })
		open(full("Bryn"), 2, { rt = { MS = 1, OS = 2, TMOG = 3 } })   -- a correction sends them again
		deepEq(S().view.tiers, { MS = 1, OS = 2, TMOG = 3 })
		open(full("Bryn"), 3)
		deepEq(S().view.tiers, { MS = 1, OS = 2, TMOG = 3 }, "a message without them keeps what was said")
	end)

	it("an older master looter that sends no tiers still opens the view, and damaged tiers are refused", function()
		raid({ "Bryn" })
		Mock.Advance(3)
		open(full("Bryn"), 1)
		isNil(S().view.tiers)
		S():Reset()
		raid({ "Bryn" })
		open(full("Bryn"), 1, { rt = { ms = 1 } })
		isNil(S().view); eq(S().lastRefused, "BAD")
		open(full("Bryn"), 1, { rt = { MS = 0 } })
		isNil(S().view)
		open(full("Bryn"), 1, { rt = "MS" })
		isNil(S().view)
	end)

	it("the whispered state gives back the player's own answer with its label and note", function()
		raid({ "Bryn" })
		Mock.Advance(3)
		receive("SSTATE", { s = "S1-1", q = 3, ml = full("Bryn"), rt = { MS = 1, OS = 2 }, a = 1,
			it = { { id = 19003, st = "ROLLING" } }, rd = { i = 1, r = 1, k = "ROLL", g = "TIER", tr = 1, cl = true },
			my = { rs = "MS", lb = "BIS", n = "set ring" } }, full("Bryn"), "WHISPER")
		local a = S():MyAnswer(1)
		deepEq(a, { rs = "MS", lb = "BIS", n = "set ring" })
		eq(S().view.mine[1], "MS")
		deepEq(S().view.tiers, { MS = 1, OS = 2 })
		isNil(S():MyAnswer(2))
		S():Reset()
		raid({ "Bryn" })
		receive("SSTATE", { s = "S1-1", q = 3, ml = full("Bryn"), a = 1, it = { { id = 19003 } },
			rd = { i = 1, r = 1, k = "ROLL", cl = true }, my = { rs = "OS", lb = "nonsense", n = string.rep("x", 200) } },
			full("Bryn"), "WHISPER")
		deepEq(S():MyAnswer(1), { rs = "OS" }, "a damaged label or a long note is dropped, the answer stays")
	end)

	it("the master looter's state carries each player's own label and note", function()
		local s = { id = "S1-1", ml = full("Aurel"), encounter = 601, state = "ROLLING", active = 1, rules = FDCP.Rules.DefaultConfig(),
			net = { seq = 4, rounds = { 2 }, open = true }, items = { { itemID = 19003, category = "armor", costs = { MS = 1 },
				state = "ROLLING", round = { kind = "ROLL", stage = "TIER", tier = 1, collect = true, rolls = {} },
				responses = { [full("Bryn")] = "MS", [full("Corin")] = "OS" }, labels = { [full("Bryn")] = "BIS" },
				notes = { [full("Bryn")] = "mine" } } } }
		local msg = S().StateFor(s, full("Bryn"))
		deepEq(msg.my, { rs = "MS", lb = "BIS", n = "mine" })
		deepEq(msg.rt, { MS = 1, OS = 2 })
		deepEq(S().StateFor(s, full("Corin")).my, { rs = "OS" })
		isNil(S().StateFor(s, full("Dara")).my)
	end)

	it("a response is always the sender's own: one naming another player is forged", function()
		local r = S().ReadResponse({ s = "S1-1", i = 1, r = 1, rs = "MS", lb = "BIS", n = "big one" }, full("Bryn"))
		deepEq(r, { s = "S1-1", i = 1, r = 1, rs = "MS", lb = "BIS", n = "big one" })
		local _, code = S().ReadResponse({ s = "S1-1", i = 1, r = 1, rs = "MS", p = full("Corin") }, full("Bryn"))
		eq(code, "FORGED")
		truthy(S().ReadResponse({ s = "S1-1", i = 1, r = 1, rs = "MS", p = "Bryn" }, full("Bryn")), "naming yourself is fine")
		local bad = {
			{ s = "S1-1", i = 1, r = 1, rs = "ms" }, { s = "S1-1", i = 0, r = 1, rs = "MS" },
			{ s = "S1-1", i = 1, r = 1, rs = "MS", lb = "bis" }, { s = "S1-1", i = 1, r = 1, rs = "MS", n = string.rep("x", 81) },
			{ i = 1, r = 1, rs = "MS" },
		}
		for _, m in ipairs(bad) do
			local _, c = S().ReadResponse(m, full("Bryn"))
			eq(c, "BAD")
		end
	end)

	it("follows the master looter's session in order, ignores repeats and refuses others' control messages", function()
		raid({ "Bryn", "Corin" })
		Mock.Advance(3)
		local seen = {}
		FDCP.Bus:On("SESSION_VIEW", function(_, v, what) seen[#seen + 1] = what end, "t")
		open(full("Bryn"), 1)
		local v = S().view
		eq(v.ml, full("Bryn")); eq(v.items[1].id, 19003); eq(v.items[1].cs.MS, 1)
		receive("SROLL", { s = "S1-1", q = 2, i = 1, r = 1, k = "ROLL", g = "TIER", tr = 1, cl = true,
			de = FDCP.Compat.ServerTime() + 30 }, full("Bryn"))
		local round = S():OpenRound()
		eq(round.item, 1); eq(round.collect, true); eq(round.remaining, 30)
		Mock.Advance(10)
		eq(S():OpenRound().remaining, 20, "the timer runs on the local clock")
		receive("SROLL", { s = "S1-1", q = 2, i = 1, r = 1, k = "ROLL", cl = true }, full("Bryn"))
		eq(S().stats.dups, 1)
		receive("SCLOSE", { s = "S1-1", q = 3, i = 1, r = 1 }, full("Corin"))
		eq(S().lastRefused, "NOT_ML")
		truthy(S():OpenRound(), "Corin cannot close Bryn's round")
		receive("SCLOSE", { s = "S1-1", q = 3, i = 1, r = 1 }, full("Bryn"), "GUILD")
		eq(S().lastRefused, "DIST")
		receive("SCLOSE", { s = "S1-1", q = 3, i = 1, r = 1 }, full("Bryn"))
		isNil(S():OpenRound())
		eq(v.items[1].st, "COMPUTING")
		receive("SPROP", { s = "S1-1", q = 4, i = 1, k = "AWARD", tg = "member", w = full("Corin"), c = 1, rs = "MS",
			rc = { "HIGHEST_ROLL" } }, full("Bryn"))
		eq(v.proposal.w, full("Corin"))
		receive("SRESULT", { s = "S1-1", q = 5, i = 1, o = "AWARDED", w = full("Corin"), c = 1, tg = "member" }, full("Bryn"))
		eq(v.items[1].st, "ASSIGNED"); eq(v.items[1].w, full("Corin")); eq(v.items[1].pc, 1)
		receive("SEND", { s = "S1-1", q = 6 }, full("Bryn"))
		truthy(v.ended)
		deepEq(seen, { "OPENED", "ROLL", "CLOSED", "PROPOSAL", "RESULT", "ENDED" })
	end)

	it("refuses a session from outside the raid, and a second one while a session runs", function()
		raid({ "Bryn", "Corin" })
		Mock.Advance(3)
		open(full("Gale"), 1)
		eq(S().lastRefused, "NOT_IN_RAID")
		isNil(S().view)
		open(full("Bryn"), 1, { ml = full("Corin") })
		eq(S().lastRefused, "NOT_ML", "the opener must name himself")
		open(full("Bryn"), 1)
		truthy(S().view)
		open(full("Corin"), 1, { s = "S1-2" })
		eq(S().lastRefused, "BUSY")
		eq(S().view.ml, full("Bryn"))
		receive("SEND", { s = "S1-1", q = 2 }, full("Bryn"))
		open(full("Corin"), 1, { s = "S1-2" })
		eq(S().view.ml, full("Corin"), "after the end another master looter may open")
	end)

	it("damaged session messages are refused without an error", function()
		raid({ "Bryn" })
		Mock.Advance(3)
		open(full("Bryn"), 1, { it = { { id = -1 } } })
		isNil(S().view)
		open(full("Bryn"), 1, { it = { { id = 19003, cs = { MS = "one" } } } })
		isNil(S().view)
		open(full("Bryn"), 1)
		receive("SROLL", { s = "S1-1", q = 2, i = 9, r = 1, k = "ROLL" }, full("Bryn"))
		receive("SROLL", { s = "S1-1", q = 2, i = 1, r = 1, k = "ROLL", am = "Corin" }, full("Bryn"))
		receive("SRESULT", { s = "S1-1", q = 2, i = 1, o = "STOLEN" }, full("Bryn"))
		eq(S().stats.bad, 5)
		eq(S().view.q, 1)
	end)

	it("a gap in the sequence asks the master looter for the state by whisper", function()
		raid({ "Bryn" })
		Mock.Advance(3)
		open(full("Bryn"), 1)
		receive("SCLOSE", { s = "S1-1", q = 3, i = 1, r = 1 }, full("Bryn"))
		Mock.Advance(2)
		eq(S().stats.gaps, 1)
		local sent = sentMessages(Mock)
		local last = sent[#sent]
		eq(last.msg.t, "SSYNCQ"); eq(last.chatType, "WHISPER"); eq(last.msg.s, "S1-1")
		Mock.Advance(S().SYNC_RETRY + 1)
		eq(count(sentMessages(Mock), "SSYNCQ"), 2, "asked again: the state did not come")
		receive("SSTATE", { s = "S1-1", q = 3, ml = full("Bryn"), it = { { id = 19003, st = "COMPUTING" } }, a = 1 },
			full("Bryn"), "WHISPER")
		eq(S().view.q, 3); eq(S().view.items[1].st, "COMPUTING")
		Mock.Advance(S().SYNC_RETRY * 3)
		eq(count(sentMessages(Mock), "SSYNCQ"), 2, "no more questions once synced")
		receive("SSTATE", { s = "S1-1", q = 9, ml = full("Bryn"), it = {} }, full("Bryn"), "RAID")
		eq(S().lastRefused, "DIST", "a state comes by whisper only")
	end)

	it("a control message of an unknown session asks its sender for the state", function()
		raid({ "Bryn" })
		Mock.Advance(3)
		receive("SROLL", { s = "S1-1", q = 4, i = 1, r = 1, k = "ROLL" }, full("Bryn"))
		Mock.Advance(2)
		local sent = sentMessages(Mock)
		eq(sent[#sent].msg.t, "SSYNCQ"); eq(sent[#sent].target, full("Bryn"))
	end)

	it("the HELLO asks for the state only while no session is in view", function()
		raid({ "Bryn" })
		Mock.Advance(3)
		local hellos = {}
		for _, e in ipairs(sentMessages(Mock)) do if e.msg.t == "HELLO" then hellos[#hellos + 1] = e.msg end end
		eq(hellos[1].sq, true)
		open(full("Bryn"), 1)
		falsy(S():NeedsState())
		P():Announce()
		Mock.Advance(2)
		local sent = sentMessages(Mock)
		isNil(sent[#sent].msg.sq)
	end)

	it("Respond needs an open round that collects answers", function()
		raid({ "Bryn" })
		Mock.Advance(3)
		local _, code = S():Respond("MS")
		eq(code, "NO_SESSION")
		open(full("Bryn"), 1)
		_, code = S():Respond("MS")
		eq(code, "RESPONSES_CLOSED")
		receive("SROLL", { s = "S1-1", q = 2, i = 1, r = 1, k = "ROLL", cl = true }, full("Bryn"))
		_, code = S():Respond("ms") eq(code, "BAD_RESPONSE")
		_, code = S():Respond("MS", "bis") eq(code, "BAD_LABEL")
		_, code = S():Respond("MS", nil, string.rep("x", 81)) eq(code, "BAD_NOTE")
		truthy(S():Respond("OS"))
		truthy(S():Respond("MS", "BIS", "two-hander upgrade"))
		Mock.Advance(2)
		eq(count(sentMessages(Mock), "SRESP"), 1, "the latest answer waiting wins")
		local sent = sentMessages(Mock)
		local m = sent[#sent].msg
		eq(m.rs, "MS"); eq(m.lb, "BIS"); eq(m.n, "two-hander upgrade"); eq(m.r, 1); isNil(m.p)
		eq(S():OpenRound().mine, "MS")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The network

-- The master looter's controller, a stand-in for App/SessionController.lua (M4-4): SessionFSM on the ML's client, the
-- SESSION_INPUT events stepped, the effects published. The session table survives a /reload as the SavedVariables keep
-- it (a plain-data round trip).
local function ser(v)
	local t = type(v)
	if t == "number" then return string.format("%.17g", v) end
	if t == "string" then return string.format("%q", v) end
	if t == "boolean" then return tostring(v) end
	local parts = {}
	for k, x in pairs(v) do parts[#parts + 1] = "[" .. ser(k) .. "]=" .. ser(x) end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function host(c, names, rules)
	local h = { c = c, inputs = {}, refused = {} }
	local present = {}
	for _, n in ipairs(names) do present[full(n)] = true end
	function h.A() return c.addon() end
	function h.attach(s)
		local A = h.A()
		h.s = s
		h.L = h.L or A.Ledger.New()
		A.Bus:On("SESSION_INPUT", function(_, input)
			h.inputs[#h.inputs + 1] = input
			h.step(input)
		end, h)
		A.Protocol.Session:Host(s)
	end
	function h.step(input)
		local A = h.A()
		input.ts = input.ts or A.Compat.Now()
		local ok, code, effects = A.SessionFSM.Step(h.s, input, { ledger = h.L })
		if not ok then h.refused[#h.refused + 1] = code return nil, code end
		A.Protocol.Session:Publish(effects, h.s)
		return true
	end
	function h.ml(kind, extra)
		local input = extra or {}
		input.type, input.by = kind, full(c.name)
		assert(h.step(input), "refused " .. kind .. ": " .. tostring(h.refused[#h.refused]))
	end
	function h.reload(net)
		local saved = assert(loadstring("return " .. ser(h.s)))()
		net:Reload(c.name)
		h.attach((h.A().SessionFSM.Restore(saved)))
	end
	local A = c.addon()
	h.attach(assert(A.SessionFSM.New({ id = "S1-1", season = "S1", ml = full(c.name), ts = A.Compat.Now(),
		encounter = 601, rules = rules or manual(), present = present, addon = present })))
	return h
end

local function view(c) return c.addon().Protocol.Session.view end

describe("simulated session", function()
	local NAMES = { "Aurel", "Bryn", "Corin", "Dara", "Edda" }   -- Edda has no addon

	local function standard()
		local net = Sim.new{ realm = REALM }
		local c = {}
		for _, n in ipairs({ "Aurel", "Bryn", "Corin", "Dara" }) do c[n] = net:Client(n) end
		net:Raid(NAMES)
		net:Advance(3)
		local h = host(c.Aurel, { "Aurel", "Bryn", "Corin", "Dara" })
		return net, c, h
	end

	local function started(items)
		local net, c, h = standard()
		h.step({ type = "LOOT_OPENED", items = items or { RING, SWORD }, encounter = 601 })
		h.ml("START")
		h.ml("OPEN_ROLL")
		net:Advance(3)
		return net, c, h
	end

	it("a whole item: announced, answered from every client, proposed, awarded, and the session closed", function()
		local net, c, h = standard()
		h.step({ type = "LOOT_OPENED", items = { RING, SWORD }, encounter = 601 })
		net:Advance(2)
		isNil(view(c.Bryn), "collecting is the master looter's business"); eq(#h.refused, 0, tostring(h.refused[1])); eq(h.s.state, "COLLECTING")
		h.ml("START")
		net:Advance(2)
		for _, n in ipairs({ "Aurel", "Bryn", "Corin", "Dara" }) do
			local v = view(c[n])
			truthy(v, n .. " sees the session")
			eq(#v.items, 2); eq(v.items[1].id, 19003); eq(v.items[2].cs.MS, 2); eq(v.ml, full("Aurel"))
		end
		h.ml("OPEN_ROLL")
		net:Advance(2)
		local round = c.Bryn.addon().Protocol.Session:OpenRound()
		eq(round.item, 1); truthy(round.collect)
		truthy(round.remaining > 25 and round.remaining <= 30, "the timer arrived in server time")
		truthy(c.Bryn.addon().Protocol.Session:Respond("MS", "BIS", "ring of the set"))
		truthy(c.Corin.addon().Protocol.Session:Respond("OS"))
		truthy(c.Dara.addon().Protocol.Session:Respond("PASS"))
		truthy(c.Aurel.addon().Protocol.Session:Respond("OS"), "the master looter answers like everybody")
		net:Advance(3)
		local item = h.s.items[1]
		eq(item.responses[full("Bryn")], "MS"); eq(item.responses[full("Corin")], "OS")
		eq(item.responses[full("Dara")], "PASS"); eq(item.responses[full("Aurel")], "OS")
		eq(#h.inputs, 4)
		for _, input in ipairs(h.inputs) do eq(input.type, "RESPONSE", "nothing from the network becomes a roll") end
		local corinSees = view(c.Corin).responses[1][full("Bryn")]
		eq(corinSees.rs, "MS"); eq(corinSees.lb, "BIS"); eq(corinSees.n, "ring of the set")
		-- the rolls come from the chat (M4-3); here the controller hands them over
		h.step({ type = "ROLL", player = full("Bryn"), value = 61, min = 1, max = 100 })
		h.ml("CLOSE_ROUND")
		net:Advance(2)
		local v = view(c.Dara)
		eq(v.items[1].st, "PROPOSAL")
		eq(v.proposal.w, full("Bryn")); eq(v.proposal.c, 1); eq(v.proposal.rs, "MS")
		h.ml("CONFIRM")
		net:Advance(2)
		for _, n in ipairs({ "Aurel", "Bryn", "Corin", "Dara" }) do
			local w = view(c[n])
			eq(w.items[1].st, "ASSIGNED", n); eq(w.items[1].w, full("Bryn")); eq(w.items[1].pc, 1); isNil(w.a)
		end
		eq(FDCP.Ledger.Count(h.L), 1, "ITEM_AWARDED written once, by the master looter")
		h.ml("END")
		net:Advance(2)
		truthy(view(c.Corin).ended)
		eq(view(c.Corin).q, h.s.net.seq, "every message arrived")
		for _, n in ipairs({ "Bryn", "Corin", "Dara" }) do
			local st = c[n].addon().Protocol.Session.stats
			eq(st.gaps, 0, n); eq(st.refused, 0, n); eq(st.forged, 0, n)
		end
		-- the order of the master looter's messages on RAID
		local order = {}
		for _, t in ipairs(types(sentMessages(c.Aurel.Mock))) do
			if t ~= "HELLO" and t ~= "HELLOQ" and t ~= "SRESP" then order[#order + 1] = t end
		end
		deepEq(order, { "SOPEN", "SROLL", "SCLOSE", "SPROP", "SRESULT", "SEND" })
	end)

	it("a forged response for another player is refused and the real one still counts", function()
		local net, c, h = started()
		local B = c.Bryn.addon()
		local v = view(c.Bryn)
		-- a modified addon: Bryn answers in Corin's name
		B.Transport:Send("RAID", { t = "SRESP", s = v.s, i = 1, r = 1, rs = "MS", p = full("Corin") }, { prio = "ALERT" })
		net:Advance(2)
		isNil(h.s.items[1].responses[full("Corin")])
		isNil(h.s.items[1].responses[full("Bryn")], "a forged message counts for nobody")
		eq(c.Aurel.addon().Protocol.Session.stats.forged, 1)
		isNil(view(c.Dara).responses[1][full("Corin")], "the other views refuse it too")
		-- a stale round and a roll inside a response
		B.Transport:Send("RAID", { t = "SRESP", s = v.s, i = 1, r = 7, rs = "MS" }, { prio = "ALERT" })
		B.Transport:Send("RAID", { t = "SRESP", s = v.s, i = 1, r = 1, rs = "MS", roll = 100, value = 100 }, { prio = "ALERT" })
		net:Advance(2)
		eq(c.Aurel.addon().Protocol.Session.stats.stale, 1)
		eq(h.s.items[1].responses[full("Bryn")], "MS", "the sender's own answer is taken")
		eq(#h.s.items[1].round.rolls, 0, "a roll never comes from an addon message")
		-- Corin answers for himself
		truthy(c.Corin.addon().Protocol.Session:Respond("OS"))
		net:Advance(2)
		eq(h.s.items[1].responses[full("Corin")], "OS")
		-- a raider tries to close the round
		B.Transport:Send("RAID", { t = "SCLOSE", s = v.s, q = h.s.net.seq + 1, i = 1, r = 1 }, { prio = "ALERT" })
		net:Advance(2)
		truthy(c.Corin.addon().Protocol.Session:OpenRound(), "only the master looter closes it")
		eq(c.Corin.addon().Protocol.Session.lastRefused, "NOT_ML")
	end)

	it("a raider who reloads mid-round gets the state back by whisper, with their own answer", function()
		local net, c, h = started()
		truthy(c.Bryn.addon().Protocol.Session:Respond("MS", "BIG_UPGRADE"))
		net:Advance(2)
		local before = view(c.Bryn).q
		net:Reload("Bryn")
		isNil(view(c.Bryn))
		net:Advance(4)
		local v = view(c.Bryn)
		truthy(v, "resynced")
		eq(v.q, before); eq(v.a, 1); eq(#v.items, 2)
		local round = c.Bryn.addon().Protocol.Session:OpenRound()
		eq(round.mine, "MS", "their own answer came back")
		truthy(round.remaining > 20 and round.remaining < 30)
		local whispers = 0
		for _, e in ipairs(sentMessages(c.Aurel.Mock)) do
			if e.msg.t == "SSTATE" then
				whispers = whispers + 1
				eq(e.chatType, "WHISPER"); eq(e.target, full("Bryn"))
			end
		end
		eq(whispers, 1, "only the one who reloaded")
		-- the session goes on and Bryn follows it without a gap
		h.ml("CLOSE_ROUND")
		net:Advance(2)
		eq(view(c.Bryn).items[1].st, "PROPOSAL")
		eq(c.Bryn.addon().Protocol.Session.stats.gaps, 0)
		eq(c.Bryn.addon().Protocol.Session.stats.synced, 1)
	end)

	it("a late joiner is brought into the session", function()
		local net, c, h = started()
		c.Fenn = net:Client("Fenn")
		net:Raid({ "Aurel", "Bryn", "Corin", "Dara", "Edda", "Fenn" })
		net:Advance(4)
		local v = view(c.Fenn)
		truthy(v)
		eq(v.ml, full("Aurel")); truthy(c.Fenn.addon().Protocol.Session:OpenRound())
		-- the frozen raid of the open item does not include them (§4.1: from the next item)
		truthy(c.Fenn.addon().Protocol.Session:Respond("MS"))
		net:Advance(2)
		isNil(h.s.items[1].responses[full("Fenn")])
		eq(h.refused[#h.refused], "NOT_PRESENT")
	end)

	it("the master looter reloads: the saved session gives the view back and the raid follows without a gap", function()
		local net, c, h = started()
		truthy(c.Bryn.addon().Protocol.Session:Respond("MS"))
		net:Advance(2)
		h.reload(net)
		net:Advance(3)
		local v = view(c.Aurel)
		truthy(v); eq(v.a, 1); eq(v.q, h.s.net.seq)
		h.step({ type = "ROLL", player = full("Bryn"), value = 40, min = 1, max = 100 })
		h.ml("CLOSE_ROUND")
		net:Advance(2)
		eq(view(c.Corin).items[1].st, "PROPOSAL")
		eq(view(c.Corin).proposal.w, full("Bryn"))
		eq(c.Corin.addon().Protocol.Session.stats.gaps, 0)
		eq(view(c.Aurel).items[1].st, "PROPOSAL")
	end)

	it("during a chat lockdown the master looter's messages wait and arrive in order", function()
		local net, c, h = standard()
		h.step({ type = "LOOT_OPENED", items = { RING }, encounter = 601 })
		c.Aurel.Mock.chat.lockdown = true
		h.ml("START")
		h.ml("OPEN_ROLL")
		h.ml("PAUSE")
		net:Advance(20)
		isNil(view(c.Bryn), "nothing left the master looter's client")
		truthy(view(c.Aurel), "the master looter's own view is up to date")
		c.Aurel.Mock.chat.lockdown = false
		net:Advance(5)
		local v = view(c.Bryn)
		truthy(v); eq(v.q, 3); truthy(v.paused)
		local round = c.Bryn.addon().Protocol.Session:OpenRound()
		truthy(round); truthy(round.remaining and round.remaining > 0, "paused: the time left is kept")
		h.ml("RESUME")
		net:Advance(2)
		falsy(view(c.Bryn).paused)
		eq(c.Bryn.addon().Protocol.Session.stats.gaps, 0)
		-- a raider in lockdown: the answer waits too, and the latest one wins
		c.Corin.Mock.chat.lockdown = true
		truthy(c.Corin.addon().Protocol.Session:Respond("OS"))
		truthy(c.Corin.addon().Protocol.Session:Respond("MS"))
		net:Advance(5)
		isNil(h.s.items[1].responses[full("Corin")])
		c.Corin.Mock.chat.lockdown = false
		net:Advance(3)
		eq(h.s.items[1].responses[full("Corin")], "MS")
		eq(count(sentMessages(c.Corin.Mock), "SRESP"), 1)
	end)

	it("a lockdown longer than a message's life loses messages: the gap is healed by a state", function()
		local net, c, h = standard()
		h.step({ type = "LOOT_OPENED", items = { RING }, encounter = 601 })
		h.ml("START")
		net:Advance(2)
		eq(view(c.Bryn).q, 1)
		c.Aurel.Mock.chat.lockdown = true
		h.ml("OPEN_ROLL")
		net:Advance(c.Aurel.addon().Transport.TTL.RAID + 5)   -- the SROLL expires in the queue
		c.Aurel.Mock.chat.lockdown = false
		h.ml("PAUSE")
		net:Advance(4)
		local B = c.Bryn.addon().Protocol.Session
		eq(B.stats.gaps, 1)
		eq(B.stats.synced, 1)
		local v = view(c.Bryn)
		eq(v.q, h.s.net.seq); eq(v.a, 1); truthy(v.paused)
		truthy(B:OpenRound(), "the lost round is back")
	end)

	it("plan B: during a boss nothing is sent; the session reaches the raid after ENCOUNTER_END", function()
		local net, c, h = standard()
		h.step({ type = "LOOT_OPENED", items = { RING }, encounter = 601 })
		c.Aurel.Mock.encounter.Start(602, "Next boss")
		h.ml("START")
		net:Advance(30)
		isNil(view(c.Dara))
		c.Aurel.Mock.encounter.End(602, "Next boss", true)
		net:Advance(3)
		truthy(view(c.Dara))
		eq(view(c.Dara).items[1].id, 19003)
	end)

	it("automatic phases: the round closes when everybody answered and rolled, the next item opens by itself", function()
		local net = Sim.new{ realm = REALM }
		local c = {}
		for _, n in ipairs({ "Aurel", "Bryn", "Corin" }) do c[n] = net:Client(n) end
		net:Raid({ "Aurel", "Bryn", "Corin" })
		net:Advance(3)
		local rules = FDCP.Rules.DefaultConfig()
		rules.session.autoAdvance = true
		local h = host(c.Aurel, { "Aurel", "Bryn", "Corin" }, rules)
		h.step({ type = "LOOT_OPENED", items = { RING, SWORD }, encounter = 601 })
		h.ml("START")
		net:Advance(2)
		eq(view(c.Bryn).a, 1, "the first roll opened by itself")
		c.Aurel.addon().Protocol.Session:Respond("PASS")
		c.Bryn.addon().Protocol.Session:Respond("MS")
		c.Corin.addon().Protocol.Session:Respond("PASS")
		net:Advance(2)
		h.step({ type = "ROLL", player = full("Bryn"), value = 12, min = 1, max = 100 })
		net:Advance(2)
		local v = view(c.Corin)
		eq(v.items[1].st, "PROPOSAL", "closed because everybody had done their part")
		h.ml("CONFIRM")
		net:Advance(2)
		v = view(c.Corin)
		eq(v.items[1].st, "ASSIGNED"); eq(v.a, 2, "the sword opened by itself")
		truthy(c.Corin.addon().Protocol.Session:OpenRound().collect)
		eq(c.Corin.addon().Protocol.Session.stats.gaps, 0)
	end)
end)
