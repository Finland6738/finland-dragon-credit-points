-- The inventory adapter, the gear snapshot and the upgrade advisor (M5-2, rewritten by M7-5c): Adapters/Inventory.lua reads
-- what the player wears and an item's data through Core/Compat.lua (mock client: C_Item.*, GetInventoryItemLink,
-- specializations), Adapters/GearSnapshot.lua keeps the gear of the boss fight (ENCOUNTER_START), App/UpgradeAdvisor.lua
-- turns it into the badges of main-spec and off-spec with Domain/UpgradeScore.lua's tiers, the season's item-level band and
-- the rules of the ledger; the response protocol carries the result (Net/Protocol.lua: SRESP `vd` / `eq`).
-- (docs/ANALISI.md §5.1, §6)
local function Inv() return FDCP.Inventory end
local function A() return FDCP.UpgradeAdvisor end
local function U() return FDCP.UpgradeScore end
local function G() return FDCP.GearSnapshot end
local function PS() return FDCP.Protocol.Session end

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end

local function link(id, name) return "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[" .. name .. "]|h|r" end
local function ref(id) return "item:" .. id .. "::::::::70:::::" end

local GREEN, BLUE, PURPLE = 2, 3, 4

-- A warrior (the mock's default character) in plate: a worn blue helm and a worn purple chest, a purple helm to pick up,
-- a purple chest of a lower level, a wand and a token it cannot use, a ring for the empty ring slots.
local ITEMS = {
	{ id = 19100, link = link(19100, "Old Helm"), name = "Old Helm", equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 4,
		level = 200, quality = BLUE },
	{ id = 19101, link = link(19101, "Helm of Embers"), name = "Helm of Embers", equipLoc = "INVTYPE_HEAD", classID = 4,
		subclassID = 4, level = 226, quality = PURPLE },
	{ id = 19110, link = link(19110, "Old Chest"), name = "Old Chest", equipLoc = "INVTYPE_CHEST", classID = 4, subclassID = 4,
		level = 213, quality = PURPLE },
	{ id = 19111, link = link(19111, "Bulwark Chest"), name = "Bulwark Chest", equipLoc = "INVTYPE_CHEST", classID = 4,
		subclassID = 4, level = 226, quality = PURPLE },
	{ id = 19120, link = link(19120, "Wand of Sparks"), name = "Wand of Sparks", equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2,
		subclassID = 19, level = 226, quality = PURPLE },
	{ id = 19130, link = link(19130, "Ring of the Keeper"), name = "Ring of the Keeper", equipLoc = "INVTYPE_FINGER",
		classID = 4, subclassID = 0, level = 226, quality = PURPLE },
	{ id = 19140, link = link(19140, "Token of Embers"), name = "Token of Embers", equipLoc = "", classID = 15,
		subclassID = 0, level = 226, quality = PURPLE },
	{ id = 19190, link = link(19190, "Green Helm"), name = "Green Helm", equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 4,
		level = 150, quality = GREEN },
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

	it("describes an item: slot, kind, quality, level and the specs it is for; no stats any more", function()
		Mock.items.Add{ id = 19150, link = link(19150, "Arms Blade"), name = "Arms Blade", equipLoc = "INVTYPE_2HWEAPON", classID = 2,
			subclassID = 8, level = 226, quality = PURPLE, specs = { 71, 72 } }
		local p = assert(Inv().Piece(19150))
		eq(p.itemID, 19150); eq(p.link, "item:19150")
		eq(p.equipLoc, "INVTYPE_2HWEAPON"); eq(p.classID, 2); eq(p.subclassID, 8)
		eq(p.level, 226); eq(p.quality, PURPLE)
		isNil(p.stats)
		deepEq(p.specs, { 71, 72 })
		isNil(Inv().Piece(19101).specs, "an item with no spec list is not restricted")
	end)

	it("reads the quality with C_Item.GetItemQualityByID", function()
		local real = C_Item.GetItemQualityByID
		local asked
		C_Item.GetItemQualityByID = function(x) asked = x; return BLUE end
		eq(Inv().Piece(WORN_HEAD).quality, BLUE)
		C_Item.GetItemQualityByID = real
		eq(asked, WORN_HEAD, "the worn piece's own link")
		eq(FDCP.Compat.Item.Quality(19100), BLUE)
		isNil(FDCP.Compat.Item.Quality(nil))
	end)

	it("reads the spec list from DoesItemContainSpec when GetItemSpecInfo says nothing", function()
		Mock.items.Add{ id = 19151, link = link(19151, "Fury Blade"), name = "Fury Blade", equipLoc = "INVTYPE_WEAPON", classID = 2,
			subclassID = 7, level = 226, specs = { 72 } }
		local real = C_Item.GetItemSpecInfo
		C_Item.GetItemSpecInfo = function() return nil end
		local p = assert(Inv().Piece(19151, { classID = 1, classFile = "WARRIOR" }))
		C_Item.GetItemSpecInfo = real
		deepEq(p.specs, { 72 })
	end)

	it("says why it has nothing: an unknown item, an item whose data is not loaded", function()
		local p, why = Inv().Piece(99999)
		isNil(p); eq(why, "UNKNOWN")
		Mock.items.Add{ id = 19160, link = link(19160, "Late Item"), name = "Late Item", equipLoc = "INVTYPE_HEAD", classID = 4,
			subclassID = 4, level = 226, cached = false }
		p, why = Inv().Piece(19160)
		isNil(p); eq(why, "NOT_LOADED")
		p = Inv().Piece(19160, { unloaded = true })
		truthy(p, "a worn piece may be read from the instant data")
		eq(p.equipLoc, "INVTYPE_HEAD")
		isNil(p.quality, "the quality waits for the full data")
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
		eq(worn[1].slot, 1); eq(worn[1].quality, BLUE)
		deepEq(Inv().Links(), { [1] = WORN_HEAD, [5] = WORN_CHEST })
	end)

	it("reads the character: class and the spec it plays", function()
		local p = Inv().Player()
		eq(p.class, "WARRIOR"); eq(p.classID, 1); eq(p.spec, 71)
		Mock.specs.Set{ active = 3 }
		eq(Inv().Player().spec, 73)
	end)
end)

---------------------------------------------------------------------------------------------------------------------

describe("the gear snapshot of the boss fight", function()
	before_boot(setup)

	it("ENCOUNTER_START keeps the worn links, the boss and the time, also in the character's saved data", function()
		Mock.Fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
		local snap = assert(G().Current())
		eq(snap.encounter, 663)
		deepEq(snap.links, { [1] = WORN_HEAD, [5] = WORN_CHEST })
		eq(snap.at, GetServerTime())
		eq(FDCP.Config.char.gearSnapshot, snap)
	end)

	it("a gear change after the kill does not change the snapshot", function()
		Mock.Fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
		Mock.Fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1)
		Mock.items.equipped[1] = nil
		deepEq(G().Current(663).links[1], WORN_HEAD)
	end)

	it("a client that missed the start takes it at the end", function()
		isNil(G().Current())
		Mock.Fire("ENCOUNTER_END", 664, "Magmadar", 9, 40, 1)
		eq(G().Current().encounter, 664)
	end)

	it("a hidden id at the start is completed at the end", function()
		Mock.Fire("ENCOUNTER_START", Mock.SECRET, "Lucifron", 9, 40)
		isNil(G().Current().encounter)
		Mock.Fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1)
		eq(G().Current().encounter, 663)
	end)

	it("Pick: fresh, and of the session's boss when both are known", function()
		local snap = { encounter = 663, at = 1000, links = {} }
		eq(G().Pick(snap, 663, 1000 + 60), snap)
		eq(G().Pick(snap, nil, 1000 + 60), snap)
		isNil(G().Pick(snap, 664, 1000 + 60), "another boss")
		isNil(G().Pick(snap, 663, 1000 + G().MAX_AGE + 1), "too old")
		eq(G().Pick({ at = 1000, links = {} }, 664, 1001).at, 1000, "a snapshot without a boss stands for any")
		isNil(G().Pick(nil, 663, 1000)); isNil(G().Pick({ at = 1 }, 663, 2))
	end)

	it("an old snapshot is not used", function()
		Mock.Fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
		Mock.SetServerTime(GetServerTime() + G().MAX_AGE + 5)
		isNil(G().Current())
	end)
