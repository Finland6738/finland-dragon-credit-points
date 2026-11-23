-- Roll cheating (M7-5d, owner rule of 2026-11-22): Domain/Cheat.lua detects the four cases (gear swapped for a lower one,
-- a piece taken off, a pass on a medium or major main-spec upgrade, an off-spec piece that hides the upgrade) from the
-- evidence the player's client sends with the response; the flags go with the proposal and never change the winner; the
-- master looter or the council adds `penalties.cheat` credits (preset 2) with one click and a confirmation (or by itself
-- with `penalties.autoApply`); a void cancels the penalty; a typed /roll is still discarded as in M7-2d.
local function Ch() return FDCP.Cheat end
local function Fl() return FDCP.Flags end
local function F() return FDCP.SessionFSM end
local function Lg() return FDCP.Ledger end
local function P() return FDCP.Permissions end
local function C() return FDCP.Council end
local function SBd() return FDCP.SessionBoard end

local MAIN = { MS = true }

local function causes(list)
	local out = {}
	for i, f in ipairs(list) do out[i] = f.code .. ":" .. f.player .. ":" .. tostring(f.cause) end
	return out
end

local function detect(input)
	input.player = input.player or "Bryn"
	input.main = input.main or MAIN
	return Ch().Detect(input)
end

local function unpack_(w) return FDCP.UpgradeScore.Unpack(w) end

-- Evidence: one slot (the head, 1) with the item levels of the fight (f) and of the roll (n).
local function gear(f, n, extra)
	local e = { s = 1, f = f, n = n, fi = 1001, ni = n > 0 and 1002 or nil }
	for k, v in pairs(extra or {}) do e[k] = v end
	return Ch().ReadGear({ g = { e } })
end

describe("the four cases", function()
	it("1. gear swapped for a lower one after the fight -> GEAR_SWAP with the evidence", function()
		local list = detect({ response = "MS", verdict = unpack_({ v = "MAJOR", l = 30 }), gear = gear(226, 200) })
		deepEq(causes(list), { "CHEAT:Bryn:GEAR_SWAP" })
		eq(list[1].fight, 226); eq(list[1].now, 200); eq(list[1].fightItem, 1001); eq(list[1].nowItem, 1002)
		eq(list[1].slot, 1)
	end)

	it("2. a piece taken off after the fight -> UNEQUIPPED", function()
		local list = detect({ response = "MS", verdict = unpack_({ v = "MAJOR", c = "EMPTY_SLOT" }), gear = gear(226, 0) })
		deepEq(causes(list), { "CHEAT:Bryn:UNEQUIPPED" })
		eq(list[1].fight, 226); eq(list[1].now, 0)
	end)

	it("3. a pass on a medium or major main-spec upgrade -> UPGRADE_PASSED", function()
		deepEq(causes(detect({ response = "PASS", verdict = unpack_({ v = "MEDIUM", l = 13 }) })), { "CHEAT:Bryn:UPGRADE_PASSED" })
		local list = detect({ response = "PASS", verdict = unpack_({ v = "MAJOR", l = 40 }) })
		deepEq(causes(list), { "CHEAT:Bryn:UPGRADE_PASSED" })
		eq(list[1].shown, "MAJOR"); eq(list[1].ilvl, 40)
	end)

	it("4. an off-spec piece that hides the upgrade -> OFFSPEC_HIDE", function()
		local g = Ch().ReadGear({ g = { { s = 16, f = 240, n = 240, fi = 2001, ni = 2001, x = 1 } }, h = { v = "MAJOR", l = 20 } })
		local list = detect({ response = "OS", verdict = unpack_({ v = "MINOR", l = 2 }), gear = g })
		deepEq(causes(list), { "CHEAT:Bryn:OFFSPEC_HIDE" })
		eq(list[1].honest, "MAJOR"); eq(list[1].shown, "MINOR"); eq(list[1].nowItem, 2001); eq(list[1].slot, 16)
		-- the same with a pass
		deepEq(causes(detect({ response = "PASS", verdict = unpack_({ v = "NONE" }), gear = g })), { "CHEAT:Bryn:OFFSPEC_HIDE" })
	end)

	it("several cases of one player come in the order of Cheat.CAUSES, one flag per case", function()
		local g = Ch().ReadGear({ g = { { s = 11, f = 226, n = 0 }, { s = 12, f = 226, n = 210 } } })
		local list = detect({ response = "PASS", verdict = unpack_({ v = "MEDIUM", l = 5 }), gear = g })
		deepEq(causes(list), { "CHEAT:Bryn:GEAR_SWAP", "CHEAT:Bryn:UNEQUIPPED", "CHEAT:Bryn:UPGRADE_PASSED" })
	end)
end)

