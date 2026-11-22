-- SiteExport: the three files of the community site's WoW Forever page, built from the ledger (docs/specs/site-export.md,
-- docs/ANALISI.md §7.1, M6-4). Pure Lua 5.1: it never calls the game and stores nothing; the game's answers (the realm's
-- day, an item's name in the client's language, the labels) come in through `opts`. Same ledger and same options give the
-- same bytes.
--
--   SiteExport.Roster(L, season, opts)   roster.json: the playing mains of the guild's faction (Raider / Trial)
--   SiteExport.Season(L, season, opts)   one season of loot.json: roster of the season, one raid per closed night, the awards
--   SiteExport.Loot(L, opts)             loot.json: every season of the ledger, newest first
--   SiteExport.Progress(L, opts)         progress.json: the guild's own faction key only, first kills (Domain/Progress.lua)
--   SiteExport.Build(L, opts)            all three, as JSON text (the full files and the fragments) and the warnings
--
-- What the site wants (read from its source, never modified): `scripts/validate.mjs` stops the deploy when a class is not one
-- of the nine, a role is not tank/healer/dps, an award's player is not in the season's roster or a `cost` is not 0, 1 or 2.
-- So the export is the **current state** of the ledger: a voided award is left out, a corrected award has its corrected cost,
-- an award that cannot be shown (a bank item, a member outside the roster, a night still open) is left out and counted in
-- the warnings. The totals are never written: the site adds up the costs, as the addon does. A starting credit of a member
-- (a late joiner's average) becomes synthetic award rows of 2 and 1 in the member's first night, which keeps the site's total
-- equal to the addon's; with `opts.extended` (the hidden option of issue #3, off) it is `start` on the roster row instead, and
-- manual adjustments are written as rows with `kind = "adjust"`.
--
-- Attendance, bench, notes, council reasons, alts and realms never appear: the data below carries only what the site shows.
-- opts = { faction? (the client's faction token: only that faction's members), siteFaction (the guild's key on the site),
--          today ("YYYY-MM-DD", the day of the export), itemName? (function(itemID) -> string|nil), labels? = { startCredits,
--          adjustment }, extended? }. The permission `export.public` is the caller's to check.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local SiteExport = {}
ns.SiteExport, ns.modules.SiteExport = SiteExport, SiteExport

local type, ipairs, pairs, tostring, floor = type, ipairs, pairs, tostring, math.floor
local sort, concat = table.sort, table.concat

SiteExport.COST_MAX = 2   -- the site accepts 0, 1 or 2 on an award row
SiteExport.CLASSES = { warrior = true, paladin = true, hunter = true, rogue = true, priest = true, shaman = true,
	mage = true, warlock = true, druid = true }
SiteExport.FILES = { "roster", "loot", "progress" }
-- data for the site, not interface text: the window passes the guild language's words (SITE_START_CREDITS, SITE_ADJUSTMENT)
SiteExport.DEFAULT_LABELS = { startCredits = "Starting credits (roster average)", adjustment = "Credits adjustment" }   -- nolocale

---------------------------------------------------------------------------------------------------------------------
-- JSON: an object keeps its keys in the order they were written, so the bytes are the same every time

local NULL = {}
SiteExport.NULL = NULL

-- An object: O(inline, k1, v1, k2, v2, ...); a nil value is skipped, NULL writes null. `inline` = one line.
local function O(inline, ...)
	local o = { __o = true, inline = inline, list = {} }
	local n = select("#", ...)
	local args = { ... }
	for i = 1, n, 2 do
		if args[i + 1] ~= nil then o.list[#o.list + 1] = { args[i], args[i + 1] } end
	end
	return o
end

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function jstr(s)
	return '"' .. tostring(s):gsub('[%c"\\]', function(c) return ESC[c] or ("\\u%04x"):format(c:byte()) end) .. '"'
end

local function jnum(n)
	n = floor(n * 100 + 0.5) / 100
	local s = ("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", "")
	if s == "-0" then s = "0" end
	return s
end

local function scalar(v)
	local t = type(v)
	return v == NULL or t == "string" or t == "number" or t == "boolean"
end

local function enc(v, depth)
	if v == NULL then return "null" end
	local t = type(v)
	if t == "string" then return jstr(v) end
	if t == "number" then return jnum(v) end
	if t == "boolean" then return v and "true" or "false" end
	local pad, pad1 = ("  "):rep(depth), ("  "):rep(depth + 1)
	if v.__o then
		if #v.list == 0 then return "{}" end
		local parts = {}
		for i, kv in ipairs(v.list) do
			parts[i] = jstr(kv[1]) .. ": " .. enc(kv[2], depth + 1)
		end
		if v.inline then return "{ " .. concat(parts, ", ") .. " }" end
		return "{\n" .. pad1 .. concat(parts, ",\n" .. pad1) .. "\n" .. pad .. "}"
	end
	if #v == 0 then return "[]" end
	local allScalar = true
	for _, x in ipairs(v) do
		if not scalar(x) then allScalar = false end
	end
	local parts = {}
	for i, x in ipairs(v) do parts[i] = enc(x, depth + 1) end
	if allScalar then return "[" .. concat(parts, ", ") .. "]" end
	return "[\n" .. pad1 .. concat(parts, ",\n" .. pad1) .. "\n" .. pad .. "]"
end

-- The JSON text of a value built with O() (a final newline included).
function SiteExport.Encode(v)
	return enc(v, 0) .. "\n"
end

---------------------------------------------------------------------------------------------------------------------
-- Small helpers

local function short(name) return (tostring(name or "?"):gsub("%-.*$", "")) end

local function Ledger() return ns.Ledger end

-- Warnings: a list of { code, n } in the order they first happened (the caller shows codes; Domain/ carries no text).
local function newWarnings()
	local w = { list = {}, at = {} }
	function w.add(code, n)
		local i = w.at[code]
		if not i then
			w.list[#w.list + 1] = { code = code, n = 0 }
			i = #w.list
			w.at[code] = i
		end
		w.list[i].n = w.list[i].n + (n or 1)
	end
	return w
end

-- "YYYY-MM-DD" -> "DD/MM" (the site shows no year), anything else is kept.
local function dayMonth(iso)
	local _, m, d = tostring(iso or ""):match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
	if not m then return tostring(iso or "") end
	return d .. "/" .. m
end

-- A cost as award rows: a list of costs in {0, 1, 2}, and whether the number had to be rounded. 3 is 2 + 1.
local function costParts(cost)
	local r = floor((cost or 0) + 0.5)
	local rounded = r ~= cost
	if r <= 0 then return { 0 }, rounded end
	local parts = {}
	while r > 0 do
		if r >= SiteExport.COST_MAX then parts[#parts + 1] = SiteExport.COST_MAX; r = r - SiteExport.COST_MAX
		else parts[#parts + 1] = 1; r = r - 1 end
	end
	return parts, rounded
end

-- A season id as it is written in the raid ids: letters and digits, the rest becomes "-" ("Season 1" -> "Season-1").
local function slug(label)
	local s = tostring(label):gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
	return s == "" and "x" or s
end

local function seasonLabel(s) return tostring(s.label or s.id) end

-- The season the roster.json and the fragments are about: the open one, else the newest.
function SiteExport.CurrentSeason(L)
	local cur = ns.Season.Current(L)
	if cur then return cur end
	local list = ns.Season.List(L)
	return list[#list]
end

---------------------------------------------------------------------------------------------------------------------
-- The pool of a season

-- The members of the season's pool the site can show: { list = { { member, name, class, spec, role, status, rank, joinedTs,
-- initial } ... } (the Roster's order: class, then name), by = { [member] = entry } }. A member without a declaration (class,
-- spec) cannot be shown: it is left out and counted. `opts.faction` keeps one faction's members (a member with no faction
-- counts for every faction, as in the Roster tab).
local function pool(L, season, opts, warn)
	local list, by = {}, {}
	for _, m in ipairs(ns.Roster.List(L, season)) do
		if opts.faction == nil or not m.faction or m.faction == opts.faction then
			local site = m.ms1 and ns.Specs and ns.Specs.Site(m.ms1) or nil
			local class = m.class and m.class:lower() or nil
			local role = ns.Specs and ns.Specs.SITE_ROLE and ns.Specs.SITE_ROLE[m.role] or (site and site.role) or nil
			if site and class and SiteExport.CLASSES[class] and role then
				local je = L.events[m.joined]
				local e = { member = m.member, name = short(m.member), class = class, spec = site.spec, role = role, status = m.status,
					rank = ns.Roster.SITE_RANK[m.status], joinedTs = je and je.ts or 0, initial = m.initialCredits or 0 }
				list[#list + 1] = e
				by[m.member] = e
			else
				warn.add("MEMBER_NOT_SHOWN")
			end
		end
	end
	return { list = list, by = by }
end

---------------------------------------------------------------------------------------------------------------------
-- roster.json

local function rosterObject(L, season, opts, warn)
	local players = {}
	if season then
		for _, e in ipairs(pool(L, season, opts, warn).list) do
			if e.rank then
				players[#players + 1] = O(true, "name", e.name, "class", e.class, "spec", e.spec, "role", e.role,
					"faction", opts.siteFaction or "", "rank", e.rank)
			end
		end
	end
	return players
end

-- roster.json for a season (default: the current one): { O object, players array }. The players are the playing mains
-- (active: Raider, in trial: Trial) of the guild's faction.
function SiteExport.Roster(L, season, opts)
	opts = opts or {}
	local warn = newWarnings()
	if season == nil then
		local s = SiteExport.CurrentSeason(L)
		season = s and s.id
	end
	local players = rosterObject(L, season, opts, warn)
	return O(false, "updated", opts.today or "", "players", players), players, warn.list
end

---------------------------------------------------------------------------------------------------------------------
-- loot.json

-- One season of loot.json. Returns the object, the list of warnings and nil; or nil and "SEASON_UNKNOWN".
function SiteExport.Season(L, season, opts)
	opts = opts or {}
	local s = ns.Season.Get(L, season)
	if not s then return nil, "SEASON_UNKNOWN" end
	local warn = newWarnings()
	local labels = opts.labels or {}
	local startLabel = labels.startCredits or SiteExport.DEFAULT_LABELS.startCredits
	local adjustLabel = labels.adjustment or SiteExport.DEFAULT_LABELS.adjustment
	local Lg = Ledger()
	local label = seasonLabel(s)

	local pl = pool(L, season, opts, warn)
	local allNights = ns.Nights.List(L, season)
	local nightById = {}
	for _, n in ipairs(allNights) do nightById[n.id] = n end

	-- the raids: the closed nights, by date and then by when they were opened (the order of the site's columns)
	local raids = {}
	for _, n in ipairs(allNights) do
		if n.closed then raids[#raids + 1] = { night = n, awards = {} } else warn.add("NIGHT_OPEN") end
	end
	sort(raids, function(a, b)
		if a.night.date ~= b.night.date then return a.night.date < b.night.date end
		return a.night.openedAt < b.night.openedAt
	end)
	local raidOf = {}
	for i, r in ipairs(raids) do raidOf[r.night.id] = r; r.index = i end

	-- the starting credits: synthetic rows in the first night the member was there for (extended: `start` on the roster row)
	if not opts.extended then
		for _, e in ipairs(pl.list) do
			if e.initial and e.initial > 0 then
				local parts, rounded = costParts(e.initial)
				if rounded then warn.add("COST_ROUNDED") end
				local target
				for _, r in ipairs(raids) do
					if (r.night.closedAt or 0) >= e.joinedTs then target = r; break end
				end
				target = target or raids[#raids]
				if target then
					for _, c in ipairs(parts) do
						target.awards[#target.awards + 1] = O(true, "player", e.name, "item", startLabel, "cost", c)
					end
				else
					warn.add("START_NO_RAID")
				end
			end
		end
	end

	-- the awards and, in the extended format, the adjustments
	local voided = Lg.State(L).voided
	for _, e in ipairs(Lg.Sorted(L, function(x)
		return x.season == season and (x.type == "ITEM_AWARDED" or x.type == "CREDITS_ADJUSTED")
	end)) do
		local p = Lg.Readable(e) and Lg.Payload(e)
		if p and not voided[e.id] then
			local isAward = e.type == "ITEM_AWARDED"
			if isAward and (p.target or "member") ~= "member" then
				warn.add("AWARD_NOT_MEMBER")   -- the guild bank, disenchant, the master looter: no player on the site
			elseif not isAward and not opts.extended then
				warn.add("ADJUSTMENT_NOT_SHOWN")
			else
				local who = pl.by[p.member]
				local nightId = ns.CreditTable.NightOf(L, e, p, allNights, nightById)
				local raid = nightId and raidOf[nightId]
				if not who then
					warn.add("AWARD_OUTSIDE_ROSTER")
				elseif not nightId then
					warn.add("AWARD_NO_NIGHT")
				elseif not raid then
					warn.add("AWARD_OPEN_NIGHT")   -- its night is not closed yet: it goes out with the night
				elseif isAward then
					local item = opts.itemName and opts.itemName(p.item) or nil
					item = item or ("Item " .. tostring(p.item))
					if p.response == "OS" then item = item .. " (off-spec)" end   -- nolocale (the site's own word)
					local parts, rounded = costParts(p.cost)
					if rounded then warn.add("COST_ROUNDED") end
					for _, c in ipairs(parts) do
						raid.awards[#raid.awards + 1] = O(true, "player", who.name, "item", item, "cost", c,
							"kind", opts.extended and "award" or nil)
					end
				else
					raid.awards[#raid.awards + 1] = O(true, "player", who.name, "item", adjustLabel, "cost", Lg.Round(p.delta),
						"kind", "adjust")
				end
			end
		end
	end

	-- the bosses killed in each night
	local killed = {}
	for _, k in ipairs(ns.Nights.Kills(L, { season = season })) do
		if k.night then
			killed[k.night] = killed[k.night] or {}
			killed[k.night][k.encounterID] = true
		end
	end

	local raidObjects, updated = {}, nil
	for i, r in ipairs(raids) do
		local n = r.night
		local inst = ns.Instances and ns.Instances.Get(n.instanceID)
		local count = 0
		for _ in pairs(killed[n.id] or {}) do count = count + 1 end
		local total = inst and #inst.bosses or count
		if not inst then warn.add("INSTANCE_UNKNOWN") end
		if n.date and (not updated or n.date > updated) then updated = n.date end
		raidObjects[i] = O(false, "id", ("s%s-r%d"):format(slug(label), i), "instance", inst and inst.name or ("Instance " .. tostring(n.instanceID)),
			"date", dayMonth(n.date), "bosses", ("%d/%d"):format(count, total), "awards", r.awards)
	end

	local roster = {}
	for _, e in ipairs(pl.list) do
		roster[#roster + 1] = O(true, "name", e.name, "class", e.class, "spec", e.spec, "faction", opts.siteFaction or "",
			"start", (opts.extended and e.initial and e.initial ~= 0) and e.initial or nil)
	end

	return O(false, "season", label, "updated", updated or opts.today or "", "closed", s.closed ~= nil and s.closed ~= false,
		"roster", roster, "raids", raidObjects), warn.list
end

-- loot.json: every season of the ledger, newest first. Returns the object, the seasons' objects (the same, as a list) and the
-- warnings { { code, n, season } ... }.
function SiteExport.Loot(L, opts)
	opts = opts or {}
	local list, out, warnings = ns.Season.List(L), {}, {}
	for i = #list, 1, -1 do
		local obj, w = SiteExport.Season(L, list[i].id, opts)
		if obj then
			out[#out + 1] = obj
			for _, x in ipairs(w) do warnings[#warnings + 1] = { code = x.code, n = x.n, season = seasonLabel(list[i]) } end
		end
	end
	return O(false, "seasons", out), out, warnings
end

---------------------------------------------------------------------------------------------------------------------
-- progress.json

-- The guild's own key only: the date of the first kill of each boss of the fixed table, or null. Returns the object, the
-- fragment (a list of { id, bosses } to paste into the site's file by hand) and the key. The merge (tools/site_export.py) keeps the other faction's key and never moves a date forward.
function SiteExport.Progress(L, opts)
	opts = opts or {}
	local key = opts.siteFaction
	if not (ns.Progress.ValidKey(key)) then key = ns.Progress.DEFAULT_KEYS.Horde end
	local built = ns.Progress.Build(L, key, { keys = { key } })
	local instances, fragment = {}, {}
	for i, inst in ipairs(built.instances) do
		local bosses = {}
		for j, b in ipairs(inst.bosses) do
			local f = b.first[key]
			bosses[j] = O(true, "name", b.name, key, f and f.date or NULL)
		end
		instances[i] = O(false, "id", inst.slug, "name", inst.name, "size", inst.size, "bosses", bosses)
		fragment[i] = O(false, "id", inst.slug, "bosses", bosses)
	end
	return O(false, "instances", instances), fragment, key
end

---------------------------------------------------------------------------------------------------------------------
-- Everything

-- The three files and their fragments as JSON text. Returns
--   { season = id of the current season (or nil), siteFaction, extended,
--     files = { roster, loot, progress } (the full files), fragments = { roster = the players, loot = the current season's
--     object, progress = the first kills of the guild's key per instance }, warnings = { { code, n, season? } ... } }
-- or nil and a code. A ledger without a season gives empty lists, not an error.
function SiteExport.Build(L, opts)
	opts = opts or {}
	local cur = SiteExport.CurrentSeason(L)
	local rosterObj, players = SiteExport.Roster(L, cur and cur.id or nil, opts)
	local lootObj, seasons, warnings = SiteExport.Loot(L, opts)
	local progressObj, fragment, key = SiteExport.Progress(L, opts)
	return {
		season = cur and cur.id or nil, siteFaction = key, extended = opts.extended and true or false,
		files = { roster = SiteExport.Encode(rosterObj), loot = SiteExport.Encode(lootObj), progress = SiteExport.Encode(progressObj) },
		fragments = { roster = SiteExport.Encode(players), loot = SiteExport.Encode(seasons[1] or NULL),
			progress = SiteExport.Encode(fragment) },
		warnings = warnings,
	}
end

if ns.addon then ns.addon.SiteExport = SiteExport end   -- also reachable from tests