end)

---------------------------------------------------------------------------------------------------------------------

describe("the badges of the advisor", function()
	before_boot(setup)

	it("purple over the worn blue helm: medium upgrade, ilvl +26", function()
		local advice = assert(A().For(19101))
		eq(advice.ms.verdict, "MEDIUM"); eq(advice.ms.usable, true)
		eq(advice.ms.ilvlDelta, 26)
		isNil(advice.os, "no declaration: there is no off-spec")
		eq(advice.specs.ms, 71); isNil(advice.specs.os)
		eq(advice.autoPass, false)
		eq(advice.snapshot, false, "no fight seen: the gear worn now")
		deepEq(advice.equipped, { "item:19100::::::::70:::::" })
		deepEq(advice.wire.vd.m, { v = "MEDIUM", l = 26 })
	end)

	it("purple over the worn purple chest: minor upgrade", function()
		local advice = assert(A().For(19111))
		eq(advice.ms.verdict, "MINOR"); eq(advice.ms.ilvlDelta, 13)
	end)

	it("says the words: badge text, tone and tooltip lines, from the locale", function()
		local u = A().For(19101).ms
		eq(A().Text(u), "Medium upgrade · ilvl +26")
		eq(A().Tone(u), "accent")
		local lines = A().Lines(u, "MS")
		eq(lines[1], "Main-spec: Medium upgrade · ilvl +26")
		eq(A().Text({ verdict = "MAJOR", usable = true, code = "EMPTY_SLOT" }), "Major upgrade · empty slot")
		eq(A().Text({ verdict = "MINOR", usable = true, ilvlDelta = 13 }), "Minor upgrade · ilvl +13")
		eq(A().Text({ verdict = "NONE", usable = true, ilvlDelta = -4 }), "No upgrade · ilvl -4")
		eq(A().Text({ verdict = "NOT_COMPARABLE", usable = true, code = "NO_QUALITY" }), "Not comparable")
		eq(A().Text({ verdict = "NONE", usable = false, code = "ARMOR_TYPE" }), "Not usable")
		eq(A().Tone({ verdict = "MAJOR", usable = true }), "ok")
		eq(A().Tone({ verdict = "NONE", usable = false }), "warn")
		eq(A().Tone({ verdict = "NONE", usable = true }), "neutral")
		eq(A().Text(nil), "")
		local old = A().Lines({ verdict = "MEDIUM", usable = true, ilvlDelta = 39, notes = { "OLD_SEASON" } }, "MS")
		eq(old[2], FDCP.L["RC_UPGRADE_OLD_SEASON"])
	end)

	it("speaks Italian", function()
		FDCP.Locale.SetActive("itIT")
		eq(A().Text(A().For(19101).ms), "Upgrade medio · ilvl +26")
		eq(A().Text({ verdict = "MAJOR", usable = true, code = "EMPTY_SLOT" }), "Upgrade grande · slot vuoto")
		eq(A().Text({ verdict = "NONE", usable = false }), "Non usabile")
		local lines = A().Lines({ verdict = "NONE", usable = false, code = "ARMOR_TYPE" }, "OS")
		eq(lines[1], "Off-spec: Non usabile")
		eq(lines[2], "La tua classe non può indossare questo tipo di armatura.")
		FDCP.Locale.SetActive(nil)
	end)

	it("an empty slot is a major upgrade", function()
		local advice = assert(A().For(19130))
		eq(advice.ms.verdict, "MAJOR"); eq(advice.ms.code, "EMPTY_SLOT")
		deepEq(advice.equipped, {})
		eq(A().Text(advice.ms), "Major upgrade · empty slot")
	end)

	it("a green worn piece: major upgrade", function()
		Mock.items.equipped[1] = link(19190, "Green Helm")
		A().Reset()
		local advice = assert(A().For(19101))
		eq(advice.ms.verdict, "MAJOR"); eq(advice.ms.ilvlDelta, 76)
	end)

	it("an item the character cannot use: not usable, the code, Pass preselected", function()
		local advice = assert(A().For(19120))
		eq(advice.ms.usable, false); eq(advice.ms.code, "WEAPON_TYPE")
		eq(advice.autoPass, true)
		deepEq(advice.wire.vd.m, { v = "NONE", u = false, c = "WEAPON_TYPE" })
		eq(A().Lines(advice.ms)[2], FDCP.L["RC_UPGRADE_WEAPON_TYPE"])
		eq(A().Badge(advice), advice.ms)
	end)

	it("a token the addon cannot compare is not a reason to pass", function()
		local advice = assert(A().For(19140))
		eq(advice.ms.verdict, "NOT_COMPARABLE"); isNil(advice.ms.usable)
		eq(advice.autoPass, false)
	end)

	it("a worn piece the client has not loaded: not comparable, asked for, then computed", function()
		Mock.items.byId[19100].cached = false
		A().Reset()
		local seen = 0
		FDCP.Bus:On("UPGRADE_ADVICE_CHANGED", function() seen = seen + 1 end)
		local advice = assert(A().For(19101))
		eq(advice.ms.verdict, "NOT_COMPARABLE"); eq(advice.ms.code, "NO_QUALITY")
		Mock.Advance(1)
		truthy(seen >= 1, "the popup is told to draw again")
		eq(A().For(19101).ms.verdict, "MEDIUM")
	end)

	it("keeps the badge while nothing changes and recomputes when the equipment changes", function()
		local first = A().For(19101)
		eq(A().For(19101), first, "the same table: nothing was read again")
		Mock.items.Add{ id = 19102, link = link(19102, "Better Helm"), name = "Better Helm", equipLoc = "INVTYPE_HEAD", classID = 4,
			subclassID = 4, level = 226, quality = PURPLE }
		Mock.items.equipped[1] = link(19102, "Better Helm")
		Mock.Fire("PLAYER_EQUIPMENT_CHANGED", 1, false)
		local second = A().For(19101)
		ne(second, first)
		eq(second.ms.verdict, "NONE", "the same level and grade")
		eq(second.ms.ilvlDelta, 0)
		deepEq(second.equipped, { "item:19102::::::::70:::::" })
	end)

	it("uses the gear of the fight, not the gear worn when the item is rolled", function()
		Mock.Fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
		Mock.items.equipped[1] = nil            -- the helm comes off after the kill
		Mock.Fire("PLAYER_EQUIPMENT_CHANGED", 1, true)
		local advice = assert(A().For(19101))
		eq(advice.snapshot, true)
		eq(advice.ms.verdict, "MEDIUM", "against the blue helm of the fight, not an empty slot")
		deepEq(advice.equipped, { "item:19100::::::::70:::::" })
		-- without the snapshot the same gear would be a major upgrade
		G().last, FDCP.Config.char.gearSnapshot = nil, nil
		A().Reset()
		eq(A().For(19101).ms.verdict, "MAJOR")
	end)

	it("a new snapshot tells the popup", function()
		local seen = 0
		FDCP.Bus:On("UPGRADE_ADVICE_CHANGED", function() seen = seen + 1 end)
		Mock.Fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
		truthy(seen >= 1)
	end)

	it("the session's item-level band makes an older purple count as a blue", function()
		Mock.items.Add{ id = 19112, link = link(19112, "Ancient Chest"), name = "Ancient Chest", equipLoc = "INVTYPE_CHEST",
			classID = 4, subclassID = 4, level = 187, quality = PURPLE }
		Mock.items.equipped[5] = link(19112, "Ancient Chest")
		A().Reset()
		eq(A().For(19111).ms.verdict, "MINOR", "no band: every purple is this season's")
		PS().view = { s = "S1-663-1", e = 663, items = {}, responses = {}, band = { min = 200, max = 226 } }
		local advice = A().For(19111)
		eq(advice.ms.verdict, "MEDIUM"); eq(advice.ms.ilvlDelta, 39)
		deepEq(advice.band, { min = 200, max = 226 })
		PS().view = nil
	end)

	it("recomputes when the player changes specialization, and tells the popup", function()
		local seen = 0
		FDCP.Bus:On("UPGRADE_ADVICE_CHANGED", function() seen = seen + 1 end)
		eq(A().For(19111).specs.ms, 71)
		Mock.specs.Set{ active = 3 }
		eq(A().For(19111).specs.ms, 73)
		truthy(seen >= 1)
	end)

	it("does not keep an item whose data is not loaded, and has it once the game has loaded it", function()
		Mock.items.Add{ id = 19160, link = link(19160, "Late Helm"), name = "Late Helm", equipLoc = "INVTYPE_HEAD", classID = 4,
			subclassID = 4, level = 226, cached = false }
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

	it("two rings: the worse of the two worn", function()
		Mock.items.Add{ id = 19131, link = link(19131, "Worn Ring"), name = "Worn Ring", equipLoc = "INVTYPE_FINGER", classID = 4,
			subclassID = 0, level = 190, quality = BLUE }
		Mock.items.Add{ id = 19132, link = link(19132, "Good Ring"), name = "Good Ring", equipLoc = "INVTYPE_FINGER", classID = 4,
			subclassID = 0, level = 220, quality = PURPLE }
		Mock.items.equipped[11], Mock.items.equipped[12] = link(19131, "Worn Ring"), link(19132, "Good Ring")
		A().Reset()
		local advice = assert(A().For(19130))
		eq(advice.ms.verdict, "MEDIUM", "against the blue ring")
		deepEq(advice.ms.slots, { 11 })
		deepEq(advice.equipped, { "item:19131::::::::70:::::" })
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The declared specs and the guild's rules come from the ledger

describe("declared specs, rules and the season's band", function()
	before_boot(function(M)
		setup(M)
		M.guild.Set({ name = "Keepers", ranks = { [0] = "Guild Master", "Officer" }, myRank = 1, members = {
			{ name = "Aurel", rank = 0 }, { name = "Testchar", rank = 1 } } })
	end)

	local function ledger(ms1, ms2, upgrade, band)
		local Lg, Sn, R = FDCP.Ledger, FDCP.Season, FDCP.Roster
		local L1 = Lg.New()
		local GM = full("Aurel")
		assert(Sn.Open(L1, { author = GM, ts = 1, season = "S1", instances = { { id = 409, size = 40 } } }))
		assert(R.Join(L1, { author = GM, ts = 2, season = "S1", member = full("Testchar"), faction = "Horde", ms1 = ms1, ms2 = ms2 }))
		if upgrade then
			assert(FDCP.Rules.Change(L1, { author = GM, ts = 3, rules = FDCP.Rules.WithDefaults({ upgrade = upgrade }), confirmed = true }))
		end
		if band then assert(Sn.SetBand(L1, { author = GM, ts = 4, season = "S1", min = band[1], max = band[2] })) end
		FDCP.NightController:Bind(L1)
		Mock.Advance(3)
		A().Reset()
		return L1
	end

	it("main-spec is the MS1 and off-spec the MS2", function()
		ledger(72, 73)
		local advice = assert(A().For(19101))
		eq(advice.specs.ms, 72); eq(advice.specs.os, 73)
		eq(advice.ms.verdict, "MEDIUM"); eq(advice.os.verdict, "MEDIUM", "the tier does not depend on the spec")
		deepEq(advice.wire.vd, { m = { v = "MEDIUM", l = 26 }, o = { v = "MEDIUM", l = 26 } })
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

	it("a declared spec of another class is ignored", function()
		ledger(258, nil)   -- a priest's shadow spec on a warrior
		eq(A().For(19101).specs.ms, 71)
	end)

	it("the band of this client's open season, without a session", function()
		Mock.items.Add{ id = 19112, link = link(19112, "Ancient Chest"), name = "Ancient Chest", equipLoc = "INVTYPE_CHEST",
			classID = 4, subclassID = 4, level = 187, quality = PURPLE }
		Mock.items.equipped[5] = link(19112, "Ancient Chest")
		ledger(72, nil, nil, { 200, 226 })
		eq(A().For(19111).ms.verdict, "MEDIUM")
		deepEq(A().For(19111).band, { min = 200, max = 226 })
	end)

	it("the rules can turn the badge off", function()
		ledger(72, nil, { enabled = false, autoPass = true })
		local advice, why = A().For(19101)
		isNil(advice); eq(why, "DISABLED")
	end)

	it("the rules can turn the Pass preselection off", function()
		ledger(72, nil)
		eq(A().For(19120).autoPass, true)
		ledger(72, nil, { enabled = true, autoPass = false })
		local advice = A().For(19120)
		eq(advice.ms.usable, false); eq(advice.autoPass, false)
	end)

	it("rules written before M7-5c (with the stat thresholds and the label mode) still work", function()
		local L1 = ledger(72, nil)
		local old = FDCP.Rules.DefaultConfig()
		old.upgrade = { enabled = true, autoPass = false, useStats = true, bigThreshold = 0.15, smallThreshold = 0,
			ilvlBigThreshold = 0.05 }
		old.responses = { labelMode = "auto" }
		assert(FDCP.Ledger.Append(L1, { author = full("Aurel"), ts = 5, type = "CONFIG_CHANGED", payload = { rules = old, confirmed = true } }))
		A().Reset()
		eq(A().For(19101).ms.verdict, "MEDIUM")
		eq(A().For(19120).autoPass, false, "the old event is read: its autoPass counts")
	end)

	it("Pass is preselected only when no declared spec can use the item; the badge shows the usable spec", function()
		ledger(72, 73)
		eq(A().For(19120).autoPass, true)
		Mock.items.Add{ id = 19180, link = link(19180, "Guardian Plate"), name = "Guardian Plate", equipLoc = "INVTYPE_LEGS", classID = 4,
			subclassID = 4, level = 226, quality = PURPLE, specs = { 73 } }
		A().Reset()
		local advice = A().For(19180)
		eq(advice.ms.usable, false); eq(advice.ms.code, "SPEC_RESTRICTED")
		eq(advice.os.usable, true); eq(advice.os.verdict, "MAJOR")
		eq(advice.autoPass, false)
		local shown, which = A().Badge(advice)
		eq(shown, advice.os); eq(which, "os")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The wire: what a response carries and what the other side accepts

describe("the badges on the wire", function()
	before_boot(setup)

	local GOOD = { m = { v = "MEDIUM", l = 26 }, o = { v = "NONE", u = false, c = "ARMOR_TYPE" } }

	it("reads a good SRESP with its badges and worn pieces", function()
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

	it("an old client's fields are ignored: label, origin, note, and its BIG / SMALL verdict with basis and percent", function()
		local r = assert(PS().ReadResponse({ s = "S1-1", i = 1, r = 1, rs = "MS", lb = "BIS", lo = "AUTO", n = "my set ring",
			vd = { m = { v = "BIG", b = "STATS", p = 117, l = 6 } }, eq = { "item:19100" } }, full("Bryn")))
		eq(r.rs, "MS")
		isNil(r.lb); isNil(r.lo); isNil(r.n)
		isNil(r.vd, "an old verdict is not a tier")
		deepEq(r.eq, { "item:19100" })
		-- a label or a note that is not even well formed no longer refuses the response
		truthy(PS().ReadResponse({ s = "S1-1", i = 1, r = 1, rs = "MS", lb = 5, n = string.rep("x", 500) }, full("Bryn")))
		-- an old client's tier field next to a new one: only the known fields are kept
		deepEq(PS().ReadResponse({ s = "S1-1", i = 1, r = 1, rs = "MS", vd = { m = { v = "MAJOR", b = "STATS", p = 5 } } },
			full("Bryn")).vd, { m = { v = "MAJOR" } })
	end)

	it("drops a damaged badge or link and keeps the response", function()
		local function read(fields)
			fields.s, fields.i, fields.r, fields.rs = "S1-1", 1, 1, "MS"
			return assert(PS().ReadResponse(fields, full("Bryn")))
		end
		isNil(read({ vd = "MAJOR" }).vd, "not a table")
		isNil(read({ vd = {} }).vd, "no main-spec badge")
		isNil(read({ vd = { m = { v = "major" } } }).vd, "not a code")
		isNil(read({ vd = { m = { v = "HUGE" } } }).vd, "not a tier")
		isNil(read({ vd = { m = { v = "MAJOR", u = true } } }).vd, "u is false or absent")
		isNil(read({ vd = { m = { v = "MAJOR", l = 99999 } } }).vd)
		isNil(read({ vd = { m = { v = "MAJOR", l = 1.5 } } }).vd)
		isNil(read({ vd = { m = { v = "MAJOR", c = "lower" } } }).vd)
		isNil(read({ vd = { m = { v = "MAJOR" }, o = "x" } }).vd, "a damaged off-spec badge drops the pair")
		isNil(read({ eq = "item:1" }).eq)
		isNil(read({ eq = {} }).eq)
		isNil(read({ eq = { "|cffa335ee|Hitem:1::::::::70:::::|h[Hacked]|h|r" } }).eq, "no hyperlink markup")
		isNil(read({ eq = { "item:1", "item:2", "item:3", "item:4", "item:5" } }).eq, "at most four")
		isNil(read({ eq = { "item:" .. string.rep("1", 200) } }).eq, "too long")
		isNil(read({ eq = { 19100 } }).eq)
		isNil(read({ eq = { "spell:12" } }).eq)
	end)

	it("a response sent with the badges carries them; without a session it is refused first", function()
		local item, why = PS():Respond("MS", { vd = GOOD })
		isNil(item); eq(why, "NO_SESSION")
	end)
end)

describe("the master looter's session keeps the badges", function()
	local F = function() return FDCP.SessionFSM end
	before_boot(setup)

	local function session()
		local present = { [full("Aurel")] = true, [full("Bryn")] = true, [full("Corin")] = true }
		local rules = FDCP.Rules.DefaultConfig()
		rules.session.autoAdvance = false   -- the master looter opens each roll
		local s = assert(F().New({ id = "S1-1", season = "S1", ml = full("Aurel"), ts = 1, rules = rules, present = present, addon = present,
			band = { min = 200, max = 226 } }))
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

	it("the session keeps the season's band it was opened with", function()
		local s = session()
		deepEq(s.band, { min = 200, max = 226 })
		isNil(assert(F().New({ id = "x", season = "S1", ml = full("Aurel"), ts = 1, band = { min = 5, max = 1 } })).band)
	end)

	it("stores what a response says about the piece, for a pass too, and a later answer replaces it", function()
		local s, step = session()
		local vd = { m = { v = "MAJOR", l = 26 }, o = { v = "MINOR", l = 3 } }
		assert(step({ type = "RESPONSE", player = full("Bryn"), response = "MS", verdict = vd, equipped = { "item:19100" } }))
		assert(step({ type = "RESPONSE", player = full("Corin"), response = "PASS", verdict = vd }))
		local item = s.items[1]
		deepEq(item.verdicts[full("Bryn")], vd)
		deepEq(item.equipped[full("Bryn")], { "item:19100" })
		deepEq(item.verdicts[full("Corin")], vd, "a pass keeps the badge: the 'upgrade ignored' flag needs it")
		isNil(item.equipped[full("Corin")])
		assert(step({ type = "RESPONSE", player = full("Bryn"), response = "OS", verdict = { m = { v = "NONE" } } }))
		deepEq(item.verdicts[full("Bryn")], { m = { v = "NONE" } })
		isNil(item.equipped[full("Bryn")])
	end)

	it("an old input's label and note are ignored", function()
		local s, step = session()
		assert(step({ type = "RESPONSE", player = full("Bryn"), response = "MS", label = "BIS", note = "set", labelOrigin = "AUTO" }))
		eq(s.items[1].responses[full("Bryn")], "MS")
		isNil(s.items[1].labels); isNil(s.items[1].notes); isNil(s.items[1].labelOrigins)
	end)

	it("ignores a badge that is not a table and never lets it change the rules' view of the answer", function()
		local s, step = session()
		assert(step({ type = "RESPONSE", player = full("Bryn"), response = "MS", verdict = "MAJOR", equipped = "x" }))
		eq(s.items[1].responses[full("Bryn")], "MS")
		isNil(s.items[1].verdicts[full("Bryn")])
		isNil(s.items[1].equipped[full("Bryn")])
	end)

	it("hands them to the board: the badge of the spec of the answer, both badges and the worn pieces", function()
		local s, step = session()
		local vd = { m = { v = "MAJOR", l = 26 }, o = { v = "NONE", u = false, c = "ARMOR_TYPE" } }
		assert(step({ type = "RESPONSE", player = full("Bryn"), response = "MS", verdict = vd, equipped = { "item:19100" } }))
		assert(step({ type = "RESPONSE", player = full("Corin"), response = "OS", verdict = vd }))
		assert(step({ type = "RESPONSE", player = full("Aurel"), response = "OS", verdict = { m = { v = "MINOR" } } }))
		local board = FDCP.SessionBoard.Build({ host = true, session = s }, { now = 2 })
		local by = {}
		for _, c in ipairs(board.candidates) do by[c.player] = c end
		eq(by[full("Bryn")].upgrade.verdict, "MAJOR"); eq(by[full("Bryn")].upgrade.ilvlDelta, 26)
		eq(by[full("Bryn")].upgradeOS.usable, false)
		deepEq(by[full("Bryn")].equipped, { "item:19100" })
		isNil(by[full("Bryn")].label); isNil(by[full("Bryn")].note)
		eq(by[full("Corin")].upgrade.usable, false, "an off-spec answer reads the off-spec badge")
		eq(by[full("Aurel")].upgrade.verdict, "MINOR", "no off-spec badge: the main-spec one")
		isNil(by[full("Aurel")].upgradeOS)
		isNil(by[full("Aurel")].equipped)
	end)

	it("a candidate who sent nothing has no badge", function()
		local s, step = session()
		assert(step({ type = "RESPONSE", player = full("Bryn"), response = "MS" }))
		local board = FDCP.SessionBoard.Build({ host = true, session = s }, { now = 2 })
		for _, c in ipairs(board.candidates) do isNil(c.upgrade); isNil(c.equipped) end
	end)
end)
