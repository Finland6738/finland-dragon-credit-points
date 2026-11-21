-- Widgets: the first components of docs/specs/ui-style.md §3 — Button (primary, secondary, ghost, neon), Card, TitleBar,
-- Tabs with the underline indicator, Segmented (pill selector), Badge and the Dialog base (M1-7). Lua 5.1.
-- Every widget is made of ordinary frames and white textures tinted through UI/Theme.lua. Text is passed in already
-- translated by the caller (L[...]); a widget never contains a sentence. Unprotected frames only.
local ADDON_NAME, ns = ...
ns = ns or {}

local Widgets = {}
ns.Widgets = Widgets
if ns.addon then ns.addon.Widgets = Widgets end   -- also reachable from tests

local Theme = ns.Theme
local Assets = ns.Assets

local function gradientColor(token)
	local r, g, b, a = Theme.Color(token)
	if CreateColor then return CreateColor(r, g, b, a) end
	return { r = r, g = g, b = b, a = a }
end

-- --- Button -----------------------------------------------------------------------------------------------------------

-- Button styles: fill token, text token, and what else the style adds.
local BUTTON_STYLES = {
	primary   = { fill = "accent",    ink = "on-accent", gradient = true },
	secondary = { fill = "surface-3", ink = "text-1",    ring = "border" },
	ghost     = { fill = nil,         ink = "text-2",    ring = nil },
	neon      = { fill = "surface-1", ink = "text-1",    ring = "neon", glow = true },
}
Widgets.BUTTON_STYLES = BUTTON_STYLES

-- opts: text, style ("primary" | "secondary" | "ghost" | "neon"), width, height, onClick.
function Widgets.Button(parent, opts)
	opts = opts or {}
	local style = BUTTON_STYLES[opts.style or "secondary"] or BUTTON_STYLES.secondary
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(opts.width or 120, opts.height or 32)
	b.style = opts.style or "secondary"
	if style.fill then
		b.fill = Theme.Slice(b, "rr_fill_8", style.fill, "BACKGROUND")
		b.fill:SetAllPoints(b)
		if style.gradient then
			Theme.Call(b.fill, function(region)   -- amber -> coral, two colours (the spec: SetGradient)
				if region.SetGradient then region:SetGradient("HORIZONTAL", gradientColor("accent"), gradientColor("accent-2")) end
			end)
		end
	end
	if style.ring then
		b.ring = Theme.Slice(b, "rr_ring_8", style.ring, "BORDER")
		b.ring:SetAllPoints(b)
	end
	if style.glow then
		b.glow = Theme.Slice(b, "glow_s", "neon", "BACKGROUND", 0.5)
		b.glow:SetPoint("TOPLEFT", b, "TOPLEFT", -18, 18)
		b.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 18, -18)
		if b.glow.SetBlendMode and Theme.IsDark() then b.glow:SetBlendMode("ADD") end
	end
	-- hover 8 % and pressed 12 % white over the shape
	b.over = Theme.Slice(b, "rr_fill_8", nil, "ARTWORK")
	b.over:SetAllPoints(b)
	b.over:SetVertexColor(1, 1, 1, 0)
	b.label = Theme.NewText(b, "Button", style.ink)
	b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.label:SetText(opts.text or "")
	function b:SetLabel(text) self.label:SetText(text or "") end
	b:SetScript("OnEnter", function(self) if self:IsEnabled() then self.over:SetVertexColor(1, 1, 1, 0.08) end end)
	b:SetScript("OnLeave", function(self) self.over:SetVertexColor(1, 1, 1, 0) end)
	b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.over:SetVertexColor(1, 1, 1, 0.12) end end)
	b:SetScript("OnMouseUp", function(self) self.over:SetVertexColor(1, 1, 1, 0) end)
	if opts.onClick then b:SetScript("OnClick", opts.onClick) end
	return b
end

-- --- Card -------------------------------------------------------------------------------------------------------------

