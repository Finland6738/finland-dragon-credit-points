-- AddonCheck: who in the raid runs a compatible addon (docs/ANALISI.md §4.1, M3-5). Lua 5.1. The messages are in
-- Net/Protocol.lua (HELLOQ / HELLO on RAID); the raid comes from Adapters/Group.lua (GROUP_SCANNED).
--
-- Every client keeps the same table, because every HELLOQ and HELLO travels on RAID: the checker asks, everybody hears
-- the answers. The checker is the runner of the open night (the officer who opened it or its master looter): it asks
-- the whole raid when the night opens, or when it joins a raid during its night, and only the newcomers at every later
-- raid join (a member who comes back online counts as a newcomer). Anyone with `raid.addonCheck`, and the runner, can ask
-- again by hand (Request). Every client also says HELLO by itself when it enters a raid and after a login or /reload in
-- one, so a player who installs the addon and reloads comes back without being asked.
--
-- The state of a raid member:
--   ACTIVE        answered, compatible, same or newer version (the player's own client is always ACTIVE)
--   OUTDATED      answered, compatible, older version: rolls normally and is asked to update
--   INCOMPATIBLE  answered with a session protocol this client does not understand: cannot roll, like a missing addon
--   MISSING       asked, and no answer within TIMEOUT seconds: "addon not active" (not installed and disabled look the
--                 same, §4.1)
--   WAITING       offline, not asked yet, or asked less than TIMEOUT seconds ago: checked again by itself
-- An answer counts only when it is not older than the last question that named the member: a stale answer from before
-- a /reload that disabled the addon does not keep anyone ACTIVE.
--
-- The rule for M4 (§4.1): the candidates of an item are only the raid members with a compatible addon (ACTIVE or
-- OUTDATED). Candidates() returns them as { [name] = true }, RaidInput() as { present, addon } for SessionFSM SET_RAID.
--
-- Bus event: "ADDON_CHECK_CHANGED"(summary) whenever a state may have changed.
-- Not verified in the real client (spike S4): RAID delivery of addon messages, the sender's name format.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local AddonCheck = {}
ns.AddonCheck, ns.modules.AddonCheck = AddonCheck, AddonCheck

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local sort = table.sort

AddonCheck.TIMEOUT = 15   -- seconds an asked member has to answer before "addon not active"

AddonCheck.STATES = { "ACTIVE", "OUTDATED", "INCOMPATIBLE", "MISSING", "WAITING" }
local CAN_ROLL = { ACTIVE = true, OUTDATED = true }

local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function now() return ns.Compat.Now() end
local function me() return ns.GuildRanks and ns.GuildRanks.Me() end
local function P() return ns.Protocol end

local EMPTY_RAID = { inRaid = false, members = {}, size = 0, read = 0, complete = false }

function AddonCheck:Reset()
	self.raid = EMPTY_RAID
	self.replies = {}      -- [name] = { av, pv, pm, at }
	self.asked = {}        -- [name] = time of the last question that reached them (named, or to the whole raid)
	self.timerAt = nil
end
AddonCheck:Reset()

---------------------------------------------------------------------------------------------------------------------
-- States

-- The state of a raid member `name` (see the top of the file).
function AddonCheck:StateOf(name)
	if name == me() then return "ACTIVE" end
	local row = self.raid.members[name]
	if row and row.online == false then return "WAITING" end
	local reply, asked = self.replies[name], self.asked[name]
	if reply and (asked == nil or reply.at >= asked) then return P().Classify(reply) end
	if asked == nil or now() < asked + self.TIMEOUT then return "WAITING" end
	return "MISSING"
end

-- The words of a state in the player's language.
-- locale-key: ADDON_STATE_ACTIVE ADDON_STATE_OUTDATED ADDON_STATE_INCOMPATIBLE ADDON_STATE_MISSING ADDON_STATE_WAITING
function AddonCheck.StateLabel(state)
	local L = ns.L
	return L and L["ADDON_STATE_" .. tostring(state)] or tostring(state)
end

-- One row per raid member, sorted by name: { name, state, label, av? }.
function AddonCheck:Rows()
	local rows = {}
	for name in pairs(self.raid.members) do
		local reply = self.replies[name]
		local av = name == me() and P().AddonVersion() or (reply and reply.av) or nil
		local state = self:StateOf(name)
		rows[#rows + 1] = { name = name, state = state, label = self.StateLabel(state), av = av }
	end
	sort(rows, function(a, b) return a.name < b.name end)
	return rows
end

-- { total, with, ACTIVE, OUTDATED, INCOMPATIBLE, MISSING, WAITING, inRaid, text } ("37/40 with the addon": `with`
-- counts the members who can roll).
function AddonCheck:Summary()
	local s = { total = 0, with = 0, inRaid = self.raid.inRaid == true }
	for _, state in ipairs(self.STATES) do s[state] = 0 end
	for name in pairs(self.raid.members) do
		local state = self:StateOf(name)
		s.total = s.total + 1
		s[state] = s[state] + 1
		if CAN_ROLL[state] then s.with = s.with + 1 end
	end
	local L = ns.L
	s.text = L and L["ADDON_CHECK_SUMMARY"]:format(s.with, s.total) or (s.with .. "/" .. s.total)
	return s
end

-- May raid member `name` roll from the addon? (ACTIVE or OUTDATED)
function AddonCheck:CanRoll(name)
	return self.raid.members[name] ~= nil and CAN_ROLL[self:StateOf(name)] == true
end

-- The rule for M4: { [name] = true } for every raid member with a compatible addon.
function AddonCheck:Candidates()
	local out = {}
	for name in pairs(self.raid.members) do
		if CAN_ROLL[self:StateOf(name)] then out[name] = true end
	end
	return out
end

-- The input of SessionFSM SET_RAID: { present = { [name] = true } for the raid, addon = Candidates() }.
function AddonCheck:RaidInput()
	local present = {}
	for name in pairs(self.raid.members) do present[name] = true end
	return { present = present, addon = self:Candidates() }
end

---------------------------------------------------------------------------------------------------------------------
-- Changes

local function changed(self)
	emit("ADDON_CHECK_CHANGED", self:Summary())
end

-- A timer that refreshes the states once the newest question times out.
local function armTimer(self, at)
	if self.timerAt and self.timerAt >= at then return end
	self.timerAt = at
	ns.Compat.After(at - now() + 0.05, function()
		if self.timerAt == at then self.timerAt = nil end
		changed(self)
	end)
end

-- Records a question that left at `t`: `names` (list) or everybody (nil): the members in the raid at that moment, so a
-- player who joins later is not counted as asked.
function AddonCheck:NoteAsked(names, t)
	t = t or now()
	if names == nil then
		for name in pairs(self.raid.members) do self.asked[name] = t end
	else
		for _, name in ipairs(names) do self.asked[name] = t end
	end
	armTimer(self, t + self.TIMEOUT)
	changed(self)
end

function AddonCheck:OnHello(info, sender)
	if type(info) ~= "table" or type(sender) ~= "string" then return end
	self.replies[sender] = { av = info.av, pv = info.pv, pm = info.pm, at = now() }
	changed(self)
end

---------------------------------------------------------------------------------------------------------------------
-- Asking

-- The runner of the open night (NightController), who asks by itself.
function AddonCheck:IsChecker()
	local NC = ns.NightController
	if not NC then return false end
	local ok, night = pcall(NC.Current, NC)
	return ok and night ~= nil and NC:IsRunner(night) or false
end

-- Sends a question (`names` or everybody); the time is noted when it really leaves (a question to everybody that is
-- still waiting is replaced by the new one, Protocol:Ask uses a transport key for it).
local function ask(self, names)
	if names and #names > P().MAX_NAMES then names = nil end
	return P():Ask(names, function() self:NoteAsked(names) end)
end

-- May the player see the panel and ask by hand: the runner of the open night, or `raid.addonCheck`. true, or false and a
-- permission code ("RANK_TOO_LOW", "PENDING", "NOT_IN_GUILD").
function AddonCheck:CanManage()
	if self:IsChecker() then return true end
	if ns.PermissionService then return ns.PermissionService:Can("raid.addonCheck") end
	return true
end

-- Asks the whole raid by hand. Returns true, or nil plus a code: "NOT_IN_RAID", the permission codes
-- ("RANK_TOO_LOW", "PENDING", "NOT_IN_GUILD"), or the transport's reason.
function AddonCheck:Request()
	if not self.raid.inRaid then return nil, "NOT_IN_RAID" end
	local ok, code = self:CanManage()
	if not ok then return nil, code end
	local item, why = ask(self, nil)
	if not item then return nil, why end
	return true
end

-- GROUP_SCANNED: the new raid. Says HELLO when the player enters a raid; the checker asks the newcomers.
function AddonCheck:OnGroup(snapshot)
	if type(snapshot) ~= "table" then return end
	local before = self.raid
	if not snapshot.inRaid then
		if before.inRaid then self:Reset() changed(self) end
		return
	end
	self.raid = snapshot
	local mine = me()
	if not before.inRaid then
		if self:IsChecker() then ask(self, nil) else P():Announce() end   -- a question carries the asker's HELLO
	elseif self:IsChecker() then
		local newcomers = {}
		for name, row in pairs(snapshot.members) do
			local old = before.members[name]
			if name ~= mine and row.online ~= false and (old == nil or old.online == false) then
				newcomers[#newcomers + 1] = name
			end
		end
		if #newcomers > 0 then
			sort(newcomers)
			ask(self, newcomers)
		end
	end
	changed(self)
end

-- NIGHT_OPENED: the runner asks the whole raid.
function AddonCheck:OnNightOpened(night)
	local NC = ns.NightController
	if self.raid.inRaid and NC and NC:IsRunner(night) then ask(self, nil) end
end

---------------------------------------------------------------------------------------------------------------------
-- /fdcp debug

function AddonCheck:DebugLines()
	local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })
	local s, st = self:Summary(), P() and P().stats or {}
	return {
		L["DEBUG_ADDON_CHECK"]:format(s.text, s.ACTIVE, s.OUTDATED, s.INCOMPATIBLE, s.MISSING, s.WAITING,
			tostring(P().AddonVersion()), P().VERSION, P().MIN, st.asked or 0, st.hellos or 0, st.bad or 0),
	}
end

if ns.Bus then
	ns.Bus:On("GROUP_SCANNED", function(_, snapshot) AddonCheck:OnGroup(snapshot) end, AddonCheck)
	ns.Bus:On("ADDON_HELLO", function(_, info, sender) AddonCheck:OnHello(info, sender) end, AddonCheck)
	ns.Bus:On("ADDON_HELLO_ASKED", function(_, names) AddonCheck:NoteAsked(names) end, AddonCheck)
	ns.Bus:On("NIGHT_OPENED", function(_, night) AddonCheck:OnNightOpened(night) end, AddonCheck)
end
if ns.addon then
	ns.addon.AddonCheck = AddonCheck   -- also reachable from tests
	if ns.addon.AddDebugSection then
		ns.addon:AddDebugSection("AddonCheck", function() return AddonCheck:DebugLines() end)
	end
end
