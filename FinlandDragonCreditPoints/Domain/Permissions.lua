-- Permissions: who may do what, by guild rank index (docs/ANALISI.md §3.9, §8.4, §10). Pure Lua 5.1: it never calls
-- the game; the adapter (M3-1) reads the ranks from the guild roster and passes them in.
--
-- A permission maps to the **lowest** rank that holds it, as a rank **index** (0 = Guild Master, 1 the next rank, ...
-- as GetGuildRosterInfo returns it). A member with rank index r holds permission p when r <= table[p]. Names are never
-- used: renaming a rank changes nothing; reordering or deleting ranks is detected (Permissions.RanksChanged,
-- Permissions.CheckRanks) so the GM can check the table again.
--
-- config.rules and config.permissions are fixed at 0: only the GM changes the rules and this table. The table is an
-- event of the ledger, PERMISSIONS_CHANGED{table, confirmed?}, written only by the GM; the table in force when an
-- event was written is the one of the last PERMISSIONS_CHANGED before it (Permissions.Current), the preset before the
-- first one. While a season is open Permissions.Change refuses without `confirmed` (§10).
--
-- Trust (§3.9): every event needs the permission of its type (Permissions.EVENT_PERMISSION; voids and manual credit
-- corrections need credits.adjust outside a night and night.run while a night of the season is open). Permissions.Gate
-- builds the gate of Ledger.Append / Ledger.Merge: an event is accepted only if its author had the required rank when
-- it was written (`rankOf(author, ts)`, from the rank history the adapter keeps: Permissions.RecordRank / RankAt), a
-- config event only if its author was the GM then. A GM change hands the power to the new GM from the moment the game
-- shows it; the old GM's events stay valid (they were written by the GM of that time). While the roster is not
-- loaded the author's rank is unknown and the gate answers "PENDING": the caller queues the event and merges it again.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Permissions = {}
ns.Permissions, ns.modules.Permissions = Permissions, Permissions

local type, pairs, ipairs, tostring, floor, sort = type, pairs, ipairs, tostring, math.floor, table.sort

local function Ledger() return ns.Ledger end

Permissions.GM = 0          -- the Guild Master's rank index
Permissions.OFFICER = 1     -- "officer" in the preset: rank index 1 (the GM moves it)
Permissions.MAX_RANK = 9    -- a guild has at most 10 ranks, 0-9

-- The permissions of §3.9, in its order.
Permissions.LIST = {
	"config.rules", "config.permissions", "season.manage", "night.run", "award.confirm", "council.member",
	"credits.adjust", "roster.manage", "export.public", "view.attendance", "raid.addonCheck",
}
local KNOWN = {}
for _, p in ipairs(Permissions.LIST) do KNOWN[p] = true end

-- Fixed at the GM: nobody can lower them, not even the GM.
Permissions.FIXED = { ["config.rules"] = true, ["config.permissions"] = true }

-- The preset table (§3.9): the lowest rank index holding each permission. A fresh copy on every call.
function Permissions.DefaultTable()
	local GM, OFF = Permissions.GM, Permissions.OFFICER
	return {
		["config.rules"] = GM,
		["config.permissions"] = GM,
		["season.manage"] = GM,
		["night.run"] = OFF,
		["award.confirm"] = OFF,     -- in a night, also the master looter of that night (M4)
		["council.member"] = OFF,    -- and present in the raid when council.requirePresent (Rules, M5)
		["credits.adjust"] = GM,     -- the GM may lower it to the officers
		["roster.manage"] = OFF,
		["export.public"] = OFF,
		["view.attendance"] = OFF,
		["raid.addonCheck"] = OFF,   -- and the master looter of the night (M3)
	}
end

-- The permission each ledger type needs. AWARD_VOIDED and CREDITS_ADJUSTED depend on the night (Permissions.Required).
Permissions.EVENT_PERMISSION = {
	SEASON_OPENED = "season.manage",
	SEASON_CLOSED = "season.manage",
	MEMBER_JOINED = "roster.manage",
	MEMBER_LINKED_ALT = "roster.manage",
	ROSTER_CHANGED = "roster.manage",
	NIGHT_OPENED = "night.run",
	NIGHT_CLOSED = "night.run",
	ENCOUNTER_KILLED = "night.run",
	PROGRESS_SET = "night.run",
	DROP_SEEN = "night.run",
	ITEM_AWARDED = "night.run",
	LEGENDARY_PROJECT_OPENED = "night.run",
	LEGENDARY_PROJECT_PAID = "night.run",
	LEGENDARY_PROJECT_CLOSED = "night.run",
	AWARD_VOIDED = "credits.adjust",
	CREDITS_ADJUSTED = "credits.adjust",
	CONFIG_CHANGED = "config.rules",
	PERMISSIONS_CHANGED = "config.permissions",
}
-- In a night, the council's corrections are written by the master looter (§3.6): night.run is enough.
Permissions.IN_NIGHT = { AWARD_VOIDED = "night.run", CREDITS_ADJUSTED = "night.run" }

