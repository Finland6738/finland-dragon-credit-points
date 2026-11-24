-- Adding players to the roster (fix/roster-join, docs/ANALISI.md §6.1): the player's request on the network (GUILD to the
-- officers, the officers' answer by whisper, the decision on GUILD), the officers' inbox, the approval into the ledger and
-- its sync, the officers' direct addition and "Add the raid group", dedupe, throttling and trust, the windows on the mock
-- client, and the absence of the faction switch (one guild is one faction in game).
-- On the simulator Aurel is the Guild Master, Bryn an officer (rank 1), Corin and Dara members (rank 3), Gale a new member
-- (rank 3, a priest) who is not in the pool.
local REALM = "Camelot"
local SEASON = "S1"
local function full(name) return name .. "-" .. REALM end
local RANKS = { Aurel = 0, Bryn = 1, Corin = 3, Dara = 3, Gale = 3 }
local CLASSES = { Aurel = "WARRIOR", Bryn = "PALADIN", Corin = "PRIEST", Dara = "MAGE", Gale = "PRIEST" }
local NAMES = { "Aurel", "Bryn", "Corin", "Dara", "Gale" }

local function setupFor(name)
	return function(M)
		local members = {}
		for _, n in ipairs(NAMES) do
			if n ~= name then members[#members + 1] = { name = n, rank = RANKS[n], class = CLASSES[n] } end
		end
		M.player.classFile = CLASSES[name]
		M.guild.Set({ name = "Dragon", members = members, myRank = RANKS[name] })
	end
end

local function A(c) return c.addon() end
local function Ldg(c) return assert(A(c).NightController:Ledger()) end
local function gate(c) return A(c).PermissionService:Gate() end
local function now(c) return A(c).Compat.ServerTime() end
local function RCof(c) return A(c).RosterController end

local function guild(names)
	local net = Sim.new{ realm = REALM, step = 0.5 }
	local c = {}
	for _, n in ipairs(names) do c[n] = net:Client(n, { setup = setupFor(n) }) end
	net:Advance(3)
	return net, c
end

-- The season of the guild, its pool (Bryn, Corin, Dara) and one night played: a player who joins now is a late joiner.
local function openSeason(c)
	local a, L = A(c), Ldg(c)
	assert(a.Season.Open(L, { author = full(c.name), ts = now(c), season = SEASON, label = "Season 1",
		instances = { { id = 409, size = 40 } } }, nil, gate(c)))
	for _, m in ipairs({ { "Bryn", 65 }, { "Corin", 257 }, { "Dara", 63 } }) do
		assert(a.Roster.Join(L, { author = full(c.name), ts = now(c), season = SEASON, member = full(m[1]),
			faction = "Horde", ms1 = m[2] }, nil, gate(c)))
	end
	assert(a.Nights.Open(L, { author = full(c.name), ts = now(c), season = SEASON, date = "2026-01-07", instanceID = 409,
		difficulty = "normal" }, gate(c)))
	assert(a.Ledger.Append(L, { author = full(c.name), ts = now(c), season = SEASON, type = "ITEM_AWARDED",
		payload = { member = full("Dara"), item = 19003, cost = 2, response = "MS" } }, gate(c)))
	assert(a.Nights.Close(L, { author = full(c.name), ts = now(c), season = SEASON }, gate(c)))
end

-- The guild on the simulator, the season open, the officers synced and the members holding the snapshot.
local function ready(names)
	local net, c = guild(names or { "Aurel", "Bryn", "Corin", "Gale" })
	openSeason(c.Aurel)
	net:Advance(120)
	return net, c
end

---------------------------------------------------------------------------------------------------------------------

describe("the request round trip on the network", function()
	it("a new player asks, both officers keep it, one approves, the ledger syncs and the player sees it", function()
		local net, c = ready()
		truthy(A(c.Bryn).Roster.Get(Ldg(c.Bryn), SEASON, full("Dara")), "the officers synced first")
		local rc = RCof(c.Gale)
		eq(Ldg(c.Gale).schema and A(c.Gale).Ledger.Count(Ldg(c.Gale)), 0, "Gale has no ledger of its own")
		local status = assert(rc:MyStatus())
		eq(status.source, "snapshot"); eq(status.state, "OUT")
		local rec = assert(rc:SendJoin({ ms1 = 257, ms2 = 258, avail = { "WED", "MON" }, note = "Holy main" }))
		eq(rec.state, "SENDING"); eq(rec.kind, "JOIN")
		net:Advance(5)
		eq(rc:MyRequest().state, "PENDING", "an officer answered")
		for _, o in ipairs({ "Aurel", "Bryn" }) do
			local pending = RCof(c[o]):Pending()
			eq(#pending, 1, o .. " keeps the request")
			local r = pending[1]
			eq(r.id, full("Gale") .. "#" .. rec.q)
			eq(r.member, full("Gale")); eq(r.from, full("Gale")); eq(r.class, "PRIEST"); eq(r.role, "HEALER")
			eq(r.ms1, 257); eq(r.ms2, 258); deepEq(r.avail, { "MON", "WED" }); eq(r.note, "Holy main"); eq(r.faction, "Horde")
		end
		eq(#A(c.Corin).Roster.Pending(RCof(c.Corin):Requests()), 0, "a member's client keeps nothing")
		truthy(A(c.Corin).RosterNet:Stats().ignored >= 1)

		local id = RCof(c.Aurel):Pending()[1].id
		local e = assert(RCof(c.Aurel):Approve(id))
		eq(e.type, "MEMBER_JOINED")
		eq(e.payload.member, full("Gale")); eq(e.payload.ms1, 257)
		truthy(e.payload.rule ~= "START", "a late joiner: the guild's rule after the first night")
		net:Advance(5)
		eq(rc:MyRequest().state, "APPROVED", "the decision reached the player")
		eq(#RCof(c.Bryn):Pending(), 0, "the decision reached the other officer")
		net:Advance(120)
		local m = A(c.Bryn).Roster.Get(Ldg(c.Bryn), SEASON, full("Gale"))
		truthy(m, "the event reached the other officer by the ledger sync")
		eq(m.ms1, 257); eq(m.initialCredits, e.payload.initialCredits)
		eq(rc:MyStatus().state, "IN", "the player's snapshot shows them in the pool")
	end)

	it("a rejected request is rejected for the player and leaves every inbox", function()
		local net, c = ready()
		local rc = RCof(c.Gale)
		local rec = assert(rc:SendJoin({ ms1 = 258 }))
		net:Advance(5)
		local id = RCof(c.Bryn):Pending()[1].id
		assert(RCof(c.Bryn):Reject(id))
		net:Advance(5)
		eq(rc:MyRequest().state, "REJECTED")
		eq(#RCof(c.Aurel):Pending(), 0)
		eq(rc:MyStatus().state, "OUT")
		eq(rec.q, rc:MyRequest().q)
	end)

	it("an alt link goes the same way and the snapshot shows the character as an alt", function()
		local net, c = ready()
		local rc = RCof(c.Gale)
		deepEq(rc:Mains(), { full("Bryn"), full("Corin"), full("Dara") })
		local e0, code = rc:SendAlt(full("Nobody"))
		isNil(e0); eq(code, "MAIN_UNKNOWN")
		assert(rc:SendAlt(full("Corin")))
		net:Advance(5)
		local pending = RCof(c.Aurel):Pending()
		eq(#pending, 1); eq(pending[1].kind, "ALT"); eq(pending[1].alt, full("Gale")); eq(pending[1].main, full("Corin"))
		local e = assert(RCof(c.Aurel):Approve(pending[1].id))
		eq(e.type, "MEMBER_LINKED_ALT")
		net:Advance(120)
		local status = rc:MyStatus()
		eq(status.state, "ALT"); eq(status.main, full("Corin"))
		eq(status.request.state, "APPROVED")
	end)

	it("an undeclared member's declaration is approved into the officer's ROSTER_CHANGED", function()
		local net, c = ready({ "Aurel", "Bryn", "Gale" })
		local L = Ldg(c.Aurel)
		assert(A(c.Aurel).Members.Join(L, { author = full("Aurel"), ts = now(c.Aurel), season = SEASON, member = full("Gale"),
			faction = "Horde", decl = { class = "PRIEST" } }, nil, gate(c.Aurel)))
		net:Advance(120)
		local rc = RCof(c.Gale)
		eq(rc:MyStatus().state, "UNDECLARED")
		assert(rc:SendJoin({ ms1 = 256 }))
		net:Advance(5)
		local pending = RCof(c.Aurel):Pending()
		eq(#pending, 1); truthy(pending[1].declare)
		local before = A(c.Aurel).Roster.Get(L, SEASON, full("Gale")).initialCredits
		local e = assert(RCof(c.Aurel):Approve(pending[1].id))
		eq(e.type, "ROSTER_CHANGED"); eq(e.payload.set.ms1, 256); eq(e.payload.reason, "DECLARATION")
		local m = A(c.Aurel).Roster.Get(L, SEASON, full("Gale"))
		truthy(m.declared); eq(m.role, "HEALER"); eq(m.initialCredits, before, "the credits do not change")
		net:Advance(120)
		eq(rc:MyStatus().state, "IN")
		eq(rc:MyRequest().state, "APPROVED")
	end)
end)

describe("dedupe, throttling and trust", function()
	it("a player sends one request per gap; a request heard twice is kept once", function()
		local net, c = ready({ "Aurel", "Bryn", "Gale" })
		local rc = RCof(c.Gale)
		local rec = assert(rc:SendJoin({ ms1 = 257 }))
		local again, code, wait = rc:SendJoin({ ms1 = 258 })
		isNil(again); eq(code, "TOO_SOON"); truthy(wait > 0 and wait <= rc.SEND_GAP)
		net:Advance(10)
		truthy(A(c.Gale).RosterNet:Resend(), "the waiting request goes out again (the same number)")
		net:Advance(10)
		local s = A(c.Aurel).RosterNet:Stats()
		eq(s.heard, 2); eq(s.stored, 1)
		eq(#RCof(c.Aurel):Pending(), 1)
		eq(rc:MyRequest().state, "PENDING")
		-- after the gap the player's new request replaces their pending one
		net:Advance(rc.SEND_GAP)
		local rec2 = assert(rc:SendJoin({ ms1 = 258 }))
		truthy(rec2.q ~= rec.q)
		net:Advance(10)
		local pending = RCof(c.Aurel):Pending()
		eq(#pending, 1); eq(pending[1].ms1, 258)
	end)

	it("an officer's client takes one request per sender per gap and drops a damaged one", function()
		local net, c = ready({ "Aurel", "Gale" })
		local RN = A(c.Aurel).RosterNet
		local msg = { t = "RREQ", q = 77, k = "J", s = SEASON, c = "PRIEST", m1 = 257, f = "Horde" }
		truthy(RN:OnMessage(msg, "Gale", "GUILD"))
		truthy(RN:OnMessage({ t = "RREQ", q = 78, k = "J", s = SEASON, c = "PRIEST", m1 = 258 }, "Gale", "GUILD"))
		eq(RN:Stats().throttled, 1)
		eq(#RCof(c.Aurel):Pending(), 1)
		net:Advance(10)
		RN:OnMessage({ t = "RREQ", q = 79, k = "X", s = SEASON }, "Gale", "GUILD")
		RN:OnMessage({ t = "RREQ", q = 80, k = "J", s = SEASON, m1 = 257 }, "Gale", "WHISPER")
		eq(RN:Stats().bad, 2)
		-- the member is always the sender: a request names nobody else
		net:Advance(10)
		RN:OnMessage({ t = "RREQ", q = 81, k = "J", s = SEASON, c = "MAGE", m1 = 63, member = full("Aurel") }, "Corin", "GUILD")
		local refused = RN:Stats().refused
		eq(refused, 1, "Corin is already in the pool: refused, whatever the message says")
	end)

	it("a decision or an answer from a member is not trusted; a member cannot approve", function()
		local net, c = ready({ "Aurel", "Bryn", "Corin", "Gale" })
		local rc = RCof(c.Gale)
		local rec = assert(rc:SendJoin({ ms1 = 257 }))
		net:Advance(5)
		eq(rc:MyRequest().state, "PENDING")
		A(c.Corin).Transport:Send("GUILD", { t = "RDEC", p = full("Gale"), q = rec.q, st = "R" })
		A(c.Corin).Transport:Send("WHISPER", { t = "RACK", q = rec.q, st = "ALREADY_JOINED" }, { target = full("Gale") })
		net:Advance(5)
		eq(rc:MyRequest().state, "PENDING", "the forged decision changed nothing")
		eq(#RCof(c.Aurel):Pending(), 1)
		truthy(A(c.Aurel).RosterNet:Stats().untrusted >= 1)
		truthy(A(c.Gale).RosterNet:Stats().untrusted >= 2)
		local id = RCof(c.Aurel):Pending()[1].id
		local e, code = RCof(c.Corin):Approve(id)
		isNil(e); truthy(code ~= nil, "a member holds neither the request nor the right")
		eq(#A(c.Corin).Roster.Pending(RCof(c.Corin):Requests()), 0)
	end)

	it("a request an officer cannot accept is answered with the reason", function()
		local net, c = ready({ "Aurel", "Gale" })
		local RN = A(c.Gale).RosterNet
		-- a priest spec for a mage: built by hand, the player's own window never sends it
		RN:Send({ kind = "JOIN", season = SEASON, faction = "Horde", class = "MAGE", ms1 = 257 })
		local rc = RCof(c.Gale)
		local store = A(c.Gale).Config:GuildData().myRequests
		store[full("Gale")] = { kind = "JOIN", season = SEASON, q = math.floor(now(c.Gale)), state = "SENDING", at = now(c.Gale) }
		net:Advance(5)
		eq(rc:MyRequest().state, "REFUSED"); eq(rc:MyRequest().code, "SPEC_CLASS")
		eq(#RCof(c.Aurel):Pending(), 0)
	end)

	it("a waiting request goes out again after the next login, once", function()
		local net, c = ready({ "Aurel", "Gale" })
		net:Logout("Aurel")
		local rc = RCof(c.Gale)
		assert(rc:SendJoin({ ms1 = 257 }))
		net:Advance(5)
		eq(rc:MyRequest().state, "SENT", "nobody answered: no officer online")
		net:Login("Aurel")
		net:Advance(10)
		net:Reload("Gale")
		net:Advance(60)
		rc = RCof(c.Gale)
		eq(A(c.Gale).RosterNet:Stats().resent, 1)
		eq(rc:MyRequest().state, "PENDING")
		eq(#RCof(c.Aurel):Pending(), 1)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The officers' direct addition (mock client: Testchar is an officer of rank 1)

local RANK_NAMES = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }
local MREALM = "TestRealm"
local function mfull(n) return n .. "-" .. MREALM end

local function mguild(myRank, faction)
	return function(M)
		if faction then M.player.faction = faction end
		M.guild.Set({ name = "Keepers", ranks = RANK_NAMES, myRank = myRank or 1, members = {
			{ name = "Aurel", rank = 0, class = "WARRIOR" }, { name = "Bryn", rank = 1, class = "PALADIN" },
			{ name = "Corin", rank = 3, class = "PRIEST" }, { name = "Dara", rank = 3, class = "MAGE" },
			{ name = "Edda", rank = 3, class = "DRUID", online = false },
		} })
	end
end

local function bound()
	local L = FDCP.Ledger.New()
	assert(FDCP.Season.Open(L, { author = mfull("Aurel"), ts = 1, season = "S1", instances = { { id = 409, size = 40 } } }))
	assert(FDCP.Roster.Join(L, { author = mfull("Aurel"), ts = 2, season = "S1", member = mfull("Aurel"), faction = "Horde", ms1 = 73 }))
	assert(FDCP.Roster.Join(L, { author = mfull("Aurel"), ts = 3, season = "S1", member = mfull("Bryn"), faction = "Horde", ms1 = 65 }))
	assert(FDCP.Roster.Join(L, { author = mfull("Aurel"), ts = 4, season = "S1", member = mfull("Fenn"), faction = "Alliance", ms1 = 70 }))
	assert(FDCP.Nights.Open(L, { author = mfull("Aurel"), ts = 5, season = "S1", date = "2026-01-01", instanceID = 409,
		difficulty = "normal" }))
	assert(FDCP.Nights.Close(L, { author = mfull("Aurel"), ts = 6, season = "S1" }))
	FDCP.NightController:Bind(L)
	Mock.group.Set({ raid = true, members = {
		{ name = "Corin", inGuild = true, class = "PRIEST" }, { name = "Dara", inGuild = true, class = "MAGE" },
		{ name = "Pug", inGuild = false, class = "ROGUE" },
	} })
	Mock.Advance(3)
	return L
end

local function RC() return FDCP.RosterController end

describe("the officers add players", function()
	before_boot(mguild(1))

	it("the candidates are the raid's and the guild's characters outside the pool, the raid first", function()
		bound()
		local list = assert(RC():Candidates())
		local byName = {}
		for i, m in ipairs(list) do byName[m.name] = { i = i, m = m } end
		eq(byName[mfull("Corin")].m.class, "PRIEST"); truthy(byName[mfull("Corin")].m.inRaid)
		eq(byName[mfull("Dara")].m.class, "MAGE")
		truthy(byName[mfull("Corin")].i <= 2 and byName[mfull("Dara")].i <= 2, "the raid first")
		eq(byName[mfull("Edda")].m.class, "DRUID"); falsy(byName[mfull("Edda")].m.online)
		isNil(byName[mfull("Aurel")], "already in the pool")
		isNil(byName[mfull("Pug")], "not in the guild")
	end)

	it("adds a player directly with the late-joiner rule, once", function()
		local L = bound()
		local value = RC():JoinCredits(mfull("Edda"))
		truthy(type(value) == "number")
		local e = assert(RC():AddMember(mfull("Edda"), { class = "DRUID", ms1 = 105, ms2 = 102 }))
		eq(e.type, "MEMBER_JOINED"); eq(e.author, mfull("Testchar"))
		eq(e.payload.class, "DRUID"); eq(e.payload.role, "HEALER"); eq(e.payload.faction, "Horde")
		truthy(e.payload.rule ~= "START"); eq(e.payload.initialCredits, value)
		local again, code = RC():AddMember(mfull("Edda"), { class = "DRUID", ms1 = 105 })
		isNil(again); eq(code, "ALREADY_JOINED")
		local bad, why = RC():AddMember(mfull("Corin"), { class = "PRIEST", ms1 = 73 })
		isNil(bad); eq(why, "SPEC_CLASS")
		local none, need = RC():AddMember(mfull("Corin"), { class = "PRIEST" })
		isNil(none); eq(need, "MS1_REQUIRED")
	end)

	it("adds the raid group's guild members without a declaration, then approves a declaration", function()
		local L = bound()
		local missing = assert(RC():RaidMissing())
		eq(#missing, 3, "Corin, Dara and the officer, who is in the raid too; not the player outside the guild")
		eq(missing[1].name, mfull("Corin")); eq(missing[2].name, mfull("Dara")); eq(missing[3].name, mfull("Testchar"))
		local added, refused = RC():AddRaid()
		eq(#added, 3); eq(#refused, 0)
		local corin = FDCP.Roster.Get(L, "S1", mfull("Corin"))
		falsy(corin.declared); eq(corin.class, "PRIEST")
		truthy(added[1].payload.rule ~= "START")
		eq(#RC():Pool().undeclared, 3)
		local none, code = RC():AddRaid()
		isNil(none); eq(code, "NOBODY_MISSING")
		-- Corin's declaration arrives (as the network would bring it) and is approved
		local wrong, why = RC():RequestJoin({ member = mfull("Corin"), from = mfull("Corin"), ms1 = 63 })
		isNil(wrong); eq(why, "SPEC_CLASS")
		local req = assert(RC():RequestJoin({ member = mfull("Corin"), from = mfull("Corin"), ms1 = 257, note = "late" }))
		truthy(req.declare)
		local e = assert(RC():Approve(req.id))
		eq(e.type, "ROSTER_CHANGED")
		corin = FDCP.Roster.Get(L, "S1", mfull("Corin"))
		truthy(corin.declared); eq(corin.ms1, 257); eq(corin.note, "late"); eq(corin.status, "ACTIVE")
		eq(#RC():Pool().undeclared, 2)
	end)

	it("a member cannot add anybody", function()
		bound()
		Mock.guild.SetMyRank(3)
		Mock.Advance(3)
		local e, code = RC():AddMember(mfull("Edda"), { class = "DRUID", ms1 = 105 })
		isNil(e); eq(code, "RANK_TOO_LOW")
		isNil((RC():Candidates()))
		isNil((RC():AddRaid()))
	end)

	it("without a raid there is nobody to add from it", function()
		bound()
		Mock.group.Leave()
		Mock.Advance(3)
		local list, code = RC():RaidMissing()
		isNil(list); eq(code, "NOT_IN_RAID")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The windows

local function open()
	Mock.Slash("/fdcp")
	FDCP.RosterWindow:Refresh()
	return FDCP.RosterWindow.pool
end
local function F() return FDCP.RosterForms end

describe("the Pool window", function()
	before_boot(mguild(1))

	it("has no faction switch: the header names the guild's faction", function()
		bound()
		local pool = open()
		isNil(pool.faction)
		contains(pool.eyebrow:GetText(), "HORDE")
		eq(pool.summary:GetText(), "2 players, 0 on trial, 0 without a declaration", "the Horde pool only")
		FDCP.MainWindow:SelectTab("credits")
		local cw = FDCP.CreditsWindow
		cw:Refresh()
		eq(cw.root.faction:GetObjectType(), "FontString", "a text, not a switch")
		eq(cw.root.faction:GetText(), "Horde")
	end)

	it("a player outside the pool joins with the form; an officer's own request lands in the inbox", function()
		bound()
		local pool = open()
		truthy(pool.join:IsShown()); truthy(pool.alt:IsShown())
		truthy(pool.add:IsShown()); truthy(pool.addRaid:IsShown())
		eq(pool.join.label:GetText(), "Join the roster")
		pool.join:Click()
		local d = F().form
		truthy(d:IsShown())
		eq(d.title:GetText(), "Join the roster")
		eq(d.class:GetText(), "Class: Warrior")
		falsy(d.list:IsShown())
		falsy(d.ok:IsEnabled(), "MS1 is required")
		truthy(d.ms1:Pick(73))
		truthy(d.ok:IsEnabled())
		d.ms2:Pick(71)
		d.days:Pick("TUE"); d.days:Pick("MON")
		d.note:SetText("  tank  ")
		deepEq(F():Fields(), { ms1 = 73, ms2 = 71, avail = { "MON", "TUE" }, note = "tank" })
		d.ok:Click()
		falsy(d:IsShown())
		eq(pool.message:GetText(), "Request sent to the officers.")
		eq(pool.mine:GetText(), "Request to join the roster: received by an officer, pending.")
		eq(pool.inbox.rows[1].text:GetText(), "Testchar asks to join: Warrior Protection")
		-- the second request within the gap is refused in the form
		pool.join:Click()
		d.ms1:Pick(72)
		d.ok:Click()
		truthy(d:IsShown())
		contains(d.info:GetText(), "Wait")
	end)

	it("an officer adds a player from the list, after the confirmation", function()
		local L = bound()
		local pool = open()
		pool.add:Click()
		local d = F().form
		truthy(d:IsShown()); truthy(d.list:IsShown())
		eq(d.title:GetText(), "Add a player")
		eq(d.info:GetText(), "Pick a player from the list.")
		falsy(d.ok:IsEnabled())
		truthy(d.list:Select(mfull("Edda")))
		eq(d.class:GetText(), "Class: Druid")
		d.ms1:Pick(105)
		contains(d.info:GetText(), "Edda starts with")
		d.ok:Click()
		falsy(d:IsShown())
		local c = F().confirm
		truthy(c:IsShown())
		contains(c.body:GetText(), "Edda joins the season's pool as Druid Restoration")
		-- Cancel goes back to the form, nothing written
		c.cancel:Click()
		truthy(d:IsShown())
		isNil(FDCP.Roster.Get(L, "S1", mfull("Edda")))
		d.ok:Click()
		c.ok:Click()
		local m = FDCP.Roster.Get(L, "S1", mfull("Edda"))
		truthy(m); eq(m.ms1, 105); eq(m.class, "DRUID")
		eq(pool.message:GetText(), "Edda added to the roster.")
	end)

	it("Add the raid group asks first, then lists the members without a declaration", function()
		local L = bound()
		local pool = open()
		pool.addRaid:Click()
		local c = F().confirm
		truthy(c:IsShown())
		contains(c.body:GetText(), "Corin, Dara, Testchar")
		c.ok:Click()
		truthy(FDCP.Roster.Get(L, "S1", mfull("Corin")))
		eq(pool.message:GetText(), "3 raid members added without a declaration, 0 refused.")
		eq(pool.inbox.undeclared:GetText(), "Without a declaration (3): Dara, Corin, Testchar", "by class, then name")
		eq(pool.summary:GetText(), "5 players, 0 on trial, 3 without a declaration")
		eq(pool.join.label:GetText(), "Declare your specs", "the officer, now in the pool, declares too")
	end)

	it("a member without the ledger joins from the snapshot's season, and links an alt", function()
		FDCP.NightController:Bind(FDCP.Ledger.New())
		Mock.guild.SetMyRank(3)
		Mock.Advance(3)
		FDCP.Snapshot:Keep({ s = "S1", so = true, n = {}, nn = 0, k = 3, ts = 1, r = {
			{ m = mfull("Aurel"), t = 0, c = "WARRIOR", sp = 73, f = "Horde" },
			{ m = mfull("Bryn"), t = 0, c = "PALADIN", sp = 65, f = "Horde" },
		} }, mfull("Aurel"))
		local pool = open()
		eq(pool.empty:GetText(), "The pool is kept by the officers' addon: your credits are in the Credits tab.")
		truthy(pool.join:IsShown()); truthy(pool.alt:IsShown())
		falsy(pool.add:IsShown()); falsy(pool.addRaid:IsShown())
		pool.alt:Click()
		local d = F().alt
		truthy(d:IsShown())
		eq(d.list:Count(), 2)
		falsy(d.ok:IsEnabled())
		d.list:Select(mfull("Bryn"))
		d.ok:Click()
		falsy(d:IsShown())
		eq(pool.mine:GetText(), "Request as an alt of Bryn: waiting to be sent.")
		Mock.Advance(3)
		eq(pool.mine:GetText(), "Request as an alt of Bryn: sent, waiting for an officer.")
		FDCP.RosterController:OnAnswer(FDCP.RosterController:MyRequest().q, "REJECTED")
		eq(pool.mine:GetText(), "Request as an alt of Bryn: rejected.")
	end)

	it("a member already declared sees no button", function()
		local L = bound()
		assert(FDCP.Roster.Join(L, { author = mfull("Aurel"), ts = 9, season = "S1", member = mfull("Testchar"),
			faction = "Horde", ms1 = 71 }))
		local pool = open()
		falsy(pool.join:IsShown()); falsy(pool.alt:IsShown())
		eq(pool.mine:GetText(), "")
	end)

	it("an undeclared member declares with the same form", function()
		local L = bound()
		assert(FDCP.Members.Join(L, { author = mfull("Aurel"), ts = 9, season = "S1", member = mfull("Testchar"),
			faction = "Horde", decl = { class = "WARRIOR" } }))
		local pool = open()
		truthy(pool.join:IsShown()); falsy(pool.alt:IsShown())
		eq(pool.join.label:GetText(), "Declare your specs")
		pool.join:Click()
		eq(F().form.title:GetText(), "Declare your specs")
		eq(F().form.info:GetText(), "You are in the pool without a declaration: an officer approves the one you send.")
	end)
end)

describe("the Pool window of an Alliance guild", function()
	before_boot(mguild(1, "Alliance"))

	it("shows the Alliance pool and says so", function()
		bound()
		local pool = open()
		contains(pool.eyebrow:GetText(), "ALLIANCE")
		eq(pool.cards.DAMAGER.count:GetText(), "1/34")
		eq(pool.summary:GetText(), "1 players, 0 on trial, 0 without a declaration")
	end)
end)

describe("the Pool window in Italian", function()
	before_boot(function(M) mguild(1)(M); M.player.locale = "itIT" end)

	it("shows the buttons and the form in Italian", function()
		bound()
		local pool = open()
		eq(pool.join.label:GetText(), "Entra nel roster")
		eq(pool.add.label:GetText(), "Aggiungi giocatore")
		contains(pool.eyebrow:GetText(), "ORDA")
		pool.join:Click()
		eq(F().form.class:GetText(), "Classe: Guerriero")
		eq(F().form.days.chips[1].label:GetText(), "Lun")
	end)
end)
