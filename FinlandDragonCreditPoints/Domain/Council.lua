-- Council (M5-5): who sits on the loot council and the corrections it writes outside a proposal (docs/ANALISI.md §3.6,
-- §3.9). Pure Lua 5.1: it never calls the game and never writes a sentence (codes only; Domain/Reasons.lua group
-- CORRECTION gives the words).
--
-- Membership (§3.6 "Chi è"): the rules' `council.members`, a list of characters, when it is not empty; otherwise the
-- rank, through the permission council.member (Domain/Permissions.lua). With `council.requirePresent` (preset) the
-- member must also be in the raid. The caller (App/CouncilService.lua) reads the rank and the raid and passes them in.
--
-- The interventions (§3.6 "Cosa può fare"), always with a reason code that ends in the audit:
--   correct the category or the cost before the roll opens  SessionFSM CORRECT_ITEM (refused once the roll is open)
--   "spreco palese": another candidate                       SessionFSM MODIFY{winner, reason = OBVIOUS_WASTE}
--   "passa per fare il furbo": a non-roller at full cost     SessionFSM MODIFY{winner, reason = PASSED_TO_GAME}
--   the council's vote                                       SessionFSM VOTE / CLOSE_VOTE (reason COUNCIL_VOTE)
--   void an award                                            Council.Void: AWARD_VOIDED{ref, reason} (a compensation
--                                                            event: the award stays in the ledger, marked voided)
--   adjust a member's credits by hand                        Council.Adjust: CREDITS_ADJUSTED{member, delta, reason}
-- The two ledger corrections pass the permission gate of Ledger.Append (opts): night.run while a night of the season
-- is open (the master looter writes the council's corrections), credits.adjust outside one (the GM in the preset).
--
-- Council.Audit reads every intervention back from the ledger, in canonical order: the awards that departed from the
-- rule (with the rule's winner and cost, the reason and the votes), the corrections of category or cost written with an
-- award, the votes, the voids and the manual adjustments.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Council = {}
ns.Council, ns.modules.Council = Council, Council

local type, pairs, ipairs, tostring, floor = type, pairs, ipairs, tostring, math.floor
local huge = math.huge

Council.MAX_MEMBERS = 40     -- names in the explicit list
Council.MAX_DELTA = 1000     -- the largest manual adjustment, either way

-- The reasons a void may give (group CORRECTION of Domain/Reasons.lua).
Council.VOID_REASONS = {
	MISTAKE = true, DUPLICATE_AWARD = true, OBVIOUS_WASTE = true, PASSED_TO_GAME = true, COUNCIL_VOTE = true,
	LEGENDARY = true, OTHER = true,
}
-- The reasons a manual adjustment may give.
Council.ADJUST_REASONS = { MISTAKE = true, PENALTY = true, BONUS = true, COUNCIL_VOTE = true, OTHER = true }
-- The same reasons in the order a dialog or the help lists them.
Council.VOID_ORDER = { "MISTAKE", "DUPLICATE_AWARD", "OBVIOUS_WASTE", "PASSED_TO_GAME", "COUNCIL_VOTE", "LEGENDARY", "OTHER" }
Council.ADJUST_ORDER = { "MISTAKE", "PENALTY", "BONUS", "COUNCIL_VOTE", "OTHER" }

-- The kinds of an audit entry.
Council.AUDIT_KINDS = { MODIFY = true, CORRECT = true, VOTE = true, VOID = true, ADJUST = true }

local function Ledger() return ns.Ledger end

local function isName(s) return type(s) == "string" and s ~= "" and #s <= 64 and not s:find(":", 1, true) end
local function isNum(n) return type(n) == "number" and n == n and n > -huge and n < huge end

local function copy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = copy(x) end
	return c
end

---------------------------------------------------------------------------------------------------------------------
-- The rules' keys this module owns

-- The preset of the `council` keys of this module: no explicit list (the rank decides). A fresh copy on every call.
function Council.DefaultConfig()
	return { members = {} }
end

-- Checks the keys of the `council` section this module owns: a list of problem codes, empty when valid.
function Council.ValidateConfig(c)
	if type(c) ~= "table" then return { "council" } end
	local m = c.members
	if type(m) ~= "table" or #m > Council.MAX_MEMBERS then return { "council.members" } end
	local seen, n = {}, 0
	for k, name in pairs(m) do
		n = n + 1
		if type(k) ~= "number" or not isName(name) or seen[name] then return { "council.members" } end
		seen[name] = true
	end
	if n ~= #m then return { "council.members" } end
	return {}
end

---------------------------------------------------------------------------------------------------------------------
-- Membership

-- Is a character on the council? council = the rules' `council` section; who = { name, rank (true when the character
-- holds the permission council.member), present (true in the raid, false out of it, nil when not known) }. Returns true,
-- or false and a code: NOT_COUNCIL (not on the list, or no rank) or NOT_PRESENT (council.requirePresent and not in the
-- raid, or the raid is not known).
function Council.IsMember(council, who)
	council = type(council) == "table" and council or {}
	if type(who) ~= "table" or not isName(who.name) then return false, "NOT_COUNCIL" end
	local list = type(council.members) == "table" and council.members or {}
	local listed
	if #list > 0 then
		listed = false
		for _, name in ipairs(list) do
			if name == who.name then listed = true break end
		end
	else
		listed = who.rank == true
	end
	if not listed then return false, "NOT_COUNCIL" end
	if council.requirePresent ~= false and who.present ~= true then return false, "NOT_PRESENT" end
	return true
