-- MainWindow: the one main window (docs/specs/ui-style.md §6): a title bar, six underline tabs (Roster, Credits,
-- Progress, Loot, History, Settings) and a page for each, empty until its step arrives (M1-7). Movable, resizable from a minimum size, position
-- and size remembered per character, Esc closes it, /fdcp and the minimap button toggle it. Lua 5.1; unprotected frames.
local ADDON_NAME, ns = ...
ns = ns or {}

local MainWindow = {}
ns.MainWindow = MainWindow
if ns.addon then ns.addon.MainWindow = MainWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

local FRAME_NAME = "FDCPMainFrame"
MainWindow.FRAME_NAME = FRAME_NAME
MainWindow.DEFAULT_W, MainWindow.DEFAULT_H = 960, 640
MainWindow.MIN_W, MainWindow.MIN_H = 900, 560
MainWindow.MAX_W, MainWindow.MAX_H = 1400, 900

-- The tabs in order; `key` is a locale key. Later steps fill the pages (docs/specs/ui-style.md §6).
MainWindow.TABS = {
	{ id = "roster",   key = "TAB_ROSTER" },
	{ id = "credits",  key = "TAB_CREDITS" },
	{ id = "progress", key = "TAB_PROGRESS" },
	{ id = "loot",     key = "TAB_LOOT" },
	{ id = "history",  key = "TAB_HISTORY" },
	{ id = "settings", key = "TAB_SETTINGS" },
}

local function charData()
	local Config = ns.Config
	return Config and Config.char
end

-- The saved placement: { point, x, y, w, h } or nil.
function MainWindow.LoadPlacement()
	local c = charData()
	local p = c and c.window
	if type(p) ~= "table" then return nil end
	if type(p.point) ~= "string" or type(p.x) ~= "number" or type(p.y) ~= "number" then return nil end
	local w = math.min(MainWindow.MAX_W, math.max(MainWindow.MIN_W, tonumber(p.w) or MainWindow.DEFAULT_W))
	local h = math.min(MainWindow.MAX_H, math.max(MainWindow.MIN_H, tonumber(p.h) or MainWindow.DEFAULT_H))
	return { point = p.point, x = p.x, y = p.y, w = w, h = h }
end

function MainWindow:SavePlacement()
	local f, c = self.frame, charData()
	if not f or not c then return end
	if ns.Config and ns.Config:IsReadOnly() then return end
	local point, _, _, x, y = f:GetPoint(1)
	if not point then return end
	c.window = { point = point, x = x, y = y, w = f:GetWidth(), h = f:GetHeight() }
end

