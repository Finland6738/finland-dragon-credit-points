-- Config: SavedVariables, profiles, per-guild data, validation and schema migrations (docs/ANALISI.md §8.3, §10). Lua 5.1.
-- * FinlandDragonCreditPointsDB (AceDB): profiles hold the settings; db.global.guilds["<realm>/<guild>"] holds the data
--   of one guild (seasons, ledger, snapshots from later steps), so two guilds never mix.
-- * db.global.schema is the schema version. Migrations run one version at a time. A database written by a newer
--   addon opens read-only: nothing is migrated and every write is refused, so an old client never damages it.
-- * FinlandDragonCreditPointsCharDB: per-character data (window positions, personal choices).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Config = {}
ns.Config, ns.modules.Config = Config, Config

local Log = ns.Log
local function log(level, code, ...) if Log then Log[level]("Config", code, ...) end end
local function plain(s) return Log and Log.Plain(s) or s end

-- Development mode: only the packager-stripped block below may turn it on (tools/check_package.py checks this).
Config.DEV = false
--@debug@
Config.DEV = true
--@end-debug@

Config.SCHEMA = 1   -- bump it together with a new entry in Config.migrations

-- migrations[n] upgrades a database from schema n-1 to n; it receives the AceDB `global` table.
Config.migrations = {
	[1] = function(global)   -- the first schema: make sure the containers exist
		global.guilds = global.guilds or {}
	end,
}

Config.defaults = {
	global = { schema = 0, guilds = {}, language = "auto" },   -- language: personal, "auto" = the client's (needs /reload)
	profile = {
		guildLanguage = "enUS",   -- language of the texts sent to everyone (M1-5)
		rollSeconds = 30,
		debug = false,
	},
}

-- Validators of profile settings: type plus optional min / max / values.
Config.validators = {
	guildLanguage = { type = "string", check = function(v) return ns.Locale == nil or ns.Locale.Has(v) end },
	rollSeconds = { type = "number", min = 5, max = 300 },
	debug = { type = "boolean" },
}

-- Runs the steps from `from` to `to` on `global`. A failing step stops there and leaves the version at the last good
-- one. Returns ok, version reached.
function Config.Migrate(global, from, to, steps)
	steps = steps or Config.migrations
	local version = from
	for n = from + 1, to do
		local step = steps[n]
		if type(step) ~= "function" then
			log("error", "MIGRATION_MISSING", n)
			return false, version
		end
		local ok, err = pcall(step, global)
		if not ok then
			log("error", "MIGRATION_FAILED", n, plain(tostring(err):sub(1, 80)))
			return false, version
		end
		version = n
		log("info", "MIGRATED", n)
	end
	return true, version
end

-- The guild key "<realm>/<guild>" or nil when the player has no guild (or the game does not say).
function Config.ComputeGuildKey()
	local Compat = ns.Compat
	if not Compat or not Compat.Guild.InGuild() then return nil end
	local guild, realm = Compat.Guild.GuildName(), Compat.Guild.GuildRealm() or Compat.Player.Realm()
	if not guild or not realm then return nil end
	return realm .. "/" .. guild
end

function Config:Setup()
	if self.db then return self.db end
	local AceDB = LibStub("AceDB-3.0")
	self.db = AceDB:New("FinlandDragonCreditPointsDB", Config.defaults, true)
	local global = self.db.global
	self.readOnly = false
	if (global.schema or 0) > Config.SCHEMA then
		self.readOnly = true
		log("warn", "SCHEMA_NEWER", global.schema, Config.SCHEMA)
	else
		local ok = Config.Migrate(global, global.schema or 0, Config.SCHEMA)
		global.schema = ok and Config.SCHEMA or global.schema
		if not ok then self.readOnly = true end   -- a half-migrated database is not written to either
	end
	if ns.Locale then ns.Locale.SetActive(self:GetLanguage() ~= "auto" and self:GetLanguage() or nil) end
	FinlandDragonCreditPointsCharDB = FinlandDragonCreditPointsCharDB or {}
	self.char = FinlandDragonCreditPointsCharDB
	self:UpdateGuildKey()
	self.db.RegisterCallback(self, "OnProfileChanged", function() ns.Bus:Emit("CONFIG_PROFILE_CHANGED") end)
	self.db.RegisterCallback(self, "OnProfileCopied", function() ns.Bus:Emit("CONFIG_PROFILE_CHANGED") end)
	self.db.RegisterCallback(self, "OnProfileReset", function() ns.Bus:Emit("CONFIG_PROFILE_CHANGED") end)
	return self.db
