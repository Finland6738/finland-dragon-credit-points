-- AboutWindow: the Info sub-tab of Settings and `/fdcp about` (docs/ANALISI.md §3.9, docs/specs/ui-style.md §6, M7-2c).
-- Tells who made the addon and for whom (Finland, for the Italian guild NEBULA), what it is for, the licence, the third-party
-- fonts and libraries, and how to support the project. The only link is the Ko-fi page (owner rule of 2026-11-24: no links
-- to the community site or to GitHub inside the addon). The game cannot open a web page, so it is a read-only copy box
-- (click it, Ctrl+C). Words come from locale keys; the links and names are constants of this file. Lua 5.1; unprotected frames.
-- Not verified in the real client: the look of the page and the copy boxes (M7-2c "in game").
local ADDON_NAME, ns = ...
ns = ns or {}
local AboutWindow = {}
ns.AboutWindow = AboutWindow
if ns.addon then ns.addon.AboutWindow = AboutWindow end   -- also reachable from tests

local Theme, Widgets, Assets = ns.Theme, ns.Widgets, ns.Assets
local L = ns.L

AboutWindow.AUTHOR = "Finland"
AboutWindow.GUILD = "NEBULA"
AboutWindow.LICENSE = "GPL-3.0"
-- The links, in the order of the page. `id` names the label (locale key ABOUT_LINK_<ID>). Only Ko-fi: the addon carries
-- no link to the community site or to GitHub (owner rule of 2026-11-24).
AboutWindow.LINKS = {
	{ id = "kofi", url = "https://ko-fi.com/finland6738" },
}

-- The NEBULA community logo: the dark-theme art (own colours, white word) on Nebula and Drago, the light-theme art
-- (black word) on Aurora. Returns the key of Assets.textures. The logo belongs to the community (docs/third-party.md).
function AboutWindow.LogoKey(themeId)
	local theme = Theme.themes[themeId or Theme.Current()]
	if theme and theme.dark == false then return "nebula_light_256" end
	return "nebula_dark_256"
end

-- Puts the logo of the current theme on `tex`. When the client cannot load the file, the texture is hidden and the word
-- NEBULA takes its place (`tex.fallback`).
function AboutWindow.ApplyLogo(tex, themeId)
	local ok, loaded = pcall(tex.SetTexture, tex, Assets.textures[AboutWindow.LogoKey(themeId)].path)
	local shown = ok and loaded ~= false and tex:GetTexture() ~= nil
	tex:SetShown(shown)
	if tex.fallback then tex.fallback:SetShown(not shown) end
end

-- The lines of the page, as text: used by the window, by `/fdcp about` and by the tests.
-- locale-key: ABOUT_MADE_BY ABOUT_PURPOSE ABOUT_GUILD ABOUT_LICENSE ABOUT_SUPPORT ABOUT_THIRD ABOUT_DISCLAIMER ABOUT_VERSION
-- locale-key: ABOUT_LINK_KOFI
function AboutWindow.Lines()
	local version = ns.Protocol and ns.Protocol.AddonVersion() or "dev"
	return {
		title = L["ADDON_TITLE"],
		version = L["ABOUT_VERSION"]:format(version),
		madeBy = L["ABOUT_MADE_BY"]:format(AboutWindow.AUTHOR, AboutWindow.GUILD),
		purpose = L["ABOUT_PURPOSE"],
		guild = L["ABOUT_GUILD"]:format(AboutWindow.GUILD),
		license = L["ABOUT_LICENSE"]:format(AboutWindow.LICENSE),
		support = L["ABOUT_SUPPORT"],
		third = L["ABOUT_THIRD"],
		disclaimer = L["ABOUT_DISCLAIMER"],
	}
end

