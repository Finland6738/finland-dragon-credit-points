-- ReadinessCheck: the master looter's readiness table (docs/ANALISI.md §4.2, ADR 0010, M8-2). Lua 5.1. The messages are
-- Net/Readiness.lua's (RDYQ / RDY), the verdicts Domain/Readiness.lua's, the requirements the `readiness` section of the
-- rules in force (App/SettingsController.lua); the raid is App/AddonCheck.lua's (GROUP_SCANNED) and so is "who has no
-- addon". M8-3 draws this table in a tab and turns its rows into the /raid summary and the whispers of the notify button.
--
-- Who asks: the runner of the open night (its officer or master looter) or anyone whose guild rank holds `raid.addonCheck`
-- (the same people who run the addon check). A request asks the whole raid; the previous answers are dropped, because
-- readiness is transient: it is never saved, never written to the ledger and lost at /reload (ADR 0010).
--
-- A row per raid member (Rows): { name, status, result, reason? }
--   status  OK | WARN | MISSING | UNKNOWN (Domain/Readiness.lua Evaluate, against the rules in force)
--   result  the verdict: enchants and items missing, by slot and by category
--   reason  why a row is UNKNOWN: NOT_ASKED (no check yet, or joined after it), WAITING (asked less than TIMEOUT seconds
--           ago: an answer can wait for the end of combat), NO_ADDON (the addon check found none, or an incompatible
--           one), OFFLINE, NO_ANSWER (an older addon without the check, or no answer)
-- The role of a raider is the role of the specialization its client reports (Data/Specs.lua); without one, no
-- requirement with roles concerns it.
--
-- Bus event: "READINESS_CHANGED"(summary) whenever a row may have changed.
-- Not verified in the real client: everything of the check (docs/checklists/M8.md).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local ReadinessCheck = {}
ns.ReadinessCheck, ns.modules.ReadinessCheck = ReadinessCheck, ReadinessCheck

local type, pairs, next, sort = type, pairs, next, table.sort

ReadinessCheck.TIMEOUT = 15   -- seconds after the request before a silent raider is NO_ANSWER

local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function now() return ns.Compat.Now() end
local function Net() return ns.ReadinessNet end

function ReadinessCheck:Reset()
	self.request = nil   -- { q, at, cats, asked = { [name] = true } }
	self.replies = {}    -- [name] = { snap, at }
	self.lastAt = nil    -- when this client last asked
	self.stale = 0       -- answers to an older request, or from outside the raid
end
ReadinessCheck:Reset()

local function raid()
	local AC = ns.AddonCheck
	return AC and AC.raid or { inRaid = false, members = {} }
end

-- The `readiness` section of the rules in force (the defaults without a ledger).
function ReadinessCheck:Rules()
	local SC = ns.SettingsController
	local rules = SC and SC:Rules()
	return rules and rules.readiness or ns.Readiness.DefaultConfig()
end

-- May the player ask? The runner of the open night, or `raid.addonCheck`: true, or false and a permission code.
function ReadinessCheck:CanManage()
	local AC = ns.AddonCheck
	if AC and AC:IsChecker() then return true end
	if ns.PermissionService then return ns.PermissionService:Can("raid.addonCheck") end
	return true
end

-- The seconds before the player may ask again (0 when now).
function ReadinessCheck:Wait()
	if not self.lastAt then return 0 end
	local left = self.lastAt + Net().REQUEST_GAP - now()
	return left > 0 and left or 0
end

---------------------------------------------------------------------------------------------------------------------
-- Asking

-- Asks the whole raid. Returns q, or nil plus a code: "NOT_IN_RAID", "DISABLED" (the rules turn the check off),
-- "TOO_SOON" (plus the seconds left), the permission codes ("RANK_TOO_LOW", "PENDING", "NOT_IN_GUILD"), or the
-- transport's reason.
function ReadinessCheck:Request()
	if not raid().inRaid then return nil, "NOT_IN_RAID" end
	local ok, code = self:CanManage()
	if not ok then return nil, code end
	local rules = self:Rules()
	if rules.enabled == false then return nil, "DISABLED" end
	local wait = self:Wait()
	if wait > 0 then return nil, "TOO_SOON", wait end
	local cats = ns.Readiness.Categories(rules)
	local asked = {}
	for name in pairs(raid().members) do asked[name] = true end
	local q = math.floor(ns.Compat.ServerTime())
	local before = self.request
	self.replies = {}
	self.request = { q = q, at = now(), cats = cats, asked = asked }
	local sent, why = Net():Ask(cats, q)   -- the asker's own snapshot comes back at once (READINESS_REPLY)
	if not sent then
		self.request = before
		return nil, why
	end
	self.lastAt = now()
	ns.Compat.After(self.TIMEOUT + 0.05, function() emit("READINESS_CHANGED", self:Summary()) end)
	emit("READINESS_CHANGED", self:Summary())
	return q