local function isRank(r) return type(r) == "number" and r == floor(r) and r >= 0 and r <= Permissions.MAX_RANK end
Permissions.IsRank = isRank

function Permissions.IsPermission(p) return KNOWN[p] == true end

-- Checks a permission table: only known permissions, each a rank index 0-9, the fixed ones at 0. A missing permission
-- takes the preset (Permissions.Normalize). Returns true, or false plus a sorted list of codes.
function Permissions.Validate(t)
	if type(t) ~= "table" then return false, { "table" } end
	local problems = {}
	for p, r in pairs(t) do
		if not KNOWN[p] then
			problems[#problems + 1] = "unknown:" .. tostring(p)
		elseif not isRank(r) then
			problems[#problems + 1] = p
		elseif Permissions.FIXED[p] and r ~= Permissions.GM then
			problems[#problems + 1] = "fixed:" .. p
		end
	end
	sort(problems)
	return #problems == 0, problems
end

-- A complete table: the preset for every permission `t` lacks, the fixed ones forced to the GM. A new table.
function Permissions.Normalize(t)
	local out = Permissions.DefaultTable()
	for p, r in pairs(type(t) == "table" and t or {}) do
		if KNOWN[p] and isRank(r) then out[p] = r end
	end
	for p in pairs(Permissions.FIXED) do out[p] = Permissions.GM end
	return out
end

-- True when a member of rank index `rank` holds permission `p` under table `t` (the preset when nil).
function Permissions.Can(rank, p, t)
	if not isRank(rank) or not KNOWN[p] then return false end
	if Permissions.FIXED[p] then return rank == Permissions.GM end
	local min = Permissions.Normalize(t)[p]
	return rank <= min
end

-- Every permission a rank holds: { [p] = true }.
function Permissions.Of(rank, t)
	local out = {}
	for _, p in ipairs(Permissions.LIST) do
		if Permissions.Can(rank, p, t) then out[p] = true end
	end
	return out
end

-- The table in force: from the last PERMISSIONS_CHANGED before `at` (an event, or nil for now), or the preset.
-- Returns the table and the id of the event it comes from (nil for the preset).
function Permissions.Current(L, at)
	local e = Ledger().LatestBefore(L, "PERMISSIONS_CHANGED", at)
	if not e then return Permissions.DefaultTable(), nil end
	return Permissions.Normalize(Ledger().Payload(e).table), e.id
end

-- True when a night of e.season is open when `e` is written: the last NIGHT_OPENED / NIGHT_CLOSED of the season
-- before it is an opening.
local function inNight(L, e)
	if e.season == nil then return false end
	local Lg = Ledger()
	local last
	for _, x in pairs(L.events) do
		if (x.type == "NIGHT_OPENED" or x.type == "NIGHT_CLOSED") and x.season == e.season and Lg.Before(x, e)
			and Lg.Readable(x) and (not last or Lg.Before(last, x)) then
			last = x
		end
	end
	return last ~= nil and last.type == "NIGHT_OPENED"
end

-- The permission event `e` needs, given the ledger it enters. An unknown type (a newer addon's) needs the loosest
-- permission that writes any event: whoever may write something may forward it; its content is never read.
function Permissions.Required(L, e)
	if Permissions.IN_NIGHT[e.type] and inNight(L, e) then return Permissions.IN_NIGHT[e.type] end
	local p = Permissions.EVENT_PERMISSION[e.type]
	if p then return p end
	local t, loosest, best = Permissions.Current(L, e), nil, -1
	for _, q in pairs(Permissions.EVENT_PERMISSION) do
		if t[q] > best or (t[q] == best and q < loosest) then loosest, best = q, t[q] end
	end
	return loosest
end

-- Decides whether `e` may enter ledger `L`. rankOf(author, ts) gives the author's rank index when the event was
-- written, false when the author was not in the guild, nil when it is not known yet. Returns true, or false and a
-- code: "PENDING" (rank unknown: queue it), "NOT_IN_GUILD", "NOT_GM" (a config event from another rank) or
-- "RANK_TOO_LOW".
function Permissions.Accept(L, e, rankOf)
	local rank = rankOf(e.author, e.ts)
	if rank == nil then return false, "PENDING" end
	if rank == false or not isRank(rank) then return false, "NOT_IN_GUILD" end
	local p = Permissions.Required(L, e)
	if Permissions.FIXED[p] then
		if rank ~= Permissions.GM then return false, "NOT_GM" end
		return true
	end
	if rank > Permissions.Current(L, e)[p] then return false, "RANK_TOO_LOW" end
	return true
end

-- The gate for Ledger.Append / Ledger.Merge (and the Season, Members, Rules writers): { accept = function(L, e) }.
-- `ranks` is a rank history (Permissions.RecordRank) or a function rankOf(author, ts).
function Permissions.Gate(ranks)
	local rankOf = ranks
	if type(ranks) ~= "function" then
		rankOf = function(author, ts) return Permissions.RankAt(ranks, author, ts) end
	end
	return { accept = function(L, e) return Permissions.Accept(L, e, rankOf) end }
end

---------------------------------------------------------------------------------------------------------------------
-- The rank history: { loaded = bool, members = { [name] = { {ts, rank}, ... } } }, plain data the adapter (M3-1) saves
-- and feeds from the guild roster. rank = false records that the character left the guild.

function Permissions.NewHistory() return { loaded = false, members = {} } end

-- Records the rank of `name` seen at `ts` (only a change is stored). Returns true when it changed.
function Permissions.RecordRank(h, name, rank, ts)
	if rank ~= false and not isRank(rank) then return false end
	local list = h.members[name]
	if not list then
		list = {}
		h.members[name] = list
	end
	local last = list[#list]
	if last and last.rank == rank then return false end
	list[#list + 1] = { ts = ts, rank = rank }
	sort(list, function(a, b) return a.ts < b.ts end)
	return true
end

-- The rank of `name` at `ts`: the last record at or before ts; the first record when ts is older than every record
-- (the rank seen first is the best guess for the past). nil while the roster is not loaded (`loaded` false); once it
-- is loaded, false for a name never seen in it (not in the guild).
function Permissions.RankAt(h, name, ts)
	if type(h) ~= "table" or not h.loaded then return nil end
	local list = h.members and h.members[name]
	if not list or #list == 0 then return false end
	local rank = list[1].rank
	for _, r in ipairs(list) do
		if r.ts <= ts then rank = r.rank else break end
	end
	return rank
end

---------------------------------------------------------------------------------------------------------------------
-- Rank changes the GM must look at

-- Compares the rank names seen before and now (lists by index). Returns nil when nothing changed, or a code:
-- "RENAMED" (same count, not a permutation: nothing to do, the table uses indexes), "REORDERED" (same names, other
-- order), "REMOVED" (fewer ranks), "ADDED" (more ranks). The last three ask the GM to check the table.
function Permissions.RanksChanged(before, now)
	if type(before) ~= "table" or type(now) ~= "table" then return nil end
	if #now < #before then return "REMOVED" end
	if #now > #before then return "ADDED" end
	local same, count = true, {}
	for i = 1, #before do
		if before[i] ~= now[i] then same = false end
		count[before[i]] = (count[before[i]] or 0) + 1
	end
	if same then return nil end
	for i = 1, #now do
		if not count[now[i]] or count[now[i]] == 0 then return "RENAMED" end
		count[now[i]] = count[now[i]] - 1
	end
	return "REORDERED"
end

-- The permissions whose rank index does not exist in a guild of `numRanks` ranks (after ranks were deleted): a sorted
-- list (empty when the table fits).
function Permissions.CheckRanks(t, numRanks)
	local out = {}
	for p, r in pairs(Permissions.Normalize(t)) do
		if r >= numRanks then out[#out + 1] = p end
	end
	sort(out)
	return out
end

-- Writes a PERMISSIONS_CHANGED. draft = { author, ts, table, confirmed? }: the table is validated and stored complete
-- (Permissions.Normalize). opts goes to Ledger.Append (the gate: only the GM). Returns the event, or nil and a code:
-- "TABLE:<code>", "UNCHANGED", "CONFIRM_REQUIRED" (a season is open and `confirmed` is not set) or a Ledger.Append /
-- gate code.
function Permissions.Change(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	local ok, problems = Permissions.Validate(draft.table)
	if not ok then return nil, "TABLE:" .. problems[1] end
	local t = Permissions.Normalize(draft.table)
	local cur = Permissions.Current(L)
	local changed = false
	for _, p in ipairs(Permissions.LIST) do
		if cur[p] ~= t[p] then changed = true end
	end
	if not changed then return nil, "UNCHANGED" end
	local confirmed = draft.confirmed == true
	if ns.Season and ns.Season.Current(L) and not confirmed then return nil, "CONFIRM_REQUIRED" end
	return Ledger().Append(L, {
		author = draft.author, ts = draft.ts, type = "PERMISSIONS_CHANGED",
		payload = { table = t, confirmed = confirmed or nil },
	}, opts)
end

-- The payload check of PERMISSIONS_CHANGED (Ledger.Check).
ns.Ledger.CHECKS.PERMISSIONS_CHANGED = function(p)
	if not Permissions.Validate(p.table) then return "table" end
	if p.confirmed ~= nil and type(p.confirmed) ~= "boolean" then return "confirmed" end
end

if ns.addon then ns.addon.Permissions = Permissions end   -- also reachable from tests