-- A card: surface-1 fill, subtle ring (strong on hover when `hover`), radius 18, optional shadow. Four regions at most.
function Widgets.Card(parent, opts)
	opts = opts or {}
	local c = CreateFrame("Frame", nil, parent)
	c:SetSize(opts.width or 200, opts.height or 100)
	c.parts = Theme.Panel(c, { radius = 18, fill = opts.fill or "surface-1", border = "border-subtle", shadow = opts.shadow })
	if opts.hover then
		c:EnableMouse(true)
		c:SetScript("OnEnter", function(self) Theme.Tint(self.parts.ring, "border-strong") end)
		c:SetScript("OnLeave", function(self) Theme.Tint(self.parts.ring, "border-subtle") end)
	end
	return c
end

-- --- Badge ------------------------------------------------------------------------------------------------------------

local BADGE_TONES = { accent = "accent-text", ok = "ok", warn = "warn", err = "err", neutral = "text-2" }
Widgets.BADGE_TONES = BADGE_TONES

-- A pill (24 high) whose width follows its text; the fill is the tone's colour at low alpha, the text the tone's.
function Widgets.Badge(parent, text, tone)
	local token = BADGE_TONES[tone or "neutral"] or BADGE_TONES.neutral
	local f = CreateFrame("Frame", nil, parent)
	f.fill = Theme.Slice(f, "rr_fill_12", token, "BACKGROUND", 0.16)
	f.fill:SetAllPoints(f)
	f.label = Theme.NewText(f, "Th", token)
	f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
	function f:SetBadge(newText, newTone)
		local t = BADGE_TONES[newTone or tone or "neutral"] or token
		Theme.Tint(self.fill, t, 0.16)
		Theme.Text(self.label, t)
		self.label:SetText(newText or "")
		self:SetSize(math.max(24, self.label:GetStringWidth() + 20), 24)
	end
	f:SetBadge(text, tone)
	return f
end

-- --- Tabs (underline) -------------------------------------------------------------------------------------------------