function AboutWindow:Build(pane)
	if self.root then return self.root end
	local card = Widgets.Card(pane, {})
	card:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -4)
	card:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
	self.root, self.card = card, card
	local logo = card:CreateTexture(nil, "ARTWORK")
	logo:SetSize(72, 72)
	logo:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -16)
	logo:SetTexture(Assets.textures.logo_256.path)
	card.logo = logo
	local function text(id, token, anchor, dy)
		local fs = Theme.NewText(card, id, token)
		fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, dy or -6)
		fs:SetPoint("RIGHT", card, "RIGHT", -16, 0)
		fs:SetJustifyH("LEFT")
		fs:SetJustifyV("TOP")
		return fs
	end
	-- the NEBULA logo, top right; it follows the theme (dark art on dark themes, light art on Aurora)
	local nebula = card:CreateTexture(nil, "ARTWORK")
	nebula:SetSize(112, 112)
	nebula:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -16)
	nebula.fallback = Theme.NewText(card, "H2", "text-2")
	nebula.fallback:SetPoint("CENTER", nebula, "CENTER", 0, 0)
	nebula.fallback:SetText(self.GUILD)
	card.nebulaLogo = nebula
	Theme.Call(nebula, function(tex, themeId) AboutWindow.ApplyLogo(tex, themeId) end)
	card.title = Theme.NewText(card, "H2", "text-1")
	card.title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 14, -6)
	card.version = text("Small", "text-3", card.title, -4)
	card.madeBy = text("Body", "text-1", logo, -10)
	card.madeBy:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -10)
	card.purpose = text("Body", "text-2", card.madeBy)
	card.guild = text("Body", "text-2", card.purpose)
	for _, fs in ipairs({ card.madeBy, card.purpose, card.guild }) do   -- the text stops at the logo
		fs:SetPoint("RIGHT", nebula, "LEFT", -16, 0)
	end
	card.support = text("Body", "text-2", card.guild, -8)
	-- the copy boxes, two per row
	card.links = {}
	for i, link in ipairs(self.LINKS) do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		local label = Theme.NewText(card, "Small", "text-3")
		label:SetText(L["ABOUT_LINK_" .. link.id:upper()])
		local box = Widgets.EditBox(card, { width = 380, height = 28 })
		box:SetText(link.url)
		local url = link.url
		box.edit:SetScript("OnTextChanged", function(self, user)
			if user and self:GetText() ~= url then self:SetText(url) end   -- a copy, not a field: an edit is put back at once
		end)
		box.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
		label:SetPoint("TOPLEFT", card.support, "BOTTOMLEFT", col * 400, -10 - row * 58)
		box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
		card.links[link.id] = box
	end
	card.license = Theme.NewText(card, "Body", "text-2")
	local rows = math.floor((#self.LINKS + 1) / 2)
	-- (tight spacing: the page fits the smallest window in Italian, fix/settings-layout)
	card.license:SetPoint("TOPLEFT", card.support, "BOTTOMLEFT", 0, -10 - rows * 58)
	card.license:SetPoint("RIGHT", card, "RIGHT", -16, 0)
	card.license:SetJustifyH("LEFT")
	card.third = text("Small", "text-3", card.license)
	card.disclaimer = text("Small", "text-3", card.third)
	return card
end

function AboutWindow:Refresh()
	local card = self.card
	if not card then return end
	local t = self.Lines()
	card.title:SetText(t.title)
	card.version:SetText(t.version)
	card.madeBy:SetText(t.madeBy)
	card.purpose:SetText(t.purpose)
	card.guild:SetText(t.guild)
	card.support:SetText(t.support)
	card.license:SetText(t.license)
	card.third:SetText(t.third)
	card.disclaimer:SetText(t.disclaimer)
end

-- The page in the chat, links included (they can be selected and copied from the chat frame).
function AboutWindow.PrintToChat()
	local FDCP = ns.addon
	local t = AboutWindow.Lines()
	FDCP:Print(t.title .. " - " .. t.version)
	FDCP:Print(t.madeBy)
	FDCP:Print(t.guild)
	for _, link in ipairs(AboutWindow.LINKS) do FDCP:Print(L["ABOUT_LINK_" .. link.id:upper()] .. ": " .. link.url) end
	FDCP:Print(t.license)
end

function AboutWindow.Open()
	if not ns.MainWindow then return AboutWindow.PrintToChat() end
	ns.MainWindow:Open("settings")
	if ns.SettingsWindow and ns.SettingsWindow.root then ns.SettingsWindow.root.sub:Select("about") end
end

-- /fdcp about: opens the Info page; /fdcp about chat: prints it in the chat instead.
function AboutWindow.Command(input)
	local _, arg = ns.addon:GetArgs(input or "", 2)
	if arg and arg:lower() == "chat" then return AboutWindow.PrintToChat() end
	AboutWindow.Open()
end

if ns.addon and ns.addon.commands then
	local cmds = ns.addon.commands
	cmds[#cmds + 1] = { name = "about", helpKey = "HELP_ABOUT", handler = function(_, input) AboutWindow.Command(input) end }
end
