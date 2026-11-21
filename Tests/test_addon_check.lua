-- Addon presence (M3-5): Net/Protocol.lua (HELLOQ / HELLO on RAID) and App/AddonCheck.lua (the states, the summary and
-- the candidates rule for M4), docs/ANALISI.md §4.1, §8.4. The first groups run on one client; the scenarios run on
-- the network simulator (Tests/sim/sim.lua): several whole clients in one raid, players without the addon, an old
-- version, an incompatible protocol, an offline member, a /reload, a boss encounter.
local function P() return FDCP.Protocol end
local function AC() return FDCP.AddonCheck end
local function Codec() return FDCP.Codec end

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end

local function onRealm(M) M.player.name, M.player.realm = "Aurel", REALM end

-- The states of a client's AddonCheck as { [short name] = state }.
local function states(check)
	local out = {}
	for _, row in ipairs(check:Rows()) do out[row.name:match("^([^%-]+)")] = row.state end
	return out
end

-- The decoded addon messages a client sent, oldest first.
local function sentMessages(Mock)
	local out = {}
	for _, e in ipairs(Mock.chat.SentWithPrefix("FDCP1")) do
		local text = e.message
		if text:byte(1) == 4 then text = text:sub(2) end   -- AceComm escape byte
		local msg = Codec():Decode(text)
		if msg then out[#out + 1] = { msg = msg, chatType = e.chatType } end
	end
	return out
end

local function count(list, t)
	local n = 0
	for _, e in ipairs(list) do if e.msg.t == t then n = n + 1 end end
	return n
end

describe("versions", function()
	it("parses release versions and refuses anything else", function()
		deepEq(P().ParseVersion("1.2.3"), { 1, 2, 3 })
		deepEq(P().ParseVersion("v1.10"), { 1, 10 })
		deepEq(P().ParseVersion("2.0.0-beta2"), { 2, 0, 0 })
		isNil(P().ParseVersion("dev"))
		isNil(P().ParseVersion("@project-version@"))
		isNil(P().ParseVersion("1..2"))
		isNil(P().ParseVersion(12))
	end)

	it("compares versions part by part, missing parts are zero", function()
		eq(P().CompareVersions("1.2.0", "1.10.0"), -1)
		eq(P().CompareVersions("1.2", "1.2.0"), 0)
		eq(P().CompareVersions("v2.0.1", "2.0.0"), 1)
		isNil(P().CompareVersions("dev", "1.0.0"), "an unpackaged checkout is never older nor newer")
	end)

	it("the unpackaged TOC gives the dev version; the override wins", function()
		eq(P().AddonVersion(), "dev")
		P().addonVersion = "1.4.0"
		eq(P().AddonVersion(), "1.4.0")
		eq(P().Mine().av, "1.4.0")
		eq(P().Mine().pv, P().VERSION)
	end)

	it("classifies an answer: compatible newer, same, older; incompatible both ways", function()
		local mine = { av = "1.2.0", pv = 2, pm = 2 }
		eq(P().Classify({ av = "1.3.0", pv = 2, pm = 2 }, mine), "ACTIVE")
		eq(P().Classify({ av = "1.2.0", pv = 3, pm = 2 }, mine), "ACTIVE")
		eq(P().Classify({ av = "1.1.0", pv = 2, pm = 1 }, mine), "OUTDATED")
		eq(P().Classify({ av = "dev", pv = 2, pm = 2 }, mine), "ACTIVE")
		eq(P().Classify({ av = "1.0.0", pv = 1, pm = 1 }, mine), "INCOMPATIBLE", "too old a protocol")
		eq(P().Classify({ av = "3.0.0", pv = 4, pm = 3 }, mine), "INCOMPATIBLE", "it no longer speaks ours")
	end)

	it("reads a HELLO and refuses damaged ones", function()
		deepEq(P().ReadHello({ av = "1.0", pv = 2 }), { av = "1.0", pv = 2, pm = 2 })
		deepEq(P().ReadHello({ av = "1.0", pv = 2, pm = 1 }), { av = "1.0", pv = 2, pm = 1 })
		isNil(P().ReadHello({ av = "1.0" }), "no protocol version")
		isNil(P().ReadHello({ av = "1.0", pv = 1.5 }))
		isNil(P().ReadHello({ av = "1.0", pv = 0 }))
		isNil(P().ReadHello({ av = "1.0", pv = 2, pm = 3 }), "oldest above own")
		isNil(P().ReadHello({ av = "", pv = 1 }))
		isNil(P().ReadHello({ av = string.rep("9", 40), pv = 1 }))
	end)
end)

describe("messages on one client", function()
	before_boot(onRealm)

	local function receive(t, fields, sender, dist)
		return Mock.chat.Receive("FDCP1", Codec():Encode(t, fields), dist or "RAID", sender)
	end

	local function raid(names)
		local members = {}
		for i, n in ipairs(names) do members[i] = { name = n } end
		Mock.group.Set{ raid = true, members = members }
	end

	it("answers a question to everybody and one that names the player, not one for others", function()
		raid({ "Bryn", "Corin" })
		Mock.Advance(3)
		local before = count(sentMessages(Mock), "HELLO")
		eq(before, 1, "the HELLO said on entering the raid")
		receive("HELLOQ", {}, full("Bryn"))
		Mock.Advance(2)
		eq(count(sentMessages(Mock), "HELLO"), 2)
		receive("HELLOQ", { w = { "Corin-Camelot" } }, full("Bryn"))
		Mock.Advance(2)
		eq(count(sentMessages(Mock), "HELLO"), 2, "not named: no answer")
		receive("HELLOQ", { w = { "Corin", "Aurel" } }, full("Bryn"))   -- short names are on the sender's realm
		Mock.Advance(2)
		eq(count(sentMessages(Mock), "HELLO"), 3)
		local hello = sentMessages(Mock)[3].msg
		eq(hello.av, "dev"); eq(hello.pv, P().VERSION); eq(hello.pm, P().MIN)
		eq(sentMessages(Mock)[3].chatType, "RAID")
	end)

	it("ignores presence messages outside RAID and damaged ones", function()
		raid({ "Bryn" })
		Mock.Advance(3)
		receive("HELLO", { av = "1.0", pv = 1 }, full("Bryn"), "GUILD")
		receive("HELLO", { av = "1.0" }, full("Bryn"))
		receive("HELLOQ", { w = "Aurel" }, full("Bryn"))
		receive("HELLOQ", {}, full("Bryn"), "WHISPER")
		Mock.Advance(2)
		eq(P().stats.bad, 4)
		eq(P().stats.hellos, 0)
		eq(count(sentMessages(Mock), "HELLO"), 1, "only the HELLO of the raid join")
		eq(AC():StateOf(full("Bryn")), "WAITING")
	end)

	it("the summary reads 37/40 with three players without the addon", function()
		local names = {}
		for i = 1, 39 do names[i] = "Raider" .. i end
		raid(names)
		Mock.Advance(2)
		-- the raid leader's question reaches this client too; 36 of the 39 others answer
		receive("HELLOQ", {}, full(names[1]))
		for i = 4, 39 do receive("HELLO", { av = "dev", pv = P().VERSION }, full(names[i])) end
		Mock.Advance(2)
		local s = AC():Summary()
		eq(s.total, 40)
		eq(s.with, 37)
		eq(s.WAITING, 3, "asked a moment ago")
		Mock.Advance(AC().TIMEOUT)
		s = AC():Summary()
		eq(s.MISSING, 3)
		eq(s.text, "37/40 with the addon")
		local n = 0
		for _ in pairs(AC():Candidates()) do n = n + 1 end
		eq(n, 37)
	end)

	it("speaks Italian in the summary", function()
		T.boot(function(M) onRealm(M) M.player.locale = "itIT" end)
		raid({ "Bryn" })
		Mock.Advance(2)
		eq(AC():Summary().text, "1/2 con l'addon")
	end)

	it("a request needs a raid and the permission; the Guild Master has it", function()
		local ok, code = AC():Request()
		isNil(ok); eq(code, "NOT_IN_RAID")
		raid({ "Bryn" })
		Mock.Advance(2)
		ok, code = AC():Request()
		isNil(ok); eq(code, "PENDING", "no guild roster: no rank")
		Mock.guild.Set{ name = "Dragons", myRank = 0 }
		Mock.Advance(3)
		truthy(AC():Request())
		Mock.Advance(2)
		eq(count(sentMessages(Mock), "HELLOQ"), 1)
		Mock.guild.SetMyRank(3)
		Mock.Advance(3)
		ok, code = AC():Request()
		isNil(ok); eq(code, "RANK_TOO_LOW")
	end)

	it("leaving the raid empties the table", function()
		raid({ "Bryn" })
		Mock.Advance(2)
		receive("HELLO", { av = "dev", pv = 1 }, full("Bryn"))
		eq(AC():Summary().with, 2)
		Mock.group.Leave()
		Mock.Advance(2)
		eq(AC():Summary().total, 0)
		falsy(AC():CanRoll(full("Bryn")))
	end)

	it("/fdcp debug has the summary line in both languages", function()
		raid({ "Bryn" })
		Mock.Advance(2)
		local lines = AC():DebugLines()
		contains(lines[1], "1/2 with the addon")
		contains(lines[1], "own version dev")
	end)

	it("every state has words in both languages", function()
		eq(AC().StateLabel("MISSING"), "Addon not active")
		eq(AC().StateLabel("OUTDATED"), "Needs an update")
		T.boot(function(M) onRealm(M) M.player.locale = "itIT" end)
		eq(AC().StateLabel("MISSING"), "Addon non attivo")
		eq(AC().StateLabel("WAITING"), "In attesa")
		raid({ "Bryn" })
		Mock.Advance(2)
		eq(AC():Rows()[1].label, "Attivo")
	end)
end)

describe("simulated raids", function()
	-- Aurel runs the night (the checker); the others are clients or players without the addon.
	local function checker(c) c.addon().AddonCheck.IsChecker = function() return true end end

	local function standard()
		local net = Sim.new{ realm = REALM }
		local c = {
			Aurel = net:Client("Aurel", { version = "1.2.0", pv = 2, pm = 2, after = checker }),
			Bryn = net:Client("Bryn", { version = "1.2.0", pv = 2, pm = 2 }),
			Corin = net:Client("Corin", { version = "1.1.0", pv = 2, pm = 1 }),   -- old, compatible
			Dara = net:Client("Dara", { version = "0.9.0", pv = 1, pm = 1 }),     -- protocol too old
		}
		net:Raid({ "Aurel", "Bryn", "Corin", "Dara", "Edda" })                    -- Edda has no addon
		return net, c
	end

	it("old, incompatible and missing addons give the right states on every client", function()
		local net, c = standard()
		net:Advance(3)
		truthy(c.Aurel.addon().AddonCheck:Request())
		net:Advance(3)
		local seen = states(c.Aurel.addon().AddonCheck)
		eq(seen.Aurel, "ACTIVE"); eq(seen.Bryn, "ACTIVE"); eq(seen.Corin, "OUTDATED"); eq(seen.Dara, "INCOMPATIBLE")
		eq(seen.Edda, "WAITING", "asked a moment ago")
		net:Advance(c.Aurel.addon().AddonCheck.TIMEOUT)
		seen = states(c.Aurel.addon().AddonCheck)
		eq(seen.Edda, "MISSING")
		local s = c.Aurel.addon().AddonCheck:Summary()
		eq(s.text, "3/5 with the addon")
		eq(s.ACTIVE, 2); eq(s.OUTDATED, 1); eq(s.INCOMPATIBLE, 1); eq(s.MISSING, 1); eq(s.WAITING, 0)
		-- Bryn heard the same question and the same answers: the same table
		local bryn = states(c.Bryn.addon().AddonCheck)
		eq(bryn.Aurel, "ACTIVE"); eq(bryn.Corin, "OUTDATED"); eq(bryn.Dara, "INCOMPATIBLE"); eq(bryn.Edda, "MISSING")
		-- seen from the old client, the new ones are newer (active) and Dara is still incompatible with Corin's pm 1? no:
		-- Corin speaks 1 and 2, so Dara (pv 1) is compatible for Corin, and Corin's version is newer than Dara's
		local corin = states(c.Corin.addon().AddonCheck)
		eq(corin.Aurel, "ACTIVE"); eq(corin.Dara, "OUTDATED")
	end)

	it("the candidates are only the members with a compatible addon, in the shape SessionFSM expects", function()
		local net, c = standard()
		net:Advance(3)
		c.Aurel.addon().AddonCheck:Request()
		net:Advance(20)
		local check = c.Aurel.addon().AddonCheck
		deepEq(check:Candidates(), { [full("Aurel")] = true, [full("Bryn")] = true, [full("Corin")] = true })
		truthy(check:CanRoll(full("Corin")))
		falsy(check:CanRoll(full("Dara")))
		falsy(check:CanRoll(full("Edda")))
		falsy(check:CanRoll(full("Nobody")))
		local input = check:RaidInput()
		eq(#(function() local l = {} for k in pairs(input.present) do l[#l + 1] = k end return l end)(), 5)
		-- the session machine takes it as it is and refuses a response from the missing player
		local F = c.Aurel.addon().SessionFSM
		local s = assert(F.New({ id = "S1-1", season = "S1", ml = full("Aurel"), ts = 1, present = input.present,
			addon = input.addon }))
		local ok = F.Step(s, { type = "SET_RAID", ts = 2, present = input.present, addon = input.addon }, {})
		truthy(ok)
		eq(s.raid.addon[full("Edda")], nil)
		eq(s.raid.addon[full("Corin")], true)
	end)

	it("everybody says HELLO on entering the raid, so the states are known before any question", function()
		local net, c = standard()
		net:Advance(3)
		local seen = states(c.Bryn.addon().AddonCheck)
		eq(seen.Aurel, "ACTIVE"); eq(seen.Corin, "OUTDATED"); eq(seen.Dara, "INCOMPATIBLE")
		eq(seen.Edda, "WAITING", "never asked: still waiting, not yet 'not active'")
		eq(net:SentBy("Bryn", "RAID"), 2, "the HELLO of the join and the answer to the runner's question")
	end)

	it("an offline member waits and is asked when back online; a newcomer is asked alone", function()
		local net = Sim.new{ realm = REALM }
		local a = net:Client("Aurel", { after = checker })
		net:Client("Bryn")
		local fenn = net:Client("Fenn")
		net:Raid({ "Aurel", "Bryn", "Fenn" }, { offline = { Fenn = true } })
		net:Advance(3)
		a.addon().AddonCheck:Request()
		net:Advance(20)
		local check = a.addon().AddonCheck
		eq(check:StateOf(full("Fenn")), "WAITING", "offline: never 'not active'")
		-- Fenn's own client said HELLO (it is a simulated client), but the roster says offline: still waiting
		local bryn = net:SentBy("Bryn", "RAID")
		net:Raid({ "Aurel", "Bryn", "Fenn" })
		net:Advance(3)
		eq(check:StateOf(full("Fenn")), "ACTIVE")
		eq(net:SentBy("Bryn", "RAID"), bryn, "Bryn was not asked again")
		-- a newcomer joins: one question naming only them
		net:Client("Gale")
		local questions = 0
		for _, e in ipairs(sentMessages(a.Mock)) do if e.msg.t == "HELLOQ" then questions = questions + 1 end end
		net:Raid({ "Aurel", "Bryn", "Fenn", "Gale" })
		net:Advance(3)
		local sent = sentMessages(a.Mock)
		local last = sent[#sent].msg
		eq(last.t, "HELLOQ")
		deepEq(last.w, { full("Gale") })
		eq(count(sent, "HELLOQ"), questions + 1)
		eq(net:SentBy("Bryn", "RAID"), bryn, "Bryn does not answer a question for Gale")
		eq(check:StateOf(full("Gale")), "ACTIVE")
	end)

	it("a stale answer does not keep a player active after they disable the addon", function()
		local net, c = standard()
		net:Advance(3)
		eq(c.Aurel.addon().AddonCheck:StateOf(full("Bryn")), "ACTIVE")
		net:Drop("Bryn")   -- Bryn disables the addon and reloads: nothing answers any more
		c.Aurel.addon().AddonCheck:Request()
		net:Advance(3)
		eq(c.Aurel.addon().AddonCheck:StateOf(full("Bryn")), "WAITING")
		net:Advance(c.Aurel.addon().AddonCheck.TIMEOUT)
		eq(c.Aurel.addon().AddonCheck:StateOf(full("Bryn")), "MISSING")
		falsy(c.Aurel.addon().AddonCheck:Candidates()[full("Bryn")])
	end)

	it("a player who installs the addon and logs in comes back without being asked", function()
		local net, c = standard()
		net:Advance(3)
		c.Aurel.addon().AddonCheck:Request()
		net:Advance(20)
		eq(c.Aurel.addon().AddonCheck:StateOf(full("Edda")), "MISSING")
		local questions = count(sentMessages(c.Aurel.Mock), "HELLOQ")
		net:Client("Edda", { version = "1.2.0", pv = 2, pm = 2 })
		net:Advance(3)
		eq(c.Aurel.addon().AddonCheck:StateOf(full("Edda")), "ACTIVE")
		eq(count(sentMessages(c.Aurel.Mock), "HELLOQ"), questions, "no new question")
		truthy(c.Aurel.addon().AddonCheck:Candidates()[full("Edda")])
	end)

	it("a /reload says HELLO again and the checker's table is rebuilt from the raid", function()
		local net, c = standard()
		net:Advance(3)
		local before = net:SentBy("Corin", "RAID")
		net:Reload("Corin")
		net:Advance(3)
		eq(net:SentBy("Corin", "RAID"), before + 1)
		net:Reload("Aurel")
		net:Advance(3)
		local check = c.Aurel.addon().AddonCheck
		check.IsChecker = function() return true end
		eq(check:Summary().total, 5)
		check:Request()
		net:Advance(20)
		local seen = states(check)
		eq(seen.Bryn, "ACTIVE"); eq(seen.Corin, "OUTDATED"); eq(seen.Dara, "INCOMPATIBLE"); eq(seen.Edda, "MISSING")
	end)

	it("a question during a boss waits, and the time to answer starts when it leaves", function()
		local net, c = standard()
		net:Advance(3)
		local asked = count(sentMessages(c.Aurel.Mock), "HELLOQ")
		eq(asked, 1, "the question of the raid join")
		c.Aurel.Mock.encounter.Start(601, "Boss")
		net:Raid({ "Aurel", "Bryn", "Corin", "Dara", "Edda", "Gale" })   -- Gale, without the addon, joins mid-fight
		net:Advance(60)
		eq(count(sentMessages(c.Aurel.Mock), "HELLOQ"), asked, "held during the encounter")
		eq(c.Aurel.addon().AddonCheck:StateOf(full("Gale")), "WAITING", "not asked yet")
		c.Aurel.Mock.encounter.End(601, "Boss", true)
		net:Advance(3)
		local sent = sentMessages(c.Aurel.Mock)
		eq(count(sent, "HELLOQ"), asked + 1)
		deepEq(sent[#sent].msg.w, { full("Gale") })
		eq(c.Aurel.addon().AddonCheck:StateOf(full("Gale")), "WAITING")
		net:Advance(c.Aurel.addon().AddonCheck.TIMEOUT)
		eq(c.Aurel.addon().AddonCheck:StateOf(full("Gale")), "MISSING")
	end)

	it("the runner asks the whole raid when the night opens; nobody else asks by themself", function()
		local net = Sim.new{ realm = REALM }
		local a = net:Client("Aurel")
		local b = net:Client("Bryn")
		net:Raid({ "Aurel", "Bryn", "Corin" })
		net:Advance(3)
		eq(count(sentMessages(a.Mock), "HELLOQ"), 0)
		b.addon().Bus:Emit("NIGHT_OPENED", { author = full("Aurel") })   -- Bryn hears of a night that is not his
		a.addon().Bus:Emit("NIGHT_OPENED", { author = full("Aurel") })
		net:Advance(3)
		eq(count(sentMessages(a.Mock), "HELLOQ"), 1)
		eq(count(sentMessages(b.Mock), "HELLOQ"), 0)
		isNil(sentMessages(a.Mock)[#sentMessages(a.Mock)].msg.w, "a question to everybody")
		net:Advance(20)
		eq(b.addon().AddonCheck:StateOf(full("Corin")), "MISSING")
	end)

	it("every change reaches the bus with the summary", function()
		local net, c = standard()
		local seen = {}
		c.Aurel.addon().Bus:On("ADDON_CHECK_CHANGED", function(_, s) seen[#seen + 1] = s end)
		net:Advance(3)
		c.Aurel.addon().AddonCheck:Request()
		net:Advance(20)
		truthy(#seen >= 5)
		eq(seen[#seen].MISSING, 1, "the timeout refreshes the states by itself")
	end)
end)
