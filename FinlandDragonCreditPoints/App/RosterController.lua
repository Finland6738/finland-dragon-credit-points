-- RosterController: what the Roster > Pool window reads and writes (docs/ANALISI.md §6, §9.3, M3-7). Lua 5.1. The rules are
-- in Domain/Roster.lua (pure); this module is the glue with the guild's ledger, the permission service and the player.
--
-- * The pool is read from the ledger (Roster.State), never stored apart: three role columns for one faction, each with the
--   players of that role, the count against the target and the free slots. The targets come from the raid size of the
--   season's pack and the guild's bench minimums (tanks, healers); the rest of the slots are damage dealers.
-- * Writes need `roster.manage` (an officer): a status change (Raider / Trial / Inactive), and the approval or rejection of
--   the requests of the players (a declaration to join, an alt). The requests are plain data kept with the guild's data
--   (outside the ledger, Roster.NewRequests); until the transport of M6 delivers them they only come from the tests and
--   from the owner's own character.
-- * Every refusal is a code the window turns into a locale key (App/RosterController.lua never writes a sentence).
--
-- Bus events: "ROSTER_VIEW_CHANGED" (the faction shown changed), "ROSTER_UPDATED" (a write succeeded).
-- Not verified in the real client: the guild roster and ranks in game (M0 spike S3), the window itself.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local RosterController = {}
ns.RosterController, ns.modules.RosterController = RosterController, RosterController

local type, pairs, ipairs = type, pairs, ipairs

RosterController.ROLES = { "TANK", "HEALER", "DAMAGER" }
RosterController.FACTIONS = { "Horde", "Alliance" }
RosterController.DEFAULT_SIZE = 20
RosterController.faction = nil
RosterController.requests = nil

local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function now() return ns.Compat.ServerTime() end
local function NC() return ns.NightController end

function RosterController:Ledger() return NC() and NC():Ledger() or nil end
function RosterController:Me() return NC() and NC():Me() or nil end
function RosterController:Can(p)
	if not NC() then return false, "NOT_READY" end
	return NC():Can(p)
end
function RosterController:Season()
	local L = self:Ledger()
	return L and ns.Season.Current(L) or nil
end

local function gate() return ns.PermissionService and ns.PermissionService:Gate() or nil end

-- The faction the window shows: the one picked, else the player's own, else the Horde.
function RosterController:Faction()
	return self.faction or (ns.Compat.Player and ns.Compat.Player.Faction()) or "Horde"
end

function RosterController:SetFaction(faction)
	if faction ~= "Horde" and faction ~= "Alliance" then return false end
	if self.faction == faction then return true end
	self.faction = faction
	emit("ROSTER_VIEW_CHANGED", faction)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Reading

-- The raid size the targets are made for: the largest instance of the season's pack, or the default.
local function raidSize(season)
	local size = 0
	for _, inst in ipairs(season and season.instances or {}) do
		if type(inst.size) == "number" and inst.size > size then size = inst.size end
	end
	return size > 0 and size or RosterController.DEFAULT_SIZE
end

-- { TANK = n, HEALER = n, DAMAGER = n, size = n }: the composition the guild aims at.
function RosterController:Targets(L, season)
	local rules = ns.Rules.Current(L)
	local b = type(rules) == "table" and rules.bench or {}
	local d = ns.Rules.DefaultConfig().bench
	local size = raidSize(season)
	local tanks, healers = b.minTanks or d.minTanks, b.minHealers or d.minHealers
	return { TANK = tanks, HEALER = healers, DAMAGER = math.max(size - tanks - healers, 0), size = size }
end

local function inFaction(m, faction) return not m.faction or m.faction == faction end

