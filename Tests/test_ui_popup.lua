-- The player's item popup (M4-6): App/PopupBoard.lua (what the player may do now) and UI/Windows/MemberLootPopup.lua (the
-- card: item, chip, segmented response, label chips, note, timer bar, Roll). It is driven through the real protocol
-- (Net/Protocol.lua's view), on one client and on the network simulator, where a master looter receives the answers
-- (docs/ANALISI.md §5.1, §6, docs/specs/ui-style.md §3).
local function PS() return FDCP.Protocol.Session end
local function Codec() return FDCP.Codec end
local function PB() return FDCP.PopupBoard end
local function P() return FDCP.MemberLootPopup end
local function L(key) return FDCP.L[key] end

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end
local ML = full("Aurel")

local ITEMS = {
	{ id = 19003, link = "|cffa335ee|Hitem:19003::::::::70:::::|h[Ring of the Keeper]|h|r", name = "Ring of the Keeper", quality = 4,
		equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0, type = "Armor", subType = "Miscellaneous", level = 66 },
	{ id = 19002, link = "|cffa335ee|Hitem:19002::::::::70:::::|h[Sword of Embers]|h|r", name = "Sword of Embers", quality = 4,
		equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7, type = "Weapon", subType = "One-Handed Swords", level = 70 },
}

local function items(M)
	for _, def in ipairs(ITEMS) do M.items.Add(def) end
	_G.INVTYPE_FINGER, _G.INVTYPE_WEAPON = "Finger", "One-Hand"   -- the client's own words for the slots
end

-- The decoded addon messages a client sent, oldest first.
local function sentMessages(M)
	local out = {}
	for _, e in ipairs(M.chat.SentWithPrefix("FDCP1")) do
		local text = e.message
		if text:byte(1) == 4 then text = text:sub(2) end   -- AceComm escape byte
		local msg = Codec():Decode(text)
		if msg then out[#out + 1] = { msg = msg, chatType = e.chatType, target = e.target } end
	end
	return out
end

local function lastOf(list, t)
	for i = #list, 1, -1 do if list[i].msg.t == t then return list[i].msg end end
end

local function count(list, t)
	local n = 0
	for _, e in ipairs(list) do if e.msg.t == t then n = n + 1 end end
	return n
end

local function card() return P().cards[1] end
local function seg() return card().data.seg end

---------------------------------------------------------------------------------------------------------------------
-- The board: plain data, no frames

local function view(extra)
	local v = { s = "S1-1", q = 3, ml = ML, e = 663, tiers = { MS = 1, OS = 2 }, mine = {}, responses = {},
		items = { { id = 19003, ca = "jewelry", cs = { MS = 1, OS = 0 }, st = "ROLLING" } },
		a = 1, round = { i = 1, r = 1, k = "ROLL", g = "TIER", tr = 1, cl = true, deadline = 130 } }
	for k, x in pairs(extra or {}) do v[k] = x end
	return v
end
local ME = full("Bryn")
local function build(v, env)
	env = env or {}
	env.me, env.now = env.me or ME, env.now or 100
	return PB().Build(v, env).cards[1]
end

describe("the board", function()
	before_boot(function(M) M.player.name, M.player.realm = "Bryn", REALM end)

	it("lists the responses on offer by tier, with their costs, and keeps Pass out of the list", function()
		local c = build(view())
		eq(#c.offered, 2)
		eq(c.offered[1].code, "MS"); eq(c.offered[1].cost, 1); eq(c.offered[1].tier, 1)
		eq(c.offered[2].code, "OS"); eq(c.offered[2].cost, 0)
		eq(c.main, "MS")
		eq(c.cost, 1, "before an answer the card shows the full cost")
		falsy(c.council)
	end)

	it("falls back to the usual order when an older master looter does not say the tiers", function()
		local v = view({ tiers = false })
		v.tiers = nil
		v.items[1].cs = { OS = 0, MS = 1, TMOG = 0 }
		local c = build(v)
		eq(c.offered[1].code, "MS"); eq(c.offered[2].code, "OS"); eq(c.offered[3].code, "TMOG")
	end)

	it("shows the cost of the response the player picked, and 'council' when there is none", function()
		local v = view()
		v.responses[1] = { [ME] = { rs = "OS" } }
		eq(build(v).cost, 0)
		v = view()
		v.items[1].co = true
		truthy(build(v).council)
		v = view()
		v.items[1].cs = {}
		truthy(build(v).council)
	end)

	it("offers the label chips only in the round that collects responses, enabled for main-spec or no answer", function()
		local v = view()
		local c = build(v)
		deepEq(c.labels, { "BIS", "BIG_UPGRADE", "SMALL_UPGRADE", "SITUATIONAL" })
		truthy(c.labelsOn)
		v.responses[1] = { [ME] = { rs = "OS" } }
		falsy(build(v).labelsOn, "off-spec carries no label")
		v.responses[1] = { [ME] = { rs = "MS", lb = "BIS" } }
		c = build(v)
		truthy(c.labelsOn); eq(c.label, "BIS")
	end)

	it("says whether the player rolls: the first round needs a main-spec answer, the next tier its own", function()
		local v = view()
		local c = build(v)
		falsy(c.canRoll); eq(c.hint, "CHOOSE"); truthy(c.canAnswer)
		v.responses[1] = { [ME] = { rs = "MS" } }
		c = build(v)
		truthy(c.canRoll); eq(c.hint, "ROLL")
		v.responses[1] = { [ME] = { rs = "OS" } }
		c = build(v)
		falsy(c.canRoll); eq(c.hint, "LATER")
		v.responses[1] = { [ME] = { rs = "PASS" } }
		c = build(v)
		falsy(c.canRoll); eq(c.hint, "PASSED")
		-- the off-spec round: only whoever answered off-spec gets a card
		v.round = { i = 1, r = 2, k = "ROLL", g = "TIER", tr = 2, deadline = 130 }
		isNil(build(v), "a pass has nothing to roll for")
		v.responses[1] = { [ME] = { rs = "MS" } }
		isNil(build(v), "nor does main-spec in the off-spec round")
		v.responses[1] = { [ME] = { rs = "OS" } }
		c = build(v)
		truthy(c.canRoll); falsy(c.canAnswer); falsy(c.collect); eq(c.hint, "TURN"); falsy(c.labels)
	end)

	it("a reroll is for the tied only, a free roll for everybody", function()
		local v = view()
		v.responses[1] = { [ME] = { rs = "MS" } }
		v.round = { i = 1, r = 2, k = "REROLL", g = "TIER", tr = 1, am = { full("Corin"), ME }, deadline = 130 }
		local c = build(v)
		truthy(c.canRoll); eq(c.hint, "REROLL"); eq(c.kind, "REROLL")
		v.round.am = { full("Corin"), full("Dara") }
		isNil(build(v), "not tied: no card")
		v.round = { i = 1, r = 2, k = "ROLL", g = "FREE_ROLL", deadline = 130 }
		v.responses[1] = { [ME] = { rs = "PASS" } }
		c = build(v)
		truthy(c.canRoll); eq(c.hint, "FREE"); eq(c.stage, "FREE_ROLL")
	end)

	it("draws nothing without a round, after the end, or once the card was hidden", function()
		local v = view()
		v.round = nil
		isNil(build(v))
		isNil(build(view({ ended = true })))
		isNil(build(view(), { dismissed = function() return true end }))
		isNil(PB().Build(nil, {}).cards[1])
	end)

	it("counts the time left, and keeps the paused value", function()
		eq(build(view(), { now = 112 }).remaining, 18)
		eq(build(view(), { now = 500 }).remaining, 0)
		local v = view({ paused = true })
		v.round.rm = 21
		local c = build(v)
		eq(c.remaining, 21); truthy(c.paused)
	end)

	it("the answer being typed wins over what the session knows, for its own round only", function()
		local v = view()
		v.responses[1] = { [ME] = { rs = "MS" } }
		local c = build(v, { draft = { key = "S1-1:1:1", rs = "OS", n = "later" } })
		eq(c.response, "OS"); eq(c.note, "later")
		c = build(v, { draft = { key = "S1-1:1:9", rs = "OS" } })
		eq(c.response, "MS")
	end)

	it("clips a note to 80 bytes without cutting a character in two", function()
		eq(PB().ClipNote("  "), "  ")
		isNil(PB().ClipNote(""))
		isNil(PB().ClipNote(nil))
		eq(PB().ClipNote("two\nlines"), "two lines")
		eq(#PB().ClipNote(string.rep("x", 200)), 80)
		local s = PB().ClipNote(string.rep("x", 79) .. "è")   -- the accent needs two bytes: 81 in all
		eq(s, string.rep("x", 79))
		s = PB().ClipNote(string.rep("è", 60))
		eq(#s, 80)
		eq(s, string.rep("è", 40))
	end)
end)

describe("the place in the queue", function()
	before_boot(function(M)
		M.player.name, M.player.realm = "Testchar", REALM
		M.guild.Set({ name = "Keepers", ranks = { [0] = "Guild Master", "Officer" }, myRank = 1, members = {
			{ name = "Aurel", rank = 0 }, { name = "Testchar", rank = 1 } } })
	end)

	local function ledger()
		local Lg, Sn, R = FDCP.Ledger, FDCP.Season, FDCP.Roster
		local L1 = Lg.New()
		local A = full("Aurel")
		assert(Sn.Open(L1, { author = A, ts = 1, season = "S1", instances = { { id = 409, size = 40 } } }))
		for i, p in ipairs({ { "Aurel", 73 }, { "Bryn", 65 }, { "Corin", 105 }, { "Dara", 63 }, { "Testchar", 63 } }) do
			assert(R.Join(L1, { author = A, ts = 2 + i, season = "S1", member = full(p[1]), faction = "Horde", ms1 = p[2] }))
		end
		local function award(ts, who, cost)
			assert(Lg.Append(L1, { author = A, ts = ts, season = "S1", type = "ITEM_AWARDED", payload = { target = "member",
				member = full(who), item = 100 + ts, cost = cost, reasons = {}, flags = {} } }))
		end
		award(20, "Aurel", 3); award(21, "Bryn", 1); award(22, "Dara", 2); award(23, "Testchar", 2)
		FDCP.NightController:Bind(L1)
		Mock.Advance(3)
		return L1
	end

	it("is the credits and 1 + the members with fewer credits (a tie is for the roll to settle)", function()
		ledger()
		local s = PB().Standing(full("Testchar"))
		truthy(s)
		near(s.credits, 2)
		-- Corin 0, Bryn 1 are ahead; Dara has the same 2 (not counted: a tie)
		eq(s.position, 3)
	end)

	it("counts only the raid members when the raid is known", function()
		ledger()
		local raid = { inRaid = true, complete = true, members = { [full("Testchar")] = true, [full("Bryn")] = true } }
		eq(PB().Standing(full("Testchar"), raid).position, 2)
		eq(PB().Standing(full("Testchar"), { inRaid = false }).position, 3)
	end)

	it("is nothing when this client has no ledger, no season or no row for the player", function()
		isNil(PB().Standing(full("Testchar")), "no ledger bound")
		ledger()
		isNil(PB().Standing(full("Nobody")))
		isNil(PB().Standing(nil))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The card on one client

describe("the card", function()
	before_boot(function(M)
		M.player.name, M.player.realm = "Bryn", REALM
		items(M)
	end)

	local function raid()
		Mock.group.Set{ raid = true, members = { { name = "Aurel" }, { name = "Corin" } } }
		Mock.Advance(3)
	end

	local function receive(t, fields)
		return Mock.chat.Receive("FDCP1", Codec():Encode(t, fields), "RAID", ML)
	end

	local q = 0
	local function open(tiers)
		q = 1
		raid()
		receive("SOPEN", { s = "S1-1", q = q, ml = ML, e = 663, rt = tiers == nil and { MS = 1, OS = 2 } or tiers or nil,
			it = { { id = 19003, ca = "jewelry", cs = { MS = 1, OS = 0 } }, { id = 19002, ca = "weapon", cs = { MS = 2, OS = 0 } } } })
	end
	local function roll(extra)
		q = q + 1
		local fields = { s = "S1-1", q = q, i = 1, r = 1, k = "ROLL", g = "TIER", tr = 1, cl = true,
			de = FDCP.Compat.ServerTime() + 30 }
		for k, v in pairs(extra or {}) do fields[k] = v end
		receive("SROLL", fields)
	end
	local function control(t, fields)
		q = q + 1
		fields.s, fields.q = "S1-1", q
		receive(t, fields)
	end
	local function sent() return sentMessages(Mock) end
	local function lastAnswer()
		Mock.Advance(2)
		return lastOf(sent(), "SRESP")
	end

	it("stays away until a round asks something of the player, then shows the item", function()
		open()
		falsy(P():IsShown(), "the session is announced: no roll yet")
		isNil(P().frame)
		roll()
		truthy(P():IsShown())
		eq(card().name:GetText(), "Ring of the Keeper")
		Mock.RunScript(card().hit, "OnEnter")
		truthy(GameTooltip:IsShown(), "hovering the item shows the game's tooltip")
		Mock.RunScript(card().hit, "OnLeave")
		falsy(GameTooltip:IsShown())
		eq(card().line:GetText(), "Finger · Item level 66")
		eq(card().eyebrow:GetText(), "ROLL OPEN · LUCIFRON")
		eq(card().badge.label:GetText(), "JEWELRY · 1 CREDIT")
		eq(card().timer:GetText(), "0:30")
		eq(card().hint:GetText(), L("POPUP_HINT_CHOOSE"))
	end)

	it("shows the weapon kind for a weapon, and the quality colour on the name", function()
		open()
		roll({ i = 2 })
		eq(card().name:GetText(), "Sword of Embers")
		eq(card().line:GetText(), "One-Hand · One-Handed Swords · Item level 70")
		eq(card().badge.label:GetText(), "WEAPON · 2 CREDITS")
		local r, g, b = card().name:GetTextColor()
		near(r, 0.64, 0.01); near(g, 0.21, 0.01); near(b, 0.93, 0.01)
	end)

	it("asks the client for an item it has not loaded, and fills the name in when it arrives", function()
		Mock.items.Add{ id = 19099, link = "|Hitem:19099|h[Late Item]|h", name = "Late Item", quality = 4, equipLoc = "INVTYPE_HEAD",
			classID = 4, subclassID = 4, cached = false }
		raid()
		receive("SOPEN", { s = "S1-1", q = 1, ml = ML, rt = { MS = 1 }, it = { { id = 19099, ca = "armor", cs = { MS = 1 } } } })
		receive("SROLL", { s = "S1-1", q = 2, i = 1, r = 1, k = "ROLL", g = "TIER", tr = 1, cl = true })
		eq(card().name:GetText(), L("ML_ITEM_UNKNOWN"):format(19099))
		Mock.Advance(1)
		eq(card().name:GetText(), "Late Item")
	end)

	it("offers Main-spec, Off-spec and Pass, in that order, with nothing selected", function()
		open()
		roll()
		local s = seg()
		deepEq(s.order, { "MS", "OS", "PASS" })
		eq(s.buttons.MS.label:GetText(), "Main-spec")
		eq(s.buttons.OS.label:GetText(), "Off-spec")
		eq(s.buttons.PASS.label:GetText(), "Pass")
		isNil(s:Active())
		truthy(s.enabled ~= false)
	end)

	it("sends the answer at once, and again when it changes: the latest one wins", function()
		open()
		roll()
		seg().buttons.OS:Click()
		local m = lastAnswer()
		eq(m.rs, "OS"); isNil(m.lb); isNil(m.p, "a member only ever sends their own answer")
		eq(m.i, 1); eq(m.r, 1)
		eq(PS():MyAnswer(1).rs, "OS")
		seg().buttons.MS:Click()
		Mock.Advance(2)
		eq(lastOf(sent(), "SRESP").rs, "MS")
		eq(seg():Active(), "MS")
		eq(card().hint:GetText(), L("POPUP_HINT_ROLL"):format(1, 100))
	end)

	it("a label answers main-spec by itself, toggles off, and goes away with off-spec or pass", function()
		open()
		roll()
		local chip = card().chips.BIS
		truthy(chip:IsEnabled())
		chip:Click()
		local m = lastAnswer()
		eq(m.rs, "MS"); eq(m.lb, "BIS")
		truthy(card().chips.BIS:IsSelected())
		eq(seg():Active(), "MS")
		card().chips.BIG_UPGRADE:Click()
		eq(lastAnswer().lb, "BIG_UPGRADE")
		falsy(card().chips.BIS:IsSelected())
		card().chips.BIG_UPGRADE:Click()
		isNil(lastAnswer().lb, "clicking the chosen label again clears it")
		card().chips.SMALL_UPGRADE:Click()
		eq(lastAnswer().lb, "SMALL_UPGRADE")
		seg().buttons.OS:Click()
		m = lastAnswer()
		eq(m.rs, "OS"); isNil(m.lb)
		falsy(card().chips.SMALL_UPGRADE:IsEnabled(), "no label for off-spec")
		card().chips.SMALL_UPGRADE:Click()
		eq(lastAnswer().rs, "OS", "a disabled chip does nothing")
		seg().buttons.MS:Click()
		card().chips.SITUATIONAL:Click()
		seg().buttons.PASS:Click()
		m = lastAnswer()
		eq(m.rs, "PASS"); isNil(m.lb)
	end)

	it("the labels read the same in English and in Italian", function()
		open()
		roll()
		eq(card().chips.BIG_UPGRADE.label:GetText(), "Big upgrade")
		eq(FDCP.Reasons.Text("LABEL", "BIG_UPGRADE"), "Big upgrade")
		FDCP.Locale.SetActive("itIT")
		eq(FDCP.Reasons.Text("LABEL", "BIG_UPGRADE"), "Upgrade grande")
		eq(FDCP.Reasons.Text("LABEL", "SMALL_UPGRADE"), "Upgrade piccolo")
		eq(FDCP.Reasons.Text("LABEL", "SITUATIONAL"), "Situazionale")
	end)

	it("sends the note when the box loses the keyboard, with the answer; a note alone waits for an answer", function()
		open()
		roll()
		local note = card().note
		note.edit:SetFocus()
		Mock.TypeInto(note.edit, "two-hander, big upgrade")
		note.edit:ClearFocus()
		Mock.Advance(2)
		isNil(lastOf(sent(), "SRESP"), "no answer yet: the note waits")
		seg().buttons.MS:Click()
		local m = lastAnswer()
		eq(m.rs, "MS"); eq(m.n, "two-hander, big upgrade")
		eq(PS():MyAnswer(1).n, "two-hander, big upgrade")
		note.edit:SetFocus()
		Mock.TypeInto(note.edit, "changed my mind")
		note.edit:ClearFocus()
		m = lastAnswer()
		eq(m.n, "changed my mind"); eq(m.rs, "MS")
	end)

	it("never sends a note longer than 80 bytes", function()
		open()
		roll()
		seg().buttons.MS:Click()
		local note = card().note
		note.edit:SetFocus()
		Mock.TypeInto(note.edit, string.rep("è", 60))
		note.edit:ClearFocus()
		local m = lastAnswer()
		eq(#m.n, 80)
		eq(m.n, string.rep("è", 40))
	end)

	it("keeps the typed note while other players' answers arrive", function()
		open()
		roll()
		seg().buttons.MS:Click()
		local note = card().note
		note.edit:SetFocus()
		Mock.TypeInto(note.edit, "typing")
		Mock.chat.Receive("FDCP1", Codec():Encode("SRESP", { s = "S1-1", i = 1, r = 1, rs = "MS" }), "RAID", full("Corin"))
		eq(note.edit:GetText(), "typing")
	end)

	it("Roll waits for an answer, then calls RandomRoll(1, 100) once, and locks the answer", function()
		open()
		roll()
		falsy(card().rollButton:IsEnabled())
		falsy(P():Roll())
		eq(#Mock.loot.rolls, 0)
		seg().buttons.MS:Click()
		truthy(card().rollButton:IsEnabled())
		eq(card().rollButton.label:GetText(), "Roll")
		card().rollButton:Click()
		eq(#Mock.loot.rolls, 1)
		deepEq(Mock.loot.rolls[1], { lo = 1, hi = 100 })
		eq(card().rollButton.label:GetText(), "Rolled")
		falsy(card().rollButton:IsEnabled())
		eq(card().hint:GetText(), L("POPUP_HINT_ROLLED"))
		card().rollButton:Click()
		eq(#Mock.loot.rolls, 1, "a second click does not roll again")
		falsy(seg().enabled)
		seg().buttons.OS:Click()
		eq(seg():Active(), "MS", "the answer is locked once the player rolled")
		falsy(card().chips.BIS:IsEnabled())
		falsy(P():Choose("OS"))
	end)

	it("the note typed before Roll goes with the answer", function()
		open()
		roll()
		seg().buttons.MS:Click()
		local note = card().note
		note.edit:SetFocus()
		Mock.TypeInto(note.edit, "ring for my set")
		card().rollButton:Click()   -- the box never lost the keyboard
		Mock.Advance(2)
		eq(lastOf(sent(), "SRESP").n, "ring for my set")
		eq(#Mock.loot.rolls, 1)
	end)

	it("says so when the game does not let the addon roll", function()
		open()
		roll()
		seg().buttons.MS:Click()
		local real = _G.RandomRoll
		_G.RandomRoll = nil
		local ok = P():Roll()
		_G.RandomRoll = real
		falsy(ok)
		eq(card().hint:GetText(), L("POPUP_ERR_ROLL"):format(1, 100))
		truthy(card().rollButton:IsEnabled(), "the player may try again")
	end)

	it("says so when the answer cannot be sent, and the next click tries again", function()
		open()
		roll()
		local real = PS().Respond
		PS().Respond = function() return nil, "BUSY" end
		local ok, code = P():Choose("MS")
		PS().Respond = real
		falsy(ok); eq(code, "BUSY")
		eq(card().hint:GetText(), L("POPUP_ERR_SEND"))
		truthy(P():Choose("MS"))
		eq(card().hint:GetText(), L("POPUP_HINT_ROLL"):format(1, 100))
	end)

	it("the next tier's round is a roll-only card for who answered that tier; the others see no card", function()
		open()
		roll()
		seg().buttons.OS:Click()
		control("SCLOSE", { i = 1, r = 1 })
		falsy(P():IsShown(), "the popup closes with the round")
		control("SROLL", { i = 1, r = 2, k = "ROLL", g = "TIER", tr = 2, de = FDCP.Compat.ServerTime() + 30 })
		truthy(P():IsShown())
		falsy(card().data.collect)
		eq(card().eyebrow:GetText(), "ROLL OPEN · LUCIFRON")
		eq(seg():Active(), "OS", "the answer shows, locked")
		falsy(seg().enabled)
		falsy(card().note:IsShown())
		falsy(card().chips.BIS:IsShown())
		eq(card().hint:GetText(), L("POPUP_HINT_TURN"))
		truthy(card().rollButton:IsEnabled())
		card().rollButton:Click()
		eq(#Mock.loot.rolls, 1)
	end)

	it("closes when the round closes, and a reroll or a free roll opens a card only for who takes part", function()
		open()
		roll()
		seg().buttons.MS:Click()
		control("SCLOSE", { i = 1, r = 1 })
		falsy(P():IsShown())
		control("SROLL", { i = 1, r = 2, k = "REROLL", g = "TIER", tr = 1, am = { ML, full("Corin") },
			de = FDCP.Compat.ServerTime() + 30 })
		falsy(P():IsShown(), "not tied: nothing to roll")
		control("SCLOSE", { i = 1, r = 2 })
		control("SROLL", { i = 1, r = 3, k = "REROLL", g = "TIER", tr = 1, am = { ML, full("Bryn") },
			de = FDCP.Compat.ServerTime() + 30 })
		truthy(P():IsShown())
		eq(card().eyebrow:GetText(), "REROLL · LUCIFRON")
		eq(card().hint:GetText(), L("POPUP_HINT_REROLL"))
		card().rollButton:Click()
		eq(#Mock.loot.rolls, 1)
		control("SCLOSE", { i = 1, r = 3 })
		control("SROLL", { i = 1, r = 4, k = "ROLL", g = "FREE_ROLL", de = FDCP.Compat.ServerTime() + 30 })
		truthy(P():IsShown())
		eq(card().eyebrow:GetText(), "FREE ROLL · LUCIFRON")
		eq(card().hint:GetText(), L("POPUP_HINT_FREE"))
		truthy(card().rollButton:IsEnabled(), "a new round: the player may roll again")
	end)

	it("closes when the session ends or the player leaves the raid", function()
		open()
		roll()
		truthy(P():IsShown())
		control("SEND", {})
		falsy(P():IsShown())
		Mock.group.Leave()
		Mock.Advance(3)
		falsy(P():IsShown())
	end)

	it("counts the timer down, shows Paused, and turns amber at five seconds", function()
		open()
		roll()
		eq(card().timer:GetText(), "0:30")
		Mock.Advance(12)
		eq(card().timer:GetText(), "0:18")
		near(card().bar:GetFraction(), 18 / 30, 0.05)
		Mock.Advance(14)
		eq(card().timer:GetText(), "0:05")
		deepEq({ card().timer:GetTextColor() }, { FDCP.Theme.Color("warn") })
		control("SPAUSE", { p = true, rm = 4 })
		eq(card().timer:GetText(), L("POPUP_PAUSED"))
		Mock.Advance(10)
		eq(card().timer:GetText(), L("POPUP_PAUSED"))
		control("SPAUSE", { p = false, de = FDCP.Compat.ServerTime() + 20 })
		eq(card().timer:GetText(), "0:20")
	end)

	it("the close button hides the card for this round and the next round brings it back", function()
		open()
		roll()
		Mock.RunScript(card().close, "OnEnter")
		eq(GameTooltip:GetText(), L("POPUP_DISMISS"))
		Mock.RunScript(card().close, "OnLeave")
		falsy(GameTooltip:IsShown())
		card().close:Click()
		falsy(P():IsShown())
		control("SCLOSE", { i = 1, r = 1 })
		control("SROLL", { i = 2, r = 1, k = "ROLL", g = "TIER", tr = 1, cl = true, de = FDCP.Compat.ServerTime() + 30 })
		truthy(P():IsShown())
		eq(card().name:GetText(), "Sword of Embers")
	end)

	it("the first card carries the one neon element", function()
		open()
		roll()
		truthy(card().glow:IsShown())
	end)

	it("follows an older master looter's session that does not say the tiers", function()
		open(false)
		roll()
		deepEq(seg().order, { "MS", "OS", "PASS" })
	end)

	it("every visible text of the card comes from the locale: Italian", function()
		FDCP.Locale.SetActive("itIT")
		open()
		roll()
		eq(card().eyebrow:GetText(), "ROLL APERTO · LUCIFRON")
		eq(card().rollButton.label:GetText(), "Tira")
		eq(card().hint:GetText(), L("POPUP_HINT_CHOOSE"))
		eq(card().hint:GetText(), "Scegli la risposta, poi tira.")
		eq(card().badge.label:GetText(), "GIOIELLO · 1 CREDITO")
		eq(seg().buttons.PASS.label:GetText(), "Passo")
		eq(card().chips.BIG_UPGRADE.label:GetText(), "Upgrade grande")
		eq(card().noteCaption:GetText(), "Nota")
	end)

	it("uses the display fonts and no secure template", function()
		open()
		roll()
		eq(card().name:GetFontObject(), FDCP.Theme.Font("BodyMedium"))
		eq(card().timer:GetFontObject(), FDCP.Theme.Font("Mono"))
		for _, frame in ipairs({ P().frame, card() }) do falsy(frame._template, "no template") end
	end)

	it("the player's credits and place in the queue show when this client knows the guild's table", function()
		open()
		roll()
		eq(card().credits:GetText(), "")
		local Lg, Sn, R = FDCP.Ledger, FDCP.Season, FDCP.Roster
		local L1 = Lg.New()
		assert(Sn.Open(L1, { author = ML, ts = 1, season = "S1", instances = { { id = 409, size = 40 } } }))
		for i, p in ipairs({ { "Aurel", 73 }, { "Bryn", 65 }, { "Corin", 105 } }) do
			assert(R.Join(L1, { author = ML, ts = 2 + i, season = "S1", member = full(p[1]), faction = "Horde", ms1 = p[2] }))
		end
		assert(Lg.Append(L1, { author = ML, ts = 20, season = "S1", type = "ITEM_AWARDED", payload = { target = "member",
			member = full("Bryn"), item = 5, cost = 2, reasons = {}, flags = {} } }))
		FDCP.NightController:Bind(L1)
		P():Refresh()
		eq(card().credits:GetText(), "Your credits 2 · queue ~3")
	end)
end)

describe("position and width", function()
	before_boot(function(M)
		M.player.name, M.player.realm = "Bryn", REALM
		items(M)
	end)

	local function show()
		Mock.group.Set{ raid = true, members = { { name = "Aurel" } } }
		Mock.Advance(3)
		Mock.chat.Receive("FDCP1", Codec():Encode("SOPEN", { s = "S1-1", q = 1, ml = ML, rt = { MS = 1 },
			it = { { id = 19003, ca = "jewelry", cs = { MS = 1 } } } }), "RAID", ML)
		Mock.chat.Receive("FDCP1", Codec():Encode("SROLL", { s = "S1-1", q = 2, i = 1, r = 1, k = "ROLL", g = "TIER", tr = 1,
			cl = true }), "RAID", ML)
	end

	it("opens in the middle of the screen the first time, movable and clamped, on its own strata", function()
		show()
		local f = P().frame
		truthy(f:IsMovable()); truthy(f._clamped)
		eq(f:GetFrameStrata(), "DIALOG")
		eq(f:GetWidth(), P().DEFAULT_W)
		eq((f:GetPoint(1)), "CENTER")
	end)

	it("remembers where it was dragged, per character, across /reload", function()
		show()
		Mock.RunScript(card(), "OnDragStart", "LeftButton")   -- a card drags the whole popup
		truthy(P().frame._moving)
		P().frame:ClearAllPoints()
		P().frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -80)
		Mock.RunScript(card(), "OnDragStop")
		local saved = FDCP.Config.char.popup
		eq(saved.point, "TOPLEFT"); eq(saved.x, 120); eq(saved.y, -80)
		Mock.Reload()
		deepEq(FDCP.MemberLootPopup.LoadPlacement(), { point = "TOPLEFT", x = 120, y = -80, w = P().DEFAULT_W })
	end)

	it("remembers its width, within the bounds, and ignores a damaged placement", function()
		show()
		P().frame:SetSize(470, 300)
		P():SavePlacement()
		eq(FDCP.Config.char.popup.w, 470)
		FDCP.Config.char.popup.w = 9999
		eq(P().LoadPlacement().w, P().MAX_W)
		FDCP.Config.char.popup.w = 10
		eq(P().LoadPlacement().w, P().MIN_W)
		FDCP.Config.char.popup = { point = 3 }
		isNil(P().LoadPlacement())
	end)

	it("does not save a position when the saved data is read-only", function()
		show()
		FDCP.Config.readOnly = true
		FDCP.Config.char.popup = nil
		P():SavePlacement()
		isNil(FDCP.Config.char.popup)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The network: the answers reach the master looter

local function host(c, names)
	local h = { c = c, inputs = {}, refused = {} }
	local present = {}
	for _, n in ipairs(names) do present[full(n)] = true end
	local A = c.addon()
	local rules = A.Rules.DefaultConfig()
	rules.session.autoAdvance = false   -- the master looter opens each roll
	h.s = assert(A.SessionFSM.New({ id = "S1-1", season = "S1", ml = full(c.name), ts = A.Compat.Now(), encounter = 663,
		rules = rules, present = present, addon = present }))
	h.L = A.Ledger.New()
	A.Bus:On("SESSION_INPUT", function(_, input)
		h.inputs[#h.inputs + 1] = input
		h.step(input)
	end, h)
	A.Protocol.Session:Host(h.s)
	function h.step(input)
		input.ts = input.ts or A.Compat.Now()
		local ok, code, effects = A.SessionFSM.Step(h.s, input, { ledger = h.L })
		if not ok then h.refused[#h.refused + 1] = code return nil, code end
		A.Protocol.Session:Publish(effects, h.s)
		return true
	end
	function h.ml(kind, extra)
		local input = extra or {}
		input.type, input.by = kind, full(c.name)
		assert(h.step(input), "refused " .. kind .. ": " .. tostring(h.refused[#h.refused]))
	end
	return h
end

describe("the master looter hears the popups", function()
	local NAMES = { "Aurel", "Bryn", "Corin", "Dara" }
	local function popup(c) return c.addon().MemberLootPopup end
	local function card1(c) return popup(c).cards[1] end

	local function started()
		local net = Sim.new{ realm = REALM }
		local c = {}
		for _, n in ipairs(NAMES) do
			c[n] = net:Client(n, { setup = items })
		end
		net:Raid(NAMES)
		net:Advance(3)
		local h = host(c.Aurel, NAMES)
		h.step({ type = "LOOT_OPENED", items = { { itemID = 19003, slot = 1, classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER",
			quality = 4 } }, encounter = 663 })
		h.ml("START")
		h.ml("OPEN_ROLL")
		net:Advance(3)
		return net, c, h
	end

	it("opens a popup on every client with the addon, the master looter's included", function()
		local net, c = started()
		for _, n in ipairs(NAMES) do
			truthy(popup(c[n]):IsShown(), n .. " sees the popup")
			eq(card1(c[n]).name:GetText(), "Ring of the Keeper")
			eq(card1(c[n]).eyebrow:GetText(), "ROLL OPEN · LUCIFRON")
		end
		eq(card1(c.Bryn).badge.label:GetText(), "JEWELRY · 1 CREDIT")
	end)

	it("every answer, label and note reaches the master looter as that player's own", function()
		local net, c, h = started()
		card1(c.Bryn).chips.SITUATIONAL:Click()   -- the addon may have suggested another: this is the player's pick
		card1(c.Bryn).note.edit:SetFocus()
		c.Bryn.Mock.TypeInto(card1(c.Bryn).note.edit, "my set ring")
		card1(c.Bryn).note.edit:ClearFocus()
		card1(c.Corin).data.seg.buttons.OS:Click()
		popup(c.Dara):Choose("PASS")
		popup(c.Aurel):Choose("MS")
		net:Advance(3)
		local item = h.s.items[1]
		eq(item.responses[full("Bryn")], "MS"); eq(item.labels[full("Bryn")], "SITUATIONAL"); eq(item.notes[full("Bryn")], "my set ring")
		truthy(item.labelOrigins[full("Bryn")], "and who chose it")
		eq(item.responses[full("Corin")], "OS"); isNil(item.labels[full("Corin")])
		eq(item.responses[full("Dara")], "PASS"); isNil(item.notes[full("Dara")])
		eq(item.responses[full("Aurel")], "MS")
		eq(#h.refused, 0, tostring(h.refused[1]))
	end)

	it("a client cannot answer for another player: a forged answer is refused and counted", function()
		local net, c, h = started()
		local before = h.s.items[1].responses[full("Dara")]
		-- delivered to the master looter as if from Bryn, naming Dara
		c.Aurel.Mock.chat.Receive("FDCP1", c.Aurel.addon().Codec:Encode("SRESP", { s = "S1-1", i = 1, r = 1, rs = "MS", p = full("Dara") }),
			"RAID", full("Bryn"))
		eq(h.s.items[1].responses[full("Dara")], before)
		eq(c.Aurel.addon().Protocol.Session.stats.forged, 1)
		-- the popup itself never names a player
		card1(c.Bryn).data.seg.buttons.MS:Click()
		net:Advance(2)
		local found
		for _, e in ipairs(c.Bryn.Mock.chat.SentWithPrefix("FDCP1")) do
			local text = e.message
			if text:byte(1) == 4 then text = text:sub(2) end
			local m = c.Bryn.addon().Codec:Decode(text)
			if m and m.t == "SRESP" then found = m end
		end
		truthy(found); isNil(found.p)
	end)

	it("the roll button rolls in the game, one roll per client", function()
		local net, c, h = started()
		popup(c.Bryn):Choose("MS")
		card1(c.Bryn).rollButton:Click()
		eq(#c.Bryn.Mock.loot.rolls, 1)
		deepEq(c.Bryn.Mock.loot.rolls[1], { lo = 1, hi = 100 })
		eq(#c.Corin.Mock.loot.rolls, 0)
		-- the master looter's client reads the roll from the chat (M4-3); here the roll message is handed over by hand
		h.step({ type = "ROLL", player = full("Bryn"), value = 50, min = 1, max = 100 })
		eq(#h.s.items[1].round.rolls, 1)
	end)

	it("the popups close on every client when the round closes", function()
		local net, c, h = started()
		popup(c.Bryn):Choose("MS")
		h.step({ type = "ROLL", player = full("Bryn"), value = 50, min = 1, max = 100 })
		h.ml("CLOSE_ROUND")
		net:Advance(3)
		for _, n in ipairs(NAMES) do falsy(popup(c[n]):IsShown(), n .. " popup closed") end
	end)

	it("a player who reloads gets the card back with their answer, label and note", function()
		local net, c, h = started()
		popup(c.Bryn):SetLabel("BIS")
		net:Advance(3)
		card1(c.Bryn).note.edit:SetFocus()
		c.Bryn.Mock.TypeInto(card1(c.Bryn).note.edit, "set bonus")
		card1(c.Bryn).note.edit:ClearFocus()
		net:Advance(3)
		eq(h.s.items[1].notes[full("Bryn")], "set bonus")
		net:Reload("Bryn")
		net:Advance(6)
		truthy(popup(c.Bryn):IsShown(), "the master looter whispered the state")
		local card = card1(c.Bryn)
		eq(card.data.response, "MS"); eq(card.data.label, "BIS"); eq(card.data.note, "set bonus")
		eq(card.data.seg:Active(), "MS")
		truthy(card.chips.BIS:IsSelected())
		eq(card.note:GetText(), "set bonus")
	end)

	it("a late joiner sees the open round and may answer it", function()
		local net, c, h = started()
		c.Edda = net:Client("Edda", { setup = items })
		net:Raid({ "Aurel", "Bryn", "Corin", "Dara", "Edda" })
		net:Advance(6)
		truthy(popup(c.Edda):IsShown())
		truthy(popup(c.Edda):Choose("MS"))
		net:Advance(2)
		eq(h.refused[#h.refused], "NOT_PRESENT", "the raid of the open item was frozen: Edda comes in from the next item")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The upgrade verdicts in the card (M5-2)

local STR, STA = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT"
local function hlink(id, name) return "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[" .. name .. "]|h|r" end
local VERDICT_ITEMS = {
	{ id = 19100, link = hlink(19100, "Old Helm"), name = "Old Helm", quality = 4, equipLoc = "INVTYPE_HEAD", classID = 4,
		subclassID = 4, type = "Armor", subType = "Plate", level = 64, stats = { [STR] = 90, [STA] = 40 } },
	{ id = 19101, link = hlink(19101, "Helm of Embers"), name = "Helm of Embers", quality = 4, equipLoc = "INVTYPE_HEAD",
		classID = 4, subclassID = 4, type = "Armor", subType = "Plate", level = 70, stats = { [STR] = 100, [STA] = 50 } },
	{ id = 19120, link = hlink(19120, "Wand of Sparks"), name = "Wand of Sparks", quality = 4, equipLoc = "INVTYPE_RANGEDRIGHT",
		classID = 2, subclassID = 19, type = "Weapon", subType = "Wands", level = 70, stats = { ITEM_MOD_SPELL_POWER_SHORT = 20 } },
}
local function verdictItems(M)
	for _, def in ipairs(VERDICT_ITEMS) do M.items.Add(def) end
	M.items.equipped = { [1] = hlink(19100, "Old Helm") }
	_G.INVTYPE_HEAD, _G.INVTYPE_RANGEDRIGHT = "Head", "Ranged"
end

describe("the upgrade verdicts in the card", function()
	before_boot(function(M)
		M.player.name, M.player.realm = "Bryn", REALM
		verdictItems(M)
	end)

	local function raid()
		Mock.group.Set{ raid = true, members = { { name = "Aurel" }, { name = "Corin" } } }
		Mock.Advance(3)
	end
	local function receive(t, fields) return Mock.chat.Receive("FDCP1", Codec():Encode(t, fields), "RAID", ML) end
	local function open(itemID)
		raid()
		receive("SOPEN", { s = "S1-1", q = 1, ml = ML, e = 663, rt = { MS = 1, OS = 2 },
			it = { { id = itemID, ca = "armor", cs = { MS = 1, OS = 0 } } } })
		receive("SROLL", { s = "S1-1", q = 2, i = 1, r = 1, k = "ROLL", g = "TIER", tr = 1, cl = true,
			de = FDCP.Compat.ServerTime() + 30 })
	end

	-- the player's declared specs and the guild's rules come from a ledger bound to the client
	local function declare(ms1, ms2, rules)
		local Lg, Sn, R = FDCP.Ledger, FDCP.Season, FDCP.Roster
		Mock.guild.Set({ name = "Keepers", ranks = { [0] = "Guild Master", "Officer" }, myRank = 1, members = {
			{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 } } })
		local L1 = Lg.New()
		assert(Sn.Open(L1, { author = ML, ts = 1, season = "S1", instances = { { id = 409, size = 40 } } }))
		assert(R.Join(L1, { author = ML, ts = 2, season = "S1", member = full("Bryn"), faction = "Horde", ms1 = ms1, ms2 = ms2 }))
		if rules then assert(FDCP.Rules.Change(L1, { author = ML, ts = 3, rules = rules, confirmed = true })) end
		FDCP.NightController:Bind(L1)
		FDCP.UpgradeAdvisor.Reset()
	end

	it("shows how much of an upgrade the item is for the main-spec, in the player's words", function()
		open(19101)
		local v = card().verdicts
		truthy(v.ms:IsShown())
		eq(v.ms.label:GetText(), "Main-spec · Big upgrade +11.7% · ilvl +6")
		falsy(v.os:IsShown(), "no declared off-spec: no second line")
		eq(card().data.upgrade.ms.verdict, "BIG")
	end)

	it("speaks Italian with the decimal comma", function()
		FDCP.Locale.SetActive("itIT")
		open(19101)
		eq(card().verdicts.ms.label:GetText(), "Main-spec · Upgrade grande +11,7% · ilvl +6")
	end)

	it("the tooltip says the verdict, what it was compared on, what is worn and the limits", function()
		open(19101)
		Mock.RunScript(card().verdicts.ms, "OnEnter")
		truthy(GameTooltip:IsShown())
		local lines = GameTooltip._lines
		eq(lines[1], L("UPG_BASIS_STATS"))
		contains(lines[2], "Old Helm")
		eq(lines[3], L("UPG_LIMITS"))
		Mock.RunScript(card().verdicts.ms, "OnLeave")
		falsy(GameTooltip:IsShown())
	end)

	it("an item the character cannot use comes with Pass preselected, and nothing is sent by itself", function()
		open(19120)
		eq(card().verdicts.ms.label:GetText(), "Main-spec · Not usable")
		eq(card().data.preselect, "PASS")
		eq(card().data.hint, "UNUSABLE")
		eq(card().hint:GetText(), L("POPUP_HINT_UNUSABLE"))
		isNil(seg():Active(), "a preselection is not an answer")
		eq(card().data.response, nil)
		falsy(card().data.canRoll, "no answer, no roll")
		Mock.Advance(2)
		eq(count(sentMessages(Mock), "SRESP"), 0)
	end)

	it("clicking the preselected Pass sends it, with the verdict", function()
		open(19120)
		seg().buttons.PASS:Click()
		Mock.Advance(2)
		local m = lastOf(sentMessages(Mock), "SRESP")
		truthy(m); eq(m.rs, "PASS")
		deepEq(m.vd, { m = { v = "NONE", u = false, c = "WEAPON_TYPE" } })
	end)

	it("the player may answer main-spec on an item that was preselected as Pass", function()
		open(19120)
		seg().buttons.MS:Click()
		Mock.Advance(2)
		eq(lastOf(sentMessages(Mock), "SRESP").rs, "MS")
		eq(card().data.hint, "ROLL")
		eq(card().data.preselect, nil, "an answer is given")
	end)

	it("every answer carries the verdicts and the worn pieces to the master looter", function()
		open(19101)
		seg().buttons.MS:Click()
		Mock.Advance(2)
		local m = lastOf(sentMessages(Mock), "SRESP")
		deepEq(m.vd, { m = { v = "BIG", b = "STATS", p = 117, l = 6 } })
		deepEq(m.eq, { "item:19100::::::::70:::::" })
		-- a label sent later carries them again
		P():SetLabel("BIS")
		Mock.Advance(2)
		m = lastOf(sentMessages(Mock), "SRESP")
		eq(m.lb, "BIS")
		eq(m.vd.m.v, "BIG")
	end)

	it("the window does not wait for an item whose data is not loaded, and shows the verdict when it arrives", function()
		Mock.items.Add{ id = 19160, link = hlink(19160, "Late Helm"), name = "Late Helm", quality = 4, equipLoc = "INVTYPE_HEAD",
			classID = 4, subclassID = 4, level = 70, stats = { [STR] = 100 }, cached = false }
		open(19160)
		falsy(card().verdicts.ms:IsShown(), "no data yet")
		Mock.Advance(1)
		truthy(card().verdicts.ms:IsShown())
	end)

	it("redraws when the player puts a better piece on", function()
		open(19101)
		eq(card().data.upgrade.ms.verdict, "BIG")
		Mock.items.Add{ id = 19102, link = hlink(19102, "Better Helm"), name = "Better Helm", quality = 4, equipLoc = "INVTYPE_HEAD",
			classID = 4, subclassID = 4, level = 72, stats = { [STR] = 130, [STA] = 50 } }
		Mock.items.equipped[1] = hlink(19102, "Better Helm")
		Mock.Fire("PLAYER_EQUIPMENT_CHANGED", 1, false)
		eq(card().data.upgrade.ms.verdict, "NONE")
		eq(card().verdicts.ms.label:GetText(), "Main-spec · No upgrade -22.2% · ilvl -2")
	end)

	it("shows no verdict when the guild's rules turn them off", function()
		local rules = FDCP.Rules.DefaultConfig()
		rules.upgrade.enabled = false
		declare(72, nil, rules)
		open(19101)
		falsy(card().verdicts.ms:IsShown())
		isNil(card().data.upgrade)
		seg().buttons.MS:Click()
		Mock.Advance(2)
		local m = lastOf(sentMessages(Mock), "SRESP")
		isNil(m.vd); isNil(m.eq)
	end)

	it("the two specs get a line each when the player declared an off-spec", function()
		declare(72, 73)
		open(19101)
		truthy(card().verdicts.ms:IsShown()); truthy(card().verdicts.os:IsShown())
		eq(card().verdicts.ms.label:GetText(), "Main-spec · Big upgrade +11.7% · ilvl +6")
		eq(card().verdicts.os.label:GetText():find("Off-spec", 1, true), 1)
		local msY = select(5, card().verdicts.ms:GetPoint(1))
		local osY = select(5, card().verdicts.os:GetPoint(1))
		truthy(osY < msY, "the off-spec line is under the main-spec one")
	end)
end)

describe("the master looter sees the verdicts of the raid", function()
	local NAMES = { "Aurel", "Bryn", "Corin" }
	local function popup(c) return c.addon().MemberLootPopup end

	local function started()
		local net = Sim.new{ realm = REALM }
		local c = {}
		for _, n in ipairs(NAMES) do c[n] = net:Client(n, { setup = verdictItems }) end
		-- Corin wears a better helm than the one on offer
		c.Corin.Mock.items.Add{ id = 19102, link = hlink(19102, "Better Helm"), name = "Better Helm", quality = 4,
			equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 4, level = 72, stats = { [STR] = 130, [STA] = 50 } }
		c.Corin.Mock.items.equipped = { [1] = hlink(19102, "Better Helm") }
		c.Aurel.Mock.items.Add{ id = 19102, link = hlink(19102, "Better Helm"), name = "Better Helm", quality = 4,
			equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 4, level = 72, stats = { [STR] = 130, [STA] = 50 }, cached = false }
		net:Raid(NAMES)
		net:Advance(3)
		local h = host(c.Aurel, NAMES)
		h.step({ type = "LOOT_OPENED", items = { { itemID = 19101, slot = 1, classID = 4, subclassID = 4, equipLoc = "INVTYPE_HEAD",
			quality = 4 } }, encounter = 663 })
		h.ml("START")
		h.ml("OPEN_ROLL")
		net:Advance(3)
		return net, c, h
	end

	it("each answer brings the player's own verdict and worn piece, passes included", function()
		local net, c, h = started()
		popup(c.Bryn):Choose("MS")
		popup(c.Corin):Choose("PASS")
		popup(c.Aurel):Choose("OS")
		net:Advance(3)
		local item = h.s.items[1]
		eq(item.verdicts[full("Bryn")].m.v, "BIG")
		eq(item.verdicts[full("Bryn")].m.p, 117)
		deepEq(item.equipped[full("Bryn")], { "item:19100::::::::70:::::" })
		eq(item.verdicts[full("Corin")].m.v, "NONE", "Corin wears a better helm and passes: the verdict still comes")
		eq(item.verdicts[full("Corin")].m.l, -2)
		deepEq(item.equipped[full("Corin")], { "item:19102::::::::70:::::" })
		eq(item.verdicts[full("Aurel")].m.v, "BIG")
		eq(#h.refused, 0, tostring(h.refused[1]))
	end)

	it("the candidates' board carries them, ready for the Upgrade column and its tooltip", function()
		local net, c, h = started()
		popup(c.Bryn):Choose("MS")
		popup(c.Corin):Choose("MS")
		net:Advance(3)
		local A = c.Aurel.addon()
		local board = A.SessionBoard.Build({ host = true, session = h.s }, { now = A.Compat.Now() })
		local by = {}
		for _, row in ipairs(board.candidates) do by[row.player] = row end
		eq(A.UpgradeAdvisor.Text(by[full("Bryn")].upgrade), "Big upgrade +11.7% · ilvl +6")
		eq(A.UpgradeAdvisor.Text(by[full("Corin")].upgrade), "No upgrade -22.2% · ilvl -2")
		deepEq(A.UpgradeAdvisor.EquippedNames(by[full("Corin")].equipped), {}, "the master looter's client has not loaded it yet: asked")
		net:Advance(1)
		deepEq(A.UpgradeAdvisor.EquippedNames(by[full("Corin")].equipped), { "Better Helm" })
	end)

	it("a client of protocol 2 that sends no verdict is heard all the same", function()
		local net, c, h = started()
		c.Aurel.Mock.chat.Receive("FDCP1", c.Aurel.addon().Codec:Encode("SRESP", { s = "S1-1", i = 1, r = 1, rs = "MS" }),
			"RAID", full("Corin"))
		eq(h.s.items[1].responses[full("Corin")], "MS")
		isNil(h.s.items[1].verdicts[full("Corin")])
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- Who picks the label (M7-2b): the guild's rule responses.labelMode, as the master looter's SOPEN carries it

describe("the label of a main-spec answer follows the guild's mode", function()
	before_boot(function(M)
		M.player.name, M.player.realm = "Bryn", REALM
		verdictItems(M)
	end)

	local function raid()
		Mock.group.Set{ raid = true, members = { { name = "Aurel" }, { name = "Corin" } } }
		Mock.Advance(3)
	end
	local function receive(t, fields) return Mock.chat.Receive("FDCP1", Codec():Encode(t, fields), "RAID", ML) end
	-- `mode` nil = a master looter of protocol 4 or less, which says nothing
	local function open(itemID, mode)
		raid()
		receive("SOPEN", { s = "S1-1", q = 1, ml = ML, e = 663, rt = { MS = 1, OS = 2 }, lm = mode,
			it = { { id = itemID, ca = "armor", cs = { MS = 1, OS = 0 } } } })
		receive("SROLL", { s = "S1-1", q = 2, i = 1, r = 1, k = "ROLL", g = "TIER", tr = 1, cl = true,
			de = FDCP.Compat.ServerTime() + 30 })
	end
	local function lastAnswer()
		Mock.Advance(2)
		return lastOf(sentMessages(Mock), "SRESP")
	end
	local BIG, WAND = 19101, 19120   -- a big upgrade for the player, an item the character cannot use

	it("auto: the addon sets the label from the verdict, the chips are locked and the hint says so", function()
		open(BIG, "auto")
		local c = card()
		eq(c.data.labelMode, "auto"); eq(c.data.label, "BIG_UPGRADE"); eq(c.data.labelOrigin, "AUTO")
		truthy(c.chips.BIG_UPGRADE:IsSelected())
		for _, chip in pairs(c.chips) do falsy(chip:IsEnabled()) end
		truthy(c.labelHint:IsShown()); eq(c.labelHint:GetText(), L("POPUP_LABEL_AUTO"))
		c.chips.BIS:Click()
		isNil(lastAnswer(), "a locked chip sends nothing")
		seg().buttons.MS:Click()
		local m = lastAnswer()
		eq(m.rs, "MS"); eq(m.lb, "BIG_UPGRADE"); eq(m.lo, "AUTO")
		seg().buttons.OS:Click()
		m = lastAnswer()
		eq(m.rs, "OS"); isNil(m.lb); isNil(m.lo)
		falsy(card().chips.BIG_UPGRADE:IsSelected(), "off-spec carries no label")
		seg().buttons.MS:Click()
		m = lastAnswer()
		eq(m.lb, "BIG_UPGRADE"); eq(m.lo, "AUTO", "main-spec again: the addon's label comes back")
	end)

	it("auto: an item on the wishlist is BiS, and one with nothing to say has no label", function()
		FDCP.PersonalUpgrade.WishAdd(BIG)
		open(BIG, "auto")
		eq(card().data.label, "BIS")
		seg().buttons.MS:Click()
		eq(lastAnswer().lb, "BIS")
	end)

	it("auto: an item with no verdict to speak of is answered without a label", function()
		open(WAND, "auto")
		isNil(card().data.label)
		truthy(card().labelHint:IsShown(), "the player still learns why the chips are locked")
		seg().buttons.MS:Click()
		local m = lastAnswer()
		eq(m.rs, "MS"); isNil(m.lb); isNil(m.lo)
	end)

	it("suggest: the label is filled in beforehand and goes with the main-spec answer as the addon's", function()
		open(BIG, "suggest")
		local c = card()
		eq(c.data.label, "BIG_UPGRADE"); truthy(c.chips.BIG_UPGRADE:IsSelected())
		for _, chip in pairs(c.chips) do truthy(chip:IsEnabled()) end
		eq(c.labelHint:GetText(), L("POPUP_LABEL_SUGGEST"))
		Mock.Advance(2)
		isNil(lastOf(sentMessages(Mock), "SRESP"), "a suggestion is not an answer: nothing is sent by itself")
		seg().buttons.MS:Click()
		local m = lastAnswer()
		eq(m.rs, "MS"); eq(m.lb, "BIG_UPGRADE"); eq(m.lo, "AUTO")
	end)

	it("suggest: another label is a change, the same one is not, clearing it is final", function()
		open(BIG, "suggest")
		card().chips.SITUATIONAL:Click()
		local m = lastAnswer()
		eq(m.rs, "MS"); eq(m.lb, "SITUATIONAL"); eq(m.lo, "CHANGED")
		truthy(card().chips.SITUATIONAL:IsSelected()); falsy(card().chips.BIG_UPGRADE:IsSelected())
		card().chips.BIG_UPGRADE:Click()
		m = lastAnswer()
		eq(m.lb, "BIG_UPGRADE"); eq(m.lo, "AUTO", "the player picked what the addon had suggested")
		card().chips.BIG_UPGRADE:Click()
		m = lastAnswer()
		isNil(m.lb); isNil(m.lo)
		falsy(card().chips.BIG_UPGRADE:IsSelected(), "taken off: the suggestion does not come back by itself")
		seg().buttons.OS:Click()
		seg().buttons.MS:Click()
		m = lastAnswer()
		eq(m.rs, "MS"); isNil(m.lb, "the player took the label off, and says no again")
	end)

	it("suggest: back to main-spec from off-spec brings the suggestion back if the player never touched it", function()
		open(BIG, "suggest")
		seg().buttons.OS:Click()
		isNil(lastAnswer().lb)
		seg().buttons.MS:Click()
		local m = lastAnswer()
		eq(m.lb, "BIG_UPGRADE"); eq(m.lo, "AUTO")
	end)

	it("suggest: with nothing to suggest the player's own pick is a plain choice", function()
		open(WAND, "suggest")
		isNil(card().data.label)
		falsy(card().labelHint:IsShown())
		card().chips.BIS:Click()
		local m = lastAnswer()
		eq(m.lb, "BIS"); eq(m.lo, "MANUAL")
	end)

	local function playersOwn(mode)
		open(BIG, mode)
		local c = card()
		isNil(c.data.label); falsy(c.labelHint:IsShown())
		for _, chip in pairs(c.chips) do truthy(chip:IsEnabled()) end
		c.chips.SITUATIONAL:Click()
		local m = lastAnswer()
		eq(m.rs, "MS"); eq(m.lb, "SITUATIONAL"); eq(m.lo, "MANUAL")
	end

	it("manual: as before, the player's own", function() playersOwn("manual") end)

	it("a master looter that says nothing (protocol 4 or less) leaves the label to the player too", function() playersOwn(nil) end)

	it("a player who reloads gets the card back with the label and who chose it", function()
		open(BIG, "suggest")
		card().chips.SITUATIONAL:Click()
		Mock.Advance(2)
		local v = FDCP.Protocol.Session.view
		eq(v.labelMode, "suggest")
		local mine = FDCP.Protocol.Session:MyAnswer(1)
		eq(mine.lb, "SITUATIONAL"); eq(mine.lo, "CHANGED")
		P().draft = nil
		P():Refresh()
		eq(card().data.label, "SITUATIONAL"); eq(card().data.labelOrigin, "CHANGED")
	end)

	it("speaks Italian", function()
		FDCP.Locale.SetActive("itIT")
		open(BIG, "auto")
		eq(card().labelHint:GetText(), "L'addon imposta questa etichetta dal tuo equipaggiamento e dalla tua lista BiS.")
		eq(card().chips.BIG_UPGRADE.label:GetText(), "Upgrade grande")
	end)
end)
