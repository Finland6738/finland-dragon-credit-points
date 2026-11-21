-- ThinBar: the 4 pt bar of docs/specs/ui-style.md §3 (roster columns, progress cards): a subtle track and a fill with the
-- two-colour gradient of the theme (the first and third colour of `grad`, here accent -> accent-2). M3-7. Lua 5.1.
--   bar = Widgets.ThinBar(parent, { height = 4 }); bar:SetFraction(0..1); bar:GetFraction()
local ADDON_NAME, ns = ...
ns = ns or {}
local Theme, Widgets = ns.Theme, ns.Widgets

local function color(token)
	local r, g, b, a = Theme.Color(token)
	if CreateColor then return CreateColor(r, g, b, a) end
	return { r = r, g = g, b = b, a = a }
end

function Widgets.ThinBar(parent, opts)
	opts = opts or {}
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(opts.height or 4)
	bar.track = bar:CreateTexture(nil, "BACKGROUND")
	Theme.Fill(bar.track, "border-subtle")
	bar.track:SetAllPoints(bar)
	bar.fill = bar:CreateTexture(nil, "ARTWORK")
	Theme.Fill(bar.fill, "accent")
	Theme.Call(bar.fill, function(region)
		if region.SetGradient then region:SetGradient("HORIZONTAL", color("accent"), color("accent-2")) end
	end)
	bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
	bar.fraction = 0

	local function paint()
		local w = bar:GetWidth() or 0
		if w <= 1 then w = opts.width or 200 end
		if bar.fraction <= 0 then bar.fill:Hide() else
			bar.fill:SetWidth(math.max(w * bar.fraction, 1))
			bar.fill:Show()
		end
	end
	function bar:SetFraction(f)
		f = tonumber(f) or 0
		self.fraction = math.min(math.max(f, 0), 1)
		paint()
	end
	function bar:GetFraction() return self.fraction end
	bar:SetScript("OnSizeChanged", paint)
	return bar
end
