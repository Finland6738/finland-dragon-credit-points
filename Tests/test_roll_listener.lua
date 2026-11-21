-- The roll listener (M4-3): Adapters/RollListener.lua reads the server's /roll results from CHAT_MSG_SYSTEM with the
-- pattern built from the client's RANDOM_ROLL_RESULT, classifies them (valid, duplicate, out of range, early, absent, no
-- addon) and feeds them to Domain/SessionFSM.lua as ROLL inputs; hidden (secret) messages wait in a buffer until the
-- lockdown ends (plan B, docs/ANALISI.md §11 risk 2). Every scenario runs with an English and an Italian client.
local function RL() return FDCP.RollListener end
local function F() return FDCP.SessionFSM end

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end
local ML = full("Dara")

-- The client formats: English (the mock's own), Italian, and a made-up one with explicit argument positions in another
-- order (as some client languages write it), to prove the pattern follows the global and never a hand-written text.
local FORMATS = {
	enUS = "%s rolls %d (%d-%d)",
	itIT = "%s ottiene %d (%d-%d)",
	positional = "(%3$d-%4$d) %2$d : %1$s",
}
local LOCALES = { "enUS", "itIT" }

local function onRealm(M) M.player.name, M.player.realm = "Dara", REALM end
local function useFormat(key) RANDOM_ROLL_RESULT = FORMATS[key] end

-- The raid: Aurel, Bryn, Dara with the addon; Corin in the raid without it; Eve is not in the raid.
local PRESENT = { [full("Aurel")] = true, [full("Bryn")] = true, [full("Corin")] = true, [ML] = true }
local ADDON = { [full("Aurel")] = true, [full("Bryn")] = true, [ML] = true }
local RING = { itemID = 19003, slot = 1, classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER", quality = 4 }

-- A session run by hand (no auto-advance), attached to the listener. b.open() opens the roll of the ring.
local function bench()
	local r = FDCP.Rules.DefaultConfig()
	r.session.autoAdvance = false
	local b = {}
	b.s = assert(F().New({ id = "S1-1", season = "S1", ml = ML, ts = GetTime(), encounter = 601, rules = r,
		present = PRESENT, addon = ADDON }))
	function b.step(input)
		input.ts = input.ts or GetTime()
		local ok, code = F().Step(b.s, input, { credits = {} })
		return ok, code
	end
	function b.ml(kind, extra)
		local input = extra or {}
		input.type, input.by = kind, ML
		assert(b.step(input))
	end
	function b.open()
		b.ml("LOOT_OPENED", { items = { RING }, encounter = 601 })
		b.ml("START")
		b.ml("OPEN_ROLL")
		b.respondAll()
	end
	-- Main-spec answers from the three players with the addon, so the first round's rolls are judged (not set aside).
	function b.respondAll()
		for _, p in ipairs({ "Aurel", "Bryn", "Dara" }) do
			assert(b.step({ type = "RESPONSE", player = full(p), response = "MS" }))
		end
	end
	function b.round() return b.s.items[b.s.active].round end
	truthy(RL():Attach(function() return b.s end, b.step))
	return b
end

local function roll(name, value, lo, hi) Mock.loot.Roll(name, value, lo or 1, hi or 100) end
local function last() local log = RL().log; return log[#log] end
local function codes()
	local out = {}
	for _, e in ipairs(RL().log) do out[#out + 1] = e.player:match("^([^%-]+)") .. ":" .. e.code end
	return out
end

describe("parsing a roll message", function()
	before_boot(onRealm)

	it("reads the English message, with the player's realm added to a name without one", function()
		useFormat("enUS")
		deepEq(RL().Parse("Aurel rolls 42 (1-100)"), { player = full("Aurel"), value = 42, min = 1, max = 100 })
		deepEq(RL().Parse("Bryn-Silvermoon rolls 7 (1-50)"), { player = "Bryn-Silvermoon", value = 7, min = 1, max = 50 })
		isNil(RL().Parse("Aurel has gone offline."))
		isNil(RL().Parse(42))
	end)

	it("reads the Italian message on an Italian client, and not the English one", function()
		useFormat("itIT")
		deepEq(RL().Parse("Aurel ottiene 42 (1-100)"), { player = full("Aurel"), value = 42, min = 1, max = 100 })
		isNil(RL().Parse("Aurel rolls 42 (1-100)"))
	end)

	it("follows explicit argument positions of the global", function()
		useFormat("positional")
		deepEq(RL().Parse("(1-100) 77 : Corin"), { player = full("Corin"), value = 77, min = 1, max = 100 })
	end)

	it("never looks inside a secret message", function()
		local r, why = RL().Parse(Mock.SECRET)
		isNil(r)
		eq(why, "secret")
	end)

	it("reads nothing, without an error, when the client has no RANDOM_ROLL_RESULT", function()
		RANDOM_ROLL_RESULT = nil
		isNil(RL().Parse("Aurel rolls 42 (1-100)"))
		local b = bench()
		b.open()
		Mock.Fire("CHAT_MSG_SYSTEM", "Aurel rolls 42 (1-100)")
		eq(#RL().log, 0)
		eq(#b.round().rolls, 0)
	end)
end)

for _, locale in ipairs(LOCALES) do
	describe("classifying the rolls of a round (" .. locale .. " client)", function()
		before_boot(function(M) onRealm(M); M.player.locale = locale end)

		it("ignores rolls while no session is attached", function()
			useFormat(locale)
			roll("Aurel", 50)
			eq(#RL().log, 0)
		end)

		it("valid, duplicate, out of range, early, absent and no-addon rolls", function()
			useFormat(locale)
			local b = bench()
			local seen = {}
			FDCP.Bus:On("ROLL_SEEN", function(_, e) seen[#seen + 1] = e end)

			roll("Aurel", 12)                       -- before the round opened
			eq(last().code, "NO_ROUND")
			b.open()
			Mock.Advance(1)
			roll("Aurel", 60)
			roll("Aurel", 99)                       -- a second roll: only the first counts
			roll("Bryn", 30, 1, 50)                 -- another range: does not use Bryn's turn
			roll("Bryn", 101, 1, 100)               -- impossible value
			roll("Bryn", 44)
			roll("Corin", 100)                      -- in the raid without the addon
			roll("Eve", 88)                         -- not in the raid
			roll("Dara", 1)
			deepEq(codes(), { "Aurel:NO_ROUND", "Aurel:VALID", "Aurel:DUPLICATE", "Bryn:NOT_1_100", "Bryn:BAD_VALUE",
				"Bryn:VALID", "Corin:NO_ADDON", "Eve:NOT_PRESENT", "Dara:VALID" })
			eq(#seen, 9)
			eq(seen[7].player, full("Corin"))

			-- Every roll seen during the round reached the session; the early one did not.
			local rolls = b.round().rolls
			eq(#rolls, 8)
			eq(rolls[1].player, full("Aurel")); eq(rolls[1].value, 60)
			local stats = RL():Stats()
			eq(stats.seen, 9); eq(stats.fed, 8); eq(stats.refused, 0)
			eq(stats.byCode.VALID, 3); eq(stats.byCode.NO_ADDON, 1)

			-- The session's own judgement (Priority) gives the same codes: the ML sees "addon not active" for Corin.
			b.ml("CLOSE_ROUND")
			local item = b.s.items[b.s.active]
			local byPlayer = {}
			for _, d in ipairs(item.discarded or {}) do
				byPlayer[#byPlayer + 1] = (d.player or "?"):match("^([^%-]+)") .. ":" .. d.code
			end
			deepEq(byPlayer, { "Aurel:DUPLICATE", "Bryn:NOT_1_100", "Bryn:BAD_VALUE", "Corin:NO_ADDON", "Eve:NOT_PRESENT" })
			eq(FDCP.Reasons.Key("DISCARD", "NO_ADDON"), "RC_DISCARD_NO_ADDON")
			for _, e in ipairs(RL().log) do
				if e.code ~= "VALID" then truthy(FDCP.Reasons.Key("DISCARD", e.code), e.code) end
			end

			-- After the round closed, a roll is not given to the session.
			roll("Bryn", 70)
			eq(last().code, "NO_ROUND")
			eq(RL():Stats().fed, 8)
		end)

		it("a reroll accepts only the tied players", function()
			useFormat(locale)
			local b = bench()
			b.open()
			b.s.items[b.s.active].round.among = { full("Aurel"), full("Bryn") }
			roll("Dara", 40)
			roll("Bryn", 41)
			deepEq(codes(), { "Dara:NOT_ELIGIBLE", "Bryn:VALID" })
		end)

		it("judges duplicates from the session itself, so a /reload does not reset them", function()
			useFormat(locale)
			local b = bench()
			b.open()
			roll("Aurel", 60)
			RL():Reset()                             -- the master looter reloads; the session is saved data
			RL():Attach(function() return b.s end, b.step)
			roll("Aurel", 95)
			eq(last().code, "DUPLICATE")
		end)
	end)
end

-- A text the client hides while `hidden[text]` is true (the mock's issecretvalue only knows Mock.SECRET).
local function hideTexts(hidden)
	local base = issecretvalue
	issecretvalue = function(v) return base(v) or (type(v) == "string" and hidden[v] == true) end
end

for _, locale in ipairs(LOCALES) do
	describe("plan B: hidden roll messages wait for the lockdown to end (" .. locale .. " client)", function()
		before_boot(function(M) onRealm(M); M.player.locale = locale end)

		local function text(name, value) return string.format(RANDOM_ROLL_RESULT, name, value, 1, 100) end

		it("holds the hidden messages and reads them, with their arrival time, once the restriction ends", function()
			useFormat(locale)
			local b = bench()
			b.open()
			local hidden = {}
			hideTexts(hidden)
			Mock.restrictions.Set({ Encounter = 2 })
			local t0 = GetTime()
			local a, c = text("Aurel", 55), text("Corin", 90)
			hidden[a], hidden[c] = true, true
			Mock.Fire("CHAT_MSG_SYSTEM", a)
			Mock.Advance(2)
			Mock.Fire("CHAT_MSG_SYSTEM", c)
			eq(RL():Pending(), 2)
			eq(#RL().log, 0)
			eq(#b.round().rolls, 0)

			Mock.Advance(3)                          -- the recheck runs, but the lockdown is still on
			eq(RL():Pending(), 2)

			hidden[a], hidden[c] = nil, nil          -- readable again
			Mock.restrictions.Set({})                -- ADDON_RESTRICTION_STATE_CHANGED
			eq(RL():Pending(), 0)
			deepEq(codes(), { "Aurel:VALID", "Corin:NO_ADDON" })
			eq(RL().log[1].ts, t0)
			eq(RL().log[2].ts, t0 + 2)
			truthy(RL().log[1].held)
			eq(b.round().rolls[1].ts, t0)
			eq(RL():Stats().held, 2)
		end)

		it("judges a held roll against the round it was made in", function()
			useFormat(locale)
			local b = bench()
			local hidden = {}
			hideTexts(hidden)
			b.ml("LOOT_OPENED", { items = { RING }, encounter = 601 })
			b.ml("START")
			Mock.chat.lockdown = true
			local early = text("Bryn", 80)
			hidden[early] = true
			Mock.Fire("CHAT_MSG_SYSTEM", early)      -- rolled before the roll opened
			Mock.Advance(1)
			b.ml("OPEN_ROLL")
			b.respondAll()
			Mock.chat.lockdown = false
			hidden[early] = nil
			Mock.Advance(RL().RECHECK)               -- no event: the one-second recheck reads it
			eq(last().code, "BEFORE_OPEN")
			b.ml("CLOSE_ROUND")
			local d = b.s.items[b.s.active].discarded
			eq(d[1].code, "BEFORE_OPEN")
		end)

		it("a held roll read after its round closed is not given to the session", function()
			useFormat(locale)
			local b = bench()
			b.open()
			local hidden = {}
			hideTexts(hidden)
			Mock.encounter.inProgress = true
			local m = text("Aurel", 33)
			hidden[m] = true
			Mock.Fire("CHAT_MSG_SYSTEM", m)
			b.ml("CLOSE_ROUND")
			hidden[m] = nil
			Mock.encounter.End(601, "Boss", true)
			eq(last().code, "NO_ROUND")
			truthy(last().held)
			eq(RL():Stats().fed, 0)
		end)

		it("drops and counts what stays hidden after the lockdown, never reading it", function()
			useFormat(locale)
			local b = bench()
			b.open()
			Mock.restrictions.Set({ Combat = 2 })
			Mock.loot.Set({ secretMessages = true })
			roll("Aurel", 10)
			roll("Bryn", 20)
			eq(RL():Pending(), 2)
			Mock.loot.Set({ secretMessages = false })
			Mock.restrictions.Set({})
			eq(RL():Pending(), 0)
			eq(RL():Stats().hidden, 2)
			eq(#RL().log, 0)
			eq(#b.round().rolls, 0)
		end)

		it("keeps at most MAX_BUFFER hidden messages and counts the dropped ones", function()
			useFormat(locale)
			bench()
			local max = RL().MAX_BUFFER
			RL().MAX_BUFFER = 3
			Mock.restrictions.Set({ Encounter = 2 })
			Mock.loot.Set({ secretMessages = true })
			for i = 1, 5 do roll("Aurel", i) end
			eq(RL():Pending(), 3)
			eq(RL():Stats().dropped, 2)
			RL().MAX_BUFFER = max
			RL():Detach()
			eq(RL():Pending(), 0)
		end)
	end)
end
