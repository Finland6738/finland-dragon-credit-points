-- SiteExportService: builds the three files of the community site from the guild's ledger and keeps the last result in the
-- SavedVariables, for tools/site_export.py (docs/specs/site-export.md §6, docs/ANALISI.md §7.1, M6-4). Lua 5.1. The
-- files themselves are made by Domain/SiteExport.lua (pure); this module gives it what only the game knows (the realm's day,
-- an item's name in the client's language, the guild's labels) and stores the result.
--
-- * Saved in db.global.guilds["<realm>/<guild>"].siteExport = { updated = "YYYY-MM-DD", season, faction (the site key),
--   extended, files = { roster, loot, progress } (JSON text), warnings = { "CODE:n" ... } }: JSON text and not tables, because
--   a Lua table cannot hold the nulls of progress.json and cannot tell an empty list from an empty object.
-- * Saved at every night close (by whoever closes it, when the rank allows `export.public`) and on request (the Export pane's
--   button, `Save`). Nothing is saved without the permission; building needs a ledger only.
-- * The hidden option of issue #3 (`start` / `kind`) is the rules' `site.extended`, off by default and not in any window.
--
-- Bus events: "SITE_EXPORT_SAVED"(record).
-- Not verified in the real client: the item names of the client's language, the copy window and the script on a real night.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local SiteExportService = {}
ns.SiteExportService, ns.modules.SiteExportService = SiteExportService, SiteExportService

local ipairs, tostring = ipairs, tostring

local function NC() return ns.NightController end
local function log(level, code, ...) if ns.Log then ns.Log[level]("SiteExport", code, ...) end end

-- The guild's ledger, or nil.
function SiteExportService:Ledger()
	return NC() and NC():Ledger() or nil
end

-- May the player export for the site? true, or false and a code ("PENDING", "NOT_IN_GUILD", "RANK_TOO_LOW", "NOT_READY").
function SiteExportService:Can()
	local nc = NC()
	if not nc then return false, "NOT_READY" end
	return nc:Can("export.public")
end

-- The options of Domain/SiteExport.lua from the game: the faction, the site key, today, the item names, the labels and the
-- hidden switch.
-- locale-key: SITE_START_CREDITS SITE_ADJUSTMENT
function SiteExportService:Options(L)
	local rules = ns.Rules.Current(L)
	local faction = ns.RosterController and ns.RosterController:Faction() or ns.Compat.Player.Faction()
	local l = ns.L
	return {
		faction = faction,
		siteFaction = ns.Progress.FactionKey(rules, faction),
		today = ns.Nights.FormatDay(ns.Compat.ServerDay()),
		itemName = function(id)
			local info = ns.Compat.Item.Info(id)
			return info and info.name or nil
		end,
		labels = { startCredits = l["SITE_START_CREDITS"], adjustment = l["SITE_ADJUSTMENT"] },
		extended = rules and rules.site and rules.site.extended == true or false,
	}
end

-- Builds the three files now. Returns the result of SiteExport.Build, or nil and "NOT_READY" / a permission code.
function SiteExportService:Build()
	local ok, why = self:Can()
	if not ok then return nil, why end
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	return ns.SiteExport.Build(L, self:Options(L))
end

-- The warning codes of a result as saved: "CODE:n" or "CODE:n:season".
local function warningLines(list)
	local out = {}
	for _, w in ipairs(list or {}) do
		out[#out + 1] = w.season and ("%s:%d:%s"):format(w.code, w.n, tostring(w.season)) or ("%s:%d"):format(w.code, w.n)
	end
	return out
end

-- Builds and stores the files in the guild's saved data. Returns the saved record, or nil and a code ("NOT_READY",
-- a permission code, "READ_ONLY").
function SiteExportService:Save()
	local result, why = self:Build()
	if not result then return nil, why end
	local data = ns.Config and ns.Config.GuildData and ns.Config:GuildData()
	if not data or (ns.Config.IsReadOnly and ns.Config:IsReadOnly()) then return nil, "READ_ONLY" end
	local record = {
		updated = ns.Nights.FormatDay(ns.Compat.ServerDay()), season = result.season, faction = result.siteFaction,
		extended = result.extended, files = result.files, warnings = warningLines(result.warnings),
	}
	data.siteExport = record
	log("info", "SITE_EXPORT_SAVED", #record.warnings)
	if ns.Bus then ns.Bus:Emit("SITE_EXPORT_SAVED", record) end
	return record
end

-- The last saved record, or nil.
function SiteExportService:Saved()
	local data = ns.Config and ns.Config.GuildData and ns.Config:GuildData()
	return data and data.siteExport or nil
end

if ns.Bus then
	-- a night is over: the files of the site are ready for the script (silently: no right, no file)
	ns.Bus:On("NIGHT_CLOSED", function() SiteExportService:Save() end, SiteExportService)
end

if ns.addon then ns.addon.SiteExportService = SiteExportService end   -- also reachable from tests