-- Builds the window once (hidden). Returns the frame.
function MainWindow:Build()
	if self.frame then return self.frame end
	Theme.SetupFonts()
	Theme.Load()

	local f = CreateFrame("Frame", FRAME_NAME, UIParent)
	self.frame = f
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	f:SetResizeBounds(MainWindow.MIN_W, MainWindow.MIN_H, MainWindow.MAX_W, MainWindow.MAX_H)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f.parts = Theme.Panel(f, { radius = 12, fill = "bg", border = "border", shadow = true })

	local placement = MainWindow.LoadPlacement()
	if placement then
		f:SetSize(placement.w, placement.h)
		f:SetPoint(placement.point, UIParent, placement.point, placement.x, placement.y)
	else
		f:SetSize(MainWindow.DEFAULT_W, MainWindow.DEFAULT_H)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end

	f.titleBar = Widgets.TitleBar(f, {
		title = L["WINDOW_TITLE"], subtitle = L["WINDOW_SUBTITLE"], onClose = function() MainWindow:Close() end,
	})
	f.titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.titleBar:EnableMouse(true)
	f.titleBar:RegisterForDrag("LeftButton")
	local function startMoving() f:StartMoving() end
	local function stopMoving() f:StopMovingOrSizing(); MainWindow:SavePlacement() end
	f.titleBar:SetScript("OnDragStart", startMoving)
	f.titleBar:SetScript("OnDragStop", stopMoving)
	f:SetScript("OnDragStart", startMoving)
	f:SetScript("OnDragStop", stopMoving)

	-- tabs
	local tabs = {}
	for _, t in ipairs(MainWindow.TABS) do tabs[#tabs + 1] = { id = t.id, text = L[t.key] } end
	f.tabs = Widgets.Tabs(f, tabs, function(id) MainWindow:ShowPage(id) end)
	f.tabs:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -52)
	f.tabs:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -52)

	-- pages: an empty page each (a title and one line), filled by the steps named in the spec
	f.pages = {}
	for _, t in ipairs(MainWindow.TABS) do
		local page = CreateFrame("Frame", nil, f)
		page.id = t.id
		page:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -104)
		page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 20)
		page:Hide()
		page.eyebrow = Theme.NewText(page, "Eyebrow", "accent-text")
		page.eyebrow:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -12)
		page.eyebrow:SetText(L[t.key]:upper())
		page.empty = Theme.NewText(page, "Body", "text-3")
		page.empty:SetPoint("TOPLEFT", page.eyebrow, "BOTTOMLEFT", 0, -8)
		page.empty:SetText(L["PAGE_EMPTY"])
		f.pages[t.id] = page
	end

	-- Roster (M3-7): the roster page hosts the sub-tabs Pool, Night and Addon, its own placeholder goes away
	if ns.RosterWindow then
		f.pages.roster.eyebrow:Hide()
		f.pages.roster.empty:Hide()
		ns.RosterWindow:Build(f.pages.roster, f.titleBar)
	end

	-- Credits (M3-8): the table of the season's credits replaces the empty page
	if ns.CreditsWindow then
		f.pages.credits.eyebrow:Hide()
		f.pages.credits.empty:Hide()
		ns.CreditsWindow:Build(f.pages.credits)
	end

	-- Progress (M3-8b): the first kills per instance and guild replace the empty page
	if ns.ProgressWindow then
		f.pages.progress.eyebrow:Hide()
		f.pages.progress.empty:Hide()
		ns.ProgressWindow:Build(f.pages.progress)
	end

	-- Loot (M4-5): the master looter's session replaces the empty page
	if ns.MLSession then
		f.pages.loot.eyebrow:Hide()
		f.pages.loot.empty:Hide()
		ns.MLSession:Build(f.pages.loot, f)
	end

	-- History (M6-1): the nights, the member and the item views replace the empty page
	if ns.HistoryWindow then
		f.pages.history.eyebrow:Hide()
		f.pages.history.empty:Hide()
		ns.HistoryWindow:Build(f.pages.history)
	end

	-- resize grip (bottom right)
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(18, 18)
	grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
	grip.icon = grip:CreateTexture(nil, "OVERLAY")
	grip.icon:SetTexture(ns.Assets.textures.icons.path)
	grip.icon:SetTexCoord(ns.Assets.IconCoords("dashed"))
	grip.icon:SetAllPoints(grip)
	Theme.Tint(grip.icon, "text-3", 0.6)
	grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); MainWindow:SavePlacement() end)
	f.grip = grip

	-- Esc closes the window
	local present = false
	for _, n in ipairs(UISpecialFrames) do if n == FRAME_NAME then present = true end end
	if not present then UISpecialFrames[#UISpecialFrames + 1] = FRAME_NAME end

	f:Hide()
	f.tabs:Select("roster")
	return f
end

function MainWindow:ShowPage(id)
	local f = self.frame
	if not f then return end
	for pid, page in pairs(f.pages) do page:SetShown(pid == id) end
	if id == "credits" and ns.CreditsWindow then ns.CreditsWindow:Refresh() end
	if id == "progress" and ns.ProgressWindow then ns.ProgressWindow:Refresh() end
	if id == "history" and ns.HistoryWindow then ns.HistoryWindow:Refresh() end
	if id == "loot" and ns.MLSession and ns.MLSession.root then ns.MLSession:Refresh() end
end

function MainWindow:SelectTab(id)
	self:Build()
	return self.frame.tabs:Select(id)
end

function MainWindow:ActiveTab()
	return self.frame and self.frame.tabs:Active()
end

function MainWindow:SetTabVisible(id, shown)
	self:Build()
	self.frame.tabs:SetTabShown(id, shown)
end

function MainWindow:IsShown() return self.frame ~= nil and self.frame:IsShown() end

function MainWindow:Open(tab)
	self:Build()
	-- a loot session runs on this client: the window opens on the Loot tab (docs/specs/ui-style.md §6)
	if not tab and not self:IsShown() and ns.SessionController and ns.SessionController:IsHost() then tab = "loot" end
	if tab then self.frame.tabs:Select(tab) end
	self.frame:Show()
	self.frame:Raise()
end

function MainWindow:Close()
	if self.frame then self.frame:Hide() end
end

function MainWindow:Toggle()
	if self:IsShown() then self:Close() else self:Open() end
end

-- The language and the theme are applied at Build; a theme change recolours the registry by itself (Theme.Apply).

-- /fdcp debug: what the client answered to the UI probes of docs/specs/ui-style.md §7 (read by the owner in game).
local FDCP = ns.addon
if FDCP and FDCP.AddDebugSection then
	FDCP:AddDebugSection("UI", function()
		local function yn(v) return v and L["DEBUG_YES"] or L["DEBUG_NO"] end
		local fallbacks, addon = 0, 0
		for _, status in pairs(Theme.fontStatus) do
			if status == "game" then fallbacks = fallbacks + 1 else addon = addon + 1 end
		end
		local p = Theme.Probes()
		return {
			L["DEBUG_UI_THEME"]:format(Theme.Name(Theme.Current()), addon, fallbacks, p.texturesRefused),
			L["DEBUG_UI_PROBES"]:format(yn(p.scrollBox), yn(p.dataProvider), yn(p.slicing), yn(p.addBlend), yn(p.spriteSheet),
				p.pixel, p.scale),
		}
	end)
end
