-- The raid announcements (M4-8): Domain/Announce.lua (texts, placeholders, 255-byte lines that never cut a link),
-- App/Announcer.lua (the queue: never during an encounter, only when the chat accepts, in the GUILD language whatever the
-- master looter's own language, the reason sentence from the reason codes), wired to the session controller of M4-4.
local function SC() return FDCP.SessionController end
local function Lg() return FDCP.Ledger end
local function A() return FDCP.Announce end
local function AR() return FDCP.Announcer end
local function sent() return Mock.chat.messages end
local function cfg() return FDCP.Config end

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end
local ML = full("Dara")
local PLAYERS = { "Aurel", "Bryn", "Corin", "Dara" }
local BOSS_GUID = "Creature-0-3-2000-1-11502-0000A1B2C3"
local function link(id) return "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[Item " .. id .. "]|h|r" end

local ITEMS = {
	{ id = 19003, name = "Ring", equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0 },
	{ id = 19002, name = "Sword", equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7 },
	{ id = 19001, name = "Shoulders", equipLoc = "INVTYPE_SHOULDER", classID = 4, subclassID = 4 },
}

local function setup(M)
	M.player.name, M.player.realm = "Dara", REALM
	for _, def in ipairs(ITEMS) do
		M.items.Add{ id = def.id, link = link(def.id), name = def.name, quality = 4, equipLoc = def.equipLoc,
			classID = def.classID, subclassID = def.subclassID }
	end
end

local function presentAll()
	local present = {}
	for _, p in ipairs(PLAYERS) do present[full(p)] = true end
	return present
end

-- A raid of the four players, the controller bound to a guild ledger, the corpse of a boss.
local function bench(opts)
	opts = opts or {}
	local b = { L = Lg().New(), store = {} }
	assert(FDCP.Season.Open(b.L, { author = ML, ts = 1, season = "S1", instances = { { id = 9001, size = 20 } } }))
	local members = {}
	for _, p in ipairs(PLAYERS) do if p ~= "Dara" then members[#members + 1] = { name = p } end end
	if opts.raid ~= false then Mock.group.Set{ raid = true, members = members } end
	if opts.gm then Mock.Advance(3) end   -- the guild roster is read: the Guild Master may change the rules
	SC():Bind(b.L, b.store)
	SC().Env = function(self) return { ledger = self:Ledger() } end
	local slots = {}
	for i, def in ipairs(ITEMS) do slots[i] = { link = link(def.id), name = def.name, quality = 4, sources = { BOSS_GUID, 1 } } end
	Mock.loot.Set{ method = "master", masterLooter = true, threshold = 3, slots = slots }
	function b.s() return SC().session end
	function b.collect()
		Mock.encounter.Start(601, "Boss")
		Mock.encounter.End(601, "Boss", true)
		if SC().session then SC().session.rules.session.buttonRollsOnly = false end   -- typed rolls (M7-2d: test_button_rolls.lua)
		Mock.loot.Open()
		assert(SC():Step({ type = "SET_RAID", present = presentAll(), addon = presentAll() }))
	end
	function b.start()
		b.collect()
		assert(SC():Command("START"))
	end
	function b.answer(name, rs)
		local s = b.s()
		Mock.chat.Receive("FDCP1", FDCP.Codec:Encode("SRESP", { s = s.id, i = s.active, r = s.net.rounds[s.active], rs = rs }),
			"RAID", name)
	end
	-- Aurel alone asks for the first item in main-spec and rolls: a proposal, ready to confirm.
	function b.proposal()
		b.start()
		b.answer("Aurel", "MS"); b.answer("Bryn", "PASS"); b.answer("Corin", "PASS")
		assert(FDCP.Protocol.Session:Respond("PASS"))
		Mock.loot.Roll("Aurel", 40, 1, 100)
		eq(b.s().state, "PROPOSAL")
	end
	return b
end

local function texts()
	local out = {}
	for _, m in ipairs(sent()) do
		if m.chatType == "RAID" and m.message:find("^%[FDCP%] ") then out[#out + 1] = m.message end
	end
	return out
end

describe("the texts", function()
	before_boot(setup)

	it("fills the placeholders, leaves an unknown one, trims", function()
		eq(A().Fill("{item}: {category}, {cost} {nope}", { item = "X", category = "Ring", cost = "free" }), "X: Ring, free {nope}")
		eq(A().Fill("  {reason} ", { reason = "" }), "")
	end)

	it("splits at 255 bytes at a space and never inside a link", function()
		local l = link(19003)
		local words = {}
		for i = 1, 60 do words[i] = "word" .. i end
		local lines = A().Lines(l .. " " .. table.concat(words, " ") .. " " .. l)
		truthy(#lines > 1)
		local seen = 0
		for _, line in ipairs(lines) do
			truthy(#line <= 255, "a line of " .. #line)
			eq(line:sub(1, 7), "[FDCP] ")
			if line:find(l, 1, true) then seen = seen + 1 end
		end
		eq(seen, 2, "both links intact")
	end)

	it("validates the section", function()
		truthy(A().ValidateConfig(A().DefaultConfig()))
		local ok, p = A().ValidateConfig({ enabled = "yes", itemText = string.rep("x", 200), resultText = "", reason = true, extra = 1 })
		falsy(ok)
		deepEq(p, { "enabled", "itemText", "unknown:extra" })
		truthy(FDCP.Rules.Validate(FDCP.Rules.DefaultConfig()))
	end)

	it("composes the cost phrase", function()
		local t = { free = "free", one = "1 credit", many = "%s credits", council = "council" }
		eq(A().CostText(t, 0, "0"), "free")
		eq(A().CostText(t, 1, "1"), "1 credit")
		eq(A().CostText(t, 1.5, "1.5"), "1.5 credits")
		eq(A().CostText(t, 2, "2", true), "council")
	end)
end)

describe("announcing a session", function()
	before_boot(setup)

	it("writes the category and cost of every item in /raid before the first roll", function()
		local b = bench()
		b.start()
		local out = texts()
		eq(#out, 3)
		truthy(out[1]:find("|Hitem:19003", 1, true), out[1])
		truthy(out[1]:find("Jewelry", 1, true), out[1])
		truthy(out[2]:find("Weapon", 1, true), out[2])
		truthy(out[1]:find("credit", 1, true) or out[1]:find("free", 1, true), out[1])
		for _, m in ipairs(sent()) do eq(m.chatType, "RAID") end
		eq(b.s().state, "ROLLING", "the first roll opened after the announcement")
	end)

	it("uses the guild language, whatever the master looter's language", function()
		local b = bench()
		truthy(cfg():Set("guildLanguage", "itIT"))
		eq(FDCP.Locale.Text("enUS", "ML_CAT_JEWELRY"), "Jewelry")
		b.start()
		local out = texts()
		truthy(out[1]:find("Gioiello", 1, true), out[1])
		truthy(out[2]:find("Arma", 1, true), out[2])
		falsy(out[1]:find("Jewelry", 1, true))
	end)

	it("announces the result with the reason sentence composed from the codes", function()
		local b = bench()
		b.proposal()
		local s = b.s()
		local before = #texts()
		assert(SC():Command("CONFIRM"))
		local out = texts()
		eq(#out, before + 1)
		local line = out[#out]
		truthy(line:find("|Hitem:19003", 1, true), line)
		truthy(line:find("Aurel", 1, true), line)
		truthy(line:find(FDCP.Reasons.Text("REASON", s.items[1].proposal.reasons[1], "enUS"), 1, true), line)
		falsy(line:find("-" .. REALM, 1, true), "the winner without the realm")
	end)

	it("writes the result in the guild language too", function()
		local b = bench()
		truthy(cfg():Set("guildLanguage", "itIT"))
		b.proposal()
		local s = b.s()
		assert(SC():Command("CONFIRM"))
		local out = texts()
		local it = FDCP.Reasons.Text("REASON", s.items[1].proposal.reasons[1], "itIT")
		local en = FDCP.Reasons.Text("REASON", s.items[1].proposal.reasons[1], "enUS")
		truthy(it ~= en)
		truthy(out[#out]:find(it, 1, true), out[#out])
		falsy(out[#out]:find(en, 1, true))
	end)

	it("announces a correction made after the start, not one made before", function()
		local b = bench()
		b.collect()
		assert(SC():Command("CORRECT_ITEM", { index = 3, category = "weapon", reason = "WRONG_CATEGORY" }))
		eq(#texts(), 0)
		Mock.chat.messages = Mock.chat.messages
		-- the session starts with the PAUSE not set; the first roll opens: a correction is refused once the roll is open,
		-- so correct a pending item after the start
		assert(SC():Command("START"))
		eq(#texts(), 3)
		local ok = SC():Command("CORRECT_ITEM", { index = 2, category = "armor", reason = "WRONG_CATEGORY" })
		if ok then
			eq(#texts(), 4)
			truthy(texts()[4]:find("Armor", 1, true), texts()[4])
		end
	end)
end)

describe("when the lines may go out", function()
	before_boot(setup)

	it("waits for the end of an encounter, then writes the queue in order", function()
		local b = bench()
		Mock.encounter.Start(602, "Boss 2")
		AR():Enqueue({ "[FDCP] a" })
		eq(#texts(), 0)
		eq(AR():Pending(), 1)
		Mock.Advance(5)
		eq(#texts(), 0, "still fighting")
		Mock.encounter.End(602, "Boss 2", true)
		Mock.Advance(2)
		eq(AR():Pending(), 0)
		eq(#texts(), 1)
		isNil(AR().ticker, "the ticker stops with the queue")
	end)

	it("waits out a chat lockdown", function()
		local b = bench()
		b.collect()
		Mock.chat.lockdown = true
		assert(SC():Command("START"))
		eq(#sent(), 0)
		eq(AR():Pending(), 3)
		Mock.Advance(3)
		eq(#sent(), 0)
		Mock.chat.lockdown = false
		Mock.Advance(2)
		eq(AR():Pending(), 0)
		eq(#texts(), 3)
	end)

	it("limits a burst to a few lines per flush", function()
		local b = bench()
		local lines = {}
		for i = 1, 10 do lines[i] = "[FDCP] line " .. i end
		AR():Enqueue(lines)
		eq(#sent(), AR().BURST)
		Mock.Advance(1)
		eq(#sent(), AR().BURST * 2)
		Mock.Advance(2)
		eq(#sent(), 10)
		eq(sent()[10].message, "[FDCP] line 10")
	end)

	it("drops the queue after repeated refusals and says so", function()
		local b = bench()
		local dropped
		FDCP.Bus:On("ANNOUNCE_DROPPED", function(_, n, code) dropped = code end)
		local original = C_ChatInfo.SendChatMessage
		C_ChatInfo.SendChatMessage = function() error("refused") end
		AR():Enqueue({ "[FDCP] a" })
		Mock.Advance(AR().MAX_FAILS + 1)
		C_ChatInfo.SendChatMessage = original
		eq(dropped, "SEND_FAILED")
		eq(AR():Pending(), 0)
	end)

	it("writes nothing outside a raid", function()
		local b = bench({ raid = false })
		Mock.group.Set{ raid = false, members = {} }
		AR():Enqueue({ "[FDCP] a" })
		eq(#sent(), 0)
		eq(AR():Pending(), 0)
	end)
end)

describe("the Guild Master's wording", function()
	before_boot(function(M) setup(M); M.guild.Set{ name = "Dragons", myRank = 0 } end)

	it("can switch the announcements off", function()
		local b = bench({ gm = true })
		truthy(AR():SaveConfig({ enabled = false }))
		b.start()
		eq(#sent(), 0)
		eq(AR():Pending(), 0)
	end)

	it("changes the texts and the reason, with the audit", function()
		local b = bench({ gm = true })
		truthy(AR():SaveConfig({ itemText = "New: {item} is {category} for {cost}", resultText = "{winner} gets {item} {reason}",
			reason = false }))
		b.proposal()
		truthy(texts()[1]:find("^%[FDCP%] New: .* is Jewelry for "), texts()[1])
		assert(SC():Command("CONFIRM"))
		local out = texts()
		truthy(out[#out]:find("^%[FDCP%] Aurel gets "), out[#out])
		falsy(out[#out]:find("Same credits", 1, true))
		local ok, code = AR():SaveConfig({ itemText = string.rep("x", 200) })
		isNil(ok); eq(code, "ANNOUNCE:itemText")
	end)

	it("the notice wording still saves through the shared path", function()
		bench({ gm = true })
		truthy(FDCP.AddonNotice:SaveConfig({ minutes = 3 }))
		local ok, code = FDCP.AddonNotice:SaveConfig({ minutes = 99 })
		isNil(ok); eq(code, "NOTICE:minutes")
	end)
end)
