-- The inventory adapter and the upgrade advisor (M5-2): Adapters/Inventory.lua reads what the player wears and an item's
-- data through Core/Compat.lua (mock client: C_Item.*, GetInventoryItemLink, specializations), App/UpgradeAdvisor.lua
-- turns it into the verdicts of main-spec and off-spec for Domain/UpgradeScore.lua, with the rules of the ledger and the
-- declared specs; the response protocol carries the result (Net/Protocol.lua: SRESP `vd` / `eq`).
-- (docs/ANALISI.md §5.1, §6)
local function Inv() return FDCP.Inventory end
local function A() return FDCP.UpgradeAdvisor end
local function U() return FDCP.UpgradeScore end
local function PS() return FDCP.Protocol.Session end

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end

local function link(id, name) return "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[" .. name .. "]|h|r" end
local function ref(id) return "item:" .. id .. "::::::::70:::::" end

local STR, STA = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT"

-- A warrior (the mock's default character) in plate: a worn helm and a worn chest, a better helm to pick up, a chest that
-- trades strength for stamina, a wand and a token it cannot use, an empty ring slot.
local ITEMS = {
	{ id = 19100, link = link(19100, "Old Helm"), name = "Old Helm", equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 4,
		level = 64, stats = { [STR] = 90, [STA] = 40 } },
	{ id = 19101, link = link(19101, "Helm of Embers"), name = "Helm of Embers", equipLoc = "INVTYPE_HEAD", classID = 4,
		subclassID = 4, level = 70, stats = { [STR] = 100, [STA] = 50 } },
	{ id = 19110, link = link(19110, "Old Chest"), name = "Old Chest", equipLoc = "INVTYPE_CHEST", classID = 4, subclassID = 4,
		level = 66, stats = { [STR] = 100, [STA] = 50 } },
	{ id = 19111, link = link(19111, "Bulwark Chest"), name = "Bulwark Chest", equipLoc = "INVTYPE_CHEST", classID = 4,
		subclassID = 4, level = 66, stats = { [STR] = 80, [STA] = 120 } },
	{ id = 19120, link = link(19120, "Wand of Sparks"), name = "Wand of Sparks", equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2,
		subclassID = 19, level = 70, stats = { ITEM_MOD_SPELL_POWER_SHORT = 20 } },
	{ id = 19130, link = link(19130, "Ring of the Keeper"), name = "Ring of the Keeper", equipLoc = "INVTYPE_FINGER",
		classID = 4, subclassID = 0, level = 66, stats = { [STR] = 30 } },
	{ id = 19140, link = link(19140, "Token of Embers"), name = "Token of Embers", equipLoc = "", classID = 15,
		subclassID = 0, level = 70, stats = {} },
}
local WORN_HEAD, WORN_CHEST = link(19100, "Old Helm"), link(19110, "Old Chest")

local function addItems(M)
	for _, def in ipairs(ITEMS) do M.items.Add(def) end
	M.items.equipped = { [1] = WORN_HEAD, [5] = WORN_CHEST }
end

local function setup(M)
	M.player.name, M.player.realm = "Testchar", REALM
	addItems(M)
end

---------------------------------------------------------------------------------------------------------------------

describe("the inventory adapter", function()
	before_boot(setup)

	it("reads the item string, the id and nothing from what is not an item", function()
		local r, id = Inv().Ref(WORN_HEAD)
		eq(r, "item:19100::::::::70:::::"); eq(id, 19100)
		eq(Inv().Ref(19101), "item:19101")
		eq(Inv().Ref("item:19101:5"), "item:19101:5")
		isNil(Inv().Ref("|Hspell:12|h[x]|h"))
		isNil(Inv().Ref(nil)); isNil(Inv().Ref(-4)); isNil(Inv().Ref(1.5)); isNil(Inv().Ref({}))
	end)

	it("describes an item: slot, kind, level, stats and the specs it is for", function()
		Mock.items.Add{ id = 19150, link = link(19150, "Arms Blade"), name = "Arms Blade", equipLoc = "INVTYPE_2HWEAPON", classID = 2,
			subclassID = 8, level = 72, stats = { [STR] = 120 }, specs = { 71, 72 } }
		local p = assert(Inv().Piece(19150))
		eq(p.itemID, 19150); eq(p.link, "item:19150")
		eq(p.equipLoc, "INVTYPE_2HWEAPON"); eq(p.classID, 2); eq(p.subclassID, 8)
		eq(p.level, 72)
		deepEq(p.stats, { [STR] = 120 })
		deepEq(p.specs, { 71, 72 })
		isNil(Inv().Piece(19101).specs, "an item with no spec list is not restricted")
	end)

	it("reads the spec list from DoesItemContainSpec when GetItemSpecInfo says nothing", function()
		Mock.items.Add{ id = 19151, link = link(19151, "Fury Blade"), name = "Fury Blade", equipLoc = "INVTYPE_WEAPON", classID = 2,
			subclassID = 7, level = 72, stats = { [STR] = 90 }, specs = { 72 } }
		local real = C_Item.GetItemSpecInfo
		C_Item.GetItemSpecInfo = function() return nil end
		local p = assert(Inv().Piece(19151, { classID = 1, classFile = "WARRIOR" }))
		C_Item.GetItemSpecInfo = real
		deepEq(p.specs, { 72 })
	end)

	it("keeps the item level of a worn piece (its link carries the upgrades)", function()
		local p = assert(Inv().Piece(WORN_HEAD))
		eq(p.level, 64)
	end)

	it("says why it has nothing: an unknown item, an item whose data is not loaded", function()
		local p, why = Inv().Piece(99999)
		isNil(p); eq(why, "UNKNOWN")
		Mock.items.Add{ id = 19160, link = link(19160, "Late Item"), name = "Late Item", equipLoc = "INVTYPE_HEAD", classID = 4,
			subclassID = 4, level = 70, cached = false }
		p, why = Inv().Piece(19160)
		isNil(p); eq(why, "NOT_LOADED")
		p = Inv().Piece(19160, { unloaded = true })
		truthy(p, "a worn piece may be read from the instant data")
		eq(p.equipLoc, "INVTYPE_HEAD")
	end)

	it("an item the client says cannot be equipped has no slot", function()
		local p = assert(Inv().Piece(19140))
		falsy(p.equipLoc and p.equipLoc ~= "", "an empty slot name from the game is no slot")
	end)

	it("lists the worn pieces by slot, without the shirt and the tabard", function()
		Mock.items.Add{ id = 19170, link = link(19170, "Shirt"), name = "Shirt", equipLoc = "INVTYPE_BODY", classID = 4, subclassID = 0, level = 1 }
		Mock.items.Add{ id = 19171, link = link(19171, "Tabard"), name = "Tabard", equipLoc = "INVTYPE_TABARD", classID = 4, subclassID = 0, level = 1 }
		Mock.items.equipped[4], Mock.items.equipped[19] = link(19170, "Shirt"), link(19171, "Tabard")
		local worn, links = Inv().Equipped()
		eq(worn[1].itemID, 19100); eq(worn[5].itemID, 19110)
		isNil(worn[4]); isNil(worn[19])
		deepEq(links, { "item:19100::::::::70:::::", "item:19110::::::::70:::::" })
		eq(worn[1].slot, 1)
		deepEq(worn[5].stats, { [STR] = 100, [STA] = 50 })
	end)

	it("reads the character: class and the spec it plays", function()
		local p = Inv().Player()
		eq(p.class, "WARRIOR"); eq(p.classID, 1); eq(p.spec, 71)
		Mock.specs.Set{ active = 3 }
		eq(Inv().Player().spec, 73)
	end)

	it("fills the stats of the new piece from the stat delta when the game gives none", function()
		local real = C_Item.GetItemStats
		C_Item.GetItemStats = function(l) if tostring(l):find("19101") then return nil end return real(l) end
		local worn = Inv().Equipped()
		local piece = assert(Inv().Piece(19101))
		isNil(piece.stats)
		eq(Inv().Fill(piece, worn), 1)
		C_Item.GetItemStats = real
		deepEq(piece.stats, { [STR] = 100, [STA] = 50 })
	end)

	it("fills the stats of a worn piece from the stat delta the other way round", function()
		local real = C_Item.GetItemStats
		C_Item.GetItemStats = function(l) if tostring(l):find("19100") then return nil end return real(l) end
		local worn = Inv().Equipped()
		isNil(worn[1].stats)
		local piece = assert(Inv().Piece(19101))
		Inv().Fill(piece, worn)
		C_Item.GetItemStats = real
		deepEq(worn[1].stats, { [STR] = 90, [STA] = 40 })
		deepEq(worn[5].stats, { [STR] = 100, [STA] = 50 }, "known stats stay as they are")
	end)

	it("never touches stats that are known on both sides", function()
		local worn = Inv().Equipped()
		local piece = assert(Inv().Piece(19101))
		eq(Inv().Fill(piece, worn), 0)
	end)

	it("a secret value from the game is read as no stats at all", function()
		Mock.items.secret = true
		local piece = assert(Inv().Piece(19101))
		isNil(piece.stats)
	end)
end)

---------------------------------------------------------------------------------------------------------------------

describe("the verdicts of the advisor", function()
	before_boot(setup)

	it("compares with the worn piece on the stats of the spec being played: Big upgrade, +11.7%, ilvl +6", function()
		local advice = assert(A().For(19101))
		eq(advice.ms.verdict, "BIG"); eq(advice.ms.basis, "STATS"); eq(advice.ms.usable, true)
		near(advice.ms.pct, 11 / 94, 0.0001)
		eq(advice.ms.ilvlDelta, 6)
		isNil(advice.os, "no declaration: there is no off-spec")
		eq(advice.specs.ms, 71); isNil(advice.specs.os)
		eq(advice.autoPass, false)
		deepEq(advice.equipped, { "item:19100::::::::70:::::" })
	end)

	it("says the words: chip text, tone and tooltip lines, from the locale", function()
		local u = A().For(19101).ms
		eq(A().Text(u), "Big upgrade +11.7% · ilvl +6")
		eq(A().Tone(u), "ok")
		local lines = A().Lines(u, "MS")
		eq(lines[1], "Main-spec: Big upgrade +11.7% · ilvl +6")
		eq(lines[2], FDCP.L["UPG_BASIS_STATS"])
		eq(A().Text({ verdict = "SMALL", usable = true, pct = 0.031, ilvlDelta = 0 }), "Small upgrade +3.1% · ilvl +0")
		eq(A().Text({ verdict = "NONE", usable = true, pct = -0.124, ilvlDelta = -4 }), "No upgrade -12.4% · ilvl -4")
		eq(A().Text({ verdict = "NOT_COMPARABLE", usable = true }), "Not comparable")
		eq(A().Text({ verdict = "NONE", usable = false, code = "ARMOR_TYPE" }), "Not usable")
		eq(A().Tone({ verdict = "NONE", usable = false }), "warn")
		eq(A().Tone({ verdict = "SMALL", usable = true }), "accent")
		eq(A().Tone({ verdict = "NONE", usable = true }), "neutral")
		eq(A().Text(nil), "")
	end)

	it("speaks Italian, with the decimal comma", function()
		FDCP.Locale.SetActive("itIT")
		eq(A().Text(A().For(19101).ms), "Upgrade grande +11,7% · ilvl +6")
		eq(A().Text({ verdict = "NONE", usable = false }), "Non usabile")
		local lines = A().Lines({ verdict = "NONE", usable = false, code = "ARMOR_TYPE" }, "OS")
		eq(lines[1], "Off-spec: Non usabile")
		eq(lines[2], "La tua classe non può indossare questo tipo di armatura.")
		FDCP.Locale.SetActive(nil)
	end)

	it("an empty slot is a big upgrade with no percentage", function()
		local advice = assert(A().For(19130))
		eq(advice.ms.verdict, "BIG"); isNil(advice.ms.pct)
		deepEq(advice.equipped, {})
		eq(A().Text(advice.ms), "Big upgrade")
	end)

	it("an item the character cannot use: not usable, the code, Pass preselected", function()
		local advice = assert(A().For(19120))
		eq(advice.ms.usable, false); eq(advice.ms.code, "WEAPON_TYPE")
		eq(advice.autoPass, true)
		deepEq(advice.wire.vd.m, { v = "NONE", u = false, c = "WEAPON_TYPE" })
		eq(A().Lines(advice.ms)[2], FDCP.L["RC_UPGRADE_WEAPON_TYPE"])
	end)

	it("a token the addon cannot compare is not a reason to pass", function()
		local advice = assert(A().For(19140))
		eq(advice.ms.verdict, "NOT_COMPARABLE"); isNil(advice.ms.usable)
		eq(advice.autoPass, false)
	end)

	it("keeps the verdict while nothing changes and recomputes when the equipment changes", function()
		local first = A().For(19101)
		eq(A().For(19101), first, "the same table: nothing was read again")
		Mock.items.Add{ id = 19102, link = link(19102, "Better Helm"), name = "Better Helm", equipLoc = "INVTYPE_HEAD", classID = 4,
			subclassID = 4, level = 70, stats = { [STR] = 120, [STA] = 50 } }
		Mock.items.equipped[1] = link(19102, "Better Helm")
		Mock.Fire("PLAYER_EQUIPMENT_CHANGED", 1, false)
		local second = A().For(19101)
		ne(second, first)
		eq(second.ms.verdict, "NONE")
		eq(second.ms.ilvlDelta, 0)
		deepEq(second.equipped, { "item:19102::::::::70:::::" })
	end)

	it("recomputes when the player changes specialization, and tells the popup", function()
		local seen = 0
		FDCP.Bus:On("UPGRADE_ADVICE_CHANGED", function() seen = seen + 1 end)
		eq(A().For(19111).specs.ms, 71)
		Mock.specs.Set{ active = 3 }
		local advice = A().For(19111)
		eq(advice.specs.ms, 73)
		eq(advice.ms.verdict, "BIG", "the tank weights value the stamina")
		truthy(seen >= 1)
	end)

	it("does not keep an item whose data is not loaded, and has it once the game has loaded it", function()
		Mock.items.Add{ id = 19160, link = link(19160, "Late Helm"), name = "Late Helm", equipLoc = "INVTYPE_HEAD", classID = 4,
			subclassID = 4, level = 70, stats = { [STR] = 100 }, cached = false }
		local advice, why = A().For(19160)
		isNil(advice); eq(why, "NOT_LOADED")
		Mock.items.byId[19160].cached = true
		truthy(A().For(19160))
	end)

	it("is nothing when the game does not say the class", function()
		Mock.player.classFile = nil
		A().Reset()
		local advice, why = A().For(19101)
		isNil(advice); eq(why, "NO_CLASS")
	end)

	it("falls back to the item level when the game gives no stats", function()
		Mock.items.noStats = true
		local advice = assert(A().For(19101))
		eq(advice.ms.basis, "ILVL")
		near(advice.ms.pct, 6 / 64, 0.0001)
		eq(advice.ms.verdict, "BIG")
	end)

	it("two rings and a one-hander read the slots the item goes in", function()
		Mock.items.Add{ id = 19131, link = link(19131, "Worn Ring"), name = "Worn Ring", equipLoc = "INVTYPE_FINGER", classID = 4,
			subclassID = 0, level = 60, stats = { [STR] = 20 } }
		Mock.items.Add{ id = 19132, link = link(19132, "Good Ring"), name = "Good Ring", equipLoc = "INVTYPE_FINGER", classID = 4,
			subclassID = 0, level = 66, stats = { [STR] = 40 } }
		Mock.items.equipped[11], Mock.items.equipped[12] = link(19131, "Worn Ring"), link(19132, "Good Ring")
		A().Reset()
		local advice = assert(A().For(19130))
		eq(advice.ms.verdict, "BIG", "30 against the worse ring (20)")
		deepEq(advice.ms.slots, { 11 })
		deepEq(advice.equipped, { "item:19131::::::::70:::::" })
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The declared specs and the guild's rules come from the ledger

describe("declared specs and rules", function()
	before_boot(function(M)
		setup(M)
		M.guild.Set({ name = "Keepers", ranks = { [0] = "Guild Master", "Officer" }, myRank = 1, members = {
			{ name = "Aurel", rank = 0 }, { name = "Testchar", rank = 1 } } })
	end)

	local function ledger(ms1, ms2, rules)
		local Lg, Sn, R = FDCP.Ledger, FDCP.Season, FDCP.Roster
		local L1 = Lg.New()
		local GM = full("Aurel")
		assert(Sn.Open(L1, { author = GM, ts = 1, season = "S1", instances = { { id = 409, size = 40 } } }))
		assert(R.Join(L1, { author = GM, ts = 2, season = "S1", member = full("Testchar"), faction = "Horde", ms1 = ms1, ms2 = ms2 }))
		if rules then
			assert(FDCP.Rules.Change(L1, { author = GM, ts = 3, rules = FDCP.Rules.WithDefaults(rules), confirmed = true }))
		end
		FDCP.NightController:Bind(L1)
		Mock.Advance(3)
		A().Reset()
		return L1
	end

	it("main-spec is the MS1 and off-spec the MS2, each with its own weights", function()
		ledger(72, 73)
		local advice = assert(A().For(19111))
		eq(advice.specs.ms, 72); eq(advice.specs.os, 73)
		eq(advice.ms.verdict, "NONE", "fury: 80 strength and 120 stamina is worse than 100 and 50")
		near(advice.ms.pct, -13 / 105, 0.001)
		eq(advice.os.verdict, "BIG", "protection: the stamina is worth more")
		near(advice.os.pct, 62 / 90, 0.001)
		deepEq(advice.wire.vd.m, { v = "NONE", b = "STATS", p = -124, l = 0 })
		deepEq(advice.wire.vd.o, { v = "BIG", b = "STATS", p = 689, l = 0 })
		eq(advice.autoPass, false)
	end)

	it("the declared spec wins over the spec played now, and an undeclared one falls back to it", function()
		ledger(72, nil)
		eq(A().For(19101).specs.ms, 72)
		isNil(A().For(19101).os)
		Mock.specs.Set{ active = 3 }
		eq(A().For(19101).specs.ms, 72, "MS1 is the main-spec whatever the player plays at the moment")
		FDCP.NightController:Bind(FDCP.Ledger.New())
		A().Reset()
		eq(A().For(19101).specs.ms, 73)
	end)

	it("a declared spec of another class is ignored (an alt on the main's name does not exist, a wrong id does)", function()
		ledger(258, nil)   -- a priest's shadow spec on a warrior
		eq(A().For(19101).specs.ms, 71)
	end)

	it("uses the thresholds of the rules: a 5% upgrade is small when the guild asks for 15% for a big one", function()
		ledger(72, nil, { upgrade = { enabled = true, autoPass = true, useStats = true, bigThreshold = 0.15, smallThreshold = 0,
			ilvlBigThreshold = 0.05 } })
		eq(A().For(19101).ms.verdict, "SMALL", "+11.7% is not 15%")
	end)

	it("the rules can turn the item-level fallback on for everybody", function()
		ledger(72, nil, { upgrade = { enabled = true, autoPass = true, useStats = false, bigThreshold = 0.05, smallThreshold = 0,
			ilvlBigThreshold = 0.20 } })
		local advice = A().For(19101)
		eq(advice.ms.basis, "ILVL")
		eq(advice.ms.verdict, "SMALL", "+9.4% of item level, the big threshold is 20%")
	end)

	it("the rules can turn the verdicts off", function()
		ledger(72, nil, { upgrade = { enabled = false, autoPass = true, useStats = true, bigThreshold = 0.05, smallThreshold = 0,
			ilvlBigThreshold = 0.05 } })
		local advice, why = A().For(19101)
		isNil(advice); eq(why, "DISABLED")
	end)

	it("the rules can turn the Pass preselection off", function()
		ledger(72, nil)
		eq(A().For(19120).autoPass, true)
		ledger(72, nil, { upgrade = { enabled = true, autoPass = false, useStats = true, bigThreshold = 0.05, smallThreshold = 0,
			ilvlBigThreshold = 0.05 } })
		local advice = A().For(19120)
		eq(advice.ms.usable, false); eq(advice.autoPass, false)
	end)

	it("Pass is preselected only when no declared spec can use the item", function()
		-- a one-hander for a priest's wand... use the wand for a warrior: neither fury nor protection can use it
		ledger(72, 73)
		eq(A().For(19120).autoPass, true)
		-- a plate piece that only the second spec may use is not refused for the main-spec
		Mock.items.Add{ id = 19180, link = link(19180, "Guardian Plate"), name = "Guardian Plate", equipLoc = "INVTYPE_LEGS", classID = 4,
			subclassID = 4, level = 70, stats = { [STA] = 80 }, specs = { 73 } }
		A().Reset()
		local advice = A().For(19180)
		eq(advice.ms.usable, false); eq(advice.ms.code, "SPEC_RESTRICTED")
		eq(advice.os.usable, true)
		eq(advice.autoPass, false)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The wire: what a response carries and what the other side accepts

describe("the verdicts on the wire", function()
	before_boot(setup)

	local GOOD = { m = { v = "BIG", b = "STATS", p = 117, l = 6 }, o = { v = "NONE", u = false, c = "ARMOR_TYPE" } }

	it("a result becomes a few small fields and comes back as the same result", function()
		local r = A().For(19101).ms
		local w = U().Pack(r)
		deepEq(w, { v = "BIG", b = "STATS", p = 117, l = 6 })
		local back = U().Unpack(w)
		eq(back.verdict, "BIG"); eq(back.usable, true); eq(back.basis, "STATS"); eq(back.pct, 0.117); eq(back.ilvlDelta, 6)
		deepEq(U().Pack({ verdict = "NONE", usable = false, code = "ARMOR_TYPE" }), { v = "NONE", u = false, c = "ARMOR_TYPE" })
		isNil(U().Pack(nil)); isNil(U().Pack({})); isNil(U().Unpack({}))
		eq(U().Pack({ verdict = "BIG", pct = 1e9, ilvlDelta = -1e9 }).p, 100000, "clamped, never a runaway number")
		eq(U().Pack({ verdict = "BIG", ilvlDelta = -1e9 }).l, -2000)
		eq(U().Unpack({ v = "NONE", u = false }).usable, false)
	end)

	it("reads a good SRESP with its verdicts and worn pieces", function()
		local r = PS().ReadResponse({ s = "S1-1", i = 1, r = 1, rs = "MS", vd = GOOD, eq = { "item:19100::::::::70:::::" } },
			full("Bryn"))
		deepEq(r.vd, GOOD)
		deepEq(r.eq, { "item:19100::::::::70:::::" })
	end)

	it("an older client sends neither, and the response still counts", function()
		local r = assert(PS().ReadResponse({ s = "S1-1", i = 1, r = 1, rs = "PASS" }, full("Bryn")))
		isNil(r.vd); isNil(r.eq)
		eq(r.rs, "PASS")
	end)

	it("drops a damaged verdict or link and keeps the response", function()
		local function read(fields)
			fields.s, fields.i, fields.r, fields.rs = "S1-1", 1, 1, "MS"
			return assert(PS().ReadResponse(fields, full("Bryn")))
		end
		isNil(read({ vd = "BIG" }).vd, "not a table")
		isNil(read({ vd = {} }).vd, "no main-spec verdict")
		isNil(read({ vd = { m = { v = "big" } } }).vd, "not a code")
		isNil(read({ vd = { m = { v = "BIG", u = true } } }).vd, "u is false or absent")
		isNil(read({ vd = { m = { v = "BIG", p = 1.5 } } }).vd, "permille is a whole number")
		isNil(read({ vd = { m = { v = "BIG", p = 1e12 } } }).vd, "out of range")
		isNil(read({ vd = { m = { v = "BIG", l = 99999 } } }).vd)
		isNil(read({ vd = { m = { v = "BIG", c = "lower" } } }).vd)
		isNil(read({ vd = { m = { v = "BIG", b = 5 } } }).vd)
		isNil(read({ vd = { m = { v = "BIG" }, o = "x" } }).vd, "a damaged off-spec verdict drops the pair")
		isNil(read({ eq = "item:1" }).eq)
		isNil(read({ eq = {} }).eq)
		isNil(read({ eq = { "|cffa335ee|Hitem:1::::::::70:::::|h[Hacked]|h|r" } }).eq, "no hyperlink markup")
		isNil(read({ eq = { "item:1", "item:2", "item:3", "item:4", "item:5" } }).eq, "at most four")
		isNil(read({ eq = { "item:" .. string.rep("1", 200) } }).eq, "too long")
		isNil(read({ eq = { 19100 } }).eq)
		isNil(read({ eq = { "spell:12" } }).eq)
	end)

	it("a response sent with the verdicts carries them, a damaged extra is left out", function()
		-- the sender side is Session:Respond: without a session it refuses before looking at the extras
		local item, why = PS():Respond("MS", nil, nil, { vd = GOOD })
		isNil(item); eq(why, "NO_SESSION")
	end)
end)

describe("the master looter's session keeps the verdicts", function()
	local F = function() return FDCP.SessionFSM end
	before_boot(setup)

	local function session()
		local present = { [full("Aurel")] = true, [full("Bryn")] = true, [full("Corin")] = true }
		local rules = FDCP.Rules.DefaultConfig()
		rules.session.autoAdvance = false   -- the master looter opens each roll
		local s = assert(F().New({ id = "S1-1", season = "S1", ml = full("Aurel"), ts = 1, rules = rules, present = present, addon = present }))
		local L = FDCP.Ledger.New()
		local function step(input)
			input.ts = input.ts or 2
			return F().Step(s, input, { ledger = L })
		end
		assert(step({ type = "LOOT_OPENED", items = { { itemID = 19101, slot = 1, classID = 4, subclassID = 4, equipLoc = "INVTYPE_HEAD", quality = 4 } },
			encounter = 663 }))
		assert(step({ type = "START", by = full("Aurel") }))
		assert(step({ type = "OPEN_ROLL", by = full("Aurel") }))
		return s, step
	end

	it("stores what a response says about the piece, for a pass too, and a later answer replaces it", function()
		local s, step = session()
		local vd = { m = { v = "BIG", p = 117, l = 6 }, o = { v = "SMALL", p = 31 } }
		assert(step({ type = "RESPONSE", player = full("Bryn"), response = "MS", verdict = vd, equipped = { "item:19100" } }))
		assert(step({ type = "RESPONSE", player = full("Corin"), response = "PASS", verdict = vd }))
		local item = s.items[1]
		deepEq(item.verdicts[full("Bryn")], vd)
		deepEq(item.equipped[full("Bryn")], { "item:19100" })
		deepEq(item.verdicts[full("Corin")], vd, "a pass keeps the verdict: the 'upgrade ignored' flag needs it")
		isNil(item.equipped[full("Corin")])
		assert(step({ type = "RESPONSE", player = full("Bryn"), response = "OS", verdict = { m = { v = "NONE" } } }))
		deepEq(item.verdicts[full("Bryn")], { m = { v = "NONE" } })
		isNil(item.equipped[full("Bryn")])
	end)

	it("ignores a verdict that is not a table and never lets it change the rules' view of the answer", function()
		local s, step = session()
		assert(step({ type = "RESPONSE", player = full("Bryn"), response = "MS", verdict = "BIG", equipped = "x" }))
		eq(s.items[1].responses[full("Bryn")], "MS")
		isNil(s.items[1].verdicts[full("Bryn")])
		isNil(s.items[1].equipped[full("Bryn")])
	end)

	it("hands them to the board: the verdict of the spec of the answer, both verdicts and the worn pieces", function()
		local s, step = session()
		local vd = { m = { v = "BIG", p = 117, l = 6 }, o = { v = "NONE", u = false, c = "ARMOR_TYPE" } }
		assert(step({ type = "RESPONSE", player = full("Bryn"), response = "MS", verdict = vd, equipped = { "item:19100" } }))
		assert(step({ type = "RESPONSE", player = full("Corin"), response = "OS", verdict = vd }))
		assert(step({ type = "RESPONSE", player = full("Aurel"), response = "OS", verdict = { m = { v = "SMALL" } } }))
		local board = FDCP.SessionBoard.Build({ host = true, session = s }, { now = 2 })
		local by = {}
		for _, c in ipairs(board.candidates) do by[c.player] = c end
		eq(by[full("Bryn")].upgrade.verdict, "BIG"); eq(by[full("Bryn")].upgrade.pct, 0.117)
		eq(by[full("Bryn")].upgradeMS.ilvlDelta, 6)
		eq(by[full("Bryn")].upgradeOS.usable, false)
		deepEq(by[full("Bryn")].equipped, { "item:19100" })
		eq(by[full("Corin")].upgrade.usable, false, "an off-spec answer reads the off-spec verdict")
		eq(by[full("Aurel")].upgrade.verdict, "SMALL", "no off-spec verdict: the main-spec one")
		isNil(by[full("Aurel")].upgradeOS)
		isNil(by[full("Aurel")].equipped)
	end)

	it("a candidate who sent nothing has no verdict", function()
		local s, step = session()
		assert(step({ type = "RESPONSE", player = full("Bryn"), response = "MS" }))
		local board = FDCP.SessionBoard.Build({ host = true, session = s }, { now = 2 })
		for _, c in ipairs(board.candidates) do isNil(c.upgrade); isNil(c.equipped) end
	end)
end)
