-- Export: the credits table as text to copy (docs/ANALISI.md §7, §8.5, M6-3). Pure Lua 5.1: it never calls the game and
-- stores nothing; the numbers come from Domain/CreditTable.lua, i.e. from the ledger. Three forms:
--
--   Export.Discord(data, fmt)   a list of messages (each under Discord's 2000 characters): a header line and a monospaced
--                               table in a code block, numbers and dates in the guild's language
--   Export.Csv(data, fmt)       one row per member, a column per night; `;` as separator when the language writes the decimal
--                               comma (spreadsheets of that locale), `,` otherwise
--   Export.Json(data)           machine form: dates `YYYY-MM-DD`, numbers with a decimal point, fixed key order
--
-- Everything is deterministic: the same ledger gives the same bytes (rows in queue order, no clock, no `pairs` order).
-- The attendance (who was in the raid or on the bench) is **never** part of a public export: the data below only carries
-- what the Credits tab shows to every member (rank, name, class, role, credits, credits spent per night). The permission
-- `export.public` is checked by the caller (the window), not here.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Export = {}
ns.Export, ns.modules.Export = Export, Export

local type, ipairs, tostring, floor = type, ipairs, tostring, math.floor
local concat = table.concat

Export.KINDS = { "discord", "csv", "json" }
Export.DISCORD_LIMIT = 1900   -- Discord refuses a message over 2000 characters; a margin for the code fence

-- The guild's language comes from the caller (the window builds it from the locale keys; Domain/ carries no text):
-- fmt = { decimal, group, date (a pattern of %d %m %Y), className(code), roleName(code),
--         labels = { rank, member, class, role, credits, title (one %s), updated (one %s), part (two %d) } }.
local NEUTRAL = { decimal = ".", group = "" }

local function short(name) return (tostring(name or "?"):gsub("%-.*$", "")) end
local function round2(n) return floor(n * 100 + 0.5) / 100 end

---------------------------------------------------------------------------------------------------------------------
-- Data

-- What every export is made of: { season, label, updated = "YYYY-MM-DD"|nil, nights = { "YYYY-MM-DD" ... },
-- rows = { { rank, member, class, role, total, perNight = { n ... } } ... } } with the rows in queue order and perNight
-- aligned with `nights` (oldest first). opts.faction keeps one faction's members (the guild's). nil and the refusal code when the season does not exist.
function Export.Data(L, season, opts)
	local t, why = ns.CreditTable.Build(L, season, { faction = opts and opts.faction })
	if not t then return nil, why end
	local out = { season = t.season, label = t.label, updated = t.updated, nights = {}, rows = {} }
	for i, n in ipairs(t.nights) do out.nights[i] = n.date or "" end
	for i, r in ipairs(t.rows) do
		local per = {}
		for j, n in ipairs(t.nights) do per[j] = round2(r.perNight[n.id] or 0) end
		out.rows[i] = { rank = r.rank, member = short(r.member), class = r.class, role = r.role,
			total = round2(r.total), perNight = per }
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Numbers, dates, widths