describe("an honest player", function()
	it("is never flagged", function()
		-- the same gear in the fight and at the roll, a main-spec answer
		deepEq(detect({ response = "MS", verdict = unpack_({ v = "MAJOR", l = 30 }), gear = gear(226, 226) }), {})
		-- better gear at the roll than in the fight (a piece won earlier in the night)
		deepEq(detect({ response = "MS", verdict = unpack_({ v = "MINOR", l = 3 }), gear = gear(200, 226) }), {})
		-- a pass on a minor upgrade or on nothing
		deepEq(detect({ response = "PASS", verdict = unpack_({ v = "MINOR", l = 3 }) }), {})
		deepEq(detect({ response = "PASS", verdict = unpack_({ v = "NONE", l = -4 }) }), {})
		-- no answer yet: never cheating
		deepEq(detect({ response = nil, verdict = unpack_({ v = "MAJOR", l = 30 }) }), {})
		-- an item the player cannot use
		deepEq(detect({ response = "PASS", verdict = unpack_({ v = "NONE", u = false, c = "ARMOR_TYPE" }) }), {})
		-- an empty slot in the fight that is still empty
		deepEq(detect({ response = "MS", verdict = unpack_({ v = "MAJOR", c = "EMPTY_SLOT" }), gear = gear(0, 0) }), {})
		-- no snapshot of the fight: nothing to compare
		deepEq(detect({ response = "MS", verdict = unpack_({ v = "MINOR" }), gear = Ch().ReadGear({ g = { { s = 1, n = 100 } } }) }), {})
		-- an off-spec piece, but the player asks for the item at full cost
		local g = Ch().ReadGear({ g = { { s = 16, f = 240, n = 240, x = 1 } }, h = { v = "MAJOR" } })
		deepEq(detect({ response = "MS", verdict = unpack_({ v = "MINOR" }), gear = g }), {})
		-- an off-spec piece that hides nothing (the item is not an upgrade even without it)
		g = Ch().ReadGear({ g = { { s = 16, f = 240, n = 240, x = 1 } }, h = { v = "MINOR" } })
		deepEq(detect({ response = "OS", verdict = unpack_({ v = "MINOR" }), gear = g }), {})
	end)
end)

