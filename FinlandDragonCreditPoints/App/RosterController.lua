-- RosterController: what the Roster > Pool window reads and writes (docs/ANALISI.md §6, §9.3, M3-7, fix/roster-join). Lua
-- 5.1. The rules are in Domain/Roster.lua (pure); this module is the glue with the guild's ledger, the permission service,
-- the network (Net/RosterNet.lua) and the player.
--
-- * The pool is read from the ledger (Roster.State), never stored apart: three role columns, each with the players of
--   that role, the count against the target and the free slots. The targets come from the raid size of the season's pack
--   and the guild's bench minimums (tanks, healers); the rest of the slots are damage dealers. One guild is one faction in
--   game (Nebulah is Horde, Nebulaa Alliance: two guilds, two ledgers), so the pool shown is the faction of the player's
--   own guild; there is no faction switch (the faction stays in the data and in the site export).
-- * A player **asks** (SendJoin: the declaration, SendAlt: "this character is an alt of ..."): the request goes to the
--   guild's officers through Net/RosterNet.lua, and the player follows it (MyStatus: sending, sent, pending, approved,
--   rejected). A member already in the pool without a declaration (added by an officer) sends the same form: approved, it
--   becomes the officer's ROSTER_CHANGED.
-- * An officer (`roster.manage`) keeps the requests heard (outside the ledger, Roster.NewRequests), approves them (the
--   MEMBER_JOINED with the guild's late-joiner rule, Roster.Approve) or rejects them, and the decision is told to the guild.
--   An officer also **adds a player directly** (AddMember: a raid or guild member not in the pool, the class read from the
--   game, MS1 required) or **adds the raid group** (AddRaid: the raid's guild members missing from the pool, without a
--   declaration; each player then sends their own, docs/ANALISI.md §6.1), and changes a status (Raider / Trial / Inactive).
-- * Every refusal is a code the window turns into a locale key (App/RosterController.lua never writes a sentence).
--
-- Bus events: "ROSTER_UPDATED" (a write succeeded, a request came or was decided), "ROSTER_MY_REQUEST" (the player's own
-- request changed state).
-- Not verified in the real client: the guild roster and ranks in game (M0 spike S3), the GUILD and WHISPER addon messages
-- of the requests, the window itself.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local RosterController = {}
ns.RosterController, ns.modules.RosterController = RosterController, RosterController

local type, pairs, ipairs = type, pairs, ipairs

RosterController.ROLES = { "TANK", "HEALER", "DAMAGER" }
RosterController.DEFAULT_SIZE = 20
RosterController.SEND_GAP = 30      -- seconds between two requests of the player (the officers dedupe the rest)
RosterController.faction = nil      -- the faction shown; nil = the player's own (the guild's). Tests set it.
RosterController.requests = nil
RosterController.mine = nil         -- the player's own request when there is no guild data to keep it in

local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function now() return ns.Compat.ServerTime() end
local function NC() return ns.NightController end
local function fullName(name) return ns.GuildRanks and ns.GuildRanks.FullName(name) or name end

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

-- The faction of the player's guild (one guild is one faction in game): the player's own, else the Horde.
function RosterController:Faction()
	return self.faction or (ns.Compat.Player and ns.Compat.Player.Faction()) or "Horde"
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

-- The pool of the guild's faction: { season, faction, size, roles = { TANK = { role, list, count, target, free, trial }, ... },
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
-- The officers: adding players directly

-- The late-joiner credits a player would start with if added now (Members.LateJoinCredits, the rule the approval uses):
-- value and rule, or nil and a code.
function RosterController:JoinCredits(name)
	local L, season = writer(self)
	if not L then return nil, season end
	if ns.Season.NightCount(L, season) == 0 then
		local s = ns.Season.Get(L, season)
		return s and s.startCredits or 0, ns.Members.RULES.START
	end
	local value, rule = ns.Members.LateJoinCredits(L, season, nil,
		{ faction = self:Faction(), nights = ns.Nights.Played(L, season), exclude = name })
	return value, rule