-- The pool of the faction shown: { season, faction, size, roles = { TANK = { role, list, count, target, free, trial }, ... },
-- undeclared = { entries }, total, trial }. Entries are Roster.State's, plus `altCount`. nil and a code without a ledger or
-- an open season ("NOT_READY", "NO_SEASON").
function RosterController:Pool()
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	local season = ns.Season.Current(L)
	if not season then return nil, "NO_SEASON" end
	local faction = self:Faction()
	local targets = self:Targets(L, season)
	local out = { season = season.id, faction = faction, size = targets.size, roles = {}, undeclared = {}, total = 0, trial = 0 }
	for _, role in ipairs(self.ROLES) do
		out.roles[role] = { role = role, list = {}, count = 0, target = targets[role], free = 0, trial = 0 }
	end
	for _, m in ipairs(ns.Roster.List(L, season.id, { playing = true })) do
		if inFaction(m, faction) then
			m.altCount = m.alts and #m.alts or 0
			out.total = out.total + 1
			if m.status == "TRIAL" then out.trial = out.trial + 1 end
			local r = m.role and out.roles[m.role]
			if r then
				r.list[#r.list + 1] = m
				r.count = r.count + 1
				if m.status == "TRIAL" then r.trial = r.trial + 1 end
			else
				out.undeclared[#out.undeclared + 1] = m
			end
		end
	end
	for _, role in ipairs(self.ROLES) do
		local r = out.roles[role]
		r.free = math.max(r.target - r.count, 0)
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Writing (roster.manage)

local function writer(self)
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	local s = ns.Season.Current(L)
	if not s then return nil, "NO_SEASON" end
	local ok, why = self:Can("roster.manage")
	if not ok then return nil, why end
	if not self:Me() then return nil, "NOT_READY" end
	return L, s.id
end

-- Sets a member's status (ACTIVE | TRIAL | INACTIVE). Returns the event, or nil and a code ("NOT_READY", "NO_SEASON",
-- "PENDING", "RANK_TOO_LOW", "NOT_MEMBER", "UNCHANGED", ...).
function RosterController:SetStatus(name, status)
	local L, season = writer(self)
	if not L then return nil, season end
	local e, why = ns.Roster.SetStatus(L, { author = self:Me(), ts = now(), season = season, member = name, status = status },
		gate())
	if not e then return nil, why end
	emit("ROSTER_UPDATED", e)
	return e
end

---------------------------------------------------------------------------------------------------------------------
-- The players' requests

-- The requests of the guild: kept with the guild's data (outside the ledger), in memory when there is no guild data.
function RosterController:Requests()
	local data = ns.Config and ns.Config.GuildData and ns.Config:GuildData()
	if data and not ns.Config:IsReadOnly() then
		data.requests = data.requests or ns.Roster.NewRequests()
		return data.requests
	end
	self.requests = self.requests or ns.Roster.NewRequests()
	return self.requests
end

-- The pending requests of the open season, oldest first (officers only: `roster.manage`). Each is the table of
-- Roster.Pending. nil and a code when the player may not see them.
function RosterController:Pending()
	local L, season = writer(self)
	if not L then return nil, season end
	return ns.Roster.Pending(self:Requests(), season)
end

-- Asks to join the pool with a declaration (what the player's own window sends; stored here until M6 delivers it).
function RosterController:RequestJoin(req)
	local L = self:Ledger()
	local s = L and ns.Season.Current(L)
	if not s then return nil, "NO_SEASON" end
	req = req or {}
	req.season, req.ts, req.from = s.id, now(), req.from or self:Me()
	local r, why = ns.Roster.RequestJoin(self:Requests(), L, req)
	if r then emit("ROSTER_UPDATED", r) end
	return r, why
end

function RosterController:RequestAlt(req)
	local L = self:Ledger()
	local s = L and ns.Season.Current(L)
	if not s then return nil, "NO_SEASON" end
	req = req or {}
	req.season, req.ts, req.from = s.id, now(), req.from or self:Me()
	local r, why = ns.Roster.RequestAlt(self:Requests(), L, req)
	if r then emit("ROSTER_UPDATED", r) end
	return r, why
end

-- Approves a request: the event is written with the late-joiner rule of the guild. Returns the event, or nil and a code.
function RosterController:Approve(id)
	local L, season = writer(self)
	if not L then return nil, season end
	local e, why = ns.Roster.Approve(self:Requests(), L, id,
		{ author = self:Me(), ts = now(), nights = ns.Nights.Played(L, season) }, nil, gate())
	if not e then return nil, why end
	emit("ROSTER_UPDATED", e)
	return e
end

function RosterController:Reject(id)
	local L = writer(self)
	if not L then return nil, "RANK_TOO_LOW" end
	local ok, why = ns.Roster.Reject(self:Requests(), id, self:Me(), now())
	if not ok then return nil, why end
	emit("ROSTER_UPDATED", id)
	return true
end

if ns.Bus then
	ns.Bus:On("GUILD_KEY_CHANGED", function() RosterController.requests = nil end, RosterController)
end
if ns.addon then ns.addon.RosterController = RosterController end   -- also reachable from tests
