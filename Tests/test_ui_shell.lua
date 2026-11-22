-- The main window and its widgets (M1-7): /fdcp opens a themed window with the six tabs, every visible text comes from
-- the locales, the theme recolours it live, it moves and resizes and remembers where it was, Esc closes it, the minimap
-- button and the compartment entry toggle it. Read the game's globals inside the tests: every test boots a fresh client.

local function W() return FDCP.MainWindow end
local function frame() return FDCP.MainWindow:Build() end

-- Every FontString under a frame, depth first.
local function eachText(f, fn)
	for _, r in ipairs({ f:GetRegions() }) do
		if r:GetObjectType() == "FontString" then fn(r) end
	end
	for _, c in ipairs({ f:GetChildren() }) do eachText(c, fn) end
end

describe("window", function()
	it("/fdcp opens it and /fdcp toggle closes it", function()
		Mock.Slash("/fdcp")
		truthy(W():IsShown())
		Mock.Slash("/fdcp toggle")
		falsy(W():IsShown())
		Mock.Slash("/fdcp toggle")
		truthy(W():IsShown())
	end)

	it("has the six tabs of the spec, in order, with the Roster tab open", function()
		Mock.Slash("/fdcp")
		local order = {}
		for _, t in ipairs(W().TABS) do order[#order + 1] = t.id end
		deepEq(order, { "roster", "credits", "progress", "loot", "history", "settings" })
		eq(W():ActiveTab(), "roster")
		local labels = {}
		for _, id in ipairs(order) do labels[#labels + 1] = frame().tabs.buttons[id].label:GetText() end
		deepEq(labels, { "Roster", "Credits", "Progress", "Loot", "History", "Settings" })
	end)

	it("shows one empty page at a time", function()
		W():Open()
		for _, t in ipairs(W().TABS) do
			truthy(W():SelectTab(t.id))
			for id, page in pairs(frame().pages) do eq(page:IsShown(), id == t.id, id .. " while " .. t.id) end
		end
		falsy(W():SelectTab("nowhere"))
	end)

	it("a hidden tab is skipped and the next one opens", function()
		W():Open()
		W():SelectTab("loot")
		W():SetTabVisible("loot", false)
		eq(W():ActiveTab(), "roster")
		falsy(frame().tabs.buttons.loot:IsShown())
		falsy(W():SelectTab("loot"))
		W():SetTabVisible("loot", true)
		truthy(W():SelectTab("loot"))
	end)

	it("opens on a requested tab", function()
		W():Open("loot")
		eq(W():ActiveTab(), "loot")
	end)

	it("every visible text comes from the locale: English", function()
		W():Open()
		local n = 0
		eachText(frame(), function(fs)
			local text = fs:GetText()
			n = n + 1
			falsy(text:match("^[A-Z][A-Z_]+$") and FDCP.Locale.Text("enUS", text) ~= text and false)
			falsy(FDCP.Locale._strings().enUS[text] ~= nil, "a raw key is shown: " .. text)
		end)
		truthy(n >= 14)
	end)

	it("every visible text comes from the locale: Italian", function()
		T.boot(function(M) M.player.locale = "itIT" end)
		W():Open()
		eq(frame().tabs.buttons.credits.label:GetText(), "Crediti")
		eq(frame().tabs.buttons.history.label:GetText(), "Storico")
		eq(frame().tabs.buttons.settings.label:GetText(), "Impostazioni")
		eq(frame().pages.roster.empty:GetText(), "Questa pagina è ancora vuota: si riempie con le prossime versioni.")
		eachText(frame(), function(fs)
			falsy(FDCP.Locale._strings().itIT[fs:GetText()] ~= nil, "a raw key is shown: " .. fs:GetText())
		end)
	end)

	it("uses the display font for the title and no secure or Blizzard template", function()
		W():Open()
		eq(frame().titleBar.title:GetFontObject(), FDCP.Theme.Font("Display"))
		eq(frame().titleBar.title:GetText(), "DRAGON CREDIT POINTS")
		local function walk(f)
			falsy(f._template, "template " .. tostring(f._template))
			for _, c in ipairs({ f:GetChildren() }) do walk(c) end
		end
		walk(frame())
	end)
end)

describe("behaviour", function()
	it("is movable and resizable from a minimum size, clamped to the screen", function()
		local f = frame()
		truthy(f:IsMovable()); truthy(f:IsResizable()); truthy(f._clamped)
		deepEq(f._bounds, { 900, 560, 1400, 900 })
	end)

	it("Esc closes it", function()
		local found = false
		for _, n in ipairs(UISpecialFrames) do if n == "FDCPMainFrame" then found = true end end
		falsy(found, "not registered before the window is built")
		W():Open()
		for _, n in ipairs(UISpecialFrames) do if n == "FDCPMainFrame" then found = true end end
		truthy(found)
		eq(_G.FDCPMainFrame, frame())
	end)

	it("is registered only once however often it is built", function()
		W():Build(); W():Build(); W():Open(); W():Close(); W():Open()
		local n = 0
		for _, name in ipairs(UISpecialFrames) do if name == "FDCPMainFrame" then n = n + 1 end end
		eq(n, 1)
	end)

	it("remembers where it was moved, per character, across /reload", function()
		W():Open()
		Mock.Drag(frame(), "TOPLEFT", 120, -80)
		deepEq({ FDCP.Config.char.window.point, FDCP.Config.char.window.x, FDCP.Config.char.window.y }, { "TOPLEFT", 120, -80 })
		Mock.Reload()
		W():Open()
		local point, _, _, x, y = frame():GetPoint(1)
		deepEq({ point, x, y }, { "TOPLEFT", 120, -80 })
	end)

	it("remembers its size, clamped to the bounds", function()
		W():Open()
		frame():SetSize(1100, 700)
		Mock.RunScript(frame().grip, "OnMouseUp")
		eq(FDCP.Config.char.window.w, 1100)
		Mock.Reload()
		W():Open()
		deepEq({ frame():GetSize() }, { 1100, 700 })
		FDCP.Config.char.window = { point = "CENTER", x = 0, y = 0, w = 100, h = 99999 }
		Mock.Reload()
		W():Open()
		deepEq({ frame():GetSize() }, { 900, 900 })
	end)

	it("ignores a damaged placement", function()
		FDCP.Config.char.window = { point = 5, x = "a" }
		Mock.Reload()
		W():Open()
		deepEq({ frame():GetSize() }, { 960, 640 })
		eq((frame():GetPoint(1)), "CENTER")
	end)

	it("does not save a position when the saved data is read-only", function()
		W():Open()
		FDCP.Config.readOnly = true
		Mock.Drag(frame(), "TOPLEFT", 5, 5)
		isNil(FDCP.Config.char.window)
	end)

	it("the compartment entry toggles it", function()
		FinlandDragonCreditPoints_OnAddonCompartmentClick()
		truthy(W():IsShown())
		FinlandDragonCreditPoints_OnAddonCompartmentClick()
		falsy(W():IsShown())
	end)

	it("the close button closes it", function()
		W():Open()
		frame().titleBar.close:Click()
		falsy(W():IsShown())
	end)
end)

describe("theme in the window", function()
	it("switching the theme recolours every region without /reload", function()
		W():Open()
		local fill = frame().parts.fill
		near((fill:GetVertexColor()), 0x0B / 255, 1e-6)    -- Nebula bg
		truthy(FDCP.Theme.Set("aurora"))
		near((fill:GetVertexColor()), 0xF5 / 255, 1e-6)    -- Aurora bg
		local tab = frame().tabs.buttons.roster.label
		near((tab:GetTextColor()), 0x0B / 255, 1e-6)       -- the active tab is text-1 of Aurora
		truthy(FDCP.Theme.Set("drago"))
		near((fill:GetVertexColor()), 0x07 / 255, 1e-6)
	end)

	it("the saved theme is applied when the window is built", function()
		FDCP.Config:Set("theme", "aurora")
		W():Open()
		eq(FDCP.Theme.Current(), "aurora")
	end)

	it("many regions are registered", function()
		W():Open()
		truthy(FDCP.Theme.Count() >= 25, tostring(FDCP.Theme.Count()))
	end)
end)

describe("widgets", function()
	local function parent() return CreateFrame("Frame") end

	it("Button: four styles, text, click and hover overlay", function()
		local clicked = 0
		for _, style in ipairs({ "primary", "secondary", "ghost", "neon" }) do
			local b = FDCP.Widgets.Button(parent(), { text = "OK", style = style, onClick = function() clicked = clicked + 1 end })
			eq(b.label:GetText(), "OK")
			b:Click()
		end
		eq(clicked, 4)
		FDCP.Config:Set("animations", false)   -- the layers show at once (their fade is tested in test_controls.lua)
		local b = FDCP.Widgets.Button(parent(), { text = "x" })
		Mock.RunScript(b, "OnEnter")
		near(b.over:GetAlpha(), 0.08, 1e-9)
		Mock.RunScript(b, "OnMouseDown")
		near(b.over:GetAlpha(), 0.12, 1e-9)
		Mock.RunScript(b, "OnLeave")
		eq(b.over:GetAlpha(), 0)
	end)

	it("Button: a disabled button shows no hover", function()
		FDCP.Config:Set("animations", false)
		local b = FDCP.Widgets.Button(parent(), { text = "x" })
		b:Disable()
		Mock.RunScript(b, "OnEnter")
		eq(b.over:GetAlpha(), 0)
	end)

	it("Card: fill, ring and at most four regions", function()
		local c = FDCP.Widgets.Card(parent(), { shadow = true, hover = true })
		eq(c.parts.fill._asset, "rr_fill_18")
		local n = 0
		for _ in pairs(c.parts) do n = n + 1 end
		truthy(n <= 4)
		Mock.RunScript(c, "OnEnter")
		near(select(4, c.parts.ring:GetVertexColor()), 0.26, 1e-6)
		Mock.RunScript(c, "OnLeave")
		near(select(4, c.parts.ring:GetVertexColor()), 0.08, 1e-6)
	end)

	it("Badge: width follows the text, the tone sets the colour", function()
		local b = FDCP.Widgets.Badge(parent(), "TRIAL", "warn")
		eq(b:GetHeight(), 24)
		eq(b:GetWidth(), math.max(24, 5 * 6 + 20))
		b:SetBadge("TRIAL LONG", "ok")
		eq(b:GetWidth(), 10 * 6 + 20)
		near((b.label:GetTextColor()), 0x46 / 255, 1e-6)
	end)

	it("Segmented: selects one segment and tells the callback", function()
		local got
		local s = FDCP.Widgets.Segmented(parent(), { { id = "a", text = "A" }, { id = "b", text = "B" } }, function(id) got = id end)
		truthy(s:Select("b"))
		eq(got, "b"); eq(s:Active(), "b")
		falsy(s:Select("zzz"))
		eq(s:Active(), "b")
		truthy(s.thumb:IsShown())
	end)

	it("Tabs: select, callback once per change, underline follows the tab", function()
		local calls = {}
		local t = FDCP.Widgets.Tabs(parent(), { { id = "a", text = "A" }, { id = "b", text = "B" } }, function(id) calls[#calls + 1] = id end)
		t:Select("a"); t:Select("a"); t:Select("b")
		deepEq(calls, { "a", "b" })
		truthy(t.indicator:IsShown())
		eq(select(2, t.indicator:GetPoint(1)), t.buttons.b)
		Mock.RunScript(t.buttons.a, "OnClick")
		eq(t:Active(), "a")
	end)

	it("Dialog: a veil and a card on the DIALOG strata; Esc is registered", function()
		local d = FDCP.Widgets.Dialog(UIParent, "FDCPTestDialog", { width = 300, height = 120 })
		eq(d:GetFrameStrata(), "DIALOG")
		falsy(d:IsShown())
		d:Open(); truthy(d:IsShown())
		d:Close(); falsy(d:IsShown())
		local found
		for _, n in ipairs(UISpecialFrames) do if n == "FDCPTestDialog" then found = true end end
		truthy(found)
		deepEq({ d.card:GetSize() }, { 300, 120 })
	end)
end)

describe("minimap button", function()
	it("registers a launcher with the guild logo", function()
		local icon = LibStub("LibDBIcon-1.0")
		truthy(icon:IsRegistered("FinlandDragonCreditPoints"))
		local obj = LibStub("LibDataBroker-1.1"):GetDataObjectByName("FinlandDragonCreditPoints")
		eq(obj.type, "launcher")
		contains(obj.icon, "logo_64.tga")
	end)

	it("a left click toggles the window and the tooltip says so", function()
		local obj = LibStub("LibDataBroker-1.1"):GetDataObjectByName("FinlandDragonCreditPoints")
		obj.OnClick(nil, "LeftButton")
		truthy(W():IsShown())
		obj.OnClick(nil, "RightButton")
		truthy(W():IsShown(), "only the left button toggles")
		local lines = {}
		obj.OnTooltipShow({ AddLine = function(_, t) lines[#lines + 1] = t end })
		deepEq(lines, { "Finland Dragon Credit Points", "Click to open the window." })
	end)

	it("can be hidden and the choice is saved", function()
		truthy(FDCP.Minimap:SetShown(false))
		truthy(FDCP.Config.db.profile.minimap.hide)
		truthy(FDCP.Minimap:SetShown(true))
		falsy(FDCP.Config.db.profile.minimap.hide)
	end)
end)

describe("/fdcp debug", function()
	it("prints the UI lines: theme, fonts and the probes", function()
		Mock.Slash("/fdcp debug")
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "UI: theme Nebula")
		contains(text, "UI probes: ScrollBox")
	end)

	it("counts the fonts that fell back to the game font", function()
		Mock.missingFonts[FDCP.Assets.fonts.mono.path] = true
		FDCP.Theme.SetupFonts("addon")
		Mock.Slash("/fdcp debug")
		contains(table.concat(Mock.PlainOutput(), "\n"), "game fallback 2")
	end)
end)
