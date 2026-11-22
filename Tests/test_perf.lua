-- Performance budgets of a long season (M7-5, docs/ANALISI.md §11): 20 raid nights, 40 raiders, hundreds of awards.
-- Time budgets are generous (CI machines vary; they catch an accidental O(n^2), not a few milliseconds); the size and the
-- network budgets are exact counts. The measurements are printed with -v and recorded in docs/ANALISI.md §11.
local GM, OFFICER = "Testchar-TestRealm", "Bryn-TestRealm"
local NIGHTS, RAIDERS, AWARDS_PER_NIGHT = 20, 40, 15

-- Budgets (see docs/ANALISI.md §11)
local BUDGET = {
	events = 2500,            -- the simulated season holds well under this many events
	bytes = 1024 * 1024,      -- estimated SavedVariables size of the whole ledger (1 MiB)
	computeSeconds = 2.0,     -- credits + per-night table + attendance of the full season, all together
	snapshotBytes = 6000,     -- the encoded credits snapshot an officer broadcasts
	snapshotSeconds = 1.0,    -- build + encode + decode + clean
	afterCompactBytes = 0.92, -- a compacted season keeps at most this fraction of the bytes (measured 0.89)
}

local function clock() return os.clock() end
-- The measured values are recorded in docs/ANALISI.md �11; the harness has no output channel for passing tests.
local function print() end

local function season()
	local L = FDCP.Ledger.New()
	local ts = 1
	local function t() ts = ts + 1; return ts end
	assert(FDCP.Season.Open(L, { author = GM, ts = t(), season = "S1", label = "Tier 1", instances = { { id = 409, size = 40 } } }))
	local names = {}
	for i = 1, RAIDERS do
		names[i] = ("Raider%02d-TestRealm"):format(i)
		assert(FDCP.Roster.Join(L, { author = OFFICER, ts = t(), season = "S1", member = names[i], faction = "Horde",
			ms1 = (i <= 4 and 73) or (i <= 12 and 257) or 72 }))
	end
	for n = 1, NIGHTS do
		assert(FDCP.Nights.Open(L, { author = OFFICER, ts = t(), season = "S1", date = ("2026-10-%02d"):format(n), instanceID = 409,
			difficulty = "normal", faction = "Horde" }))
		local raid = {}
		for i = 1, RAIDERS do raid[#raid + 1] = names[i] end
		assert(FDCP.Nights.SetLineup(L, { author = OFFICER, ts = t(), season = "S1", raid = raid, bench = {} }))
		-- a swap after each kill: a raider sits out, the next one of the bench comes in (the group changes during a night)
		local inRaid, onBench = names[RAIDERS], names[RAIDERS - 1]
		for k = 1, 6 do
			assert(FDCP.Nights.Kill(L, { author = OFFICER, ts = t(), season = "S1", encounterID = 100 + n * 10 + k, difficulty = 14 }))
			assert(FDCP.Nights.SetLineup(L, { author = OFFICER, ts = t(), season = "S1", raid = { onBench }, bench = { inRaid } }))
			inRaid, onBench = onBench, inRaid
		end
		for a = 1, AWARDS_PER_NIGHT do
			assert(FDCP.Ledger.Append(L, { author = OFFICER, ts = t(), season = "S1", type = "ITEM_AWARDED",
				payload = { member = names[((n * 7 + a * 3) % RAIDERS) + 1], item = 19000 + n * 100 + a,
					cost = 0.5 + (a % 3) * 0.5, response = "MS" } }))
		end
		assert(FDCP.Nights.Close(L, { author = OFFICER, ts = t(), season = "S1" }))
	end
	assert(FDCP.Season.Close(L, { author = GM, ts = t(), season = "S1" }))
	return L, names, t
end

local function count(L)
	local n = 0
	for _ in pairs(L.events) do n = n + 1 end
	return n
end

describe("a long season", function()
	it("stays inside the documented size and time budgets", function()
		local L = season()
		local n = count(L)
		local awards = NIGHTS * AWARDS_PER_NIGHT
		truthy(n >= awards, "the season holds the awards")
		truthy(n <= BUDGET.events, "events " .. n .. " over budget " .. BUDGET.events)

		local size = FDCP.Backup.Size(L)
		print(("  [perf] events=%d awards=%d estimated SavedVariables=%d bytes"):format(n, awards, size.bytes))
		truthy(size.bytes <= BUDGET.bytes, "size " .. size.bytes .. " over budget " .. BUDGET.bytes)

		local t0 = clock()
		local credits = FDCP.Ledger.Credits(L, "S1")
		local table_ = FDCP.CreditTable.Build(L, "S1", { faction = "Horde" })
		local att = FDCP.Nights.Attendance(L, "S1")
		local dt = clock() - t0
		print(("  [perf] credits + table + attendance: %.3f s"):format(dt))
		truthy(dt <= BUDGET.computeSeconds, "compute " .. dt .. " s over budget " .. BUDGET.computeSeconds)
		eq(#table_.rows, RAIDERS)
		truthy(credits ~= nil and att ~= nil)
	end)

	it("a credits snapshot stays small and is cheap to build and read", function()
		local L = season()
		local t0 = clock()
		local snap = assert(FDCP.CreditSnapshot.Build(L, 5000))
		local text = assert(FDCP.Codec:Encode("CSNAP", snap))
		local clean = assert(FDCP.CreditSnapshot.Clean(assert(FDCP.Codec:Decode(text))))
		local rows = FDCP.CreditSnapshot.Table(clean, "S1", "Horde").rows
		local dt = clock() - t0
		print(("  [perf] snapshot: %d bytes, %.3f s"):format(#text, dt))
		eq(#rows, RAIDERS)
		truthy(#text <= BUDGET.snapshotBytes, "snapshot " .. #text .. " bytes over budget " .. BUDGET.snapshotBytes)
		truthy(dt <= BUDGET.snapshotSeconds, "snapshot time " .. dt .. " over budget")
		-- it carries every raider and only the newest nights, so its size does not grow with the season
		eq(#snap.n, FDCP.CreditSnapshot.MAX_NIGHTS)
		eq(snap.nn, NIGHTS)
	end)

	it("compaction of the closed season shrinks it and keeps every total", function()
		local L = season()
		local before = FDCP.Backup.Size(L).bytes
		local credits = FDCP.Ledger.Credits(L, "S1")
		local ok, err = FDCP.Backup.Compact(L, { author = GM, ts = 900000, season = "S1" })
		assert(ok, err)
		local after = FDCP.Backup.Size(L).bytes
		print(("  [perf] compaction: %d -> %d bytes (%.0f%%)"):format(before, after, 100 * after / before))
		truthy(after <= before * BUDGET.afterCompactBytes, "compaction kept " .. after .. " of " .. before)
		deepEq(FDCP.Ledger.Credits(L, "S1"), credits)
	end)

	it("the officers' sync serves a full season within the network budget", function()
		-- docs/ANALISI.md §11: at most 200 events per request, 600 served every 5 minutes, 1800 bytes of text per message
		local L = season()
		local n = count(L)
		local minutes = math.ceil(n / 600) * 5
		print(("  [perf] a new officer pulls %d events in about %d minutes at 600 events per 5 minutes"):format(n, minutes))
		truthy(minutes <= 20, "a full season takes " .. minutes .. " minutes to serve")
	end)
end)