-- tabs: { { id = "roster", text = "Roster" }, ... }. The active tab is text-1 with a 2 pt accent bar under it; the others
-- text-3 (text-2 on hover). :Select(id), :SetTabShown(id, bool), :Active(). onSelect(id) runs after a change.
function Widgets.Tabs(parent, tabs, onSelect)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(44)
	bar.buttons, bar.order, bar.hidden = {}, {}, {}
	bar.line = bar:CreateTexture(nil, "BORDER")
	Theme.Fill(bar.line, "border-subtle")
	bar.line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
	bar.line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	bar.line:SetHeight(Theme.Px(1))
	bar.indicator = bar:CreateTexture(nil, "ARTWORK")
	Theme.Fill(bar.indicator, "accent")
	bar.indicator:SetHeight(2)
	bar.indicator:Hide()

	local function layout()
		local x = 0
		for _, id in ipairs(bar.order) do
			local b = bar.buttons[id]
			if bar.hidden[id] then
				b:Hide()
			else
				b:Show()
				b:ClearAllPoints()
				b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
				x = x + b:GetWidth() + 4
			end
		end
		local active = bar.active and bar.buttons[bar.active]
		if active and not bar.hidden[bar.active] then
			bar.indicator:ClearAllPoints()
			bar.indicator:SetPoint("BOTTOMLEFT", active, "BOTTOMLEFT", 8, 0)
			bar.indicator:SetPoint("BOTTOMRIGHT", active, "BOTTOMRIGHT", -8, 0)
			bar.indicator:Show()
		else
			bar.indicator:Hide()
		end
	end

	local function paint()
		for id, b in pairs(bar.buttons) do
			Theme.Text(b.label, id == bar.active and "text-1" or "text-3")
		end
	end

	function bar:Select(id)
		if not self.buttons[id] or self.hidden[id] then return false end
		local changed = self.active ~= id
		self.active = id
		paint(); layout()
		if changed and onSelect then onSelect(id) end
		return true
	end
	function bar:Active() return self.active end
	function bar:SetTabShown(id, shown)
		self.hidden[id] = not shown or nil
		if not shown and self.active == id then
			for _, other in ipairs(self.order) do
				if not self.hidden[other] then self:Select(other) break end
			end
		end
		layout()
	end
	function bar:Layout() layout() end

	for _, t in ipairs(tabs) do
		local b = CreateFrame("Button", nil, bar)
		b.id = t.id
		b.label = Theme.NewText(b, "Tab", "text-3")
		b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
		b.label:SetText(t.text or "")
		b:SetSize(math.max(64, b.label:GetStringWidth() + 32), 44)
		b:SetScript("OnClick", function() bar:Select(t.id) end)
		b:SetScript("OnEnter", function(self) if bar.active ~= self.id then Theme.Text(self.label, "text-2") end end)
		b:SetScript("OnLeave", function(self) if bar.active ~= self.id then Theme.Text(self.label, "text-3") end end)
		bar.buttons[t.id] = b
		bar.order[#bar.order + 1] = t.id
	end
	layout()
	return bar
end

-- --- Segmented (pill selector) ----------------------------------------------------------------------------------------

-- items: { { id, text } }. A surface-2 pill with the selected segment raised. :Select(id), :Active().
function Widgets.Segmented(parent, items, onSelect)
	local seg = CreateFrame("Frame", nil, parent)
	seg:SetHeight(32)
	seg.fill = Theme.Slice(seg, "rr_fill_12", "surface-2", "BACKGROUND")
	seg.fill:SetAllPoints(seg)
	seg.ring = Theme.Slice(seg, "rr_ring_12", "border", "BORDER")
	seg.ring:SetAllPoints(seg)
	seg.thumb = Theme.Slice(seg, "rr_fill_12", "raised", "ARTWORK")
	seg.thumb:Hide()
	seg.buttons, seg.order = {}, {}

	function seg:Select(id)
		local b = self.buttons[id]
		if not b then return false end
		local changed = self.active ~= id
		self.active = id
		self.thumb:ClearAllPoints()
		self.thumb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
		self.thumb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
		self.thumb:Show()
		for other, ob in pairs(self.buttons) do Theme.Text(ob.label, other == id and "text-1" or "text-3") end
		if changed and onSelect then onSelect(id) end
		return true
	end
	function seg:Active() return self.active end
	-- No segment selected (the thumb goes away).
	function seg:Clear()
		self.active = nil
		self.thumb:Hide()
		for _, ob in pairs(self.buttons) do Theme.Text(ob.label, "text-3") end
	end
	-- Locked: the segments stop answering clicks and dim; the selection stays visible.
	function seg:SetEnabled(enabled)
		self.enabled = enabled ~= false
		self:SetAlpha(self.enabled and 1 or 0.55)
		for _, ob in pairs(self.buttons) do ob:SetEnabled(self.enabled) end
	end

	local x = 4
	for _, item in ipairs(items) do
		local b = CreateFrame("Button", nil, seg)
		b.label = Theme.NewText(b, "BodyMedium", "text-3")
		b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
		b.label:SetText(item.text or "")
		b:SetSize(math.max(48, b.label:GetStringWidth() + 24), 24)
		b:SetPoint("LEFT", seg, "LEFT", x, 0)
		x = x + b:GetWidth() + 2
		b:SetScript("OnClick", function() seg:Select(item.id) end)
		seg.buttons[item.id] = b
		seg.order[#seg.order + 1] = item.id
	end
	seg:SetWidth(x + 2)
	return seg
end

-- --- Chip (label) ------------------------------------------------------------------------------------------------------

-- A pill with a border (28 high), filled with the accent when selected (docs/ANALISI.md §9.2, the site's filter chip).
-- opts: text, onClick(chip), height, font (a Theme font id, default BodyMedium), pad (text padding, default 28).
-- :SetSelected(bool), :IsSelected(), :SetLabel(text), :SetEnabled(bool).
function Widgets.Chip(parent, opts)
	opts = opts or {}
	local c = CreateFrame("Button", nil, parent)
	c:SetHeight(opts.height or 28)
	c.fill = Theme.Slice(c, "rr_fill_12", "surface-2", "BACKGROUND", 0)
	c.fill:SetAllPoints(c)
	c.ring = Theme.Slice(c, "rr_ring_12", "border", "BORDER")
	c.ring:SetAllPoints(c)
	c.label = Theme.NewText(c, opts.font or "BodyMedium", "text-2")
	c.label:SetPoint("CENTER", c, "CENTER", 0, 0)
	function c:Paint()
		if self.selected then
			Theme.Tint(self.fill, "accent", 1)
			Theme.Tint(self.ring, "accent")
			Theme.Text(self.label, "on-accent")
		else
			Theme.Tint(self.fill, "surface-2", self.hot and 1 or 0)
			Theme.Tint(self.ring, self.hot and "border-strong" or "border")
			Theme.Text(self.label, "text-2")
		end
	end
	function c:SetLabel(text)
		self.label:SetText(text or "")
		self:SetWidth(math.max(32, self.label:GetStringWidth() + (opts.pad or 28)))
	end
	function c:SetSelected(selected) self.selected = selected and true or false; self:Paint() end
	function c:IsSelected() return self.selected == true end
	local setEnabled = c.SetEnabled
	function c:SetEnabled(enabled)
		setEnabled(self, enabled and true or false)
		self:SetAlpha(enabled and 1 or 0.45)
	end
	c:SetScript("OnEnter", function(self) if self:IsEnabled() then self.hot = true; self:Paint() end end)
	c:SetScript("OnLeave", function(self) self.hot = false; self:Paint() end)
	if opts.onClick then c:SetScript("OnClick", function(self) if self:IsEnabled() then opts.onClick(self) end end) end
	c:SetLabel(opts.text)
	c:Paint()
	return c
end

-- --- TitleBar ---------------------------------------------------------------------------------------------------------

-- The window's title bar: 52 pt, surface-1, round logo, title in the display font, mono subtitle, close button.
-- opts: title, subtitle, closeLabel (accessibility text), onClose.
function Widgets.TitleBar(parent, opts)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(52)
	bar.fill = Theme.Slice(bar, "rr_fill_12", "surface-1", "BACKGROUND")
	bar.fill:SetAllPoints(bar)
	bar.line = bar:CreateTexture(nil, "BORDER")
	Theme.Fill(bar.line, "border-subtle")
	bar.line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 12, 0)
	bar.line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -12, 0)
	bar.line:SetHeight(Theme.Px(1))

	bar.logoGlow = Theme.Slice(bar, "glow_s", "accent", "ARTWORK", 0.35)
	bar.logoGlow:SetSize(64, 64)
	bar.logoGlow:SetPoint("LEFT", bar, "LEFT", 6, 0)
	if bar.logoGlow.SetBlendMode and Theme.IsDark() then bar.logoGlow:SetBlendMode("ADD") end
	bar.logo = bar:CreateTexture(nil, "OVERLAY")
	bar.logo:SetTexture(Assets.textures.logo_64.path)
	bar.logo:SetSize(32, 32)
	bar.logo:SetPoint("LEFT", bar, "LEFT", 20, 0)
	if bar.logo.SetMaskTexture then bar.logo:SetMaskTexture(Assets.textures.circle.path) end

	bar.title = Theme.NewText(bar, "Display", "text-1")
	bar.title:SetPoint("TOPLEFT", bar, "TOPLEFT", 64, -9)
	bar.title:SetText(opts.title or "")
	bar.subtitle = Theme.NewText(bar, "MonoSmall", "text-3")
	bar.subtitle:SetPoint("TOPLEFT", bar.title, "BOTTOMLEFT", 0, -3)
	bar.subtitle:SetText(opts.subtitle or "")

	bar.close = CreateFrame("Button", nil, bar)
	bar.close:SetSize(28, 28)
	bar.close:SetPoint("RIGHT", bar, "RIGHT", -14, 0)
	bar.close.bg = Theme.Slice(bar.close, "rr_fill_8", "surface-3", "BACKGROUND", 0)
	bar.close.bg:SetAllPoints(bar.close)
	bar.close.icon = bar.close:CreateTexture(nil, "OVERLAY")
	bar.close.icon:SetTexture(Assets.textures.icons.path)
	bar.close.icon:SetTexCoord(Assets.IconCoords("cross"))
	bar.close.icon:SetSize(16, 16)
	bar.close.icon:SetPoint("CENTER")
	Theme.Tint(bar.close.icon, "text-2")
	bar.close:SetScript("OnEnter", function(self) Theme.Tint(self.bg, "surface-3", 1) end)
	bar.close:SetScript("OnLeave", function(self) Theme.Tint(self.bg, "surface-3", 0) end)
	if opts.onClose then bar.close:SetScript("OnClick", opts.onClose) end
	return bar
end

-- --- Dialog -----------------------------------------------------------------------------------------------------------

-- A modal base: a dark veil (no blur: the engine cannot) over `parent` with a centred card on the DIALOG strata.
-- Esc closes it (it is added to UISpecialFrames under `name`). :Open(), :Close(), .card, .content.
function Widgets.Dialog(parent, name, opts)
	opts = opts or {}
	local d = CreateFrame("Frame", name, parent or UIParent)
	d:SetAllPoints(parent or UIParent)
	d:SetFrameStrata("DIALOG")
	d:EnableMouse(true)   -- the veil swallows clicks
	d.veil = d:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(d.veil, "scrim")
	d.veil:SetAllPoints(d)
	d.card = CreateFrame("Frame", nil, d)
	d.card:SetSize(opts.width or 420, opts.height or 220)
	d.card:SetPoint("CENTER", d, "CENTER", 0, 0)
	d.card.parts = Theme.Panel(d.card, { radius = 18, fill = "surface-1", border = "border", shadow = true })
	d.content = d.card
	d:Hide()
	if name then
		for _, n in ipairs(UISpecialFrames) do if n == name then name = nil break end end
		if name then UISpecialFrames[#UISpecialFrames + 1] = name end
	end
	function d:Open() self:Show() end
	function d:Close() self:Hide() end
	return d
end

-- --- EditBox ----------------------------------------------------------------------------------------------------------

-- A one-line field: surface-2 fill, 1 pt ring (accent while it has the keyboard). opts: width, height, maxLetters,
-- onChange(text) after every edit. :GetText(), :SetText(text) (through .edit), :Clear(). The edit box itself is `.edit`.
function Widgets.EditBox(parent, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(opts.width or 120, opts.height or 28)
	f.fill = Theme.Slice(f, "rr_fill_8", "surface-2", "BACKGROUND")
	f.fill:SetAllPoints(f)
	f.ring = Theme.Slice(f, "rr_ring_8", "border", "BORDER")
	f.ring:SetAllPoints(f)
	local e = CreateFrame("EditBox", nil, f)
	e:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -2)
	e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 2)
	e:SetAutoFocus(false)
	if Theme.fontObjects.Body then e:SetFontObject(Theme.fontObjects.Body) end
	if opts.maxLetters then e:SetMaxLetters(opts.maxLetters) end
	Theme.Text(e, "text-1")
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEditFocusGained", function() Theme.Tint(f.ring, "accent") end)
	e:SetScript("OnEditFocusLost", function() Theme.Tint(f.ring, "border") end)
	e:SetScript("OnTextChanged", function(self, user) if opts.onChange then opts.onChange(self:GetText(), user) end end)
	f.edit = e
	function f:GetText() return self.edit:GetText() end
	function f:SetText(text) self.edit:SetText(text or "") end
	function f:Clear() self.edit:SetText("") end
	return f
end

-- --- ChoiceList -------------------------------------------------------------------------------------------------------

-- A list of single-choice rows (a radio list: no UIDropDownMenu, which taints, docs/specs/ui-style.md §3) inside a
-- surface-2 field. choices = { { id, text, token? } }; `rows` rows show at once and the mouse wheel scrolls the rest.
-- opts: rows (6), rowHeight (24), width, onSelect(id). :SetChoices(list), :Select(id), :Selected(), :Clear(), :Count().
function Widgets.ChoiceList(parent, opts)
	opts = opts or {}
	local rows, rowH = opts.rows or 6, opts.rowHeight or 24
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(opts.width or 240, rows * rowH + 8)
	f.fill = Theme.Slice(f, "rr_fill_8", "surface-2", "BACKGROUND")
	f.fill:SetAllPoints(f)
	f.ring = Theme.Slice(f, "rr_ring_8", "border", "BORDER")
	f.ring:SetAllPoints(f)
	f.choices, f.offset, f.rowH, f.rowsShown = {}, 0, rowH, rows
	f:EnableMouseWheel(true)
	f.rows = {}
	for i = 1, rows do
		local b = CreateFrame("Button", nil, f)
		b:SetHeight(rowH)
		b:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4 - (i - 1) * rowH)
		b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4 - (i - 1) * rowH)
		b.mark = b:CreateTexture(nil, "BACKGROUND")
		Theme.Fill(b.mark, "raised", 0)
		b.mark:SetAllPoints(b)
		b.dot = b:CreateTexture(nil, "ARTWORK")
		Theme.Fill(b.dot, "accent", 0)
		b.dot:SetSize(6, 6)
		b.dot:SetPoint("LEFT", b, "LEFT", 8, 0)
		b.label = Theme.NewText(b, "Body", "text-2")
		b.label:SetPoint("LEFT", b, "LEFT", 22, 0)
		b.label:SetPoint("RIGHT", b, "RIGHT", -6, 0)
		b.label:SetJustifyH("LEFT")
		b:SetScript("OnClick", function(self) if self.choice then f:Select(self.choice.id) end end)
		b:Hide()
		f.rows[i] = b
	end
	local function paint()
		for i, b in ipairs(f.rows) do
			local c = f.choices[f.offset + i]
			b.choice = c
			if c then
				local on = f.selected ~= nil and c.id == f.selected
				b.label:SetText(c.text or "")
				Theme.Text(b.label, on and "text-1" or c.token or "text-2")
				Theme.Fill(b.mark, "raised", on and 1 or 0)
				Theme.Fill(b.dot, "accent", on and 1 or 0)
				b:Show()
			else
				b:Hide()
			end
		end
	end
	function f:SetChoices(list)
		self.choices = list or {}
		self.offset = 0
		if self.selected ~= nil then
			local found = false
			for _, c in ipairs(self.choices) do if c.id == self.selected then found = true end end
			if not found then self.selected = nil end
		end
		paint()
	end
	function f:Select(id)
		local found = false
		for _, c in ipairs(self.choices) do if c.id == id then found = true end end
		if not found then return false end
		local changed = self.selected ~= id
		self.selected = id
		paint()
		if changed and opts.onSelect then opts.onSelect(id) end
		return true
	end
	function f:Selected() return self.selected end
	function f:Clear() self.selected = nil; paint() end
	function f:Count() return #self.choices end
	function f:Scroll(delta)
		self.offset = math.min(math.max(self.offset + delta, 0), math.max(#self.choices - rows, 0))
		paint()
	end
	f:SetScript("OnMouseWheel", function(self, delta) self:Scroll(-delta * 2) end)
	return f
end