end

-- The personal language: "auto" or a registered code. It is applied once per session, at Setup (so a change needs /reload).
function Config:GetLanguage()
	local code = self.db and self.db.global.language
	if code ~= "auto" and not (ns.Locale and ns.Locale.Has(code)) then return "auto" end
	return code
end

function Config:SetLanguage(code)
	if not self.db then return false, "NOT_READY" end
	if self.readOnly then return false, "READ_ONLY" end
	if type(code) ~= "string" then return false, "BAD_TYPE" end
	if code:lower() == "auto" then code = "auto"
	else
		local found
		for _, lang in ipairs(ns.Locale and ns.Locale.Languages() or {}) do
			if lang.code:lower() == code:lower() then found = lang.code end   -- "itit" is accepted
		end
		if not found then return false, "BAD_VALUE" end
		code = found
	end
	self.db.global.language = code
	return true
end

function Config:IsReadOnly() return self.readOnly == true end

-- The current guild key; recomputed by UpdateGuildKey when the guild changes.
function Config:GuildKey() return self.guildKey end

function Config:UpdateGuildKey()
	local key = Config.ComputeGuildKey()
	if key ~= self.guildKey then
		self.guildKey = key
		if ns.Bus then ns.Bus:Emit("GUILD_KEY_CHANGED", key) end
		return true
	end
	return false
end

-- The data table of one guild (default: the current one), created on first use; nil without a guild, with the
-- database read-only and the guild not yet known (nothing may be created then).
function Config:GuildData(key)
	key = key or self.guildKey
	if not key or not self.db then return nil end
	local guilds = self.db.global.guilds
	if not guilds[key] then
		if self.readOnly then return nil end
		guilds[key] = {}
	end
	return guilds[key]
end

-- Validation of one setting: ok, error code.
function Config.Validate(name, value)
	local v = Config.validators[name]
	if not v then return false, "UNKNOWN_SETTING" end
	if type(value) ~= v.type then return false, "BAD_TYPE" end
	if v.type == "number" then
		if value ~= value or value == math.huge or value == -math.huge then return false, "BAD_VALUE" end
		if (v.min and value < v.min) or (v.max and value > v.max) then return false, "OUT_OF_RANGE" end
	end
	if v.values and not v.values[value] then return false, "BAD_VALUE" end
	if v.check and not v.check(value) then return false, "BAD_VALUE" end
	return true
end

function Config:Get(name)
	if not self.db then return Config.defaults.profile[name] end
	return self.db.profile[name]
end

function Config:Set(name, value)
	if not self.db then return false, "NOT_READY" end
	if self.readOnly then return false, "READ_ONLY" end
	local ok, err = Config.Validate(name, value)
	if not ok then return false, err end
	local old = self.db.profile[name]
	self.db.profile[name] = value
	if old ~= value then ns.Bus:Emit("CONFIG_CHANGED", name, value, old) end
	return true
end

local FDCP = ns.addon
if FDCP then
	FDCP.Config = Config
	FDCP.Log, FDCP.Bus = ns.Log, ns.Bus
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_GUILD_UPDATE")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("GUILD_ROSTER_UPDATE")
	frame:SetScript("OnEvent", function() if Config.db then Config:UpdateGuildKey() end end)
end
