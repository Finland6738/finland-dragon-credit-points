-- LegendaryService: the legendary projects on this client (docs/ANALISI.md §3.7; M5-6). Lua 5.1. The rules are in
-- Domain/Legendary.lua (the projects folded from the ledger, who receives a chain piece) and Domain/SessionFSM.lua (a
-- piece that drops is proposed to its receiver, without a roll); this module is the glue: it reads the open season and
-- the rules and writes the projects through the permission gate (night.run, the officers in the preset).
--
--   LS:Projects()                       the projects of the open season (Legendary.Projects), oldest first
--   LS:Open(draft)                      LEGENDARY_PROJECT_OPENED: { name, item, pieces, builder?, queue? }
--   LS:Close(id, outcome)               LEGENDARY_PROJECT_CLOSED: COMPLETED or ABANDONED
-- LEGENDARY_PROJECT_PAID is the session's (SessionFSM CONFIRM of a chain piece), never written by hand.
--
-- The council window (UI/Windows/Council.lua, M5-8) drives these methods; the command `/fdcp legendary` stays as the
-- keyboard interface: the list, one project's pieces, open, complete, abandon. Item fields take item links (shift-click)
-- or item ids; its words are locale keys.
-- Bus events: "LEGENDARY_CHANGED"(event) after a project was opened or closed.
-- Not verified in the real client: the command's output in the chat and item links typed into it.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local LS = {}
ns.LegendaryService, ns.modules.LegendaryService = LS, LS

local type, ipairs, tostring, tonumber, concat = type, ipairs, tostring, tonumber, table.concat

local function L() return ns.L end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function me() return ns.GuildRanks and ns.GuildRanks.Me() or nil end
local function SC() return ns.SessionController end
local function fullName(name) return ns.GuildRanks and ns.GuildRanks.FullName(name) or name end
local function ledger() return SC() and SC():Ledger() or nil end
local function gate() return ns.PermissionService and ns.PermissionService:Gate() or nil end
local function serverNow() return ns.Compat and ns.Compat.ServerTime() or 0 end

-- The rules' `legendary` section in force (the guild's rules; the presets without a ledger).
function LS:Rules()
	local rules = SC() and SC():Rules() or (ns.Rules and ns.Rules.DefaultConfig())
	return rules and rules.legendary or { mode = "council", chainPieceCost = 2 }
end

-- The open season's id, or nil.
local function season()
	local Lg = ledger()
	local open = Lg and ns.Season.Current(Lg)
	return open and open.id or nil
end

function LS:Projects()
	local Lg, id = ledger(), season()
	if not Lg or not id then return {} end
	return ns.Legendary.Projects(Lg, id)
end

-- Opens a project in the open season. draft = { name, item, pieces = {ids}, builder?, queue? = {names} } (names with
-- or without the realm). Returns the event, or nil and a code.
function LS:Open(draft)
	local Lg, author, id = ledger(), me(), season()
	if not Lg or not author then return nil, "NOT_READY" end
	if not id then return nil, "NO_SEASON" end
	if type(draft) ~= "table" then return nil, "event" end
	local queue
	if type(draft.queue) == "table" then
		queue = {}
		for i, name in ipairs(draft.queue) do queue[i] = fullName(name) end
	end
	local e, code = ns.Legendary.OpenProject(Lg, { author = author, ts = serverNow(), season = id, name = draft.name,
		item = draft.item, pieces = draft.pieces, builder = draft.builder and fullName(draft.builder) or nil,
		queue = queue }, gate())
	if not e then return nil, code end
	emit("LEGENDARY_CHANGED", e)
	return e
end

-- Closes the project `ref` (its id) as COMPLETED or ABANDONED. Returns the event, or nil and a code.
function LS:Close(ref, outcome)
	local Lg, author = ledger(), me()
	if not Lg or not author then return nil, "NOT_READY" end
	local e, code = ns.Legendary.Close(Lg, { author = author, ts = serverNow(), ref = ref, outcome = outcome }, gate())
	if not e then return nil, code end
	emit("LEGENDARY_CHANGED", e)
	return e
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

