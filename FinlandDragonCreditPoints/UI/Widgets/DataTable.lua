-- DataTable: the table of docs/specs/ui-style.md §3 (M3-7): a header on surface-2 **outside** the list, sortable columns
-- (the sorted one in accent-text), a fixed first and last column with the flexible ones between them, and rows recycled
-- from a pool (a fixed number of row frames that are re-filled while the list scrolls with the mouse wheel). Lua 5.1;
-- ordinary frames. Blizzard's ScrollBox is not used: the spec allows the pool, and it works the same on every client.
--
-- columns: { { id, title (translated), width? (fixed, in points), flex? (share of the free width), align? "LEFT" | "RIGHT" |
--   "CENTER", sortable? (default true), mono? (numbers), text = function(data) -> string, token? = function(data) -> token,
--   value? = function(data) -> sort key (default: the text), render? = function(cell, data, row) (custom cell) } }
-- opts: { rowHeight (30), headerHeight (28), pool (rows made, 40), onRowClick(data, row), rowSetup(row) (a row is created),
--   rowUpdate(row, data) (a row is filled) }
-- Methods: :SetData(list), :SortBy(id, descending), :Refresh(), :SetOffset(n), :VisibleRows(), :GetData(), :GetSort().
local ADDON_NAME, ns = ...
ns = ns or {}
local Theme, Widgets = ns.Theme, ns.Widgets

local floor, max, min = math.floor, math.max, math.min

local function textOf(col, data)
	local v = col.text and col.text(data)
	return v == nil and "" or tostring(v)
end

local function keyOf(col, data)
	if col.value then return col.value(data) end
	local v = textOf(col, data)
	return tonumber(v) or v:lower()
end

