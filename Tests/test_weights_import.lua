-- Personal stat weights and the best-in-slot wishlist (M5-3): the Pawn-like import string (valid and invalid), the weights
-- per spec feeding the upgrade advisor, the wishlist in the character's own saved data (it survives /reload) and its
-- reminder in the player's popup (docs/ANALISI.md §5.1 points 3 and 5, §13 question 8).
local function WI() return FDCP.WeightImport end
local function WL() return FDCP.Wishlist end
local function PU() return FDCP.PersonalUpgrade end
local function Codec() return FDCP.Codec end
local function P() return FDCP.MemberLootPopup end
local function L(key) return FDCP.L[key] end

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end
local ML = full("Aurel")

local function parse(text)
	local r, code, detail = WI().Parse(text)
	return r, code, detail
end

---------------------------------------------------------------------------------------------------------------------
-- The string

describe("the weight string", function()
	it("reads the Pawn-like format with its version and name", function()
		local r = parse('( Pawn: v1: "Fury raid": Strength=1, CritRating=0.85, HasteRating=0.6, Stamina=0.1 )')
		deepEq(r.weights, { STR = 1, CRIT = 0.85, HASTE = 0.6, STA = 0.1 })
		eq(r.name, "Fury raid")
		deepEq(r.ignored, {})
	end)

	it("reads the bare form, the short codes, any case and the other spellings", function()
		deepEq(parse("Strength=1, agility=0.5"). weights, { STR = 1, AGI = 0.5 })
		deepEq(parse("STR=2,CRIT=1.5"). weights, { STR = 2, CRIT = 1.5 })
		deepEq(parse("ATTACKPOWER=0.5, SpellPower=1, ArmorPen=.4, Mp5=-1"). weights, { AP = 0.5, SP = 1, ARPEN = 0.4, MP5 = -1 })
		deepEq(parse("  Strength = 1 ,\n Stamina=0.2  "). weights, { STR = 1, STA = 0.2 })
	end)

	it("lists the stats it does not know and skips the class and spec fields", function()
		local r = parse('( Pawn: v1: "x": Class=Warrior, Spec=Fury, Strength=1, MetaSocketEffect=10, Zeta=2 )')
		deepEq(r.weights, { STR = 1 })
		deepEq(r.ignored, { "MetaSocketEffect", "Zeta" })
	end)

	it("the last value of a repeated stat wins", function()
		eq(parse("Strength=1, Strength=3").weights.STR, 3)
	end)

	it("refuses what is not a weight string, with a code and the piece at fault", function()
		local cases = {
			{ "", "EMPTY" }, { "   ", "EMPTY" }, { 42, "EMPTY" }, { nil, "EMPTY" },
			{ "Strength", "BAD_FORMAT" }, { "Strength 1, Agility 2", "BAD_FORMAT" }, { "=1", "BAD_FORMAT" },
			{ '( Pawn: v1: "x": Strength=1', "BAD_FORMAT" }, { '( Strength=1 )', "BAD_FORMAT" },
			{ '( Pawn: v1: x: Strength=1 )', "BAD_FORMAT" },
			{ "Strength=abc", "BAD_VALUE" }, { "Strength=0x10", "BAD_VALUE" }, { "Strength=1e3", "BAD_VALUE" },
			{ "Strength=", "BAD_VALUE" }, { "Strength=1.5.2", "BAD_VALUE" }, { "Strength=1001", "BAD_VALUE" },
			{ "Strength=1, Zeta=oops", "BAD_VALUE" }, { "Strength=inf", "BAD_VALUE" }, { "Strength=nan", "BAD_VALUE" },
			{ "Zeta=1", "NO_STATS" }, { "( Pawn: v1: \"x\": Class=Mage )", "NO_STATS" },
			{ ("Strength=1,"):rep(300), "TOO_LONG" },
		}
		for _, c in ipairs(cases) do
			local r, code = parse(c[1])
			isNil(r, tostring(c[1]))
			eq(code, c[2], tostring(c[1]))
		end
		local _, _, detail = parse("Strength=1, Agility 2")
		eq(detail, "Agility 2")
		_, _, detail = parse("Strength=abc")
		eq(detail, "Strength")
	end)

	it("writes the string again in a fixed order, and reads what it wrote", function()
		local w = { CRIT = 0.85, STR = 1, STA = 0.1, HASTE = 0.6, JUNK = 5 }
		local text = WI().Format(w, 'Fury "raid"')
		eq(text, '( Pawn: v1: "Fury raid": Strength=1, Stamina=0.1, CritRating=0.85, HasteRating=0.6 )')
		local r = parse(text)
		deepEq(r.weights, { STR = 1, STA = 0.1, CRIT = 0.85, HASTE = 0.6 })
		eq(r.name, "Fury raid")
	end)

	it("cleans a saved row", function()
		deepEq(WI().Sanitize({ STR = 1, JUNK = 2, CRIT = "x", HIT = 0 / 0, AGI = 5000 }), { STR = 1 })
		isNil(WI().Sanitize({ JUNK = 1 }))
		isNil(WI().Sanitize("x"))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The wishlist (domain)

describe("the wishlist", function()
	it("finds the items in links, ids and mixed text, once each", function()
		local text = "|cffa335ee|Hitem:19101::::::::70:::::|h[Helm of Embers]|h|r 19102 item:19103 19102 abc 0 x12"
		deepEq(WL().ItemIDs(text), { 19101, 19103, 19102 })
		deepEq(WL().ItemIDs(""), {})
		deepEq(WL().ItemIDs(nil), {})
	end)

	it("adds, removes, lists in order and refuses a bad id or a full list", function()
		local list = {}
		truthy(WL().Add(list, 5)); truthy(WL().Add(list, 3)); truthy(WL().Add(list, 5))
		eq(WL().Count(list), 2)
		deepEq(WL().List(list), { 3, 5 })
		local ok, why = WL().Add(list, 0); falsy(ok); eq(why, "BAD_ITEM")
		ok, why = WL().Add(list, 1.5); falsy(ok); eq(why, "BAD_ITEM")
		ok, why = WL().Add(list, "7"); falsy(ok); eq(why, "BAD_ITEM")
		truthy(WL().Remove(list, 3)); falsy(WL().Remove(list, 3))
		truthy(WL().Has(list, 5)); falsy(WL().Has(list, 3))
		for i = 1, WL().MAX do list[1000 + i] = true end
		ok, why = WL().Add(list, 9); falsy(ok); eq(why, "FULL")
		WL().Clear(list)
		eq(WL().Count(list), 0)
	end)

	it("cleans a saved list", function()
		deepEq(WL().Sanitize({ [5] = true, [6] = "yes", [-1] = true, [2.5] = true, x = true }), { [5] = true })
		deepEq(WL().Sanitize("x"), {})
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The commands, the saved data and the advisor

local STR, STA = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT"
local function hlink(id, name) return "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[" .. name .. "]|h|r" end
local ITEMS = {
	{ id = 19100, link = hlink(19100, "Old Helm"), name = "Old Helm", quality = 4, equipLoc = "INVTYPE_HEAD", classID = 4,
		subclassID = 4, type = "Armor", subType = "Plate", level = 64, stats = { [STR] = 90, [STA] = 40 } },
	{ id = 19101, link = hlink(19101, "Helm of Embers"), name = "Helm of Embers", quality = 4, equipLoc = "INVTYPE_HEAD",
		classID = 4, subclassID = 4, type = "Armor", subType = "Plate", level = 70, stats = { [STR] = 100, [STA] = 50 } },
}

local function plain() return table.concat(Mock.PlainOutput(), "\n") end

describe("the commands, the advisor and the popup", function()
	before_boot(function(M)
		M.player.name, M.player.realm = "Bryn", REALM
		for _, def in ipairs(ITEMS) do M.items.Add(def) end
		M.items.equipped = { [1] = hlink(19100, "Old Helm") }
		_G.INVTYPE_HEAD = "Head"
	end)

	local function declare(ms1, ms2)
		local Lg, Sn, R = FDCP.Ledger, FDCP.Season, FDCP.Roster
		Mock.guild.Set({ name = "Keepers", ranks = { [0] = "Guild Master", "Officer" }, myRank = 1, members = {
			{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 } } })
		local L1 = Lg.New()
		assert(Sn.Open(L1, { author = ML, ts = 1, season = "S1", instances = { { id = 409, size = 40 } } }))
		assert(R.Join(L1, { author = ML, ts = 2, season = "S1", member = full("Bryn"), faction = "Horde", ms1 = ms1, ms2 = ms2 }))
		FDCP.NightController:Bind(L1)
		FDCP.UpgradeAdvisor.Reset()
	end

	local function advice(id) return (FDCP.UpgradeAdvisor.For(id)) end

	it("an import sets the weights for the spec, turns them on, and the advisor uses them", function()
		declare(72, 73)
		local before = advice(19101)
		eq(before.ms.verdict, "BIG")
		falsy(before.personal.ms)
		Mock.ClearOutput()
		Mock.Slash("/fdcp weights import 72 ( Pawn: v1: \"Mine\": Stamina=1 )")
		contains(plain(), "Weights imported for Fury (72): 1 stats")
		truthy(PU().Enabled())
		local after = advice(19101)
		-- only stamina counts now: 50 against 40 is +25%; the off-spec (73) still has the default weights
		eq(after.ms.pct, 0.25)
		truthy(after.personal.ms)
		falsy(after.personal.os)
		eq(after.os.pct, before.os.pct)
		eq(FDCP.UpgradeAdvisor.Text(after.ms), "Big upgrade +25.0% · ilvl +6")
	end)

	it("'ms' and 'os' name the declared specs", function()
		declare(72, 73)
		Mock.Slash("/fdcp weights import ms Strength=1")
		Mock.Slash("/fdcp weights import os Stamina=1")
		deepEq(PU().Specs(), { 72, 73 })
		deepEq(PU().Row(72), { STR = 1 })
		deepEq(PU().Row(73), { STA = 1 })
		truthy(advice(19101).personal.os)
	end)

	it("an invalid string is refused with a message and changes nothing", function()
		declare(72)
		Mock.ClearOutput()
		Mock.Slash("/fdcp weights import 72 Strength=abc")
		contains(plain(), "Import refused: this stat has no usable number (Strength)")
		Mock.Slash("/fdcp weights import 72 hello")
		contains(plain(), "this is not a weight string")
		Mock.Slash("/fdcp weights import 72 Zeta=1")
		contains(plain(), "no stat the addon knows")
		Mock.Slash("/fdcp weights import 72")
		contains(plain(), "the string is empty")
		Mock.Slash("/fdcp weights import 9999 Strength=1")
		contains(plain(), 'Unknown spec: "9999"')
		Mock.Slash("/fdcp weights import nope Strength=1")
		contains(plain(), 'Unknown spec: "nope"')
		falsy(PU().Enabled())
		deepEq(PU().Specs(), {})
		falsy(advice(19101).personal.ms)
	end)

	it("lists what was ignored in a string", function()
		declare(72)
		Mock.ClearOutput()
		Mock.Slash("/fdcp weights import 72 Strength=1, Zeta=2")
		contains(plain(), "Not recognised and ignored: Zeta")
	end)

	it("off keeps the rows and goes back to the default weights; on brings them back; reset removes them", function()
		declare(72)
		Mock.Slash("/fdcp weights import 72 Stamina=1")
		eq(advice(19101).ms.pct, 0.25)
		Mock.Slash("/fdcp weights off")
		falsy(PU().Enabled())
		falsy(advice(19101).personal.ms)
		truthy(advice(19101).ms.pct ~= 0.25)
		deepEq(PU().Specs(), { 72 })
		Mock.Slash("/fdcp weights on")
		eq(advice(19101).ms.pct, 0.25)
		Mock.ClearOutput()
		Mock.Slash("/fdcp weights reset 72")
		contains(plain(), "Personal weights removed for Fury (72)")
		deepEq(PU().Specs(), {})
		falsy(advice(19101).personal.ms)
		Mock.ClearOutput()
		Mock.Slash("/fdcp weights reset 72")
		contains(plain(), "You have no personal weights for Fury (72)")
	end)

	it("show prints the personal string, or the default one when there is none", function()
		declare(72)
		Mock.ClearOutput()
		Mock.Slash("/fdcp weights show 72")
		contains(plain(), "Weights of Fury (72) (default): ( Pawn: v1: \"Fury (72)\": Strength=1")
		Mock.Slash("/fdcp weights import 72 Strength=2, CritRating=1")
		Mock.ClearOutput()
		Mock.Slash("/fdcp weights show 72")
		contains(plain(), "(personal): ( Pawn: v1: \"Fury (72)\": Strength=2, CritRating=1 )")
	end)

	it("with no argument it says the state and the usage", function()
		declare(72)
		Mock.ClearOutput()
		Mock.Slash("/fdcp weights")
		contains(plain(), "Personal weights: off")
		contains(plain(), "You have no personal weights")
		contains(plain(), "Usage: /fdcp weights")
	end)

	it("speaks Italian", function()
		FDCP.Locale.SetActive("itIT")
		declare(72)
		Mock.ClearOutput()
		Mock.Slash("/fdcp weights import 72 Strength=abc")
		contains(plain(), "Import rifiutato: questa statistica non ha un numero valido (Strength)")
		Mock.Slash("/fdcp wish")
		contains(plain(), "La tua lista best-in-slot è vuota.")
	end)

	it("the personal weights and the wishlist survive /reload", function()
		declare(72)
		Mock.Slash("/fdcp weights import 72 Stamina=1")
		Mock.Slash("/fdcp wish add 19101 item:19100")
		Mock.Reload()
		truthy(FDCP.PersonalUpgrade.Enabled())
		deepEq(FDCP.PersonalUpgrade.Row(72), { STA = 1 })
		truthy(FDCP.PersonalUpgrade.Has(19101))
		deepEq(FDCP.PersonalUpgrade.WishList(), { 19100, 19101 })
		truthy(FDCP.Config.char.upgrade, "kept in the character's own data")
		isNil(FDCP.Config.db.global.upgrade, "never in the shared data")
	end)

	it("a damaged saved table is cleaned, not trusted", function()
		FDCP.Config.char.upgrade = { personal = "yes", weights = { [72] = { STR = "x", CRIT = 1 }, junk = { STR = 1 }, [73] = "no" },
			wish = { [5] = true, bad = true, [6] = 7 } }
		falsy(PU().Enabled())
		deepEq(PU().Specs(), { 72 })
		deepEq(PU().Row(72), { CRIT = 1 })
		deepEq(PU().WishList(), { 5 })
	end)

	it("the wishlist adds and removes by link or id, lists, clears, and says so", function()
		Mock.ClearOutput()
		Mock.Slash("/fdcp wish add " .. hlink(19101, "Helm of Embers") .. " 19100")
		contains(plain(), "On your best-in-slot list: ")
		deepEq(PU().WishList(), { 19100, 19101 })
		Mock.ClearOutput()
		Mock.Slash("/fdcp wish list")
		contains(plain(), "Your best-in-slot list (2):")
		contains(plain(), "Helm of Embers")
		Mock.ClearOutput()
		Mock.Slash("/fdcp wish remove 19100")
		contains(plain(), "Removed from your best-in-slot list")
		Mock.ClearOutput()
		Mock.Slash("/fdcp wish remove 19100")
		contains(plain(), "Not on your best-in-slot list")
		Mock.ClearOutput()
		Mock.Slash("/fdcp wish add nothing")
		contains(plain(), "Usage: /fdcp wish")
		Mock.ClearOutput()
		Mock.Slash("/fdcp wish clear")
		contains(plain(), "Your best-in-slot list is empty now.")
		deepEq(PU().WishList(), {})
		Mock.ClearOutput()
		Mock.Slash("/fdcp wish")
		contains(plain(), "Your best-in-slot list is empty.")
	end)

	it("the commands are in the help", function()
		Mock.ClearOutput()
		Mock.Slash("/fdcp help")
		contains(plain(), "/fdcp weights - ")
		contains(plain(), "/fdcp wish - ")
	end)

	-- the popup
	local function receive(t, fields) return Mock.chat.Receive("FDCP1", Codec():Encode(t, fields), "RAID", ML) end
	local function open(itemID)
		Mock.group.Set{ raid = true, members = { { name = "Aurel" }, { name = "Corin" } } }
		Mock.Advance(3)
		receive("SOPEN", { s = "S1-1", q = 1, ml = ML, e = 663, rt = { MS = 1, OS = 2 },
			it = { { id = itemID, ca = "armor", cs = { MS = 1, OS = 0 } } } })
		receive("SROLL", { s = "S1-1", q = 2, i = 1, r = 1, k = "ROLL", g = "TIER", tr = 1, cl = true,
			de = FDCP.Compat.ServerTime() + 30 })
	end
	local function card() return P().cards[1] end

	it("the popup reminds the player of an item on the wishlist, and only of those", function()
		Mock.Slash("/fdcp wish add 19101")
		open(19101)
		truthy(card().data.wish)
		truthy(card().wish:IsShown())
		eq(card().wish.label:GetText(), "ON YOUR BIS LIST")
		Mock.RunScript(card().wish, "OnEnter")
		truthy(GameTooltip:IsShown())
		contains(GameTooltip._lines[1], "Only you see this")
		Mock.RunScript(card().wish, "OnLeave")
		falsy(GameTooltip:IsShown())
	end)

	it("no reminder for an item that is not on the list, and it follows the list while the popup is open", function()
		open(19101)
		falsy(card().data.wish)
		falsy(card().wish:IsShown())
		Mock.Slash("/fdcp wish add 19101")
		truthy(card().wish:IsShown())
		Mock.Slash("/fdcp wish remove 19101")
		falsy(card().wish:IsShown())
	end)

	it("the badge takes a row of its own above the verdicts", function()
		open(19101)
		local plainY = select(5, card().verdicts.ms:GetPoint(1))
		Mock.Slash("/fdcp wish add 19101")
		local wishY = select(5, card().wish:GetPoint(1))
		local msY = select(5, card().verdicts.ms:GetPoint(1))
		eq(wishY, plainY)
		truthy(msY < wishY)
	end)

	it("the verdict line in the popup follows the personal weights and its tooltip says so", function()
		declare(72)
		open(19101)
		falsy(card().data.upgrade.personal.ms)
		Mock.Slash("/fdcp weights import 72 Stamina=1")
		eq(card().verdicts.ms.label:GetText(), "Main-spec · Big upgrade +25.0% · ilvl +6")
		Mock.RunScript(card().verdicts.ms, "OnEnter")
		local found
		for _, line in ipairs(GameTooltip._lines) do if line == L("UPG_BASIS_PERSONAL") then found = true end end
		truthy(found)
	end)

	it("the verdict the master looter gets is the one made with the personal weights", function()
		declare(72)
		Mock.Slash("/fdcp weights import 72 Stamina=1")
		open(19101)
		card().data.seg.buttons.MS:Click()
		Mock.Advance(2)
		local sent
		for _, e in ipairs(Mock.chat.SentWithPrefix("FDCP1")) do
			local text = e.message
			if text:byte(1) == 4 then text = text:sub(2) end
			local m = Codec():Decode(text)
			if m and m.t == "SRESP" then sent = m end
		end
		truthy(sent)
		eq(sent.vd.m.p, 250)
	end)
end)
