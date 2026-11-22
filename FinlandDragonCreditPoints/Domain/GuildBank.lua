-- GuildBank (M5-7): the items the guild bank received and the gold of their sale (docs/ANALISI.md §3.8). Pure Lua 5.1:
-- it never calls the game and never writes a sentence (codes and numbers only).
--
-- A BoE nobody asks for as main-spec follows `priority.boeFallback` (Domain/Priority.lua): `bank` (the preset) proposes
-- it to `priority.bankCharacter` at cost 0; the master looter's CONFIRM writes ITEM_AWARDED{target = "bank", member =
-- the bank character, cost = 0} (Domain/SessionFSM.lua) and the delivery of M4-7 gives it to that character. The
-- ledger never charges credits for a target other than "member" (Ledger.TARGETS), so a bank award moves nobody's
-- credits. The same happens to any item the master looter sends to the bank (REJECT then BANK, MODIFY to the bank).
--
-- An officer adds the gold of the sale later:
--   BANK_ITEM_SOLD{ref, copper}   ref = the ITEM_AWARDED (target bank) of the item; copper = the price, in copper
-- through the permission gate (night.run, the officers in the preset). The event takes the award's season; it never
-- moves credits. A second sale of the same item corrects the first: the last one in canonical order counts. A sale of
-- an award that was voided later stays in the ledger but is not counted (the item is not in the bank list any more).
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local GuildBank = {}
ns.GuildBank, ns.modules.GuildBank = GuildBank, GuildBank

local type, ipairs, tostring, tonumber, floor = type, ipairs, tostring, tonumber, math.floor

GuildBank.COPPER_PER_SILVER = 100
GuildBank.COPPER_PER_GOLD = 10000
GuildBank.MAX_COPPER = 99999999999   -- the game's gold cap (9,999,999g 99s 99c); a double holds it exactly

local function Ledger() return ns.Ledger end

local function isInt(n) return type(n) == "number" and n == floor(n) and n > -math.huge and n < math.huge end
local function isCopper(n) return isInt(n) and n >= 0 and n <= GuildBank.MAX_COPPER end

-- The payload check of BANK_ITEM_SOLD, registered in the ledger.
local function checkSold(p)
	if not Ledger().SplitId(p.ref) then return "ref" end
	if not isCopper(p.copper) then return "copper" end
end

if ns.Ledger and ns.Ledger.CHECKS then ns.Ledger.CHECKS.BANK_ITEM_SOLD = checkSold end

-- True when `e` is an ITEM_AWARDED to the guild bank that the computations read.
local function isBankAward(e)
	if type(e) ~= "table" or e.type ~= "ITEM_AWARDED" then return false end
	local p = Ledger().Readable(e) and Ledger().Payload(e)
	return p and p.target == "bank" or false
end

-- The voided ids of the ledger: { [ref] = true }.
local function voidedIds(L)
	local out = {}
	for _, e in ipairs(Ledger().Sorted(L, function(x) return x.type == "AWARD_VOIDED" end)) do
		local p = Ledger().Readable(e) and Ledger().Payload(e)
		if p then out[p.ref] = true end
	end
	return out
end