-- 2 decimals at most, no trailing zeros, the language's decimal mark and thousands separator.
function Export.Number(n, fmt)
	fmt = fmt or NEUTRAL
	n = round2(n or 0)
	local sign = n < 0 and "-" or ""
	local s = ("%.2f"):format(math.abs(n)):gsub("0+$", ""):gsub("%.$", "")
	local int, frac = s:match("^(%d+)%.?(%d*)$")
	local grouped, group = int, fmt.group or ""
	if group ~= "" then
		grouped = ""
		for i = 1, #int do
			grouped = grouped .. int:sub(i, i)
			if (#int - i) % 3 == 0 and i < #int then grouped = grouped .. group end
		end
	end
	return sign .. grouped .. (frac ~= "" and (fmt.decimal or ".") .. frac or "")
end

-- "YYYY-MM-DD" through a pattern of %d %m %Y %y (the locale's DATE_LONG); anything else is kept as it is.
function Export.Date(iso, pattern)
	local y, m, d = tostring(iso or ""):match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
	if not y then return tostring(iso or "") end
	return (pattern:gsub("%%(%a)", function(c)
		if c == "d" then return d elseif c == "m" then return m elseif c == "Y" then return y
		elseif c == "y" then return y:sub(3) end
	end))
end

local function ulen(s)   -- characters, not bytes (names may carry accents)
	local _, n = tostring(s):gsub("[^\128-\191]", "")
	return n
end
local function padRight(s, w) return s .. (" "):rep(w - ulen(s)) end
local function padLeft(s, w) return (" "):rep(w - ulen(s)) .. s end

---------------------------------------------------------------------------------------------------------------------
-- Discord

local function header(data, fmt)
	local lb = fmt.labels
	local text = "**" .. lb.title:format(data.label or tostring(data.season)) .. "**"
	if data.updated then text = text .. " (" .. lb.updated:format(Export.Date(data.updated, fmt.date)) .. ")" end
	return text
end

-- The messages: { text ... }, at least one. A long table goes on in further messages that repeat the column line.
function Export.Discord(data, fmt)
	local lb = fmt.labels
	local cells = {}
	local w = { ulen(lb.rank), ulen(lb.member), ulen(lb.class), ulen(lb.role), ulen(lb.credits) }
	for i, r in ipairs(data.rows) do
		local c = { tostring(r.rank), r.member, fmt.className(r.class), fmt.roleName(r.role), Export.Number(r.total, fmt) }
		cells[i] = c
		for k = 1, 5 do if ulen(c[k]) > w[k] then w[k] = ulen(c[k]) end end
	end
	local function line(c)
		return padLeft(c[1], w[1]) .. "  " .. padRight(c[2], w[2]) .. "  " .. padRight(c[3], w[3]) .. "  "
			.. padRight(c[4], w[4]) .. "  " .. padLeft(c[5], w[5])
	end
	local head = line({ lb.rank, lb.member, lb.class, lb.role, lb.credits })
	local messages, body, size, first = {}, {}, 0, true
	local function flush()
		local top = first and (header(data, fmt) .. "\n") or ""
		messages[#messages + 1] = top .. "```\n" .. head .. "\n" .. concat(body, "\n") .. (#body > 0 and "\n" or "") .. "```"
		body, size, first = {}, 0, false
	end
	local reserve = #header(data, fmt) + #head + 16
	for _, c in ipairs(cells) do
		local l = line(c)
		if size + #l + 1 + reserve > Export.DISCORD_LIMIT and #body > 0 then flush() end
		body[#body + 1] = l
		size = size + #l + 1
	end
	flush()
	if #messages > 1 then
		for i, m in ipairs(messages) do messages[i] = m .. "\n" .. lb.part:format(i, #messages) end
	end
	return messages
end

---------------------------------------------------------------------------------------------------------------------
-- CSV

local function csvField(s, sep)
	s = tostring(s)
	if s:find('[' .. sep .. '"\r\n]') then return '"' .. s:gsub('"', '""') .. '"' end
	return s
end

function Export.Csv(data, fmt)
	local lb = fmt.labels
	local sep = (fmt.decimal == ",") and ";" or ","
	local function row(fields)
		local out = {}
		for i, f in ipairs(fields) do out[i] = csvField(f, sep) end
		return concat(out, sep)
	end
	local lines = {}
	local head = { lb.rank, lb.member, lb.class, lb.role, lb.credits }
	for _, d in ipairs(data.nights) do head[#head + 1] = Export.Date(d, fmt.date) end
	lines[1] = row(head)
	for _, r in ipairs(data.rows) do
		local f = { tostring(r.rank), r.member, fmt.className(r.class), fmt.roleName(r.role), Export.Number(r.total, fmt) }
		for _, v in ipairs(r.perNight) do f[#f + 1] = Export.Number(v, fmt) end
		lines[#lines + 1] = row(f)
	end
	return concat(lines, "\n") .. "\n"
end

---------------------------------------------------------------------------------------------------------------------
-- JSON

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function jstr(s)
	return '"' .. tostring(s):gsub('[%c"\\]', function(c) return ESC[c] or ("\\u%04x"):format(c:byte()) end) .. '"'
end
local function jnum(n) return Export.Number(n, NEUTRAL) end

function Export.Json(data)
	local out = { "{" }
	out[#out + 1] = '  "season": ' .. jstr(data.season) .. ","
	out[#out + 1] = '  "label": ' .. jstr(data.label or "") .. ","
	out[#out + 1] = '  "updated": ' .. (data.updated and jstr(data.updated) or "null") .. ","
	local nights = {}
	for i, d in ipairs(data.nights) do nights[i] = jstr(d) end
	out[#out + 1] = '  "nights": [' .. concat(nights, ", ") .. "],"
	out[#out + 1] = '  "credits": ['
	for i, r in ipairs(data.rows) do
		local per = {}
		for j, v in ipairs(r.perNight) do per[j] = jnum(v) end
		out[#out + 1] = concat({
			'    {"rank": ', tostring(r.rank), ', "member": ', jstr(r.member), ', "class": ', jstr(r.class or ""),
			', "role": ', jstr(r.role or ""), ', "total": ', jnum(r.total), ', "perNight": [', concat(per, ", "), "]}",
			i < #data.rows and "," or "",
		})
	end
	out[#out + 1] = "  ]"
	out[#out + 1] = "}"
	return concat(out, "\n") .. "\n"
end

-- One call for the window: kind = "discord" | "csv" | "json"; the answer is a list of texts (one for csv and json).
function Export.Build(L, season, kind, fmt, opts)
	local data, why = Export.Data(L, season, opts)
	if not data then return nil, why end
	if kind == "discord" then return Export.Discord(data, fmt)
	elseif kind == "csv" then return { Export.Csv(data, fmt) }
	elseif kind == "json" then return { Export.Json(data) } end
	return nil, "EXPORT_KIND_UNKNOWN"
end

if ns.addon then ns.addon.Export = Export end   -- also reachable from tests
