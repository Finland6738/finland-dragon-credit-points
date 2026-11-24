-- The public read-only API for other addons (M8-1, ADR 0009, docs/ANALISI.md §8.6): the global table
-- FinlandDragonCreditPointsAPI. Aurel is the Guild Master, Bryn an officer (rank 1), Corin and Dara members (rank 3).
local REALM = "Camelot"
local SEASON = "S1"
local function full(name) return name .. "-" .. REALM end
local RANKS = { Aurel = 0, Bryn = 1, Corin = 3, Dara = 3 }
local NAMES = { "Aurel", "Bryn", "Corin", "Dara" }

local function setupFor(name)
	return function(M)
		local members = {}
		for _, n in ipairs(NAMES) do
			if n ~= name then members[#members + 1] = { name = n, rank = RANKS[n], class = "WARRIOR" } end
		end
		M.guild.Set({ name = "Dragon", members = members, myRank = RANKS[name] })
	end
end

local function A(c) return c.addon() end
local function API(c) return c.E.FinlandDragonCreditPointsAPI end
local function Ldg(c) return assert(A(c).NightController:Ledger()) end
local function gate(c) return A(c).PermissionService:Gate() end
local function now(c) return A(c).Compat.ServerTime() end

local function guild(names)
	local net = Sim.new{ realm = REALM, step = 0.5 }
	local c = {}
	for _, n in ipairs(names) do c[n] = net:Client(n, { setup = setupFor(n) }) end
	net:Advance(3)
	return net, c
end

-- The season of the officers: Bryn (priest, with an alt and availability), Corin, Dara (trial).
local function openSeason(c)
	local a, L = A(c), Ldg(c)
	assert(a.Season.Open(L, { author = full(c.name), ts = now(c), season = SEASON, label = "Season 1",
		instances = { { id = 409, size = 40 } } }, nil, gate(c)))
	assert(a.Roster.Join(L, { author = full(c.name), ts = now(c), season = SEASON, member = full("Bryn"), faction = "Horde",
		ms1 = 257, ms2 = 256, os = 258, avail = { "WED", "MON" }, note = "secret note" }, nil, gate(c)))
	assert(a.Roster.Join(L, { author = full(c.name), ts = now(c), season = SEASON, member = full("Corin"), faction = "Horde",
		ms1 = 73 }, nil, gate(c)))
	assert(a.Roster.Join(L, { author = full(c.name), ts = now(c), season = SEASON, member = full("Dara"), faction = "Horde",
		ms1 = 73, status = "TRIAL" }, nil, gate(c)))
	assert(a.Roster.LinkAlt(L, { author = full(c.name), ts = now(c), season = SEASON, alt = full("Brynalt"),
		main = full("Bryn") }, gate(c)))
end

local function award(c, member, cost)
	assert(A(c).Ledger.Append(Ldg(c), { author = full(c.name), ts = now(c), season = SEASON, type = "ITEM_AWARDED",
		payload = { member = full(member), item = 19003, cost = cost, response = "MS" } }, gate(c)))
end

local function byName(list)
	local out = {}
	for _, e in ipairs(list) do out[e.name] = e end
	return out
end

---------------------------------------------------------------------------------------------------------------------

describe("the global table", function()
	before_boot()

	it("has a stable name, a version, ignores writes and never raises", function()
		local api = FinlandDragonCreditPointsAPI
		truthy(api, "the global exists")
		eq(api.API_VERSION, 1)
		eq(type(api.API_VERSION), "number")
		-- writes are ignored, the metatable is hidden
		api.API_VERSION = 99
		api.GetSeason = function() return "forged" end
		api.Extra = true
		eq(api.API_VERSION, 1)
		eq(api.Extra, nil)
		truthy(api.GetSeason() ~= "forged")
		eq(getmetatable(api), false)
		-- dot and colon give the same
		local v1, n1 = api.GetVersion()
		local v2, n2 = api:GetVersion()
		eq(v1, v2); eq(n1, 1); eq(n2, 1)
		eq(type(v1), "string")
		deepEq(api.GetEvents(), { "READY", "SEASON_CHANGED", "POOL_CHANGED", "CREDITS_CHANGED", "NIGHT_CHANGED", "RULES_CHANGED" })
		-- wrong arguments: nil or false, never an error
		eq(api.GetMember(nil), nil)
		eq(api.GetMember(42), nil)
		eq(api.GetCredits({}), nil)
		eq(api.RegisterCallback("NOPE", function() end), nil)
		eq(select(2, api.RegisterCallback("NOPE", function() end)), "UNKNOWN_EVENT")
		eq(select(2, api.RegisterCallback("POOL_CHANGED", "not a function")), "BAD_CALLBACK")
		eq(api.UnregisterCallback("POOL_CHANGED", print), false)
		-- an internal error gives the fallback
		local P = FDCP.PublicAPI
		local saved = P.Pool
		P.Pool = function() error("boom") end
		deepEq(api.GetPool(), {})
		P.Pool = saved
	end)

	it("answers nil or empty before the guild roster is read", function()
		local api = FinlandDragonCreditPointsAPI
		local PS = FDCP.PermissionService
		local saved = PS.IsReady
		PS.IsReady = function() return false end
		eq(api.IsReady(), false)
		eq(api.GetSource(), nil)
		eq(api.GetSeason(), nil)
		deepEq(api.GetPool(), {})
		deepEq(api.GetCreditList(), {})
		eq(api.GetMember("Corin"), nil)
		eq(api.GetCredits("Corin"), nil)
		eq(api.GetNight(), nil)
		eq(api.GetRules(), nil)
		PS.IsReady = saved
	end)
end)

---------------------------------------------------------------------------------------------------------------------

describe("an officer's client and a member's client", function()
	it("the officer reads the ledger; the member the credits table an officer sent, nothing more", function()
		local net, c = guild({ "Aurel", "Bryn", "Corin" })
		openSeason(c.Aurel)
		net:Advance(60)
		assert(A(c.Aurel).Nights.Open(Ldg(c.Aurel), { author = full("Aurel"), ts = now(c.Aurel), season = SEASON,
			date = "2026-01-07", instanceID = 409, difficulty = "normal", faction = "Horde" }, gate(c.Aurel)))
		assert(A(c.Aurel).Nights.SetLineup(Ldg(c.Aurel), { author = full("Aurel"), ts = now(c.Aurel), season = SEASON,
			raid = { full("Bryn"), full("Corin") }, bench = { full("Dara") } }, gate(c.Aurel)))
		award(c.Aurel, "Corin", 2)
		award(c.Aurel, "Dara", 1)
		net:Advance(90)

		-- the officer
		local o = API(c.Aurel)
		truthy(o.IsReady())
		eq(o.GetSource(), "LEDGER")
		deepEq(o.GetSeason(), { id = SEASON, name = "Season 1", state = "OPEN", updated = "2026-01-07" })
		local pool = byName(o.GetPool())
		local bryn = pool[full("Bryn")]
		eq(bryn.class, "PRIEST"); eq(bryn.role, "HEALER"); eq(bryn.ms1, 257); eq(bryn.ms2, 256); eq(bryn.os, 258)
		deepEq(bryn.avail, { "MON", "WED" }); deepEq(bryn.alts, { full("Brynalt") }); eq(bryn.status, "ACTIVE")
		eq(bryn.faction, "Horde")
		eq(bryn.note, nil, "the player's free note is not exposed")
		eq(pool[full("Dara")].status, "TRIAL")
		-- an alt resolves to its main, short names work
		local viaAlt = o.GetMember("Brynalt")
		eq(viaAlt.name, full("Bryn")); eq(viaAlt.viaAlt, true)
		eq(o.GetMember("Nobody"), nil)
		-- credits and queue place: fewest first (Bryn 0, Dara 1, Corin 2)
		deepEq(o.GetCredits("Corin"), { name = full("Corin"), credits = 2, place = 3, of = 3, faction = "Horde", viaAlt = false })
		deepEq(o.GetCredits(full("Brynalt")), { name = full("Bryn"), credits = 0, place = 1, of = 3, faction = "Horde", viaAlt = true })
		eq(#o.GetCreditList(), 3)
		-- the open night: raid and bench, never the absent
		local night = o.GetNight()
		eq(night.date, "2026-01-07"); eq(night.instanceID, 409); eq(night.size, 40); eq(night.difficulty, "normal")
		deepEq(night.raid, { full("Bryn"), full("Corin") })
		deepEq(night.bench, { full("Dara") })
		eq(night.absent, nil)
		-- the rules: the guild wrote none, so the Patto defaults
		local rules = o.GetRules()
		eq(rules.preset, "PATTO"); eq(rules.custom, false); eq(rules.source, "DEFAULT")
		eq(rules.costs.weapon[4], 2); eq(rules.costs.armor[4], 1); eq(rules.costs.weapon[5], "council")
		eq(rules.penalties.absence, 1); eq(rules.penalties.cheat, 2)
		eq(rules.responseMultiplier.OS, 0)
		eq(rules.lateJoin, "min")

		-- the member: the snapshot only
		local m = API(c.Corin)
		truthy(m.IsReady())
		eq(A(c.Corin).Ledger.Count(Ldg(c.Corin)), 0, "Corin has no ledger")
		eq(m.GetSource(), "SNAPSHOT")
		local season = m.GetSeason()
		eq(season.id, SEASON); eq(season.name, "Season 1"); eq(season.state, "OPEN"); eq(season.updated, "2026-01-07")
		eq(type(season.asOf), "number")
		local mpool = byName(m.GetPool())
		local mb = mpool[full("Bryn")]
		eq(mb.class, "PRIEST"); eq(mb.ms1, 257); deepEq(mb.alts, { full("Brynalt") }); eq(mpool[full("Dara")].status, "TRIAL")
		eq(mb.ms2, nil); eq(mb.os, nil); eq(mb.avail, nil); eq(mb.twin, nil)
		deepEq(m.GetCredits("Corin"), o.GetCredits("Corin"), "the same numbers as the officer")
		deepEq(m.GetCredits("Brynalt"), o.GetCredits("Brynalt"))
		deepEq(m.GetCreditList(), o.GetCreditList())
		eq(m.GetNight(), nil, "a member's client has no nights")
		eq(m.GetRules().source, "DEFAULT")

		-- nothing in the API names attendance or absences
		for _, client in ipairs({ c.Aurel, c.Corin }) do
			local text = A(client).PublicAPI.Fingerprint({ API(client).GetSeason(), API(client).GetPool(),
				API(client).GetCreditList(), API(client).GetNight(), API(client).GetRules() })
			falsy(text:find("absent", 1, true)); falsy(text:find("attend", 1, true)); falsy(text:find("secret note", 1, true))
		end
	end)

	it("the guild's own rules are read on the officer's client", function()
		local net, c = guild({ "Aurel", "Corin" })
		openSeason(c.Aurel)
		local a = A(c.Aurel)
		local rules = a.Rules.DefaultConfig()
		rules.cost.matrix.weapon[4] = 3
		assert(a.Rules.Change(Ldg(c.Aurel), { author = full("Aurel"), ts = now(c.Aurel), rules = rules, preset = "PATTO",
			confirmed = true }, gate(c.Aurel)))
		net:Advance(5)
		local r = API(c.Aurel).GetRules()
		eq(r.source, "GUILD"); eq(r.preset, "PATTO"); eq(r.custom, true); eq(r.costs.weapon[4], 3)
	end)

	it("returns copies: changing them changes nothing in FDCP", function()
		local net, c = guild({ "Aurel", "Corin" })
		openSeason(c.Aurel)
		award(c.Aurel, "Corin", 2)
		net:Advance(90)
		for _, client in ipairs({ c.Aurel, c.Corin }) do
			local api = API(client)
			local before = A(client).PublicAPI.Fingerprint({ api.GetSeason(), api.GetPool(), api.GetCreditList(), api.GetRules() })
			local pool = api.GetPool()
			for _, e in ipairs(pool) do
				e.name, e.class, e.status = "X", "MAGE", "INACTIVE"
				e.alts[#e.alts + 1] = "Thief"
				if e.avail then e.avail[1] = "SUN" end
			end
			local s = api.GetSeason(); s.id, s.state = "S9", "CLOSED"
			local cr = api.GetCredits("Corin"); cr.credits, cr.place = -100, 1
			local list = api.GetCreditList(); list[1].credits = 999
			local rules = api.GetRules(); rules.costs.weapon[4] = 0; rules.penalties.absence = 0
			local m = api.GetMember("Corin"); m.ms1 = 1
			local after = A(client).PublicAPI.Fingerprint({ api.GetSeason(), api.GetPool(), api.GetCreditList(), api.GetRules() })
			eq(after, before, client.name .. ": the state did not move")
			eq(api.GetCredits("Corin").credits, 2)
		end
		-- the officer's ledger and the member's kept snapshot are untouched
		eq(A(c.Aurel).Ledger.Credits(Ldg(c.Aurel), SEASON)[full("Corin")], 2)
		eq(A(c.Aurel).Rules.Current(Ldg(c.Aurel)).cost.matrix.weapon[4], 2)
	end)
end)

---------------------------------------------------------------------------------------------------------------------

describe("change notifications", function()
	it("fire once per change, only for what changed, and a failing callback is isolated", function()
		local net, c = guild({ "Aurel", "Corin" })
		local seen = { Aurel = {}, Corin = {} }
		for _, n in ipairs({ "Aurel", "Corin" }) do
			local api = API(c[n])
			for _, ev in ipairs(api.GetEvents()) do
				truthy(api.RegisterCallback(ev, function(event) seen[n][event] = (seen[n][event] or 0) + 1 end))
			end
		end
		-- a broken callback, registered first: it fails every time and the others still run
		local broken = 0
		truthy(API(c.Aurel).RegisterCallback("CREDITS_CHANGED", function() broken = broken + 1; error("caller bug") end))
		-- the same function twice is kept once
		local twice = 0
		local function f() twice = twice + 1 end
		truthy(API(c.Aurel).RegisterCallback("SEASON_CHANGED", f))
		truthy(API(c.Aurel).RegisterCallback("SEASON_CHANGED", f))

		net:Advance(5)
		eq(seen.Aurel.SEASON_CHANGED, nil, "nothing changed since the registration")

		openSeason(c.Aurel)
		net:Advance(5)
		eq(seen.Aurel.SEASON_CHANGED, 1); eq(seen.Aurel.POOL_CHANGED, 1); eq(twice, 1)
		local credits = seen.Aurel.CREDITS_CHANGED
		truthy(credits == 1, "the pool joined with credits")
		eq(seen.Aurel.NIGHT_CHANGED, nil); eq(seen.Aurel.RULES_CHANGED, nil)

		award(c.Aurel, "Corin", 2)
		net:Advance(5)
		eq(seen.Aurel.CREDITS_CHANGED, credits + 1, "an award changes the credits")
		eq(seen.Aurel.POOL_CHANGED, 1, "but not the pool")
		eq(seen.Aurel.SEASON_CHANGED, 1)
		truthy(broken >= 2, "the broken callback ran and failed")
		truthy(A(c.Aurel).PublicAPI.stats.errors >= 2, "its errors are counted")

		assert(A(c.Aurel).Nights.Open(Ldg(c.Aurel), { author = full("Aurel"), ts = now(c.Aurel), season = SEASON,
			date = "2026-01-07", instanceID = 409, difficulty = "normal" }, gate(c.Aurel)))
		net:Advance(5)
		eq(seen.Aurel.NIGHT_CHANGED, 1)
		eq(seen.Aurel.SEASON_CHANGED, 2, "the season's newest night date moved")
		eq(twice, 2)

		-- the member hears about the officers' snapshot
		net:Advance(90)
		truthy((seen.Corin.SEASON_CHANGED or 0) >= 1, "the member's season arrived")
		truthy((seen.Corin.CREDITS_CHANGED or 0) >= 1, "the member's credits arrived")
		eq(seen.Corin.NIGHT_CHANGED, nil, "a member never has a night")

		-- unregistered: no more calls
		truthy(API(c.Aurel).UnregisterCallback("SEASON_CHANGED", f))
		assert(A(c.Aurel).Nights.Close(Ldg(c.Aurel), { author = full("Aurel"), ts = now(c.Aurel), season = SEASON }, gate(c.Aurel)))
		assert(A(c.Aurel).Nights.Open(Ldg(c.Aurel), { author = full("Aurel"), ts = now(c.Aurel), season = SEASON,
			date = "2026-01-08", instanceID = 409, difficulty = "normal" }, gate(c.Aurel)))
		net:Advance(5)
		eq(twice, 2, "unregistered: not called again")
		eq(seen.Aurel.SEASON_CHANGED, 3, "the other callback still is")
		eq(seen.Aurel.NIGHT_CHANGED, 2, "the close and the new night in one check")
	end)

	it("READY fires once the guild roster is read", function()
		local net = Sim.new{ realm = REALM, step = 0.5 }
		local ready = 0
		local c = net:Client("Corin", { setup = setupFor("Corin"), after = function(client)
			local api = client.E.FinlandDragonCreditPointsAPI
			api.RegisterCallback("READY", function() ready = ready + 1 end)
		end })
		net:Advance(15)
		truthy(c.E.FinlandDragonCreditPointsAPI.IsReady())
		eq(ready, 1)
	end)
end)
