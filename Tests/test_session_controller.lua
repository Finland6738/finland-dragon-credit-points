-- The session controller (M4-4): App/SessionController.lua runs Domain/SessionFSM.lua on the master looter's client,
-- wired to the mock client: a boss kill (ENCOUNTER_END), the corpse (LOOT_OPENED through Adapters/LootSource.lua), the
-- raiders' responses (SRESP on RAID through Net/Protocol.lua), the server's /roll messages (Adapters/RollListener.lua),
-- the timers, a lockdown, a /reload in the middle of a reroll, and the ledger events it writes (docs/ANALISI.md §4).
local function SC() return FDCP.SessionController end
local function Lg() return FDCP.Ledger end
local function Codec() return FDCP.Codec end
local function PS() return FDCP.Protocol.Session end
local function RL() return FDCP.RollListener end

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end
local ML = full("Dara")
local PLAYERS = { "Aurel", "Bryn", "Corin", "Dara" }
local BOSS_GUID = "Creature-0-3-2000-1-11502-0000A1B2C3"

local function link(id) return "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[Item " .. id .. "]|h|r" end

-- Five epics of one boss (preset Patto prices them; the test reads the costs from the session).
local ITEMS = {
	{ id = 19003, name = "Ring", equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0 },
	{ id = 19001, name = "Shoulders", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 4 },
	{ id = 19002, name = "Sword", equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7 },
	{ id = 19007, name = "Helm", equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 4 },
	{ id = 19008, name = "Necklace", equipLoc = "INVTYPE_NECK", classID = 4, subclassID = 0 },
}

local function setup(M)
	M.player.name, M.player.realm = "Dara", REALM
	for _, def in ipairs(ITEMS) do
		M.items.Add{ id = def.id, link = link(def.id), name = def.name, quality = 4, equipLoc = def.equipLoc,
			classID = def.classID, subclassID = def.subclassID }
	end
end

-- The SavedVariables round trip of a table (plain data only).
local function ser(v)
	local t = type(v)
	if t == "number" then return string.format("%.17g", v) end
	if t == "string" then return string.format("%q", v) end
	if t == "boolean" then return tostring(v) end
	if t ~= "table" then error("cannot be saved: " .. t) end
	local parts = {}
	for k, x in pairs(v) do parts[#parts + 1] = "[" .. ser(k) .. "]=" .. ser(x) end
	return "{" .. table.concat(parts, ",") .. "}"
end
local function reloaded(v) return assert(loadstring("return " .. ser(v)))() end

-- A guild ledger with season S1, the controller bound to it and a saved-data table, the corpse of the boss.
local function bench(n)
	local b = { L = Lg().New(), store = {} }
	assert(FDCP.Season.Open(b.L, { author = ML, ts = 1, season = "S1", instances = { { id = 9001, size = 20 } } }))
	SC():Bind(b.L, b.store)
	-- offline there is no guild rank history: the permission gate is tested in test_permissions.lua
	SC().Env = function(self) return { ledger = self:Ledger() } end
	local slots = {}
	for i = 1, n or #ITEMS do
		slots[i] = { link = link(ITEMS[i].id), name = ITEMS[i].name, quality = 4, sources = { BOSS_GUID, 1 } }
	end
	Mock.loot.Set{ method = "master", masterLooter = true, threshold = 3, slots = slots }
	function b.s() return SC().session end
	function b.item(i) local s = b.s(); return s.items[i or s.active] end
	function b.kill()
		Mock.encounter.Start(601, "Boss")
		Mock.encounter.End(601, "Boss", true)
	end
	function b.raid()
		local present = {}
		for _, p in ipairs(PLAYERS) do present[full(p)] = true end
		assert(SC():Step({ type = "SET_RAID", present = present, addon = present }))
	end
	-- kill, corpse, raid, start: the first item's roll opens by itself (autoAdvance)
	function b.open()
		b.kill()
		Mock.loot.Open()
		b.raid()
		assert(SC():Command("START"))
	end
	-- A raider's answer, as it travels: SRESP on RAID (the ML's own goes through Protocol.Session:Respond).
	function b.respond(name, rs)
		if full(name) == ML then return assert(PS():Respond(rs)) end
		local s = b.s()
		Mock.chat.Receive("FDCP1", Codec():Encode("SRESP", { s = s.id, i = s.active, r = s.net.rounds[s.active], rs = rs }),
			"RAID", name)
	end
	function b.answers(map)
		for _, p in ipairs(PLAYERS) do b.respond(p, map[p] or "PASS") end
	end
	function b.roll(name, value) Mock.loot.Roll(name, value, 1, 100) end
	function b.awards() return Lg().Sorted(b.L, function(e) return e.type == "ITEM_AWARDED" end) end
	return b
