-- CouncilService: the loot council on this client (docs/ANALISI.md §3.6, §3.9; M5-5). Lua 5.1. The rules are in
-- Domain/Council.lua (membership, the ledger corrections, the audit) and Domain/SessionFSM.lua (the interventions on a
-- proposal and the vote); this module is the glue: it reads the rank (App/PermissionService.lua), the raid and the
-- rules, sends this member's vote (Net/Protocol.lua SVOTE) and writes the corrections through the permission gate.
--
--   CS:IsMember(name?, anywhere?)  is `name` (default: the player) on the council: the rules' explicit list, else the
--                                  permission council.member; and in the raid when council.requirePresent (`anywhere`
--                                  skips the raid: the session's read-only window only reaches the raid anyway)
--   CS:Vote(choice)                this member's vote on the open proposal (the master looter sees it before confirming)
--   CS:Void(ref, reason)           AWARD_VOIDED: cancels an award or a manual adjustment (compensation event)
--   CS:Adjust(member, delta, reason)  CREDITS_ADJUSTED: moves a member's credits by hand
--   CS:Audit(season?)              every intervention of the ledger (Council.Audit)
-- Both corrections need night.run while a night of the season is open (the master looter writes the council's
-- corrections, §3.6) and credits.adjust outside one (the GM in the preset): the gate of Ledger.Append decides, and every
-- other client checks the event again when it arrives. The interventions on a proposal (another winner, a non-roller
-- at full cost) and the corrections of category or cost before the roll are the master looter's commands
-- (SessionController:Command MODIFY / CORRECT_ITEM), each with its reason.
--
-- Until the council window (M5-8) the command `/fdcp council` is the interface: status, vote, the awards a void can
-- cancel, void, adjust, audit. Its words are locale keys.
-- Bus events: "COUNCIL_CORRECTED"(event) after a void or an adjustment was written.
-- Not verified in the real client: the vote message on RAID during a session (spike S4, like SRESP).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local CS = {}
ns.CouncilService, ns.modules.CouncilService = CS, CS

local type, ipairs, pairs, tostring, tonumber, concat = type, ipairs, pairs, tostring, tonumber, table.concat

CS.AUDIT_LINES = 10    -- entries printed by /fdcp council audit
CS.AWARD_LINES = 10    -- awards listed by /fdcp council awards

local function L() return ns.L end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function me() return ns.GuildRanks and ns.GuildRanks.Me() or nil end
local function SC() return ns.SessionController end
local function fullName(name) return ns.GuildRanks and ns.GuildRanks.FullName(name) or name end

---------------------------------------------------------------------------------------------------------------------
-- Membership

-- The rules' `council` section in force: the hosted session's own (frozen when it opened), else the ledger's.
function CS:Rules()
	local s = SC() and SC().session
	if s and s.state ~= "ENDED" and type(s.rules) == "table" and type(s.rules.council) == "table" then
		return s.rules.council
	end
	local rules = SC() and SC():Rules() or (ns.Rules and ns.Rules.DefaultConfig())
	return rules and rules.council or {}
end

-- Is `name` in the raid? The hosted session's raid on the master looter's client, else the last raid scan; nil when
-- it is not known.
function CS:IsPresent(name)
	local s = SC() and SC().session
	if s and s.state ~= "ENDED" and type(s.raid) == "table" and type(s.raid.present) == "table" then
		return s.raid.present[name] == true
	end
	local raid = ns.Protocol and ns.Protocol.Session.raid
	if type(raid) ~= "table" then return nil end
	if not raid.inRaid then return false end
	if name == raid.me or name == me() then return true end
	return type(raid.members) == "table" and raid.members[name] ~= nil
end

-- Is `name` (default: the player) on the council? Returns true, or false and a code (NOT_COUNCIL, NOT_PRESENT).
function CS:IsMember(name, anywhere)
	name = name or me()
	if not name then return false, "NOT_COUNCIL" end
	local ps = ns.PermissionService
	local rank = ps and ps:Can("council.member", name) == true or false
	local present = true
	if not anywhere then present = self:IsPresent(name) end
	return ns.Council.IsMember(self:Rules(), { name = name, rank = rank, present = present })
end

---------------------------------------------------------------------------------------------------------------------
-- The vote and the corrections

-- This member's vote for `choice` (a name, with or without the realm) on the open proposal. Returns ok, code.
function CS:Vote(choice)
	if type(choice) ~= "string" or choice == "" then return nil, "BAD_CHOICE" end
	return ns.Protocol.Session:Vote(fullName(choice))
end

local function ledger() return SC() and SC():Ledger() or nil end
local function gate() return ns.PermissionService and ns.PermissionService:Gate() or nil end
local function serverNow() return ns.Compat and ns.Compat.ServerTime() or 0 end

-- Voids the award (or manual adjustment) `ref` (an event id) with a reason code. Returns the event, or nil and a code.
function CS:Void(ref, reason)
	local Lg, author = ledger(), me()
	if not Lg or not author then return nil, "NOT_READY" end
	local e, code = ns.Council.Void(Lg, { author = author, ts = serverNow(), ref = ref, reason = reason }, gate())
	if not e then return nil, code end
	emit("COUNCIL_CORRECTED", e)
	return e
end

-- Moves `member`'s credits of the open season by `delta` with a reason code. Returns the event, or nil and a code.
function CS:Adjust(member, delta, reason)
	local Lg, author = ledger(), me()
	if not Lg or not author then return nil, "NOT_READY" end
	local season = ns.Season.Current(Lg)
	if not season then return nil, "NO_SEASON" end
	local e, code = ns.Council.Adjust(Lg, { author = author, ts = serverNow(), season = season.id,
		member = type(member) == "string" and fullName(member) or member, delta = delta, reason = reason }, gate())
	if not e then return nil, code end
	emit("COUNCIL_CORRECTED", e)
	return e
end

-- The interventions of a season (default: the open one), oldest first.
function CS:Audit(season)
	local Lg = ledger()
	if not Lg then return {} end
	if season == nil then
		local open = ns.Season.Current(Lg)
		season = open and open.id or nil
	end
	return ns.Council.Audit(Lg, season)
end

-- The awards of the open season a void may still cancel, newest first.
function CS:Voidable()
	local Lg = ledger()
	local season = Lg and ns.Season.Current(Lg)
	if not season then return {} end
	return ns.Council.Voidable(Lg, season.id)
end

---------------------------------------------------------------------------------------------------------------------
-- The command (words from the locale)

local function say(text) if ns.addon then ns.addon:Print(text) end end
local function short(name) return (tostring(name or "?"):gsub("%-.*$", "")) end
local function errorText(code)
	if ns.SessionBoard then return ns.SessionBoard.ErrorText(code) end
	return tostring(code)
end
local function itemText(id)
	local entry = ns.ItemCache and ns.ItemCache.Lookup(id)
	return entry and entry.link or ("item:" .. tostring(id))
end
local function num(n)
	if type(n) ~= "number" then return tostring(n) end
	if n == math.floor(n) then return ("%d"):format(n) end
	return ("%.2f"):format(n)
end

-- "MISTAKE, PENALTY, ..." as the player types them (lower case).
local function reasonList(order)
	local out = {}
	for i, code in ipairs(order) do out[i] = code:lower() end
	return concat(out, ", ")
end

-- locale-key: COUNCIL_STATE_MEMBER COUNCIL_STATE_NOT_MEMBER COUNCIL_STATE_LIST COUNCIL_STATE_RANK COUNCIL_USAGE
local function status()
	local ok = CS:IsMember()
	say(L()[ok and "COUNCIL_STATE_MEMBER" or "COUNCIL_STATE_NOT_MEMBER"])
	say(L()[ns.Council.HasList(CS:Rules()) and "COUNCIL_STATE_LIST" or "COUNCIL_STATE_RANK"])
	say(L()["COUNCIL_USAGE"])
end

-- locale-key: COUNCIL_AUDIT_HEADER COUNCIL_AUDIT_EMPTY COUNCIL_AUDIT_MODIFY COUNCIL_AUDIT_CORRECT COUNCIL_AUDIT_VOTE
-- locale-key: COUNCIL_AUDIT_VOID COUNCIL_AUDIT_ADJUST COUNCIL_AUDIT_VOIDED
function CS.AuditLine(entry)
	local R = ns.Reasons
	local why = entry.reason and R.Text("CORRECTION", entry.reason) or ""
	local text
	if entry.kind == "MODIFY" then
		text = L()["COUNCIL_AUDIT_MODIFY"]:format(itemText(entry.item), short(entry.member), short(entry.ruleWinner), why)
	elseif entry.kind == "CORRECT" then
		text = L()["COUNCIL_AUDIT_CORRECT"]:format(itemText(entry.item), why)
	elseif entry.kind == "VOTE" then
		text = L()["COUNCIL_AUDIT_VOTE"]:format(itemText(entry.item), short(entry.member))
	elseif entry.kind == "VOID" then
		text = L()["COUNCIL_AUDIT_VOID"]:format(entry.item and itemText(entry.item) or R.Text("EVENT", entry.refType or "?"),
			short(entry.member), why)
	else
		text = L()["COUNCIL_AUDIT_ADJUST"]:format(short(entry.member), num(entry.delta), why)
	end
	if entry.voided then text = text .. " " .. L()["COUNCIL_AUDIT_VOIDED"] end
	return short(entry.author) .. ": " .. text
end

-- locale-key: COUNCIL_VOTED COUNCIL_REFUSED COUNCIL_AWARDS_HEADER COUNCIL_AWARD_LINE COUNCIL_NO_AWARDS COUNCIL_VOIDED
-- locale-key: COUNCIL_ADJUSTED COUNCIL_VOID_REASONS COUNCIL_ADJUST_REASONS
function CS.Command(input)
	local rest = (input or ""):match("^%s*%S+%s*(.-)%s*$") or ""
	local sub, args = rest:match("^(%S*)%s*(.-)$")
	sub = (sub or ""):lower()
	if sub == "" then return status() end
	if sub == "vote" then
		if args == "" then return say(L()["COUNCIL_USAGE"]) end
		local ok, code = CS:Vote(args:match("^(%S+)"))
		if not ok then return say(L()["COUNCIL_REFUSED"]:format(errorText(code))) end
		return say(L()["COUNCIL_VOTED"]:format(short(fullName(args:match("^(%S+)")))))
	end
	if sub == "awards" then
		local list = CS:Voidable()
		if #list == 0 then return say(L()["COUNCIL_NO_AWARDS"]) end
		say(L()["COUNCIL_AWARDS_HEADER"])
		for i = 1, math.min(#list, CS.AWARD_LINES) do
			local a = list[i]
			say(L()["COUNCIL_AWARD_LINE"]:format(i, itemText(a.item), short(a.member), num(a.cost)))
		end
		return
	end
	if sub == "void" then
		local n, reason = args:match("^(%d+)%s*(%S*)$")
		local list = CS:Voidable()
		local a = n and list[tonumber(n)]
		if not a then return say(L()["COUNCIL_USAGE"]) end
		if reason == "" then return say(L()["COUNCIL_VOID_REASONS"]:format(reasonList(ns.Council.VOID_ORDER))) end
		local e, code = CS:Void(a.id, reason:upper())
		if not e then
			if code == "REASON_REQUIRED" then say(L()["COUNCIL_VOID_REASONS"]:format(reasonList(ns.Council.VOID_ORDER))) end
			return say(L()["COUNCIL_REFUSED"]:format(errorText(code)))
		end
		return say(L()["COUNCIL_VOIDED"]:format(itemText(a.item), short(a.member)))
	end
	if sub == "adjust" then
		local who, delta, reason = args:match("^(%S+)%s+(%S+)%s*(%S*)$")
		local d = tonumber(delta or "")
		if not who or not d then return say(L()["COUNCIL_USAGE"]) end
		if reason == "" then return say(L()["COUNCIL_ADJUST_REASONS"]:format(reasonList(ns.Council.ADJUST_ORDER))) end
		local e, code = CS:Adjust(who, d, reason:upper())
		if not e then
			if code == "REASON_REQUIRED" then say(L()["COUNCIL_ADJUST_REASONS"]:format(reasonList(ns.Council.ADJUST_ORDER))) end
			return say(L()["COUNCIL_REFUSED"]:format(errorText(code)))
		end
		return say(L()["COUNCIL_ADJUSTED"]:format(short(e.payload.member), num(d), ns.Reasons.Text("CORRECTION", e.payload.reason)))
	end
	if sub == "audit" then
		local list = CS:Audit()
		if #list == 0 then return say(L()["COUNCIL_AUDIT_EMPTY"]) end
		say(L()["COUNCIL_AUDIT_HEADER"]:format(#list))
		for i = math.max(1, #list - CS.AUDIT_LINES + 1), #list do say(CS.AuditLine(list[i])) end
		return
	end
	say(L()["COUNCIL_USAGE"])
end

if ns.addon and ns.addon.commands then
	local cmds = ns.addon.commands
	cmds[#cmds + 1] = { name = "council", helpKey = "HELP_COUNCIL", handler = function(_, input) CS.Command(input) end }
end

if ns.addon then ns.addon.CouncilService = CS end   -- also reachable from tests
