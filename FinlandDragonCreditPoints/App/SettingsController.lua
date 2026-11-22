-- SettingsController: the Settings tab's reads and writes (docs/ANALISI.md §3.9, §10, docs/specs/ui-style.md §6, M7-2). Lua 5.1.
--
-- Three kinds of setting, three owners:
--   * personal   theme, fonts, neon effects, animations, sounds, guild language and the personal language live in the profile
--                (Core/Config.lua); the player changes them freely, nothing is shared. The popup's position is reset here too.
--   * rules      the guild's rules are CONFIG_CHANGED events of the ledger (Domain/Rules.lua). Only the Guild Master writes them:
--                SettingsController:ApplyRules answers "NOT_GM" to anybody else *before* building the event, and a forged one
--                (an event of another rank that reaches the ledger through a sync) is refused by the trust gate of
--                Domain/Permissions.lua. While a season is open the write needs the explicit confirmation of the window
--                (`confirmed = true`, kept in the event for the audit).
--   * permissions the table of the rank each permission needs, PERMISSIONS_CHANGED, the same two guards.
-- It also hands the GM the review of a guild rank change (App/PermissionService.lua) and builds the options of the game's own
-- settings window (a few personal switches and a button that opens the addon window).
--
-- Bus events: "SETTINGS_RULES_CHANGED"(event), "SETTINGS_PERMISSIONS_CHANGED"(event), "SETTINGS_PERSONAL_CHANGED"(name, value).
-- Not verified in the real client: the window and the game's settings entry (M7-2 "in game").
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local SettingsController = {}
ns.SettingsController, ns.modules.SettingsController = SettingsController, SettingsController

local type, ipairs, pairs, tostring = type, ipairs, pairs, tostring

local function log(level, code, ...) if ns.Log then ns.Log[level]("Settings", code, ...) end end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function NC() return ns.NightController end
local function PS() return ns.PermissionService end
local function gate() return PS() and PS():Gate() or nil end

-- The personal settings of the profile, in the order of the window.
SettingsController.PERSONAL = { "theme", "fontSource", "effects", "animations", "sounds", "guildLanguage" }

---------------------------------------------------------------------------------------------------------------------
-- Reading

-- The guild's ledger, or nil while the data is not loaded.
function SettingsController:Ledger() return NC() and NC():Ledger() end

-- The rules in force (the defaults without a ledger).
function SettingsController:Rules()
	local L = self:Ledger()
	return L and ns.Rules.Current(L) or ns.Rules.DefaultConfig()
end

-- The permission table in force: { [permission] = rank index } (the preset without a ledger).
function SettingsController:Table()
	local L = self:Ledger()
	return L and (ns.Permissions.Current(L)) or ns.Permissions.DefaultTable()
end

-- May the player change the rules and the permissions? Only the Guild Master (rank index 0): true, or false and a code
-- ("PENDING" while the roster loads, "NOT_IN_GUILD", "NOT_GM").
function SettingsController:CanConfigure()
	if not PS() then return false, "PENDING" end
	return PS():CanConfigure()
end

-- True when a season is open: a change of the rules or the permissions then needs the GM's explicit confirmation.
function SettingsController:NeedsConfirmation()
	local L = self:Ledger()
	return L ~= nil and ns.Season.Current(L) ~= nil
end

-- The leaf paths a draft would change in the rules ("cost.matrix.weapon.4"), sorted.
function SettingsController:RulesDiff(draft)
	return ns.Rules.Diff(self:Rules(), ns.Rules.WithDefaults(draft))
end

