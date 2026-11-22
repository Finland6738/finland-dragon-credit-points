-- History: the readable views of the ledger (docs/ANALISI.md §7, docs/specs/ui-style.md §6, M6-1). Pure Lua 5.1: it never
-- calls the game and stores nothing: every number is computed from the ledger of events, the same way the credits are.
--
--   History.Nights(L, season, opts)       the nights of a season by week, newest first: instance, bosses, drops, credits spent
--   History.Member(L, season, member, o)  a member's items, credit curve, council actions and (officers only) attendance
--   History.Item(L, item, opts)           an item's drops and owners, across seasons
--
-- Attendance is for the officers only (`view.attendance`, §6, owner decision): who was in the raid or on the bench, and
-- how often a member played, is returned **only** when `opts.attendance` is true (the caller asks the permission service);
-- without it the fields do not exist in the answers, so no window can show what the data does not carry. Awards and credits
-- are public (the Credits tab shows them to every member).
--
-- An award belongs to a night the way Domain/CreditTable.lua says (the `night` of its payload, else the night that was open).
-- A voided award stays in the lists marked `voided` (the history says what happened) and moves no credits; corrections and
-- voids read from the council's audit (Domain/Council.lua).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local History = {}
ns.History, ns.modules.History = History, History

local ipairs, pairs, type = ipairs, pairs, type
local floor, sort = math.floor, table.sort

local function Lg() return ns.Ledger end

---------------------------------------------------------------------------------------------------------------------
-- Weeks: a night belongs to the week (Monday to Sunday) of its date; the week is named by its Monday, "YYYY-MM-DD".

local function dayNumber(y, m, d)   -- days since 1970-01-01 (proleptic Gregorian)
	if m <= 2 then y = y - 1 end
	local era = floor(y / 400)
	local yoe = y - era * 400
	local doy = floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
	local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

local function civil(z)
	z = z + 719468
	local era = floor(z / 146097)
	local doe = z - era * 146097
	local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
	local mp = floor((5 * doy + 2) / 153)
	local d = doy - floor((153 * mp + 2) / 5) + 1
	local m = mp < 10 and mp + 3 or mp - 9
	if m <= 2 then y = y + 1 end
	return y, m, d
end

-- The Monday of the week of a "YYYY-MM-DD" date, or nil for a date that is not one.
function History.WeekOf(date)
	if not ns.Nights.ValidDate(date) then return nil end
	local y, m, d = date:match("^(%d+)%-(%d+)%-(%d+)$")
	local z = dayNumber(tonumber(y), tonumber(m), tonumber(d))
	local monday = z - ((z + 3) % 7)   -- 1970-01-01 was a Thursday
	return ("%04d-%02d-%02d"):format(civil(monday))
end

---------------------------------------------------------------------------------------------------------------------
-- Awards

local function payloadOf(e)
	return Lg().Readable(e) and Lg().Payload(e) or nil
end

-- One award as the views show it.
local function awardRow(L, e, p, nights, byId, voided)
	local night = ns.CreditTable.NightOf(L, e, p, nights, byId)
	return { id = e.id, season = e.season, ts = e.ts, author = e.author, item = p.item, member = p.member,
		target = p.target or "member", cost = p.cost or 0, response = p.response, reasons = p.reasons, flags = p.flags,
		night = night, nightDate = night and byId[night] and byId[night].date or nil, voided = voided or nil }
end

