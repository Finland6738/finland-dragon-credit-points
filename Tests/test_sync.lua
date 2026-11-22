-- The officers' ledger sync (M6-5, docs/ANALISI.md §8.4): heads on OFFICER, requests for the missing ranges, events
-- accepted only when their author had the rank, never an overwrite, budgets. Most of it runs on the network simulator:
-- Aurel is the Guild Master, Bryn and Elin officers (rank 1), Corin and Dara members (rank 3).
local REALM = "Camelot"
local SEASON = "S1"
local function full(name) return name .. "-" .. REALM end
local RANKS = { Aurel = 0, Bryn = 1, Elin = 1, Corin = 3, Dara = 3 }
local NAMES = { "Aurel", "Bryn", "Elin", "Corin", "Dara" }

local function setupFor(name, extra)
	return function(M)
		local members = {}
		for _, n in ipairs(NAMES) do
			if n ~= name then members[#members + 1] = { name = n, rank = RANKS[n], class = "WARRIOR" } end
		end
		for _, m in ipairs(extra or {}) do members[#members + 1] = m end
		M.guild.Set({ name = "Dragon", members = members, myRank = RANKS[name] })
	end
end

local function A(c) return c.addon() end
local function Ldg(c) return assert(A(c).NightController:Ledger()) end
local function gate(c) return A(c).PermissionService:Gate() end
local function now(c) return A(c).Compat.ServerTime() end

-- The guild on the simulator: one client per name (default: the three officers and Corin).
local function guild(names, opts)
	opts = opts or {}
	local net = Sim.new{ realm = REALM, step = 0.5 }
	local c = {}
	for _, n in ipairs(names or { "Aurel", "Bryn", "Elin", "Corin" }) do
		c[n] = net:Client(n, { setup = setupFor(n, opts.extra and opts.extra[n]) })
	end
	net:Advance(3)
	return net, c
end

local function openSeason(c)
	local a = A(c)
	assert(a.Season.Open(Ldg(c), { author = full(c.name), ts = now(c), season = SEASON,
		instances = { { id = 409, size = 40 } } }, nil, gate(c)))
	for _, m in ipairs({ "Bryn", "Elin", "Corin", "Dara" }) do
		assert(a.Members.Join(Ldg(c), { author = full(c.name), ts = now(c), season = SEASON, member = full(m) }, nil, gate(c)))
	end
end

-- A night run by client `c`: opened, the awards { {member, cost}, ... } written, closed.
local function night(c, date, awards)
	local a, L = A(c), Ldg(c)
	assert(a.Nights.Open(L, { author = full(c.name), ts = now(c), season = SEASON, date = date, instanceID = 409,
		difficulty = "normal" }, gate(c)))
	for _, w in ipairs(awards) do
		assert(a.Ledger.Append(L, { author = full(c.name), ts = now(c), season = SEASON, type = "ITEM_AWARDED",
			payload = { member = full(w[1]), item = 19003, cost = w[2], response = "MS" } }, gate(c)))
	end
	assert(a.Nights.Close(L, { author = full(c.name), ts = now(c), season = SEASON }, gate(c)))
end

local function ids(c)
	local out = {}
	for id in pairs(Ldg(c).events) do out[#out + 1] = id end
	table.sort(out)
	return out
end

local function authors(c)
	local out = {}
	for _, e in pairs(Ldg(c).events) do out[e.author] = (out[e.author] or 0) + 1 end
	return out
end

---------------------------------------------------------------------------------------------------------------------

describe("what a client lacks and how it is packed", function()
	it("asks only the holes below a peer's heads, skips what the gate refused or queued, within the budget", function()
		local Lg, S = FDCP.Ledger, FDCP.Sync
		local L = Lg.New()
		local function ev(author, seq)
			return { id = Lg.MakeId(author, seq), author = author, seq = seq, ts = 1000 + seq, season = SEASON,
				type = "DROP_SEEN", v = 1, payload = { item = 19003 } }
		end
		Lg.Merge(L, { ev("Aurel-Camelot", 1), ev("Aurel-Camelot", 2), ev("Aurel-Camelot", 5), ev("Bryn-Camelot", 1) })
		S:Reset()
		local ranges, count = S:Wanted(L, { ["Aurel-Camelot"] = 7, ["Bryn-Camelot"] = 1, ["Elin-Camelot"] = 2 })
		deepEq(ranges, { { "Aurel-Camelot", 3, 4 }, { "Aurel-Camelot", 6, 7 }, { "Elin-Camelot", 1, 2 } })
		eq(count, 6)
		S.refused["Aurel-Camelot:3"] = "RANK_TOO_LOW"
		ranges = S:Wanted(L, { ["Aurel-Camelot"] = 7 })
		deepEq(ranges, { { "Aurel-Camelot", 4, 4 }, { "Aurel-Camelot", 6, 7 } })
		local max = S.MAX_REPLY
		S.MAX_REPLY = 2
		ranges, count = S:Wanted(L, { ["Aurel-Camelot"] = 7 })
		deepEq(ranges, { { "Aurel-Camelot", 4, 4 }, { "Aurel-Camelot", 6, 6 } })
		eq(count, 2)
		S.MAX_REPLY = max
		deepEq(S:Wanted(L, { ["Aurel-Camelot"] = 2, ["Bryn-Camelot"] = "x", [3] = 4 }), {})
		S:Reset()
	end)

	it("packs the events in messages under the byte budget, the last one marked", function()
		local S, Lg = FDCP.Sync, FDCP.Ledger
		local list = {}
		for i = 1, 60 do
			list[i] = S.Wire({ author = "Aurel-Camelot", seq = i, ts = 1000 + i, season = SEASON, type = "DROP_SEEN", v = 1,
				payload = { item = 19000 + i, note = string.rep("x", 40) } })
		end
		local msgs = S:Pack(list, "Bryn-Camelot")
		truthy(#msgs >= 3, "60 events need at least three messages")
		local n = 0
		for i, m in ipairs(msgs) do
			truthy(#m.e <= S.MAX_PER_MSG)
			truthy(#FDCP.Codec:Encode("LEVENTS", m) <= S.MSG_BYTES)
			eq(m.to, "Bryn-Camelot")
			eq(m.d, i == #msgs and true or nil)
			n = n + #m.e
		end
		eq(n, 60)
		local back = S.Unwire(msgs[1].e[1])
		eq(back.id, Lg.MakeId("Aurel-Camelot", 1)); eq(back.payload.item, 19001)
		local empty = S:Pack({}, "Bryn-Camelot")
		eq(#empty, 1); eq(#empty[1].e, 0); eq(empty[1].d, true)
	end)
end)

---------------------------------------------------------------------------------------------------------------------

describe("officers converge", function()
	it("two officers who ran different nights end with the same ledger and the same credits", function()
		local net, c = guild()
		openSeason(c.Aurel)
		net:Advance(40)
		deepEq(ids(c.Bryn), ids(c.Aurel), "the season reached Bryn")
		deepEq(ids(c.Elin), ids(c.Aurel), "and Elin")

		-- Wednesday: only Bryn is online and runs the night
		net:Logout("Aurel"); net:Logout("Elin")
		night(c.Bryn, "2026-01-07", { { "Corin", 1 }, { "Dara", 2 } })
		net:Advance(10)
		net:Logout("Bryn")
		-- Thursday: only Elin, who never saw Wednesday
		net:Login("Elin")
		net:Advance(10)
		night(c.Elin, "2026-01-08", { { "Dara", 0.5 }, { "Bryn", 1 } })
		net:Advance(10)
		local L = Ldg(c.Elin)
		eq(L.heads[full("Bryn")], nil, "Elin has nothing of Bryn yet")
		-- Friday: everybody back
		net:Login("Bryn"); net:Login("Aurel")
		net:Advance(120)

		local want = ids(c.Aurel)
		deepEq(ids(c.Bryn), want)
		deepEq(ids(c.Elin), want)
		eq(authors(c.Aurel)[full("Bryn")], 4); eq(authors(c.Aurel)[full("Elin")], 4)
		local credits = A(c.Aurel).Ledger.Credits(Ldg(c.Aurel), SEASON, { full = true })
		deepEq(A(c.Bryn).Ledger.Credits(Ldg(c.Bryn), SEASON, { full = true }), credits)
		deepEq(A(c.Elin).Ledger.Credits(Ldg(c.Elin), SEASON, { full = true }), credits)
		eq(credits[full("Dara")], 2.5); eq(credits[full("Corin")], 1); eq(credits[full("Bryn")], 1)
		deepEq(A(c.Elin).Ledger.Heads(Ldg(c.Elin)), A(c.Bryn).Ledger.Heads(Ldg(c.Bryn)))
		-- the member's client heard none of it and took no part
		eq(A(c.Corin).Ledger.Count(Ldg(c.Corin)), 0)
		eq(net:SentBy("Corin", "OFFICER"), 0)
		falsy(A(c.Corin).Sync:IsActive())
		truthy(A(c.Elin).Sync:Stats().added > 0)
	end)

	it("a long gap comes in several requests, inside the budgets", function()
		local net, c = guild({ "Aurel", "Elin" })
		openSeason(c.Aurel)
		net:Advance(30)
		net:Logout("Elin")
		local a, L = A(c.Aurel), Ldg(c.Aurel)
		for i = 1, 450 do
			assert(a.Ledger.Append(L, { author = full("Aurel"), ts = now(c.Aurel), season = SEASON, type = "CREDITS_ADJUSTED",
				payload = { member = full("Dara"), delta = 0.25, reason = "MANUAL" } }, gate(c.Aurel)))
		end
		net:Advance(5)
		net:Login("Elin")
		net:Advance(240)
		deepEq(ids(c.Elin), ids(c.Aurel))
		local s = A(c.Elin).Sync:Stats()
		truthy(s.asked >= 3, "450 events at most 200 per request: " .. s.asked)
		eq(s.conflicts, 0)
		truthy(A(c.Aurel).Sync:Stats().servedEvents <= 460, "nothing served twice over")
		eq(A(c.Elin).Ledger.Credits(Ldg(c.Elin), SEASON, { full = true })[full("Dara")], 112.5)
	end)

	it("never overwrites an event: the same id with another content stays as it was and is counted", function()
		local net, c = guild({ "Aurel", "Bryn" })
		openSeason(c.Aurel)
		net:Advance(30)
		local L = Ldg(c.Bryn)
		local e = L.events[full("Aurel") .. ":1"]
		local before = A(c.Bryn).Ledger.Get(L, e.id).payload.startCredits
		local forged = A(c.Bryn).Sync.Wire(e)
		forged.p = { instances = { { id = 409, size = 40 } }, startCredits = 99 }
		A(c.Aurel).Transport:Send("OFFICER", { t = "LEVENTS", e = { forged } })
		net:Advance(3)
		eq(Ldg(c.Bryn).events[e.id].payload.startCredits, before)
		eq(A(c.Bryn).Sync:Stats().conflicts, 1)
	end)

	it("ignores its messages on any channel but OFFICER, and stays off before the guild roster is read", function()
		local net, c = guild({ "Aurel", "Bryn" })
		openSeason(c.Aurel)
		A(c.Aurel).Transport:Send("GUILD", { t = "LHEADS", h = { [full("Aurel")] = 5 } })
		net:Advance(2)
		eq(A(c.Bryn).Sync:Stats().dist, 1)
		local S = A(c.Bryn).Sync
		local ready = A(c.Bryn).PermissionService.IsReady
		A(c.Bryn).PermissionService.IsReady = function() return false end
		falsy(S:IsActive())
		A(c.Bryn).PermissionService.IsReady = ready
		truthy(S:IsActive())
	end)
end)

---------------------------------------------------------------------------------------------------------------------

describe("trust", function()
	it("a member's forged events are refused everywhere", function()
		local net, c = guild()
		openSeason(c.Aurel)
		net:Advance(40)
		local count = #ids(c.Aurel)
		local corin = A(c.Corin)
		-- an award Corin writes to themself, and one in Bryn's name, sent straight on OFFICER
		local own = corin.Sync.Wire({ author = full("Corin"), seq = 1, ts = now(c.Corin), season = SEASON,
			type = "ITEM_AWARDED", v = 1, payload = { member = full("Corin"), item = 19003, cost = 0 } })
		local asBryn = corin.Sync.Wire({ author = full("Bryn"), seq = 1, ts = now(c.Corin), season = SEASON,
			type = "CREDITS_ADJUSTED", v = 1, payload = { member = full("Corin"), delta = -5, reason = "MANUAL" } })
		corin.Transport:Send("OFFICER", { t = "LEVENTS", e = { own, asBryn } })
		corin.Transport:Send("OFFICER", { t = "LHEADS", h = { [full("Corin")] = 1 } })
		net:Advance(30)
		for _, n in ipairs({ "Aurel", "Bryn", "Elin" }) do
			eq(#ids(c[n]), count, n .. " stored nothing")
			truthy(A(c[n]).Sync:Stats().untrusted >= 2, n .. " counted the untrusted sender")
			eq(authors(c[n])[full("Corin")], nil)
		end

		-- Bryn's client was tampered with: Corin's award is in its ledger without the gate. Bryn announces it, the other
		-- officers ask for it, and their own gate refuses it (the author's rank), once: it is not asked again.
		local raw = corin.Sync.Unwire(own)
		assert(A(c.Bryn).Ledger.Merge(Ldg(c.Bryn), { raw }).added == 1)
		net:Advance(60)
		for _, n in ipairs({ "Aurel", "Elin" }) do
			local S = A(c[n]).Sync
			eq(Ldg(c[n]).events[raw.id], nil, n .. " refused it")
			eq(S.refused[raw.id], "RANK_TOO_LOW")
		end
		local asked = A(c.Elin).Sync:Stats().asked
		net:Advance(120)
		eq(A(c.Elin).Sync:Stats().asked, asked, "a refused event is not asked again")
		deepEq(A(c.Elin).Ledger.Credits(Ldg(c.Elin), SEASON, { full = true }),
			A(c.Aurel).Ledger.Credits(Ldg(c.Aurel), SEASON, { full = true }))
	end)

	it("an author this client never saw is vouched for by the officer who relays it, within that officer's rank", function()
		-- Fara was an officer when Aurel's client knew her; she left before Elin's client ever read the roster
		local fara = { { name = "Fara", rank = 1, class = "MAGE" } }
		local net, c = guild({ "Aurel", "Bryn" }, { extra = { Aurel = fara } })
		openSeason(c.Aurel)
		local a, L = A(c.Aurel), Ldg(c.Aurel)
		assert(a.Ledger.Append(L, { author = full("Fara"), ts = now(c.Aurel), season = SEASON, type = "ITEM_AWARDED",
			payload = { member = full("Dara"), item = 19003, cost = 1 } }, gate(c.Aurel)))
		c.Aurel.Mock.guild.Remove("Fara")
		net:Advance(30)
		-- Bryn's roster never had Fara either: vouched by Aurel (the GM), accepted
		eq(Ldg(c.Bryn).events[full("Fara") .. ":1"].payload.cost, 1)
		local e = Ldg(c.Bryn).events[full("Fara") .. ":1"]

		-- the vouching officer's own rank is the limit: Bryn (rank 1) cannot bring in a configuration change (GM only)
		local cfg = { id = full("Ghost") .. ":1", author = full("Ghost"), seq = 1, ts = now(c.Bryn), type = "PERMISSIONS_CHANGED",
			v = 1, payload = { table = FDCP.Permissions.DefaultTable() } }
		local ok, code = A(c.Bryn).Sync:Gate(full("Bryn")).accept(Ldg(c.Bryn), cfg)
		falsy(ok); eq(code, "NOT_GM")
		-- an author the history knows is judged by their own rank, whoever relays it
		local member = { id = full("Corin") .. ":1", author = full("Corin"), seq = 1, ts = now(c.Bryn), season = SEASON,
			type = "ITEM_AWARDED", v = 1, payload = { member = full("Corin"), item = 19003, cost = 0 } }
		ok, code = A(c.Bryn).Sync:Gate(full("Aurel")).accept(Ldg(c.Bryn), member)
		falsy(ok); eq(code, "RANK_TOO_LOW")
		truthy(A(c.Bryn).Sync:Gate(full("Aurel")).accept(Ldg(c.Bryn), e))
	end)

	it("a member is not trusted as a relayer and an officer is", function()
		local net, c = guild({ "Aurel", "Bryn", "Corin" })
		local S = A(c.Bryn).Sync
		truthy(S:Trusted(full("Aurel"))); truthy(S:Trusted(full("Bryn")))
		falsy(S:Trusted(full("Corin"))); falsy(S:Trusted(full("Nobody"))); falsy(S:Trusted(nil))
		-- a member promoted to officer takes part from the next roster on
		c.Bryn.Mock.guild.SetRank("Corin", 1)
		net:Advance(3)
		truthy(S:Trusted(full("Corin")))
	end)
end)

describe("the end-of-season compaction in the sync (M6-7)", function()
	it("every officer compacts with the Guild Master, and one who was away takes the tombstones and catches up", function()
		local net, c = guild({ "Aurel", "Bryn", "Elin" })
		openSeason(c.Aurel)
		net:Advance(40)
		net:Logout("Elin")
		local b, L = A(c.Bryn), Ldg(c.Bryn)
		for n = 1, 2 do
			assert(b.Nights.Open(L, { author = full("Bryn"), ts = now(c.Bryn), season = SEASON, date = "2026-01-0" .. n,
				instanceID = 409, difficulty = "normal" }, gate(c.Bryn)))
			assert(b.Nights.SetLineup(L, { author = full("Bryn"), ts = now(c.Bryn), season = SEASON,
				raid = { full("Corin"), full("Dara"), full("Bryn") }, bench = { full("Elin") } }, gate(c.Bryn)))
			assert(b.Nights.Kill(L, { author = full("Bryn"), ts = now(c.Bryn), season = SEASON, encounterID = 660 + n,
				difficulty = 9 }, gate(c.Bryn)))
			assert(b.Ledger.Append(L, { author = full("Bryn"), ts = now(c.Bryn), season = SEASON, type = "ITEM_AWARDED",
				payload = { member = full("Dara"), item = 19003, cost = 1, response = "MS" } }, gate(c.Bryn)))
			assert(b.Nights.SetLineup(L, { author = full("Bryn"), ts = now(c.Bryn), season = SEASON,
				raid = { full("Elin") }, absent = { full("Corin") } }, gate(c.Bryn)))
			assert(b.Nights.Close(L, { author = full("Bryn"), ts = now(c.Bryn), season = SEASON }, gate(c.Bryn)))
			net:Advance(5)
		end
		net:Advance(30)
		local a = A(c.Aurel)
		assert(a.Season.Close(Ldg(c.Aurel), { author = full("Aurel"), ts = now(c.Aurel), season = SEASON }, gate(c.Aurel)))
		net:Advance(30)
		deepEq(ids(c.Bryn), ids(c.Aurel))
		local credits = a.Ledger.Credits(Ldg(c.Aurel), SEASON)
		local played = a.Nights.Played(Ldg(c.Aurel), SEASON)
		assert(a.BackupService:ArchiveText(SEASON))
		eq(assert(a.BackupService:Compact(SEASON, { confirmed = true, confirmedAgain = true })), 4)
		net:Advance(60)
		-- Bryn's client took the compaction: the same ledger, the same totals
		local function lineups(cl)
			local n = 0
			for _, e in pairs(Ldg(cl).events) do if e.type == "LINEUP_CHANGED" then n = n + 1 end end
			return n
		end
		eq(lineups(c.Aurel), 0); eq(lineups(c.Bryn), 0)
		deepEq(ids(c.Bryn), ids(c.Aurel))
		deepEq(Ldg(c.Bryn).gone, Ldg(c.Aurel).gone)
		deepEq(b.Ledger.Credits(L, SEASON), credits)
		deepEq(b.Nights.Played(L, SEASON), played)
		-- Elin was away the whole season: the compacted seqs come as tombstones, the rest as events
		net:Login("Elin")
		net:Advance(240)
		local e = A(c.Elin)
		deepEq(ids(c.Elin), ids(c.Aurel))
		deepEq(Ldg(c.Elin).gone, Ldg(c.Aurel).gone)
		deepEq(e.Ledger.Heads(Ldg(c.Elin)), a.Ledger.Heads(Ldg(c.Aurel)))
		deepEq(e.Ledger.Credits(Ldg(c.Elin), SEASON), credits)
		deepEq(e.Nights.Played(Ldg(c.Elin), SEASON), played)
		truthy(e.Sync:Stats().gone >= 4, "tombstones taken")
		truthy(e.Sync:Stats().asked <= 6, "no endless requests: " .. e.Sync:Stats().asked)
		eq(e.Sync:Stats().conflicts, 0)
	end)
end)