end

-- True when the rules name the council by an explicit list.
function Council.HasList(council)
	return type(council) == "table" and type(council.members) == "table" and #council.members > 0
end

---------------------------------------------------------------------------------------------------------------------
-- The corrections written in the ledger

-- Voids an award or a manual adjustment: AWARD_VOIDED{ref, reason, member?, item?}. draft = { author, ts, ref (the
-- event id), reason }. The void takes the season of the event it cancels. opts = the trust gate of Ledger.Append.
-- Returns the stored event, or nil and a code: REASON_REQUIRED (no reason, or one a void cannot give), REF_MISSING,
-- REF_NOT_VOIDABLE, ALREADY_VOIDED, or a Ledger.Append code (the gate's RANK_TOO_LOW, PENDING ...).
function Council.Void(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	if not Council.VOID_REASONS[draft.reason] then return nil, "REASON_REQUIRED" end
	local Lg = Ledger()
	local ref = type(draft.ref) == "string" and Lg.Get(L, draft.ref) or nil
	if not ref then return nil, "REF_MISSING" end
	if not Lg.VOIDABLE[ref.type] then return nil, "REF_NOT_VOIDABLE" end
	if Lg.IsVoided(L, ref.id) then return nil, "ALREADY_VOIDED" end
	local p = Lg.Readable(ref) and Lg.Payload(ref) or {}
	local payload = { ref = ref.id, reason = draft.reason }
	if isName(p.member) then payload.member = p.member end
	if type(p.item) == "number" then payload.item = p.item end
	return Lg.Append(L, { author = draft.author, ts = draft.ts, season = ref.season, type = "AWARD_VOIDED",
		payload = payload }, opts)
end

-- Moves a member's credits by hand: CREDITS_ADJUSTED{member, delta, reason}. draft = { author, ts, season, member,
-- delta (a number, not 0, at most MAX_DELTA either way: positive raises the credits, so it weighs like a cost),
-- reason }. The member must be in the season's pool (a main). Returns the stored event, or nil and a code:
-- REASON_REQUIRED, NOT_MEMBER, BAD_DELTA, or a Ledger.Append code.
function Council.Adjust(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	if not Council.ADJUST_REASONS[draft.reason] then return nil, "REASON_REQUIRED" end
	local d = draft.delta
	if not isNum(d) or d == 0 or d > Council.MAX_DELTA or d < -Council.MAX_DELTA then return nil, "BAD_DELTA" end
	if not isName(draft.member) or not ns.Members.Get(L, draft.season, draft.member) then return nil, "NOT_MEMBER" end
	return Ledger().Append(L, { author = draft.author, ts = draft.ts, season = draft.season, type = "CREDITS_ADJUSTED",
		payload = { member = draft.member, delta = d, reason = draft.reason } }, opts)
end

---------------------------------------------------------------------------------------------------------------------
-- The audit

local function base(e, kind)
	return { kind = kind, id = e.id, author = e.author, ts = e.ts, season = e.season }
end

-- Every intervention of the ledger, in canonical order (season = only that season's; nil = all): a list of
--   { kind = "MODIFY", id, author, ts, season, member, item, cost, reason, ruleWinner, ruleCost, flags, votes, voided }
--   { kind = "CORRECT", id, author, ts, season, item, category, cost, reason, by }   (the award's corrections, one each)
--   { kind = "VOTE", id, author, ts, season, member, item, votes, voided }            (an award decided with votes that
--                                                                                       kept the rule's winner)
--   { kind = "VOID", id, author, ts, season, ref, refType, member, item, reason }
--   { kind = "ADJUST", id, author, ts, season, member, delta, reason, voided }
-- `id` is the event the entry comes from (an award's corrections share its id); `voided` = a void cancels it.
function Council.Audit(L, season)
	local Lg = Ledger()
	local out = {}
	local function keep(e)
		return (season == nil or e.season == season)
			and (e.type == "ITEM_AWARDED" or e.type == "AWARD_VOIDED" or e.type == "CREDITS_ADJUSTED")
	end
	for _, e in ipairs(Lg.Sorted(L, keep)) do
		local p = Lg.Readable(e) and Lg.Payload(e)
		if p then
			if e.type == "ITEM_AWARDED" then
				for _, c in ipairs(type(p.corrections) == "table" and p.corrections or {}) do
					if type(c) == "table" then
						local entry = base(e, "CORRECT")
						entry.item, entry.category, entry.cost, entry.reason, entry.by = p.item, c.category, c.cost, c.reason, c.by
						out[#out + 1] = entry
					end
				end
				local votes = type(p.votes) == "table" and next(p.votes) ~= nil and copy(p.votes) or nil
				if p.intervention then
					local entry = base(e, "MODIFY")
					entry.member, entry.item, entry.cost, entry.reason = p.member, p.item, p.cost, p.mlReason
					entry.ruleWinner, entry.ruleCost, entry.flags, entry.votes = p.ruleWinner, p.ruleCost, copy(p.flags), votes
					entry.target = p.target
					entry.voided = Lg.IsVoided(L, e.id) or nil
					out[#out + 1] = entry
				elseif votes then
					local entry = base(e, "VOTE")
					entry.member, entry.item, entry.votes = p.member, p.item, votes
					entry.voided = Lg.IsVoided(L, e.id) or nil
					out[#out + 1] = entry
				end
			elseif e.type == "AWARD_VOIDED" then
				local entry = base(e, "VOID")
				local ref = Lg.Get(L, p.ref)
				entry.ref, entry.refType, entry.reason = p.ref, ref and ref.type or nil, p.reason
				entry.member, entry.item = p.member, p.item
				out[#out + 1] = entry
			else
				local entry = base(e, "ADJUST")
				entry.member, entry.delta, entry.reason = p.member, p.delta, p.reason
				entry.voided = Lg.IsVoided(L, e.id) or nil
				out[#out + 1] = entry
			end
		end
	end
	return out
end

-- The awards of a season that a void may still cancel, newest first: { { id, member, item, cost, ts, target } }.
function Council.Voidable(L, season)
	local Lg = Ledger()
	local out = {}
	for _, e in ipairs(Lg.Sorted(L, function(e) return e.season == season and e.type == "ITEM_AWARDED" end)) do
		local p = Lg.Readable(e) and Lg.Payload(e)
		if p and not Lg.IsVoided(L, e.id) then
			table.insert(out, 1, { id = e.id, member = p.member, item = p.item, cost = p.cost, ts = e.ts, target = p.target })
		end
	end
	return out
end

if ns.addon then ns.addon.Council = Council end   -- also reachable from tests
