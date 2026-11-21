-- The master looter's session window (M4-5): UI/Windows/MLSession.lua (Loot > Session) drawn from App/SessionBoard.lua through
-- App/SessionController.lua, on the mock client. A whole boss is run from the window's buttons; Modify cannot be saved
-- without a reason; Reject, Correct, Pause, the "cannot roll" warning and the read-only view of another officer are
-- covered too (docs/ANALISI.md §4, §9.3 point 3).
local function SC() return FDCP.SessionController end
local function Lg() return FDCP.Ledger end
local function Codec() return FDCP.Codec end
local function PS() return FDCP.Protocol.Session end
local function W() return FDCP.MLSession end
local function MW() return FDCP.MainWindow end
local function SBd() return FDCP.SessionBoard end
local function L(key) return FDCP.L[key] end

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end
local ML = full("Dara")
local PLAYERS = { "Aurel", "Bryn", "Corin", "Dara" }
local BOSS_GUID = "Creature-0-3-2000-1-11502-0000A1B2C3"

local function link(id) return "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[Item " .. id .. "]|h|r" end

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

-- A guild ledger with season S1 (the pool of PLAYERS), the controller bound to it, the corpse of the boss.
local function bench(n, opts)
	opts = opts or {}
	local b = { L = Lg().New(), store = {} }
	assert(FDCP.Season.Open(b.L, { author = ML, ts = 1, season = "S1", instances = { { id = 9001, size = 20 } } }))
	SC():Bind(b.L, b.store)
	SC().Env = function(self) return { ledger = self:Ledger() } end   -- the permission gate is tested in test_permissions.lua
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
	function b.raid(addon)
		local present, with = {}, {}
		for _, p in ipairs(PLAYERS) do present[full(p)] = true; with[full(p)] = true end
		for _, p in ipairs(opts.noAddon or {}) do present[full(p)] = true; with[full(p)] = nil end
		assert(SC():Step({ type = "SET_RAID", present = present, addon = with }))
	end
	function b.respond(name, rs)
		if full(name) == ML then return assert(PS():Respond(rs)) end
		local s = b.s()
		Mock.chat.Receive("FDCP1", Codec():Encode("SRESP", { s = s.id, i = s.active, r = s.net.rounds[s.active], rs = rs }),
			"RAID", name)
	end
	function b.answers(map) for _, p in ipairs(PLAYERS) do b.respond(p, map[p] or "PASS") end end
	function b.roll(name, value) Mock.loot.Roll(name, value, 1, 100) end
	function b.awards() return Lg().Sorted(b.L, function(e) return e.type == "ITEM_AWARDED" end) end
	-- kill and corpse (the window opens by itself), the raid
	function b.collect()
		b.kill()
		Mock.loot.Open()
		b.raid()
	end
	return b
end

local function ui() return W().ui end
local function click(button) button:Click() end
local function mainLabel() return ui().main.label:GetText() end
local function rowName(i) return ui().rows[i].name:GetText() end

describe("the tab", function()
	before_boot(setup)

	it("is the Loot page of the main window, with the Session sub-tab", function()
		bench()
		MW():Open("loot")
		truthy(W().root, "built with the window")
		eq(MW():ActiveTab(), "loot")
		eq(W().root.sub:Active(), "session")
		truthy(ui().pane:IsShown())
	end)

	it("says so when no session runs", function()
		bench()
		MW():Open("loot")
		W():Refresh()
		eq(ui().status:GetText(), L("ML_NONE"))
		eq(ui().empty:GetText(), L("ML_NONE_HELP"))
		falsy(ui().rows[1]:IsShown())
		falsy(ui().card:IsShown())
		falsy(ui().main:IsShown())
	end)

	it("opens by itself on the session when the corpse is read, and a bare open goes to Loot while a session runs", function()
		local b = bench()
		b.kill()
		falsy(MW():IsShown(), "a kill alone does not open the window")
		Mock.loot.Open()
		truthy(MW():IsShown())
		eq(MW():ActiveTab(), "loot")
		MW():Close()
		MW():SelectTab("roster")
		Mock.Slash("/fdcp")
		eq(MW():ActiveTab(), "loot", "the window opens on Loot while a session runs")
		MW():Close()
		SC():Reset()
		SC().bound = true
		MW():SelectTab("roster")
		Mock.Slash("/fdcp")
		eq(MW():ActiveTab(), "roster", "and as before when none runs")
	end)
end)

