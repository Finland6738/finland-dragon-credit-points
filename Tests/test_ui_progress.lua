-- The Progress tab (M3-8b): UI/Windows/Progress.lua over App/ProgressController.lua and Domain/Progress.lua.
local function Lg() return FDCP.Ledger end
local function Sn() return FDCP.Season end
local function M() return FDCP.Members end
local function NC() return FDCP.NightController end
local function PC() return FDCP.ProgressController end
local function PW() return FDCP.ProgressWindow end

local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }
local MC, ONY = 409, 249
local LUCIFRON, MAGMADAR, ONYXIA = 663, 664, 1084

local function guild(myRank)
	return function(Mock)
		Mock.guild.Set({ name = "Keepers", ranks = RANKS, myRank = myRank, members = {
			{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
		} })
	end
end

local function bound()
	local L = Lg().New()
	assert(Sn().Open(L, { author = "Aurel-TestRealm", ts = 1, season = "S1",
		instances = { { id = MC, size = 40 }, { id = ONY, size = 40 } } }))
	for i, n in ipairs({ "Aurel", "Bryn", "Corin" }) do
		assert(M().Join(L, { author = "Bryn-TestRealm", ts = 1 + i, season = "S1", member = n .. "-TestRealm", faction = "Horde" }))
	end
	NC():Bind(L)
	Mock.Advance(3)
	return L
end

local function open()
	Mock.Slash("/fdcp")
	FDCP.MainWindow:SelectTab("progress")
	PW():Refresh()
	return PW().root
end

describe("the Progress tab", function()
	before_boot(guild(1))

	it("one card per instance with the kills, the bars and the dates of the own guild", function()
		bound()
		assert(PC():Set(LUCIFRON, "2025-12-01"))
		assert(PC():Set(MAGMADAR, "2025-12-08"))
		local root = open()
		local mc, ony = root.cards.mc, root.cards.ony
		truthy(mc:IsShown()); truthy(ony:IsShown())
		eq(mc.name:GetText(), "Molten Core")
		eq(mc.eyebrow:GetText(), "RAID · 40 PLAYERS")
		eq(mc.bars[1].label:GetText(), "Nebulah")
		eq(mc.bars[1].count:GetText(), "2/10")
		eq(mc.bars[1].bar:GetFraction(), 0.2)
		eq(mc.bars[2].count:GetText(), "0/10", "the other guild: nothing entered")
		eq(ony.bars[1].count:GetText(), "0/1")
		eq(mc.rows[1].name:GetText(), "Lucifron")
		eq(mc.rows[1].index:GetText(), "01")
		eq(mc.rows[1].keys[1].date:GetText(), "01/12/25")
		eq(mc.rows[2].keys[1].date:GetText(), "08/12/25")
		eq(mc.rows[3].keys[1].date:GetText(), "")
		truthy(mc.rows[1].keys[1].killed); falsy(mc.rows[3].keys[1].killed)
		truthy(mc.rows[10]:IsShown(), "ten bosses, two columns")
		falsy(ony.rows[2] and ony.rows[2]:IsShown())
	end)

	it("the other guild's column shows only what an officer entered for it", function()
		bound()
		local other = PC():Build().keys[2]
		assert(PC():Set(LUCIFRON, "2025-12-03", other))
		local root = open()
		eq(root.cards.mc.bars[2].label:GetText(), other)
		eq(root.cards.mc.bars[2].count:GetText(), "1/10")
		eq(root.cards.mc.rows[1].keys[2].date:GetText(), "03/12/25")
		eq(root.cards.mc.rows[1].keys[1].date:GetText(), "")
	end)

	it("uses the journal's cover and name when the client has them, a generated cover otherwise", function()
		bound()
		local root = open()
		falsy(root.cards.mc.hasCover)
		truthy(root.cards.mc.glow:IsShown())
		Mock.journal.instances[741] = { name = "Nucleo Fuso", mapID = MC, button = "Interface\Foo\mc" }
		PW():Refresh()
		truthy(root.cards.mc.hasCover)
		falsy(root.cards.mc.glow:IsShown())
		eq(root.cards.mc.cover:GetTexture(), "Interface\Foo\mc")
		eq(root.cards.mc.name:GetText(), "Nucleo Fuso")
		eq(root.cards.ony.name:GetText(), "Onyxia\226\128\153s Lair", "no journal entry: the table's name")
	end)

	it("an officer enters, corrects and removes a date from the boss row", function()
		local L = bound()
		local root = open()
		truthy(PW():CanEdit())
		eq(root.hint:GetText(), "Click a boss to enter or correct a first kill.")
		root.cards.mc.rows[1]:GetScript("OnClick")(root.cards.mc.rows[1])
		local d = PW().dialog
		truthy(d:IsShown())
		eq(d.title:GetText(), "First kill: Lucifron")
		Mock.TypeInto(d.edit, "2026-02-30x")
		local ev, why = PW():Save()
		isNil(ev); eq(why, "date")
		eq(d.status:GetText(), "The date must be written YYYY-MM-DD.")
		Mock.TypeInto(d.edit, "2099-01-01")
		eq(select(2, PW():Save()), "FUTURE")
		Mock.TypeInto(d.edit, "2026-01-01")
		truthy(PW():Save())
		falsy(d:IsShown())
		eq(root.cards.mc.rows[1].keys[1].date:GetText(), "01/01/26")
		eq(root.cards.mc.bars[1].count:GetText(), "1/10")
		-- correct
		root.cards.mc.rows[1]:GetScript("OnClick")(root.cards.mc.rows[1])
		eq(d.edit:GetText(), "2026-01-01", "starts with the current date")
		eq(select(2, PW():Save()), "UNCHANGED")
		Mock.TypeInto(d.edit, "2025-12-30")
		truthy(PW():Save())
		eq(root.cards.mc.rows[1].keys[1].date:GetText(), "30/12/25")
		-- remove
		root.cards.mc.rows[1]:GetScript("OnClick")(root.cards.mc.rows[1])
		truthy(PW():Remove())
		eq(root.cards.mc.rows[1].keys[1].date:GetText(), "")
		root.cards.mc.rows[1]:GetScript("OnClick")(root.cards.mc.rows[1])
		eq(select(2, PW():Remove()), "NOTHING_TO_CLEAR")
		eq(PW().ErrorText("NOTHING_TO_CLEAR"), "No date was entered by hand for this boss.")
		truthy(L)
	end)

	it("a date entered for the other guild goes under its key", function()
		bound()
		local root = open()
		local other = root.data.keys[2]
		root.cards.mc.rows[2]:GetScript("OnClick")(root.cards.mc.rows[2])
		local d = PW().dialog
		PW():PickKey(other)
		Mock.TypeInto(d.edit, "2025-12-05")
		truthy(PW():Save())
		eq(root.cards.mc.rows[2].keys[2].date:GetText(), "05/12/25")
		eq(root.cards.mc.rows[2].keys[1].date:GetText(), "")
	end)

	it("the Onyxia card and the wheel scroll", function()
		bound()
		assert(PC():Set(ONYXIA, "2025-12-09"))
		local root = open()
		eq(root.cards.ony.bars[1].count:GetText(), "1/1")
		eq(root.cards.ony.rows[1].name:GetText(), "Onyxia")
		PW():Scroll(100000)
		truthy(root.offset >= 0)
		PW():Scroll(-100000)
		eq(root.offset, 0)
	end)
end)

describe("the Progress tab for a member", function()
	before_boot(guild(3))

	it("shows the dates but cannot edit", function()
		bound()
		local root = open()
		falsy(PW():CanEdit())
		eq(root.hint:GetText(), "Dates are entered by the officers of each guild.")
		root.cards.mc.rows[1]:GetScript("OnClick")(root.cards.mc.rows[1])
		falsy(PW().dialog and PW().dialog:IsShown())
		falsy(PW():OpenEditor(root.cards.mc.rows[1].boss))
		local ev, why = PC():Set(LUCIFRON, "2026-01-01")
		isNil(ev); eq(why, "RANK_TOO_LOW")
	end)

end)

describe("the Progress tab without a guild", function()
	before_boot(function() end)

	it("before the guild data is loaded it says so", function()
		local root = open()
		eq(root.empty:GetText(), "The guild data is not loaded yet.")
	end)
end)