end

local function has(list, value)
	for _, v in ipairs(list or {}) do if v == value then return true end end
	return false
end

describe("a session from a boss kill", function()
	before_boot(setup)

	it("opens in WAITING after the kill on the master looter's client, saved in the guild data", function()
		local b = bench()
		b.kill()
		local s = b.s()
		eq(s.state, "WAITING")
		eq(s.ml, ML)
		eq(s.season, "S1")
		eq(s.encounter, 601)
		truthy(b.store.session == s, "the saved table is the session itself")
		truthy(PS().host == s, "hosted on the protocol")
		truthy(RL().getSession, "the roll listener is attached")
	end)

	it("does nothing on a wipe or on a client that is not the master looter", function()
		local b = bench()
		Mock.encounter.Start(601, "Boss")
		Mock.encounter.End(601, "Boss", false)
		isNil(b.s())
		Mock.loot.Set{ masterLooter = false }
		b.kill()
		isNil(b.s())
		local _, code = SC():OnKill({ encounterID = 601, success = true })
		eq(code, "NOT_MASTER_LOOTER")
	end)

	it("collects the corpse into the session when the ML opens it", function()
		local b = bench()
		b.kill()
		Mock.loot.Open()
		local s = b.s()
		eq(s.state, "COLLECTING")
		eq(#s.items, 5)
		eq(s.items[1].itemID, 19003)
		eq(s.items[3].category, "weapon")
	end)
end)

describe("a whole boss: five items, a reroll, an empty main-spec tier, a fallback", function()
	before_boot(setup)

	it("ends with the right ITEM_AWARDED events in the ledger", function()
		local b = bench()
		local delivered = {}
		FDCP.Bus:On("SESSION_DELIVER", function(_, e) delivered[#delivered + 1] = e.item end)
		b.open()
		local s = b.s()
		eq(s.state, "ROLLING"); eq(s.active, 1)
		eq(PS().view.a, 1, "the raid's view follows")

		-- 1. Ring: Aurel and Bryn main-spec, same credits, same roll: the addon opens a reroll among them by itself
		b.answers({ Aurel = "MS", Bryn = "MS", Corin = "OS" })
		b.roll("Aurel", 50); b.roll("Bryn", 50)
		eq(s.state, "ROLLING")
		eq(b.item().round.kind, "REROLL")
		deepEq(b.item().round.among, { full("Aurel"), full("Bryn") })
		b.roll("Corin", 99)   -- not one of the tied: discarded
		b.roll("Aurel", 80); b.roll("Bryn", 20)
		eq(s.state, "PROPOSAL")
		eq(b.item().proposal.winner, full("Aurel"))
		assert(SC():Command("CONFIRM"))
		eq(s.items[1].state, "ASSIGNED")

		-- 2. Shoulders: nobody main-spec; the off-spec round opens by itself; credits first (Aurel paid the ring)
		eq(s.active, 2, "the next item opens by itself")
		b.answers({ Aurel = "OS", Bryn = "OS", Corin = "OS" })
		eq(b.item().round.tier, 2)
		eq(b.item().dropped.code, "TIER_EMPTY")
		b.roll("Aurel", 100); b.roll("Bryn", 90); b.roll("Corin", 40)
		eq(b.item().proposal.winner, full("Bryn"))
		eq(b.item().proposal.response, "OS")
		assert(SC():Command("CONFIRM"))

		-- 3. Sword: Corin has fewer credits than Aurel, whatever the roll
		b.answers({ Aurel = "MS", Corin = "MS" })
		b.roll("Aurel", 99); b.roll("Corin", 5)
		eq(b.item().proposal.winner, full("Corin"))
		truthy(has(b.item().proposal.reasons, "LOWER_CREDITS"))
		assert(SC():Command("CONFIRM"))

		-- 4. Helm: the only candidate
		b.answers({ Bryn = "MS" })
		b.roll("Bryn", 12)
		eq(b.item().proposal.winner, full("Bryn"))
		assert(SC():Command("CONFIRM"))

		-- 5. Necklace: everybody passes, the fallback leaves it to the ML, who gives it with a reason
		b.answers({})
		eq(s.state, "PROPOSAL")
		isNil(b.item().proposal.winner)
		local ok, code = SC():Command("CONFIRM")
		falsy(ok); eq(code, "NO_WINNER")
		falsy(SC():Command("MODIFY", { winner = full("Aurel") }), "a reason is mandatory")
		assert(SC():Command("MODIFY", { winner = full("Aurel"), reason = "OTHER" }))
		assert(SC():Command("CONFIRM"))
		eq(s.state, "ANNOUNCING")
		assert(SC():Command("END"))
		eq(s.state, "ENDED")
		isNil(SC().ticker, "the ticker stops with the session")
		isNil(RL().getSession, "and the roll listener")

		local awards = b.awards()
		eq(#awards, 5)
		local expect = {
			{ member = full("Aurel"), item = 19003, response = "MS", cost = s.items[1].costs.MS },
			{ member = full("Bryn"), item = 19001, response = "OS", cost = s.items[2].costs.OS },
			{ member = full("Corin"), item = 19002, response = "MS", cost = s.items[3].costs.MS },
			{ member = full("Bryn"), item = 19007, response = "MS", cost = s.items[4].costs.MS },
			{ member = full("Aurel"), item = 19008, cost = s.items[5].costs.MS },
		}
		for i, want in ipairs(expect) do
			local p = awards[i].payload
			eq(awards[i].author, ML)
			eq(awards[i].season, "S1")
			eq(p.member, want.member, "award " .. i)
			eq(p.item, want.item, "award " .. i)
			eq(p.response, want.response, "award " .. i)
			eq(p.cost, want.cost, "award " .. i)
			eq(p.session, s.id)
			eq(p.encounter, 601)
			eq(p.target, "member")
		end
		truthy(awards[1].payload.reroll, "the ring was won on the reroll")
		truthy(has(awards[1].payload.reasons, "REROLL_WON"))
		truthy(has(awards[2].payload.reasons, "OFFSPEC_TIER"))
		truthy(awards[5].payload.intervention)
		eq(awards[5].payload.mlReason, "OTHER")
		truthy(has(awards[5].payload.flags, "ML_DECIDED"))
		deepEq(delivered, { 1, 2, 3, 4, 5 })
		local credits = Lg().Credits(b.L, "S1")
		eq(credits[full("Aurel")], s.items[1].costs.MS + s.items[5].costs.MS)
	end)
end)

describe("timers, pause and the lockdown", function()
	before_boot(setup)

	it("closes a round on its timer, and never while it is paused", function()
		local b = bench(1)
		b.open()
		b.answers({ Aurel = "MS", Bryn = "MS" })
		b.roll("Aurel", 70)   -- Bryn never rolls
		eq(b.s().state, "ROLLING")
		assert(SC():Command("PAUSE"))
		Mock.Advance(60)
		eq(b.s().state, "ROLLING", "paused: the timer waits")
		assert(SC():Command("RESUME"))
		Mock.Advance(35)
		eq(b.s().state, "PROPOSAL")
		eq(b.item().proposal.winner, full("Aurel"))
	end)

	it("does not let time close a round while hidden rolls wait in the roll listener's buffer", function()
		local b = bench(1)
		b.open()
		b.answers({ Aurel = "MS", Bryn = "MS" })
		RL().buffer[1] = { text = Mock.SECRET, ts = FDCP.Compat.Now() }
		Mock.chat.lockdown = true
		Mock.Advance(45)
		eq(b.s().state, "ROLLING")
		eq(b.s().lockdown, true, "the session knows the chat is locked down")
		RL().buffer = {}
		Mock.chat.lockdown = false
		Mock.Advance(2)
		eq(b.s().lockdown, false)
		eq(b.s().state, "PROPOSAL")
	end)

	it("holds the corpse during a lockdown and collects it once the lockdown is over", function()
		local b = bench()
		b.kill()
		Mock.chat.lockdown = true
		local held
		FDCP.Bus:On("SESSION_HELD", function(_, code) held = code end)
		Mock.loot.Open()
		eq(held, "LOCKDOWN")
		eq(b.s().state, "WAITING")
		Mock.Advance(3)
		eq(b.s().state, "WAITING")
		Mock.chat.lockdown = false
		Mock.Advance(1.5)
		eq(b.s().state, "COLLECTING")
		eq(#b.s().items, 5)
	end)

	it("ignores a corpse while another boss is engaged, until the encounter ends", function()
		local b = bench()
		b.kill()
		Mock.encounter.inProgress = true
		Mock.loot.Open()
		eq(b.s().state, "WAITING")
		Mock.encounter.inProgress = false
		Mock.Advance(1.5)
		eq(b.s().state, "COLLECTING")
	end)
end)

describe("a /reload in the middle of a session", function()
	before_boot(setup)

	it("resumes from the saved data in the middle of a reroll and ends with the same result", function()
		local b = bench(1)
		b.open()
		b.answers({ Aurel = "MS", Bryn = "MS" })
		b.roll("Aurel", 33); b.roll("Bryn", 33)
		eq(b.item().round.kind, "REROLL")
		local id = b.s().id

		-- /reload: only the saved data survives
		local saved = reloaded(b.store)
		SC():Reset()
		PS():Reset()
		RL():Reset()
		isNil(SC().session)
		local s = SC():Bind(b.L, saved)
		SC().Env = function(self) return { ledger = self:Ledger() } end
		truthy(s)
		eq(s.id, id)
		eq(s.state, "ROLLING")
		truthy(PS().host == s, "hosted again")
		eq(PS().view.a, 1, "the ML's view is rebuilt from the session")
		truthy(RL().getSession, "rolls are read again")

		b.roll("Aurel", 10); b.roll("Bryn", 60)
		eq(s.state, "PROPOSAL")
		eq(s.items[1].proposal.winner, full("Bryn"))
		assert(SC():Command("CONFIRM"))
		local awards = b.awards()
		eq(#awards, 1)
		eq(awards[1].payload.member, full("Bryn"))
		eq(awards[1].payload.session, id)
	end)

	it("does not resume another character's session", function()
		local store = { session = { id = "X", ml = full("Bryn"), items = {}, rules = {}, state = "ANNOUNCING" } }
		isNil(SC():Bind(Lg().New(), store))
	end)

	it("resumes a session of a newer addon read-only", function()
		local b = bench(1)
		b.kill()
		local saved = reloaded(b.store)
		saved.session.schema = 99
		SC():Reset()
		SC():Bind(b.L, saved)
		truthy(SC().readOnly)
		local ok, code = SC():Command("START")
		falsy(ok); eq(code, "READ_ONLY")
	end)
end)

describe("commands and views", function()
	before_boot(setup)

	it("refuses commands without a session, and gives other officers the read-only view", function()
		bench(1)
		local ok, code = SC():Command("START")
		falsy(ok); eq(code, "NO_SESSION")
		isNil(SC():View())
		PS().view = { s = "S1-9", ml = full("Bryn"), items = {}, mine = {}, responses = {} }
		FDCP.PermissionService.Can = function() return false, "RANK_TOO_LOW" end
		isNil(SC():View(), "a raider sees the popup, not the session window")
		FDCP.PermissionService.Can = function() return true end
		local v = SC():View()
		eq(v.host, false); eq(v.readOnly, true); eq(v.view.ml, full("Bryn"))
	end)

	it("gives the host its own session", function()
		local b = bench(1)
		b.kill()
		local v = SC():View()
		eq(v.host, true)
		truthy(v.session == b.s())
	end)

	it("moves on to the next boss: a session with no item in progress ends, one in progress refuses", function()
		local b = bench(1)
		b.open()
		local first = b.s()
		local _, code = SC():OnKill({ encounterID = 602, success = true })
		eq(code, "SESSION_RUNNING")
		b.answers({})
		assert(SC():Command("MODIFY", { winner = full("Corin"), reason = "OTHER" }))
		assert(SC():Command("CONFIRM"))
		local s = assert(SC():OnKill({ encounterID = 602, success = true }))
		eq(first.state, "ENDED")
		eq(s.encounter, 602)
		eq(s.state, "WAITING")
		truthy(b.store.session == s)
	end)
end)
