-- PermissionService: Domain/Permissions.lua wired to the live guild ranks (docs/ANALISI.md §3.9, M3-1). Lua 5.1.
--
-- * The rank history (Permissions.RecordRank / RankAt) is kept here from the snapshots of Adapters/GuildRanks.lua and
--   saved per guild in FinlandDragonCreditPointsDB (Config:GuildData().ranks.history). Every member's rank change is
--   stored with the server time it was seen, a member who is gone from a complete roster is recorded as `false` (left
--   the guild). The history is "loaded" only once this session has read a roster: before that the gate answers PENDING.
-- * The gate (PermissionService:Gate()) is Permissions.Gate over that history: an event enters a ledger only if its
--   author had the required rank when it was written; CONFIG_CHANGED / PERMISSIONS_CHANGED only from rank index 0.
-- * The queue: PermissionService:Merge(L, events) merges through the gate; the events it cannot decide yet (PENDING,
--   the roster is still loading) wait in a queue and are merged again, so accepted or refused, as soon as a roster has
--   been read ("PERMISSIONS_QUEUE_DRAINED"{added, refused} on the bus). Local writes are not queued: they get PENDING
--   back and the windows keep their buttons off until PermissionService:IsReady().
-- * The Guild Master: the config power belongs to whoever has rank index 0 in the roster (CanConfigure). A GM change is
--   seen in the roster: the history makes the new GM's events valid from that moment on and keeps the old GM's ones
--   valid; "GUILD_LEADER_CHANGED"(old, new) goes on the bus and the two players are told in chat.
-- * Rank reorder / deletion / addition: the rank names are compared with the ones saved last time
--   (Permissions.RanksChanged); a change that is not a plain rename is kept as a pending review for the GM
--   ("GUILD_RANKS_CHANGED"(code, missing) on the bus, told in chat to the GM, again at every login until the GM
--   acknowledges it), with the permissions whose rank no longer exists (Permissions.CheckRanks).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local PermissionService = {}
ns.PermissionService, ns.modules.PermissionService = PermissionService, PermissionService

local type, pairs, ipairs, tostring, concat = type, pairs, ipairs, tostring, table.concat

PermissionService.MAX_QUEUE = 2000   -- events waiting for the roster; beyond it they are dropped (a later sync asks again)

local function P() return ns.Permissions end
local function log(level, code, ...) if ns.Log then ns.Log[level]("Permissions", code, ...) end end
local function plain(s) return ns.Log and ns.Log.Plain(s) or s end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function say(text) if ns.addon and ns.addon.Print then ns.addon:Print(text) end end

PermissionService.queue = {}    -- { { L = ledger, e = event }, ... } in arrival order
PermissionService.queued = {}   -- [ledger][id] = true

---------------------------------------------------------------------------------------------------------------------
-- The saved state of the current guild

-- (Re)binds to the current guild's saved data (in memory without a guild or with a read-only database). The history
-- is not "loaded" until a roster of this session is read; the queue belongs to the old guild's ledgers and is dropped.
function PermissionService:Bind()
	local data = ns.Config and ns.Config.GuildData and ns.Config:GuildData()
	local ranks = data and data.ranks
	if data and not ranks and not (ns.Config:IsReadOnly()) then
		ranks = {}
		data.ranks = ranks
	end
	ranks = ranks or {}
	ranks.history = ranks.history or P().NewHistory()
	ranks.history.members = ranks.history.members or {}
	ranks.history.loaded = false
	self.data, self.history = ranks, ranks.history
	self.queue, self.queued = {}, {}
	self.bound = true
	return ranks
end

function PermissionService:Data()
	if not self.bound then self:Bind() end
	return self.data
end

function PermissionService:History()
	if not self.bound then self:Bind() end
	return self.history
end

-- True once this session has read a roster: ranks can be answered.
function PermissionService:IsReady()
	return self:History().loaded == true
end

-- The ledger whose permission table is in force for this player's own checks (the ledger store binds it). nil = the
-- preset table.
function PermissionService:BindLedger(L) self.ledger = L end

local function tableOf(L)
	if L then return (P().Current(L)) end
	return P().DefaultTable()
