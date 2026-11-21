-- Legendary (M5-6): the legendary projects of a season and who receives a chain piece (docs/ANALISI.md §3.7). Pure Lua
-- 5.1: it never calls the game and never writes a sentence (codes only; Domain/Reasons.lua gives the words).
--
-- A project is folded from three ledger events of the season, all through the permission gate of Ledger.Append
-- (night.run, Domain/Permissions.lua):
--   LEGENDARY_PROJECT_OPENED{name, item, pieces, builder?, queue?}   the project; its id is this event's id
--   LEGENDARY_PROJECT_PAID{ref, item, member, cost, award}           a chain piece awarded to `member` (`award` = the
--                                                                    ITEM_AWARDED that charged the credits)
--   LEGENDARY_PROJECT_CLOSED{ref, outcome, reason?}                  COMPLETED (the legendary is built) or ABANDONED
-- `name` is the name the officers give the project (data, like a season's label), `item` the final item, `pieces` the
-- item ids of the chain pieces, `builder` the character who builds it (the council's choice), `queue` the priority list
-- decided at the start of the season (mode `queue`). The credits are never in these events: the piece's ITEM_AWARDED
-- charges them like any award, PAID only marks the project's progress; a PAID whose award was voided does not count.
--
-- The rules' `legendary.mode` (Domain/Rules.lua) says who receives a chain piece that drops:
--   council (preset)  no roll: the project's builder, at legendary.chainPieceCost
--   vote              no roll: the council votes (the builder is proposed first), the majority wins, same cost
--   roll              a roll like any other item, the category decides the cost (the project is not consulted)
--   queue             no roll: the first of the project's queue who is present, same cost
-- Domain/SessionFSM.lua recognises a piece of an open project when the corpse is opened (Legendary.Pieces) and asks
-- Legendary.Recipient when the item's turn comes.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Legendary = {}
ns.Legendary, ns.modules.Legendary = Legendary, Legendary

local type, pairs, ipairs, tostring, floor = type, pairs, ipairs, tostring, math.floor
local huge = math.huge

Legendary.MODES = { council = true, vote = true, roll = true, queue = true }
Legendary.MODE_ORDER = { "council", "vote", "roll", "queue" }
Legendary.OUTCOMES = { COMPLETED = true, ABANDONED = true }
Legendary.MAX_NAME = 48      -- bytes of a project's name
Legendary.MAX_PIECES = 40    -- item ids of a chain
Legendary.MAX_QUEUE = 40     -- names of a queue

-- The reasons a proposal for a chain piece gives (group REASON) and the flags that need the master looter (group FLAG).
Legendary.REASON = { council = "LEGENDARY_BUILDER", vote = "LEGENDARY_BUILDER", queue = "LEGENDARY_QUEUE" }

local function Ledger() return ns.Ledger end

local function isName(s) return type(s) == "string" and s ~= "" and #s <= 64 and not s:find(":", 1, true) end
local function isInt(n) return type(n) == "number" and n == floor(n) and n > -huge and n < huge end
local function isNum(n) return type(n) == "number" and n == n and n > -huge and n < huge end
local function isCode(s) return type(s) == "string" and s:match("^[A-Z][A-Z0-9_]*$") ~= nil end
local function isId(n) return isInt(n) and n > 0 end

local function copy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = copy(x) end
	return c
end

-- A list (1..n, no holes) of unique values that pass `ok`, at most `max` long; `empty` allows {}. Returns true or false.
local function uniqueList(list, ok, max, empty)
	if type(list) ~= "table" then return false end
	local n, seen = 0, {}
	for k, v in pairs(list) do
		n = n + 1
		if not isInt(k) or k < 1 or not ok(v) or seen[v] then return false end
		seen[v] = true
	end
	if n ~= #list or n > max then return false end
	return empty or n > 0
end

---------------------------------------------------------------------------------------------------------------------
-- The payload checks (registered in Ledger.CHECKS, like the other modules' own types)

local function checkOpened(p)
	if type(p.name) ~= "string" or p.name == "" or #p.name > Legendary.MAX_NAME then return "name" end
	if not isId(p.item) then return "item" end
	if not uniqueList(p.pieces, isId, Legendary.MAX_PIECES, false) then return "pieces" end
	if p.builder ~= nil and not isName(p.builder) then return "builder" end
	if p.queue ~= nil and not uniqueList(p.queue, isName, Legendary.MAX_QUEUE, true) then return "queue" end
end

local function checkPaid(p)
	if not Ledger().SplitId(p.ref) then return "ref" end
	if not isId(p.item) then return "item" end
	if not isName(p.member) then return "member" end
	if not isNum(p.cost) or p.cost < 0 then return "cost" end
	if p.award ~= nil and not Ledger().SplitId(p.award) then return "award" end
end

local function checkClosed(p)
	if not Ledger().SplitId(p.ref) then return "ref" end
	if not Legendary.OUTCOMES[p.outcome] then return "outcome" end
	if p.reason ~= nil and not isCode(p.reason) then return "reason" end
end

if ns.Ledger then
	ns.Ledger.CHECKS.LEGENDARY_PROJECT_OPENED = checkOpened
	ns.Ledger.CHECKS.LEGENDARY_PROJECT_PAID = checkPaid
	ns.Ledger.CHECKS.LEGENDARY_PROJECT_CLOSED = checkClosed
end

---------------------------------------------------------------------------------------------------------------------
-- The projects, folded from the ledger

local LEGENDARY_TYPES = { LEGENDARY_PROJECT_OPENED = true, LEGENDARY_PROJECT_PAID = true, LEGENDARY_PROJECT_CLOSED = true }

-- The projects of a season, in canonical order (oldest first): a list of
--   { id, author, ts, season, name, item, pieces = {ids}, builder?, queue = {names}, open = bool,
--     paid = { { id, ts, item, member, cost, award } }, voided = { same, for the PAIDs whose award was voided },
--     outcome?, reason?, closedAt?, closedBy? }
-- The projects are read first, then their PAIDs and CLOSEDs in canonical order: a session stamps its events with its
-- own clock, so a PAID may sort before the OPENED of its project and still belongs to it. A PAID or a CLOSED for an
-- unknown project, or a PAID that sorts after the project's CLOSED, is ignored (the first CLOSED wins).
function Legendary.Projects(L, season)
	local Lg = Ledger()
	local list, byId, later = {}, {}, {}
	local function keep(e) return e.season == season and LEGENDARY_TYPES[e.type] == true end
	for _, e in ipairs(Lg.Sorted(L, keep)) do
		local p = Lg.Readable(e) and Lg.Payload(e)
		if p and e.type == "LEGENDARY_PROJECT_OPENED" then
			local project = {
				id = e.id, author = e.author, ts = e.ts, season = e.season, name = p.name, item = p.item,
				pieces = copy(p.pieces), builder = p.builder, queue = copy(p.queue or {}), open = true,
				paid = {}, voided = {},
			}
			list[#list + 1] = project
			byId[e.id] = project
		elseif p then
			later[#later + 1] = { e = e, p = p }
		end
	end
	for _, x in ipairs(later) do
		local e, p = x.e, x.p
		local project = byId[p.ref]
		if project and project.open then
			if e.type == "LEGENDARY_PROJECT_PAID" then
				local entry = { id = e.id, ts = e.ts, item = p.item, member = p.member, cost = p.cost, award = p.award }
				if p.award and Lg.IsVoided(L, p.award) then
					project.voided[#project.voided + 1] = entry
				else
					project.paid[#project.paid + 1] = entry
				end
			else
				project.open = false
				project.outcome, project.reason = p.outcome, p.reason
				project.closedAt, project.closedBy = e.ts, e.author
			end
		end
	end
	return list
end

-- One project by its id (the OPENED event's id), or nil.
function Legendary.Get(L, season, id)
	for _, project in ipairs(Legendary.Projects(L, season)) do
		if project.id == id then return project end
	end
	return nil
end

-- The open projects of a season.
function Legendary.Active(L, season)
	local out = {}
	for _, project in ipairs(Legendary.Projects(L, season)) do
		if project.open then out[#out + 1] = project end
	end
	return out
end

-- The chain pieces of the open projects: { [itemID] = { project, name, item, builder?, queue = {names} } }, what the
-- session freezes on an item that drops (Domain/SessionFSM.lua LOOT_OPENED). Opening refuses a piece another open
-- project already has, so an item id names one project; with merged ledgers the oldest project keeps it.
function Legendary.Pieces(L, season)
	local out = {}
	for _, project in ipairs(Legendary.Active(L, season)) do
		for _, id in ipairs(project.pieces) do
			if out[id] == nil then
				out[id] = { project = project.id, name = project.name, item = project.item, builder = project.builder,
					queue = copy(project.queue) }
			end
		end
	end
	return out
end

-- How many pieces each member paid in a project: { [member] = n }.
function Legendary.PaidBy(project)
	local out = {}
	for _, entry in ipairs(type(project) == "table" and project.paid or {}) do
		out[entry.member] = (out[entry.member] or 0) + 1
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Who receives a chain piece

local function isPresent(present, name)
	if type(present) ~= "table" then return true end   -- the raid is not known: the session does not guess
	return present[name] == true
end

-- The receiver of a chain piece under `mode`. piece = an entry of Legendary.Pieces (frozen on the session's item);
-- present = { [name] = true } (nil when the raid is not known). Returns winner (or nil), reason (a REASON code, nil in
-- mode roll) and flags (a list of FLAG codes, the cases the master looter must look at):
--   council, vote  the builder; NO_BUILDER (the project has none), BUILDER_ABSENT (not in the raid)
--   queue          the first of the queue who is present (the builder alone when the queue is empty); QUEUE_EMPTY
--   roll           nil: the item is rolled like any other
function Legendary.Recipient(piece, mode, present)
	if mode == "roll" or not Legendary.MODES[mode] or type(piece) ~= "table" then return nil, nil, {} end
	local reason = Legendary.REASON[mode]
	if mode == "queue" then
		local queue = type(piece.queue) == "table" and #piece.queue > 0 and piece.queue or { piece.builder }
		for _, name in ipairs(queue) do
			if isName(name) and isPresent(present, name) then return name, reason, {} end
		end
		return nil, reason, { "QUEUE_EMPTY" }
	end
	if not isName(piece.builder) then return nil, reason, { "NO_BUILDER" } end
	if not isPresent(present, piece.builder) then return nil, reason, { "BUILDER_ABSENT" } end
	return piece.builder, reason, {}
end

---------------------------------------------------------------------------------------------------------------------
-- Writing the events (the officers' commands and the session's confirm)

-- Checks that `name` is a character of the season's pool (a main or a linked alt).
local function inPool(L, season, name)
	return ns.Members == nil or ns.Members.Resolve(L, season, name) ~= nil
end

-- Opens a project. draft = { author, ts, season, name, item, pieces = {ids}, builder?, queue? = {names} }. Returns the
-- stored event (its id is the project's id), or nil and a code: SEASON_UNKNOWN, SEASON_CLOSED, BAD_NAME, BAD_ITEM,
-- BAD_PIECES, PIECE_TAKEN (an open project of the season already has one of the pieces), NOT_MEMBER (the builder or a
-- name of the queue is not in the season's pool), or a Ledger.Append code (the gate's RANK_TOO_LOW, PENDING ...).
function Legendary.OpenProject(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	local S = ns.Season
	if S then
		local season = S.Get(L, draft.season)
		if not season then return nil, "SEASON_UNKNOWN" end
		if season.closed then return nil, "SEASON_CLOSED" end
	end
	local payload = { name = draft.name, item = draft.item, pieces = copy(draft.pieces), builder = draft.builder,
		queue = (type(draft.queue) == "table" and #draft.queue > 0) and copy(draft.queue) or nil }
	local bad = checkOpened(payload)
	if bad == "name" then return nil, "BAD_NAME" end
	if bad == "item" then return nil, "BAD_ITEM" end
	if bad == "pieces" then return nil, "BAD_PIECES" end
	if bad then return nil, "NOT_MEMBER" end
	local taken = Legendary.Pieces(L, draft.season)
	for _, id in ipairs(payload.pieces) do
		if taken[id] then return nil, "PIECE_TAKEN" end
	end
	if payload.builder and not inPool(L, draft.season, payload.builder) then return nil, "NOT_MEMBER" end
	for _, name in ipairs(payload.queue or {}) do
		if not inPool(L, draft.season, name) then return nil, "NOT_MEMBER" end
	end
	return Ledger().Append(L, { author = draft.author, ts = draft.ts, season = draft.season,
		type = "LEGENDARY_PROJECT_OPENED", payload = payload }, opts)
end

local function openProject(L, ref)
	local e = type(ref) == "string" and Ledger().Get(L, ref) or nil
	if not e or e.type ~= "LEGENDARY_PROJECT_OPENED" then return nil, "PROJECT_UNKNOWN" end
	local project = Legendary.Get(L, e.season, ref)
	if not project then return nil, "PROJECT_UNKNOWN" end
	if not project.open then return nil, "PROJECT_CLOSED" end
	return project
end

-- Records a chain piece paid: LEGENDARY_PROJECT_PAID{ref, item, member, cost, award}. draft = { author, ts, ref (the
-- project), item (a piece of the project), member, cost, award? (the ITEM_AWARDED id) }. The event takes the project's
-- season. Returns the stored event, or nil and a code: PROJECT_UNKNOWN, PROJECT_CLOSED, NOT_A_PIECE, or a Ledger.Append
-- code.
function Legendary.Pay(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	local project, code = openProject(L, draft.ref)
	if not project then return nil, code end
	local isPiece = false
	for _, id in ipairs(project.pieces) do
		if id == draft.item then isPiece = true break end
	end
	if not isPiece then return nil, "NOT_A_PIECE" end
	return Ledger().Append(L, { author = draft.author, ts = draft.ts, season = project.season,
		type = "LEGENDARY_PROJECT_PAID",
		payload = { ref = project.id, item = draft.item, member = draft.member, cost = draft.cost, award = draft.award } }, opts)
end

-- Closes a project: LEGENDARY_PROJECT_CLOSED{ref, outcome, reason?}. draft = { author, ts, ref, outcome (COMPLETED or
-- ABANDONED), reason? (a code) }. Returns the stored event, or nil and a code: PROJECT_UNKNOWN, PROJECT_CLOSED,
-- BAD_OUTCOME, or a Ledger.Append code.
function Legendary.Close(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	if not Legendary.OUTCOMES[draft.outcome] then return nil, "BAD_OUTCOME" end
	local project, code = openProject(L, draft.ref)
	if not project then return nil, code end
	return Ledger().Append(L, { author = draft.author, ts = draft.ts, season = project.season,
		type = "LEGENDARY_PROJECT_CLOSED",
		payload = { ref = project.id, outcome = draft.outcome, reason = isCode(draft.reason) and draft.reason or nil } }, opts)
end

if ns.addon then ns.addon.Legendary = Legendary end   -- also reachable from tests