describe("the evidence on the wire", function()
	it("keeps a valid cg and drops a damaged one", function()
		local g = Ch().ReadGear({ g = { { s = 1, f = 226, n = 200, fi = 5, ni = 6 } }, h = { v = "MAJOR", l = 4 } })
		deepEq(g, { g = { { s = 1, f = 226, n = 200, fi = 5, ni = 6 } }, h = { v = "MAJOR", l = 4 } })
		isNil(Ch().ReadGear(nil))
		isNil(Ch().ReadGear({ g = { { s = 30, f = 1, n = 1 } } }))
		isNil(Ch().ReadGear({ g = { { s = 1, f = -1, n = 1 } } }))
		isNil(Ch().ReadGear({ g = { { s = 1, x = 2 } } }))
		isNil(Ch().ReadGear({ g = { { s = 1 }, { s = 2 }, { s = 3 }, { s = 4 } } }))
		isNil(Ch().ReadGear({ g = { { s = 1, n = 1 } }, h = { v = "BIG" } }))
		isNil(Ch().ReadGear({ g = {} }))
	end)

	it("the inspection's cross-check of the gear worn now", function()
		local g = gear(226, 200)
		eq(Ch().CrossCheck(g, { [1] = 200 }), "MATCH")
		eq(Ch().CrossCheck(g, { [1] = 226 }), "MISMATCH")
		isNil(Ch().CrossCheck(g, { [5] = 200 }))
		isNil(Ch().CrossCheck(nil, { [1] = 200 }))
	end)

	it("reads the cg of a SRESP and drops a damaged one without losing the response", function()
		local S = FDCP.Protocol.Session
		local r = assert(S.ReadResponse({ t = "SRESP", s = "S1-1", i = 1, r = 1, rs = "MS",
			cg = { g = { { s = 1, f = 226, n = 200 } } } }, "Bryn-Camelot"))
		eq(r.cg.g[1].n, 200)
		r = assert(S.ReadResponse({ t = "SRESP", s = "S1-1", i = 1, r = 1, rs = "MS", cg = { g = "x" } }, "Bryn-Camelot"))
		isNil(r.cg); eq(r.rs, "MS")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The flags in the session

local ML = "Dara"
local RAID = { Aurel = true, Bryn = true, Corin = true, Dara = true }
local HELM = { itemID = 19003, slot = 1, classID = 4, subclassID = 4, equipLoc = "INVTYPE_HEAD", quality = 4 }

local function bench(opts)
	opts = opts or {}
	local b = { L = Lg().New(), t = 1000 }
	local rules = FDCP.Rules.DefaultConfig()
	rules.session.autoAdvance = false
	if opts.rules then opts.rules(rules) end
	b.s = assert(F().New({ id = "S1-1", season = "S1", ml = ML, ts = 1000, encounter = 601, rules = rules,
		present = RAID, addon = RAID }))
	local credits = { Aurel = 0, Bryn = 1, Corin = 2, Dara = 3 }
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
	function b.respond(player, response, vd, cg)
		local ok, code = b.step({ type = "RESPONSE", player = player, response = response, verdict = vd, gear = cg })
		if not ok then error("refused response: " .. tostring(code), 2) end
	end
	function b.open()
		assert(b.step({ type = "LOOT_OPENED", items = { HELM }, encounter = 601 }))
		b.ml("START")
		b.ml("OPEN_ROLL")
	end
	function b.item() return b.s.items[b.s.active or 1] end
	function b.board() return SBd().Build({ host = true, session = b.s }, { now = b.t }) end
	return b
end

describe("in the session", function()
	it("flags the cases as soon as the response arrives, with the evidence on the board", function()
		local b = bench()
		b.open()
		b.respond("Bryn", "MS", { m = { v = "MAJOR", l = 26 } }, { g = { { s = 1, f = 226, n = 200, fi = 1001, ni = 1002 } } })
		b.respond("Corin", "PASS", { m = { v = "MEDIUM", l = 13 } })
		b.respond("Aurel", "MS", { m = { v = "MAJOR", l = 30 } }, { g = { { s = 1, f = 226, n = 226 } } })
		deepEq(causes(F().Flags(b.s, 1)), { "CHEAT:Bryn:GEAR_SWAP", "CHEAT:Corin:UPGRADE_PASSED" })
		local board = b.board()
		eq(SBd().FlagLine(board.flags[1]), FDCP.L["ML_CHEAT_GEAR_SWAP"]:format("Bryn", "#1001", 226, "#1002", 200))
		eq(SBd().FlagLine(board.flags[2]), FDCP.L["ML_CHEAT_UPGRADE_PASSED"]:format("Corin", "Medium upgrade · ilvl +13"))
		local rows = {}
		for _, r in ipairs(board.candidates) do rows[r.player] = r end
		deepEq(rows.Bryn.flags, { "CHEAT" })
		eq(SBd().FlagShort("CHEAT"), FDCP.L["ML_FLAG_SHORT_CHEAT"])
	end)

	it("a pass on a major upgrade stays M5-4's UPGRADE_IGNORED, which counts as the case UPGRADE_PASSED", function()
		local b = bench()
		b.open()
		b.respond("Bryn", "PASS", { m = { v = "MAJOR", l = 40 } })
		local list = F().Flags(b.s, 1)
		deepEq(causes(list), { "UPGRADE_IGNORED:Bryn:nil" })
		eq(Fl().CheatCause(list[1]), "UPGRADE_PASSED")
		isNil(Fl().CheatCause({ code = "UPGRADE_IGNORED", player = "Bryn" }))   -- no answer: never cheating
	end)

	it("writes the flag with the proposal and never changes the winner", function()
		local b = bench()
		b.open()
		b.respond("Aurel", "MS", { m = { v = "MAJOR", l = 26 } }, { g = { { s = 1, f = 226, n = 0 } } })
		b.respond("Bryn", "MS", { m = { v = "MAJOR", l = 20 } })
		assert(b.step({ type = "ROLL", player = "Aurel", value = 10, min = 1, max = 100 }))
		assert(b.step({ type = "ROLL", player = "Bryn", value = 90, min = 1, max = 100 }))
		b.ml("CLOSE_ROUND")
		local item = b.item()
		eq(item.state, "PROPOSAL")
		eq(item.proposal.winner, "Aurel", "fewer credits wins: a flag changes nothing")
		local found = false
		for _, c in ipairs(item.proposal.flags) do if c == "CHEAT" then found = true end end
		truthy(found)
		deepEq(causes(item.flagged), { "CHEAT:Aurel:UNEQUIPPED" })
	end)

	it("a typed /roll is still discarded as NOT_FROM_BUTTON (M7-2d), flags or not", function()
		local b = bench()
		b.open()
		b.respond("Aurel", "MS", { m = { v = "MAJOR", l = 26 } }, { g = { { s = 1, f = 226, n = 200 } } })
		b.respond("Bryn", "MS", { m = { v = "MAJOR", l = 20 } })
		assert(b.step({ type = "ROLL", player = "Aurel", value = 99, min = 1, max = 100, nb = true }))
		assert(b.step({ type = "ROLL", player = "Bryn", value = 10, min = 1, max = 100 }))
		b.ml("CLOSE_ROUND")
		local item = b.item()
		local typed = {}
		for _, d in ipairs(item.discarded or {}) do if d.code == "NOT_FROM_BUTTON" then typed[#typed + 1] = d.player end end
		deepEq(typed, { "Aurel" })
		deepEq(causes(item.flagged), { "CHEAT:Aurel:GEAR_SWAP" })
	end)

	it("says nothing when the rules turn the flags off", function()
		local b = bench({ rules = function(r) r.council.flags = false end })
		b.open()
		b.respond("Bryn", "MS", { m = { v = "MAJOR" } }, { g = { { s = 1, f = 226, n = 0 } } })
		deepEq(F().Flags(b.s, 1), {})
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The penalty in the ledger

local GM, OFFICER = "Aurel-Camelot", "Bryn-Camelot"

local function ranks()
	local h = P().NewHistory()
	P().RecordRank(h, GM, 0, 0)
	P().RecordRank(h, OFFICER, 1, 0)
	h.loaded = true
	return h
end
local function gate() return P().Gate(ranks()) end

local function season()
	local L = Lg().New()
	assert(FDCP.Season.Open(L, { author = GM, ts = 1, season = "S1", instances = { { id = 409, size = 40 } } }))
	for i, name in ipairs({ "Aurel", "Bryn", "Corin" }) do
		assert(FDCP.Members.Join(L, { author = GM, ts = 1 + i, season = "S1", member = name, faction = "Horde" }))
	end
	return L
end

describe("the penalty", function()
	it("adds the rules' amount (preset 2) as CREDITS_ADJUSTED reason CHEAT, once per case, item and session", function()
		local L = season()
		eq(Ch().Amount(FDCP.Rules.DefaultConfig().penalties), 2)
		local before = Lg().Credits(L, "S1").Corin
		local e = assert(Ch().Apply(L, { author = GM, ts = 10, season = "S1", member = "Corin", cause = "GEAR_SWAP",
			item = 19003, sid = "S1-1", amount = 2 }, gate()))
		eq(e.payload.reason, "CHEAT"); eq(e.payload.cause, "GEAR_SWAP"); eq(e.payload.delta, 2)
		eq(e.payload.item, 19003); eq(e.payload.sid, "S1-1")
		eq(Lg().Credits(L, "S1").Corin, before + 2)
		local again, code = Ch().Apply(L, { author = GM, ts = 11, season = "S1", member = "Corin", cause = "GEAR_SWAP",
			item = 19003, sid = "S1-1", amount = 2 }, gate())
		isNil(again); eq(code, "DUPLICATE")
		-- another case of the same item is another penalty
		assert(Ch().Apply(L, { author = GM, ts = 12, season = "S1", member = "Corin", cause = "UPGRADE_PASSED",
			item = 19003, sid = "S1-1", amount = 2 }, gate()))
		eq(Lg().Credits(L, "S1").Corin, before + 4)
	end)

	it("refuses an unknown case and an amount of 0 (the penalty is off)", function()
		local L = season()
		local e, code = Ch().Apply(L, { author = GM, ts = 10, season = "S1", member = "Corin", cause = "LUCK", amount = 2 }, gate())
		isNil(e); eq(code, "cause")
		e, code = Ch().Apply(L, { author = GM, ts = 10, season = "S1", member = "Corin", cause = "GEAR_SWAP", amount = 0 }, gate())
		isNil(e); eq(code, "BAD_DELTA")
	end)

	it("a void restores the credits, and the penalty is not proposed again", function()
		local L = season()
		local before = Lg().Credits(L, "S1").Corin
		local e = assert(Ch().Apply(L, { author = GM, ts = 10, season = "S1", member = "Corin", cause = "UNEQUIPPED",
			item = 19003, sid = "S1-1", amount = 2 }, gate()))
		assert(C().Void(L, { author = GM, ts = 20, ref = e.id, reason = "MISTAKE" }, gate()))
		eq(Lg().Credits(L, "S1").Corin, before)
		local _, code = Ch().Apply(L, { author = GM, ts = 30, season = "S1", member = "Corin", cause = "UNEQUIPPED",
			item = 19003, sid = "S1-1", amount = 2 }, gate())
		eq(code, "DUPLICATE")
		-- the audit shows it like any adjustment, voided
		local found
		for _, a in ipairs(C().Audit(L, "S1")) do if a.kind == "ADJUST" and a.id == e.id then found = a end end
		truthy(found); eq(found.reason, "CHEAT"); truthy(found.voided)
	end)

	it("the rules: penalties.cheat is checked, the other presets turn it off, old rules get the default", function()
		local r = FDCP.Rules.DefaultConfig()
		eq(r.penalties.cheat, 2)
		r.penalties.cheat = -1
		local ok, problems = FDCP.Rules.Validate(r)
		falsy(ok); deepEq(problems, { "penalties.cheat" })
		eq(FDCP.Presets.Get("ROLL_ONLY").penalties.cheat, 0)
		eq(FDCP.Reasons.Key("CORRECTION", "CHEAT"), "RC_CORRECTION_CHEAT")
		for _, c in ipairs(Ch().CAUSES) do truthy(FDCP.Reasons.Key("CHEAT", c)) end
		truthy(FDCP.Reasons.Text("CHEAT", "GEAR_SWAP", "itIT"):find("dopo lo scontro", 1, true))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The button: one click arms, the second writes (the penalty is never written without the confirmation)

describe("the Penalize button", function()
	local saved
	local function stub(written)
		local CS = FDCP.CheatService
		saved = CS.Penalize
		CS.Penalize = function(_, target) written[#written + 1] = target; return { id = "x" } end
		CS.armed = nil
	end
	local function restore() FDCP.CheatService.Penalize = saved end

	it("writes nothing on the first click, the penalty on the confirmation", function()
		local CS, written = FDCP.CheatService, {}
		stub(written)
		local target = { member = "Corin-Camelot", cause = "GEAR_SWAP", item = 19003, sid = "S1-1", amount = 2 }
		eq(CS:Label(target), FDCP.L["ML_PENALIZE"]:format("2"))
		eq(CS:Click(target), "ARMED")
		eq(#written, 0)
		eq(CS:Label(target), FDCP.L["ML_PENALIZE_CONFIRM"]:format("2", "Corin"))
		truthy(CS:Click(target))
		eq(#written, 1); eq(written[1].member, "Corin-Camelot")
		restore()
	end)

	it("a confirmation for another player, or after the delay, only arms again", function()
		local CS, written = FDCP.CheatService, {}
		stub(written)
		local a = { member = "Corin-Camelot", cause = "GEAR_SWAP", item = 19003, sid = "S1-1" }
		local b = { member = "Bryn-Camelot", cause = "GEAR_SWAP", item = 19003, sid = "S1-1" }
		eq(CS:Click(a), "ARMED")
		eq(CS:Click(b), "ARMED")
		eq(#written, 0)
		Mock.Advance(CS.CONFIRM_SECONDS + 1)
		eq(CS:Click(b), "ARMED")
		eq(#written, 0)
		restore()
	end)

	it("autoApply writes the flagged penalties by itself, the preset never does", function()
		local CS, written = FDCP.CheatService, {}
		stub(written)
		local SC = FDCP.SessionController
		local savedRules, savedLedger = SC.Rules, SC.Ledger
		local rules = FDCP.Rules.DefaultConfig()
		SC.Rules = function() return rules end
		SC.Ledger = function() return Lg().New() end
		local s = { id = "S1-1", items = { { itemID = 19003, flagged = {
			{ code = "CHEAT", player = "Corin-Camelot", cause = "UNEQUIPPED" },
			{ code = "UPGRADE_IGNORED", player = "Bryn-Camelot", response = "PASS" },
			{ code = "UPGRADE_IGNORED", player = "Aurel-Camelot" },
		} } } }
		deepEq(CS:AutoApply(s), {})
		eq(#written, 0)
		rules.penalties.autoApply = true
		eq(#CS:AutoApply(s), 2)
		eq(written[1].cause, "UNEQUIPPED"); eq(written[2].cause, "UPGRADE_PASSED"); eq(written[2].member, "Bryn-Camelot")
		SC.Rules, SC.Ledger = savedRules, savedLedger
		restore()
	end)
end)
