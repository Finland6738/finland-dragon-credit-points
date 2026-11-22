-- BankService: the guild bank on this client (docs/ANALISI.md §3.8; M5-7). Lua 5.1. The rules are in Domain/Priority.lua
-- (a BoE nobody needs as main-spec follows priority.boeFallback), Domain/SessionFSM.lua (the award to the bank character
-- at cost 0) and Domain/GuildBank.lua (the bank items and the gold of their sale); this module is the glue: it reads the
-- season and the rules and writes BANK_ITEM_SOLD through the permission gate (night.run, the officers in the preset).
--
--   BS:Season()               the open season's id, or else the newest season (a sale often comes after the season)
--   BS:Items()                the bank items of that season (GuildBank.Items), oldest first
--   BS:Totals()               { items, sold, copper }
--   BS:RecordSale(ref, copper) BANK_ITEM_SOLD{ref, copper}
--
-- The command `/fdcp bank` is the interface (the council window of M5-8 does not cover the bank): the fallback in force and the bank
-- character, the bank items with their price, and `sold <n> <price>`. Its words are locale keys.
-- Bus events: "BANK_CHANGED"(event) after a sale was recorded.
-- Not verified in the real client: the command's output in the chat.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local BS = {}
ns.BankService, ns.modules.BankService = BS, BS

local type, ipairs, tostring, tonumber = type, ipairs, tostring, tonumber

local function L() return ns.L end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function me() return ns.GuildRanks and ns.GuildRanks.Me() or nil end
local function SC() return ns.SessionController end
local function ledger() return SC() and SC():Ledger() or nil end
local function gate() return ns.PermissionService and ns.PermissionService:Gate() or nil end
local function serverNow() return ns.Compat and ns.Compat.ServerTime() or 0 end

-- The rules' `priority` section in force (the guild's rules; the presets without a ledger).
function BS:Rules()
	local rules = SC() and SC():Rules() or (ns.Rules and ns.Rules.DefaultConfig())
	return rules and rules.priority or ns.Priority.DefaultConfig()
end

function BS:Season()
	local Lg = ledger()
	if not Lg then return nil end
	local open = ns.Season.Current(Lg)
	if open then return open.id end
	local list = ns.Season.List(Lg)
	return list[#list] and list[#list].id or nil
end

function BS:Items()
	local Lg, id = ledger(), self:Season()
	if not Lg or not id then return {} end
	return ns.GuildBank.Items(Lg, id)
end

function BS:Totals()
	local Lg, id = ledger(), self:Season()
	if not Lg or not id then return { items = 0, sold = 0, copper = 0 } end
	return ns.GuildBank.Totals(Lg, id)
end

-- Records the sale of the bank item `ref` (its ITEM_AWARDED id) for `copper`. Returns the event, or nil and a code.
function BS:RecordSale(ref, copper)
	local Lg, author = ledger(), me()
	if not Lg or not author then return nil, "NOT_READY" end
	local e, code = ns.GuildBank.RecordSale(Lg, { author = author, ts = serverNow(), ref = ref, copper = copper }, gate())
	if not e then return nil, code end
	emit("BANK_CHANGED", e)
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

-- "12g 30s 5c" in the client's language.
-- locale-key: BANK_MONEY
function BS.MoneyText(copper)
	return L()["BANK_MONEY"]:format(ns.GuildBank.Split(copper))
end

-- locale-key: BANK_FALLBACK BANK_FALLBACK_BANK BANK_FALLBACK_OFFSPEC BANK_FALLBACK_DISENCHANT BANK_FALLBACK_FREEROLL
-- locale-key: BANK_CHARACTER BANK_NO_CHARACTER
local function rulesLines()
	local rules = BS:Rules()
	local mode = rules.boeFallback or "bank"
	say(L()["BANK_FALLBACK"]:format(L()["BANK_FALLBACK_" .. tostring(mode):upper()]))
	local bank = rules.bankCharacter
	if type(bank) == "string" and bank ~= "" then
		say(L()["BANK_CHARACTER"]:format(short(bank)))
	else
		say(L()["BANK_NO_CHARACTER"])
	end
end

-- locale-key: BANK_LINE_SOLD BANK_LINE_UNSOLD
function BS.ItemLine(i, entry)
	if entry.copper then
		return L()["BANK_LINE_SOLD"]:format(i, itemText(entry.item), short(entry.member), BS.MoneyText(entry.copper))
	end
	return L()["BANK_LINE_UNSOLD"]:format(i, itemText(entry.item), short(entry.member))
end

-- locale-key: BANK_USAGE BANK_EMPTY BANK_HEADER BANK_TOTAL BANK_SOLD BANK_REFUSED BANK_BAD_PRICE
function BS.Command(input)
	local rest = (input or ""):match("^%s*%S+%s*(.-)%s*$") or ""
	local sub, args = rest:match("^(%S*)%s*(.-)$")
	sub = (sub or ""):lower()
	local list = BS:Items()
	if sub == "" then
		rulesLines()
		if #list == 0 then return say(L()["BANK_EMPTY"]) end
		say(L()["BANK_HEADER"])
		for i, entry in ipairs(list) do say(BS.ItemLine(i, entry)) end
		local t = BS:Totals()
		return say(L()["BANK_TOTAL"]:format(t.sold, t.items, BS.MoneyText(t.copper)))
	end
	if sub == "sold" then
		local n, price = args:match("^(%d+)%s+(.+)$")
		local entry = list[tonumber(n or "")]
		if not entry then return say(L()["BANK_USAGE"]) end
		local copper = ns.GuildBank.ParseMoney(price)
		if not copper then return say(L()["BANK_BAD_PRICE"]) end
		local e, code = BS:RecordSale(entry.id, copper)
		if not e then return say(L()["BANK_REFUSED"]:format(errorText(code))) end
		return say(L()["BANK_SOLD"]:format(itemText(entry.item), BS.MoneyText(copper)))
	end
	say(L()["BANK_USAGE"])
end

if ns.addon and ns.addon.commands then
	local cmds = ns.addon.commands
	cmds[#cmds + 1] = { name = "bank", helpKey = "HELP_BANK", handler = function(_, input) BS.Command(input) end }
end

if ns.addon then ns.addon.BankService = BS end   -- also reachable from tests
