-- CheatService: possible roll cheating on this client (docs/ANALISI.md §3.6, §5.2, owner rule of 2026-11-22, M7-5d). Lua
-- 5.1, no frames. Domain/Cheat.lua detects the four cases and writes the penalty; Domain/Flags.lua and the session put
-- the flags on the board (App/SessionBoard.lua). This module is the glue:
--
--   CheatService:Decorate(board)   marks each CHEAT flag (and each UPGRADE_IGNORED pass: Flags.CheatCause) of the board with `applied` (already penalized) and `inspect`
--                                  ("MATCH" / "MISMATCH": the master looter's inspection, Adapters/InspectCheck.lua,
--                                  asked here for the flagged players of the gear cases); board.cheat = the flag the
--                                  "Penalize" button acts on (the first one not penalized), with the amount
--   CheatService:CanPenalize()     the master looter, or a council member (CouncilService:IsMember); the permission
--                                  gate of the ledger decides in the end (night.run during a night)
--   CheatService:Penalize(target)  writes `penalties.cheat` credits for board.cheat (one CREDITS_ADJUSTED, reason CHEAT)
--   CheatService:Click(target)     the "Penalize +2" button: the first click arms it (the label asks to confirm, for
--                                  CONFIRM_SECONDS), the second writes the penalty; returns "ARMED", or Penalize's
--   CheatService:Label(target)     the button's label: "Penalize +2", or "Confirm +2 to Bryn?" while armed
--   CheatService:AutoApply(s)      with `penalties.autoApply` (preset off), the master looter's client writes the penalty
--                                  of every CHEAT flag once the proposal names them (SESSION_CHANGED)
-- Bus events: "COUNCIL_CORRECTED"(event) after a penalty was written.
-- Not verified in the real client: the inspection in a raid (range, timing).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local CheatService = {}
ns.CheatService, ns.modules.CheatService = CheatService, CheatService

local type, ipairs, pairs, tostring = type, ipairs, pairs, tostring

local function SC() return ns.SessionController end
local function me() return ns.GuildRanks and ns.GuildRanks.Me() or nil end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function gate() return ns.PermissionService and ns.PermissionService:Gate() or nil end
local function serverNow() return ns.Compat and ns.Compat.ServerTime() or 0 end
local function ledger() return SC() and SC():Ledger() or nil end

-- The causes an inspection can check (the gear worn now).
CheatService.INSPECTED = { GEAR_SWAP = true, UNEQUIPPED = true, OFFSPEC_HIDE = true }

function CheatService:Amount()
	local rules = SC() and SC():Rules() or nil
	return ns.Cheat.Amount(rules and rules.penalties)
end

function CheatService:CanPenalize()
	if SC() and SC():Current() and not SC().readOnly then return true end
	return ns.CouncilService ~= nil and ns.CouncilService:IsMember(nil, true) == true
end

local function slotsOf(gear)
	local out = {}
	for _, e in ipairs(type(gear) == "table" and type(gear.g) == "table" and gear.g or {}) do out[#out + 1] = e.s end
	return out
end

function CheatService:Decorate(board)
	if type(board) ~= "table" or type(board.flags) ~= "table" then return board end
	local L = ledger()
	local applied = L and ns.Cheat.Applied(L) or {}
	local itemID = board.selectedItem and board.selectedItem.itemID or nil
	local IC = ns.InspectCheck
	board.cheat = nil
	for _, f in ipairs(board.flags) do
		local cause = ns.Flags.CheatCause(f)
		if cause then
			f.applied = applied[ns.Cheat.Key(f.player, cause, itemID, board.sid)] ~= nil or nil
			local gear = type(board.gear) == "table" and board.gear[f.player] or nil
			if IC and board.host and self.INSPECTED[cause] and gear then
				local seen = IC:Seen(f.player)
				if seen then f.inspect = ns.Cheat.CrossCheck(gear, seen) else IC:Request(f.player, slotsOf(gear)) end
			end
			if not f.applied and not board.cheat then
				board.cheat = { member = f.player, cause = cause, item = itemID, sid = board.sid, amount = self:Amount() }
			end
		end
	end
	return board
end

-- Writes the penalty of `target` ({ member, cause, item, sid, amount? }). Returns the event, or nil and a code.
function CheatService:Penalize(target)
	if type(target) ~= "table" then return nil, "NO_PROPOSAL" end
	local Lg, author = ledger(), me()
	if not Lg or not author then return nil, "NOT_READY" end
	local season = ns.Season.Current(Lg)
	if not season then return nil, "NO_SEASON" end
	local e, code = ns.Cheat.Apply(Lg, { author = author, ts = serverNow(), season = season.id, member = target.member,
		cause = target.cause, item = target.item, sid = target.sid, amount = target.amount or self:Amount() }, gate())
	if not e then return nil, code end
	emit("COUNCIL_CORRECTED", e)
	return e
end

CheatService.CONFIRM_SECONDS = 5
CheatService.armed = nil   -- { key, at }

local function keyOf(t) return ns.Cheat.Key(t.member, t.cause, t.item, t.sid) end
local function clock() return ns.Compat and ns.Compat.Now() or 0 end

function CheatService:IsArmed(target)
	local a = self.armed
	return type(target) == "table" and a ~= nil and a.key == keyOf(target) and clock() - a.at <= self.CONFIRM_SECONDS
end

-- locale-key: ML_PENALIZE ML_PENALIZE_CONFIRM
function CheatService:Label(target)
	local L = ns.L
	local amount = type(target) == "table" and (target.amount or self:Amount()) or self:Amount()
	if self:IsArmed(target) then
		return L["ML_PENALIZE_CONFIRM"]:format(tostring(amount), (tostring(target.member):gsub("%-.*$", "")))
	end
	return L["ML_PENALIZE"]:format(tostring(amount))
end

function CheatService:Click(target)
	if type(target) ~= "table" then return nil, "NO_PROPOSAL" end
	if not self:IsArmed(target) then
		self.armed = { key = keyOf(target), at = clock() }
		return "ARMED"
	end
	self.armed = nil
	return self:Penalize(target)
end

-- The automatic penalty (rules `penalties.autoApply`): on the master looter's client, for every flag the proposals carry.
function CheatService:AutoApply(s)
	if type(s) ~= "table" or type(s.items) ~= "table" then return {} end
	local rules = SC() and SC():Rules() or nil
	local p = rules and rules.penalties
	if not (type(p) == "table" and p.autoApply == true) or ns.Cheat.Amount(p) <= 0 then return {} end
	local written = {}
	local L = ledger()
	if not L then return written end
	local applied = ns.Cheat.Applied(L)
	for _, item in ipairs(s.items) do
		for _, f in ipairs(type(item.flagged) == "table" and item.flagged or {}) do
			local cause = ns.Flags.CheatCause(f)
			if cause and not applied[ns.Cheat.Key(f.player, cause, item.itemID, s.id)] then
				local e = self:Penalize({ member = f.player, cause = cause, item = item.itemID, sid = s.id })
				if e then
					written[#written + 1] = e
					applied[ns.Cheat.Key(f.player, cause, item.itemID, s.id)] = e.id
				end
			end
		end
	end
	return written
end

if ns.addon then ns.addon.CheatService = CheatService end   -- also reachable from tests
if ns.Bus then
	ns.Bus:On("SESSION_CHANGED", function(_, s)
		if SC() and SC().session == s and not SC().readOnly then CheatService:AutoApply(s) end
	end, CheatService)
end
