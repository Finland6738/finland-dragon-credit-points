-- The council window (M5-8): UI/Windows/Council.lua, the Loot > Council sub-tab, drawn from App/CouncilService.lua,
-- App/LegendaryService.lua and the session board, on the mock client. Part one is one Guild Master client with a season:
-- the sub-tab, cancelling an award and adjusting credits with their mandatory reason, the audit and the legendary
-- projects (open, complete, abandon, the refusals in plain words). Part two is a raid of five on the network simulator: the
-- council's page on the master looter's client and on a council member's read-only view, the votes and the shortcuts to
-- the Session tab's dialogs (docs/ANALISI.md §3.6, §3.7, §9.3, docs/specs/ui-style.md §6).
local function Lg() return FDCP.Ledger end
local function SC() return FDCP.SessionController end
local function CW() return FDCP.CouncilWindow end
local function MW() return FDCP.MainWindow end
local function ML() return FDCP.MLSession end
local function CS() return FDCP.CouncilService end
local function SBd() return FDCP.SessionBoard end
local function L(key) return FDCP.L[key] end

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end
local ME = full("Dara")
local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }

local function link(id) return "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[Item " .. id .. "]|h|r" end
local ITEMS = {
	{ id = 19003, name = "Ring of the Keeper", equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0 },
	{ id = 19101, name = "Sulfuras", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 5 },
	{ id = 19102, name = "Eye of Sulfuras", equipLoc = "", classID = 12, subclassID = 0 },
	{ id = 19103, name = "Hand of Sulfuras", equipLoc = "", classID = 12, subclassID = 0 },
}

local function setup(rank)
	return function(M)
		M.player.name, M.player.realm = "Dara", REALM
		for _, def in ipairs(ITEMS) do
			M.items.Add{ id = def.id, link = link(def.id), name = def.name, quality = 4, equipLoc = def.equipLoc,
				classID = def.classID, subclassID = def.subclassID }
		end
		M.guild.Set({ name = "Keepers", ranks = RANKS, myRank = rank, members = {
			{ name = "Aurel", rank = 1 }, { name = "Bryn", rank = 3 }, { name = "Corin", rank = 3 } } })
	end
end

-- A ledger with season S1 and the pool Aurel, Bryn, Corin, Dara; the controller is bound to it.
local function bench()
	local b = { L = Lg().New() }
	assert(FDCP.Season.Open(b.L, { author = ME, ts = 1, season = "S1", instances = { { id = 409, size = 40 } } }))
	for i, n in ipairs({ "Aurel", "Bryn", "Corin", "Dara" }) do
		assert(FDCP.Members.Join(b.L, { author = ME, ts = 1 + i, season = "S1", member = full(n), faction = "Horde" }))
	end
	SC():Bind(b.L, {})
	Mock.Advance(3)
	function b.award(member, cost, ts, item)
		return assert(Lg().Append(b.L, { author = ME, ts = ts or 10, season = "S1", type = "ITEM_AWARDED", payload = {
			target = "member", member = full(member), item = item or 19003, cost = cost, reasons = { "ONLY_CANDIDATE" }, flags = {} } }))
	end
	function b.credits(member) return Lg().Credits(b.L, "S1")[full(member)] or 0 end
	function b.count(kind)
		return #Lg().Sorted(b.L, function(e) return e.type == kind end)
	end
	return b
end

local function open(view)
	MW():Open("loot")
	ML().root.sub:Select("council")
	if view then CW():SelectView(view) end
	CW():Refresh()
	return CW()
end

local function click(button) button:Click() end
local function dlg() return CW().dlg end

describe("the sub-tab", function()
	before_boot(setup(0))

	it("is the Council sub-tab of Loot, next to Session and To deliver", function()
		bench()
		open()
		truthy(CW().root, "built with the window")
		eq(MW():ActiveTab(), "loot")
		eq(ML().root.sub:Active(), "council")
		truthy(CW().pane:IsShown())
		falsy(ML().ui.pane:IsShown())
		ML().root.sub:Select("session")
		truthy(ML().ui.pane:IsShown())
		falsy(CW().pane:IsShown())
	end)

	it("says who is on the council and how an award is decided", function()
		bench()
		open()
		local text = CW().root.status:GetText()
		contains(text, L("COUNCIL_STATE_MEMBER"))
		contains(text, L("COUNCIL_STATE_RANK"))
		contains(text, L("COUNCIL_AWARD_MODE"):format(L("COUNCIL_AWARD_MODE_CONFIRM")))
	end)

	it("with no session in view it says so and offers neither a vote nor the master looter's shortcuts", function()
		bench()
		open()
		local c = CW().card
		eq(c.item:GetText(), L("COUNCIL_NO_SESSION"))
		falsy(c.vote:IsEnabled()); falsy(c.modify:IsEnabled()); falsy(c.correct:IsEnabled())
		falsy(c.glow:IsShown(), "no neon without an open vote")
	end)

	it("reads in Italian too", function()
		FDCP.Locale.SetActive("itIT")
		bench()
		open()
		contains(CW().root.status:GetText(), L("COUNCIL_STATE_MEMBER"))
		eq(CW().root.title:GetText(), "Council")
		eq(CW().card.item:GetText(), L("COUNCIL_NO_SESSION"))
		contains(CW().card.item:GetText(), "Nessuna sessione")
	end)
end)

