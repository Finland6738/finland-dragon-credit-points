-- ProgressController: the first kills of the Progress tab (docs/ANALISI.md §7.1, docs/specs/site-export.md §4, §5;
-- M3-3b). Lua 5.1. The rules are in Domain/Progress.lua (pure); this module is the glue with the game: ENCOUNTER_ENDED
-- from Adapters/Group.lua, Compat (the instance, the guild group, the Encounter Journal names), the permission service
-- and the guild's ledger (the one App/NightController.lua opens: one ledger, one binding).
--
-- * Inside an official night the night controller records the kill (with the lineup); this module leaves it alone.
-- * Outside a night (no night open, or a night in another instance) a kill is written as ENCOUNTER_KILLED without
--   `night` when: the kill succeeded, the player stands in a raid of Data/Instances.lua, the group is a guild group
--   (Compat.Group.InGuildParty), a season is open (the event belongs to it), the player may write the ledger's kills
--   (`night.run`) and the ledger has no recorded kill of that boss yet. Only the first one matters for the progress, so
--   farm kills do not fill the ledger, and two officers in the same raid write one kill at most once their ledgers
--   meet (the oldest date wins anyway).
-- * By hand (`progress.edit`, audited like every event): Set enters or corrects a first kill for a site key (the
--   guild's own by default, or the other community guild's as read on the site), Clear removes a value entered by hand.
-- * Names: Build gives the bosses in the client's language when the Encounter Journal knows them, else the English
--   names of the table.
--
-- Bus events: "PROGRESS_KILL_RECORDED"(event), "PROGRESS_CHANGED"(event).
-- Not verified in the real client: ENCOUNTER_END ids and InGuildParty on WoW Forever, the Encounter Journal ids.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local ProgressController = {}
ns.ProgressController, ns.modules.ProgressController = ProgressController, ProgressController

local type = type

local function log(level, code, ...) if ns.Log then ns.Log[level]("Progress", code, ...) end end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function plain(s) return ns.Log and ns.Log.Plain(s) or s end

local function NC() return ns.NightController end

local function gate()
	return ns.PermissionService and ns.PermissionService:Gate() or nil
end

local function now() return ns.Compat.ServerTime() end
local function today() return ns.Nights.FormatDay(ns.Compat.ServerDay()) end

-- The guild's ledger (shared with the night controller), or nil.
function ProgressController:Ledger()
	return NC() and NC():Ledger() or nil
end

-- The guild's key on the community site: the rules' site.factionName, else Nebulah / Nebulaa by the client's faction.
function ProgressController:FactionKey()
	local L = self:Ledger()
	local rules = L and ns.Rules.Current(L) or nil
	return ns.Progress.FactionKey(rules, ns.Compat.Player.Faction())
end

---------------------------------------------------------------------------------------------------------------------
-- Kills outside a night

-- "ENCOUNTER_ENDED": a first kill outside an official night. Returns the ENCOUNTER_KILLED event, or nil and a code:
-- "NOT_A_KILL", "NOT_IN_TABLE" (not a raid of Data/Instances.lua), "IN_NIGHT" (the night controller records it),
-- "NOT_GUILD_GROUP", "NOT_READY", "NO_SEASON", a permission code ("PENDING", "RANK_TOO_LOW", ...), "ALREADY_KILLED"
-- (the ledger has a kill of that boss already) or a ledger code.
function ProgressController:OnEncounterEnd(info)
	if type(info) ~= "table" or not info.success then return nil, "NOT_A_KILL" end
	local inst = ns.Compat.Encounter.Instance()
	local entry = inst and ns.Instances.Get(inst.instanceID)
	if not entry then return nil, "NOT_IN_TABLE" end
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	local season = ns.Season.Current(L)
	if not season then return nil, "NO_SEASON" end
	local night = ns.Nights.Current(L, season.id)
	if night and night.instanceID == inst.instanceID then return nil, "IN_NIGHT" end
	if ns.Compat.Group.InGuildParty() ~= true then return nil, "NOT_GUILD_GROUP" end
	local ok, why = NC():Can("night.run")
	if not ok then return nil, why end
	local me = NC():Me()
	if not me then return nil, "NOT_READY" end
	if ns.Progress.HasKill(L, info.encounterID) then return nil, "ALREADY_KILLED" end
	local ts = now()
	local event, code = ns.Nights.Kill(L, { author = me, ts = ts, season = season.id, encounterID = info.encounterID,
		difficulty = info.difficultyID, size = info.groupSize, time = ts, date = today(), instanceID = inst.instanceID },
		gate())
	if not event then
		log("warn", "KILL_REFUSED", plain(code))
		return nil, code
	end
	log("info", "FIRST_KILL", info.encounterID)
	emit("PROGRESS_KILL_RECORDED", event)
	return event