end

---------------------------------------------------------------------------------------------------------------------
-- Ranks

-- The rank index of `name` at `ts` (default: now): nil while the roster is loading, false when not in the guild.
function PermissionService:RankAt(name, ts)
	return P().RankAt(self:History(), name, ts or ns.Compat.ServerTime())
end

-- The player's own rank index now (nil while loading).
function PermissionService:MyRank()
	local me = ns.GuildRanks and ns.GuildRanks.Me()
	if not me then return nil end
	local rank = self:RankAt(me)
	if rank == false then return nil end
	return rank
end

-- The gate for Ledger.Append / Ledger.Merge and the domain writers ({ accept = fn }). It reads the history at call
-- time, so a rebind (guild change) is followed.
function PermissionService:Gate()
	local service = self
	return P().Gate(function(author, ts) return P().RankAt(service:History(), author, ts) end)
end

-- May `name` (default: the player) use permission `p` now, under the table of ledger L (default: the bound ledger)?
-- Returns true, or false and a code: "PENDING" (roster loading), "NOT_IN_GUILD", "NOT_GM", "RANK_TOO_LOW".
function PermissionService:Can(p, name, L)
	name = name or (ns.GuildRanks and ns.GuildRanks.Me())
	local rank = name and self:RankAt(name)
	if rank == nil then return false, "PENDING" end
	if rank == false then return false, "NOT_IN_GUILD" end
	if P().Can(rank, p, tableOf(L or self.ledger)) then return true end
	return false, P().FIXED[p] and "NOT_GM" or "RANK_TOO_LOW"
end

-- Only the Guild Master changes the rules and the permission table: rank index 0 in the guild roster (§3.9).
function PermissionService:CanConfigure(name)
	return self:Can("config.permissions", name)
end

---------------------------------------------------------------------------------------------------------------------
-- The queue

local function enqueue(self, L, e)
	local ids = self.queued[L]
	if not ids then
		ids = {}
		self.queued[L] = ids
	end
	if ids[e.id] then return end
	if #self.queue >= self.MAX_QUEUE then
		log("warn", "QUEUE_FULL", self.MAX_QUEUE)
		return
	end
	ids[e.id] = true
	self.queue[#self.queue + 1] = { L = L, e = e }
end

function PermissionService:QueueSize() return #self.queue end

-- Merges events into ledger L through the gate (`gate`, default PermissionService:Gate(); the officer sync passes its own,
-- Net/Sync.lua). The events whose author's rank is not known yet wait in the queue (and are merged again with the
-- default gate). Returns the Ledger.Merge report (its `pending` are the queued events), or nil and "READ_ONLY".
function PermissionService:Merge(L, events, gate)
	local report, err = ns.Ledger.Merge(L, events, gate or self:Gate())
	if not report then return nil, err end
	for _, e in ipairs(report.pending) do enqueue(self, L, e) end
	if #report.pending > 0 then log("info", "QUEUED", #report.pending, #self.queue) end
	return report
end