end

-- READINESS_REPLY: a raider's snapshot for request q.
function ReadinessCheck:OnReply(snap, from, q)
	if type(snap) ~= "table" or type(from) ~= "string" then return end
	local req = self.request
	if not req or req.q ~= q or not raid().members[from] then
		self.stale = self.stale + 1
		return
	end
	self.replies[from] = { snap = snap, at = now() }
	emit("READINESS_CHANGED", self:Summary())
end

---------------------------------------------------------------------------------------------------------------------
-- The table

local function roleOf(snap)
	local spec = snap and snap.spec and ns.Specs and ns.Specs.Get(snap.spec)
	return spec and spec.role or nil
end

-- Why a raider without an answer is unknown.
function ReadinessCheck:ReasonOf(name, row)
	local req = self.request
	if row and row.online == false then return "OFFLINE" end
	if not req or not req.asked[name] then return "NOT_ASKED" end
	local AC = ns.AddonCheck
	local state = AC and AC:StateOf(name)
	if state == "MISSING" or state == "INCOMPATIBLE" then return "NO_ADDON" end
	if now() < req.at + self.TIMEOUT then return "WAITING" end
	return "NO_ANSWER"
end

-- The verdict of one raid member: { name, status, result, reason? }.
function ReadinessCheck:Row(name)
	local members = raid().members
	local row = members[name]
	local reply = self.replies[name]
	local snap = reply and reply.snap
	local who = { class = (snap and snap.class) or (row and row.classFile), role = roleOf(snap) }
	local result = ns.Readiness.Evaluate(snap, self:Rules(), who)
	local out = { name = name, status = result.status, result = result }
	if not snap then out.reason = self:ReasonOf(name, row) end
	return out
end

-- One row per raid member, sorted by name.
function ReadinessCheck:Rows()
	local rows = {}
	for name in pairs(raid().members) do rows[#rows + 1] = self:Row(name) end
	sort(rows, function(a, b) return a.name < b.name end)
	return rows
end

-- { total, OK, WARN, MISSING, UNKNOWN, answered, asked, q? }.
function ReadinessCheck:Summary()
	local rows = self:Rows()
	local s = ns.Readiness.Summary(rows)
	s.answered, s.asked = 0, 0
	for name in pairs(self.replies) do if raid().members[name] then s.answered = s.answered + 1 end end
	if self.request then
		for _ in pairs(self.request.asked) do s.asked = s.asked + 1 end
		s.q = self.request.q
	end
	return s
end

-- GROUP_SCANNED: leaving the raid drops the check.
function ReadinessCheck:OnGroup(snapshot)
	if type(snapshot) ~= "table" then return end
	if not snapshot.inRaid and (self.request or next(self.replies)) then
		self:Reset()
		emit("READINESS_CHANGED", self:Summary())
	end
end

if ns.Bus then
	ns.Bus:On("READINESS_REPLY", function(_, snap, from, q) ReadinessCheck:OnReply(snap, from, q) end, ReadinessCheck)
	ns.Bus:On("GROUP_SCANNED", function(_, snapshot) ReadinessCheck:OnGroup(snapshot) end, ReadinessCheck)
end
if ns.addon then
	ns.addon.ReadinessCheck = ReadinessCheck   -- also reachable from tests
	if ns.addon.AddDebugSection then
		ns.addon:AddDebugSection("ReadinessCheck", function()
			local s = ReadinessCheck:Summary()
			return { ("Readiness table: %d/%d answered, ok %d, warn %d, missing %d, unknown %d, stale %d"):format(   -- nolocale (debug output)
				s.answered, s.asked, s.OK, s.WARN, s.MISSING, s.UNKNOWN, ReadinessCheck.stale) }   -- nolocale
		end)
	end
end