function Widgets.DataTable(parent, columns, opts)
	opts = opts or {}
	local rowH, headH = opts.rowHeight or 30, opts.headerHeight or 28
	local t = CreateFrame("Frame", nil, parent)
	t.columns, t.data, t.sorted, t.rows = columns, {}, {}, {}
	t.offset, t.rowH, t.headH = 0, rowH, headH
	t.sortId, t.sortDesc = nil, false

	t.head = CreateFrame("Frame", nil, t)
	t.head:SetHeight(headH)
	t.head:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
	t.head:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, 0)
	t.head.fill = Theme.Slice(t.head, "rr_fill_8", "surface-2", "BACKGROUND")
	t.head.fill:SetAllPoints(t.head)
	t.list = CreateFrame("Frame", nil, t)
	t.list:SetPoint("TOPLEFT", t.head, "BOTTOMLEFT", 0, -2)
	t.list:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
	t.list:EnableMouseWheel(true)
	t.empty = Theme.NewText(t.list, "Body", "text-3")
	t.empty:SetPoint("TOPLEFT", t.list, "TOPLEFT", 12, -12)

	-- the column positions: the fixed ones keep their width, the flexible ones share what is left
	local function widths()
		local total = (t:GetWidth() or 0) > 50 and t:GetWidth() or 800
		local fixed, flex = 0, 0
		for _, c in ipairs(columns) do
			if c.width then fixed = fixed + c.width else flex = flex + (c.flex or 1) end
		end
		local free = max(total - fixed - 16, 0)
		local out, x = {}, 8
		for i, c in ipairs(columns) do
			local w = c.width or (flex > 0 and floor(free * (c.flex or 1) / flex) or 0)
			out[i] = { x = x, w = w }
			x = x + w
		end
		return out
	end

	local function place(fs, frame, col, pos, y)
		fs:ClearAllPoints()
		fs:SetWidth(max(pos.w - 8, 1))
		fs:SetJustifyH(col.align or "LEFT")
		fs:SetPoint("LEFT", frame, "LEFT", pos.x, y or 0)
	end

	-- header
	t.heads = {}
	for i, c in ipairs(columns) do
		local b = CreateFrame("Button", nil, t.head)
		b:SetHeight(headH)
		b.label = Theme.NewText(b, "Th", "text-3")
		b.label:SetAllPoints(b)
		b.label:SetJustifyH(c.align or "LEFT")
		b.label:SetText((c.title or ""):upper())
		b.col = c
		if c.sortable ~= false then b:SetScript("OnClick", function() t:SortBy(c.id) end) end
		t.heads[i] = b
	end

	function t:Layout()
		local pos = widths()
		self.pos = pos
		for i, b in ipairs(self.heads) do
			b:ClearAllPoints()
			b:SetPoint("LEFT", self.head, "LEFT", pos[i].x, 0)
			b:SetWidth(max(pos[i].w - 4, 1))
		end
		for _, r in ipairs(self.rows) do
			for i, fs in ipairs(r.cells) do place(fs, r, columns[i], pos[i]) end
		end
	end

	local function newRow(i)
		local r = CreateFrame("Button", nil, t.list)
		r:SetHeight(rowH)
		r:SetPoint("TOPLEFT", t.list, "TOPLEFT", 0, -(i - 1) * rowH)
		r:SetPoint("TOPRIGHT", t.list, "TOPRIGHT", 0, -(i - 1) * rowH)
		r.hover = r:CreateTexture(nil, "BACKGROUND")
		Theme.Fill(r.hover, "surface-2", 0)
		r.hover:SetAllPoints(r)
		r.line = r:CreateTexture(nil, "BORDER")
		Theme.Fill(r.line, "border-subtle")
		r.line:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
		r.line:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
		r.line:SetHeight(Theme.Px(1))
		r.cells = {}
		for ci, c in ipairs(columns) do
			r.cells[ci] = Theme.NewText(r, c.mono and "Mono" or "Body", "text-1")
		end
		r:SetScript("OnEnter", function(self) Theme.Fill(self.hover, "surface-2", 1) end)
		r:SetScript("OnLeave", function(self) Theme.Fill(self.hover, "surface-2", 0) end)
		r:SetScript("OnClick", function(self) if opts.onRowClick and self.data then opts.onRowClick(self.data, self) end end)
		if opts.rowSetup then opts.rowSetup(r) end
		r:Hide()
		return r
	end
	for i = 1, opts.pool or 40 do t.rows[i] = newRow(i) end

	function t:Capacity()
		local h = self.list:GetHeight() or 0
		if h < rowH then h = rowH * 14 end
		return min(#self.rows, max(floor(h / rowH), 1))
	end

	function t:SortBy(id, descending)
		local col
		for _, c in ipairs(columns) do if c.id == id then col = c end end
		if not col then return false end
		if descending == nil then descending = (self.sortId == id) and not self.sortDesc or false end
		self.sortId, self.sortDesc = id, descending
		local order = {}
		for i, d in ipairs(self.data) do order[i] = { d = d, i = i, k = keyOf(col, d) } end
		table.sort(order, function(a, b)
			if a.k ~= b.k then
				local ta, tb = type(a.k), type(b.k)
				local less
				if ta ~= tb then less = ta == "number" else less = a.k < b.k end
				if descending then return not less end
				return less
			end
			return a.i < b.i
		end)
		self.sorted = {}
		for i, o in ipairs(order) do self.sorted[i] = o.d end
		for i, b in ipairs(self.heads) do
			local active = columns[i].id == id
			Theme.Text(b.label, active and "accent-text" or "text-3")
		end
		self.offset = 0
		self:Refresh()
		return true
	end

	function t:GetSort() return self.sortId, self.sortDesc end
	function t:GetData() return self.sorted end

	function t:SetData(list)
		self.data = list or {}
		if self.sortId then self:SortBy(self.sortId, self.sortDesc) else
			self.sorted = {}
			for i, d in ipairs(self.data) do self.sorted[i] = d end
			self.offset = 0
			self:Refresh()
		end
	end

	function t:SetOffset(n)
		local top = max(#self.sorted - self:Capacity(), 0)
		self.offset = min(max(n, 0), top)
		self:Refresh()
	end

	function t:Refresh()
		if not self.pos then self:Layout() end
		local cap = self:Capacity()
		self.offset = min(self.offset, max(#self.sorted - cap, 0))
		for i, r in ipairs(self.rows) do
			local data = i <= cap and self.sorted[self.offset + i] or nil
			r.data = data
			if data then
				for ci, c in ipairs(columns) do
					local fs = r.cells[ci]
					if c.render then
						c.render(fs, data, r)
					else
						fs:SetText(textOf(c, data))
						Theme.Text(fs, c.token and c.token(data) or "text-1")
					end
				end
				if opts.rowUpdate then opts.rowUpdate(r, data) end
				r:Show()
			else
				r:Hide()
			end
		end
		self.empty:SetShown(#self.sorted == 0)
	end

	function t:VisibleRows()
		local out = {}
		for _, r in ipairs(self.rows) do if r:IsShown() then out[#out + 1] = r end end
		return out
	end

	function t:SetEmptyText(text) self.empty:SetText(text or "") end

	t.list:SetScript("OnMouseWheel", function(_, delta) t:SetOffset(t.offset - delta * 3) end)
	t:SetScript("OnSizeChanged", function() t:Layout(); t:Refresh() end)
	t:Layout()
	return t
end