describe("cancelling an award", function()
	before_boot(setup(0))

	it("lists the awards of the season, newest first, with the winner and the credits", function()
		local b = bench()
		b.award("Bryn", 1, 10)
		b.award("Corin", 2, 20)
		open("awards")
		local rows = CW().awards.table:VisibleRows()
		eq(#rows, 2)
		eq(rows[1].cells[1]:GetText(), "Ring of the Keeper")
		eq(rows[1].cells[2]:GetText(), "Corin")
		eq(rows[1].cells[3]:GetText(), "2")
		eq(rows[2].cells[2]:GetText(), "Bryn")
		truthy(CW().awards.void:IsEnabled())
	end)

	it("says so when there is nothing to cancel, and the button waits", function()
		bench()
		open("awards")
		eq(#CW().awards.table:VisibleRows(), 0)
		truthy(CW().awards.table.empty:IsShown())
		eq(CW().awards.table.empty:GetText(), L("COUNCIL_AWARDS_EMPTY"))
		falsy(CW().awards.void:IsEnabled())
		falsy(CW():OpenDialog("void"))
	end)

	it("cannot be saved without a reason; with one the credits come back and the award stays in the log", function()
		local b = bench()
		local a = b.award("Bryn", 1, 10)
		eq(b.credits("Bryn"), 1)
		open("awards")
		click(CW().awards.void)
		truthy(CW():DialogOpen())
		contains(dlg().hint:GetText(), "Ring of the Keeper")
		contains(dlg().hint:GetText(), "Bryn")
		local ok, code = CW():DialogSave()
		falsy(ok); eq(code, "REASON_REQUIRED")
		eq(dlg().error:GetText(), SBd().ErrorText("REASON_REQUIRED"))
		eq(b.count("AWARD_VOIDED"), 0, "nothing was written")
		truthy(dlg().reasons:Select("DUPLICATE_AWARD"))
		eq(dlg().reasons:Count(), #FDCP.Council.VOID_ORDER, "only the reasons a void may give")
		ok = CW():DialogSave()
		truthy(ok)
		falsy(CW():DialogOpen())
		eq(b.count("AWARD_VOIDED"), 1)
		eq(b.credits("Bryn"), 0, "the credits come back")
		truthy(Lg().Get(b.L, a.id), "the award stays in the ledger")
		eq(CW().root.message:GetText(), L("COUNCIL_VOIDED"):format("Ring of the Keeper", "Bryn"))
		eq(#CW().awards.table:VisibleRows(), 0, "it cannot be cancelled twice")
	end)

	it("Cancel leaves the ledger alone", function()
		local b = bench()
		b.award("Bryn", 1, 10)
		open("awards")
		click(CW().awards.void)
		click(dlg().cancel)
		falsy(CW():DialogOpen())
		eq(b.count("AWARD_VOIDED"), 0)
	end)

	it("the selected row is the one that is cancelled", function()
		local b = bench()
		b.award("Bryn", 1, 10)
		b.award("Corin", 2, 20)
		open("awards")
		local rows = CW().awards.table:VisibleRows()
		click(rows[2])   -- Bryn's, the older one
		click(CW().awards.void)
		dlg().reasons:Select("MISTAKE")
		truthy(CW():DialogSave())
		eq(b.credits("Bryn"), 0)
		eq(b.credits("Corin"), 2)
	end)
end)

describe("the officer outside a night", function()
	before_boot(setup(1))

	it("is refused by the permission gate, in the rank's words, and nothing is written", function()
		local b = bench()
		b.award("Bryn", 1, 10)
		open("awards")
		click(CW().awards.void)
		dlg().reasons:Select("MISTAKE")
		local ok, code = CW():DialogSave()
		falsy(ok); eq(code, "RANK_TOO_LOW")
		eq(dlg().error:GetText(), SBd().ErrorText("RANK_TOO_LOW"))
		truthy(CW():DialogOpen(), "the dialog stays open")
		eq(b.count("AWARD_VOIDED"), 0)
		eq(b.credits("Bryn"), 1)
	end)
end)

describe("adjusting credits by hand", function()
	before_boot(setup(0))

	it("names a member of the pool, a number and a reason; every miss is said in the dialog", function()
		local b = bench()
		open("awards")
		click(CW().root.adjust)
		truthy(CW():DialogOpen())
		eq(dlg().list:Count(), 4, "the season's pool")
		local ok, code = CW():DialogSave()
		falsy(ok); eq(code, "NOT_MEMBER")
		truthy(dlg().list:Select(full("Corin")))
		dlg().a:SetText("two")
		ok, code = CW():DialogSave()
		falsy(ok); eq(code, "BAD_DELTA")
		eq(dlg().error:GetText(), SBd().ErrorText("BAD_DELTA"))
		dlg().a:SetText("2")
		ok, code = CW():DialogSave()
		falsy(ok); eq(code, "REASON_REQUIRED")
		eq(b.count("CREDITS_ADJUSTED"), 0, "nothing was written")
		dlg().reasons:Select("PENALTY")
		eq(dlg().reasons:Count(), #FDCP.Council.ADJUST_ORDER)
		dlg().a:SetText("0")
		ok, code = CW():DialogSave()
		falsy(ok); eq(code, "BAD_DELTA", "an adjustment of nothing")
		dlg().a:SetText("1001")
		ok, code = CW():DialogSave()
		falsy(ok); eq(code, "BAD_DELTA", "more than the largest one")
		dlg().a:SetText("2,5")
		truthy(CW():DialogSave())
		falsy(CW():DialogOpen())
		eq(b.count("CREDITS_ADJUSTED"), 1)
		eq(b.credits("Corin"), 2.5)
		eq(CW().root.message:GetText(), L("COUNCIL_ADJUSTED"):format("Corin", "2.50", FDCP.Reasons.Text("CORRECTION", "PENALTY")))
	end)

	it("takes credits away with a minus sign, written plain or as the typographic one", function()
		local b = bench()
		open("awards")
		for _, text in ipairs({ "-1", "\226\136\146" .. "1" }) do
			click(CW().root.adjust)
			dlg().list:Select(full("Bryn"))
			dlg().a:SetText(text)
			dlg().reasons:Select("MISTAKE")
			truthy(CW():DialogSave())
		end
		eq(b.credits("Bryn"), -2)
		eq(CW().ParseDelta("+3"), 3)
		isNil(CW().ParseDelta(""))
	end)
end)

describe("the audit", function()
	before_boot(setup(0))

	it("says so when nothing was done", function()
		bench()
		open("audit")
		eq(#CW().audit.table:VisibleRows(), 0)
		eq(CW().audit.table.empty:GetText(), L("COUNCIL_AUDIT_EMPTY"))
	end)

	it("lists every intervention of the season, newest first, with its reason", function()
		local b = bench()
		b.award("Bryn", 1, 10)
		open("awards")
		click(CW().root.adjust)
		dlg().list:Select(full("Corin")); dlg().a:SetText("1"); dlg().reasons:Select("BONUS")
		truthy(CW():DialogSave())
		click(CW().awards.void)
		dlg().reasons:Select("MISTAKE")
		truthy(CW():DialogSave())
		CW():SelectView("audit")
		local list = CS():Audit()
		eq(#list, 2)
		local rows = CW().audit.table:VisibleRows()
		eq(#rows, 2)
		for i, row in ipairs(rows) do eq(row.cells[1]:GetText(), CS().AuditLine(list[#list - i + 1])) end
		local all = rows[1].cells[1]:GetText() .. " " .. rows[2].cells[1]:GetText()
		contains(all, FDCP.Reasons.Text("CORRECTION", "BONUS"))
		contains(all, FDCP.Reasons.Text("CORRECTION", "MISTAKE"))
		contains(all, "Corin")
	end)
end)

describe("legendary projects", function()
	before_boot(function(M)
		setup(0)(M)
		_G.ChatEdit_InsertLink = function() return false end   -- the game's own function, which the window only listens to
	end)

	local function openDialog()
		click(CW().legendary.open)
		truthy(CW():DialogOpen())
		return dlg()
	end

	local function fill(d, fields)
		d.a:SetText(fields.name or "Sulfuras")
		d.b:SetText(fields.final == nil and link(19101) or fields.final)
		d.c:SetText(fields.pieces == nil and (link(19102) .. " " .. link(19103)) or fields.pieces)
		d.d:SetText(fields.queue or "")
		if fields.builder then d.list:Select(full(fields.builder)) end
	end

	it("shows the mode and says so when there is no project", function()
		bench()
		open("legendary")
		contains(CW().legendary.mode:GetText(), L("LEGENDARY_MODE_COUNCIL"))
		eq(CW().legendary.table.empty:GetText(), L("LEGENDARY_EMPTY"))
		falsy(CW().legendary.complete:IsEnabled()); falsy(CW().legendary.abandon:IsEnabled())
		truthy(CW().legendary.open:IsEnabled())
	end)

	it("opens a project from the dialog: name, final item, chain pieces (links or ids) and the builder", function()
		local b = bench()
		open("legendary")
		local d = openDialog()
		eq(d.list:Count(), 5, "nobody yet and the four of the pool")
		eq(d.list:Selected(), "@none")
		fill(d, { builder = "Bryn" })
		truthy(CW():DialogSave())
		falsy(CW():DialogOpen())
		local p = FDCP.LegendaryService:Projects()
		eq(#p, 1)
		eq(p[1].name, "Sulfuras"); eq(p[1].item, 19101); deepEq(p[1].pieces, { 19102, 19103 })
		eq(p[1].builder, full("Bryn")); eq(#p[1].queue, 0)
		local rows = CW().legendary.table:VisibleRows()
		eq(#rows, 1)
		eq(rows[1].cells[1]:GetText(), "Sulfuras")
		eq(rows[1].cells[2]:GetText(), "Bryn")
		eq(rows[1].cells[3]:GetText(), "0/2")
		eq(rows[1].cells[4]:GetText(), L("LEGENDARY_STATE_OPEN"))
		eq(CW().root.message:GetText(), L("LEGENDARY_OPENED"):format("Sulfuras", "Sulfuras", "Bryn"))
		eq(b.count("LEGENDARY_PROJECT_OPENED"), 1)
		-- item ids work as well as links, and the builder may wait
		click(CW().legendary.open)
		fill(dlg(), { name = "Thunderfury", final = "19003", pieces = "19004, 19005" })
		truthy(CW():DialogSave())
		eq(#FDCP.LegendaryService:Projects(), 2)
		isNil(FDCP.LegendaryService:Projects()[2].builder)
		eq(CW().legendary.table:VisibleRows()[2].cells[2]:GetText(), L("LEGENDARY_NOBODY"))
	end)

	it("takes an item link shift-clicked while the final item or the pieces field has the keyboard", function()
		bench()
		open("legendary")
		local d = openDialog()
		falsy(CW().InsertLink(link(19101)), "no field has the keyboard")
		d.b.edit:SetFocus()
		falsy(ChatEdit_InsertLink(link(19101)))   -- the game's function answers for the chat box; the hook still listens
		eq(d.b:GetText(), link(19101))
		d.b.edit:ClearFocus()
		d.c.edit:SetFocus()
		ChatEdit_InsertLink(link(19102)); ChatEdit_InsertLink(link(19103))
		eq(d.c:GetText(), link(19102) .. " " .. link(19103))
		d.a:SetText("Sulfuras")
		truthy(CW():DialogSave())
		deepEq(FDCP.LegendaryService:Projects()[1].pieces, { 19102, 19103 })
		eq(FDCP.LegendaryService:Projects()[1].item, 19101)
		-- a link in the name field is not taken, and neither is one after the dialog closed
		click(CW().legendary.open)
		dlg().a.edit:SetFocus()
		falsy(CW().InsertLink(link(19101)))
		CW():CloseDialog()
		falsy(CW().InsertLink(link(19101)))
	end)

	it("writes the queue with the realm added, names split on spaces or commas", function()
		bench()
		open("legendary")
		local d = openDialog()
		fill(d, { queue = "Aurel, Corin Bryn" })
		truthy(CW():DialogSave())
		deepEq(FDCP.LegendaryService:Projects()[1].queue, { full("Aurel"), full("Corin"), full("Bryn") })
	end)

	it("refuses a missing name, final item or piece, a piece another open project holds, and a name outside the pool", function()
		local b = bench()
		open("legendary")
		local d = openDialog()
		local function refused(fields, code)
			fill(d, fields)
			local ok, got = CW():DialogSave()
			falsy(ok); eq(got, code)
			eq(d.error:GetText(), SBd().ErrorText(code))
			falsy(d.error:GetText():find("RC_REFUSAL", 1, true), "a sentence, not a key")
			truthy(CW():DialogOpen(), "the dialog stays open")
			eq(b.count("LEGENDARY_PROJECT_OPENED"), 0, "nothing was written")
		end
		refused({ name = "" }, "BAD_NAME")
		refused({ final = "" }, "BAD_ITEM")
		refused({ final = "19101 19102" }, "BAD_ITEM")
		refused({ pieces = "" }, "BAD_PIECES")
		refused({ queue = "Zed" }, "NOT_MEMBER")
		fill(d, {})
		truthy(CW():DialogSave())
		click(CW().legendary.open)
		fill(dlg(), { name = "Again", final = "19003" })
		local ok, code = CW():DialogSave()
		falsy(ok); eq(code, "PIECE_TAKEN")
		eq(b.count("LEGENDARY_PROJECT_OPENED"), 1)
	end)

	it("marks a project built or abandons it: the selected row, open projects only", function()
		local b = bench()
		open("legendary")
		fill(openDialog(), { builder = "Bryn" })
		truthy(CW():DialogSave())
		click(CW().legendary.open)
		fill(dlg(), { name = "Thunderfury", final = "19003", pieces = "19004" })
		truthy(CW():DialogSave())
		local rows = CW().legendary.table:VisibleRows()
		click(rows[1])
		truthy(CW().legendary.complete:IsEnabled())
		click(CW().legendary.complete)
		eq(FDCP.LegendaryService:Projects()[1].outcome, "COMPLETED")
		eq(CW().root.message:GetText(), L("LEGENDARY_CLOSED"):format("Sulfuras", FDCP.Reasons.Text("OUTCOME", "COMPLETED")))
		rows = CW().legendary.table:VisibleRows()
		eq(rows[1].cells[4]:GetText(), FDCP.Reasons.Text("OUTCOME", "COMPLETED"))
		falsy(CW().legendary.complete:IsEnabled(), "a closed project cannot be closed again")
		click(rows[2])
		click(CW().legendary.abandon)
		eq(FDCP.LegendaryService:Projects()[2].outcome, "ABANDONED")
		eq(b.count("LEGENDARY_PROJECT_CLOSED"), 2)
		falsy(CW():OnClose("ABANDONED") and true, "nothing left to close")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- A session on the master looter's client (the Guild Master, awardMode council): the item on the table, the flags, the
-- votes and the shortcuts.

local BOSS_GUID = "Creature-0-3-2000-1-11502-0000A1B2C3"
local PLAYERS = { "Aurel", "Bryn", "Corin", "Dara" }

local function Codec() return FDCP.Codec end
local function PS() return FDCP.Protocol.Session end

local function sessionBench(mode)
	local b = bench()
	local r = FDCP.Rules.Current(b.L)
	r.session.awardMode = mode or "council"
	r.session.autoAdvance = false
	r.session.buttonRollsOnly = false   -- typed rolls (M7-2d: test_button_rolls.lua)
	assert(FDCP.Rules.Change(b.L, { author = ME, ts = 5, rules = r, confirmed = true }))
	SC().Env = function(self)   -- the permission gate is tested in test_permissions.lua; the council is the whole raid here
		return { ledger = self:Ledger(), isCouncil = function() return true end }
	end
	Mock.loot.Set{ method = "master", masterLooter = true, threshold = 3, slots = {
		{ link = link(19003), name = "Ring of the Keeper", quality = 4, sources = { BOSS_GUID, 1 } } } }
	Mock.encounter.Start(601, "Boss")
	Mock.encounter.End(601, "Boss", true)
	Mock.loot.Open()
	local present, with = {}, {}
	for _, p in ipairs(PLAYERS) do present[full(p)] = true; with[full(p)] = true end
	assert(SC():Step({ type = "SET_RAID", present = present, addon = with }))
	assert(SC():Command("START"))
	assert(SC():Command("OPEN_ROLL"))
	function b.s() return SC().session end
	function b.answer(name, fields)
		local s = b.s()
		fields.s, fields.i, fields.r = s.id, s.active, s.net.rounds[s.active]
		Mock.chat.Receive("FDCP1", Codec():Encode("SRESP", fields), "RAID", name)
	end
	return b
end

describe("the item on the table", function()
	before_boot(setup(0))

	it("shows the item and the proposal once the round is closed, in the council's mode", function()
		local b = sessionBench()
		open()
		eq(CW().card.item:GetText(), "Ring of the Keeper")
		contains(CW().root.status:GetText(), L("COUNCIL_AWARD_MODE"):format(L("COUNCIL_AWARD_MODE_COUNCIL")))
		eq(CW().card.proposal:GetText(), "", "no proposal while the roll is open")
		b.answer("Aurel", { rs = "MS" }); b.answer("Bryn", { rs = "MS" })
		b.answer("Corin", { rs = "PASS" })
		assert(PS():Respond("PASS"))
		Mock.loot.Roll("Aurel", 40, 1, 100); Mock.loot.Roll("Bryn", 80, 1, 100)
		if b.s().state == "ROLLING" then assert(SC():Command("CLOSE_ROUND")) end
		CW():Refresh()
		eq(b.s().state, "PROPOSAL")
		eq(CW().card.proposal:GetText(), SBd().ProposalText(SC():Board().proposal))
		contains(CW().card.proposal:GetText(), "Bryn")
	end)

	it("tells the flags that name a player, before the round closes", function()
		local b = sessionBench("confirm")
		open()
		eq(CW().card.flags:GetText(), L("COUNCIL_FLAGS_NONE"))
		b.answer("Bryn", { rs = "PASS", vd = { m = { v = "BIG", b = "STATS", p = 120 } } })
		CW():Refresh()
		eq(CW().card.flags:GetText(), L("ML_FLAG_IGNORED_PASS"):format("Bryn", "Big upgrade +12.0%"))
	end)

	it("says the council's vote is advice when the mode is not the council's but the rules ask for it", function()
		local b = bench()
		local r = FDCP.Rules.Current(b.L)
		r.council.vote = true
		r.session.buttonRollsOnly = false   -- typed rolls (M7-2d: test_button_rolls.lua)
		assert(FDCP.Rules.Change(b.L, { author = ME, ts = 5, rules = r, confirmed = true }))
		open()
		contains(CW().root.status:GetText(), L("COUNCIL_AWARD_VOTE_ADVICE"))
		eq(({ CS():AwardMode() })[1], "confirm")
		eq(({ CS():AwardMode() })[2], true)
	end)
end)

describe("the vote and the master looter's shortcuts", function()
	before_boot(setup(0))

	local function toProposal()
		local b = sessionBench()
		b.answer("Aurel", { rs = "MS" }); b.answer("Bryn", { rs = "MS" })
		b.answer("Corin", { rs = "PASS" })
		assert(PS():Respond("PASS"))
		Mock.loot.Roll("Aurel", 40, 1, 100); Mock.loot.Roll("Bryn", 80, 1, 100)
		if b.s().state == "ROLLING" then assert(SC():Command("CLOSE_ROUND")) end
		eq(b.s().state, "PROPOSAL")
		open()
		return b
	end

	it("offers the proposed winner and the candidates, and a vote needs a choice", function()
		toProposal()
		local c = CW().card
		eq(c.choices:Count(), 4, "the proposed one, the other answers and the ones who passed")
		eq(c.choices.choices[1].id, full("Bryn"))
		contains(c.choices.choices[1].text, L("COUNCIL_VOTE_PROPOSED"))
		truthy(c.vote:IsEnabled())
		truthy(c.glow:IsShown(), "the one neon element of the view: the card whose vote is open")
		near((c.parts.ring:GetVertexColor()), 0xC4 / 255, 1e-6)
		click(c.vote)
		eq(CW().root.message:GetText(), SBd().ErrorText("BAD_CHOICE"))
	end)

	it("sends the vote to the council service; the master looter sees it and the member's own choice stays marked", function()
		local b = toProposal()
		local c = CW().card
		truthy(c.choices:Select(full("Aurel")))
		click(c.vote)
		eq(CW().root.message:GetText(), L("COUNCIL_VOTED"):format("Aurel"))
		deepEq(b.s().items[1].votes, { [ME] = full("Aurel") })
		eq(c.votes:GetText(), SBd().VoteText(SC():Board().votes))
		contains(c.votes:GetText(), "Aurel 1")
		eq(c.choices:Selected(), full("Aurel"))
		eq(c.voteHint:GetText(), L("COUNCIL_VOTE_MINE"):format("Aurel"))
	end)

	it("closes when the vote closes: no vote is open any more and the button waits", function()
		local b = toProposal()
		CW().card.choices:Select(full("Aurel"))
		click(CW().card.vote)
		assert(SC():Command("CLOSE_VOTE"))
		CW():Refresh()
		falsy(CW().card.vote:IsEnabled())
		falsy(CW().card.glow:IsShown())
		eq(CW().card.voteHint:GetText(), L("COUNCIL_VOTE_NO_VOTE"))
		eq(CW().card.choices:Count(), 0)
	end)

	it("Modify and Correct open the Session tab's reason dialogs for the master looter", function()
		toProposal()
		local c = CW().card
		truthy(c.modify:IsEnabled())
		click(c.modify)
		eq(ML().root.sub:Active(), "session")
		truthy(ML():DialogOpen())
		eq(ML().dlg.mode, "modify")
		ML():CloseDialog()
		ML().root.sub:Select("council")
		CW():Refresh()
		falsy(c.correct:IsEnabled(), "the category and the cost are fixed once the roll has opened")
		falsy(CW():OnIntervene("correct"))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- A raid of five on the network simulator: Aurel is the Guild Master and the master looter, Bryn and Elin officers (the
-- council by rank), Corin and Dara raiders.

local NAMES = { "Aurel", "Bryn", "Corin", "Dara", "Elin" }
local NET_RANKS = { Aurel = 0, Bryn = 1, Elin = 1, Corin = 3, Dara = 3 }
local BOSS = 663
local RING_LINK = "|cffa335ee|Hitem:19003::::::::70:::::|h[Ring of the Keeper]|h|r"

local function setupFor(name)
	return function(M)
		M.items.Add{ id = 19003, link = RING_LINK, name = "Ring of the Keeper", quality = 4, equipLoc = "INVTYPE_FINGER",
			classID = 4, subclassID = 0 }
		local members = {}
		for _, n in ipairs(NAMES) do
			if n ~= name then members[#members + 1] = { name = n, rank = NET_RANKS[n], class = "WARRIOR" } end
		end
		M.guild.Set({ name = "Dragon", members = members, myRank = NET_RANKS[name] })
		M.loot.Set{ method = "master", masterLooter = name == "Aurel", masterPartyID = 1, threshold = 3,
			candidates = NAMES, slots = {} }
		M.encounter.Set{ instance = { name = "Molten Core", type = "raid", difficultyID = 9, difficultyName = "Normal",
			maxPlayers = 40, instanceID = 409 } }
	end
end

local function A(c) return c.addon() end

local function raidToProposal()
	local net = Sim.new{ realm = REALM, step = 0.25 }
	local c = {}
	for _, n in ipairs(NAMES) do c[n] = net:Client(n, { setup = setupFor(n) }) end
	net:Raid(NAMES)
	net:Advance(3)
	local a = A(c.Aurel)
	local Ledger = assert(a.NightController:Ledger())
	assert(a.Season.Open(Ledger, { author = full("Aurel"), ts = a.Compat.ServerTime(), season = "S1",
		instances = { { id = 409, size = 40 } } }, nil, a.PermissionService:Gate()))
	local r = a.Rules.Current(Ledger)
	r.session.awardMode = "council"
	r.session.autoAdvance = false
	r.session.buttonRollsOnly = false   -- typed rolls (M7-2d: test_button_rolls.lua)
	assert(a.Rules.Change(Ledger, { author = full("Aurel"), ts = a.Compat.ServerTime(), rules = r, confirmed = true },
		a.PermissionService:Gate()))
	-- the guild's ledger reaches every client (its sync is tested elsewhere): the rules are the ones in force everywhere
	for _, n in ipairs({ "Bryn", "Corin", "Dara", "Elin" }) do
		local other = A(c[n])
		assert(other.Ledger.Merge(other.NightController:Ledger(), a.Ledger.Sorted(Ledger)))
	end
	assert(a.NightController:Open({ instanceID = 409 }))
	net:Advance(20)
	net:Encounter(BOSS, "Lucifron", "kill")
	c.Aurel.Mock.loot.Set{ slots = { { link = RING_LINK, name = "Ring of the Keeper", quality = 4, sources = { BOSS_GUID, 1 } } } }
	c.Aurel.Mock.loot.Open()
	net:Advance(3)
	local SCa = a.SessionController
	assert(SCa:Command("START"))
	assert(SCa:Command("OPEN_ROLL"))
	net:Advance(1)
	assert(A(c.Bryn).Protocol.Session:Respond("MS"))
	assert(A(c.Corin).Protocol.Session:Respond("MS"))
	net:Advance(1)
	net:Roll("Bryn", 80)
	net:Roll("Corin", 30)
	net:Advance(1)
	assert(SCa:Command("CLOSE_ROUND"))
	net:Advance(1)
	eq(SCa.session.state, "PROPOSAL")
	return net, c, SCa.session
end

-- The Council sub-tab of a client's window, drawn.
local function councilOf(c)
	local a = A(c)
	a.MainWindow:Open("loot")
	a.MLSession.root.sub:Select("council")
	a.CouncilWindow:Refresh()
	return a.CouncilWindow, a
end

describe("the council's page on each client of a raid", function()
	it("a council member votes from the read-only view; the master looter's page shows the votes arrive", function()
		local net, c, s = raidToProposal()
		local WA = councilOf(c.Aurel)
		local WB, ab = councilOf(c.Bryn)
		local WE = councilOf(c.Elin)
		eq(WA.card.item:GetText(), "Ring of the Keeper")
		eq(WB.card.item:GetText(), "Ring of the Keeper", "the read-only view shows the same item")
		contains(WB.card.proposal:GetText(), "Bryn")
		contains(WB.root.status:GetText(), ab.L["COUNCIL_STATE_MEMBER"])
		eq(WA.card.votes:GetText(), A(c.Aurel).SessionBoard.VoteText(A(c.Aurel).SessionController:Board().votes))
		truthy(WB.card.vote:IsEnabled())
		truthy(WB.card.choices:Select(full("Corin")))
		WB.card.vote:Click()
		eq(WB.root.message:GetText(), ab.L["COUNCIL_VOTED"]:format("Corin"))
		truthy(WE.card.choices:Select(full("Corin")))
		WE.card.vote:Click()
		net:Advance(1)
		deepEq(s.items[1].votes, { [full("Bryn")] = full("Corin"), [full("Elin")] = full("Corin") })
		WA:Refresh()
		contains(WA.card.votes:GetText(), "Corin 2")
		eq(WB.card.voteHint:GetText(), ab.L["COUNCIL_VOTE_MINE"]:format("Corin"))
		truthy(WA.card.modify:IsEnabled(), "the master looter's shortcuts")
		falsy(WB.card.modify:IsEnabled(), "a read-only view has none")
		falsy(WB.card.correct:IsEnabled())
	end)

	it("a raider is not on the council and has no session to look at", function()
		local net, c = raidToProposal()
		local WC, ac = councilOf(c.Corin)
		contains(WC.root.status:GetText(), ac.L["COUNCIL_STATE_NOT_MEMBER"])
		eq(WC.card.item:GetText(), ac.L["COUNCIL_NO_SESSION"])
		falsy(WC.card.vote:IsEnabled())
		local ok, code = ac.CouncilService:Vote(full("Corin"))
		falsy(ok)
	end)

	it("a vote after the master looter closed it is refused in plain words", function()
		local net, c, s = raidToProposal()
		local WB, ab = councilOf(c.Bryn)
		WB.card.choices:Select(full("Corin"))
		WB.card.vote:Click()
		net:Advance(1)
		assert(A(c.Aurel).SessionController:Command("CLOSE_VOTE"))
		net:Advance(1)
		WB:Refresh()
		falsy(WB.card.vote:IsEnabled(), "the button waits")
		eq(WB.card.voteHint:GetText(), ab.L["COUNCIL_VOTE_NO_VOTE"])
		eq(WB.card.choices:Count(), 0)
	end)
end)

describe("a session the master looter confirms by himself", function()
	before_boot(setup(0))

	it("has no council vote to cast: the button waits and says why", function()
		local b = sessionBench("confirm")
		b.answer("Aurel", { rs = "MS" }); b.answer("Bryn", { rs = "MS" })
		b.answer("Corin", { rs = "PASS" })
		assert(PS():Respond("PASS"))
		Mock.loot.Roll("Aurel", 40, 1, 100); Mock.loot.Roll("Bryn", 80, 1, 100)
		if b.s().state == "ROLLING" then assert(SC():Command("CLOSE_ROUND")) end
		eq(b.s().state, "PROPOSAL")
		open()
		falsy(CW().card.vote:IsEnabled())
		eq(CW().card.voteHint:GetText(), L("COUNCIL_VOTE_NO_VOTE"))
		falsy(CS():CanVote(SC():Board()))
		truthy(CW().card.modify:IsEnabled(), "the master looter can still modify with a reason")
	end)
end)
