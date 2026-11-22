-- Read-only credits for every member (M6-6, docs/ANALISI.md §8.4, ADR 0006): an officer's client sends the credits table
-- of the season on GUILD, a member's client asks for it at login (offers by WHISPER, the best one asked by WHISPER), keeps
-- the newest one an officer sent, and its Credits tab and loot popup read it. A snapshot from a non-officer is ignored.
-- Aurel is the Guild Master, Bryn and Elin officers (rank 1), Corin and Dara members (rank 3).
local REALM = "Camelot"
local SEASON = "S1"
local function full(name) return name .. "-" .. REALM end
local RANKS = { Aurel = 0, Bryn = 1, Elin = 1, Corin = 3, Dara = 3 }
local NAMES = { "Aurel", "Bryn", "Elin", "Corin", "Dara" }

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

local function openSeason(c)
	local a = A(c)
	assert(a.Season.Open(Ldg(c), { author = full(c.name), ts = now(c), season = SEASON, label = "Season 1",
		instances = { { id = 409, size = 40 } } }, nil, gate(c)))
	for _, m in ipairs({ "Bryn", "Elin", "Corin", "Dara" }) do
		assert(a.Roster.Join(Ldg(c), { author = full(c.name), ts = now(c), season = SEASON, member = full(m),
			faction = "Horde", ms1 = 73 }, nil, gate(c)))
	end
end

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

-- The totals a client shows: from the snapshot it kept, or from its own ledger.
local function shown(c)
	local a = A(c)
	local kept = a.Snapshot:ForView()
	local data
	if kept then
		data = a.CreditSnapshot.Table(kept.data, nil, "Horde")
	else
		data = a.CreditTable.Build(Ldg(c), SEASON, { faction = "Horde" })
	end
	local out = {}
	for _, r in ipairs(data and data.rows or {}) do out[r.member] = r.total end
	return out, data
end

local function officerTotals(c)
	local out = {}
	for _, r in ipairs(A(c).CreditTable.Build(Ldg(c), SEASON, { faction = "Horde" }).rows) do out[r.member] = r.total end
	return out
end

---------------------------------------------------------------------------------------------------------------------

