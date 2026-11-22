-- BoE and the guild bank fallback (M5-7, docs/ANALISI.md §3.8): a BoE is rolled like any item and costs credits when
-- someone takes it as main-spec; without main-spec answers it follows priority.boeFallback (bank, the preset; offspec;
-- disenchant; freeroll). An item for the bank goes to the bank character at cost 0 and never moves credits; an officer
-- records the gold of its sale later (BANK_ITEM_SOLD, Domain/GuildBank.lua) with /fdcp bank. The last part runs the
-- whole path on the mock client: the bank award is handed over by master loot to the bank character.
local function F() return FDCP.SessionFSM end
local function Lg() return FDCP.Ledger end
local function GB() return FDCP.GuildBank end

local ML = "Dara"
local SEASON = "S1"
local RAID = { Aurel = true, Bryn = true, Corin = true, Dara = true }
local POOL = { "Aurel", "Bryn", "Corin", "Dara" }
local BANK = "Oste"
local DE = "Elin"

-- A BoE shoulder (Pricing, preset Patto: main-spec 1 credit, off-spec free) and a ring that binds on pickup.
local BOE = { itemID = 19006, slot = 6, classID = 4, subclassID = 4, equipLoc = "INVTYPE_SHOULDER", quality = 4,
	boe = true }
