-- Council flags (M5-4): Domain/Flags.lua ("upgrade ignored" and "possible waste", docs/ANALISI.md §5.2, §6), their
-- settings in the rules' council section, the state machine that writes them with the proposal (they never change the
-- winner; an "auto" award waits for the master looter) and the board that shows them before the round closes. Pure
-- domain code plus the board's plain data.
local function Fl() return FDCP.Flags end
local function F() return FDCP.SessionFSM end
local function Lg() return FDCP.Ledger end
local function SBd() return FDCP.SessionBoard end

-- Wire badges (SRESP `vd`, M7-5c): a tier and the item-level difference l.
local function big(l, extra)
	local w = { v = "MAJOR", l = l }
	for k, v in pairs(extra or {}) do w[k] = v end
	return w
end
local function small(l) return { v = "MINOR", l = l } end
local function none(l) return { v = "NONE", l = l } end

local MAIN = { MS = true }

local function eval(input, upgrade, council)
	input.main = input.main or MAIN
	return Fl().Evaluate(input, upgrade, council)
end

local function codes(list)
	local out = {}
	for i, f in ipairs(list) do out[i] = f.code .. ":" .. f.player .. (f.other and (">" .. f.other) or "") end
	return out
end

local function council(changes)
	local c = FDCP.Rules.DefaultConfig().council
	for k, v in pairs(changes or {}) do c[k] = v end
	return c
end

describe("upgrade ignored", function()
	it("fires on a pass over a major main-spec upgrade", function()
		local list = eval({ responses = { Bryn = "PASS" }, verdicts = { Bryn = { m = big(120) } } })
		deepEq(codes(list), { "UPGRADE_IGNORED:Bryn" })
		eq(list[1].response, "PASS")
		eq(list[1].ilvl, 120)
	end)

	it("fires on a player who has not answered when a verdict is known", function()
		local list = eval({ responses = {}, verdicts = { Bryn = { m = big(120) } } })
		deepEq(codes(list), { "UPGRADE_IGNORED:Bryn" })
		isNil(list[1].response)
	end)

	it("never fires on who answers, whatever the answer", function()
		local list = eval({ responses = { Aurel = "MS", Bryn = "OS", Corin = "TMOG" },
			verdicts = { Aurel = { m = big(120) }, Bryn = { m = big(120) }, Corin = { m = big(120) } } })
		deepEq(codes(list), {})
	end)

	it("never fires on the off-spec verdict (MS2)", function()
		local list = eval({ responses = { Bryn = "PASS" }, verdicts = { Bryn = { m = none(0), o = big(300) } } })
		deepEq(codes(list), {})
	end)

	it("never fires on a medium or minor upgrade, nor on an old client's BIG", function()
		-- a pass on a medium one is M7-5d's roll-cheating case UPGRADE_PASSED (Tests/test_cheat.lua), not this flag
		deepEq(codes(eval({ responses = { Bryn = "PASS" }, verdicts = { Bryn = { m = { v = "MEDIUM", l = 30 } } } })),
			{ "CHEAT:Bryn" })
		deepEq(codes(eval({ responses = { Bryn = "PASS" }, verdicts = { Bryn = { m = small(40) } } })), {})
		deepEq(codes(eval({ responses = { Bryn = "PASS" }, verdicts = { Bryn = { m = { v = "BIG", p = 120 } } } })), {},
			"a verdict of a client older than M7-5c is not read")
	end)

	it("a major upgrade without an item-level difference (an empty slot) stays major", function()
		deepEq(codes(eval({ responses = { Bryn = "PASS" }, verdicts = { Bryn = { m = { v = "MAJOR", c = "EMPTY_SLOT" } } } })),
			{ "UPGRADE_IGNORED:Bryn" })
	end)

	it("never fires on a piece the player cannot use, nor on a damaged verdict", function()
		deepEq(codes(eval({ responses = { Bryn = "PASS" }, verdicts = { Bryn = { m = big(120, { u = false }) } } })), {})
		deepEq(codes(eval({ responses = { Bryn = "PASS" }, verdicts = { Bryn = { m = "BIG" } } })), {})
		deepEq(codes(eval({ responses = { Bryn = "PASS" }, verdicts = { Bryn = "x" } })), {})
		deepEq(codes(eval({ responses = { Bryn = "PASS" }, verdicts = { Bryn = { o = big(120) } } })), {})
	end)

	it("only counts the players who may roll", function()
		local input = { responses = { Bryn = "PASS", Corin = "PASS" },
			verdicts = { Bryn = { m = big(120) }, Corin = { m = big(120) } }, players = { Corin = true } }
		deepEq(codes(eval(input)), { "UPGRADE_IGNORED:Corin" })
	end)

	it("lists several players by name", function()
		local list = eval({ responses = { Corin = "PASS", Aurel = "PASS" },
			verdicts = { Corin = { m = big(120) }, Aurel = { m = big(200) } } })
		deepEq(codes(list), { "UPGRADE_IGNORED:Aurel", "UPGRADE_IGNORED:Corin" })
	end)

	it("says nothing when the rules turn the flags off", function()
		deepEq(codes(eval({ responses = { Bryn = "PASS" }, verdicts = { Bryn = { m = big(120) } } }, nil,
			council({ flags = false }))), {})
	end)
end)