end

---------------------------------------------------------------------------------------------------------------------
-- By hand (progress.edit)

local function editor(self)
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	local ok, why = NC():Can("progress.edit")
	if not ok then return nil, why end
	local me = NC():Me()
	if not me then return nil, "NOT_READY" end
	return L, me
end

-- Enters or corrects the first kill of a boss: `date` "YYYY-MM-DD", `faction` a site key (the guild's own when nil).
-- Returns the PROGRESS_SET event, or nil and a code ("NOT_READY", a permission code, "NO_FACTION", "UNKNOWN_ENCOUNTER",
-- "date", "FUTURE", "UNCHANGED", ...).
function ProgressController:Set(encounterID, date, faction)
	local L, me = editor(self)
	if not L then return nil, me end
	faction = faction or self:FactionKey()
	if not faction then return nil, "NO_FACTION" end
	local event, why = ns.Progress.Set(L, { author = me, ts = now(), encounterID = encounterID, faction = faction,
		date = date, today = today() }, gate())
	if not event then return nil, why end
	log("info", "PROGRESS_SET", encounterID)
	emit("PROGRESS_CHANGED", event)
	return event
end

-- Removes the value entered by hand for a boss (the guild's own key when `faction` is nil). Returns the PROGRESS_SET
-- event, or nil and a code ("NOTHING_TO_CLEAR", a permission code, ...).
function ProgressController:Clear(encounterID, faction)
	local L, me = editor(self)
	if not L then return nil, me end
	faction = faction or self:FactionKey()
	if not faction then return nil, "NO_FACTION" end
	local event, why = ns.Progress.Clear(L, { author = me, ts = now(), encounterID = encounterID, faction = faction },
		gate())
	if not event then return nil, why end
	log("info", "PROGRESS_CLEARED", encounterID)
	emit("PROGRESS_CHANGED", event)
	return event
end

---------------------------------------------------------------------------------------------------------------------
-- What the windows read

-- A boss's or an instance's name in the client's language, nil when the Encounter Journal does not know it.
local function localName(boss, inst)
	local E = ns.Compat.Encounter
	if boss then return E.JournalName(boss.journalID, boss.encounterID) end
	return E.JournalInstanceName(inst.journalInstanceID, inst.instanceID)
end

-- The progress of every instance of the table (Progress.Build), with the names in the client's language. Everyone may
-- read it (the site shows it publicly). Returns the table, or nil and "NOT_READY".
function ProgressController:Build()
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	return ns.Progress.Build(L, self:FactionKey(), { localName = localName })
end

---------------------------------------------------------------------------------------------------------------------
-- Wiring

if ns.Bus then
	ns.Bus:On("ENCOUNTER_ENDED", function(_, info) ProgressController:OnEncounterEnd(info) end, ProgressController)
end

if ns.addon then
	ns.addon.ProgressController = ProgressController   -- also reachable from tests
	if ns.addon.AddDebugSection then
		ns.addon:AddDebugSection("Progress", function()
			local key = ProgressController:FactionKey()
			return { ("Progress: site key %s"):format(key or "unknown") }   -- nolocale (debug output)
		end)
	end
end
