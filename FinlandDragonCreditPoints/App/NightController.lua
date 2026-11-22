-- NightController: opens and closes an official raid night, keeps its lineup from the raid group and records the boss
-- kills (docs/ANALISI.md §2, §6, §3.1, M3-3). Lua 5.1. The rules are in Domain/Nights.lua (pure); this module is the glue
-- with the game: Adapters/Group.lua (the raid and ENCOUNTER_END), the permission service (night.run, view.attendance) and
-- the guild's ledger.
--
-- * The night lives in the ledger (NIGHT_OPENED / NIGHT_CLOSED, LINEUP_CHANGED, ENCOUNTER_KILLED), never in a table of its
--   own, so a /reload resumes it: the controller only remembers who was in the group at the last scan, in memory.
-- * Who writes: the officer who opened the night (or the master looter named in it) records the lineup and the kills; any
--   other officer's client leaves them alone (a kill two officers write twice is counted once anyway, Nights.Kills).
-- * The lineup follows the raid group. At every group scan (and just before a kill is written, so the lineup is the one of
--   the kill) a main who is in the group becomes RAID, one who left becomes ABSENT, and an alt in the raid counts for its
--   main. A member the master looter benched stays BENCH while they are not in the group, and also while they are in it
--   until they join again; Bench / Unbench / SetState write the lineup by hand. When the client hides a row (spike S7) the
--   scan only adds, it never removes anybody.
-- * A kill is written on ENCOUNTER_END with success, inside the night's instance; outside a night nothing is written here
--   (M3-3b records those).
-- * Attendance is for the officers: Attendance() answers only with `view.attendance` (§6, owner decision).
--
-- * Planning (M3-4): ProposeBench asks Domain/Rotation.lua who to bench (fewest benches, role minimums, the calendar's
--   sign-ups) and **writes nothing**: the master looter decides and ApplyBench writes the bench in one lineup change. A night
--   is linked to the official raid event of the game's calendar when there is one (Adapters/Calendar.lua, `eventID`).
--
-- * Absences (M7-5b, owner rule of 2026-11-22): at the close the controller keeps the calendar's sign-ups of the night (in
--   memory) and AbsenceProposal lists the penalties of Domain/Absence.lua; the officer confirms them with ApplyAbsences
--   (one CREDITS_ADJUSTED each, reason ABSENCE), or the close writes them by itself when the rules say
--   `penalties.autoApply`. A player benches themselves with SelfBench: the request goes on GUILD (NBENCH) to the client
--   that runs the night, which writes it as a self-bench (LINEUP_CHANGED `self`); the sender is the client's, never a field.
--
-- Bus events: "NIGHT_OPENED"(night), "NIGHT_CLOSED"(night), "NIGHT_LINEUP_CHANGED"(night, event),
-- "NIGHT_ENCOUNTER_RECORDED"(night, event), "NIGHT_ABSENCES_APPLIED"(night, events).
-- Not verified in the real client (M0 spike S4/S7): the group events in a raid and the encounter ids of Forever.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local NightController = {}
ns.NightController, ns.modules.NightController = NightController, NightController

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber

local function log(level, code, ...) if ns.Log then ns.Log[level]("Nights", code, ...) end end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end

NightController.ledger = nil
NightController.group = nil   -- { [night id] = { [main] = true } }: who was in the group at the last complete scan
NightController.signups = nil -- { [night id] = { [name] = "yes" | "maybe" | "no" } }: the calendar's answers read at the close
NightController.SELF_BENCH_MSG = "NBENCH"   -- a player's request to bench themselves (GUILD)

---------------------------------------------------------------------------------------------------------------------
-- The ledger and the player

-- Binds a ledger table (tests, or the store of a later step). Returns it.
function NightController:Bind(ledger)
	self.ledger = ledger
	self.group = {}
	self.signups = {}
	if ns.PermissionService then ns.PermissionService:BindLedger(ledger) end
	return ledger
end