describe("the snapshot itself", function()
	it("is built from the ledger, read back as the Credits tab's table, cleaned and ordered", function()
		local Lg, CS = FDCP.Ledger, FDCP.CreditSnapshot
		local L = Lg.New()
		local G = full("Aurel")
		assert(FDCP.Season.Open(L, { author = G, ts = 1, season = SEASON, label = "Season 1", instances = { { id = 409, size = 40 } } }))
		for i, m in ipairs({ { "Bryn", "Horde" }, { "Corin", "Horde" }, { "Fenn", "Alliance" } }) do
			assert(FDCP.Roster.Join(L, { author = G, ts = 1 + i, season = SEASON, member = full(m[1]), faction = m[2], ms1 = 73 }))
		end
		for d = 1, 10 do
			assert(FDCP.Nights.Open(L, { author = G, ts = 10 * d, season = SEASON, date = ("2026-01-%02d"):format(d),
				instanceID = 409, difficulty = "normal" }))
			assert(Lg.Append(L, { author = G, ts = 10 * d + 1, season = SEASON, type = "ITEM_AWARDED",
				payload = { member = full(d % 2 == 0 and "Bryn" or "Corin"), item = 19003, cost = 0.5 } }))
			assert(FDCP.Nights.Close(L, { author = G, ts = 10 * d + 2, season = SEASON }))
		end
		local snap = assert(CS.Build(L, 5000))
		eq(snap.s, SEASON); eq(snap.sl, "Season 1"); eq(snap.so, true); eq(snap.nn, 10); eq(#snap.n, CS.MAX_NIGHTS)
		eq(snap.n[1].d, "2026-01-03"); eq(snap.up, "2026-01-10"); eq(snap.k, Lg.Count(L)); eq(#snap.r, 3)
		-- it travels: encoded and decoded, cleaned, it gives the same table as the ledger (newest eight nights)
		local text = assert(FDCP.Codec:Encode("CSNAP", snap))
		local back = assert(FDCP.Codec:Decode(text))
		local clean = assert(CS.Clean(back))
		local t = CS.Table(clean, SEASON, "Horde")
		local ref = FDCP.CreditTable.Build(L, SEASON, { faction = "Horde" })
		eq(#t.rows, #ref.rows)
		for i, r in ipairs(t.rows) do
			eq(r.member, ref.rows[i].member); eq(r.total, ref.rows[i].total); eq(r.rank, ref.rows[i].rank)
		end
		eq(t.rows[1].perNight[8], 0.5, "the newest night is the eighth column")
		eq(#CS.Table(clean, SEASON).rows, 3, "both factions without a filter")
		eq(CS.Table(clean, "S9"), nil)
		deepEq(CS.Seasons(clean), { { id = SEASON, label = "Season 1", open = true, nights = 10 } })
		eq(CS.Build(Lg.New(), 1), nil)

		-- what does not look like a snapshot is refused; unknown fields are dropped
		eq(select(2, CS.Clean("x")), "SHAPE")
		eq(select(2, CS.Clean({ k = 1, ts = 1, s = SEASON, n = {}, r = { { m = "A" } } })), "ROWS")
		eq(select(2, CS.Clean({ k = 1, ts = 1, s = SEASON, n = {}, r = { { m = "A", t = 1 }, { m = "A", t = 2 } } })), "ROWS")
		local many = {}
		for i = 1, CS.MAX_NIGHTS + 1 do many[i] = { d = "2026-01-01", i = 409 } end
		eq(select(2, CS.Clean({ k = 1, ts = 1, s = SEASON, n = many, r = {} })), "NIGHTS")
		local odd = assert(CS.Clean({ k = 1, ts = 1, s = SEASON, n = { { d = "2026-01-01", i = 409 } }, x = 5,
			r = { { m = "A", t = 1, p = { 1, 2, 7, 3, "a", 4 }, evil = true } } }))
		eq(odd.x, nil); eq(odd.r[1].evil, nil); deepEq(odd.r[1].p, { 1, 2 })

		-- order: the larger ledger wins; equal, the later one; a stale one gives way
		local a, b = { k = 10, ts = 100 }, { k = 12, ts = 50 }
		truthy(CS.Newer(b, a)); falsy(CS.Newer(a, b)); truthy(CS.Newer(a, nil))
		truthy(CS.Newer({ k = 12, ts = 60 }, b)); falsy(CS.Newer({ k = 12, ts = 50 }, b))
		falsy(CS.Newer(a, b, 50 + CS.STALE))
		truthy(CS.Newer(a, b, 51 + CS.STALE))
	end)
end)

---------------------------------------------------------------------------------------------------------------------

describe("members converge on the officers' totals", function()
	it("a broadcast after a night reaches every member, and the Credits tab reads it", function()
		local net, c = guild({ "Aurel", "Bryn", "Corin", "Dara" })
		openSeason(c.Aurel)
		net:Advance(60)
		night(c.Aurel, "2026-01-07", { { "Corin", 1 }, { "Dara", 2 } })
		net:Advance(90)
		local want = officerTotals(c.Aurel)
		eq(want[full("Dara")], 2)
		deepEq(officerTotals(c.Bryn), want, "the officers synced first")
		for _, n in ipairs({ "Corin", "Dara" }) do
			eq(A(c[n]).Ledger.Count(Ldg(c[n])), 0, n .. " has no ledger of its own")
			deepEq((shown(c[n])), want, n .. " sees the officers' totals")
			local from = A(c[n]).Snapshot:Kept().from
			truthy(from == full("Aurel") or from == full("Bryn"), "from an officer")
		end
		-- the officers read their own ledger, not the snapshot
		eq(A(c.Bryn).Snapshot:ForView(), nil)
		-- one officer sent it, the other heard it and dropped its own plan
		local sent = A(c.Aurel).Snapshot:Stats().sent + A(c.Bryn).Snapshot:Stats().sent
		truthy(sent >= 1 and sent <= 3, "a broadcast or two, not one per officer per event: " .. sent)
		truthy(A(c.Aurel).Snapshot:Stats().cancelled + A(c.Bryn).Snapshot:Stats().cancelled >= 1)

		-- the member's window: the season of the snapshot, the night column, the note of where it came from
		local CW = A(c.Corin).CreditsWindow
		local src = CW:Source()
		truthy(src.snapshot)
		local data, rows = CW:Data(SEASON, src)
		eq(#data.nights, 1); eq(#rows, 4)
		local corin
		for _, r in ipairs(rows) do if r.member == full("Corin") then corin = r end end
		eq(corin.perNight[1], 1)
		-- drawn: the member's Credits tab shows the season, the night and the officers' totals, marked read-only
		c.Corin.Mock.Slash("/fdcp")
		A(c.Corin).MainWindow:SelectTab("credits")
		CW:Refresh()
		local card = CW.root.cards[SEASON]
		truthy(card and card:IsShown())
		contains(card.sub:GetText(), "read-only")
		eq(card.count:GetText(), "4 in the roster")
		local drawn = {}
		for _, r in ipairs(card.table:VisibleRows()) do drawn[r.data.member] = tonumber(r.cells[#card.table.columns]:GetText()) end
		deepEq(drawn, want)
		-- the popup's standing of the member
		local PB = A(c.Corin).PopupBoard
		local st = PB.Standing(full("Corin"), nil)
		eq(st.credits, 1)
		eq(st.position, 3, "Bryn and Elin at 0, then Corin")
	end)

	it("a member who logs in later asks, takes the best offer by whisper, and survives a /reload", function()
		local net, c = guild({ "Aurel", "Bryn", "Corin" })
		openSeason(c.Aurel)
		net:Advance(60)
		net:Logout("Corin")
		night(c.Aurel, "2026-01-07", { { "Dara", 1.5 } })
		net:Advance(90)
		local function answered() return A(c.Aurel).Snapshot:Stats().answered + A(c.Bryn).Snapshot:Stats().answered end
		local before = answered()
		net:Login("Corin")
		net:Advance(30)
		local s = A(c.Corin).Snapshot:Stats()
		eq(s.asked, 1); eq(s.kept, 1)
		deepEq((shown(c.Corin)), officerTotals(c.Aurel))
		truthy(A(c.Aurel).Snapshot:Stats().offered + A(c.Bryn).Snapshot:Stats().offered >= 1)
		eq(answered() - before, 1, "one officer answered")
		net:Reload("Corin")
		eq(A(c.Corin).Snapshot:Kept().data.k, A(c.Aurel).Ledger.Count(Ldg(c.Aurel)), "kept with the guild's data")
		deepEq((shown(c.Corin)), officerTotals(c.Aurel))
		net:Advance(30)
		eq(A(c.Corin).Snapshot:Stats().kept, 0, "up to date: no officer offers anything")
	end)

	it("an officer who is behind cannot take the members back, and a member asks again after a silent officer", function()
		local net, c = guild({ "Aurel", "Bryn", "Corin" })
		openSeason(c.Aurel)
		net:Advance(60)
		net:Logout("Bryn")
		night(c.Aurel, "2026-01-07", { { "Corin", 2 } })
		net:Advance(90)
		local k = A(c.Corin).Snapshot:Kept().data.k
		eq(k, A(c.Aurel).Ledger.Count(Ldg(c.Aurel)))
		-- Bryn comes back behind and sends the snapshot of the old ledger at once
		net:Login("Bryn")
		A(c.Bryn).Snapshot:Broadcast()
		net:Advance(5)
		eq(A(c.Corin).Snapshot:Kept().data.k, k, "the older snapshot was not kept")
		truthy(A(c.Corin).Snapshot:Stats().older >= 1)
		-- the request goes to the best offer; one that never answers is passed over for the next
		local S = A(c.Corin).Snapshot
		S.request = { phase = "offers", at = 0, offers = { [full("Ghost")] = k + 9, [full("Aurel")] = k + 1 } }
		S:Pick()
		eq(S.request.peer, full("Ghost"))
		net:Advance(S.REQUEST_TIMEOUT + 2)
		eq(S:Stats().timeouts, 1)
		eq(S.request, nil, "Aurel was asked and answered")
	end)
end)

---------------------------------------------------------------------------------------------------------------------

describe("trust", function()
	it("a snapshot from a non-officer is ignored, on GUILD and by whisper, and so are its offers", function()
		local net, c = guild({ "Aurel", "Corin", "Dara" })
		openSeason(c.Aurel)
		net:Advance(60)
		night(c.Aurel, "2026-01-07", { { "Dara", 1 } })
		net:Advance(90)
		local k = A(c.Dara).Snapshot:Kept().data.k
		local want = officerTotals(c.Aurel)
		deepEq((shown(c.Dara)), want)
		-- Corin forges a newer snapshot where everybody but Corin has spent a lot
		local forged = A(c.Aurel).CreditSnapshot.Build(Ldg(c.Aurel), now(c.Aurel))
		forged.t, forged.k, forged.ts = "CSNAP", k + 100, now(c.Aurel) + 10
		for _, r in ipairs(forged.r) do r.t = r.m == full("Corin") and -50 or 99 end
		A(c.Corin).Transport:Send("GUILD", forged)
		A(c.Corin).Transport:Send("WHISPER", forged, { target = full("Dara") })
		A(c.Corin).Transport:Send("WHISPER", { t = "CSNAPO", k = k + 100 }, { target = full("Dara") })
		net:Advance(5)
		eq(A(c.Dara).Snapshot:Kept().data.k, k)
		deepEq((shown(c.Dara)), want, "Dara still sees the officers' totals")
		truthy(A(c.Dara).Snapshot:Stats().untrusted >= 3)
		eq(A(c.Aurel).Snapshot:Stats().kept, 0, "nor did the officer keep it")
		-- the request of a member is only answered by an officer: Corin offers nothing
		local S = A(c.Dara).Snapshot
		S:Ask()
		net:Advance(S.OFFER_WAIT + 2)
		eq(A(c.Corin).Snapshot:Stats().offered, 0)
		-- a message of these types on another channel is ignored
		local dist = A(c.Dara).Snapshot:Stats().dist
		A(c.Aurel).Transport:Send("GUILD", { t = "CSNAPO", k = k + 100 })
		net:Advance(3)
		eq(A(c.Dara).Snapshot:Stats().dist, dist + 1)
		eq(A(c.Dara).Snapshot:Kept().data.k, k)
	end)

	it("a demoted officer is no longer trusted and a promoted member is", function()
		local net, c = guild({ "Aurel", "Bryn", "Corin" })
		openSeason(c.Aurel)
		net:Advance(60)
		local snap = A(c.Bryn).Snapshot:Make()
		snap.t, snap.k = "CSNAP", snap.k + 50
		c.Corin.Mock.guild.SetRank("Bryn", 3)
		net:Advance(3)
		A(c.Bryn).Transport:Send("GUILD", snap)
		net:Advance(3)
		falsy(A(c.Corin).Snapshot:Kept() and A(c.Corin).Snapshot:Kept().data.k == snap.k, "Bryn's rank is a member's now")
		c.Corin.Mock.guild.SetRank("Bryn", 1)
		net:Advance(3)
		snap.ts = snap.ts + 1
		A(c.Bryn).Transport:Send("GUILD", snap)
		net:Advance(3)
		eq(A(c.Corin).Snapshot:Kept().data.k, snap.k)
	end)

	it("a snapshot heard before the roster is read is not judged, and the member asks once the roster is in", function()
		local net, c = guild({ "Aurel", "Corin" })
		local S = A(c.Corin).Snapshot
		local PS = A(c.Corin).PermissionService
		local ready = PS.IsReady
		PS.IsReady = function() return false end
		openSeason(c.Aurel)
		A(c.Aurel).Snapshot:Broadcast()
		net:Advance(5)
		eq(S:Kept(), nil)
		truthy(S:Stats().early >= 1)
		PS.IsReady = ready
		S.active = nil
		net:Advance(30)
		eq(S:Kept().from, full("Aurel"))
	end)
end)