describe("possible waste", function()
	-- Aurel is first in line (fewer credits), Corin second.
	local function line(first, second, extra)
		local input = { responses = { Aurel = "MS", Corin = "MS" }, verdicts = { Aurel = { m = first }, Corin = { m = second } },
			credits = { Aurel = 0, Corin = 2 } }
		for k, v in pairs(extra or {}) do input[k] = v end
		return input
	end

	it("fires when the first in line has a small upgrade and another candidate a big one", function()
		local list = eval(line(small(15), big(90)))
		deepEq(codes(list), { "POSSIBLE_WASTE:Aurel>Corin" })
		eq(list[1].ilvl, 15)
		eq(list[1].otherIlvl, 90)
	end)

	it("fires when the first in line gains nothing", function()
		deepEq(codes(eval(line(none(0), big(90)))), { "POSSIBLE_WASTE:Aurel>Corin" })
		deepEq(codes(eval(line(none(-20), big(60)))), { "POSSIBLE_WASTE:Aurel>Corin" })
		deepEq(codes(eval(line(none(), big(60)))), { "POSSIBLE_WASTE:Aurel>Corin" })
	end)

	it("needs the configurable ratio between the two", function()
		deepEq(codes(eval(line(small(40), big(60)))), {}, "+60 is not twice +40")
		deepEq(codes(eval(line(small(30), big(60)))), { "POSSIBLE_WASTE:Aurel>Corin" }, "exactly twice")
		deepEq(codes(eval(line(small(40), big(60)), nil, council({ wasteRatio = 1.5 }))), { "POSSIBLE_WASTE:Aurel>Corin" })
		deepEq(codes(eval(line(small(15), big(90)), nil, council({ wasteRatio = 10 }))), {})
	end)

	it("never fires when the other one is not major, or the first one already is", function()
		deepEq(codes(eval(line(small(10), small(45)))), {}, "the other one is not major")
		deepEq(codes(eval(line(small(10), { v = "MEDIUM", l = 45 }))), {}, "a medium upgrade is not major")
		deepEq(codes(eval(line(big(60), big(200)))), {}, "the first one already has a major upgrade")
		deepEq(codes(eval(line({ v = "MEDIUM", l = 10 }, big(200)))), {}, "a medium upgrade is not a waste")
	end)

	it("never fires on MS2: off-spec answers and off-spec verdicts do not count", function()
		local input = line(small(10), big(200))
		input.responses.Corin = "OS"
		deepEq(codes(eval(input)), {}, "Corin answered off-spec")
		input = line(small(10), none(0))
		input.verdicts.Corin.o = big(300)
		deepEq(codes(eval(input)), {}, "only Corin's off-spec gains")
		input = line({ v = "MINOR", l = 10 }, big(200))
		input.verdicts.Aurel.o = big(300)
		deepEq(codes(eval(input)), { "POSSIBLE_WASTE:Aurel>Corin" }, "Aurel's off-spec verdict is not read")
	end)

	it("says nothing when the first in line cannot be compared or cannot use it", function()
		deepEq(codes(eval(line({ v = "NOT_COMPARABLE" }, big(200)))), {})
		deepEq(codes(eval(line({ v = "NONE", u = false, c = "ARMOR_TYPE" }, big(200)))), {})
		deepEq(codes(eval(line(nil, big(200)))), {}, "no verdict from the first in line")
	end)

	it("names the candidate with the most to gain", function()
		local input = line(small(10), big(90))
		input.responses.Bryn, input.verdicts.Bryn, input.credits.Bryn = "MS", { m = big(150) }, 3
		local list = eval(input)
		deepEq(codes(list), { "POSSIBLE_WASTE:Aurel>Bryn" })
		eq(list[1].otherIlvl, 150)
	end)

	it("follows the rules' winner once the proposal is written", function()
		deepEq(codes(eval(line(small(10), big(90), { head = "Aurel", decided = true }))), { "POSSIBLE_WASTE:Aurel>Corin" })
		-- the rules chose Corin (a reroll, the credits per night...): Corin is first, with the big upgrade
		deepEq(codes(eval(line(small(10), big(90), { head = "Corin", decided = true }))), {})
		-- the item went elsewhere (off-spec tier, bank, the master looter's choice): nobody of the line is first
		deepEq(codes(eval(line(small(10), big(90), { head = nil, decided = true }))), {})
		deepEq(codes(eval(line(small(10), big(90), { head = "Bank", decided = true }))), {})
	end)

	it("comes after the upgrade-ignored flags", function()
		local input = line(small(10), big(90))
		input.responses.Bryn, input.verdicts.Bryn = "PASS", { m = big(70) }
		deepEq(codes(eval(input)), { "UPGRADE_IGNORED:Bryn", "POSSIBLE_WASTE:Aurel>Corin" })
	end)
end)

describe("the line and the helpers", function()
	it("orders the full-cost tier: head, fewer credits, higher roll, name", function()
		local input = { responses = { Aurel = "MS", Bryn = "MS", Corin = "MS", Dara = "OS", Edda = "PASS", Fenn = "MS" },
			main = MAIN, credits = { Aurel = 1, Bryn = 0, Corin = 1, Fenn = 1 }, rolls = { Aurel = 40, Corin = 80 } }
		deepEq(Fl().Line(input), { "Bryn", "Corin", "Aurel", "Fenn" })
		input.head = "Fenn"
		deepEq(Fl().Line(input), { "Fenn", "Bryn", "Corin", "Aurel" })
		input.players = { Aurel = true, Corin = true }
		deepEq(Fl().Line(input), { "Corin", "Aurel" })
	end)

	it("Codes and ByPlayer", function()
		local list = { { code = "UPGRADE_IGNORED", player = "Bryn" }, { code = "UPGRADE_IGNORED", player = "Dara" },
			{ code = "POSSIBLE_WASTE", player = "Aurel", other = "Bryn" } }
		deepEq(Fl().Codes(list), { "UPGRADE_IGNORED", "POSSIBLE_WASTE" })
		local by = Fl().ByPlayer(list)
		deepEq(by.Bryn, { "UPGRADE_IGNORED", "POSSIBLE_WASTE" })
		deepEq(by.Aurel, { "POSSIBLE_WASTE" })
		deepEq(by.Dara, { "UPGRADE_IGNORED" })
	end)

	it("who may see the verdicts and the flags", function()
		local function see(v, who) return Fl().MaySee(council({ verdicts = v }), who) end
		truthy(see("ml", { ml = true }))
		truthy(see("council", { ml = true }))
		truthy(see("council", { council = true }))
		falsy(see("council", { officer = true }))
		truthy(see("officers", { officer = true }))
		falsy(see("officers", { council = true }))
		falsy(see("ml", { council = true, officer = true }))
		falsy(Fl().MaySee(council(), nil))
	end)
end)

describe("the settings in the rules", function()
	local function problems(mutate)
		local c = FDCP.Rules.DefaultConfig()
		mutate(c)
		local ok, list = FDCP.Rules.Validate(c)
		return ok, table.concat(list, ",")
	end

	it("has the presets: flags on, ratio 2, verdicts to the council", function()
		local c = FDCP.Rules.DefaultConfig().council
		eq(c.flags, true)
		eq(c.wasteRatio, 2)
		eq(c.verdicts, "council")
		truthy(FDCP.Rules.Validate(FDCP.Rules.DefaultConfig()))
	end)

	it("refuses bad values", function()
		local ok, list = problems(function(c) c.council.flags = "yes" end)
		falsy(ok); eq(list, "council.flags")
		ok, list = problems(function(c) c.council.wasteRatio = 0.5 end)
		falsy(ok); eq(list, "council.wasteRatio")
		ok, list = problems(function(c) c.council.wasteRatio = 0 / 0 end)
		falsy(ok); eq(list, "council.wasteRatio")
		ok, list = problems(function(c) c.council.verdicts = "raid" end)
		falsy(ok); eq(list, "council.verdicts")
		truthy((problems(function(c) c.council.verdicts = "officers"; c.council.wasteRatio = 1 end)))
	end)

	it("fills the new keys for rules written before M5-4", function()
		local c = FDCP.Rules.WithDefaults({ council = { requirePresent = false, vote = true } })
		eq(c.council.flags, true)
		eq(c.council.wasteRatio, 2)
		eq(c.council.verdicts, "council")
		eq(c.council.vote, true)
		truthy(FDCP.Rules.Validate(c))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The state machine and the board

local ML = "Dara"
local RAID = { Aurel = true, Bryn = true, Corin = true, Dara = true }
local RING = { itemID = 19003, slot = 1, classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER", quality = 4 }

local function bench(opts)
	opts = opts or {}
	local b = { L = Lg().New(), t = 1000 }
	local rules = FDCP.Rules.DefaultConfig()
	rules.session.autoAdvance = false
	if opts.rules then opts.rules(rules) end
	b.s = assert(F().New({ id = "S1-1", season = "S1", ml = ML, ts = 1000, encounter = 601, rules = rules,
		present = opts.present or RAID, addon = opts.addon or RAID }))
	local credits = opts.credits or { Aurel = 0, Bryn = 1, Corin = 2, Dara = 3 }
	function b.step(input)
		input.ts = input.ts or b.t
		return F().Step(b.s, input, { ledger = b.L, credits = credits })
	end
	function b.ml(kind, extra)
		local input = extra or {}
		input.type, input.by = kind, ML
		local ok, code = b.step(input)
		if not ok then error("refused " .. kind .. ": " .. tostring(code), 2) end
	end
	function b.respond(player, response, vd)
		local ok, code = b.step({ type = "RESPONSE", player = player, response = response, verdict = vd })
		if not ok then error("refused response: " .. tostring(code), 2) end
	end
	function b.roll(player, value) assert(b.step({ type = "ROLL", player = player, value = value, min = 1, max = 100 })) end
	function b.item() return b.s.items[b.s.active or 1] end
	function b.open()
		assert(b.step({ type = "LOOT_OPENED", items = { RING }, encounter = 601 }))
		b.ml("START")
		b.ml("OPEN_ROLL")
	end
	function b.board() return SBd().Build({ host = true, session = b.s }, { now = b.t }) end
	return b
end

local function has(list, value)
	for _, v in ipairs(list or {}) do if v == value then return true end end
	return false
end

describe("in the session", function()
	it("shows 'upgrade ignored' as soon as the pass arrives, before the round closes", function()
		local b = bench()
		b.open()
		b.respond("Bryn", "PASS", { m = big(120) })
		eq(b.s.state, "ROLLING")
		deepEq(codes(F().Flags(b.s, 1)), { "UPGRADE_IGNORED:Bryn" })
		local board = b.board()
		deepEq(codes(board.flags), { "UPGRADE_IGNORED:Bryn" })
		eq(board.flags[1].verdict.verdict, "MAJOR")
		eq(board.flags[1].verdict.ilvlDelta, 120)
		local rows = {}
		for _, r in ipairs(board.candidates) do rows[r.player] = r end
		deepEq(rows.Bryn.flags, { "UPGRADE_IGNORED" })
		isNil(rows.Aurel.flags)
		eq(SBd().FlagLine(board.flags[1]), FDCP.L["ML_FLAG_IGNORED_PASS"]:format("Bryn", "Major upgrade · ilvl +120"))
	end)

	it("a player who changes the pass into a main-spec answer is no longer flagged", function()
		local b = bench()
		b.open()
		b.respond("Bryn", "PASS", { m = big(120) })
		b.respond("Bryn", "MS", { m = big(120) })
		deepEq(codes(F().Flags(b.s, 1)), {})
	end)

	it("writes the flags with the proposal, never changes the winner, and the award keeps the codes", function()
		local b = bench()
		b.open()
		b.respond("Aurel", "MS", { m = small(10) })
		b.respond("Corin", "MS", { m = big(90) })
		b.respond("Bryn", "PASS", { m = big(120) })
		b.respond("Dara", "OS", { m = none(0), o = big(300) })
		b.roll("Aurel", 12); b.roll("Corin", 99)
		b.ml("CLOSE_ROUND")
		local item = b.item()
		eq(item.state, "PROPOSAL")
		eq(item.proposal.winner, "Aurel", "fewer credits wins: the flags change nothing")
		truthy(has(item.proposal.flags, "UPGRADE_IGNORED"))
		truthy(has(item.proposal.flags, "POSSIBLE_WASTE"))
		deepEq(codes(item.flagged), { "UPGRADE_IGNORED:Bryn", "POSSIBLE_WASTE:Aurel>Corin" })
		local board = b.board()
		deepEq(codes(board.flags), { "UPGRADE_IGNORED:Bryn", "POSSIBLE_WASTE:Aurel>Corin" })
		eq(SBd().FlagLine(board.flags[2]), FDCP.L["ML_FLAG_WASTE"]:format("Aurel", "Minor upgrade · ilvl +10", "Corin",
			"Major upgrade · ilvl +90"))
		-- the strip does not say the council's codes twice
		local plain = SBd().FlagTexts(board.proposal, board.flags)
		falsy(has(plain, FDCP.L["RC_FLAG_UPGRADE_IGNORED"]))
		truthy(has(SBd().FlagTexts(board.proposal), FDCP.L["RC_FLAG_UPGRADE_IGNORED"]))
		b.ml("CONFIRM")
		local awards = Lg().Sorted(b.L, function(e) return e.type == "ITEM_AWARDED" end)
		eq(#awards, 1)
		local payload = Lg().Payload(awards[1])
		eq(payload.member, "Aurel")
		truthy(has(payload.flags, "UPGRADE_IGNORED"))
		truthy(has(payload.flags, "POSSIBLE_WASTE"))
		-- an assigned item still shows the flags it was awarded with
		deepEq(codes(SBd().Build({ host = true, session = b.s }, { now = b.t }, 1).flags),
			{ "UPGRADE_IGNORED:Bryn", "POSSIBLE_WASTE:Aurel>Corin" })
	end)

	it("the master looter may still give it to the other candidate, with a reason: the flag stays for the audit", function()
		local b = bench()
		b.open()
		b.respond("Aurel", "MS", { m = small(10) })
		b.respond("Corin", "MS", { m = big(90) })
		b.roll("Aurel", 12); b.roll("Corin", 99)
		b.ml("CLOSE_ROUND")
		b.ml("MODIFY", { winner = "Corin", reason = "OBVIOUS_WASTE" })
		local p = b.item().proposal
		eq(p.winner, "Corin")
		truthy(has(p.flags, "POSSIBLE_WASTE"))
		truthy(has(p.flags, "OUT_OF_ORDER"))
	end)

	it("an 'auto' award waits for the master looter when a council flag is up", function()
		local b = bench({ rules = function(r) r.session.awardMode = "auto" end })
		b.open()
		b.respond("Aurel", "MS", { m = big(90) })
		b.respond("Bryn", "PASS", { m = big(120) })
		b.roll("Aurel", 50)
		b.ml("CLOSE_ROUND")
		local item = b.item()
		eq(item.state, "PROPOSAL")
		isNil(item.autoAt, "no automatic confirmation")
		falsy(F().Ready(item.proposal))
		-- without the flag the same item is confirmed by itself
		local c = bench({ rules = function(r) r.session.awardMode = "auto" end })
		c.open()
		c.respond("Aurel", "MS", { m = big(90) })
		c.respond("Bryn", "PASS", { m = small(10) })
		c.roll("Aurel", 50)
		c.ml("CLOSE_ROUND")
		truthy(c.item().autoAt)
	end)

	it("never flags MS2 answers in the session", function()
		local b = bench()
		b.open()
		b.respond("Aurel", "MS", { m = small(10) })
		b.respond("Corin", "OS", { m = none(0), o = big(300) })
		b.respond("Bryn", "PASS", { m = none(0), o = big(300) })
		b.roll("Aurel", 12)
		b.ml("CLOSE_ROUND")
		deepEq(codes(F().Flags(b.s, 1)), {})
		falsy(has(b.item().proposal.flags, "POSSIBLE_WASTE"))
		falsy(has(b.item().proposal.flags, "UPGRADE_IGNORED"))
	end)

	it("the live line follows the credits before the proposal", function()
		local b = bench({ credits = { Aurel = 3, Bryn = 1, Corin = 0, Dara = 0 } })
		b.open()
		b.respond("Aurel", "MS", { m = big(90) })
		b.respond("Corin", "MS", { m = small(10) })
		deepEq(codes(F().Flags(b.s, 1)), { "POSSIBLE_WASTE:Corin>Aurel" })
	end)

	it("only the players who may roll count", function()
		local b = bench({ addon = { Aurel = true, Corin = true, Dara = true } })
		b.open()
		-- Bryn has no addon: the response is refused and nothing is kept
		local ok, code = b.step({ type = "RESPONSE", player = "Bryn", response = "PASS", verdict = { m = big(120) } })
		falsy(ok); eq(code, "NO_ADDON")
		deepEq(codes(F().Flags(b.s, 1)), {})
	end)

	it("the rules can turn the flags off", function()
		local b = bench({ rules = function(r) r.council.flags = false end })
		b.open()
		b.respond("Bryn", "PASS", { m = big(120) })
		deepEq(codes(F().Flags(b.s, 1)), {})
	end)

	it("a session saved before M5-4 (no council rules on it) uses the presets", function()
		local b = bench()
		b.s.rules.council, b.s.rules.upgrade = nil, nil
		b.open()
		b.respond("Bryn", "PASS", { m = big(120) })
		deepEq(codes(F().Flags(b.s, 1)), { "UPGRADE_IGNORED:Bryn" })
	end)

	it("a rejected item forgets its flags until it is rolled again", function()
		local b = bench()
		b.open()
		b.respond("Aurel", "MS", { m = small(10) })
		b.respond("Bryn", "PASS", { m = big(120) })
		b.roll("Aurel", 12)
		b.ml("CLOSE_ROUND")
		truthy(b.item().flagged)
		b.ml("REJECT")
		isNil(b.s.items[1].flagged)
		deepEq(codes(F().Flags(b.s, 1)), {})
	end)
end)

describe("the view of another client", function()
	local function view(responses, proposal)
		return { s = "S1-9", q = 3, ml = "Dara", a = 1, items = { { id = 19003, ca = "jewelry", cs = { MS = 1, OS = 0 },
			st = proposal and "PROPOSAL" or "ROLLING" } }, proposal = proposal, mine = {}, responses = { [1] = responses } }
	end
	local function env(verdicts)
		local r = FDCP.Rules.DefaultConfig()
		return { now = 0, verdicts = verdicts, priority = r.priority, upgrade = r.upgrade, council = r.council }
	end
	local ANSWERS = { Aurel = { rs = "MS", vd = { m = small(10) } }, Corin = { rs = "MS", vd = { m = big(90) } },
		Bryn = { rs = "PASS", vd = { m = big(120) } } }

	it("shows candidates and flags only where the verdicts may be seen", function()
		local b = SBd().Build({ host = false, view = view(ANSWERS) }, env(true))
		eq(#b.candidates, 3)
		deepEq(codes(b.flags), { "UPGRADE_IGNORED:Bryn" }, "no line before the proposal: no credits travel")
		isNil(b.candidates[1].credits)
		local hidden = SBd().Build({ host = false, view = view(ANSWERS) }, env(false))
		eq(#hidden.candidates, 0)
		eq(#hidden.flags, 0)
	end)

	it("says 'possible waste' once the proposal names the first in line", function()
		local p = { i = 1, k = "AWARD", tg = "member", w = "Aurel", c = 1, rc = { "LOWER_CREDITS" },
			f = { "UPGRADE_IGNORED", "POSSIBLE_WASTE" } }
		local b = SBd().Build({ host = false, view = view(ANSWERS, p) }, env(true))
		deepEq(codes(b.flags), { "UPGRADE_IGNORED:Bryn", "POSSIBLE_WASTE:Aurel>Corin" })
		local rows = {}
		for _, r in ipairs(b.candidates) do rows[r.player] = r end
		truthy(rows.Aurel.proposed)
		deepEq(rows.Corin.flags, { "POSSIBLE_WASTE" })
		-- without the verdicts the codes of the proposal still say what to look at, without names
		local plain = SBd().Build({ host = false, view = view(ANSWERS, p) }, env(false))
		eq(#plain.flags, 0)
		deepEq(SBd().FlagTexts(plain.proposal, plain.flags), { FDCP.L["RC_FLAG_UPGRADE_IGNORED"], FDCP.L["RC_FLAG_POSSIBLE_WASTE"] })
	end)
end)

describe("the words", function()
	it("every flag code has its sentences in English and Italian", function()
		for _, code in ipairs(Fl().CODES) do
			local key = FDCP.Reasons.Key("FLAG", code)
			truthy(key, code)
			for _, lang in ipairs({ "enUS", "itIT" }) do
				local text = FDCP.Locale.Text(lang, key)
				truthy(text and text ~= key, lang .. " " .. code)
				local short = FDCP.Locale.Text(lang, "ML_FLAG_SHORT_" .. code)
				truthy(short and short ~= "ML_FLAG_SHORT_" .. code, lang .. " short " .. code)
			end
		end
	end)

	it("reads in Italian", function()
		FDCP.Locale.SetActive("itIT")
		local f = { code = "UPGRADE_IGNORED", player = "Bryn-Camelot", response = nil, verdict = { verdict = "MAJOR", ilvlDelta = 12 } }
		eq(SBd().FlagLine(f), "Upgrade ignorato: Bryn non ha risposto (Upgrade grande · ilvl +12).")
		eq(SBd().FlagShort("POSSIBLE_WASTE"), "Possibile spreco")
		FDCP.Locale.SetActive("enUS")
	end)
end)
