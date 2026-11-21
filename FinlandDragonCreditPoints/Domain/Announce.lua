-- Announce: the texts the master looter's client writes in /raid during a loot session (docs/ANALISI.md §4 "Annuncio"
-- and "risultato al raid", §8.5 guild language, M4-8). Pure Lua 5.1: it never calls the game. The rules' section
-- "announce" holds what the Guild Master can edit:
--   enabled     false = nothing is written in /raid (the popups and the window are not affected)
--   itemText    the line announcing an item before its roll; "" = the default of the guild language
--   resultText  the line announcing who won; "" = the default (an item for the bank or to disenchant keeps its default)
--   reason      false = the result line carries no reason sentence
-- Placeholders of itemText: {item} (the link), {category}, {cost} ("1 credit", "free", "set by the council").
-- Placeholders of resultText: {item}, {winner}, {cost}, {category}, {reason} (the sentence composed from the reason
-- codes, in the guild language). A placeholder nobody knows is left as written.
-- The lines are built like the notice of Domain/Notice.lua: they start with "[FDCP] " and are at most 255 bytes; a longer
-- text is split at a space (an item link is never cut) and every part starts with the tag again.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Announce = {}
ns.Announce, ns.modules.Announce = Announce, Announce

local type, pairs, ipairs, tostring, sort = type, pairs, ipairs, tostring, table.sort

Announce.TEXT_MAX = 160
Announce.KINDS = { ITEM = true, RESULT = true }

function Announce.DefaultConfig()
	return { enabled = true, itemText = "", resultText = "", reason = true }
end

local FIELDS = { enabled = true, itemText = true, resultText = true, reason = true }

-- Returns true, or false and a sorted list of codes.
function Announce.ValidateConfig(c)
	if type(c) ~= "table" then return false, { "announce" } end
	local p = {}
	if type(c.enabled) ~= "boolean" then p[#p + 1] = "enabled" end
	for _, k in ipairs({ "itemText", "resultText" }) do
		if type(c[k]) ~= "string" or #c[k] > Announce.TEXT_MAX or c[k]:find("[%c|]") then p[#p + 1] = k end
	end
	if type(c.reason) ~= "boolean" then p[#p + 1] = "reason" end
	for k in pairs(c) do
		if not FIELDS[k] then p[#p + 1] = "unknown:" .. tostring(k) end
	end
	sort(p)
	return #p == 0, p
end

-- The guild's text for `kind` ("ITEM" | "RESULT"), or `default`.
function Announce.Template(cfg, kind, default)
	local own = cfg and (kind == "ITEM" and cfg.itemText or cfg.resultText)
	if type(own) == "string" and own ~= "" then return own end
	return default
end

-- Fills the {placeholders} of `template` from `vars` (values are converted to strings); the result is trimmed.
function Announce.Fill(template, vars)
	local out = template:gsub("{(%w+)}", function(name)
		local v = vars and vars[name]
		if v == nil then return nil end   -- unknown: left as written
		return tostring(v)
	end)
	out = out:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	return out
end

-- The cost as a phrase: `texts` = { free, one, many (a format with %s), council } already in the guild language, `number`
-- = the cost formatted with the language's separators; `council` true or no cost = the council sets it.
function Announce.CostText(texts, cost, number, council)
	if council or cost == nil then return texts.council end
	if cost == 0 then return texts.free end
	if cost == 1 then return texts.one end
	return texts.many:format(number)
end

-- Splits `text` into chat lines: each starts with the tag and has at most 255 bytes; breaks only at spaces, never inside
-- an item link. Returns a list (empty for an empty text).
function Announce.Lines(text)
	local tag, max = ns.Notice.TAG, ns.Notice.LINE_MAX
	text = tostring(text or "")
	local protected = text:gsub("|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r", function(l) return (l:gsub(" ", "\3")) end)
	protected = protected:gsub("|H.-|h.-|h", function(l) return (l:gsub(" ", "\3")) end)
	local lines, current = {}, nil
	for word in protected:gmatch("%S+") do
		word = word:gsub("\3", " ")
		if #tag + #word > max then word = word:sub(1, max - #tag) end   -- a single word that cannot fit: cut, never overflow
		if current and #current + 1 + #word <= max then
			current = current .. " " .. word
		else
			if current then lines[#lines + 1] = current end
			current = tag .. word
		end
	end
	if current then lines[#lines + 1] = current end
	return lines
end

if ns.addon then ns.addon.Announce = Announce end   -- also reachable from tests
