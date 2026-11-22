-- CreditSnapshot: the read-only credits table every member sees (docs/ANALISI.md §8.4, M6-6). Pure Lua 5.1: it never
-- calls the game.
--
-- Only the officers hold the guild's ledger (M6-5). A member's client gets the numbers of the Credits tab as a snapshot
-- made by an officer's client: the season (the open one, else the newest), its newest nights, and per member the total
-- and what they spent in each of those nights. A snapshot is plain data in the wire form below; nothing in it is ever
-- turned into a ledger event, and the credits are still computed from the ledger on the officer's side.
--
--   { s = season id, sl = label, so = open?, up = "YYYY-MM-DD" (newest night) | nil, nn = nights in the season,
--     n = { { d = date, i = instanceID }, ... }   the newest MAX_NIGHTS nights, oldest first
--     r = { { m = member, c = class, ro = role, sp = ms1, st = status, f = faction, al = { alts }, t = total,
--             p = { nightIndex, cost, nightIndex, cost, ... } }, ... }
--     k = events in the officer's ledger, ts = server time it was made }
--
-- `k` orders snapshots: a ledger only grows (a set union of immutable events), so the snapshot of the larger ledger is
-- the newer one; equal `k`, the later `ts`. A kept snapshot older than STALE seconds gives way to any later one (an
-- end-of-season compaction may shrink a ledger, M6-7).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local CreditSnapshot = {}
ns.CreditSnapshot, ns.modules.CreditSnapshot = CreditSnapshot, CreditSnapshot

local type, ipairs, pairs, sort, floor = type, ipairs, pairs, table.sort, math.floor

CreditSnapshot.MAX_NIGHTS = 8       -- night columns carried (the Credits tab shows the newest eight)
CreditSnapshot.MAX_ROWS = 200       -- members carried (both factions)
CreditSnapshot.MAX_ALTS = 10        -- alts per member
CreditSnapshot.MAX_TEXT = 64        -- longest string field
CreditSnapshot.STALE = 7 * 86400    -- a kept snapshot this old gives way to any later one

local function str(v)
	return type(v) == "string" and #v > 0 and #v <= CreditSnapshot.MAX_TEXT and v or nil
end
local function num(v)
	return type(v) == "number" and v == v and v > -1e12 and v < 1e12 and v or nil
end
local function int(v)
	v = num(v)
	return v and v == floor(v) and v or nil
end

-- The season a snapshot is made of: the open one, else the newest.
local function seasonOf(L)
	local cur = ns.Season.Current(L)
	if cur then return cur end
	local list = ns.Season.List(L)
	return list[#list]
end

-- Builds the snapshot of ledger L (server time `ts`). nil and "NO_SEASON" when the ledger has no season.
function CreditSnapshot.Build(L, ts)
	local season = seasonOf(L)
	if not season then return nil, "NO_SEASON" end
	local data = ns.CreditTable.Build(L, season.id)
	if not data then return nil, "NO_SEASON" end
	local nights = data.nights
	local first = math.max(#nights - CreditSnapshot.MAX_NIGHTS + 1, 1)
	local n, index = {}, {}
	for i = first, #nights do
		local night = nights[i]
		n[#n + 1] = { d = night.date, i = night.instanceID }
		index[night.id] = #n
	end
	local r = {}
	for _, row in ipairs(data.rows) do
		if #r >= CreditSnapshot.MAX_ROWS then break end
		local p, keys = {}, {}
		for id in pairs(row.perNight) do if index[id] then keys[#keys + 1] = index[id] end end
		sort(keys)
		local byIndex = {}
		for id, v in pairs(row.perNight) do if index[id] then byIndex[index[id]] = v end end
		for _, k in ipairs(keys) do
			p[#p + 1] = k
			p[#p + 1] = byIndex[k]
		end
		local alts
		if row.alts and #row.alts > 0 then
			alts = {}
			for i, a in ipairs(row.alts) do if i <= CreditSnapshot.MAX_ALTS then alts[i] = a end end
		end
		r[#r + 1] = { m = row.member, c = row.class, ro = row.role, sp = row.ms1, st = row.status, f = row.faction,
			al = alts, t = row.total, p = #p > 0 and p or nil }
	end
	return { s = season.id, sl = season.label, so = not season.closed, up = data.updated, nn = #nights, n = n, r = r,
		k = ns.Ledger.Count(L), ts = ts }
end

-- A clean copy of a snapshot that came from the network: only the known fields, of the right types, within the limits.
-- nil and a code ("SHAPE", "SEASON", "ROWS", "NIGHTS") for anything else.
function CreditSnapshot.Clean(snap)
	if type(snap) ~= "table" then return nil, "SHAPE" end
	local k, ts = int(snap.k), int(snap.ts)
	if not k or k < 0 or not ts then return nil, "SHAPE" end
	local season = str(snap.s) or int(snap.s)
	if not season then return nil, "SEASON" end
	if type(snap.n) ~= "table" or #snap.n > CreditSnapshot.MAX_NIGHTS then return nil, "NIGHTS" end
	if type(snap.r) ~= "table" or #snap.r > CreditSnapshot.MAX_ROWS then return nil, "ROWS" end
	local out = { s = season, sl = str(snap.sl), so = snap.so == true, up = str(snap.up), k = k, ts = ts, n = {}, r = {} }
	for i, night in ipairs(snap.n) do
		if type(night) ~= "table" then return nil, "NIGHTS" end
		out.n[i] = { d = str(night.d), i = int(night.i) }
	end
	out.nn = int(snap.nn) or #out.n
	if out.nn < #out.n then out.nn = #out.n end
	local seen = {}
	for _, row in ipairs(snap.r) do
		local m, t = type(row) == "table" and str(row.m), type(row) == "table" and num(row.t)
		if not m or not t or seen[m] then return nil, "ROWS" end
		seen[m] = true
		local alts
		if type(row.al) == "table" then
			alts = {}
			for i, a in ipairs(row.al) do
				if i > CreditSnapshot.MAX_ALTS then break end
				if str(a) then alts[#alts + 1] = a end
			end
		end
		local p
		if type(row.p) == "table" then
			p = {}
			for i = 1, #row.p - 1, 2 do
				local idx, v = int(row.p[i]), num(row.p[i + 1])
				if idx and v and idx >= 1 and idx <= #out.n then
					p[#p + 1] = idx
					p[#p + 1] = v
				end
			end
		end
		out.r[#out.r + 1] = { m = m, t = t, c = str(row.c), ro = str(row.ro), sp = int(row.sp), st = str(row.st),
			f = str(row.f), al = alts, p = p }
	end
	return out
end

-- True when snapshot `a` should replace the kept one `b` (`now` = server time, for the STALE rule).
function CreditSnapshot.Newer(a, b, now)
	if not b then return a ~= nil end
	if not a then return false end
	if a.k ~= b.k then
		if a.k > b.k then return true end
		return now ~= nil and now - b.ts > CreditSnapshot.STALE and a.ts > b.ts
	end
	return a.ts > b.ts
end

-- The seasons of a snapshot, as CreditTable.Seasons gives them: one entry.
function CreditSnapshot.Seasons(snap)
	if not snap then return {} end
	return { { id = snap.s, label = snap.sl, open = snap.so, nights = snap.nn } }
end

-- The table of the snapshot's season in the form of CreditTable.Build (nil for another season): the night ids are the
-- positions 1..n; the ranks are counted among the rows of `faction` (nil = all), lowest total first, then the name.
function CreditSnapshot.Table(snap, season, faction)
	if not snap or (season ~= nil and season ~= snap.s) then return nil end
	local out = { season = snap.s, label = snap.sl, open = snap.so, updated = snap.up, nights = {}, rows = {},
		snapshot = true, k = snap.k, ts = snap.ts }
	for i, night in ipairs(snap.n) do
		out.nights[i] = { id = i, date = night.d, instanceID = night.i }
	end
	for _, row in ipairs(snap.r) do
		if faction == nil or row.f == nil or row.f == faction then
			local per = {}
			local p = row.p or {}
			for i = 1, #p - 1, 2 do per[p[i]] = p[i + 1] end
			out.rows[#out.rows + 1] = { member = row.m, class = row.c, role = row.ro, ms1 = row.sp, status = row.st,
				faction = row.f, alts = row.al, perNight = per, total = row.t }
		end
	end
	sort(out.rows, function(a, b)
		if a.total ~= b.total then return a.total < b.total end
		return a.member < b.member
	end)
	for i, r in ipairs(out.rows) do r.rank = i end
	return out
end

if ns.addon then ns.addon.CreditSnapshot = CreditSnapshot end   -- also reachable from tests
