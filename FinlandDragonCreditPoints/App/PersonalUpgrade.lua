-- PersonalUpgrade: the player's own upgrade settings (docs/ANALISI.md §5.1 points 3 and 5, §13 question 8, M5-3): personal
-- stat weights per spec, imported from a Pawn-like string (Domain/WeightImport.lua), and the best-in-slot wishlist
-- (Domain/Wishlist.lua). Everything is personal: it lives in FinlandDragonCreditPointsCharDB.upgrade, the guild's ledger
-- never sees it, and nothing here is on by default (issue #2 is still open: the default weights of Data/StatWeights.lua
-- are the reversible default). Importing is the player's own act and turns the personal weights on; `/fdcp weights off`
-- turns them off again without losing the rows, `reset` removes them.
--
--   char.upgrade = { personal = bool, weights = { [specID] = { CODE = number } }, wish = { [itemID] = true } }
--
-- PU.Enabled(), PU.SetEnabled(on), PU.WeightsFor(specID) -> a row | nil (only while the personal weights are on),
-- PU.Import(specID, text) -> { weights, name, ignored } | nil, code, detail, PU.Reset(specID | nil),
-- PU.Has(itemID), PU.WishAdd(id), PU.WishRemove(id), PU.WishList(), PU.WishClear().
-- Every change emits UPGRADE_ADVICE_CHANGED (the popup draws again) and forgets the advisor's answers.
-- The commands `/fdcp weights ...` and `/fdcp wish ...` are the interface; their words are locale keys.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local PU = {}
ns.PersonalUpgrade, ns.modules.PersonalUpgrade = PU, PU

local type, tonumber, ipairs, pairs, sort, concat = type, tonumber, ipairs, pairs, table.sort, table.concat

local function L() return ns.L end

---------------------------------------------------------------------------------------------------------------------
-- The data (a clean copy is made once per session; what is saved is only ever the clean one)

local function char() return ns.Config and ns.Config.char end

local checked = setmetatable({}, { __mode = "k" })   -- the saved tables already cleaned this session

local function data()
	local c = char()
	if not c then return nil end
	local d = c.upgrade
	if type(d) ~= "table" then d = {}; c.upgrade = d end
	if not checked[d] then
		local weights = {}
		if type(d.weights) == "table" then
			for spec, row in pairs(d.weights) do
				local clean = type(spec) == "number" and ns.WeightImport.Sanitize(row)
				if clean then weights[spec] = clean end
			end
		end
		d.weights = weights
		d.wish = ns.Wishlist.Sanitize(d.wish)
		d.personal = d.personal == true
		checked[d] = true
	end
	return d
end

local function writable()
	if not data() then return false, "NOT_READY" end
	if ns.Config and ns.Config:IsReadOnly() then return false, "READ_ONLY" end
	return true
end

local function changed()
	if ns.UpgradeAdvisor then ns.UpgradeAdvisor.Reset() end
	if ns.Bus then ns.Bus:Emit("UPGRADE_ADVICE_CHANGED") end
end

---------------------------------------------------------------------------------------------------------------------
-- Weights

function PU.Enabled()
	local d = data()
	return d ~= nil and d.personal == true
end

function PU.SetEnabled(on)
	local ok, code = writable()
	if not ok then return false, code end
	data().personal = on == true
	changed()
	return true
end

-- The personal row of a spec while the personal weights are on, or nil (the default weights apply). A copy.
function PU.WeightsFor(specID)
	local d = data()
	if not d or not d.personal or type(specID) ~= "number" then return nil end
	local row = d.weights[specID]
	if not row then return nil end
	local out = {}
	for k, v in pairs(row) do out[k] = v end
	return out
end

