-- Notice: the text of the "addon missing" notice written in /raid (docs/ANALISI.md §4.1, M3-6). Pure Lua 5.1: it never
-- calls the game. The rules' section "notice" holds what the Guild Master can edit:
--   text          the notice for members without the addon; "" = the default of the player's language
--   outdatedText  the notice for members with an older version; "" = the default
--   link          where to download the addon ("" = the project's releases page)
--   whisper       true = one whisper to each name instead of one /raid message
--   minutes       at most one notice every `minutes` minutes (0 = no limit), per night
-- Placeholders in a text: {names} (the list), {link} (the download link), {addon} (the addon's name).
-- Compose builds the chat lines: every line starts with "[FDCP] " and is at most 255 bytes (the chat limit); when the
-- names do not fit in one line they are split over several lines, each one a whole notice.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Notice = {}
ns.Notice, ns.modules.Notice = Notice, Notice

local type, pairs, tostring, floor, sort = type, pairs, tostring, math.floor, table.sort

Notice.LINE_MAX = 255
Notice.TAG = "[FDCP] "
Notice.DEFAULT_LINK = "https://github.com/Finland6738/finland-dragon-credit-points/releases"
Notice.TEXT_MAX, Notice.LINK_MAX, Notice.MINUTES_MAX = 120, 80, 60
Notice.KINDS = { MISSING = true, OUTDATED = true }

function Notice.DefaultConfig()
	return { text = "", outdatedText = "", link = "", whisper = false, minutes = 5 }
end

local FIELDS = { text = true, outdatedText = true, link = true, whisper = true, minutes = true }

-- Returns true, or false and a sorted list of codes.
function Notice.ValidateConfig(c)
	if type(c) ~= "table" then return false, { "notice" } end
	local p = {}
	if type(c.text) ~= "string" or #c.text > Notice.TEXT_MAX then p[#p + 1] = "text" end
	if type(c.outdatedText) ~= "string" or #c.outdatedText > Notice.TEXT_MAX then p[#p + 1] = "outdatedText" end
	if type(c.link) ~= "string" or #c.link > Notice.LINK_MAX or c.link:find("[%c|]") then p[#p + 1] = "link" end
	if type(c.whisper) ~= "boolean" then p[#p + 1] = "whisper" end
	if type(c.minutes) ~= "number" or c.minutes ~= floor(c.minutes) or c.minutes < 0 or c.minutes > Notice.MINUTES_MAX then
		p[#p + 1] = "minutes"
	end
	for k in pairs(c) do
		if not FIELDS[k] then p[#p + 1] = "unknown:" .. tostring(k) end
	end
	sort(p)
	return #p == 0, p
end

-- The name without its realm ("Aurel-Camelot" -> "Aurel").
function Notice.ShortName(name)
	return (tostring(name):match("^([^%-]+)")) or tostring(name)
end

-- Fills the placeholders of `template` except {names}. `|` is doubled-proof: it never reaches chat from here.
local function fill(template, cfg, addonTitle)
	local link = cfg.link ~= "" and cfg.link or Notice.DEFAULT_LINK
	template = template:gsub("{link}", function() return link end)
	template = template:gsub("{addon}", function() return addonTitle end)
	return template
end

-- The template of one notice: the guild's text for the kind, or `default` (the player's language), with every
-- placeholder but {names} filled and the tag in front (a text without {names} gets the names at its end).
function Notice.Template(cfg, kind, default, addonTitle)
	cfg = cfg or Notice.DefaultConfig()
	local own = kind == "OUTDATED" and cfg.outdatedText or cfg.text
	local text = (type(own) == "string" and own ~= "") and own or default
	if not text:find("{names}", 1, true) then text = text .. " {names}" end   -- a text without the placeholder ends with the names
	return Notice.TAG .. fill(text, cfg, addonTitle or "")
end

-- The lines to write: `names` (a list of names, realms allowed) are put in the template, as many as fit in a line
-- (names joined with ", "). Returns the list of lines, or nil and a code: "NOBODY", "TEXT_TOO_LONG" (the template alone
-- leaves no room for the longest name).
function Notice.Compose(template, names)
	if type(names) ~= "table" or #names == 0 then return nil, "NOBODY" end
	local shorts, longest = {}, 0
	for i, n in ipairs(names) do
		shorts[i] = Notice.ShortName(n)
		if #shorts[i] > longest then longest = #shorts[i] end
	end
	local fixed = #(template:gsub("{names}", ""))
	if fixed + longest > Notice.LINE_MAX then return nil, "TEXT_TOO_LONG" end
	local lines, current = {}, nil
	local function flush()
		if current then
			local joined = table.concat(current, ", ")
			lines[#lines + 1] = (template:gsub("{names}", function() return joined end))
		end
		current = nil
	end
	local size = 0
	for _, short in ipairs(shorts) do
		local extra = #short + (current and 2 or 0)
		if current and fixed + size + extra > Notice.LINE_MAX then flush() end
		if not current then current, size = {}, 0 end
		size = size + #short + (#current > 0 and 2 or 0)
		current[#current + 1] = short
	end
	flush()
	return lines
end

-- The line for one whispered name.
function Notice.ComposeWhisper(template, name)
	return Notice.Compose(template, { name })
end

if ns.addon then ns.addon.Notice = Notice end   -- also reachable from tests
