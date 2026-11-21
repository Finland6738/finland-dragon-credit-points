-- CreditTable: the numbers of the Credits tab (docs/ANALISI.md §9.3 point 4, docs/specs/ui-style.md §3, §6; M3-8). Pure Lua
-- 5.1: it never calls the game. Everything is read from the ledger, nothing is stored: the credits of a member are the
-- ledger's (Ledger.Credits), and the columns of the table are the nights of the season with what each member spent in them.
--
-- * A night's column holds, per member, the cost of the valid awards (ITEM_AWARDED to a member, not voided) of that night.
--   An award belongs to the night named in its payload (`night`, written from M4 on) or else to the night that was open when
--   it was written: the newest night opened before it that was not closed before it, and failing that the newest opened
--   before it. An award before any night (or in a season with none) is only in the total.
-- * `total` is the ledger's number (initial credits + awards + adjustments); `base` is what the night columns do not
--   explain (the initial credits and the adjustments), so total = base + the sum of the nights.
-- * `rank` is the queue position: the lowest total first, then the name (the site's rule), counted among the playing members
--   of the faction, so the filters of the window never change it.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local CreditTable = {}
ns.CreditTable, ns.modules.CreditTable = CreditTable, CreditTable

local ipairs, pairs, sort = ipairs, pairs, table.sort

local function Ledger() return ns.Ledger end

-- The night an award belongs to: an id of `nights` (the list of Nights.List, in the order they were opened), or nil.
local function nightOf(L, e, payload, nights, byId)
	if payload.night and byId[payload.night] then return payload.night end
	local best
	for _, n in ipairs(nights) do
		local ne = L.events[n.id]
		if ne and Ledger().Before(ne, e) then
			local closedBefore = n.closeId and L.events[n.closeId] and Ledger().Before(L.events[n.closeId], e)
			if not closedBefore then best = n.id end
		end
	end
	if best then return best end
	for _, n in ipairs(nights) do
		local ne = L.events[n.id]
		if ne and Ledger().Before(ne, e) then best = n.id end
	end
	return best
end

-- The credits each member spent per night: { [member] = { [nightId] = n } }.
function CreditTable.PerNight(L, season, nights)
	local Lg = Ledger()
	local voided = Lg.State(L).voided
	local byId = {}
	for _, n in ipairs(nights) do byId[n.id] = n end
	local out = {}
	for _, e in ipairs(Lg.Sorted(L, function(x) return x.season == season and x.type == "ITEM_AWARDED" end)) do
		local p = Lg.Readable(e) and Lg.Payload(e)
		if p and not voided[e.id] and (p.target or "member") == "member" and (p.cost or 0) ~= 0 then
			local night = nightOf(L, e, p, nights, byId)
			if night then
				local row = out[p.member]
				if not row then row = {}; out[p.member] = row end
				row[night] = (row[night] or 0) + p.cost
			end
		end
	end
	for _, row in pairs(out) do
		for id, v in pairs(row) do row[id] = Lg.Round(v) end
	end
	return out
end

-- The table of one season: { season, label, open, updated, nights = { { id, date, instanceID, size, difficulty, closed } ...},
-- rows = { { member, class, role, ms1, status, faction, alts, perNight = { [nightId] = n }, base, total, rank } ... } }, the
-- rows in queue order. opts = { faction? }. nil and "SEASON_UNKNOWN" when the season does not exist.
function CreditTable.Build(L, season, opts)
	opts = opts or {}
	local s = ns.Season.Get(L, season)
	if not s then return nil, "SEASON_UNKNOWN" end
	local nights = ns.Nights.List(L, season)
	local credits = ns.Ledger.Credits(L, season)
	local spent = CreditTable.PerNight(L, season, nights)
	local out = { season = season, label = s.label, open = not s.closed, nights = nights, rows = {} }
	for _, n in ipairs(nights) do
		if n.date and (not out.updated or n.date > out.updated) then out.updated = n.date end
	end
	for _, m in ipairs(ns.Roster.List(L, season, { playing = true, faction = opts.faction })) do
		local per = spent[m.member] or {}
		local total = credits[m.member] or m.initialCredits or 0
		local sum = 0
		for _, v in pairs(per) do sum = sum + v end
		out.rows[#out.rows + 1] = {
			member = m.member, class = m.class, role = m.role, ms1 = m.ms1, status = m.status, faction = m.faction,
			alts = m.alts, perNight = per, total = total, base = Ledger().Round(total - sum),
		}
	end
	sort(out.rows, function(a, b)
		if a.total ~= b.total then return a.total < b.total end
		return a.member < b.member
	end)
	for i, r in ipairs(out.rows) do r.rank = i end
	return out
end

-- The seasons newest first: { { id, label, open, nights = n } ... } (the window's accordion).
function CreditTable.Seasons(L)
	local list = ns.Season.List(L)
	local out = {}
	for i = #list, 1, -1 do
		local s = list[i]
		out[#out + 1] = { id = s.id, label = s.label, open = not s.closed, nights = #ns.Nights.List(L, s.id) }
	end
	return out
end

-- Filters a table's rows by role and class (nil = all): a new list, the ranks untouched.
function CreditTable.Filter(rows, role, class)
	local out = {}
	for _, r in ipairs(rows) do
		if (role == nil or r.role == role) and (class == nil or r.class == class) then out[#out + 1] = r end
	end
	return out
end

if ns.addon then ns.addon.CreditTable = CreditTable end   -- also reachable from tests
