-- The layout of the Settings tab (fix/settings-layout): every sub-tab and every page of the rules, laid out by the mock's
-- anchor engine (Tests/mock/27_layout.lua) with text metrics close to the addon's font, at the minimum and the default size
-- of the window, in English and in Italian (the longer strings), as the Guild Master (the controls on) and as a raider
-- (read-only). What is checked, for every visible text and control:
--   * it is inside its pane (nothing spills out of the window's area or over the page list);
--   * no two of them overlap (a label never runs under a control, a value is never drawn over another row);
--   * a button's text fits in the button;
--   * in a form table (Widgets.FormList) every row has its description in the left column and its value in the right one,
--     inside the row, and only whole rows are shown;
--   * after a change of page only the rows of the new page are shown, each with the one control of its field.
-- The real client was not run: the font metrics are an approximation (0.55 of the size per character, a little wider than
-- Outfit), the same layout code runs in game.
local function SW() return FDCP.SettingsWindow end
local function RF() return FDCP.RuleFields end

local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }
local SIZES = { min = { 900, 560 }, default = { 960, 640 } }
local EPS = 0.5

local function setup(locale, myRank)
	return function(Mock)
		Mock.textScale = 0.55
		Mock.player.locale = locale
		Mock.guild.Set({ name = "Keepers", ranks = RANKS, myRank = myRank, members = {
			{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
		} })
	end
end

-- The client runs OnSizeChanged when a frame's size changes: the mock does not, so the test does it after a resize.
local function sized(frame)
	local fn = frame:GetScript("OnSizeChanged")
	if fn then fn(frame, frame:GetWidth(), frame:GetHeight()) end
	for _, child in ipairs(frame._children) do sized(child) end
end

local function openSettings(size)
	Mock.Slash("/fdcp")
	FDCP.MainWindow:SelectTab("settings")
	local f = FDCP.MainWindow.frame
	f:SetSize(size[1], size[2])
	sized(f)
	Mock.FinishAnimations()
	return SW().root
end

local function rect(w)
	local l, b, width, height = Mock.Rect(w)
	if not l then return nil end
	return { l = l, b = b, r = l + width, t = b + height, w = width, h = height }
end

local function describeWidget(w)
	if w._type == "FontString" then return "text '" .. tostring(w._text) .. "'" end
	local label = w.label and w.label._text
	return w._type .. (label and (" '" .. label .. "'") or "") .. (w.field and (" of " .. w.field.id) or "")
end

-- The visible texts and controls under `root`.
local CONTROL = { Button = true, CheckButton = true, EditBox = true }
local function content(root)
	local out = {}
	local function walk(w)
		if not w:IsVisible() then return end
		if CONTROL[w._type] then out[#out + 1] = w end
		for _, r in ipairs(w._regions) do
			if r._type == "FontString" and r:IsVisible() and (r._text or "") ~= "" then out[#out + 1] = r end
		end
		for _, c in ipairs(w._children) do walk(c) end
	end
	walk(root)
	return out
end

local function ancestor(a, b)
	local p = b._parent
	while p do
		if p == a then return true end
		p = p._parent
	end
	return false
end

local function inside(inner, outer) return inner.l >= outer.l - EPS and inner.r <= outer.r + EPS and inner.b >= outer.b - EPS and inner.t <= outer.t + EPS end
local function overlap(a, b) return math.min(a.r, b.r) - math.max(a.l, b.l) > EPS and math.min(a.t, b.t) - math.max(a.b, b.b) > EPS end

-- Every problem of the visible layout of `pane`, as lines.
local function problems(pane, where)
	local out = {}
	local box = rect(pane)
	local items = content(pane)
	local rects = {}
	for i, w in ipairs(items) do
		local r = rect(w)
		rects[i] = r
		if not r then
			out[#out + 1] = where .. ": " .. describeWidget(w) .. " has no position"
		elseif not inside(r, box) then
			out[#out + 1] = ("%s: %s is outside its pane (%.0f..%.0f x %.0f..%.0f)"):format(where, describeWidget(w), r.l - box.l, r.r - box.l, box.t - r.t, box.t - r.b)
		end
		-- the text of a button fits in it
		if r and w._type == "FontString" and w._parent and CONTROL[w._parent._type] and w._parent._type ~= "EditBox" then
			local pr = rect(w._parent)
			if pr and not inside(r, pr) then out[#out + 1] = where .. ": the " .. describeWidget(w) .. " does not fit in its button" end
		end
	end
	for i = 1, #items do
		for j = i + 1, #items do
			local a, b = items[i], items[j]
			if rects[i] and rects[j] and not ancestor(a, b) and not ancestor(b, a) and overlap(rects[i], rects[j]) then
				out[#out + 1] = where .. ": " .. describeWidget(a) .. " overlaps " .. describeWidget(b)
			end
		end
	end
	return out
end

-- The rows of a FormList: description left, value right, inside the row; rows inside the list; whole rows only.
local function formProblems(list, where)
	local out = {}
	local lr = rect(list)
	local _, valueX = list:Columns()
	for i = 1, list.count do
		local row = list.rows[i]
		if row:IsShown() then
			local rr, label = rect(row), rect(row.label)
			if not inside(rr, lr) then out[#out + 1] = where .. ": row " .. i .. " is not inside the table" end
			if not inside(label, rr) then out[#out + 1] = where .. ": the description of row " .. i .. " is taller or wider than its row" end
			local c = row.control and rect(row.control)
			if c then
				if not inside(c, rr) then out[#out + 1] = where .. ": the value of row " .. i .. " is not inside its row" end
				if math.abs(c.l - (lr.l + valueX)) > EPS then out[#out + 1] = where .. ": the value of row " .. i .. " is not in the value column" end
				if label.r > c.l + EPS then out[#out + 1] = where .. ": the description of row " .. i .. " runs under its value" end
			end
		end
	end
	return out
end

local function report(list)
	if #list > 0 then error(#list .. " layout problems:\n  " .. table.concat(list, "\n  "), 0) end
end

-- Every page of the rules, then every other sub-tab, at one size.
local function checkAll(size, label)
	local root = openSettings(SIZES[size])
	local found = {}
	local function add(list) for _, p in ipairs(list) do found[#found + 1] = p end end
	for _, sub in ipairs(SW().SUBTABS) do
		root.sub:Select(sub)
		SW():Refresh()
		Mock.FinishAnimations()
		local pane = root.panes[sub]
		if sub == "rules" or sub == "site" then
			local form = sub == "rules" and SW().rules or SW().site
			for _, page in ipairs(form.pages) do
				if form.list then form.list:Select(page) else form:SetPage(page) end
				local where = ("%s %s %s/%s"):format(label, size, sub, page)
				-- every row of the page, scrolled into view one screen at a time
				local seen, guard = {}, 0
				repeat
					add(problems(pane, where))
					add(formProblems(form.form, where))
					for i = 1, form.form.count do if form.form.rows[i]:IsShown() then seen[i] = true end end
					local before = form.form:Offset()
					form.form:Scroll(1)   -- a row at a time
					guard = guard + 1
				until form.form:Offset() == before or guard > 40
				for i = 1, #form.fields do
					if not seen[i] then found[#found + 1] = where .. ": row " .. i .. " (" .. form.fields[i].id .. ") can never be seen" end
				end
				form.form:ScrollTo(0)
			end
		else
			add(problems(pane, ("%s %s %s"):format(label, size, sub)))
			if pane.form then add(formProblems(pane.form, ("%s %s %s"):format(label, size, sub))) end
		end
	end
	report(found)
end

for _, locale in ipairs({ "enUS", "itIT" }) do
	for _, who in ipairs({ { "the Guild Master", 0 }, { "a raider", 3 } }) do
		describe("the Settings layout in " .. locale .. " for " .. who[1], function()
			before_boot(setup(locale, who[2]))
			for _, size in ipairs({ "min", "default" }) do
				it("has no overlap and nothing outside its pane at the " .. size .. " size", function()
					checkAll(size, locale .. " " .. who[1])
				end)
			end
		end)
	end
end

describe("the pages of the rules", function()
	before_boot(setup("enUS", 3))

	it("show only the rows of the page, each with the one control of its field, after any change of page", function()
		openSettings(SIZES.min)
		local root = SW().root
		root.sub:Select("rules")
		local form = SW().rules
		-- every page after every other one (the rows are pooled across the pages)
		for _, from in ipairs(form.pages) do
			for _, to in ipairs(form.pages) do
				form.list:Select(from)
				form.form:Scroll(1000)
				form.list:Select(to)
				if from ~= to then eq(form.form:Offset(), 0, to .. " starts at the top") end
				local fields = RF().Page(to)
				eq(form.form.count, #fields, to .. " has a row per field")
				for i, row in ipairs(form.form.rows) do
					if i > #fields then
						falsy(row:IsShown(), ("%s -> %s: row %d of the page before is hidden"):format(from, to, i))
					else
						local kind = fields[i].kind
						local want = (kind == "bool" and row.switch) or (kind == "choice" and row.select) or row.edit
						eq(row.field, fields[i], to .. " row " .. i .. " has its field")
						for _, c in ipairs({ row.switch, row.select, row.edit }) do
							if c then eq(c:IsShown(), c == want, ("%s -> %s: row %d shows only its own control"):format(from, to, i)) end
						end
						if kind ~= "bool" and not fields[i].wide then
							local expected = kind == "choice" and FDCP.RulesForm.CHOICE_W or FDCP.RulesForm.NUMBER_W
							eq(want:GetWidth(), expected, ("%s -> %s: row %d has the width of its kind"):format(from, to, i))
						end
					end
				end
			end
		end
	end)

	it("scroll with the mouse wheel, a whole row at a time, and say so with a bar", function()
		openSettings(SIZES.min)
		SW().root.sub:Select("rules")
		local form = SW().rules
		form.list:Select("readiness")
		local list = form.form
		truthy(list:ContentHeight() > list:GetHeight(), "the readiness page is longer than the view")
		truthy(list.thumb:IsShown(), "the scroll bar shows")
		falsy(list.rows[#form.fields]:IsShown(), "the last row is below the view")
		list:GetScript("OnMouseWheel")(list, -1)
		truthy(list:Offset() > 0, "the wheel scrolls")
		eq(list:Offset(), list.places[2].y, "a notch moves a row")
		for _ = 1, 30 do list:GetScript("OnMouseWheel")(list, -1) end
		truthy(list.rows[#form.fields]:IsShown(), "the last row can be reached")
		form.list:Select("upgrade")
		falsy(list.thumb:IsShown(), "a short page has no bar")
	end)
end)

describe("the disabled look of the buttons", function()
	before_boot(setup("enUS", 3))

	it("draws a primary button that is off flat and readable, and gives it its colours back", function()
		local b = FDCP.Widgets.Button(UIParent, { text = "Apply", style = "primary" })
		b:SetEnabled(false)
		eq(b:GetAlpha(), 1, "not faded: its text stays readable")
		local r, g, bl = FDCP.Theme.Color("text-3")
		local tr, tg, tb = b.label:GetTextColor()
		deepEq({ tr, tg, tb }, { r, g, bl }, "the text is text-3")
		r, g, bl = FDCP.Theme.Color("surface-3")
		tr, tg, tb = b.fill:GetVertexColor()
		deepEq({ tr, tg, tb }, { r, g, bl }, "the shape is surface-3")
		b:SetEnabled(true)
		r, g, bl = FDCP.Theme.Color("on-accent")
		tr, tg, tb = b.label:GetTextColor()
		deepEq({ tr, tg, tb }, { r, g, bl }, "on again: the text of the accent")
	end)

	it("widens a button whose text is longer than its width", function()
		local b = FDCP.Widgets.Button(UIParent, { text = "A very long caption for a small button", style = "secondary", width = 80 })
		truthy(b:GetWidth() >= b.label:GetStringWidth() + 28)
		b:SetLabel("Ok")
		eq(b:GetWidth(), 80, "back to its width with a short text")
	end)
end)