-- The permissions a draft table would change, in the order of the list: { { permission, from, to } }.
function SettingsController:TableDiff(draft)
	local now, new, out = self:Table(), ns.Permissions.Normalize(draft), {}
	for _, p in ipairs(ns.Permissions.LIST) do
		if now[p] ~= new[p] then out[#out + 1] = { permission = p, from = now[p], to = new[p] } end
	end
	return out
end

-- The names of the guild's ranks by index (0-based: [0] = "Guild Master"), as the game says them; a rank without a name is
-- missing (the window writes "Rank 3"). `count` is the number of ranks (0 when the client does not say).
function SettingsController:RankNames()
	local names, count = {}, 0
	local GR = ns.GuildRanks
	if GR then
		for i, name in ipairs(GR.RankNames()) do names[i - 1] = name end
		count = GR.NumRanks() or 0
	end
	return names, count
end

---------------------------------------------------------------------------------------------------------------------
-- Writing the rules and the permissions

-- Checks the player may write: the ledger, the player's name, the GM's right. Returns L, me or nil and a code.
local function writer(self)
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	local ok, why = self:CanConfigure()
	if not ok then return nil, why end
	local me = NC():Me()
	if not me then return nil, "NOT_READY" end
	return L, me
end

-- Writes `rules` (a whole configuration, the draft the window edited) as a CONFIG_CHANGED. opts = { confirmed = bool, preset? }.
-- Returns the event, or nil and a code: "NOT_READY", "PENDING", "NOT_IN_GUILD", "NOT_GM", "RULES:<field>" (invalid),
-- "UNCHANGED", "CONFIRM_REQUIRED" (a season is open and the GM has not confirmed) or a ledger code.
function SettingsController:ApplyRules(rules, opts)
	opts = opts or {}
	local L, me = writer(self)
	if not L then return nil, me end
	local changed = #self:RulesDiff(rules)
	local event, why = ns.Rules.Change(L, { author = me, ts = ns.Compat.ServerTime(), rules = rules,
		preset = opts.preset, confirmed = opts.confirmed == true }, gate())
	if not event then return nil, why end
	log("info", "RULES_CHANGED", changed)
	emit("SETTINGS_RULES_CHANGED", event)
	return event
end

-- Writes the permission table `t` as a PERMISSIONS_CHANGED (same codes as ApplyRules, "TABLE:<code>" for an invalid one).
function SettingsController:ApplyPermissions(t, opts)
	opts = opts or {}
	local L, me = writer(self)
	if not L then return nil, me end
	local event, why = ns.Permissions.Change(L, { author = me, ts = ns.Compat.ServerTime(), table = t,
		confirmed = opts.confirmed == true }, gate())
	if not event then return nil, why end
	log("info", "PERMISSIONS_CHANGED")
	emit("SETTINGS_PERMISSIONS_CHANGED", event)
	return event
end

---------------------------------------------------------------------------------------------------------------------
-- The review of a rank change (the GM only)

-- The pending review { code, ts, missing = {permissions} } for the GM; nil for everybody else and when there is none.
function SettingsController:RankReview()
	if not PS() or PS():MyRank() ~= ns.Permissions.GM then return nil end
	return PS():RankReview()
end

-- The GM confirms the permission table after a change of the guild's ranks. Returns true, or false and a code.
function SettingsController:AcknowledgeRankReview()
	local ok, why = self:CanConfigure()
	if not ok then return false, why end
	PS():AcknowledgeRanks()
	emit("SETTINGS_PERMISSIONS_CHANGED")
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Personal settings

-- Changes a personal setting. Returns true, or false and a Config code ("READ_ONLY", "BAD_VALUE", "UNKNOWN_SETTING", ...).
function SettingsController:SetPersonal(name, value)
	local Config = ns.Config
	if not (Config and Config.db) then return false, "NOT_READY" end
	local ok, err
	if name == "theme" then
		ok, err = ns.Theme.Set(value)
	else
		ok, err = Config:Set(name, value)
		if ok and name == "fontSource" then
			ns.Theme.SetupFonts(value)
			ns.Theme.Apply()
		elseif ok and name == "effects" then
			ns.Theme.Apply()
		end
	end
	if ok then emit("SETTINGS_PERSONAL_CHANGED", name, value) end
	return ok, err
end

-- The personal language: "auto" or a registered code; applied at the next /reload.
function SettingsController:SetLanguage(code)
	local ok, err = ns.Config:SetLanguage(code)
	if ok then emit("SETTINGS_PERSONAL_CHANGED", "language", code) end
	return ok, err
end

-- Puts the loot popup back where it starts (the centre of the screen). Returns true.
function SettingsController:ResetPopup()
	local c = ns.Config and ns.Config.char
	if c and not ns.Config:IsReadOnly() then c.popup = nil end
	if ns.MemberLootPopup and ns.MemberLootPopup.ResetPlacement then ns.MemberLootPopup:ResetPlacement() end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The game's own settings window

-- The options of the addon's entry in the game's settings (AceConfig): the personal switches and a button that opens the
-- addon window. The rules are not here: they belong to the Guild Master's tab.
function SettingsController:GameOptions()
	local L = ns.L
	local function toggle(order, key, name)
		return { type = "toggle", order = order, name = L[key],
			get = function() return ns.Config:Get(name) == true end,
			set = function(_, value) SettingsController:SetPersonal(name, value and true or false) end }
	end
	return {
		type = "group",
		name = L["ADDON_TITLE"],
		args = {
			note = { type = "description", order = 1, name = L["OPT_NOTE"], fontSize = "medium" },
			open = { type = "execute", order = 2, name = L["OPT_OPEN"], desc = L["OPT_OPEN_DESC"],
				func = function() if ns.MainWindow then ns.MainWindow:Open("settings") end end },
			effects = toggle(3, "PERSONAL_EFFECTS", "effects"),
			animations = toggle(4, "PERSONAL_ANIMATIONS", "animations"),
			sounds = toggle(5, "PERSONAL_SOUNDS", "sounds"),
		},
	}
end

-- Registers the entry once (at login). Returns true when the game's settings window took it. Never raises: a client
-- whose settings API differs just goes without the entry.
function SettingsController:RegisterGameOptions()
	if self.registered then return true end
	local ok = pcall(function()
		local registry = LibStub("AceConfigRegistry-3.0")
		local dialog = LibStub("AceConfigDialog-3.0")
		registry:RegisterOptionsTable("FinlandDragonCreditPoints", function() return SettingsController:GameOptions() end)
		dialog:AddToBlizOptions("FinlandDragonCreditPoints", ns.L["ADDON_TITLE"])
	end)
	if not ok then log("warn", "GAME_OPTIONS_FAILED") end
	self.registered = ok
	return ok
end

if ns.addon then ns.addon.SettingsController = SettingsController end   -- also reachable from tests