describe("running a whole session from the window", function()
	before_boot(setup)

	it("collects, starts, rolls, confirms five items and ends, with the right ledger events", function()
		local b = bench()
		b.collect()
		local s = b.s()

		-- the items on the left, with the category and cost; Start is the main button
		eq(s.state, "COLLECTING")
		eq(rowName(1), "Ring")
		eq(rowName(3), "Sword")
		truthy(ui().rows[6] ~= nil and not ui().rows[6]:IsShown(), "five items fill five rows")
		truthy(ui().rows[1].sub:GetText():find(W().CategoryName("jewelry"), 1, true))
		truthy(ui().main:IsShown())
		eq(mainLabel(), L("ML_START"))
		truthy(ui().correct:IsShown() and ui().remove:IsShown())
		falsy(ui().modify:IsShown())
		click(ui().main)
		eq(s.state, "ROLLING")
		eq(s.active, 1, "the first roll opened by itself")
		eq(mainLabel(), L("ML_CLOSE_ROUND"))
		eq(ui().rows[1].badge.label:GetText(), L("ML_BADGE_ROLLING"):upper())
		eq(ui().card.name:GetText(), "Ring")
		eq(ui().card.round:GetText(), L("ML_ROUND_TIER"):format(1))
		truthy(ui().card.bar:GetFraction() > 0.9, "the timer bar is nearly full")

		-- 1. Ring: Aurel and Bryn main-spec, same credits and roll: a reroll among them opens by itself
		b.answers({ Aurel = "MS", Bryn = "MS", Corin = "OS" })
		local rows = ui().card.table:GetData()
		eq(#rows, 4, "everybody who answered, the ML included")
		eq(rows[1].response, "MS")
		b.roll("Aurel", 50); b.roll("Bryn", 50)
		eq(ui().card.round:GetText(), L("ML_ROUND_REROLL"))
		b.roll("Aurel", 80); b.roll("Bryn", 20)
		eq(s.state, "PROPOSAL")
		eq(mainLabel(), L("ML_CONFIRM"))
		truthy(ui().modify:IsShown() and ui().reject:IsShown())
		local text = ui().card.strip.main:GetText()
		truthy(text:find("Aurel", 1, true), text)
		truthy(text:find(FDCP.Reasons.Text("REASON", "REROLL_WON"), 1, true), "the reasons are the locale's sentences")
		click(ui().main)
		eq(s.items[1].state, "ASSIGNED")
		eq(#b.awards(), 1)
		eq(b.awards()[1].payload.member, full("Aurel"))

		-- 2. Shoulders (opened by itself): the off-spec tier
		eq(s.active, 2)
		eq(ui().card.name:GetText(), "Shoulders", "the window follows the item in progress")
		b.answers({ Aurel = "OS", Bryn = "OS", Corin = "OS" })
		b.roll("Aurel", 100); b.roll("Bryn", 90); b.roll("Corin", 40)
		eq(s.state, "PROPOSAL")
		click(ui().main)
		-- 3. Sword
		b.answers({ Aurel = "MS", Corin = "MS" })
		b.roll("Aurel", 99); b.roll("Corin", 5)
		click(ui().main)
		eq(b.awards()[3].payload.member, full("Corin"))
		-- 4. Helm
		b.answers({ Bryn = "MS" })
		b.roll("Bryn", 12)
		click(ui().main)
		-- 5. Necklace: everybody passes, nobody to award: Confirm is not offered; the ML modifies with a reason
		b.answers({})
		eq(s.state, "PROPOSAL")
		falsy(ui().main:IsShown(), "no winner: nothing to confirm")
		truthy(ui().modify:IsShown())
		click(ui().modify)
		truthy(W():DialogOpen())
		W().dlg.list:Select(full("Aurel"))
		W().dlg.reasons:Select("OTHER")
		click(W().dlg.save)
		falsy(W():DialogOpen())
		eq(mainLabel(), L("ML_CONFIRM"))
		click(ui().main)

		eq(#b.awards(), 5)
		truthy(b.awards()[5].payload.intervention)
		eq(b.awards()[5].payload.mlReason, "OTHER")
		eq(s.state, "ANNOUNCING")
		truthy(ui().finish:IsShown())
		click(ui().finish)
		eq(s.state, "ENDED")
		eq(ui().status:GetText(), FDCP.Reasons.Text("STATE", "ENDED"))
		falsy(ui().main:IsShown())
		for i = 1, 5 do eq(ui().rows[i].badge.label:GetText(), L("ML_BADGE_ASSIGNED"):upper()) end
	end)

	it("shows the candidates with credits, response, roll and the discarded rolls of players without the addon", function()
		local b = bench(1, { noAddon = { "Edda" } })
		b.collect()
		click(ui().main)
		b.answers({ Aurel = "MS", Bryn = "MS", Corin = "OS" })
		b.roll("Edda", 77)   -- no addon: the roll is kept and set aside
		b.roll("Aurel", 40)
		local d = ui().card.table:GetData()
		local by = {}
		for _, r in ipairs(d) do by[r.name] = r end
		eq(by.Aurel.roll, 40, "a roll shows at once")
		eq(by.Bryn.roll, nil)
		eq(by.Edda.flag.code, "NO_ADDON", "the roll of a player without the addon is flagged as it comes in")
		b.roll("Bryn", 90)
		eq(b.s().state, "PROPOSAL", "everybody main-spec has rolled")
		d = ui().card.table:GetData()
		by = {}
		for _, r in ipairs(d) do by[r.name] = r end
		eq(d[1].name, "Bryn", "main-spec first, the highest roll first")
		eq(by.Bryn.proposed, true)
		eq(by.Aurel.proposed, false)
		eq(by.Edda.flag.code, "NO_ADDON")
		eq(by.Dara.response, "PASS", "the ML's own answer is in the list")
		eq(ui().card.table.rows[1].cells[5]:GetText(), L("ML_NOTE_PROPOSED"))
		eq(ui().card.table.rows[1].cells[2]:GetText(), "0")
	end)
end)

describe("labels and notes (M4-6)", function()
	before_boot(setup)

	it("shows the label next to the response and the note in the Notes column, for the master looter only", function()
		local b = bench(1)
		b.collect()
		click(ui().main)
		local s = b.s()
		local function answer(name, fields)
			fields.s, fields.i, fields.r = s.id, s.active, s.net.rounds[s.active]
			Mock.chat.Receive("FDCP1", Codec():Encode("SRESP", fields), "RAID", name)
		end
		answer("Aurel", { rs = "MS", lb = "BIG_UPGRADE", n = "two-hander" })
		answer("Bryn", { rs = "MS", lb = "BIS", n = "|cffff0000red|r" .. string.char(10) .. "line" })
		answer("Corin", { rs = "OS" })
		eq(b.item().labels[full("Aurel")], "BIG_UPGRADE")
		eq(b.item().notes[full("Aurel")], "two-hander")
		local by = {}
		for _, r in ipairs(ui().card.table:GetData()) do by[r.name] = r end
		eq(by.Aurel.label, "BIG_UPGRADE"); eq(by.Aurel.note, "two-hander")
		eq(by.Bryn.note, "||cffff0000red||r line", "escape sequences are doubled and control characters become spaces")
		isNil(by.Corin.label)
		local rows = {}
		for _, row in ipairs(ui().card.table.rows) do
			if row:IsShown() and row.cells[1]:GetText() ~= "" then rows[row.cells[1]:GetText()] = row end
		end
		eq(rows.Aurel.cells[3]:GetText(), "Main-spec · Big upgrade")
		eq(rows.Corin.cells[3]:GetText(), "Off-spec")
		eq(rows.Aurel.cells[5]:GetText(), "two-hander")
		eq(rows.Bryn.cells[3]:GetText(), "Main-spec · BiS")
	end)
end)

describe("Modify", function()
	before_boot(setup)

	local function proposal()
		local b = bench(1)
		b.collect()
		SC():Command("START")
		b.answers({ Aurel = "MS", Bryn = "MS", Corin = "OS" })
		b.roll("Aurel", 40); b.roll("Bryn", 90)
		eq(b.s().state, "PROPOSAL")
		eq(b.item().proposal.winner, full("Bryn"))
		return b
	end

	it("cannot be saved without a reason", function()
		local b = proposal()
		click(ui().modify)
		local d = W().dlg
		d.list:Select(full("Aurel"))
		click(d.save)
		truthy(W():DialogOpen(), "the dialog stays open")
		eq(d.error:GetText(), L("RC_REFUSAL_REASON_REQUIRED"))
		eq(b.item().proposal.winner, full("Bryn"), "nothing changed")
		falsy(b.item().intervention)
		d.reasons:Select("OBVIOUS_WASTE")
		click(d.save)
		falsy(W():DialogOpen())
		eq(b.item().proposal.winner, full("Aurel"))
		eq(b.item().intervention.reason, "OBVIOUS_WASTE")
	end)

	it("shows the difference from the rules while the choice is made, and flags the saved proposal out of order", function()
		local b = proposal()
		click(ui().modify)
		local d = W().dlg
		eq(d.preview:GetText(), "", "nothing changed yet")
		d.list:Select(full("Aurel"))
		local preview = d.preview:GetText()
		truthy(preview:find(FDCP.L["ML_DIFF_OUT_OF_ORDER"]:format("Bryn", "Aurel"), 1, true), preview)
		d.cost:SetText("0")
		truthy(d.preview:GetText():find(FDCP.L["ML_DIFF_COST"]:format(L("ML_CREDITS_N"):format(0), SBd().CreditsText(b.item().rule.cost)), 1, true)
			or d.preview:GetText():find("0", 1, true))
		eq(b.item().proposal.winner, full("Bryn"), "the preview changes nothing")
		d.reasons:Select("OBVIOUS_WASTE")
		click(d.save)
		local board = SC():Board()
		truthy(board.proposal.modified)
		local has = false
		for _, f in ipairs(board.proposal.flags) do if f == "OUT_OF_ORDER" then has = true end end
		truthy(has)
		local sub = ui().card.strip.sub:GetText()
		truthy(sub:find(FDCP.L["ML_DIFF_OUT_OF_ORDER"]:format("Bryn", "Aurel"), 1, true), sub)
		click(ui().main)
		local e = b.awards()[1]
		eq(e.payload.member, full("Aurel"))
		eq(e.payload.ruleWinner, full("Bryn"))
		eq(e.payload.mlReason, "OBVIOUS_WASTE")
	end)

	it("changes only the cost, refuses a cost that is not a number and a save that changes nothing", function()
		local b = proposal()
		click(ui().modify)
		local d = W().dlg
		d.reasons:Select("MISTAKE")
		click(d.save)
		eq(d.error:GetText(), SBd().ErrorText("NOTHING_CHANGED"))
		d.cost:SetText("abc")
		eq(d.error:GetText(), L("ML_ERR_BAD_COST"))
		click(d.save)
		eq(d.error:GetText(), L("ML_ERR_BAD_COST"))
		d.cost:SetText("3")
		click(d.save)
		falsy(W():DialogOpen())
		eq(b.item().proposal.cost, 3)
		eq(b.item().proposal.winner, full("Bryn"))
	end)

	it("can send the item to the guild bank", function()
		local b = proposal()
		click(ui().modify)
		local d = W().dlg
		d.list:Select("@bank")
		d.reasons:Select("OTHER")
		click(d.save)
		eq(b.item().proposal.target, "bank")
		eq(b.item().proposal.cost, 0)
	end)
end)

describe("Reject, Correct, Pause and the other buttons", function()
	before_boot(setup)

	it("Reject puts the item on hold; the main button opens its roll again", function()
		local b = bench(1)
		b.collect()
		SC():Command("START")
		b.answers({ Aurel = "MS" })
		b.roll("Aurel", 10)
		eq(b.s().state, "PROPOSAL")
		click(ui().reject)
		truthy(W():DialogOpen())
		eq(W().dlg.list:Selected(), "PENDING", "the default")
		click(W().dlg.save)
		falsy(W():DialogOpen())
		eq(#b.awards(), 0, "nobody was charged")
		eq(b.s().state, "ANNOUNCING")
		eq(b.item(1).state, "PENDING")
		eq(ui().rows[1].badge.label:GetText(), L("ML_BADGE_HELD"):upper())
		eq(b.s().active, nil)
		W():Select(1)
		eq(mainLabel(), L("ML_OPEN_ROLL"))
		click(ui().main)
		eq(b.s().state, "ROLLING")
		eq(b.s().active, 1)
	end)

	it("Reject to the bank makes a bank proposal", function()
		local b = bench(1)
		b.collect()
		SC():Command("START")
		b.answers({ Aurel = "MS" })
		b.roll("Aurel", 10)
		click(ui().reject)
		W().dlg.list:Select("BANK")
		click(W().dlg.save)
		eq(b.item().proposal.kind, "BANK")
		eq(b.item().rejected[1]["then"], "BANK")
	end)

	it("Correct needs a reason, changes the category and the cost before the roll", function()
		local b = bench(2)
		b.collect()
		local before = b.item(1).costs.MS
		W():Select(1)
		click(ui().correct)
		local d = W().dlg
		eq(d.list:Selected(), "jewelry", "the current category")
		d.list:Select("weapon")
		click(d.save)
		truthy(W():DialogOpen(), "no reason, no correction")
		eq(d.error:GetText(), L("RC_REFUSAL_REASON_REQUIRED"))
		d.reasons:Select("WRONG_CATEGORY")
		click(d.save)
		falsy(W():DialogOpen())
		eq(b.item(1).category, "weapon")
		truthy(b.item(1).costs.MS ~= before)
		eq(ui().rows[1].sub:GetText():find(W().CategoryName("weapon"), 1, true) ~= nil, true)
		-- a base cost typed by hand
		click(ui().correct)
		d = W().dlg
		d.cost:SetText("5")
		d.reasons:Select("COUNCIL_COST")
		click(d.save)
		eq(b.item(1).costs.MS, 5)
	end)

	it("Remove takes the selected item off the list before the session starts", function()
		local b = bench(3)
		b.collect()
		W():Select(2)
		click(ui().remove)
		eq(#b.s().items, 2)
		eq(rowName(2), "Sword", "the third item moved up")
	end)

	it("Pause stops the timer and Resume starts it again", function()
		local b = bench(1)
		b.collect()
		click(ui().main)
		eq(ui().pause.label:GetText(), L("ML_PAUSE"))
		click(ui().pause)
		truthy(b.s().paused)
		eq(ui().pause.label:GetText(), L("ML_RESUME"))
		truthy(ui().card.timer:GetText():find(L("ML_PAUSED"), 1, true))
		Mock.Advance(60)
		eq(b.s().state, "ROLLING")
		click(ui().pause)
		falsy(b.s().paused)
		eq(ui().pause.label:GetText(), L("ML_PAUSE"))
	end)

	it("counts down the timer on the open round while the tab is visible", function()
		local b = bench(1)
		b.collect()
		click(ui().main)
		local first = ui().card.timer:GetText()
		Mock.Advance(5)
		local later = ui().card.timer:GetText()
		truthy(first ~= later, first .. " " .. later)
	end)

	it("shows a refusal of the state machine in plain words", function()
		local b = bench(1)
		b.collect()
		click(ui().main)
		local ok, code = W():Do("OPEN_ROLL", { index = 1 })
		falsy(ok)
		eq(ui().message:GetText(), SBd().ErrorText(code))
	end)

	it("closes a round by hand and opens the next one when auto-advance is off", function()
		local b = bench(1)
		b.collect()
		b.s().rules.session.autoAdvance = false
		click(ui().main)   -- start
		eq(b.s().state, "ANNOUNCING", "nothing opens by itself")
		eq(mainLabel(), L("ML_OPEN_ROLL"))
		click(ui().main)
		eq(b.s().state, "ROLLING")
		b.answers({ Aurel = "MS", Bryn = "MS" })
		b.roll("Aurel", 50); b.roll("Bryn", 50)
		eq(b.s().state, "ROLLING", "still open: the ML closes it")
		click(ui().main)   -- close
		eq(b.s().state, "COMPUTING")
		eq(mainLabel(), L("ML_NEXT_ROUND"))
		click(ui().main)
		eq(b.item().round.kind, "REROLL")
	end)
end)

describe("the warning and the read-only view", function()
	before_boot(setup)

	it("warns that members cannot roll, and the button writes the notice in /raid", function()
		local b = bench(1, { noAddon = { "Edda", "Fenn" } })
		b.collect()
		truthy(ui().missing:IsShown())
		eq(ui().missing.label:GetText(), L("ML_CANNOT_ROLL_N"):format(2):upper())
		eq(SC():Board().missing[1], full("Edda"))
	end)

	it("the notify button sends the notice and tells the result, or the reason it did not leave", function()
		local b = bench(1, { noAddon = { "Edda" } })
		b.collect()
		falsy(ui().notify:IsShown(), "only who may manage the addon check sees the button")
		FDCP.AddonCheck.CanManage = function() return true end
		W():Refresh()
		truthy(ui().notify:IsShown())
		local kinds = {}
		FDCP.AddonNotice.Send = function(_, kind) kinds[#kinds + 1] = kind; return { mode = "RAID", lines = 2 } end
		click(ui().notify)
		deepEq(kinds, { "MISSING" })
		eq(ui().message:GetText(), L("NOTICE_SENT"):format("/raid", 2))
		FDCP.AddonNotice.Send = function() return nil, "ENCOUNTER" end
		click(ui().notify)
		eq(ui().message:GetText(), L("NOTICE_ERR_ENCOUNTER"))
	end)

	it("hides the warning when everybody has the addon", function()
		local b = bench(1)
		b.collect()
		falsy(ui().missing:IsShown())
		falsy(ui().notify:IsShown())
	end)

	it("gives another officer the master looter's view without buttons", function()
		bench(1)
		PS().view = { s = "S1-9", q = 4, ml = full("Bryn"), items = {
			{ id = 19003, ca = "jewelry", cs = { MS = 1, OS = 0 }, st = "PROPOSAL" },
			{ id = 19001, ca = "armor", cs = { MS = 1, OS = 0 }, st = "PENDING" },
		}, a = 1, proposal = { i = 1, k = "AWARD", tg = "member", w = full("Aurel"), c = 1, rc = { "LOWER_CREDITS" }, f = {} },
			mine = {}, responses = {} }
		FDCP.PermissionService.Can = function() return true end
		MW():Open("loot")
		W():Refresh()
		local board = SC():Board()
		eq(board.host, false)
		eq(board.state, "PROPOSAL")
		eq(rowName(1), "Ring")
		falsy(ui().main:IsShown() or ui().modify:IsShown() or ui().reject:IsShown() or ui().correct:IsShown())
		falsy(ui().pause:IsShown() or ui().finish:IsShown())
		truthy(ui().status:GetText():find(L("ML_HINT_READONLY"), 1, true))
		truthy(ui().card.strip.main:GetText():find("Aurel", 1, true))
		eq(#ui().card.table:GetData(), 0, "the candidates travel only to the master looter")
	end)

	it("hides the session from a raider who is not an officer", function()
		bench(1)
		PS().view = { s = "S1-9", q = 1, ml = full("Bryn"), items = { { id = 19003, ca = "jewelry", cs = { MS = 1 }, st = "PENDING" } },
			mine = {}, responses = {} }
		FDCP.PermissionService.Can = function() return false, "RANK_TOO_LOW" end
		MW():Open("loot")
		W():Refresh()
		eq(ui().status:GetText(), L("ML_NONE"))
	end)
end)

describe("the board", function()
	before_boot(setup)

	it("lists the items with their state, cost and the winner once awarded", function()
		local b = bench(2)
		b.collect()
		SC():Command("START")
		local board = SC():Board()
		eq(#board.items, 2)
		eq(board.items[1].state, "ROLLING")
		eq(board.items[1].active, true)
		eq(board.items[2].state, "PENDING")
		eq(board.items[1].cost, b.item(1).costs.MS)
		b.answers({ Aurel = "MS" })
		b.roll("Aurel", 30)
		SC():Command("CONFIRM")
		board = SC():Board(1)
		eq(board.items[1].winner, full("Aurel"))
		eq(board.items[1].paid, b.item(1).costs.MS)
		eq(board.selected, 1)
		eq(board.actions.confirm, false)
	end)

	it("offers only the actions the state machine would accept", function()
		local b = bench(1)
		b.collect()
		local a = SC():Board().actions
		truthy(a.start); truthy(a.correct); truthy(a.remove); truthy(a.pause); truthy(a.finish)
		falsy(a.confirm); falsy(a.closeRound)
		SC():Command("START")
		a = SC():Board().actions
		truthy(a.closeRound); falsy(a.start); falsy(a.finish, "an item is in progress")
		SC():Command("END")
	end)

	it("credits text, errors and the proposal sentence go through the locale", function()
		eq(SBd().CreditsText(1), L("ML_CREDITS_ONE"))
		eq(SBd().CreditsText(2), L("ML_CREDITS_N"):format(2))
		eq(SBd().CreditsText(nil), L("ML_COST_UNSET"))
		eq(SBd().ErrorText("BAD_STATE"), L("RC_REFUSAL_BAD_STATE"))
		eq(SBd().ErrorText("NO_SESSION"), L("ML_ERR_NO_SESSION"))
		eq(SBd().ErrorText("zzz"), L("ML_ERR_OTHER"):format("zzz"))
		eq(W().ParseCost("2,5"), 2.5)
		isNil(W().ParseCost(""))
		local _, bad = W().ParseCost("x")
		eq(bad, "ML_ERR_BAD_COST")
		eq(W().Clock(75), "1:15")
	end)

	it("a session saved before the window existed still draws (the saved session is plain data)", function()
		local b = bench(1)
		b.collect()
		SC():Command("START")
		local saved = SC().store.session
		SC():Reset()
		SC():Bind(b.L, { session = saved })
		SC().Env = function(self) return { ledger = self:Ledger() } end
		W():Refresh()
		eq(rowName(1), "Ring")
		eq(ui().rows[1].badge.label:GetText(), L("ML_BADGE_ROLLING"):upper())
	end)
end)
