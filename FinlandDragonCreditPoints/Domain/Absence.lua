-- Absence: the penalty for a missed official night (docs/ANALISI.md §3.5, §6, owner rule of 2026-11-22, M7-5b). Pure Lua
-- 5.1: it never calls the game. Lowest credits wins, so a penalty **adds** credits.
--
-- A member of the season's pool (joined by the time the night opened, not inactive, of the night's faction) gets
-- `penalties.absence` credits (preset 1) for an official night when they:
--   NOT_SIGNED_UP  did not sign up for the night in the game's calendar (no answer, or "no") and did not play;
--   NO_SHOW        signed up ("yes" or "maybe") and did not play;
--   SELF_BENCH     sat on the bench at the end of the night because they benched **themselves** (LINEUP_CHANGED `self`);
--   ABSENT         did not play and the calendar's answers are not known (no event, or the client did not load it).
-- Nothing for a member who played (in the raid at any moment of the night) or who sat on the bench because an officer
-- benched them: the rotation never penalizes (§6). A sign-up made with an alt counts for its main.
--
-- The penalty is a CREDITS_ADJUSTED{member, delta, reason = "ABSENCE", night, cause}: the ledger keeps codes and
-- numbers, the audit shows it like any correction, and a void (AWARD_VOIDED, Domain/Council.lua) cancels it. The
-- permission gate takes it from who may run a night (night.run) because it names the night (Domain/Permissions.lua).
-- Absence.Propose computes the list, nothing is written: the officer confirms it (Absence.Apply) unless the rules say
-- `penalties.autoApply` (preset off). A member already penalized for the night (even when that penalty was voided
-- later: the officer took it back on purpose) is never proposed again.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Absence = {}
ns.Absence, ns.modules.Absence = Absence, Absence

local type, pairs, ipairs, floor, sort = type, pairs, ipairs, math.floor, table.sort

local function Ledger() return ns.Ledger end
local function Nights() return ns.Nights end

Absence.REASON = "ABSENCE"   -- the CREDITS_ADJUSTED reason (group CORRECTION of Domain/Reasons.lua)
Absence.CAUSES = { NOT_SIGNED_UP = true, NO_SHOW = true, SELF_BENCH = true, ABSENT = true }
Absence.MAX_AMOUNT = 100

-- The `penalties` section of the "Patto" preset. A fresh copy on every call.
function Absence.DefaultConfig()
	return { absence = 1, autoApply = false }
end

local function isNum(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end

-- Checks a `penalties` section. Returns true, or false and the field at fault.
function Absence.Validate(config)
	if type(config) ~= "table" then return false, "config" end
	if not isNum(config.absence) or config.absence < 0 or config.absence > Absence.MAX_AMOUNT then return false, "absence" end
	if type(config.autoApply) ~= "boolean" then return false, "autoApply" end
	return true
end

-- The members already penalized for a night: { [member] = event id } (voided ones included).
function Absence.Applied(L, nightId)
	local Lg = Ledger()
	local out = {}
	for _, e in ipairs(Lg.Sorted(L, function(e) return e.type == "CREDITS_ADJUSTED" end)) do
		local p = Lg.Readable(e) and Lg.Payload(e)
		if p and p.reason == Absence.REASON and p.night == nightId and not out[p.member] then out[p.member] = e.id end
	end
	return out
end

-- The answer of a member in the sign-ups: the main's own, else the best of its alts ("yes" before "maybe" before "no").
local RANK = { yes = 3, maybe = 2, no = 1 }
local function answerOf(signups, name, alts)
	local best = signups[name]
	for _, alt in ipairs(alts or {}) do
		local a = signups[alt]
		if a and (not best or (RANK[a] or 0) > (RANK[best] or 0)) then best = a end
	end
	return best
end

-- The penalties of night `nightId` of `season`. opts = { signups? = { [name] = "yes" | "maybe" | "no" } (nil: unknown),
-- amount? (default 1) }. Returns { night, amount, entries = { { member, cause, delta }, ... sorted by name },
-- applied = { [member] = id } }, or nil and a code: "NIGHT_UNKNOWN", "NIGHT_OPEN" (the night is not over yet).
-- An amount of 0 gives no entries (the penalty is off).
function Absence.Propose(L, season, nightId, opts)
	opts = opts or {}
	local N = Nights()
	local night = N.Get(L, nightId)
	if not night or night.season ~= season then return nil, "NIGHT_UNKNOWN" end
	if not night.closed then return nil, "NIGHT_OPEN" end
	local amount = opts.amount
	if amount == nil then amount = 1 end
	local result = { night = night, amount = amount, entries = {}, applied = Absence.Applied(L, nightId) }
	if not isNum(amount) or amount <= 0 then return result end
	local rs = ns.Roster.State(L, season)
	local rec = N.Attendance(L, season, { night = nightId }).nights[1]
	local played = rec and rec.played or {}
	local states, origins = N.Lineup(L, nightId)
	local signups = opts.signups
	for _, name in ipairs(N.PoolAt(L, rs, night, night.openedAt)) do
		if not played[name] and not result.applied[name] then
			local cause
			if states[name] == "BENCH" then
				if origins[name] == "SELF" then cause = "SELF_BENCH" end
			elseif type(signups) ~= "table" then
				cause = "ABSENT"
			else
				local a = answerOf(signups, name, rs.members[name].alts)
				cause = (a == "yes" or a == "maybe") and "NO_SHOW" or "NOT_SIGNED_UP"
			end
			if cause then result.entries[#result.entries + 1] = { member = name, cause = cause, delta = amount } end
		end
	end
	sort(result.entries, function(a, b) return a.member < b.member end)
	return result
end

-- Writes the penalties of a proposal: one CREDITS_ADJUSTED each, through Council.Adjust and the trust gate (`opts`).
-- draft = { author, ts, season, night, entries = { { member, cause, delta } } }. Returns the list of events written and
-- the list of { member, code } refused (an entry already applied is refused as "DUPLICATE").
function Absence.Apply(L, draft, opts)
	local written, refused = {}, {}
	if type(draft) ~= "table" or type(draft.entries) ~= "table" then return written, refused end
	local applied = Absence.Applied(L, draft.night)
	for _, entry in ipairs(draft.entries) do
		if applied[entry.member] then
			refused[#refused + 1] = { member = entry.member, code = "DUPLICATE" }
		elseif not Absence.CAUSES[entry.cause] then
			refused[#refused + 1] = { member = entry.member, code = "cause" }
		else
			local e, code = ns.Council.Adjust(L, { author = draft.author, ts = draft.ts, season = draft.season,
				member = entry.member, delta = entry.delta, reason = Absence.REASON, night = draft.night, cause = entry.cause }, opts)
			if e then
				written[#written + 1] = e
				applied[entry.member] = e.id
			else
				refused[#refused + 1] = { member = entry.member, code = code }
			end
		end
	end
	return written, refused
end

if ns.addon then ns.addon.Absence = Absence end   -- also reachable from tests