-- Every ITEM_AWARDED of a season, canonical order: { row ... } (the night each belongs to is in `night`).
local function seasonAwards(L, season, nights)
	local byId = {}
	for _, n in ipairs(nights) do byId[n.id] = n end
	local Lg0 = Lg()
	local out = {}
	for _, e in ipairs(Lg0.Sorted(L, function(x) return x.season == season and x.type == "ITEM_AWARDED" end)) do
		local p = payloadOf(e)
		if p then
			out[#out + 1] = awardRow(L, e, p, nights, byId, Lg0.IsVoided(L, e.id))
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Nights

local function bossCount(instanceID)
	local inst = ns.Instances and ns.Instances.Get(instanceID)
	return inst and inst.bosses and #inst.bosses or nil
end

-- The nights of a season by week: { season, weeks = { { week = "YYYY-MM-DD" (a Monday), nights = {...} } ... }, nights = {...} },
-- the weeks and the nights in each newest first (the flat `nights` is the same order). A night is
--   { id, date, week, instanceID, size, difficulty, closed, ml?, bosses = { encounterID ... } (the kills, in order),
--     bossTotal? (the instance's bosses), drops = { award rows }, dropCount (every award, a voided one included),
--     spent (the credits the valid awards cost), awardedTo = n (valid awards to members) }.
-- With opts.attendance (officers) a night also has `lineup = { raid = {...}, bench = {...} }`: who was in the raid and on the
-- bench at the end of the night. nil and "SEASON_UNKNOWN" for a season that does not exist.
function History.Nights(L, season, opts)
	opts = opts or {}
	if not ns.Season.Get(L, season) then return nil, "SEASON_UNKNOWN" end
	local list = ns.Nights.List(L, season)
	local awards = seasonAwards(L, season, list)
	local kills = ns.Nights.Kills(L, { season = season })
	local flat = {}
	for _, n in ipairs(list) do
		local rec = { id = n.id, date = n.date, week = History.WeekOf(n.date), instanceID = n.instanceID, size = n.size,
			difficulty = n.difficulty, closed = n.closed, ml = n.ml, bosses = {}, bossTotal = bossCount(n.instanceID),
			drops = {}, dropCount = 0, spent = 0, awardedTo = 0, openedAt = n.openedAt }
		for _, k in ipairs(kills) do
			if k.night == n.id then rec.bosses[#rec.bosses + 1] = k.encounterID end
		end
		for _, a in ipairs(awards) do
			if a.night == n.id then
				rec.drops[#rec.drops + 1] = a
				rec.dropCount = rec.dropCount + 1
				if not a.voided and a.target == "member" then
					rec.awardedTo = rec.awardedTo + 1
					rec.spent = rec.spent + a.cost
				end
			end
		end
		rec.spent = Lg().Round(rec.spent)
		if opts.attendance then
			local lists = ns.Nights.Lists(ns.Nights.Lineup(L, n.id))
			rec.lineup = { raid = lists.raid, bench = lists.bench }
		end
		flat[#flat + 1] = rec
	end
	-- newest first: by date, then by when they were opened
	sort(flat, function(a, b)
		if a.date ~= b.date then return a.date > b.date end
		return a.openedAt > b.openedAt
	end)
	local weeks, byWeek = {}, {}
	for _, n in ipairs(flat) do
		local w = n.week or ""
		if not byWeek[w] then
			byWeek[w] = { week = w, nights = {} }
			weeks[#weeks + 1] = byWeek[w]
		end
		local wk = byWeek[w]
		wk.nights[#wk.nights + 1] = n
	end
	return { season = season, weeks = weeks, nights = flat }
end

---------------------------------------------------------------------------------------------------------------------
-- Member

-- What the council did about a member (Council.Audit), the entries of `season` that name them: a void names the award it
-- cancels, so the member is read from that award.
local function councilAbout(L, season, member)
	local out = {}
	for _, entry in ipairs(ns.Council.Audit(L, season)) do
		local who = entry.member
		if entry.kind == "VOID" and entry.ref then
			local ref = L.events[entry.ref]
			local rp = ref and payloadOf(ref)
			who = rp and rp.member or who
		end
		if who == member then out[#out + 1] = entry end
	end
	return out
end

-- A member of a season: { member, class, role, ms1, status, joinedAt, initial, total,
--   items = { award rows of the member (target "member"), voided ones marked },
--   curve = { { ts, id?, kind = "START" | "AWARD" | "ADJUST", delta, total } ... } (the credits after each move, canonical
--             order; the last total is the ledger's number), council = { audit entries about the member } }
-- With opts.attendance (officers): attendance = { nights, played, benched, bosses, possible, percent, perNight = { { night,
-- date, state = "PLAYED" | "BENCH" | "ABSENT" } ... } }. nil and "SEASON_UNKNOWN" / "MEMBER_UNKNOWN" otherwise.
function History.Member(L, season, member, opts)
	opts = opts or {}
	local Lg0 = Lg()
	if not ns.Season.Get(L, season) then return nil, "SEASON_UNKNOWN" end
	local rs = ns.Roster.State(L, season)
	local m = rs.members[member]
	if not m then return nil, "MEMBER_UNKNOWN" end
	local info
	for _, row in ipairs(ns.Roster.List(L, season)) do
		if row.member == member then info = row; break end
	end
	info = info or {}
	local joined = L.events[m.joined]
	local out = { member = member, class = info.class, role = info.role, ms1 = info.ms1, status = info.status,
		faction = info.faction, joinedAt = joined and joined.ts, initial = m.initialCredits or 0, items = {}, curve = {},
		council = councilAbout(L, season, member) }
	local running = out.initial
	out.curve[1] = { ts = joined and joined.ts or 0, kind = "START", delta = out.initial, total = Lg0.Round(running) }
	local nights = ns.Nights.List(L, season)
	local byId = {}
	for _, n in ipairs(nights) do byId[n.id] = n end
	for _, e in ipairs(Lg0.Sorted(L, function(x)
		return x.season == season and (x.type == "ITEM_AWARDED" or x.type == "CREDITS_ADJUSTED")
	end)) do
		local p = payloadOf(e)
		if p and p.member == member then
			local voided = Lg0.IsVoided(L, e.id)
			if e.type == "ITEM_AWARDED" then
				if (p.target or "member") == "member" then
					out.items[#out.items + 1] = awardRow(L, e, p, nights, byId, voided)
					if not voided and (p.cost or 0) ~= 0 then
						running = running + p.cost
						out.curve[#out.curve + 1] = { ts = e.ts, id = e.id, kind = "AWARD", delta = p.cost, total = Lg0.Round(running) }
					end
				end
			elseif not voided then
				running = running + p.delta
				out.curve[#out.curve + 1] = { ts = e.ts, id = e.id, kind = "ADJUST", delta = p.delta, total = Lg0.Round(running) }
			end
		end
	end
	out.total = Lg0.Round(running)
	if opts.attendance then
		local att = ns.Nights.Attendance(L, season)
		local a = att.members[member] or { nights = 0, played = 0, benched = 0, bosses = 0, possible = 0 }
		local perNight = {}
		for _, rec in ipairs(att.nights) do
			local state = rec.played[member] and "PLAYED" or rec.benched[member] and "BENCH" or "ABSENT"
			perNight[#perNight + 1] = { night = rec.night.id, date = rec.night.date, state = state }
		end
		out.attendance = { nights = a.nights, played = a.played, benched = a.benched, bosses = a.bosses, possible = a.possible,
			percent = a.possible > 0 and floor(a.bosses * 100 / a.possible + 0.5) or 0, perNight = perNight }
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Item

-- An item across the ledger (opts.season = one season only): { item, drops = { award rows, canonical order }, count (valid
-- awards), seen (DROP_SEEN events naming it), owners = { { member, count } ... } (valid awards to members, the most first, then
-- the name) }. An item nobody saw or received has no drops: the answer is still a table (count 0).
function History.Item(L, item, opts)
	opts = opts or {}
	local Lg0 = Lg()
	local out = { item = item, drops = {}, count = 0, seen = 0, owners = {} }
	local nightsOf = {}
	local owners = {}
	for _, e in ipairs(Lg0.Sorted(L, function(x)
		return (x.type == "ITEM_AWARDED" or x.type == "DROP_SEEN") and (opts.season == nil or x.season == opts.season)
	end)) do
		local p = payloadOf(e)
		if p and p.item == item then
			if e.type == "DROP_SEEN" then
				out.seen = out.seen + 1
			else
				local nights = nightsOf[e.season]
				if not nights then
					nights = e.season ~= nil and ns.Nights.List(L, e.season) or {}
					nightsOf[e.season] = nights
				end
				local byId = {}
				for _, n in ipairs(nights) do byId[n.id] = n end
				local row = awardRow(L, e, p, nights, byId, Lg0.IsVoided(L, e.id))
				out.drops[#out.drops + 1] = row
				if not row.voided then
					out.count = out.count + 1
					if row.target == "member" and row.member then owners[row.member] = (owners[row.member] or 0) + 1 end
				end
			end
		end
	end
	for member, n in pairs(owners) do out.owners[#out.owners + 1] = { member = member, count = n } end
	sort(out.owners, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.member < b.member
	end)
	return out
end

if ns.addon then ns.addon.History = History end   -- also reachable from tests
