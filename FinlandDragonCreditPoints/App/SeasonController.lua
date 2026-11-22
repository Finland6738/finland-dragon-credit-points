-- SeasonController: opens and closes the guild's season from the season window (docs/ANALISI.md §6, §9.3, M6-1b). Lua 5.1.
-- The rules are in Domain/Season.lua (SEASON_OPENED / SEASON_CLOSED); this module is the glue: the guild's ledger (shared
-- with App/NightController.lua), the permission `season.manage` (the Guild Master by default) and the trust gate of the
-- permission service. Nothing is deleted: a season is only ever opened and closed, both audited ledger events.
--
-- * Every write needs an explicit confirmation from the window (`confirmed = true`); closing needs a second, separate one
--   (`confirmedAgain = true`), because a closed season cannot be reopened.
-- * The late-join rule belongs to the guild's rules (CONFIG_CHANGED, `members.lateJoin.method`): when the Guild Master picks
--   another one while opening, it is written with Rules.Change just before the season (audited like any rule change).
--
-- * The item-level band of a season (M7-5c: SEASON_BAND_SET, the upgrade badge's "older season" line) is set when the
--   season opens (optional) or later with SetBand, also with an explicit confirmation.
--
-- Bus events: "SEASON_OPENED"(season record), "SEASON_CLOSED"(season record), "SEASON_BAND_SET"(season record).
-- Not verified in the real client: the window and the permission-based visibility (M6-1b "in game").
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local SeasonController = {}
ns.SeasonController, ns.modules.SeasonController = SeasonController, SeasonController

local type, ipairs, tonumber = type, ipairs, tonumber

local function NC() return ns.NightController end
local function log(level, code, ...) if ns.Log then ns.Log[level]("Season", code, ...) end end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function gate() return ns.PermissionService and ns.PermissionService:Gate() or nil end

SeasonController.METHODS = { "average", "median", "min", "zero", "fixed" }   -- the late-join methods (Domain/Members.lua)

-- The guild's ledger, or nil while the data is not loaded.
function SeasonController:Ledger() return NC():Ledger() end

-- May the player open and close seasons now? true, or false and a code (as NightController:Can).
function SeasonController:CanManage() return NC():Can("season.manage") end

-- The open season of the ledger, or nil.
function SeasonController:Current()
	local L = self:Ledger()
	return L and ns.Season.Current(L) or nil
end

-- The rules in force (defaults without a ledger).
function SeasonController:Rules()
	local L = self:Ledger()
	return L and ns.Rules.Current(L) or ns.Rules.DefaultConfig()
end

-- The id of the next season: "S1", "S2"... the first one the ledger does not use.
function SeasonController:NextId()
	local L, n = self:Ledger(), 1
	while L and ns.Season.Get(L, "S" .. n) do n = n + 1 end
	return "S" .. n
end

-- Checks the player may write: the ledger, the player's name, the permission. Returns L, me or nil and a code.
local function writer(self)
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	local ok, why = self:CanManage()
	if not ok then return nil, why end
	local me = NC():Me()
	if not me then return nil, "NOT_READY" end
	return L, me
end

-- Opens a season. args = { confirmed, label?, instances = { { id, size } }, startCredits?, lateJoin? = method,
-- band? = { min, max } }.
-- Returns the season record, or nil and a code: "CONFIRM_REQUIRED", "NOT_READY", "PENDING", "NOT_IN_GUILD", "RANK_TOO_LOW",
-- "NOT_GM", "SEASON_ALREADY_OPEN", "NO_INSTANCES", "NOT_IN_TABLE", "SIZE", "START_CREDITS", "LATE_JOIN",
-- "RULES:<field>" (the late-join rule was refused), "BAND" or a Ledger code.
function SeasonController:Open(args)
	args = args or {}
	local L, me = writer(self)
	if not L then return nil, me end
	if args.confirmed ~= true then return nil, "CONFIRM_REQUIRED" end
	if ns.Season.Current(L) then return nil, "SEASON_ALREADY_OPEN" end
	local pack = {}
	for _, inst in ipairs(args.instances or {}) do
		if not (ns.Instances and ns.Instances.Get(inst.id)) then return nil, "NOT_IN_TABLE" end
		if not ns.Ledger.RAID_SIZES[inst.size] then return nil, "SIZE" end
		pack[#pack + 1] = { id = inst.id, size = inst.size }
	end
	if #pack == 0 then return nil, "NO_INSTANCES" end
	local rules = ns.Rules.Current(L)
	local start = args.startCredits
	if start == nil then start = rules.season.startCredits end
	if type(start) ~= "number" or start ~= start or start < 0 then return nil, "START_CREDITS" end
	local band
	if args.band ~= nil then
		band = ns.UpgradeScore.Band(args.band)
		if not band then return nil, "BAND" end
	end
	local label = args.label
	if type(label) == "string" then label = label:match("^%s*(.-)%s*$") end
	if label == "" then label = nil end
	-- the late-join rule: changed in the rules first (audited), only when it differs
	local method = args.lateJoin
	if method ~= nil then
		if not ns.Members.METHODS[method] then return nil, "LATE_JOIN" end
		if method ~= rules.members.lateJoin.method then
			rules.members.lateJoin.method = method
			local _, why = ns.Rules.Change(L, { author = me, ts = ns.Compat.ServerTime(), rules = rules, confirmed = true }, gate())
			if why then return nil, why end
		end
	end
	local event, why = ns.Season.Open(L, { author = me, ts = ns.Compat.ServerTime(), season = self:NextId(), label = label,
		instances = pack, startCredits = start }, nil, gate())
	if not event then return nil, why end
	if band then
		local _, bandWhy = ns.Season.SetBand(L, { author = me, ts = ns.Compat.ServerTime(), season = event.season, min = band.min,
			max = band.max }, gate())
		if bandWhy then log("warn", "SEASON_BAND_REFUSED", bandWhy) end
	end
	local season = ns.Season.Get(L, event.season)
	log("info", "SEASON_OPENED", #pack)
	emit("SEASON_OPENED", season)
	return season
end

-- Closes the open season. args = { confirmed, confirmedAgain }. Returns the season record (closed), or nil and a code:
-- "CONFIRM_REQUIRED", "NOT_READY", a permission code, "NO_SEASON", "READ_ONLY" or a Ledger code.
function SeasonController:Close(args)
	args = args or {}
	local L, me = writer(self)
	if not L then return nil, me end
	if args.confirmed ~= true or args.confirmedAgain ~= true then return nil, "CONFIRM_REQUIRED" end
	local s = ns.Season.Current(L)
	if not s then return nil, "NO_SEASON" end
	local night = ns.Nights and ns.Nights.Current(L, s.id)
	if night then return nil, "NIGHT_OPEN" end
	local event, why = ns.Season.Close(L, { author = me, ts = ns.Compat.ServerTime(), season = s.id }, gate())
	if not event then return nil, why end
	local closed = ns.Season.Get(L, s.id)
	log("info", "SEASON_CLOSED")
	emit("SEASON_CLOSED", closed)
	return closed
end

-- Sets the item-level band of the open season (M7-5c). args = { confirmed, min, max }. Returns the season record, or nil and
-- a code: "CONFIRM_REQUIRED", "NOT_READY", a permission code, "NO_SEASON", "BAND", "UNCHANGED" or a Ledger code.
function SeasonController:SetBand(args)
	args = args or {}
	local L, me = writer(self)
	if not L then return nil, me end
	if args.confirmed ~= true then return nil, "CONFIRM_REQUIRED" end
	local s = ns.Season.Current(L)
	if not s then return nil, "NO_SEASON" end
	local event, why = ns.Season.SetBand(L, { author = me, ts = ns.Compat.ServerTime(), season = s.id, min = args.min,
		max = args.max }, gate())
	if not event then return nil, why end
	local season = ns.Season.Get(L, s.id)
	log("info", "SEASON_BAND_SET", season.band.min, season.band.max)
	emit("SEASON_BAND_SET", season)
	return season
end

if ns.addon then ns.addon.SeasonController = SeasonController end   -- also reachable from tests