-- The specs with a personal row, ascending.
function PU.Specs()
	local d, out = data(), {}
	for spec in pairs(d and d.weights or {}) do out[#out + 1] = spec end
	sort(out)
	return out
end

-- The row saved for a spec whether or not the personal weights are on (for `show`).
function PU.Row(specID)
	local d = data()
	local row = d and type(specID) == "number" and d.weights[specID]
	if not row then return nil end
	local out = {}
	for k, v in pairs(row) do out[k] = v end
	return out
end

function PU.Import(specID, text)
	local ok, code = writable()
	if not ok then return nil, code end
	if not ns.Specs or not ns.Specs.Get(specID) then return nil, "BAD_SPEC" end
	local parsed, err, detail = ns.WeightImport.Parse(text)
	if not parsed then return nil, err, detail end
	local d = data()
	d.weights[specID] = parsed.weights
	d.personal = true
	changed()
	return parsed
end

-- Removes the personal row of a spec (nil: every row). True when something was removed.
function PU.Reset(specID)
	local ok = writable()
	if not ok then return false end
	local d, any = data(), false
	for spec in pairs(d.weights) do
		if specID == nil or spec == specID then d.weights[spec] = nil; any = true end
	end
	if any then changed() end
	return any
end

---------------------------------------------------------------------------------------------------------------------
-- The wishlist

function PU.Has(itemID)
	local d = data()
	return d ~= nil and ns.Wishlist.Has(d.wish, itemID)
end

function PU.WishAdd(id)
	local ok, code = writable()
	if not ok then return false, code end
	local d = data()
	local had = d.wish[id]
	local added, why = ns.Wishlist.Add(d.wish, id)
	if added and not had then changed() end
	return added, why
end

function PU.WishRemove(id)
	local ok = writable()
	if not ok then return false end
	local removed = ns.Wishlist.Remove(data().wish, id)
	if removed then changed() end
	return removed
end

function PU.WishList()
	local d = data()
	return d and ns.Wishlist.List(d.wish) or {}
end

function PU.WishClear()
	local ok = writable()
	if not ok then return false end
	local d = data()
	if ns.Wishlist.Count(d.wish) == 0 then return false end
	ns.Wishlist.Clear(d.wish)
	changed()
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- The commands (words from the locale)

local function say(text)
	if ns.addon then ns.addon:Print(text) end
end

-- locale-key: RC_IMPORT_EMPTY RC_IMPORT_TOO_LONG RC_IMPORT_BAD_FORMAT RC_IMPORT_BAD_VALUE RC_IMPORT_NO_STATS RC_IMPORT_BAD_SPEC

local function specName(spec)
	local info = ns.Specs and ns.Specs.Get(spec)
	return info and ("%s (%d)"):format(info.name, spec) or tostring(spec)
end

-- A spec argument: an id, or "ms" / "os" for the declared (or current) main-spec and off-spec. Returns the id or nil.
local function resolveSpec(arg)
	if not arg or arg == "" then return nil end
	local n = tonumber(arg)
	if n then return n end
	local which = arg:lower()
	if which ~= "ms" and which ~= "os" then return nil end
	if not ns.UpgradeAdvisor then return nil end
	local ms, os = ns.UpgradeAdvisor.Specs()
	if which == "ms" then return ms end
	return os
end

local function readOnly() say(L()["LANGUAGE_READ_ONLY"]) end

local function weightsStatus()
	say(PU.Enabled() and L()["WEIGHTS_STATE_ON"] or L()["WEIGHTS_STATE_OFF"])
	local names = {}
	for _, spec in ipairs(PU.Specs()) do names[#names + 1] = specName(spec) end
	say(#names > 0 and L()["WEIGHTS_SPECS"]:format(concat(names, ", ")) or L()["WEIGHTS_NO_SPECS"])
	say(L()["WEIGHTS_USAGE"])
end

function PU.WeightsCommand(input)
	local rest = (input or ""):match("^%s*%S+%s*(.-)%s*$") or ""
	local sub, args = rest:match("^(%S*)%s*(.-)$")
	sub = (sub or ""):lower()
	if sub == "" then return weightsStatus() end
	if sub == "on" or sub == "off" then
		local ok, why = PU.SetEnabled(sub == "on")
		if not ok then return why == "READ_ONLY" and readOnly() or say(L()["WEIGHTS_USAGE"]) end
		return say(sub == "on" and L()["WEIGHTS_STATE_ON"] or L()["WEIGHTS_STATE_OFF"])
	end
	if sub == "import" then
		local specArg, text = args:match("^(%S+)%s*(.-)$")
		local spec = resolveSpec(specArg)
		if not spec or not (ns.Specs and ns.Specs.Get(spec)) then return say(L()["WEIGHTS_BAD_SPEC"]:format(specArg or "")) end
		local parsed, code, detail = PU.Import(spec, text)
		if not parsed then
			if code == "READ_ONLY" then return readOnly() end
			local words = ns.Reasons.Text("IMPORT", code)
			if detail then words = words .. " (" .. detail .. ")" end
			return say(L()["WEIGHTS_REFUSED"]:format(words))
		end
		local n = 0
		for _ in pairs(parsed.weights) do n = n + 1 end
		say(L()["WEIGHTS_IMPORTED"]:format(specName(spec), n))
		if #parsed.ignored > 0 then say(L()["WEIGHTS_IGNORED"]:format(concat(parsed.ignored, ", "))) end
		return
	end
	if sub == "show" then
		local spec = resolveSpec(args)
		if not spec or not (ns.Specs and ns.Specs.Get(spec)) then return say(L()["WEIGHTS_BAD_SPEC"]:format(args)) end
		local row = PU.Row(spec)
		local source = L()["WEIGHTS_SOURCE_PERSONAL"]
		if not row then row, source = ns.StatWeights and ns.StatWeights.Default(spec), L()["WEIGHTS_SOURCE_DEFAULT"] end
		if not row then return say(L()["WEIGHTS_BAD_SPEC"]:format(args)) end
		return say(L()["WEIGHTS_SHOW"]:format(specName(spec), source, ns.WeightImport.Format(row, specName(spec))))
	end
	if sub == "reset" then
		if args:lower() == "all" then
			return say(PU.Reset(nil) and L()["WEIGHTS_RESET_ALL"] or L()["WEIGHTS_NO_SPECS"])
		end
		local spec = resolveSpec(args)
		if not spec then return say(L()["WEIGHTS_BAD_SPEC"]:format(args)) end
		return say(PU.Reset(spec) and L()["WEIGHTS_RESET"]:format(specName(spec)) or L()["WEIGHTS_NONE_FOR"]:format(specName(spec)))
	end
	say(L()["WEIGHTS_USAGE"])
end

local function itemText(id)
	local entry = ns.ItemCache and ns.ItemCache.Lookup(id)
	return entry and entry.link or L()["WISH_UNKNOWN_ITEM"]:format(id)
end

function PU.WishCommand(input)
	local rest = (input or ""):match("^%s*%S+%s*(.-)%s*$") or ""
	local sub, args = rest:match("^(%S*)%s*(.-)$")
	sub = (sub or ""):lower()
	if sub == "" or sub == "list" then
		local list = PU.WishList()
		if #list == 0 then return say(L()["WISH_EMPTY"]) end
		say(L()["WISH_LIST_HEADER"]:format(#list))
		for _, id in ipairs(list) do say("  " .. itemText(id)) end
		return
	end
	if sub == "clear" then
		return say(PU.WishClear() and L()["WISH_CLEARED"] or L()["WISH_EMPTY"])
	end
	if sub == "add" or sub == "remove" then
		local ids = ns.Wishlist.ItemIDs(args)
		if #ids == 0 then return say(L()["WISH_USAGE"]) end
		for _, id in ipairs(ids) do
			if sub == "add" then
				local ok, why = PU.WishAdd(id)
				if ok then say(L()["WISH_ADDED"]:format(itemText(id)))
				elseif why == "FULL" then say(L()["WISH_FULL"]:format(ns.Wishlist.MAX)); return
				elseif why == "READ_ONLY" then return readOnly()
				else say(L()["WISH_USAGE"]) end
			else
				say(PU.WishRemove(id) and L()["WISH_REMOVED"]:format(itemText(id)) or L()["WISH_NOT_LISTED"]:format(itemText(id)))
			end
		end
		return
	end
	say(L()["WISH_USAGE"])
end

if ns.addon and ns.addon.commands then
	local cmds = ns.addon.commands
	cmds[#cmds + 1] = { name = "weights", helpKey = "HELP_WEIGHTS", handler = function(_, input) PU.WeightsCommand(input) end }
	cmds[#cmds + 1] = { name = "wish", helpKey = "HELP_WISH", handler = function(_, input) PU.WishCommand(input) end }
end

if ns.addon then ns.addon.PersonalUpgrade = PU end   -- also reachable from tests
