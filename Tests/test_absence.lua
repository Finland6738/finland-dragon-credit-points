-- The dynamic roster of M7-5b (owner rules of 2026-11-22): a late joiner starts with the fewest credits of the pool, and a
-- member who misses an official night gets +1 credit (lowest credits wins, so a penalty adds). Domain/Absence.lua decides
-- who is penalized and why (not signed up, signed up but absent, benched themselves); an officer's bench never costs
-- anything. App/NightController.lua proposes the penalties at the close and the officer confirms them (unless
-- `penalties.autoApply`); a player benches themselves with "Bench myself" (NBENCH to the night's runner).
local function Lg() return FDCP.Ledger end
local function Sn() return FDCP.Season end
local function M() return FDCP.Members end
local function N() return FDCP.Nights end
local function A() return FDCP.Absence end
local function P() return FDCP.Permissions end
local function C() return FDCP.Council end
local function NC() return FDCP.NightController end

local GM, OFFICER, RAIDER = "Aurel-Camelot", "Bryn-Camelot", "Corin-Camelot"
local PACK = { { id = 409, size = 40 } }
local POOL = { "Aurel", "Bryn", "Corin", "Dara", "Edda", "Fenn", "Gale", "Hale" }

local function ranks()
	local h = P().NewHistory()
	P().RecordRank(h, GM, 0, 0)
	P().RecordRank(h, OFFICER, 1, 0)
	P().RecordRank(h, RAIDER, 3, 0)
	h.loaded = true
	return h
end
local function gate() return P().Gate(ranks()) end

-- A season "S1" with Molten Core and the pool of eight mains (joined before the first night).
local function newSeason()
	local L = Lg().New()
	assert(Sn().Open(L, { author = GM, ts = 1, season = "S1", label = "Tier 1", instances = PACK }))
	for i, name in ipairs(POOL) do
		assert(M().Join(L, { author = OFFICER, ts = 1 + i, season = "S1", member = name, faction = "Horde" }))
	end
	return L
end

local function open(L, ts)
	return assert(N().Open(L, { author = OFFICER, ts = ts, season = "S1", date = "2026-11-22", instanceID = 409,
		difficulty = "normal", faction = "Horde" }))
end
local function close(L, ts) return assert(N().Close(L, { author = OFFICER, ts = ts, season = "S1" })) end
local function lineup(L, ts, d)
	d.author, d.ts, d.season = d.author or OFFICER, ts, "S1"
	return N().SetLineup(L, d)
end

local function causes(p)
	local out = {}
	for _, e in ipairs(p.entries) do out[e.member] = e.cause end
	return out
end

-- The night of the owner's rules: Aurel and Bryn play, Corin is benched by the officer, Dara benches herself; the
-- calendar says Aurel yes, Edda yes, Fenn maybe, Gale no, Corin no; Bryn and Hale never answered.
local SIGNUPS = { Aurel = "yes", Edda = "yes", Fenn = "maybe", Gale = "no", Corin = "no" }
local function ownersNight()
	local L = newSeason()
	local night = open(L, 100)
	assert(lineup(L, 101, { raid = { "Aurel", "Bryn" }, bench = { "Corin" } }))
	assert(lineup(L, 102, { bench = { "Dara" }, selfBench = true }))
	close(L, 200)
	return L, night.id
end

describe("who is penalized for a missed night", function()
	it("+1 for not signed up, signed up but absent and a self-bench; nothing for the raid and an officer's bench", function()
		local L, night = ownersNight()
		local p = assert(A().Propose(L, "S1", night, { signups = SIGNUPS, amount = 1 }))
		deepEq(causes(p), { Dara = "SELF_BENCH", Edda = "NO_SHOW", Fenn = "NO_SHOW", Gale = "NOT_SIGNED_UP",
			Hale = "NOT_SIGNED_UP" })
		for _, e in ipairs(p.entries) do eq(e.delta, 1) end
		eq(p.entries[1].member, "Dara")   -- sorted by name
		isNil(causes(p).Aurel); isNil(causes(p).Bryn)   -- present (Bryn never signed up, but played)
		isNil(causes(p).Corin)                          -- benched by the officer: the rotation never penalizes
	end)

	it("not signed up -> +1", function()
		local L, night = ownersNight()
		eq(causes(A().Propose(L, "S1", night, { signups = {} })).Hale, "NOT_SIGNED_UP")
		eq(causes(A().Propose(L, "S1", night, { signups = { Hale = "no" } })).Hale, "NOT_SIGNED_UP")
	end)

	it("signed up but absent -> +1", function()
		local L, night = ownersNight()
		eq(causes(A().Propose(L, "S1", night, { signups = { Hale = "yes" } })).Hale, "NO_SHOW")
		eq(causes(A().Propose(L, "S1", night, { signups = { Hale = "maybe" } })).Hale, "NO_SHOW")
	end)

	it("self-bench -> +1, even when they had signed up", function()
		local L, night = ownersNight()
		eq(causes(A().Propose(L, "S1", night, { signups = { Dara = "yes" } })).Dara, "SELF_BENCH")
	end)

	it("officer bench -> 0, even when they had not signed up", function()
		local L, night = ownersNight()
		isNil(causes(A().Propose(L, "S1", night, { signups = {} })).Corin)
	end)

	it("present -> 0, also when they came after a self-bench", function()
		local L = newSeason()
		local night = open(L, 100)
		assert(lineup(L, 101, { bench = { "Dara" }, selfBench = true }))
		assert(lineup(L, 150, { raid = { "Dara" } }))
		assert(lineup(L, 160, { absent = { "Dara" } }))   -- left before the end: she played, so she was present
		close(L, 200)
		isNil(causes(A().Propose(L, "S1", night.id, { signups = {} })).Dara)
	end)

	it("an officer who takes over a self-bench makes it the officer's: no penalty", function()
		local L = newSeason()
		local night = open(L, 100)
		local e = assert(lineup(L, 101, { bench = { "Dara" }, selfBench = true }))
		deepEq(e.payload.self, { "Dara" })
		local states, origins = N().Lineup(L, night.id)
		eq(states.Dara, "BENCH"); eq(origins.Dara, "SELF")
		local again, code = lineup(L, 102, { bench = { "Dara" }, selfBench = true })
		isNil(again); eq(code, "NO_CHANGE")
		local taken = assert(lineup(L, 103, { bench = { "Dara" } }))   -- same state, other origin: a change
		isNil(taken.payload.self)
		states, origins = N().Lineup(L, night.id)
		eq(origins.Dara, "OFFICER")
		close(L, 200)
		isNil(causes(A().Propose(L, "S1", night.id, { signups = {} })).Dara)
	end)

	it("without the calendar's answers every absent member is ABSENT", function()
		local L, night = ownersNight()
		deepEq(causes(A().Propose(L, "S1", night, {})), { Dara = "SELF_BENCH", Edda = "ABSENT", Fenn = "ABSENT",
			Gale = "ABSENT", Hale = "ABSENT" })
	end)

	it("a sign-up with an alt counts for its main", function()
		local L = newSeason()
		assert(M().LinkAlt(L, { author = OFFICER, ts = 20, season = "S1", alt = "Halealt", main = "Hale", faction = "Horde" }))
		local night = open(L, 100)
		assert(lineup(L, 101, { raid = { "Aurel" } }))
		close(L, 200)
		eq(causes(A().Propose(L, "S1", night.id, { signups = { Halealt = "yes" } })).Hale, "NO_SHOW")
	end)

	it("leaves out who joined after the night opened, and answers only for a closed night of the season", function()
		local L = newSeason()
		local night = open(L, 100)
		assert(M().Join(L, { author = OFFICER, ts = 150, season = "S1", member = "Ivo", faction = "Horde" }))
		local p, code = A().Propose(L, "S1", night.id, {})
		isNil(p); eq(code, "NIGHT_OPEN")
		close(L, 200)
		isNil(causes(A().Propose(L, "S1", night.id, {})).Ivo)
		p, code = A().Propose(L, "S2", night.id, {})
		isNil(p); eq(code, "NIGHT_UNKNOWN")
	end)

	it("an amount of 0 turns the penalty off, another amount is used as it is", function()
		local L, night = ownersNight()
		eq(#A().Propose(L, "S1", night, { signups = SIGNUPS, amount = 0 }).entries, 0)
		for _, e in ipairs(A().Propose(L, "S1", night, { signups = SIGNUPS, amount = 2 }).entries) do eq(e.delta, 2) end
	end)

	it("the ledger refuses a `self` list that is not part of the bench", function()
		local L = newSeason()
		local night = open(L, 100)
		local e, code = Lg().Append(L, { author = OFFICER, ts = 101, season = "S1", type = "LINEUP_CHANGED",
			payload = { night = night.id, raid = { "Dara" }, self = { "Dara" } } })
		isNil(e); eq(code, "payload:self")
	end)
end)

describe("writing the penalties", function()
	it("one CREDITS_ADJUSTED per member, reason ABSENCE, with the night and the cause; +1 each", function()
		local L, night = ownersNight()
		local p = A().Propose(L, "S1", night, { signups = SIGNUPS })
		local before = Lg().Credits(L, "S1")
		local written, refused = A().Apply(L, { author = OFFICER, ts = 300, season = "S1", night = night, entries = p.entries },
			gate())
		eq(#written, 5); deepEq(refused, {})
		local w = written[1]
		eq(w.type, "CREDITS_ADJUSTED")
		deepEq(w.payload, { member = "Dara", delta = 1, reason = "ABSENCE", night = night, cause = "SELF_BENCH" })
		local after = Lg().Credits(L, "S1")
		for _, name in ipairs({ "Dara", "Edda", "Fenn", "Gale", "Hale" }) do eq(after[name], (before[name] or 0) + 1) end
		for _, name in ipairs({ "Aurel", "Bryn", "Corin" }) do eq(after[name], before[name] or 0) end
	end)

	it("a member penalized once for a night is never proposed again, and a second write is refused", function()
		local L, night = ownersNight()
		local p = A().Propose(L, "S1", night, { signups = SIGNUPS })
		A().Apply(L, { author = OFFICER, ts = 300, season = "S1", night = night, entries = p.entries })
		eq(#A().Propose(L, "S1", night, { signups = SIGNUPS }).entries, 0)
		local written, refused = A().Apply(L, { author = OFFICER, ts = 301, season = "S1", night = night, entries = p.entries })
		eq(#written, 0); eq(#refused, 5); eq(refused[1].code, "DUPLICATE")
	end)

	it("a void restores the previous credits, and the voided penalty is not proposed again", function()
		local L, night = ownersNight()
		local before = Lg().Credits(L, "S1").Hale or 0
		local p = A().Propose(L, "S1", night, { signups = SIGNUPS })
		local written = A().Apply(L, { author = OFFICER, ts = 300, season = "S1", night = night, entries = p.entries })
		local hale
		for _, e in ipairs(written) do if e.payload.member == "Hale" then hale = e end end
		eq(Lg().Credits(L, "S1").Hale, before + 1)
		assert(C().Void(L, { author = GM, ts = 400, ref = hale.id, reason = "MISTAKE" }, gate()))
		eq(Lg().Credits(L, "S1").Hale, before)
		truthy(Lg().IsVoided(L, hale.id))
		isNil(causes(A().Propose(L, "S1", night, { signups = SIGNUPS })).Hale)
	end)

	it("an officer (night.run) may write the penalty of a night after its close; a raider may not", function()
		local L, night = ownersNight()
		local entries = { { member = "Hale", cause = "NOT_SIGNED_UP", delta = 1 } }
		local _, refused = A().Apply(L, { author = RAIDER, ts = 300, season = "S1", night = night, entries = entries }, gate())
		eq(refused[1].code, "RANK_TOO_LOW")
		local written = A().Apply(L, { author = OFFICER, ts = 301, season = "S1", night = night, entries = entries }, gate())
		eq(#written, 1)
		-- a plain penalty outside a night is still the GM's (credits.adjust)
		local e, code = C().Adjust(L, { author = OFFICER, ts = 302, season = "S1", member = "Gale", delta = 1,
			reason = "PENALTY" }, gate())
		isNil(e); eq(code, "RANK_TOO_LOW")
	end)

	it("the audit and the reasons name the absence", function()
		local L, night = ownersNight()
		A().Apply(L, { author = OFFICER, ts = 300, season = "S1", night = night,
			entries = { { member = "Hale", cause = "NOT_SIGNED_UP", delta = 1 } } })
		local audit = C().Audit(L, "S1")
		eq(audit[#audit].kind, "ADJUST"); eq(audit[#audit].reason, "ABSENCE")
		eq(FDCP.Reasons.Text("CORRECTION", "ABSENCE"), "Absence from an official night.")
		eq(FDCP.Reasons.Text("ABSENCE", "NOT_SIGNED_UP"), "not signed up")
		eq(FDCP.Reasons.Text("ABSENCE", "SELF_BENCH"), "benched themselves")
	end)
end)

describe("late joiners and the presets", function()
	it("a late joiner gets the credits of the member with the fewest (Patto)", function()
		local L = newSeason()
		local night = open(L, 100)
		assert(lineup(L, 101, { raid = { "Aurel", "Bryn", "Corin", "Dara", "Edda", "Fenn", "Gale", "Hale" } }))
		close(L, 200)
		for i, d in ipairs({ { "Aurel", 5 }, { "Bryn", 3 }, { "Corin", 2 }, { "Dara", 4 }, { "Edda", 6 }, { "Fenn", 3 },
			{ "Gale", 7 }, { "Hale", 4 } }) do
			assert(C().Adjust(L, { author = GM, ts = 210 + i, season = "S1", member = d[1], delta = d[2], reason = "OTHER" }))
		end
		local rules = FDCP.Rules.DefaultConfig()
		eq(rules.members.lateJoin.method, "min")
		local e = assert(M().Join(L, { author = OFFICER, ts = 300, season = "S1", member = "Ivo", faction = "Horde",
			nights = N().Played(L, "S1") }, rules.members))
		eq(e.payload.initialCredits, 2); eq(e.payload.rule, "MIN")
		eq(Lg().Credits(L, "S1").Ivo, 2)
		-- the value stays when the minimum moves later
		assert(C().Adjust(L, { author = GM, ts = 310, season = "S1", member = "Corin", delta = 5, reason = "OTHER" }))
		eq(Lg().Credits(L, "S1").Ivo, 2)
		truthy(night)
	end)

	it("only Patto has the minimum and the absence penalty; the other presets keep what they had", function()
		local patto = FDCP.Presets.Get("PATTO")
		eq(patto.members.lateJoin.method, "min"); eq(patto.penalties.absence, 1); eq(patto.penalties.autoApply, false)
		eq(FDCP.Presets.Get("EPGP_SIMPLE").members.lateJoin.method, "average")
		for _, code in ipairs({ "ROLL_ONLY", "LOOT_COUNCIL", "EPGP_SIMPLE" }) do
			local r = FDCP.Presets.Get(code)
			eq(r.penalties.absence, 0)
			truthy(FDCP.Rules.Validate(r))
		end
		eq(FDCP.Presets.Get("ROLL_ONLY").members.lateJoin.method, "zero")
	end)

	it("validates the penalties section, and rules written before it get the defaults", function()
		local r = FDCP.Rules.DefaultConfig()
		r.penalties.absence = -1
		local okRules, problems = FDCP.Rules.Validate(r)
		falsy(okRules); deepEq(problems, { "penalties.absence" })
		r.penalties.absence, r.penalties.autoApply = 1, "yes"
		okRules, problems = FDCP.Rules.Validate(r)
		deepEq(problems, { "penalties.autoApply" })
		local old = FDCP.Rules.DefaultConfig()
		old.penalties = nil
		deepEq(FDCP.Rules.WithDefaults(old).penalties, { absence = 1, cheat = 2, autoApply = false })
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- On the mock client: the controller and the Night window

local ME = "Testchar-TestRealm"
local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }
local MC = { name = "Molten Core", type = "raid", difficultyID = 14, difficultyName = "Normal", maxPlayers = 40,
	instanceID = 409 }

local function guild(myRank)
	return function(Mock)
		Mock.guild.Set({ name = "Keepers", ranks = RANKS, myRank = myRank or 1, members = {
			{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
			{ name = "Dara", rank = 3 }, { name = "Edda", rank = 3 },
		} })
	end
end

local function full(n) return n .. "-TestRealm" end

local function bound()
	local L = Lg().New()
	assert(Sn().Open(L, { author = full("Aurel"), ts = 1, season = "S1", instances = { { id = 409, size = 40 } } }))
	for i, name in ipairs({ "Aurel", "Bryn", "Corin", "Dara", "Edda" }) do
		assert(FDCP.Roster.Join(L, { author = full("Bryn"), ts = 1 + i, season = "S1", member = full(name),
			faction = "Horde", ms1 = 73 }))
	end
	NC():Bind(L)
	Mock.encounter.Set({ instance = MC })
	Mock.Advance(3)
	return L
end

local function calendar(invites)
	Mock.calendar.Set{ opened = true, month = { month = 1, year = 2026, numDays = 31, firstWeekday = 4 }, events = { [1] = {
		{ title = "Raid night", eventType = 0, calendarType = "GUILD_EVENT", eventID = 2001, invites = invites or {} },
	} } }
end

local function adjustments(L)
	local out = {}
	for _, e in pairs(L.events) do
		if e.type == "CREDITS_ADJUSTED" then out[e.payload.member] = e.payload end
	end
	return out
end

describe("the night controller and the absences", function()
	before_boot(guild(1))

	it("proposes at the close, writes nothing until the officer confirms, then writes +1 each", function()
		local L = bound()
		calendar({ { name = "Dara", inviteStatus = 1 } })   -- Dara signed up; Edda did not
		Mock.Advance(1)
		assert(NC():Open({ instanceID = 409, difficulty = "normal" }))
		assert(NC():SetState("Aurel", "RAID")); assert(NC():SetState("Bryn", "RAID"))
		assert(NC():Bench("Corin"))
		assert(NC():Close())
		deepEq(adjustments(L), {})   -- autoApply is off in the preset: a confirmation is required
		local p = assert(NC():AbsenceProposal())
		truthy(p.signupsKnown)
		deepEq(causes(p), { [full("Dara")] = "NO_SHOW", [full("Edda")] = "NOT_SIGNED_UP" })
		local written = assert(NC():ApplyAbsences())
		eq(#written, 2)
		local adj = adjustments(L)
		eq(adj[full("Dara")].delta, 1); eq(adj[full("Dara")].cause, "NO_SHOW")
		eq(adj[full("Edda")].cause, "NOT_SIGNED_UP")
		isNil(adj[full("Corin")])
		eq(#NC():AbsenceProposal().entries, 0)
	end)

	it("writes them at the close when the rules say autoApply", function()
		local L = bound()
		local rules = FDCP.Rules.DefaultConfig()
		rules.penalties.autoApply = true
		assert(FDCP.Rules.Change(L, { author = full("Aurel"), ts = 50, rules = rules, confirmed = true }))
		assert(NC():Open({ instanceID = 409, difficulty = "normal" }))
		assert(NC():SetState("Aurel", "RAID"))
		assert(NC():Close())
		local adj = adjustments(L)
		for _, name in ipairs({ "Bryn", "Corin", "Dara", "Edda" }) do eq(adj[full(name)].delta, 1) end
		isNil(adj[full("Aurel")])
		eq(adj[full("Bryn")].cause, "ABSENT")   -- the calendar has no raid event: sign-ups unknown
	end)

	it("refuses while the night is open or before any night closed", function()
		bound()
		local p, code = NC():AbsenceProposal()
		isNil(p); eq(code, "NO_NIGHT_CLOSED")
		local night = assert(NC():Open({ instanceID = 409, difficulty = "normal" }))
		p, code = NC():AbsenceProposal({ night = night.id })
		isNil(p); eq(code, "NIGHT_OPEN")
	end)

	it("a player's NBENCH on GUILD reaches the runner, which writes a self-bench", function()
		local L = bound()
		local night = assert(NC():Open({ instanceID = 409, difficulty = "normal" }))
		FDCP.Bus:Emit("NET_MESSAGE", { t = "NBENCH" }, "Dara", "GUILD")
		local states, origins = N().Lineup(L, night.id)
		eq(states[full("Dara")], "BENCH"); eq(origins[full("Dara")], "SELF")
		-- another channel, or someone outside the pool, changes nothing
		FDCP.Bus:Emit("NET_MESSAGE", { t = "NBENCH" }, "Edda", "RAID")
		isNil(N().Lineup(L, night.id)[full("Edda")])
		local e, code = NC():OnMessage({ t = "NBENCH" }, full("Nobody"), "GUILD")
		isNil(e); eq(code, "NOT_MEMBER")
		assert(NC():Close())
		eq(causes(NC():AbsenceProposal())[full("Dara")], "SELF_BENCH")
	end)

	it("the runner benches themselves at once; another client sends the request on GUILD", function()
		local L = bound()
		assert(FDCP.Roster.Join(L, { author = full("Bryn"), ts = 30, season = "S1", member = ME, faction = "Horde", ms1 = 73 }))
		local night = assert(NC():Open({ instanceID = 409, difficulty = "normal" }))
		local e = assert(NC():SelfBench())
		eq(e.type, "LINEUP_CHANGED"); deepEq(e.payload.self, { ME })
		-- a client that does not run the night: the request goes out
		local other = Lg().New()
		NC():Bind(other)
		Mock.chat.ClearSent()
		local okSent, how = NC():SelfBench()
		eq(okSent, true); eq(how, "SENT")
		Mock.Advance(2)
		local sent = Mock.chat.SentWithPrefix("FDCP1")
		eq(#sent, 1); eq(sent[1].chatType, "GUILD"); truthy(sent[1].message:find("|NBENCH|", 1, true))
		truthy(night)
	end)
end)

describe("the Night window and the absences", function()
	before_boot(guild(1))

	it("shows the proposed penalties after the close and confirms them with one click", function()
		local L = bound()
		Mock.Slash("/fdcp")
		FDCP.RosterWindow:Refresh()
		FDCP.RosterWindow:SelectSub("night")
		local root = FDCP.NightsWindow.root
		root.open:Click()
		assert(NC():SetState("Aurel", "RAID")); assert(NC():SetState("Bryn", "RAID")); assert(NC():SetState("Corin", "RAID"))
		assert(NC():Bench("Dara"))
		root.close:Click()
		eq(root.absence:GetText(), "Absence penalties proposed (1, +1 each): Edda (absent, sign-ups unknown)")
		truthy(root.confirmAbsence:IsShown())
		falsy(root.selfBench:IsShown())   -- the officer's view with no night open: the Open button is there
		root.confirmAbsence:Click()
		eq(root.message:GetText(), "Absence penalties written: 1.")
		eq(adjustments(L)[full("Edda")].delta, 1)
		eq(root.absence:GetText(), "")
		falsy(root.confirmAbsence:IsShown())
	end)

	it("offers Bench myself during a night", function()
		local L = bound()
		assert(FDCP.Roster.Join(L, { author = full("Bryn"), ts = 30, season = "S1", member = ME, faction = "Horde", ms1 = 73 }))
		Mock.Slash("/fdcp")
		FDCP.RosterWindow:Refresh()
		FDCP.RosterWindow:SelectSub("night")
		local root = FDCP.NightsWindow.root
		root.open:Click()
		truthy(root.selfBench:IsShown())
		root.selfBench:Click()
		eq(root.message:GetText(), "You are on the bench for tonight.")
		local _, origins = N().Lineup(L, N().Current(L, "S1").id)
		eq(origins[ME], "SELF")
	end)
end)

describe("the Night window for a member", function()
	before_boot(guild(3))

	it("a member has Bench myself and no penalties to confirm", function()
		bound()
		Mock.Slash("/fdcp")
		FDCP.RosterWindow:Refresh()
		FDCP.RosterWindow:SelectSub("night")
		local root = FDCP.NightsWindow.root
		FDCP.NightsWindow:Refresh()
		truthy(root.selfBench:IsShown())
		falsy(root.confirmAbsence:IsShown())
		Mock.chat.ClearSent()
		root.selfBench:Click()
		eq(root.message:GetText(), "Request sent: the officer running the night puts you on the bench.")
	end)

	it("speaks Italian", function()
		eq(FDCP.Locale.Text("itIT", "NIGHT_SELF_BENCH"), "Mettimi in panchina")
		eq(FDCP.Locale.Text("itIT", "RC_ABSENCE_NO_SHOW"), "iscritto, non presente")
	end)
end)
