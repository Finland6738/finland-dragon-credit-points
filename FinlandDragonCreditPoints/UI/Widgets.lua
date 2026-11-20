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