end

-- The players an officer may add: the raid group's and the guild roster's characters who are neither in the pool nor
-- an alt of the season, with the class the game gives. { { name, class, inRaid, online, level }, ... }, the raid first,
-- then the online members, then by name. nil and a code without `roster.manage` or an open season.
function RosterController:Candidates()
	local L, season = writer(self)
	if not L then return nil, season end
	local state = ns.Roster.State(L, season)
	local seen, out = {}, {}
	local function add(name, class, inRaid, online, level)
		local full = fullName(name)
		if not full or seen[full] or state.members[full] or state.alts[full] then return end
		if not (type(class) == "string" and ns.Roster.CLASSES[class]) then return end
		seen[full] = true
		out[#out + 1] = { name = full, class = class, inRaid = inRaid or nil, online = online or nil, level = level }
	end
	local snap = ns.Group and ns.Group.Snapshot()
	if snap and snap.inRaid then
		for name, row in pairs(snap.members) do
			if ns.GuildRanks.RankOf(name) ~= nil then add(name, row.classFile, true, row.online ~= false, row.level) end
		end
	end
	for _, row in ipairs(ns.Compat.Guild.Roster()) do
		add(row.name, row.classFile, false, row.online, row.level)
	end
	table.sort(out, function(a, b)
		if (a.inRaid or false) ~= (b.inRaid or false) then return a.inRaid == true end
		if (a.online or false) ~= (b.online or false) then return a.online == true end
		return a.name < b.name
	end)
	return out
end

-- An officer adds a player to the pool with a declaration: decl = { class, ms1, ms2?, os?, avail?, note?, status? }. The
-- MEMBER_JOINED is written with the guild's late-joiner rule (the nights played so far). Returns the event, or nil and
-- a code (writer codes, "ALREADY_JOINED", a Roster.Complete code, ...).
function RosterController:AddMember(name, decl)
	local L, season = writer(self)
	if not L then return nil, season end
	local full = fullName(name)
	if not full then return nil, "member" end
	local d = { author = self:Me(), ts = now(), season = season, member = full, faction = self:Faction(),
		nights = ns.Nights.Played(L, season) }
	for _, f in ipairs(ns.Roster.FIELDS) do
		if f ~= "twin" and type(decl) == "table" then d[f] = decl[f] end
	end
	local e, why = ns.Roster.Join(L, d, nil, gate())
	if not e then return nil, why end
	ns.Roster.Settle(self:Requests(), L, now())
	emit("ROSTER_UPDATED", e)
	return e
end

-- The raid group's guild members missing from the pool (what "Add the raid group" adds): { { name, class }, ... } by
-- name. nil and a code without `roster.manage`, an open season or a raid.
function RosterController:RaidMissing()
	local L, season = writer(self)
	if not L then return nil, season end
	local snap = ns.Group and ns.Group.Snapshot()
	if not (snap and snap.inRaid) then return nil, "NOT_IN_RAID" end
	local state = ns.Roster.State(L, season)
	local out = {}
	for name, row in pairs(snap.members) do
		if not state.members[name] and not state.alts[name] and ns.GuildRanks.RankOf(name) ~= nil
			and type(row.classFile) == "string" and ns.Roster.CLASSES[row.classFile] then
			out[#out + 1] = { name = name, class = row.classFile }
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

-- Adds the raid group's missing guild members, without a declaration (only the class the game gives): each player then
-- declares MS1 / MS2 / OS from their own window and an officer approves it (a ROSTER_CHANGED). Every MEMBER_JOINED keeps
-- the late-joiner rule. Returns the list of the events written and the list of { name, code } refused, or nil and a code.
function RosterController:AddRaid()
	local missing, why = self:RaidMissing()
	if not missing then return nil, why end
	if #missing == 0 then return nil, "NOBODY_MISSING" end
	local L, season = writer(self)
	local nights = ns.Nights.Played(L, season)
	local added, refused = {}, {}
	for _, m in ipairs(missing) do
		local e, code = ns.Members.Join(L, { author = self:Me(), ts = now(), season = season, member = m.name,
			faction = self:Faction(), nights = nights, decl = { class = m.class } }, nil, gate())
		if e then added[#added + 1] = e else refused[#refused + 1] = { name = m.name, code = code } end
	end
	if #added > 0 then emit("ROSTER_UPDATED", added[1]) end
	return added, refused
end

---------------------------------------------------------------------------------------------------------------------
-- The players' requests: the officers' side

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
-- Roster.Pending; the ones the ledger already settled (another officer approved them, the sync brought the event) leave.
-- nil and a code when the player may not see them.
function RosterController:Pending()
	local L, season = writer(self)
	if not L then return nil, season end
	local R = self:Requests()
	ns.Roster.Settle(R, L, now())
	return ns.Roster.Pending(R, season)
end

-- A request heard from a player (Net/RosterNet.lua): stored when this client is an officer's. `req` carries the fields
-- of Roster.Receive, `id` is "<sender>#<n>". Returns the stored request, or nil and a code ("RANK_TOO_LOW", "DUPLICATE",
-- "REQUEST_PENDING", a check code ...).
function RosterController:Receive(req)
	local L, season = writer(self)
	if not L then return nil, season end
	local R = self:Requests()
	ns.Roster.Prune(R, L, now() - 30 * 86400)
	local r, why = ns.Roster.Receive(R, L, req)
	if r then emit("ROSTER_UPDATED", r) end
	return r, why
end

-- Another officer's decision heard on the network: the request leaves this inbox too.
function RosterController:Closed(id, state, by)
	local ok = ns.Roster.Close(self:Requests(), id, state, by, now())
	if ok then emit("ROSTER_UPDATED", id) end
	return ok
end

-- Stores a request written on this client (the tests, an officer's own request). `kind` = "JOIN" | "ALT".
local function storeLocal(self, kind, req)
	local L = self:Ledger()
	local s = L and ns.Season.Current(L)
	if not s then return nil, "NO_SEASON" end
	req = req or {}
	req.season, req.ts, req.from = s.id, now(), req.from or self:Me()
	local fn = kind == "JOIN" and ns.Roster.RequestJoin or ns.Roster.RequestAlt
	local r, why = fn(self:Requests(), L, req)
	if r then emit("ROSTER_UPDATED", r) end
	return r, why
end

function RosterController:RequestJoin(req) return storeLocal(self, "JOIN", req) end
function RosterController:RequestAlt(req) return storeLocal(self, "ALT", req) end

local function tell(id, state)
	if ns.RosterNet then ns.RosterNet:Decide(id, state) end
end

-- Approves a request: the event is written with the late-joiner rule of the guild, and the decision is told to the
-- guild (the player, the other officers). Returns the event, or nil and a code.
function RosterController:Approve(id)
	local L, season = writer(self)
	if not L then return nil, season end
	local e, why = ns.Roster.Approve(self:Requests(), L, id,
		{ author = self:Me(), ts = now(), nights = ns.Nights.Played(L, season) }, nil, gate())
	if not e then return nil, why end
	tell(id, "APPROVED")
	emit("ROSTER_UPDATED", e)
	return e
end

function RosterController:Reject(id)
	local L = writer(self)
	if not L then return nil, "RANK_TOO_LOW" end
	local ok, why = ns.Roster.Reject(self:Requests(), id, self:Me(), now())
	if not ok then return nil, why end
	tell(id, "REJECTED")
	emit("ROSTER_UPDATED", id)
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The players' requests: the player's side

-- The open season as this client knows it: from its own ledger (an officer), else from the credits snapshot an officer
-- sent (every other member, Net/Snapshot.lua). { season, source = "ledger" | "snapshot", members = { [name] = { class,
-- faction, declared } }, alts = { [alt] = main } } or nil and "NO_SEASON".
function RosterController:SeasonView()
	local L = self:Ledger()
	local s = L and ns.Season.Current(L)
	if s then
		local st = ns.Roster.State(L, s.id)
		local members = {}
		for name, m in pairs(st.members) do
			members[name] = { class = m.class, faction = m.faction, declared = m.declared, status = m.status }
		end
		return { season = s.id, source = "ledger", members = members, alts = st.alts }
	end
	local kept = ns.Snapshot and ns.Snapshot:Kept()
	local data = kept and kept.data
	if type(data) ~= "table" or not data.so then return nil, "NO_SEASON" end
	local members, alts = {}, {}
	for _, row in ipairs(data.r or {}) do
		members[row.m] = { class = row.c, faction = row.f, declared = row.sp ~= nil, status = row.st }
		for _, a in ipairs(row.al or {}) do alts[a] = row.m end
	end
	return { season = data.s, source = "snapshot", members = members, alts = alts }
end

-- The mains of the open season the player may name in an alt request, by name (the guild's faction).
function RosterController:Mains()
	local view = self:SeasonView()
	local out = {}
	if not view then return out end
	local me, faction = self:Me(), self:Faction()
	for name, m in pairs(view.members) do
		if name ~= me and (not m.faction or m.faction == faction) then out[#out + 1] = name end
	end
	table.sort(out)
	return out
end

local function myStore(self)
	local data = ns.Config and ns.Config.GuildData and ns.Config:GuildData()
	if data and not ns.Config:IsReadOnly() then
		data.myRequests = data.myRequests or {}
		return data.myRequests
	end
	self.mine = self.mine or {}
	return self.mine
end

-- The player's own last request: { kind, season, q, state = "SENDING" | "SENT" | "PENDING" | "APPROVED" | "REJECTED" |
-- "REFUSED", code?, at, main?, ms1? } or nil. Kept per character with the guild's data.
function RosterController:MyRequest()
	local me = self:Me()
	return me and myStore(self)[me] or nil
end

local function setMine(self, rec)
	local me = self:Me()
	if not me then return end
	myStore(self)[me] = rec
	emit("ROSTER_MY_REQUEST", rec)
end

-- Where the player stands in the open season: { season, state = "OUT" | "UNDECLARED" | "IN" | "ALT", main?, request? }
-- or nil and a code ("NOT_READY", "NO_SEASON"). A request of the season the ledger (or the snapshot) already shows
-- done is APPROVED.
function RosterController:MyStatus()
	local me = self:Me()
	if not me then return nil, "NOT_READY" end
	local view, why = self:SeasonView()
	if not view then return nil, why end
	local m = view.members[me]
	local out = { season = view.season, source = view.source }
	if m then
		out.state = m.declared and "IN" or "UNDECLARED"
	elseif view.alts[me] then
		out.state, out.main = "ALT", view.alts[me]
	else
		out.state = "OUT"
	end
	local rec = self:MyRequest()
	if rec and rec.season == view.season then
		local done = (rec.kind == "JOIN" and out.state == "IN") or (rec.kind == "ALT" and out.state == "ALT")
		if done and rec.state ~= "APPROVED" then rec.state = "APPROVED" end
		out.request = rec
	end
	return out
end

-- The player's next request may go out now? true, or false and the seconds to wait.
function RosterController:CanSend()
	local rec = self:MyRequest()
	local wait = rec and rec.at and (rec.at + self.SEND_GAP - now()) or 0
	if wait > 0 then return false, wait end
	return true
end

local function send(self, kind, fields)
	local status, why = self:MyStatus()
	if not status then return nil, why end
	local ok, wait = self:CanSend()
	if not ok then return nil, "TOO_SOON", wait end
	if not ns.RosterNet then return nil, "NOT_READY" end
	local me = self:Me()
	local req = { kind = kind, season = status.season, from = me, faction = self:Faction() }
	for k, v in pairs(fields) do req[k] = v end
	local q, wire = ns.RosterNet:Send(req)
	if not q then return nil, wire end
	local rec = { kind = kind, season = status.season, q = q, state = "SENDING", at = now(), main = req.main,
		ms1 = req.ms1, wire = wire }
	setMine(self, rec)
	-- an officer's own request is stored here too (the client does not hear its own GUILD message)
	if self:Can("roster.manage") == true then
		local r = self:Receive(ns.RosterNet.Request(req, me, q))
		if r then rec.state = "PENDING" end
	end
	return rec
end

-- The player asks to join the pool (or, already in it without a declaration, declares): fields = { ms1, ms2?, os?,
-- avail?, note? }; the class and the faction are the client's. Returns the player's request record, or nil and a code:
-- "NO_SEASON", "ALREADY_JOINED", "IS_ALT", "TOO_SOON" (and the seconds), "NO_CLASS", a Roster.Complete code, a transport
-- code.
function RosterController:SendJoin(fields)
	local status, why = self:MyStatus()
	if not status then return nil, why end
	if status.state == "IN" then return nil, "ALREADY_JOINED" end
	if status.state == "ALT" then return nil, "IS_ALT" end
	local class = ns.Compat.Player.ClassFile()
	if not (class and ns.Roster.CLASSES[class]) then return nil, "NO_CLASS" end
	local decl = { class = class }
	for _, f in ipairs({ "ms1", "ms2", "os", "avail", "note" }) do
		if type(fields) == "table" and fields[f] ~= nil then decl[f] = fields[f] end
	end
	local clean, code = ns.Roster.Complete(decl)
	if not clean then return nil, code end
	clean.status, clean.twin, clean.role = nil, nil, nil
	clean.member = self:Me()
	return send(self, "JOIN", clean)
end

-- The player links this character as an alt of `main` (a main of the open season). Returns the record, or nil and a
-- code: "NO_SEASON", "ALREADY_JOINED" (this character is a main), "ALREADY_LINKED", "MAIN_UNKNOWN", "TOO_SOON", ...
function RosterController:SendAlt(main)
	local status, why = self:MyStatus()
	if not status then return nil, why end
	if status.state == "IN" or status.state == "UNDECLARED" then return nil, "ALREADY_JOINED" end
	if status.state == "ALT" then return nil, "ALREADY_LINKED" end
	main = fullName(main)
	local view = self:SeasonView()
	if not (main and view and view.members[main]) then return nil, "MAIN_UNKNOWN" end
	return send(self, "ALT", { alt = self:Me(), main = main })
end

-- The transport handed the request to the client (RosterNet): "sent".
function RosterController:OnSent(q)
	local rec = self:MyRequest()
	if rec and rec.q == q and rec.state == "SENDING" then
		rec.state = "SENT"
		emit("ROSTER_MY_REQUEST", rec)
	end
end

-- An officer's answer about the player's request `q`: "PENDING" (stored), "APPROVED", "REJECTED", or a refusal code
-- (the request was not stored: "ALREADY_JOINED", "SPEC_CLASS", ...).
function RosterController:OnAnswer(q, state)
	local rec = self:MyRequest()
	if not rec or rec.q ~= q then return false end
	if rec.state == "APPROVED" or rec.state == "REJECTED" then return false end
	if state == "PENDING" or state == "APPROVED" or state == "REJECTED" then
		if state == "PENDING" and rec.state == "PENDING" then return false end
		rec.state, rec.code = state, nil
	else
		if rec.state == "PENDING" then return false end   -- another officer already stored it
		rec.state, rec.code = "REFUSED", state
	end
	emit("ROSTER_MY_REQUEST", rec)
	return true
end

if ns.Bus then
	ns.Bus:On("GUILD_KEY_CHANGED", function() RosterController.requests, RosterController.mine = nil, nil end,
		RosterController)
end
if ns.addon then ns.addon.RosterController = RosterController end   -- also reachable from tests
