-- Rolls only from the popup's button, once per item (M7-2d, docs/ANALISI.md §4, §4.1, §8.4): a small raid of five on
-- the network simulator (Tests/sim/sim.lua), every client a whole addon. A click on Roll sends the roll intent (SRINT)
-- and then calls the game's RandomRoll; the master looter's roll listener counts a server roll only with an intent of
-- the same player for the same round (rule session.buttonRollsOnly, on by default). Aurel is the Guild Master and the
-- master looter, the others raiders with the addon.
local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end
local NAMES = { "Aurel", "Bryn", "Corin", "Dara", "Elin" }
local RANKS = { Aurel = 0, Bryn = 3, Corin = 3, Dara = 3, Elin = 3 }
local BOSS, BOSS_GUID = 663, "Creature-0-3-2000-1-11502-0000A1B2C3"
local RING_LINK = "|cffa335ee|Hitem:19003::::::::70:::::|h[Ring of the Keeper]|h|r"

local function setupFor(name)
	return function(M)
		M.items.Add{ id = 19003, link = RING_LINK, name = "Ring of the Keeper", quality = 4, equipLoc = "INVTYPE_FINGER",
			classID = 4, subclassID = 0 }
		local members = {}
		for _, n in ipairs(NAMES) do
			if n ~= name then members[#members + 1] = { name = n, rank = RANKS[n], class = "WARRIOR" } end
		end
		M.guild.Set({ name = "Dragon", members = members, myRank = RANKS[name] })
		M.loot.Set{ method = "master", masterLooter = name == "Aurel", masterPartyID = 1, threshold = 3,
			candidates = NAMES, slots = {} }
		M.encounter.Set{ instance = { name = "Molten Core", type = "raid", difficultyID = 9, difficultyName = "Normal",
			maxPlayers = 40, instanceID = 409 } }
	end
end

local function A(c) return c.addon() end

-- The raid, the season, the rules (`tune(r)` changes them), the night, the kill and the ring's first round: Bryn and
-- Corin answer main-spec. Returns net, clients, the ML's controller. `opts.pv` = { [name] = protocol } for older clients.
local function raid(tune, opts)
	opts = opts or {}
	local net = Sim.new{ realm = REALM, step = 0.25 }
	local c = {}
	for _, n in ipairs(NAMES) do
		local pv = opts.pv and opts.pv[n]
		c[n] = net:Client(n, { setup = setupFor(n), pv = pv, pm = pv and 2 or nil })
	end
	net:Raid(NAMES)
	net:Advance(3)
	local a = A(c.Aurel)
	local L = assert(a.NightController:Ledger())
	assert(a.Season.Open(L, { author = full("Aurel"), ts = a.Compat.ServerTime(), season = "S1",
		instances = { { id = 409, size = 40 } } }, nil, a.PermissionService:Gate()))
	local r = a.Rules.Current(L)
	r.session.autoAdvance = false
	if tune then tune(r) end
	assert(a.Rules.Change(L, { author = full("Aurel"), ts = a.Compat.ServerTime(), rules = r, confirmed = true },
		a.PermissionService:Gate()))
	assert(a.NightController:Open({ instanceID = 409 }))
	net:Advance(20)
	net:Encounter(BOSS, "Lucifron", "kill")
	c.Aurel.Mock.loot.Set{ slots = { { link = RING_LINK, name = "Ring of the Keeper", quality = 4, sources = { BOSS_GUID, 1 } } } }
	c.Aurel.Mock.loot.Open()
	net:Advance(3)
	local SC = a.SessionController
	assert(SC:Command("START"))
	assert(SC:Command("OPEN_ROLL"))
	net:Advance(1)
	assert(A(c.Bryn).Protocol.Session:Respond("MS"))
	assert(A(c.Corin).Protocol.Session:Respond("MS"))
	net:Advance(1)
	return net, c, SC
end

-- A click on the popup's Roll button of `name`'s client, the server answering `value`.
local function click(net, c, name, value)
	net.rolls = net.rolls or {}
	net.rolls[name] = { value }
	return A(c[name]).MemberLootPopup:Roll()
end

local function discards(SC, code)
	local out = {}
	for _, d in ipairs(SC.session.items[1].discarded or {}) do
		if code == nil or d.code == code then out[#out + 1] = d.player end
	end
	return out
end

local function close(net, SC)
	net:Advance(1)
	assert(SC:Command("CLOSE_ROUND"))
	net:Advance(1)
	return SC.session
end

local function RL(c) return A(c.Aurel).RollListener end

describe("rolls only from the button", function()
	it("is on by default, validated, and older rules are filled in", function()
		local r = FDCP.Rules.DefaultConfig()
		eq(r.session.buttonRollsOnly, true)
		eq(r.session.buttonRollWindow, 10)
		truthy(FDCP.Rules.Validate(r))
		r.session.buttonRollWindow = 1
		local ok, problems = FDCP.Rules.Validate(r)
		falsy(ok); truthy(table.concat(problems, " "):find("session.buttonRollWindow", 1, true))
		local old = FDCP.Rules.DefaultConfig()
		old.session.buttonRollsOnly, old.session.buttonRollWindow = nil, nil
		local filled = FDCP.Rules.WithDefaults(old)
		eq(filled.session.buttonRollsOnly, true)
		-- a session saved before M7-2d has no key: off
		local on = FDCP.SessionFSM.ButtonRolls({ rules = { session = {} } })
		eq(on, false)
	end)

	it("discards a typed roll and accepts a button roll; the player is warned", function()
		local net, c, SC = raid()
		eq(A(c.Bryn).Protocol.Session.view.buttonRolls, true, "the raid hears the rule (bo)")
		-- Corin types /roll 100 by hand: no intent, the roll waits for one, then it is NOT_FROM_BUTTON
		local printed = #c.Corin.Mock.output
		net:Roll("Corin", 100)
		eq(RL(c):Pending(), 1, "the typed roll waits for an intent")
		truthy(#c.Corin.Mock.output > printed, "Corin's own client warns")
		truthy(c.Corin.Mock.output[#c.Corin.Mock.output]:find(A(c.Corin).L["POPUP_ROLL_TYPED"], 1, true))
		net:Advance(12)
		eq(RL(c):Pending(), 0)
		-- Bryn clicks Roll: the intent goes first, then the server's roll; no warning
		printed = #c.Bryn.Mock.output
		truthy(click(net, c, "Bryn", 40))
		net:Advance(1)
		eq(#c.Bryn.Mock.output, printed, "no warning after a click")
		-- the typed roll did not use Corin's turn: a click afterwards still counts
		truthy(click(net, c, "Corin", 30))
		local s = close(net, SC)
		deepEq(discards(SC, "NOT_FROM_BUTTON"), { full("Corin") })
		eq(s.items[1].proposal.winner, full("Bryn"), "Corin's typed 100 did not count")
		local byCode = RL(c):Stats().byCode
		eq(byCode.NOT_FROM_BUTTON, 1); eq(byCode.VALID, 2)
		-- the master looter's window shows the reason in the player's language
		local R = A(c.Aurel).Reasons
		eq(R.Key("DISCARD", "NOT_FROM_BUTTON"), "RC_DISCARD_NOT_FROM_BUTTON")
		truthy(R.Text("DISCARD", "NOT_FROM_BUTTON", "itIT"):find("pulsante Roll", 1, true))
	end)

	it("a double click or a second roll is a duplicate", function()
		local net, c, SC = raid()
		truthy(click(net, c, "Bryn", 40))
		local ok, code = A(c.Bryn).MemberLootPopup:Roll()   -- the second click: the button is locked
		falsy(ok); eq(code, "LOCKED")
		eq(#c.Bryn.Mock.loot.rolls, 1, "one RandomRoll")
		-- a second intent and a second roll anyway (a macro): the intent is ignored, the roll is a DUPLICATE
		local P = A(c.Bryn).Protocol.Session
		truthy(P:RollIntent())
		net:Advance(1)
		net:Roll("Bryn", 99)
		-- and a typed roll after the valid one is a DUPLICATE too
		truthy(click(net, c, "Corin", 30))
		net:Advance(1)
		net:Roll("Corin", 100)
		local s = close(net, SC)
		eq(RL(c):Stats().intentDups, 1)
		local dups = discards(SC, "DUPLICATE")
		table.sort(dups)
		deepEq(dups, { full("Bryn"), full("Corin") })
		eq(s.items[1].proposal.winner, full("Bryn"))
	end)

	it("an intent without a roll does nothing", function()
		local net, c, SC = raid()
		truthy(A(c.Corin).Protocol.Session:RollIntent())   -- the intent, and the roll never comes
		truthy(click(net, c, "Bryn", 40))
		local s = close(net, SC)
		eq(RL(c):Stats().intents, 2)
		eq(#s.items[1].rounds[1].rolls, 1)
		eq(s.items[1].proposal.winner, full("Bryn"))
		-- a typed roll in a later round does not borrow that old intent
		deepEq(discards(SC), {})
	end)

	it("a lockdown that delays the intent stays within the window", function()
		local net, c, SC = raid()
		-- Bryn's client is locked down: the intent waits in its queue, the server's roll goes out at once
		c.Bryn.Mock.chat.lockdown = true
		truthy(click(net, c, "Bryn", 40))
		c.Aurel.Mock.chat.lockdown = true   -- the master looter sees the lockdown too: the wait does not run out
		net:Advance(30)
		eq(RL(c):Pending(), 1, "still waiting after 30 seconds of lockdown")
		net:Lockdown(false)
		net:Advance(2)
		eq(RL(c):Pending(), 0)
		local s = close(net, SC)
		deepEq(discards(SC), {})
		eq(s.items[1].proposal.winner, full("Bryn"))
	end)

	it("a reroll among the tied works from the button", function()
		local net, c, SC = raid()
		truthy(click(net, c, "Bryn", 50))
		truthy(click(net, c, "Corin", 50))
		local s = close(net, SC)
		eq(s.state, "COMPUTING")
		assert(SC:Command("ADVANCE"))
		net:Advance(1)
		eq(A(c.Bryn).Protocol.Session.view.round.r, 2, "the reroll round")
		-- Corin types the reroll by hand: discarded; Bryn clicks
		net:Roll("Corin", 99)
		truthy(click(net, c, "Bryn", 20))
		net:Advance(12)
		truthy(click(net, c, "Corin", 10))
		s = close(net, SC)
		eq(s.items[1].proposal.winner, full("Bryn"))
		deepEq(discards(SC, "NOT_FROM_BUTTON"), { full("Corin") })
	end)

	it("an intent is always the sender's own and only for the open round", function()
		local net, c, SC = raid()
		local s = SC.session
		local ml = A(c.Aurel).Protocol.Session
		local forged, stale = ml.stats.forged, ml.stats.stale
		-- Corin sends an intent in Bryn's name, and one for a round that is not open
		A(c.Corin).Transport:Send("RAID", { t = "SRINT", s = s.id, i = 1, r = 1, n = "x1", p = full("Bryn") }, { prio = "ALERT" })
		A(c.Corin).Transport:Send("RAID", { t = "SRINT", s = s.id, i = 1, r = 7, n = "x2" }, { prio = "ALERT" })
		net:Advance(1)
		eq(ml.stats.forged, forged + 1, "FORGED")
		eq(ml.stats.stale, stale + 1, "STALE")
		-- Bryn's typed roll finds no intent of hers
		net:Roll("Bryn", 100)
		net:Advance(12)
		close(net, SC)
		deepEq(discards(SC, "NOT_FROM_BUTTON"), { full("Bryn") })
	end)

	it("with the rule off the old behaviour comes back", function()
		local net, c, SC = raid(function(r) r.session.buttonRollsOnly = false end)
		falsy(A(c.Bryn).Protocol.Session.view.buttonRolls)
		local printed = #c.Corin.Mock.output
		net:Roll("Corin", 100)
		eq(RL(c):Pending(), 0, "nothing waits")
		eq(#c.Corin.Mock.output, printed, "no warning")
		truthy(click(net, c, "Bryn", 40))
		local s = close(net, SC)
		deepEq(discards(SC), {})
		eq(s.items[1].proposal.winner, full("Corin"))
	end)

	it("a client of protocol 5 sends no intent: its rolls are judged as before", function()
		local net, c, SC = raid(nil, { pv = { Corin = 5 } })
		net:Roll("Corin", 100)
		eq(RL(c):Pending(), 0)
		truthy(click(net, c, "Bryn", 40))
		local s = close(net, SC)
		eq(s.items[1].proposal.winner, full("Corin"))
		truthy(RL(c).log[1].legacy)
	end)
end)