-- The guild's ledger, opened from the saved data of the current guild on first use (nil without a guild). A ledger
-- written by a newer addon is read-only: every write answers READ_ONLY.
function NightController:Ledger()
	if self.ledger then return self.ledger end
	local data = ns.Config and ns.Config.GuildData and ns.Config:GuildData()
	if not data or ns.Config:IsReadOnly() then return nil end   -- a read-only database is never written, not even empty
	data.ledger = ns.Ledger.Open(data.ledger)
	return self:Bind(data.ledger)
end

function NightController:Me()
	return ns.GuildRanks and ns.GuildRanks.Me()
end

local function now() return ns.Compat.ServerTime() end

-- The realm's day as "YYYY-MM-DD" (what the site shows).
local function today() return ns.Nights.FormatDay(ns.Compat.ServerDay()) end

-- The season a night belongs to: the open one.
function NightController:Season()
	local L = self:Ledger()
	return L and ns.Season.Current(L) or nil
end

-- The open night of the open season, or nil.
function NightController:Current()
	local L, s = self:Ledger(), self:Season()
	if not L or not s then return nil end
	return ns.Nights.Current(L, s.id)
end

-- The trust gate for the writes (the permission service's, nil in a client without it).
local function gate()
	return ns.PermissionService and ns.PermissionService:Gate() or nil
end

-- May the player use permission `p` now? true, or false and a code ("PENDING" while the guild roster loads, "NOT_IN_GUILD",
-- "RANK_TOO_LOW", "NOT_GM"). A client without the permission service answers true.
function NightController:Can(p)
	if not ns.PermissionService then return true end
	return ns.PermissionService:Can(p, nil, self.ledger)
end

-- True when this client records the lineup and the kills of `night`: the officer who opened it or its master looter.
function NightController:IsRunner(night)
	local me = self:Me()
	return night ~= nil and me ~= nil and (night.author == me or night.ml == me)
end

-- The common start of a write: the ledger, the open season, the right to run a night. Returns L, season id or nil, code.
local function writer(self)
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	local s = ns.Season.Current(L)
	if not s then return nil, "NO_SEASON" end
	local ok, why = self:Can("night.run")
	if not ok then return nil, why end
	if not self:Me() then return nil, "NOT_READY" end
	return L, s.id
end

---------------------------------------------------------------------------------------------------------------------
-- Opening and closing

-- The main of a character in the season's pool (an alt counts for its main), or nil.
local function mainOf(rs, name)
	local full = ns.GuildRanks and ns.GuildRanks.FullName(name) or name   -- "Fox" is "Fox-<this realm>" in the ledger
	if rs.members[full] then return full end
	return rs.alts[full]
end

-- Opens an official night. args = { instanceID?, difficulty?, bench? = {names}, ml?, eventID? }: `eventID` is the official
-- raid event of the game's calendar the night is linked to (found for today's date when not given, left out when the
-- calendar has none or is not loaded); the instance and the difficulty default to the instance the player stands in (when it is a raid of the season's pack); `bench` is the planned bench, a
-- list of pool mains (they stay BENCH while they are not in the raid). The lineup is read from the raid group at once.
-- Returns the night record, or nil and a code: "NOT_READY", "NO_SEASON", "PENDING", "NOT_IN_GUILD", "RANK_TOO_LOW",
-- "NOT_IN_PACK" (only the official raids of the season count), "DIFFICULTY" (the client does not say which: pass it),
-- "NIGHT_ALREADY_OPEN", "NOT_MEMBER" (a benched name is not in the pool), "READ_ONLY" or a Ledger code.
function NightController:Open(args)
	args = args or {}
	local L, season = writer(self)
	if not L then return nil, season end
	local instanceID, difficulty = args.instanceID, args.difficulty
	if instanceID == nil or difficulty == nil then
		local inst = ns.Compat.Encounter.Instance()
		if inst and inst.type == "raid" then
			instanceID = instanceID or inst.instanceID
			if difficulty == nil then difficulty = ns.Nights.DifficultyCode(inst.difficultyID, inst.difficultyName) end
		end
	end
	if instanceID == nil then return nil, "NOT_IN_PACK" end
	local bench = {}
	if args.bench then
		local rs = ns.Roster.State(L, season)
		for _, name in ipairs(args.bench) do
			local main = mainOf(rs, name)
			if not main then return nil, "NOT_MEMBER" end
			bench[#bench + 1] = main
		end
	end
	local ts = now()
	local eventID = args.eventID
	if eventID == nil and ns.Calendar then
		local found = ns.Calendar.FindRaidEvent(ns.Compat.ServerDay())
		eventID = found and found.eventID or nil
	end
	local event, why = ns.Nights.Open(L, { author = self:Me(), ts = ts, season = season, date = today(),
		instanceID = instanceID, difficulty = difficulty, faction = ns.Compat.Player.Faction(), ml = args.ml,
		eventID = eventID }, gate())
	if not event then return nil, why end
	local night = ns.Nights.Get(L, event.id)
	log("info", "NIGHT_OPENED", ns.Log and ns.Log.Plain(night.difficulty), night.size)
	self.group[night.id] = nil
	if #bench > 0 then
		local _, code = ns.Nights.SetLineup(L, { author = self:Me(), ts = ts, season = season, bench = bench }, gate())
		if code and code ~= "NO_CHANGE" then log("warn", "BENCH_REFUSED", ns.Log and ns.Log.Plain(code)) end
	end
	emit("NIGHT_OPENED", night)
	self:Sync()
	return night
end

-- Closes the open night after a last read of the group. Returns the night record (closed), or nil and a code:
-- "NOT_READY", "NO_SEASON", a permission code, "NO_NIGHT_OPEN", "READ_ONLY" or a Ledger code.
function NightController:Close()
	local L, season = writer(self)
	if not L then return nil, season end
	local night = ns.Nights.Current(L, season)
	if not night then return nil, "NO_NIGHT_OPEN" end
	if self:IsRunner(night) then self:Sync() end
	local event, why = ns.Nights.Close(L, { author = self:Me(), ts = now(), season = season }, gate())
	if not event then return nil, why end
	self.group[night.id] = nil
	local closed = ns.Nights.Get(L, night.id)
	self.signups = self.signups or {}
	self.signups[night.id] = self:NightSignups(closed)
	log("info", "NIGHT_CLOSED")
	emit("NIGHT_CLOSED", closed)
	local rules = ns.Rules.Current(L)
	if rules.penalties and rules.penalties.autoApply then
		local written = self:ApplyAbsences({ night = closed.id })
		if written and #written > 0 then log("info", "ABSENCES_AUTO", #written) end
	end
	return closed
end

---------------------------------------------------------------------------------------------------------------------
-- The lineup

-- Changes one member's state by hand (RAID, BENCH or ABSENT). `name` is a pool main, or an alt (the main is used).
-- Returns the LINEUP_CHANGED event, or nil and a code ("NO_NIGHT_OPEN", "NOT_MEMBER", "NO_CHANGE", "BAD_STATE", ...).
function NightController:SetState(name, state)
	if not ns.Nights.STATES[state] then return nil, "BAD_STATE" end
	local L, season = writer(self)
	if not L then return nil, season end
	local night = ns.Nights.Current(L, season)
	if not night then return nil, "NO_NIGHT_OPEN" end
	local main = mainOf(ns.Roster.State(L, season), name)
	if not main then return nil, "NOT_MEMBER" end
	local event, why = ns.Nights.SetLineup(L, { author = self:Me(), ts = now(), season = season,
		[state:lower()] = { main } }, gate())
	if not event then return nil, why end
	emit("NIGHT_LINEUP_CHANGED", night, event)
	return event
end

function NightController:Bench(name) return self:SetState(name, "BENCH") end

---------------------------------------------------------------------------------------------------------------------
-- Benching oneself (M7-5b)

-- Writes a self-bench for `name` (a pool main or an alt) in the open night: the runner's side of a player's request.
-- Returns the LINEUP_CHANGED event, or nil and a code ("NO_NIGHT_OPEN", "NOT_RUNNER", "NOT_MEMBER", "NO_CHANGE", ...).
function NightController:RecordSelfBench(name)
	local L, season = writer(self)
	if not L then return nil, season end
	local night = ns.Nights.Current(L, season)
	if not night then return nil, "NO_NIGHT_OPEN" end
	if not self:IsRunner(night) then return nil, "NOT_RUNNER" end
	local main = mainOf(ns.Roster.State(L, season), name)
	if not main then return nil, "NOT_MEMBER" end
	local event, why = ns.Nights.SetLineup(L, { author = self:Me(), ts = now(), season = season, bench = { main },
		selfBench = true }, gate())
	if not event then return nil, why end
	log("info", "SELF_BENCH")
	emit("NIGHT_LINEUP_CHANGED", night, event)
	return event
end

-- The player benches themselves for tonight. On the client that runs the night it is written at once; elsewhere the
-- request goes on GUILD to that client. Returns the event (written here), or true and "SENT", or nil and a code
-- ("NOT_READY": no guild yet, or a Transport reason).
function NightController:SelfBench()
	local me = self:Me()
	if not me then return nil, "NOT_READY" end
	local L = self:Ledger()
	local night = L and self:Current()
	if night and self:IsRunner(night) then return self:RecordSelfBench(me) end
	if not ns.Transport then return nil, "NOT_READY" end
	local item, why = ns.Transport:Send("GUILD", { t = self.SELF_BENCH_MSG })
	if not item then return nil, why end
	return true, "SENT"
end

-- A message of the transport: a player's NBENCH on GUILD reaches the client that runs the night.
function NightController:OnMessage(msg, sender, dist)
	if type(msg) ~= "table" or msg.t ~= self.SELF_BENCH_MSG or dist ~= "GUILD" or type(sender) ~= "string" then return nil end
	local night = self:Current()
	if not night or not self:IsRunner(night) then return nil, "NOT_RUNNER" end
	return self:RecordSelfBench(sender)
end

---------------------------------------------------------------------------------------------------------------------
-- Absence penalties (M7-5b)

-- The night's date as the realm's day number YYYYMMDD (what the calendar reads), or nil.
local function dayOf(night)
	local y, m, d = tostring(night and night.date or ""):match("^(%d+)%-(%d+)%-(%d+)$")
	if not y then return nil end
	return tonumber(y) * 10000 + tonumber(m) * 100 + tonumber(d)
end

-- The calendar's sign-ups of a night (the event it is linked to, else the official raid event of its date), or nil when
-- the calendar has none or is not loaded.
function NightController:NightSignups(night)
	local day = dayOf(night)
	if not day or not ns.Calendar then return nil end
	local event
	for _, e in ipairs(ns.Calendar.RaidEvents(day)) do
		if night.eventID and e.eventID == night.eventID then event = e end
	end
	if night.eventID and not event then return nil end   -- linked to an event the calendar no longer shows
	event = event or ns.Calendar.FindRaidEvent(day)
	return event and ns.Calendar.Signups(event) or nil
end

-- The night the penalties are about: `id`, else the newest closed night of the open season. Returns L, season id, night
-- or nil and a code.
local function absenceNight(self, id)
	local L, season = writer(self)
	if not L then return nil, season end
	local night
	if id then
		night = ns.Nights.Get(L, id)
		if not night or night.season ~= season then return nil, "NIGHT_UNKNOWN" end
	else
		for _, n in ipairs(ns.Nights.List(L, season)) do
			if n.closed then night = n end
		end
		if not night then return nil, "NO_NIGHT_CLOSED" end
	end
	return L, season, night
end

-- The absence penalties proposed for a closed night (args.night = its id; default the newest closed one). Nothing is
-- written. Returns Absence.Propose's table plus `signupsKnown`, or nil and a code ("NOT_READY", "NO_SEASON", a permission
-- code, "NO_NIGHT_CLOSED", "NIGHT_UNKNOWN", "NIGHT_OPEN").
function NightController:AbsenceProposal(args)
	args = args or {}
	local L, season, night = absenceNight(self, args.night)
	if not L then return nil, season end
	self.signups = self.signups or {}
	local signups = self.signups[night.id]
	if signups == nil then
		signups = self:NightSignups(night)
		if signups then self.signups[night.id] = signups end
	end
	local rules = ns.Rules.Current(L)
	local p, code = ns.Absence.Propose(L, season, night.id, { signups = signups,
		amount = rules.penalties and rules.penalties.absence or 0 })
	if not p then return nil, code end
	p.signupsKnown = signups ~= nil
	return p
end

-- The officer's confirmation: writes the proposed penalties of a closed night (args.night, default the newest closed;
-- args.members = only these). Returns the events written and the refused entries, or nil and a code.
function NightController:ApplyAbsences(args)
	args = args or {}
	local p, code = self:AbsenceProposal(args)
	if not p then return nil, code end
	local entries = p.entries
	if args.members then
		local want = {}
		for _, name in ipairs(args.members) do want[name] = true end
		entries = {}
		for _, e in ipairs(p.entries) do if want[e.member] then entries[#entries + 1] = e end end
	end
	if #entries == 0 then return {}, {} end
	local L, season = self:Ledger(), p.night.season
	local written, refused = ns.Absence.Apply(L, { author = self:Me(), ts = now(), season = season, night = p.night.id,
		entries = entries }, gate())
	for _, r in ipairs(refused) do log("warn", "ABSENCE_REFUSED", ns.Log and ns.Log.Plain(r.code)) end
	if #written > 0 then emit("NIGHT_ABSENCES_APPLIED", p.night, written) end
	return written, refused
end

-- The master looter's decision: benches a whole list in one lineup change (names are pool mains or alts). Returns the
-- LINEUP_CHANGED event, or nil and a code ("NO_NIGHT_OPEN", "NOT_MEMBER", "NO_CHANGE", ...).
function NightController:ApplyBench(names)
	local L, season = writer(self)
	if not L then return nil, season end
	local night = ns.Nights.Current(L, season)
	if not night then return nil, "NO_NIGHT_OPEN" end
	local rs, bench = ns.Roster.State(L, season), {}
	for _, name in ipairs(type(names) == "table" and names or {}) do
		local main = mainOf(rs, name)
		if not main then return nil, "NOT_MEMBER" end
		bench[#bench + 1] = main
	end
	local event, why = ns.Nights.SetLineup(L, { author = self:Me(), ts = now(), season = season, bench = bench }, gate())
	if not event then return nil, why end
	emit("NIGHT_LINEUP_CHANGED", night, event)
	return event
end

-- Takes a member off the bench: back in the raid when they are in the group, absent otherwise.
function NightController:Unbench(name)
	local inGroup = ns.Group and ns.Group.Snapshot().members[ns.GuildRanks.FullName(name) or name]
	return self:SetState(name, inGroup and "RAID" or "ABSENT")
end

-- Reads the raid group (`snapshot` from Adapters/Group.lua, read now when nil) and writes the lineup changes into the open
-- night. Returns the LINEUP_CHANGED event, or nil and a code: "NO_NIGHT_OPEN", "NOT_RUNNER", "NOT_IN_RAID",
-- "NO_CHANGE", or a permission / ledger code.
function NightController:Sync(snapshot)
	local L, season = writer(self)
	if not L then return nil, season end
	local night = ns.Nights.Current(L, season)
	if not night then return nil, "NO_NIGHT_OPEN" end
	if not self:IsRunner(night) then return nil, "NOT_RUNNER" end
	snapshot = snapshot or ns.Group.Snapshot()
	if not snapshot.inRaid then return nil, "NOT_IN_RAID" end

	local rs = ns.Roster.State(L, season)
	local present, unknown = {}, 0
	for name in pairs(snapshot.members) do
		local main = mainOf(rs, name)
		if main then present[main] = true else unknown = unknown + 1 end
	end
	local before = self.group[night.id]
	local states = ns.Nights.Lineup(L, night.id)
	local draft = { author = self:Me(), ts = now(), season = season, raid = {}, absent = {} }
	for main in pairs(present) do
		local s = states[main]
		if s ~= "RAID" then
			-- a benched member who is in the group stays benched until they join again (before == nil: after a /reload or
			-- the first read, nobody has "just joined")
			if not (s == "BENCH" and (before == nil or before[main])) then draft.raid[#draft.raid + 1] = main end
		end
	end
	if snapshot.complete then
		for main, s in pairs(states) do
			if s == "RAID" and not present[main] then draft.absent[#draft.absent + 1] = main end
		end
		self.group[night.id] = present
	end
	local event, why = ns.Nights.SetLineup(L, draft, gate())
	if not event then return nil, why end
	log("debug", "LINEUP", #(event.payload.raid or {}), #(event.payload.bench or {}), #(event.payload.absent or {}), unknown)
	emit("NIGHT_LINEUP_CHANGED", night, event)
	return event
end

-- "GROUP_SCANNED": the lineup follows the group while a night is open and this client runs it.
function NightController:OnGroup(snapshot)
	local night = self:Current()
	if night and self:IsRunner(night) then self:Sync(snapshot) end
end

---------------------------------------------------------------------------------------------------------------------
-- Boss kills

-- "ENCOUNTER_ENDED": a kill (success) inside the night's instance is recorded, with the lineup read just before it.
-- Returns the ENCOUNTER_KILLED event, or nil and a code ("NOT_A_KILL", "NO_NIGHT_OPEN", "NOT_RUNNER",
-- "OTHER_INSTANCE", "ALREADY_KILLED", a permission or ledger code).
function NightController:OnEncounterEnd(info)
	if type(info) ~= "table" or not info.success then return nil, "NOT_A_KILL" end
	local L, season = writer(self)
	if not L then return nil, season end
	local night = ns.Nights.Current(L, season)
	if not night then return nil, "NO_NIGHT_OPEN" end
	if not self:IsRunner(night) then return nil, "NOT_RUNNER" end
	local inst = ns.Compat.Encounter.Instance()
	local instanceID = night.instanceID
	if inst and inst.instanceID then
		if inst.instanceID ~= night.instanceID then
			log("info", "OTHER_INSTANCE")
			return nil, "OTHER_INSTANCE"
		end
		instanceID = inst.instanceID
	end
	self:Sync()   -- the lineup of the kill: the group as it is now, before the kill is written
	local ts = now()
	local event, why = ns.Nights.Kill(L, { author = self:Me(), ts = ts, season = season, encounterID = info.encounterID,
		difficulty = info.difficultyID, size = info.groupSize, time = ts, date = today(), instanceID = instanceID }, gate())
	if not event then
		if why ~= "ALREADY_KILLED" then log("warn", "KILL_REFUSED", ns.Log and ns.Log.Plain(why)) end
		return nil, why
	end
	log("info", "KILL", info.encounterID)
	emit("NIGHT_ENCOUNTER_RECORDED", night, event)
	return event
end

---------------------------------------------------------------------------------------------------------------------
-- Planning the bench (a proposal, never a write)

-- The calendar's answers for a night: the event it is linked to, else the official raid event of its date. Returns the
-- sign-ups { [member] = "yes" | "maybe" | "no" } and the event, or nil when there is none or the client does not say.
local function calendarSignups(night, day)
	if not ns.Calendar then return nil end
	local event
	for _, e in ipairs(ns.Calendar.RaidEvents(day)) do
		if night and night.eventID and e.eventID == night.eventID then event = e end
	end
	event = event or ns.Calendar.FindRaidEvent(day)
	if not event then return nil end
	local signups = ns.Calendar.Signups(event)
	return signups, event
end

-- Who to bench, as Domain/Rotation.lua proposes: for the open night, or for a night about to start (args.instanceID gives
-- the size). args = { instanceID?, volunteers?, keep?, exclude?, useCalendar? (false: ignore the sign-ups),
-- useAvailability? }. Nothing is written: the master looter decides (ApplyBench / Open{bench}). Returns the proposal of
-- Rotation.Propose plus `event` (the calendar event the sign-ups came from) and `signups`, or nil and a code: "NOT_READY",
-- "NO_SEASON", a permission code, "NOT_IN_PACK" (no night open and no official instance given), "SIZE".
function NightController:ProposeBench(args)
	args = args or {}
	local L, s = self:Ledger(), self:Season()
	if not L then return nil, "NOT_READY" end
	if not s then return nil, "NO_SEASON" end
	local ok, why = self:Can("night.run")
	if not ok then return nil, why end
	local night = ns.Nights.Current(L, s.id)
	local opts = { night = night and night.id or nil, volunteers = args.volunteers, keep = args.keep,
		exclude = args.exclude, useAvailability = args.useAvailability }
	local day = ns.Compat.ServerDay()
	if not night then
		local size = ns.Season.InstanceSize(s, args.instanceID)
		if not size then return nil, "NOT_IN_PACK" end
		opts.size, opts.faction, opts.date = size, ns.Compat.Player.Faction(), today()
	end
	local signups, event
	if args.useCalendar ~= false then signups, event = calendarSignups(night, day) end
	opts.signups = signups
	local proposal, code = ns.Rotation.Propose(L, s.id, opts)
	if not proposal then return nil, code end
	proposal.event, proposal.signups = event, signups
	return proposal
end

---------------------------------------------------------------------------------------------------------------------
-- What the windows read

-- The open night's lineup lists { raid, bench, absent }, or nil without an open night.
function NightController:Lineup()
	local L, s = self:Ledger(), self:Season()
	local night = L and s and ns.Nights.Current(L, s.id)
	if not night then return nil end
	return ns.Nights.Lists(ns.Nights.Lineup(L, night.id)), night
end

-- The attendance per boss of the open season (or of one night, opts.night): only for who holds `view.attendance`
-- (officers by default, §6). Returns the Nights.Attendance table, or nil and a code ("NO_SEASON", "PENDING",
-- "RANK_TOO_LOW", ...).
function NightController:Attendance(opts)
	local L, s = self:Ledger(), self:Season()
	if not L then return nil, "NOT_READY" end
	if not s then return nil, "NO_SEASON" end
	local ok, why = self:Can("view.attendance")
	if not ok then return nil, why end
	return ns.Nights.Attendance(L, s.id, opts)
end

---------------------------------------------------------------------------------------------------------------------
-- Wiring

if ns.Bus then
	ns.Bus:On("GROUP_SCANNED", function(_, snapshot) NightController:OnGroup(snapshot) end, NightController)
	ns.Bus:On("ENCOUNTER_ENDED", function(_, info) NightController:OnEncounterEnd(info) end, NightController)
	ns.Bus:On("GUILD_KEY_CHANGED", function()
		NightController.ledger, NightController.group, NightController.signups = nil, {}, {}
	end, NightController)
	ns.Bus:On("NET_MESSAGE", function(_, msg, sender, dist)
		if type(msg) == "table" and msg.t == NightController.SELF_BENCH_MSG then
			local full = ns.GuildRanks and ns.GuildRanks.FullName(sender) or sender
			NightController:OnMessage(msg, full, dist)
		end
	end, NightController)
end
if ns.Codec then ns.Codec:RegisterType(NightController.SELF_BENCH_MSG, {}) end
NightController.group, NightController.signups = {}, {}

if ns.addon then
	ns.addon.NightController = NightController   -- also reachable from tests
	if ns.addon.AddDebugSection then
		ns.addon:AddDebugSection("Nights", function()
			local night = NightController:Current()
			return { ("Nights: %s"):format(night and ("open, " .. tostring(night.size) .. " players") or "none open") }   -- nolocale (debug output)
		end)
	end
end
