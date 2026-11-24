-- The raid readiness check (M8-2, ADR 0010, docs/ANALISI.md §4.2): Domain/Readiness.lua (the rules, the verdict, the
-- wire form), Data/Readiness.lua (the fixed tables), Adapters/SelfCheck.lua (the player's own snapshot, on the mock client:
-- GetInventoryItemLink, C_Item.GetItemInfoInstant, C_Item.GetItemCount, C_UnitAuras.GetBuffDataByIndex), Net/Readiness.lua
-- (RDYQ on RAID, RDY by whisper, trust, combat, throttling) and App/ReadinessCheck.lua (the master looter's table), the last
-- two on the network simulator.
local function R() return FDCP.Readiness end
local function D() return FDCP.ReadinessData end
local function SC() return FDCP.SelfCheck end

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end

-- An item link with an enchant id (0 = none).
local function link(id, enchant, name)
	return "|cffa335ee|Hitem:" .. id .. ":" .. (enchant or "") .. ":::::::60:::::|h[" .. (name or "Item") .. "]|h|r"
end

-- A snapshot with every default requirement met, for a class.
local function goodSnap(class)
	local slots = {}
	for _, s in ipairs({ 5, 8, 9, 10, 15, 16 }) do slots[s] = "YES" end
	if class == "HUNTER" then slots[18] = "YES" end
	return {
		class = class or "WARRIOR", slots = slots, buffs = { WELL_FED = true, FLASK = true }, buffsKnown = true,
		counts = { FOOD_BUFF = 3, FOOD = 20, WATER = 20, POTION = 5, FLASK = 2, AMMO = 2000, PET_FOOD = 20 },
	}
end

local function byCat(result)
	local out = {}
	for _, it in ipairs(result.items) do out[it.cat] = it end
	return out
end

local function bySlot(result)
	local out = {}
	for _, e in ipairs(result.enchants) do out[e.slot] = e.status end
	return out
end

---------------------------------------------------------------------------------------------------------------------

describe("the rules of the check", function()
	it("the defaults are valid, reversible and part of the rules", function()
		truthy(R().ValidateConfig(R().DefaultConfig()))
		local rules = FDCP.Rules.DefaultConfig()
		truthy(rules.readiness, "a section of the rules")
		truthy(FDCP.Rules.Validate(rules))
		deepEq(R().Categories(R().DefaultConfig()), { "FOOD_BUFF", "FOOD", "WATER", "POTION", "FLASK", "AMMO", "PET_FOOD" })
		local off = R().DefaultConfig()
		off.enabled = false
		deepEq(R().Categories(off), {}, "a check turned off asks for nothing")
	end)

	it("refuses damaged requirements with a code per field", function()
		local c = R().DefaultConfig()
		c.slots[1].slot = 2            -- the neck takes no enchant
		c.slots[2].classes = { "BARD" }
		c.needs[1].cat = "CAKE"
		c.needs[2].min = -1
		c.needs[3].roles = { "SINGER" }
		c.needs[4].mana = "yes"
		local ok, problems = R().ValidateConfig(c)
		falsy(ok)
		deepEq(problems, { "needs.1.cat", "needs.2.min", "needs.3.roles", "needs.4.mana", "slots.1.slot", "slots.2.classes" })
		local rules = FDCP.Rules.DefaultConfig()
		rules.readiness = c
		local ok2, p2 = FDCP.Rules.Validate(rules)
		falsy(ok2)
		eq(p2[1], "readiness.needs.1.cat")
	end)

	it("a requirement applies by class, role and mana", function()
		eq(R().Applies({ cat = "AMMO", min = 1, classes = { "HUNTER" } }, { class = "HUNTER" }), true)
		eq(R().Applies({ cat = "AMMO", min = 1, classes = { "HUNTER" } }, { class = "MAGE" }), false)
		eq(R().Applies({ cat = "WATER", min = 1, mana = true }, { class = "PRIEST" }), true)
		eq(R().Applies({ cat = "WATER", min = 1, mana = true }, { class = "ROGUE" }), false)
		eq(R().Applies({ cat = "FOOD", min = 1, mana = false }, { class = "ROGUE" }), true)
		eq(R().Applies({ cat = "POTION", min = 5, roles = { "TANK" } }, { class = "WARRIOR", role = "TANK" }), true)
		eq(R().Applies({ cat = "POTION", min = 5, roles = { "TANK" } }, { class = "WARRIOR" }), false,
			"an unknown role is not concerned by a requirement with roles")
	end)

	it("the rules leave the section out of the ledger while it is the default, and keep a change", function()
		local Rules = FDCP.Rules
		local stored = Rules.Stored(Rules.DefaultConfig())
		isNil(stored.readiness, "an older addon still reads a guild that never touched the check")
		truthy(Rules.Validate(Rules.WithDefaults(stored)))
		local changed = Rules.DefaultConfig()
		changed.readiness.needs[1].min = 2
		eq(Rules.Stored(changed).readiness.needs[1].min, 2)
		-- through the ledger: the GM writes it, Rules.Current reads it back filled
		local L = FDCP.Ledger.New()
		local gm = full("Aurel")
		local e = assert(Rules.Change(L, { author = gm, ts = 100, rules = changed }))
		eq(FDCP.Ledger.Payload(e).rules.readiness.needs[1].min, 2)
		eq(Rules.Current(L).readiness.needs[1].min, 2)
		local back = Rules.DefaultConfig()
		local e2 = assert(Rules.Change(L, { author = gm, ts = 200, rules = back }))
		isNil(FDCP.Ledger.Payload(e2).rules.readiness, "back to the defaults: left out again")
		deepEq(Rules.Current(L).readiness, R().DefaultConfig())
	end)
end)

describe("the verdict", function()
	it("no snapshot is UNKNOWN; everything met is OK", function()
		eq(R().Evaluate(nil, R().DefaultConfig(), { class = "MAGE" }).status, "UNKNOWN")
		local r = R().Evaluate(goodSnap("WARRIOR"), R().DefaultConfig())
		eq(r.status, "OK")
		deepEq(r.enchants, {})
		deepEq(r.items, {})
		eq(R().Evaluate(goodSnap("HUNTER"), R().DefaultConfig()).status, "OK")
	end)

	it("a missing enchant is MISSING, on its slot; an empty slot asks for nothing", function()
		local s = goodSnap("WARRIOR")
		s.slots[9] = "NO"
		s.slots[17] = nil   -- a two-hander: nothing in the off hand
		s.slots[1] = "NO"   -- the head is not required by default
		local r = R().Evaluate(s, R().DefaultConfig())
		eq(r.status, "MISSING")
		deepEq(r.enchants, { { slot = 9, status = "MISSING" } })
	end)

	it("a slot that could not be read is a warning, not a missing enchant", function()
		local s = goodSnap("WARRIOR")
		s.slots[16] = "UNKNOWN"
		local r = R().Evaluate(s, R().DefaultConfig())
		eq(r.status, "WARN")
		eq(bySlot(r)[16], "UNKNOWN")
	end)

	it("a consumable: none is MISSING, fewer than the minimum is WARN, an active buff meets it", function()
		local s = goodSnap("PRIEST")
		s.counts.POTION = 0
		s.counts.WATER = 4
		s.buffs = {}
		s.counts.FLASK = 0
		local r = R().Evaluate(s, R().DefaultConfig())
		eq(r.status, "MISSING")
		local items = byCat(r)
		deepEq(items.POTION, { cat = "POTION", status = "MISSING", have = 0, need = 2 })
		deepEq(items.WATER, { cat = "WATER", status = "WARN", have = 4, need = 10 })
		eq(items.FLASK.status, "MISSING")
		isNil(items.FOOD_BUFF, "three buff foods in the bags meet it without the buff")
		s.buffs.ELIXIR = true
		eq(byCat(R().Evaluate(s, R().DefaultConfig())).FLASK, nil, "an elixir active meets the flask category")
	end)

	it("hunter ammunition and pet food, water only for the mana users", function()
		local hunter = goodSnap("HUNTER")
		hunter.counts.AMMO = 400
		hunter.counts.PET_FOOD = 0
		local items = byCat(R().Evaluate(hunter, R().DefaultConfig()))
		deepEq(items.AMMO, { cat = "AMMO", status = "WARN", have = 400, need = 1000 })
		eq(items.PET_FOOD.status, "MISSING")
		local rogue = goodSnap("ROGUE")
		rogue.counts.WATER, rogue.counts.AMMO, rogue.counts.PET_FOOD = 0, 0, 0
		rogue.slots[18] = "NO"
		eq(R().Evaluate(rogue, R().DefaultConfig()).status, "OK", "no water, ammunition, pet food or scope for a rogue")
	end)

	it("the class comes from the snapshot or from the caller; roles and the larger minimum", function()
		local c = R().DefaultConfig()
		c.needs[#c.needs + 1] = { cat = "POTION", min = 6, roles = { "TANK" } }
		local s = goodSnap("WARRIOR")
		s.counts.POTION = 5
		eq(R().Evaluate(s, c, { role = "DAMAGER" }).status, "OK")
		local tank = R().Evaluate(s, c, { role = "TANK" })
		deepEq(byCat(tank).POTION, { cat = "POTION", status = "WARN", have = 5, need = 6 })
		eq(tank.class, "WARRIOR")
		s.class = nil
		eq(R().Evaluate(s, c, { class = "HUNTER" }).class, "HUNTER")
	end)

	it("a count that could not be read is UNKNOWN; none in the bags with hidden auras too", function()
		local s = goodSnap("MAGE")
		s.counts.POTION = nil
		s.buffs, s.buffsKnown = {}, false
		s.counts.FLASK = 0
		local r = R().Evaluate(s, R().DefaultConfig())
		eq(r.status, "WARN")
		eq(byCat(r).POTION.status, "UNKNOWN")
		eq(byCat(r).FLASK.status, "UNKNOWN", "a flask may be active and hidden")
		isNil(byCat(r).FOOD_BUFF, "three in the bags: met whatever the auras")
	end)

	it("counts the statuses of a raid", function()
		local s = R().Summary({ { status = "OK" }, { status = "OK" }, { status = "MISSING" }, { result = { status = "UNKNOWN" } },
			{ status = "WARN" }, "junk" })
		deepEq(s, { total = 5, OK = 2, WARN = 1, MISSING = 1, UNKNOWN = 1 })
	end)
end)

describe("item links and enchantable slots", function()
	it("reads the enchant field of a link", function()
		eq(R().EnchantOf(link(19100, 1883)), true)
		eq(R().EnchantOf(link(19100, 0)), false)
		eq(R().EnchantOf(link(19100)), false)
		eq(R().EnchantOf("item:19100"), false)
		eq(R().EnchantOf("item:19100:2564:0:0"), true)
		isNil(R().EnchantOf("not a link"))
		isNil(R().EnchantOf(nil))
	end)

	it("knows which off-hand and ranged items take an enchant", function()
		eq(D().Enchantable(5, nil), true)
		eq(D().Enchantable(2, {}), false, "the neck")
		eq(D().Enchantable(17, { equipLoc = "INVTYPE_SHIELD" }), true)
		eq(D().Enchantable(17, { equipLoc = "INVTYPE_HOLDABLE" }), false)
		eq(D().Enchantable(17, { equipLoc = "INVTYPE_WEAPONOFFHAND" }), true)
		isNil(D().Enchantable(17, nil), "the client did not say")
		eq(D().Enchantable(18, { equipLoc = "INVTYPE_RANGED", classID = 2, subClassID = 2 }), true, "a bow")
		eq(D().Enchantable(18, { equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2, subClassID = 19 }), false, "a wand")
		eq(D().Enchantable(18, { equipLoc = "INVTYPE_RELIC", classID = 4, subClassID = 7 }), false, "a libram")
		eq(D().Enchantable(18, { equipLoc = "INVTYPE_THROWN", classID = 2, subClassID = 16 }), false)
	end)

	it("every category and buff of the data table is well formed", function()
		local kinds = {}
		for _, k in ipairs(D().BUFF_KINDS) do kinds[k] = true end
		for id, kind in pairs(D().BUFFS) do
			truthy(type(id) == "number" and id > 0 and kinds[kind], "buff " .. tostring(id))
		end
		for _, c in ipairs(D().CATEGORIES) do
			truthy(#c.items > 0, c.code)
			for _, id in ipairs(c.items) do truthy(type(id) == "number" and id > 0, c.code) end
			for _, k in ipairs(c.buffs or {}) do truthy(kinds[k], c.code) end
		end
	end)
end)

describe("the wire form", function()
	it("packs only the check's fields and reads them back", function()
		local s = goodSnap("HUNTER")
		s.spec = 254
		s.slots[17] = "NO"
		s.slots[1] = "UNKNOWN"
		local m = R().Pack(s)
		local keys = {}
		for k in pairs(m) do keys[#keys + 1] = k end
		table.sort(keys)
		deepEq(keys, { "b", "c", "en", "eu", "ey", "n", "rv", "sp" }, "nothing else travels")
		deepEq(m.ey, { 5, 8, 9, 10, 15, 16, 18 })
		deepEq(m.en, { 17 })
		deepEq(m.eu, { 1 })
		deepEq(m.b, { "WELL_FED", "FLASK" })
		local back = R().Read(m)
		deepEq(back, s)
	end)

	it("refuses damaged answers and drops what a newer addon adds", function()
		isNil(R().Read({}), "no version")
		isNil(R().Read({ rv = 1, c = "BARD" }))
		isNil(R().Read({ rv = 1, ey = { 2 } }), "the neck")
		isNil(R().Read({ rv = 1, ey = { 5 }, en = { 5 } }), "one slot in two lists")
		isNil(R().Read({ rv = 1, n = { POTION = -1 } }))
		isNil(R().Read({ rv = 1, n = { POTION = 1.5 } }))
		isNil(R().Read({ rv = 1, b = { 7 } }))
		local s = R().Read({ rv = 2, b = { "FLASK", "MOONGLOW" }, n = { POTION = 3, CAKE = 4 }, bu = true })
		deepEq(s.buffs, { FLASK = true })
		deepEq(s.counts, { POTION = 3 })
		eq(s.buffsKnown, false)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The snapshot builder on the mock client

-- A hunter: an enchanted chest and bow, a bare wrist, a held-in-off-hand item, a flask active, a few consumables.
local function hunter(M)
	M.player.classFile, M.player.classId = "HUNTER", 3
	M.items.Add{ id = 21000, link = link(21000, 1891, "Chest"), equipLoc = "INVTYPE_CHEST", classID = 4, subclassID = 3 }
	M.items.Add{ id = 21001, link = link(21001, 0, "Bracers"), equipLoc = "INVTYPE_WRIST", classID = 4, subclassID = 3 }
	M.items.Add{ id = 21002, link = link(21002, 0, "Orb"), equipLoc = "INVTYPE_HOLDABLE", classID = 4, subclassID = 0 }
	M.items.Add{ id = 21003, link = link(21003, 2523, "Bow"), equipLoc = "INVTYPE_RANGED", classID = 2, subclassID = 2 }
	M.items.Add{ id = 21004, link = link(21004, 0, "Ring"), equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0 }
	M.items.equipped = { [5] = link(21000, 1891, "Chest"), [9] = link(21001, 0, "Bracers"), [17] = link(21002, 0, "Orb"),
		[18] = link(21003, 2523, "Bow"), [11] = link(21004, 0, "Ring") }
	M.items.counts = { [13446] = 3, [13444] = 1, [18042] = 1200, [8952] = 15, [12345] = 99 }
	M.auras.buffs = { { spellId = 1126 }, { spellId = 17628 } }
	M.specs.Set{ active = 1, list = { { id = 254, name = "Marksmanship", role = "DAMAGER" } } }
end

describe("the player's own snapshot", function()
	before_boot(hunter)

	it("reads enchants, buffs and the counts of the categories asked, nothing else", function()
		local snap = assert(SC().Build({ "POTION", "AMMO", "PET_FOOD", "FLASK" }))
		eq(snap.class, "HUNTER")
		eq(snap.spec, 254)
		deepEq(snap.slots, { [5] = "YES", [9] = "NO", [18] = "YES" },
			"the orb takes no enchant, the ring is not an enchant slot, empty slots are not listed")
		deepEq(snap.buffs, { FLASK = true })
		eq(snap.buffsKnown, true)
		deepEq(snap.counts, { POTION = 4, AMMO = 1200, PET_FOOD = 15, FLASK = 0 })
		local r = R().Evaluate(snap, R().DefaultConfig())
		deepEq(bySlot(r), { [9] = "MISSING" })
	end)

	it("all the categories when none is named", function()
		local snap = assert(SC().Build())
		local n = 0
		for _ in pairs(snap.counts) do n = n + 1 end
		eq(n, #D().CATEGORIES)
	end)

	it("never reads in combat or during a boss encounter", function()
		Mock.world.inCombat = true
		local snap, why = SC().Build({ "POTION" })
		isNil(snap)
		eq(why, "BUSY")
		Mock.world.inCombat = false
		Mock.encounter.Start(663, "Lucifron")
		isNil((SC().Build({ "POTION" })))
		Mock.encounter.End(663, "Lucifron", true)
		truthy(SC().Build({ "POTION" }))
	end)

	it("a hidden slot, hidden auras and hidden counts are unknown, never guessed", function()
		Mock.items.secretSlots = { [5] = true }
		Mock.auras.secret = { [1] = true }
		Mock.items.countSecret = true
		local snap = assert(SC().Build({ "POTION" }))
		eq(snap.slots[5], "UNKNOWN")
		eq(snap.buffsKnown, false)
		deepEq(snap.buffs, { FLASK = true }, "the readable aura still counts")
		deepEq(snap.counts, {}, "the count is unknown")
		local r = R().Evaluate(snap, R().DefaultConfig())
		eq(byCat(r).POTION.status, "UNKNOWN")
		eq(bySlot(r)[5], "UNKNOWN")
	end)

	it("a client without the aura or count functions still builds a snapshot", function()
		Mock.auras.failing = true
		C_Item.GetItemCount = nil
		local snap = assert(SC().Build({ "POTION" }))
		eq(snap.buffsKnown, false)
		deepEq(snap.counts, {})
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The messages on the network simulator: Aurel an officer (rank 1), Bryn, Corin and Dara members (rank 3); Edda has
-- no addon.

local RANKS = { Aurel = 1, Bryn = 3, Corin = 3, Dara = 3, Edda = 3, Gm = 0 }
local NAMES = { "Gm", "Aurel", "Bryn", "Corin", "Dara", "Edda" }

local function guildFor(name)
	return function(M)
		local members = {}
		for _, n in ipairs(NAMES) do
			if n ~= name then members[#members + 1] = { name = n, rank = RANKS[n], class = "WARRIOR", online = true } end
		end
		M.guild.Set({ name = "Dragon", members = members, myRank = RANKS[name] })
	end
end

-- Bryn is ready; Corin lacks a wrist enchant and potions; Dara a priest without water.
local function gear(M, name)
	if name == "Dara" then M.player.classFile, M.player.classId = "PRIEST", 5 end
	local wrist = name == "Corin" and 0 or 1885
	M.items.Add{ id = 22009, link = link(22009, wrist, "Bracers"), equipLoc = "INVTYPE_WRIST", classID = 4, subclassID = 4 }
	M.items.equipped = { [9] = link(22009, wrist, "Bracers") }
	M.items.counts = { [20452] = 5, [8932] = 20, [13446] = name == "Corin" and 0 or 5, [13510] = 1 }
	if name ~= "Dara" then M.items.counts[8079] = 20 end
	M.auras.buffs = { { spellId = 17626 } }
end

local function client(net, name, opts)
	opts = opts or {}
	local base = guildFor(name)
	return net:Client(name, { setup = function(M) base(M) gear(M, name) if opts.setup then opts.setup(M) end end })
end

local function rows(c)
	local out = {}
	for _, row in ipairs(c.addon().ReadinessCheck:Rows()) do out[row.name:match("^([^%-]+)")] = row end
	return out
end

local function scenario()
	local net = Sim.new{ realm = REALM, step = 0.5 }
	local c = {}
	for _, n in ipairs({ "Aurel", "Bryn", "Corin", "Dara" }) do c[n] = client(net, n) end
	net:Raid({ "Aurel", "Bryn", "Corin", "Dara", "Edda" })
	net:Advance(5)
	return net, c
end

describe("the readiness check between clients", function()
	it("the officer asks, every raider answers by whisper, the table shows each verdict", function()
		local net, c = scenario()
		local check = c.Aurel.addon().ReadinessCheck
		truthy(c.Aurel.addon().AddonCheck:Request())   -- the addon check finds that Edda has none
		local q = assert(check:Request())
		eq(rows(c.Aurel).Aurel.status, "OK", "the asker's own snapshot is taken at once")
		net:Advance(5)
		local seen = rows(c.Aurel)
		eq(seen.Bryn.status, "OK")
		eq(seen.Corin.status, "MISSING")
		deepEq(seen.Corin.result.enchants, { { slot = 9, status = "MISSING" } })
		deepEq(byCat(seen.Corin.result).POTION, { cat = "POTION", status = "MISSING", have = 0, need = 2 })
		eq(seen.Dara.status, "MISSING")
		eq(byCat(seen.Dara.result).WATER.status, "MISSING")
		eq(seen.Edda.status, "UNKNOWN")
		eq(seen.Edda.reason, "WAITING")
		net:Advance(c.Aurel.addon().AddonCheck.TIMEOUT + check.TIMEOUT)
		eq(rows(c.Aurel).Edda.reason, "NO_ADDON")
		local s = check:Summary()
		eq(s.q, q)
		eq(s.answered, 4)
		eq(s.OK, 2); eq(s.MISSING, 2); eq(s.UNKNOWN, 1)
		-- the answers are whispers to the asker: Bryn's client never saw Corin's
		eq(c.Bryn.addon().ReadinessNet.stats.replies, 0)
		eq(c.Bryn.addon().ReadinessCheck:Summary().answered, 0)
		eq(net:SentBy("Bryn", "WHISPER"), 1)
		-- nothing of it reaches the ledger or the saved data
		local saved = c.Aurel.addon().Config.char
		isNil(saved.readiness)
	end)

	it("throttling: the asker waits REQUEST_GAP, a raider answers one asker once per ANSWER_GAP", function()
		local net, c = scenario()
		local check = c.Aurel.addon().ReadinessCheck
		truthy(check:Request())
		net:Advance(2)
		local q, why, wait = check:Request()
		isNil(q)
		eq(why, "TOO_SOON")
		truthy(wait > 0 and wait <= 30)
		-- the network layer asked again directly (an older asker, or a forged repeat): Bryn does not answer twice
		local bryn = c.Bryn.addon().ReadinessNet
		local before = bryn.stats.answered
		c.Aurel.addon().ReadinessNet:Ask({ "POTION" }, 12345)
		net:Advance(2)
		eq(bryn.stats.answered, before)
		eq(bryn.stats.throttled, 1)
		net:Advance(30)
		truthy(check:Request())
		net:Advance(3)
		eq(bryn.stats.answered, before + 1)
		eq(check:Summary().answered, 4)
	end)

	it("only the officers, the raid leader, an assistant or the master looter are answered", function()
		local net, c = scenario()
		local q, why = c.Bryn.addon().ReadinessCheck:Request()
		isNil(q)
		eq(why, "RANK_TOO_LOW")
		c.Bryn.addon().ReadinessNet:Ask({ "POTION" })
		net:Advance(3)
		eq(c.Corin.addon().ReadinessNet.stats.refused, 1)
		eq(c.Corin.addon().ReadinessNet.stats.answered, 0)
		-- Bryn becomes an assistant: now Corin answers
		net:Raid({ "Aurel", "Bryn", "Corin", "Dara", "Edda" }, { ranks = { Bryn = 1 } })
		net:Advance(3)
		c.Bryn.addon().ReadinessNet:Ask({ "POTION" })
		net:Advance(3)
		eq(c.Corin.addon().ReadinessNet.stats.answered, 1)
		-- the master looter too
		net:Raid({ "Aurel", "Bryn", "Corin", "Dara", "Edda" }, { ml = "Dara" })
		net:Advance(3)
		c.Dara.addon().ReadinessNet:Ask({ "POTION" })
		net:Advance(3)
		eq(c.Corin.addon().ReadinessNet.stats.answered, 2)
	end)

	it("a raider in combat answers when the fight is over, never during it", function()
		local net, c = scenario()
		c.Corin.Mock.world.inCombat = true
		local check = c.Aurel.addon().ReadinessCheck
		truthy(check:Request())
		net:Advance(10)
		isNil(check.replies[full("Corin")], "no answer in combat")
		eq(c.Corin.addon().ReadinessNet.stats.deferred, 1)
		c.Corin.Mock.world.inCombat = false
		net:Advance(4)
		truthy(check.replies[full("Corin")])
		eq(rows(c.Aurel).Corin.status, "MISSING")
	end)

	it("an answer that waits too long is dropped", function()
		local net, c = scenario()
		c.Corin.Mock.world.inCombat = true
		truthy(c.Aurel.addon().ReadinessCheck:Request())
		net:Advance(c.Corin.addon().ReadinessNet.DEFER_TTL + 5)
		c.Corin.Mock.world.inCombat = false
		net:Advance(5)
		eq(c.Corin.addon().ReadinessNet.stats.expired, 1)
		eq(c.Corin.addon().ReadinessNet.stats.answered, 0)
	end)

	it("refuses an answer on the wrong channel, a damaged one and one to an older request", function()
		local net, c = scenario()
		local rn, check = c.Aurel.addon().ReadinessNet, c.Aurel.addon().ReadinessCheck
		truthy(check:Request())
		local q = check.request.q
		net:Advance(3)
		rn:OnMessage({ t = "RDY", q = q, rv = 1, c = "WARRIOR" }, full("Bryn"), "RAID")
		rn:OnMessage({ t = "RDY", q = q, rv = 1, c = "BARD" }, full("Bryn"), "WHISPER")
		eq(rn.stats.bad, 2)
		local stale = check.stale
		rn:OnMessage({ t = "RDY", q = q - 100, rv = 1, c = "WARRIOR" }, full("Bryn"), "WHISPER")
		eq(check.stale, stale + 1)
		rn:OnMessage({ t = "RDY", q = q, rv = 1, c = "WARRIOR" }, full("Stranger"), "WHISPER")
		eq(check.stale, stale + 2, "not in the raid")
		-- a request by whisper is not a readiness check
		local corin = c.Corin.addon().ReadinessNet
		corin:OnMessage({ t = "RDYQ", q = 5, rv = 1 }, full("Aurel"), "WHISPER")
		eq(corin.stats.bad, 1)
	end)

	it("leaving the raid drops the check; the check can be turned off by the rules", function()
		local net, c = scenario()
		local check = c.Aurel.addon().ReadinessCheck
		truthy(check:Request())
		net:Advance(3)
		net:Raid({ "Bryn", "Corin" })
		net:Advance(3)
		isNil(check.request)
		local q, why = check:Request()
		isNil(q)
		eq(why, "NOT_IN_RAID")
		net:Raid({ "Aurel", "Bryn", "Corin" })
		net:Advance(31)
		local original = check.Rules
		check.Rules = function() local r = c.Aurel.addon().Readiness.DefaultConfig() r.enabled = false return r end
		q, why = check:Request()
		check.Rules = original
		isNil(q)
		eq(why, "DISABLED")
	end)
end)