-- The items of the guild bank in a season, oldest first: { id (the ITEM_AWARDED id), item, member (the bank
-- character), author, ts, session?, encounter?, reasons, copper? (the price, nil while not sold), sale? (the id of the
-- BANK_ITEM_SOLD that counts), soldBy?, soldAt? }. Voided awards are left out.
function GuildBank.Items(L, season)
	local voided = voidedIds(L)
	local list, byId = {}, {}
	local events = Ledger().Sorted(L, function(x) return x.season == season end)
	for _, e in ipairs(events) do
		if isBankAward(e) and not voided[e.id] then
			local p = Ledger().Payload(e)
			local entry = { id = e.id, item = p.item, member = p.member, author = e.author, ts = e.ts,
				session = p.session, encounter = p.encounter, reasons = p.reasons or {} }
			list[#list + 1] = entry
			byId[e.id] = entry
		end
	end
	-- A second pass, so a sale whose clock ran behind the award's still finds it; the last sale in canonical order counts.
	for _, e in ipairs(events) do
		if e.type == "BANK_ITEM_SOLD" and Ledger().Readable(e) then
			local p = Ledger().Payload(e)
			local entry = byId[p.ref]
			if entry then entry.copper, entry.sale, entry.soldBy, entry.soldAt = p.copper, e.id, e.author, e.ts end
		end
	end
	return list
end

-- One item of the bank (by its ITEM_AWARDED id), or nil.
function GuildBank.Get(L, ref)
	local e = type(ref) == "string" and Ledger().Get(L, ref) or nil
	if not e or not isBankAward(e) then return nil end
	for _, entry in ipairs(GuildBank.Items(L, e.season)) do
		if entry.id == ref then return entry end
	end
	return nil
end

-- The totals of a season's bank: { items, sold, copper } (copper = the sum of the prices that count).
function GuildBank.Totals(L, season)
	local t = { items = 0, sold = 0, copper = 0 }
	for _, entry in ipairs(GuildBank.Items(L, season)) do
		t.items = t.items + 1
		if entry.copper then
			t.sold = t.sold + 1
			t.copper = t.copper + entry.copper
		end
	end
	return t
end

-- Records the sale of a bank item: BANK_ITEM_SOLD{ref, copper}. draft = { author, ts, ref (the ITEM_AWARDED id),
-- copper }. Returns the stored event, or nil and a code: NOT_BANK_ITEM (no award to the bank with that id),
-- BANK_ITEM_VOIDED (the award was voided), BAD_GOLD, or a Ledger.Append code.
function GuildBank.RecordSale(L, draft, opts)
	if type(draft) ~= "table" then return nil, "event" end
	if not isCopper(draft.copper) then return nil, "BAD_GOLD" end
	local e = type(draft.ref) == "string" and Ledger().Get(L, draft.ref) or nil
	if not e or not isBankAward(e) then return nil, "NOT_BANK_ITEM" end
	if Ledger().IsVoided(L, e.id) then return nil, "BANK_ITEM_VOIDED" end
	return Ledger().Append(L, { author = draft.author, ts = draft.ts, season = e.season, type = "BANK_ITEM_SOLD",
		payload = { ref = e.id, copper = draft.copper } }, opts)
end

-- Splits copper into gold, silver and copper.
function GuildBank.Split(copper)
	copper = isInt(copper) and copper or 0
	local g = floor(copper / GuildBank.COPPER_PER_GOLD)
	local rest = copper - g * GuildBank.COPPER_PER_GOLD
	local s = floor(rest / GuildBank.COPPER_PER_SILVER)
	return g, s, rest - s * GuildBank.COPPER_PER_SILVER
end

-- Reads a price typed by an officer, returns copper or nil. Accepted: a number of gold ("120", "12.5", "12,5") or
-- amounts with the letters of the coins in English or Italian: g/o (gold, oro), s/a (silver, argento), c/r (copper,
-- rame), in any order and with or without spaces ("12g 30s", "12o30a5r", "50s").
function GuildBank.ParseMoney(text)
	text = tostring(text or ""):lower():gsub("%s+", "")
	if text == "" then return nil end
	local whole = text:gsub(",", ".")
	if whole:match("^%d+%.?%d*$") then
		local gold = tonumber(whole)
		if not gold then return nil end
		local copper = floor(gold * GuildBank.COPPER_PER_GOLD + 0.5)
		return isCopper(copper) and copper or nil
	end
	local UNIT = { g = GuildBank.COPPER_PER_GOLD, o = GuildBank.COPPER_PER_GOLD, s = GuildBank.COPPER_PER_SILVER,
		a = GuildBank.COPPER_PER_SILVER, c = 1, r = 1 }
	local copper, seen, consumed = 0, {}, 0
	for amount, unit in text:gmatch("(%d+)(%a)") do
		local per = UNIT[unit]
		if not per then return nil end
		if seen[per] then return nil end
		seen[per] = true
		copper = copper + tonumber(amount) * per
		consumed = consumed + #amount + 1
	end
	if consumed ~= #text then return nil end
	return isCopper(copper) and copper or nil
end

if ns.addon then ns.addon.GuildBank = GuildBank end   -- also reachable from tests