-- Merges the queue again once the roster is known. Returns { added, refused = {{id, code}}, pending } (nil while the
-- roster is still loading).
function PermissionService:Drain()
	if not self:IsReady() or #self.queue == 0 then return nil end
	local queue, byLedger, order = self.queue, {}, {}
	self.queue, self.queued = {}, {}
	for _, item in ipairs(queue) do
		if not byLedger[item.L] then
			byLedger[item.L] = {}
			order[#order + 1] = item.L
		end
		local list = byLedger[item.L]
		list[#list + 1] = item.e
	end
	local result = { added = 0, refused = {}, pending = 0 }
	for _, L in ipairs(order) do
		local report = self:Merge(L, byLedger[L])
		if report then
			result.added = result.added + report.added
			for _, r in ipairs(report.refused) do result.refused[#result.refused + 1] = r end
			result.pending = result.pending + #report.pending
		end
	end
	log("info", "DRAINED", result.added, #result.refused, result.pending)
	emit("PERMISSIONS_QUEUE_DRAINED", result)
	return result
end

---------------------------------------------------------------------------------------------------------------------
-- Roster snapshots

local function copyList(list)
	local out = {}
	for i, v in ipairs(list) do out[i] = v end
	return out
end

-- The pending rank review for the GM: { code, ts, missing = {permissions} } or nil.
function PermissionService:RankReview() return self:Data().review end

-- The GM has checked the table after a rank change.
function PermissionService:AcknowledgeRanks()
	self:Data().review = nil
end

-- Tells the GM about a pending rank review (chat). Returns true when there was one and the player is the GM.
function PermissionService:ReportRanks()
	local review = self:Data().review
	if not review or self:MyRank() ~= P().GM then return false end
	say(ns.Reasons.Text("RANKS", review.code))
	if review.missing and #review.missing > 0 then
		say(ns.L["RANKS_PERMISSIONS_MISSING"]:format(concat(review.missing, ", ")))
	end
	return true
end

local function checkRanks(self, snapshot, now)
	local names = snapshot.ranks
	if type(names) ~= "table" or #names == 0 then return end
	local data = self.data
	local before = data.rankNames
	data.rankNames = copyList(names)
	if not before then return end
	local code = P().RanksChanged(before, names)
	if not code or code == "RENAMED" then return end
	local missing = P().CheckRanks(tableOf(self.ledger), #names)
	data.review = { code = code, ts = now, missing = missing }
	log("warn", "RANKS_CHANGED", plain(code), #missing)
	emit("GUILD_RANKS_CHANGED", code, missing)
	self:ReportRanks()
end

local function checkLeader(self, snapshot)
	local data, new = self.data, snapshot.gm
	if not new or data.leader == new then return end
	local old = data.leader
	data.leader = new
	if not old then return end   -- the first GM this addon sees
	log("info", "LEADER_CHANGED")
	emit("GUILD_LEADER_CHANGED", old, new)
	if new == snapshot.me then
		say(ns.L["RANKS_YOU_ARE_GM"])
	elseif old == snapshot.me then
		say(ns.L["RANKS_NO_LONGER_GM"])
	end
end

-- Takes a roster snapshot of Adapters/GuildRanks.lua: records the ranks, marks the history loaded, checks the GM and
-- the rank names, and merges the queue again. Returns true when this was the first roster of the session.
function PermissionService:OnRoster(snapshot)
	if type(snapshot) ~= "table" or type(snapshot.members) ~= "table" then return false end
	local h = self:History()
	local now = ns.Compat.ServerTime()
	local changed = false
	for name, rank in pairs(snapshot.members) do
		if P().RecordRank(h, name, rank, now) then changed = true end
	end
	if snapshot.complete then
		for name, list in pairs(h.members) do
			if snapshot.members[name] == nil and list[#list] and list[#list].rank ~= false then
				P().RecordRank(h, name, false, now)
				changed = true
			end
		end
	end
	local first = not h.loaded
	h.loaded = true
	checkLeader(self, snapshot)
	checkRanks(self, snapshot, now)
	if first then
		log("info", "ROSTER_READY", snapshot.myRank)
		emit("GUILD_RANKS_READY", snapshot.myRank)
		self:ReportRanks()   -- a review left from an earlier session
	end
	if changed and not first then emit("GUILD_RANK_HISTORY_CHANGED") end   -- the officer sync asks again what it refused
	self:Drain()
	return first
end

---------------------------------------------------------------------------------------------------------------------
-- Wiring

if ns.Bus then
	ns.Bus:On("GUILD_ROSTER_SCANNED", function(_, snapshot) PermissionService:OnRoster(snapshot) end, PermissionService)
	ns.Bus:On("GUILD_KEY_CHANGED", function() PermissionService:Bind() end, PermissionService)
end

if ns.addon then
	ns.addon.PermissionService = PermissionService   -- also reachable from tests
	if ns.addon.AddDebugSection then
		ns.addon:AddDebugSection("Permissions", function()
			local rank = PermissionService:MyRank()
			return { ("Permissions: roster %s, rank %s, queue %d"):format(   -- nolocale (debug output)
				PermissionService:IsReady() and "loaded" or "loading", rank and tostring(rank) or "-",   -- nolocale
				PermissionService:QueueSize()) }
		end)
	end
end