-- The item ids of a field: the ids of its item links, or else its bare numbers.
function LS.ParseItems(field)
	local out = {}
	for id in tostring(field or ""):gmatch("item:(%d+)") do out[#out + 1] = tonumber(id) end
	if #out == 0 then
		for id in tostring(field or ""):gmatch("%d+") do out[#out + 1] = tonumber(id) end
	end
	return out
end

-- "open <name>; <final item>; <pieces>; <builder or ->[; <queue names>]" -> a draft, or nil.
function LS.ParseOpen(args)
	local fields = {}
	for f in (tostring(args or "") .. ";"):gmatch("([^;]*);") do fields[#fields + 1] = f:match("^%s*(.-)%s*$") end
	if #fields < 4 or fields[1] == "" then return nil end
	local final = LS.ParseItems(fields[2])
	if #final ~= 1 then return nil end
	local builder = fields[4]
	if builder == "" or builder == "-" then builder = nil end
	if builder and builder:find("%s") then return nil end
	local queue
	if fields[5] and fields[5] ~= "" then
		queue = {}
		for name in fields[5]:gmatch("%S+") do queue[#queue + 1] = name end
	end
	return { name = fields[1], item = final[1], pieces = LS.ParseItems(fields[3]), builder = builder, queue = queue }
end

-- locale-key: LEGENDARY_MODE_COUNCIL LEGENDARY_MODE_VOTE LEGENDARY_MODE_ROLL LEGENDARY_MODE_QUEUE LEGENDARY_MODE
local function modeLine()
	local rules = LS:Rules()
	local key = "LEGENDARY_MODE_" .. tostring(rules.mode):upper()
	return L()["LEGENDARY_MODE"]:format(L()[key], num(rules.chainPieceCost))
end

-- locale-key: LEGENDARY_STATE_OPEN LEGENDARY_NOBODY LEGENDARY_LINE
function LS.ProjectLine(i, project)
	local state = project.open and L()["LEGENDARY_STATE_OPEN"] or ns.Reasons.Text("OUTCOME", project.outcome)
	local builder = project.builder and short(project.builder) or L()["LEGENDARY_NOBODY"]
	return L()["LEGENDARY_LINE"]:format(i, project.name, itemText(project.item), builder, #project.paid,
		#project.pieces, state)
end

-- locale-key: LEGENDARY_PIECES LEGENDARY_QUEUE LEGENDARY_PAID_LINE LEGENDARY_NO_PAID
local function details(i, project)
	say(LS.ProjectLine(i, project))
	local pieces = {}
	for k, id in ipairs(project.pieces) do pieces[k] = itemText(id) end
	say(L()["LEGENDARY_PIECES"]:format(concat(pieces, " ")))
	if #project.queue > 0 then
		local names = {}
		for k, name in ipairs(project.queue) do names[k] = short(name) end
		say(L()["LEGENDARY_QUEUE"]:format(concat(names, ", ")))
	end
	if #project.paid == 0 then return say(L()["LEGENDARY_NO_PAID"]) end
	for _, entry in ipairs(project.paid) do
		say(L()["LEGENDARY_PAID_LINE"]:format(itemText(entry.item), short(entry.member), num(entry.cost)))
	end
end

-- locale-key: LEGENDARY_USAGE LEGENDARY_EMPTY LEGENDARY_HEADER LEGENDARY_OPENED LEGENDARY_CLOSED LEGENDARY_REFUSED
function LS.Command(input)
	local rest = (input or ""):match("^%s*%S+%s*(.-)%s*$") or ""
	local sub, args = rest:match("^(%S*)%s*(.-)$")
	sub = (sub or ""):lower()
	local list = LS:Projects()
	if sub == "" then
		say(modeLine())
		if #list == 0 then say(L()["LEGENDARY_EMPTY"]) return say(L()["LEGENDARY_USAGE"]) end
		say(L()["LEGENDARY_HEADER"])
		for i, project in ipairs(list) do say(LS.ProjectLine(i, project)) end
		return
	end
	if sub:match("^%d+$") then
		local project = list[tonumber(sub)]
		if not project then return say(L()["LEGENDARY_USAGE"]) end
		return details(tonumber(sub), project)
	end
	if sub == "open" then
		local draft = LS.ParseOpen(args)
		if not draft then return say(L()["LEGENDARY_USAGE"]) end
		local e, code = LS:Open(draft)
		if not e then return say(L()["LEGENDARY_REFUSED"]:format(errorText(code))) end
		local who = e.payload.builder and short(e.payload.builder) or L()["LEGENDARY_NOBODY"]
		return say(L()["LEGENDARY_OPENED"]:format(e.payload.name, itemText(e.payload.item), who))
	end
	if sub == "complete" or sub == "abandon" then
		local project = list[tonumber(args:match("^(%d+)") or "")]
		if not project then return say(L()["LEGENDARY_USAGE"]) end
		local e, code = LS:Close(project.id, sub == "complete" and "COMPLETED" or "ABANDONED")
		if not e then return say(L()["LEGENDARY_REFUSED"]:format(errorText(code))) end
		return say(L()["LEGENDARY_CLOSED"]:format(project.name, ns.Reasons.Text("OUTCOME", e.payload.outcome)))
	end
	say(L()["LEGENDARY_USAGE"])
end

if ns.addon and ns.addon.commands then
	local cmds = ns.addon.commands
	cmds[#cmds + 1] = { name = "legendary", helpKey = "HELP_LEGENDARY", handler = function(_, input) LS.Command(input) end }
end

if ns.addon then ns.addon.LegendaryService = LS end   -- also reachable from tests