local RING = { itemID = 19003, slot = 1, classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER", quality = 4 }

local function has(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then return true end
	end
	return false
end

-- A season with the pool on a fresh ledger: every member starts at 0 credits.
local function season(opts)
	local L = Lg().New()
	assert(FDCP.Season.Open(L, { author = ML, ts = 1, season = SEASON, instances = { { id = 409, size = 40 } } }, nil, opts))
	for i, name in ipairs(POOL) do
		assert(FDCP.Members.Join(L, { author = ML, ts = 1 + i, season = SEASON, member = name }, nil, opts))
	end
	return L
end

local ZERO = { Aurel = 0, Bryn = 0, Corin = 0, Dara = 0 }

local function rules(mutate)
	local r = FDCP.Rules.DefaultConfig()
	r.session.autoAdvance = false
	r.priority.bankCharacter = BANK
	r.priority.disenchanter = DE
	if mutate then mutate(r.priority, r) end
	return r
end

-- A session on a ledger with the pool. opts = { rules }.
local function bench(opts)
	opts = opts or {}
	local b = { L = season(), t = 1000 }
	b.s = assert(F().New({ id = "S1-1", season = SEASON, ml = ML, ts = 1000, encounter = 601, rules = opts.rules or rules(),
		present = RAID, addon = RAID }))
	function b.step(input)
		input.ts = input.ts or b.t
		return F().Step(b.s, input, { ledger = b.L })
	end
	function b.must(input)
		local ok, code, effects = b.step(input)
		if not ok then error("refused " .. tostring(input.type) .. ": " .. tostring(code), 2) end
		return effects
	end
	function b.ml(kind, extra)
		local input = extra or {}
		input.type, input.by = kind, ML
		return b.must(input)
	end
	function b.start(items)
		b.must({ type = "LOOT_OPENED", items = items or { BOE }, encounter = 601 })
		b.ml("START")
		b.ml("OPEN_ROLL")
	end
	-- Everybody answers (PASS when not given) and the round closes.
	function b.answer(responses)
		for _, p in ipairs(POOL) do
			b.must({ type = "RESPONSE", player = p, response = responses[p] or "PASS" })
		end
	end
	function b.roll(player, value) return b.must({ type = "ROLL", player = player, value = value, min = 1, max = 100 }) end
	function b.item(i) return b.s.items[i or b.s.active] end
	function b.proposal() return b.item().proposal end
	function b.awards() return Lg().Sorted(b.L, function(e) return e.type == "ITEM_AWARDED" end) end
	function b.credits() return Lg().Credits(b.L, SEASON) end
	return b
end

---------------------------------------------------------------------------------------------------------------------

describe("a BoE in the session", function()
	it("is rolled like any item: a main-spec winner pays the category's cost", function()
		local b = bench()
		b.start()
		b.answer({ Aurel = "MS", Bryn = "OS" })
		b.roll("Aurel", 40)
		b.ml("CLOSE_ROUND")
		local p = b.proposal()
		eq(p.kind, "AWARD"); eq(p.winner, "Aurel"); eq(p.response, "MS"); eq(p.cost, b.item().costs.MS)
		truthy(p.cost > 0, "a BoE costs credits like a bind-on-pickup item of its category")
		b.ml("CONFIRM")
		eq(b.awards()[1].payload.target, "member")
		eq(b.credits().Aurel, p.cost)
		eq(#GB().Items(b.L, SEASON), 0, "nothing went to the bank")
	end)

	it("costs the same as a bind-on-pickup item of the same category", function()
		local b = bench()
		b.must({ type = "LOOT_OPENED", items = { BOE, { itemID = 19001, slot = 2, classID = 4, subclassID = 4,
			equipLoc = "INVTYPE_SHOULDER", quality = 4 } }, encounter = 601 })
		deepEq(b.s.items[1].costs, b.s.items[2].costs)
		truthy(b.s.items[1].boe); isNil(b.s.items[2].boe)
	end)

	it("fallback bank (the preset): no main-spec answer, the bank character gets it at cost 0", function()
		eq(FDCP.Rules.DefaultConfig().priority.boeFallback, "bank")
		local b = bench()
		b.start()
		b.answer({ Aurel = "OS", Bryn = "OS" })
		b.ml("CLOSE_ROUND")
		local p = b.proposal()
		eq(p.kind, "BANK"); eq(p.winner, BANK); eq(p.cost, 0)
		deepEq(p.reasons, { "BOE_BANK" })
		isNil(b.item().next, "the off-spec tier does not open")
		b.ml("CONFIRM")
		local e = b.awards()[1]
		eq(e.payload.target, "bank"); eq(e.payload.member, BANK); eq(e.payload.cost, 0)
		deepEq(b.credits(), ZERO)
		local items = GB().Items(b.L, SEASON)
		eq(#items, 1); eq(items[1].id, e.id); eq(items[1].item, BOE.itemID); eq(items[1].member, BANK)
		isNil(items[1].copper)
	end)

	it("fallback bank: a BoE whose main-spec answers do not roll goes to the bank too", function()
		local b = bench()
		b.start()
		b.answer({ Aurel = "MS" })
		b.ml("CLOSE_ROUND")
		eq(b.proposal().kind, "BANK")
		b.ml("CONFIRM")
		deepEq(b.credits(), ZERO)
	end)

	it("fallback offspec: the off-spec tier rolls for it, at the off-spec cost", function()
		local b = bench({ rules = rules(function(p) p.boeFallback = "offspec" end) })
		b.start()
		b.answer({ Aurel = "OS", Bryn = "OS" })
		b.ml("CLOSE_ROUND")
		eq(b.s.state, "COMPUTING"); eq(b.item().next.tier, 2)
		b.ml("ADVANCE")
		b.roll("Aurel", 20); b.roll("Bryn", 60)
		b.ml("CLOSE_ROUND")
		local p = b.proposal()
		eq(p.kind, "AWARD"); eq(p.winner, "Bryn"); eq(p.response, "OS"); eq(p.cost, b.item().costs.OS)
		b.ml("CONFIRM")
		eq(b.awards()[1].payload.target, "member")
		eq(b.credits().Bryn, b.item(1).costs.OS)
		eq(#GB().Items(b.L, SEASON), 0)
	end)

	it("fallback offspec without off-spec answers: the general fallback decides (the master looter)", function()
		local b = bench({ rules = rules(function(p) p.boeFallback = "offspec" end) })
		b.start()
		b.answer({})
		b.ml("CLOSE_ROUND")
		eq(b.proposal().kind, "ML"); isNil(b.proposal().winner)
	end)

	it("fallback disenchant: the disenchanter gets it at cost 0", function()
		local b = bench({ rules = rules(function(p) p.boeFallback = "disenchant" end) })
		b.start()
		b.answer({ Aurel = "OS" })
		b.ml("CLOSE_ROUND")
		local p = b.proposal()
		eq(p.kind, "DISENCHANT"); eq(p.winner, DE); eq(p.cost, 0)
		deepEq(p.reasons, { "FALLBACK_DISENCHANT" })
		b.ml("CONFIRM")
		eq(b.awards()[1].payload.target, "disenchant")
		deepEq(b.credits(), ZERO)
		eq(#GB().Items(b.L, SEASON), 0, "a disenchanted item is not the bank's")
	end)

	it("fallback freeroll: everybody may roll, the winner pays priority.freeRollCost", function()
		local b = bench({ rules = rules(function(p) p.boeFallback = "freeroll"; p.freeRollCost = 0.5 end) })
		b.start()
		b.answer({ Aurel = "OS" })
		b.ml("CLOSE_ROUND")
		eq(b.s.state, "COMPUTING"); eq(b.item().next.stage, "FREE_ROLL")
		b.ml("ADVANCE")
		b.roll("Corin", 30); b.roll("Dara", 85)
		b.ml("CLOSE_ROUND")
		local p = b.proposal()
		eq(p.winner, "Dara"); eq(p.cost, 0.5)
		truthy(has(p.reasons, "FALLBACK_FREE_ROLL"))
		b.ml("CONFIRM")
		eq(b.credits().Dara, 0.5)
		eq(#GB().Items(b.L, SEASON), 0)
	end)

	it("fallback freeroll at the preset's cost 0 moves no credits", function()
		local b = bench({ rules = rules(function(p) p.boeFallback = "freeroll" end) })
		b.start()
		b.answer({})
		b.ml("CLOSE_ROUND")
		b.ml("ADVANCE")
		b.roll("Aurel", 70)
		b.ml("CLOSE_ROUND")
		eq(b.proposal().winner, "Aurel"); eq(b.proposal().cost, 0)
		b.ml("CONFIRM")
		deepEq(b.credits(), ZERO)
	end)

	it("an item that binds on pickup never takes the BoE fallback", function()
		local b = bench()
		b.start({ RING })
		b.answer({ Aurel = "OS" })
		b.ml("CLOSE_ROUND")
		eq(b.s.state, "COMPUTING"); eq(b.item().next.tier, 2, "the off-spec tier opens as usual")
	end)

	it("without a bank character the master looter chooses who receives it, still at cost 0", function()
		local b = bench({ rules = rules(function(p) p.bankCharacter = nil end) })
		b.start()
		b.answer({})
		b.ml("CLOSE_ROUND")
		eq(b.proposal().kind, "BANK"); isNil(b.proposal().winner)
		truthy(has(b.proposal().flags, "NO_BANK_CHARACTER"))
		local ok, code = b.step({ type = "CONFIRM", by = ML })
		falsy(ok); eq(code, "NO_WINNER")
		b.ml("MODIFY", { target = "bank", winner = "Corin", reason = "OTHER" })
		eq(b.proposal().kind, "BANK"); eq(b.proposal().winner, "Corin"); eq(b.proposal().cost, 0)
		b.ml("CONFIRM")
		eq(b.awards()[1].payload.target, "bank")
		deepEq(b.credits(), ZERO, "a raider holding the bank's item is not charged")
	end)

	it("a main-spec proposal sent to the bank by the master looter charges nobody", function()
		local b = bench()
		b.start()
		b.answer({ Aurel = "MS" })
		b.roll("Aurel", 40)
		b.ml("CLOSE_ROUND")
		eq(b.proposal().winner, "Aurel")
		b.ml("REJECT", { ["then"] = "BANK" })
		eq(b.proposal().kind, "BANK"); eq(b.proposal().winner, BANK); eq(b.proposal().cost, 0)
		b.ml("CONFIRM")
		deepEq(b.credits(), ZERO)
		eq(#GB().Items(b.L, SEASON), 1)
	end)

	it("a bank award with a cost (written by hand) still moves no credits", function()
		local L = season()
		assert(Lg().Append(L, { author = ML, ts = 50, season = SEASON, type = "ITEM_AWARDED",
			payload = { target = "bank", member = "Aurel", item = BOE.itemID, cost = 3 } }))
		deepEq(Lg().Credits(L, SEASON), ZERO)
		deepEq(Lg().Credits(L, SEASON, { full = true }), ZERO)
	end)
end)

---------------------------------------------------------------------------------------------------------------------

-- A ledger with two bank items (BOE then RING) and one award to a member.
local function bankLedger(opts)
	local L = season(opts)
	local a = assert(Lg().Append(L, { author = ML, ts = 50, season = SEASON, type = "ITEM_AWARDED",
		payload = { target = "bank", member = BANK, item = BOE.itemID, cost = 0, reasons = { "BOE_BANK" } } }, opts))
	local b = assert(Lg().Append(L, { author = ML, ts = 60, season = SEASON, type = "ITEM_AWARDED",
		payload = { target = "bank", member = BANK, item = RING.itemID, cost = 0, reasons = { "REJECTED_TO_BANK" } } }, opts))
	local m = assert(Lg().Append(L, { author = ML, ts = 70, season = SEASON, type = "ITEM_AWARDED",
		payload = { target = "member", member = "Aurel", item = 19001, cost = 1 } }, opts))
	return L, a, b, m
end

describe("the gold of a bank item's sale", function()
	it("lists the bank items of the season, oldest first, unsold", function()
		local L, a, b = bankLedger()
		local items = GB().Items(L, SEASON)
		eq(#items, 2)
		eq(items[1].id, a.id); eq(items[1].item, BOE.itemID); deepEq(items[1].reasons, { "BOE_BANK" })
		eq(items[2].id, b.id); eq(items[2].item, RING.itemID)
		deepEq(GB().Totals(L, SEASON), { items = 2, sold = 0, copper = 0 })
		eq(#GB().Items(L, "S2"), 0, "the bank list belongs to its season")
	end)

	it("records a sale in copper; credits never change", function()
		local L, a = bankLedger()
		local before = Lg().Credits(L, SEASON)
		eq(before.Aurel, 1)
		local e = assert(GB().RecordSale(L, { author = "Bryn", ts = 500, ref = a.id, copper = 1234567 }))
		eq(e.type, "BANK_ITEM_SOLD"); eq(e.season, SEASON)
		deepEq(e.payload, { ref = a.id, copper = 1234567 })
		local entry = GB().Get(L, a.id)
		eq(entry.copper, 1234567); eq(entry.sale, e.id); eq(entry.soldBy, "Bryn"); eq(entry.soldAt, 500)
		deepEq(GB().Totals(L, SEASON), { items = 2, sold = 1, copper = 1234567 })
		deepEq(Lg().Credits(L, SEASON), before)
		deepEq(Lg().Credits(L, SEASON, { full = true }), before)
	end)

	it("a second sale corrects the first: the last one counts", function()
		local L, a = bankLedger()
		assert(GB().RecordSale(L, { author = "Bryn", ts = 500, ref = a.id, copper = 10000 }))
		local e2 = assert(GB().RecordSale(L, { author = "Corin", ts = 600, ref = a.id, copper = 25000 }))
		local entry = GB().Get(L, a.id)
		eq(entry.copper, 25000); eq(entry.sale, e2.id); eq(entry.soldBy, "Corin")
		eq(GB().Totals(L, SEASON).copper, 25000)
	end)

	it("a sale whose clock ran behind the award still finds it", function()
		local L, a = bankLedger()
		assert(GB().RecordSale(L, { author = "Bryn", ts = 10, ref = a.id, copper = 500 }))
		eq(GB().Get(L, a.id).copper, 500)
	end)

	it("refuses an item that is not the bank's, a voided award and a bad price", function()
		local L, a, _, m = bankLedger()
		local cases = {
			{ { ref = m.id, copper = 1 }, "NOT_BANK_ITEM" },
			{ { ref = "Nobody:1", copper = 1 }, "NOT_BANK_ITEM" },
			{ { ref = 42, copper = 1 }, "NOT_BANK_ITEM" },
			{ { ref = a.id, copper = -1 }, "BAD_GOLD" },
			{ { ref = a.id, copper = 1.5 }, "BAD_GOLD" },
			{ { ref = a.id, copper = GB().MAX_COPPER + 1 }, "BAD_GOLD" },
			{ { ref = a.id }, "BAD_GOLD" },
		}
		for _, case in ipairs(cases) do
			local d = case[1]
			d.author, d.ts = "Bryn", 500
			local e, code = GB().RecordSale(L, d)
			isNil(e); eq(code, case[2], tostring(d.ref) .. " " .. tostring(d.copper))
		end
		assert(Lg().Append(L, { author = ML, ts = 400, season = SEASON, type = "AWARD_VOIDED",
			payload = { ref = a.id, reason = "OTHER" } }))
		local e, code = GB().RecordSale(L, { author = "Bryn", ts = 500, ref = a.id, copper = 1 })
		isNil(e); eq(code, "BANK_ITEM_VOIDED")
		eq(#GB().Items(L, SEASON), 1, "a voided bank award leaves the list")
		isNil(GB().Get(L, a.id))
	end)

	it("a sale recorded before the award was voided stops counting", function()
		local L, a = bankLedger()
		assert(GB().RecordSale(L, { author = "Bryn", ts = 500, ref = a.id, copper = 9000 }))
		assert(Lg().Append(L, { author = ML, ts = 600, season = SEASON, type = "AWARD_VOIDED",
			payload = { ref = a.id, reason = "OTHER" } }))
		deepEq(GB().Totals(L, SEASON), { items = 1, sold = 0, copper = 0 })
	end)

	it("the ledger checks the payload: a ref and a whole number of copper", function()
		local base = { author = "Bryn", seq = 1, id = "Bryn:1", ts = 1, season = SEASON, type = "BANK_ITEM_SOLD", v = 1 }
		local function check(payload)
			local e = {}
			for k, v in pairs(base) do e[k] = v end
			e.payload = payload
			return Lg().Check(e)
		end
		truthy(check({ ref = "Dara:5", copper = 0 }))
		local ok, code = check({ ref = "nope", copper = 1 })
		falsy(ok); eq(code, "payload:ref")
		ok, code = check({ ref = "Dara:5", copper = -3 })
		falsy(ok); eq(code, "payload:copper")
		ok, code = check({ ref = "Dara:5", copper = "12g" })
		falsy(ok); eq(code, "payload:copper")
		eq(FDCP.Permissions.EVENT_PERMISSION.BANK_ITEM_SOLD, "night.run")
		local key = FDCP.Reasons.Key("EVENT", "BANK_ITEM_SOLD")
		truthy(key and FDCP.L[key] ~= key)
	end)

	it("goes through the permission gate: an officer may, a raider may not", function()
		local ranks = { Dara = 0, Bryn = 1, Corin = 4 }
		local gate = FDCP.Permissions.Gate(function(author) return ranks[author] end)
		local L, a = bankLedger()
		local e, code = GB().RecordSale(L, { author = "Corin", ts = 500, ref = a.id, copper = 100 }, gate)
		isNil(e); eq(code, "RANK_TOO_LOW")
		truthy(GB().RecordSale(L, { author = "Bryn", ts = 500, ref = a.id, copper = 100 }, gate))
	end)

	it("reads a price in gold or in coins, in English or in Italian letters", function()
		local P = GB().ParseMoney
		eq(P("120"), 1200000); eq(P("12.5"), 125000); eq(P("12,5"), 125000); eq(P("0"), 0)
		eq(P("12g 30s 5c"), 123005); eq(P("12g30s"), 123000); eq(P("50s"), 5000); eq(P("7c"), 7)
		eq(P("12o 30a 5r"), 123005); eq(P(" 3G "), 30000)
		isNil(P("")); isNil(P("abc")); isNil(P("12x")); isNil(P("12g 3g")); isNil(P("g12")); isNil(P("-5"))
		isNil(P("12g30")); isNil(P("99999999999g"))
		eq(select("#", GB().Split(123005)), 3)
		local g, s, c = GB().Split(123005)
		eq(g, 12); eq(s, 30); eq(c, 5)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The whole path on the mock client: Dara is the master looter, Corin the bank character. The BoE nobody wants as
-- main-spec is proposed to the bank, confirmed, handed over by master loot to Corin, and /fdcp bank records its sale.

local function SC() return FDCP.SessionController end
local function PS() return FDCP.Protocol.Session end
local function Codec() return FDCP.Codec end

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end
local MASTER = full("Dara")
local BOSS_GUID = "Creature-0-3-2000-1-11502-0000A1B2C3"
local BOE_LINK = "|cffa335ee|Hitem:19006::::::::70:::::|h[Mantle of the Inn]|h|r"

local function setup(M)
	M.player.name, M.player.realm = "Dara", REALM
	M.items.Add{ id = 19006, link = BOE_LINK, name = "Mantle of the Inn", quality = 4, equipLoc = "INVTYPE_SHOULDER",
		classID = 4, subclassID = 4, bindType = 2 }
	-- Dara is the Guild Master, so the permission gate of /fdcp bank lets her record a sale.
	M.guild.Set({ name = "Dragon", myRank = 0, members = { { name = "Aurel", rank = 3, class = "WARRIOR" },
		{ name = "Bryn", rank = 1, class = "WARRIOR" }, { name = "Corin", rank = 3, class = "WARRIOR" } } })
end

local function plain() return table.concat(Mock.PlainOutput(), "\n") end

-- Season S1 with the pool, the guild's rules with Corin as the bank character, the controller bound to the ledger and
-- the corpse of a boss holding the BoE.
local function mockBench(mutate)
	Mock.Advance(3)   -- the guild roster loads, so the permission gate knows the ranks
	local b = { L = Lg().New(), store = {} }
	assert(FDCP.Season.Open(b.L, { author = MASTER, ts = 1, season = SEASON, instances = { { id = 9001, size = 20 } } }))
	for i, n in ipairs(POOL) do
		assert(FDCP.Members.Join(b.L, { author = MASTER, ts = 1 + i, season = SEASON, member = full(n) }))
	end
	local r = FDCP.Rules.DefaultConfig()
	r.priority.bankCharacter = full("Corin")
	if mutate then mutate(r.priority) end
	assert(FDCP.Rules.Change(b.L, { author = MASTER, ts = 10, rules = r, confirmed = true }))
	SC():Bind(b.L, b.store)
	SC().Env = function(self) return { ledger = self:Ledger() } end   -- the permission gate is tested above
	Mock.loot.Set{ method = "master", masterLooter = true, threshold = 3,
		slots = { { link = BOE_LINK, name = "Mantle of the Inn", quality = 4, sources = { BOSS_GUID, 1 } } },
		candidates = { "Aurel", "Bryn", "Corin", "Dara" } }
	function b.s() return SC().session end
	function b.open()
		Mock.encounter.Start(601, "Boss")
		Mock.encounter.End(601, "Boss", true)
		Mock.loot.Open()
		local present = {}
		for _, p in ipairs(POOL) do present[full(p)] = true end
		assert(SC():Step({ type = "SET_RAID", present = present, addon = present }))
		assert(SC():Command("START"))
	end
	-- Everybody answers (PASS when not given); the round ends when the last one answered.
	function b.answer(responses)
		local s = b.s()
		for _, p in ipairs(POOL) do
			local rs = responses[p] or "PASS"
			if full(p) == MASTER then
				assert(PS():Respond(rs))
			else
				Mock.chat.Receive("FDCP1", Codec():Encode("SRESP", { s = s.id, i = s.active, r = s.net.rounds[s.active],
					rs = rs }), "RAID", p)
			end
		end
	end
	return b
end

describe("a BoE for the bank on the mock client", function()
	before_boot(setup)

	it("is recognised as BoE, proposed to the bank character, handed over by master loot, and charges nobody", function()
		local b = mockBench()
		b.open()
		local item = b.s().items[1]
		truthy(item.boe, "the item cache reads bind on equip")
		b.answer({ Aurel = "OS" })
		eq(item.state, "PROPOSAL")
		eq(item.proposal.kind, "BANK"); eq(item.proposal.winner, full("Corin")); eq(item.proposal.cost, 0)
		assert(SC():Command("CONFIRM"))
		eq(#Mock.loot.given, 1)
		eq(Mock.loot.given[1].slot, 1); eq(Mock.loot.given[1].candidate, 3, "Corin is the third candidate")
		local credits = Lg().Credits(b.L, SEASON)
		for _, n in ipairs(POOL) do eq(credits[full(n)], 0, n) end
		local items = GB().Items(b.L, SEASON)
		eq(#items, 1); eq(items[1].member, full("Corin"))
	end)

	it("/fdcp bank lists the item and records its sale, in English and in Italian", function()
		local b = mockBench()
		b.open()
		b.answer({})
		assert(SC():Command("CONFIRM"))
		Mock.ClearOutput()
		Mock.Slash("/fdcp bank")
		local out = plain()
		contains(out, "A BoE nobody needs as main-spec: it goes to the guild bank, no credits.")
		contains(out, "Bank character: Corin.")
		contains(out, "1. ")
		contains(out, "(Corin): not sold yet")
		contains(out, "Sold 0 of 1, 0g 0s 0c in all.")
		Mock.ClearOutput()
		Mock.Slash("/fdcp bank sold 1 12g 30s")
		contains(plain(), "Sale recorded:")
		contains(plain(), "for 12g 30s 0c. Nobody's credits change.")
		eq(GB().Items(b.L, SEASON)[1].copper, 123000)
		eq(GB().Items(b.L, SEASON)[1].soldBy, MASTER)
		Mock.ClearOutput()
		Mock.Slash("/fdcp bank sold 1 lots")
		contains(plain(), "Write the price in gold")
		Mock.Slash("/fdcp bank sold 9 10")
		contains(plain(), "Usage: /fdcp bank")
		Mock.Slash("/fdcp bank burn")
		contains(plain(), "Usage: /fdcp bank")
		FDCP.Locale.SetActive("itIT")
		Mock.ClearOutput()
		Mock.Slash("/fdcp bank")
		out = plain()
		contains(out, "va alla banca di gilda, senza crediti")
		contains(out, "venduto per 12o 30a 0r")
		Mock.ClearOutput()
		Mock.Slash("/fdcp bank sold 1 15o")
		contains(plain(), "Vendita registrata:")
		eq(GB().Totals(b.L, SEASON).copper, 150000)
	end)

	it("says every fallback mode and when no bank character is set", function()
		for _, mode in ipairs(FDCP.Priority.BOE_FALLBACKS) do
			for _, lang in ipairs({ "enUS", "itIT" }) do
				local key = "BANK_FALLBACK_" .. mode:upper()
				local text = FDCP.Locale.Text(lang, key)
				truthy(text ~= key and text ~= "", lang .. " " .. key)
			end
		end
		mockBench(function(p) p.bankCharacter = nil; p.boeFallback = "disenchant" end)
		Mock.ClearOutput()
		Mock.Slash("/fdcp bank")
		contains(plain(), "it is disenchanted, no credits")
		contains(plain(), "No bank character is set")
		contains(plain(), "No item went to the guild bank this season.")
	end)

	it("the command is in the help", function()
		Mock.ClearOutput()
		Mock.Slash("/fdcp help")
		contains(plain(), "the guild bank: unused BoEs and the gold of their sale")
	end)
end)
