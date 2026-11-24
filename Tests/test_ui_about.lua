-- The Info page (M7-2c): UI/Windows/About.lua, the Info sub-tab of Settings and `/fdcp about`.
local function AW() return FDCP.AboutWindow end
local function SW() return FDCP.SettingsWindow end

describe("the Info page", function()
	before_boot()

	it("is the last sub-tab of Settings and fills its texts from the locale", function()
		eq(SW().SUBTABS[#SW().SUBTABS], "about")
		Mock.Slash("/fdcp")
		FDCP.MainWindow:SelectTab("settings")
		SW().root.sub:Select("about")
		truthy(SW().root.panes.about:IsShown())
		local card = AW().card
		contains(card.madeBy:GetText(), "Finland")
		contains(card.madeBy:GetText(), "NEBULA")
		contains(card.license:GetText(), "GPL-3.0")
		contains(card.guild:GetText(), "NEBULA")
		contains(card.third:GetText(), "Orbitron")
		contains(card.third:GetText(), "Ace3")
	end)

	it("shows only the Ko-fi link, as a copy box that puts an edit back and selects its text on focus", function()
		Mock.Slash("/fdcp about")
		local want = {
			kofi = "https://ko-fi.com/finland6738",
		}
		for id, url in pairs(want) do
			local box = AW().card.links[id]
			truthy(box, id)
			eq(box:GetText(), url)
			box.edit:SetText("typed by hand")
			box.edit:GetScript("OnTextChanged")(box.edit, true)
			eq(box:GetText(), url, id .. " is put back")
			box.edit:GetScript("OnEditFocusGained")(box.edit)
			truthy(box.edit._highlighted, id .. " is selected")
		end
		eq(#AW().LINKS, 1)
		for _, id in ipairs({ "repo", "issues", "site" }) do
			truthy(not AW().card.links[id], id .. " is not on the page")
		end
	end)

	it("opens on /fdcp about and prints on /fdcp about chat", function()
		Mock.Slash("/fdcp about")
		truthy(FDCP.MainWindow:IsShown())
		eq(FDCP.MainWindow:ActiveTab(), "settings")
		eq(SW():ActiveSub(), "about")
		local before = #Mock.PlainOutput()
		Mock.Slash("/fdcp about chat")
		local lines = table.concat(Mock.PlainOutput(), "\n", before + 1)
		contains(lines, "Finland")
		contains(lines, "ko-fi.com/finland6738")
		contains(lines, "GPL-3.0")
		truthy(not lines:find("github", 1, true), "no GitHub link in the chat")
		truthy(not lines:find("nebula-community", 1, true), "no community-site link in the chat")
	end)

	it("shows the NEBULA logo of the theme: dark art on Nebula and Drago, light art on Aurora, live on a change", function()
		Mock.Slash("/fdcp about")
		local logo = AW().card.nebulaLogo
		truthy(logo, "the logo is on the page")
		eq(AW().LogoKey("nebula"), "nebula_dark_256")
		eq(AW().LogoKey("drago"), "nebula_dark_256")
		eq(AW().LogoKey("aurora"), "nebula_light_256")
		local function shows(name) contains(logo:GetTexture(), name .. ".tga") end
		truthy(FDCP.Theme.Set("nebula")); shows("nebula_dark_256")
		truthy(FDCP.Theme.Set("aurora")); shows("nebula_light_256")
		truthy(FDCP.Theme.Set("drago")); shows("nebula_dark_256")
		truthy(logo:IsShown()); truthy(not logo.fallback:IsShown())
		FDCP.Theme.Set("nebula")
	end)

	it("shows the word NEBULA instead of the logo when the client cannot load the picture", function()
		Mock.Slash("/fdcp about")
		local logo = AW().card.nebulaLogo
		Mock.missingTextures[FDCP.Assets.textures.nebula_dark_256.path] = true
		AW().ApplyLogo(logo, "nebula")
		truthy(not logo:IsShown()); truthy(logo.fallback:IsShown()); eq(logo.fallback:GetText(), "NEBULA")
		Mock.missingTextures[FDCP.Assets.textures.nebula_dark_256.path] = nil
		AW().ApplyLogo(logo, "nebula")
		truthy(logo:IsShown()); truthy(not logo.fallback:IsShown())
	end)

	it("keeps the personal data out: the author is the public handle only", function()
		for _, text in pairs(AW().Lines()) do
			truthy(not text:find("@", 1, true), "no email in " .. text)
		end
		eq(AW().AUTHOR, "Finland")
	end)

	it("speaks Italian after the language is changed", function()
		contains(AW().Lines().madeBy, "for the Italian guild")
		FDCP.Config:SetLanguage("itIT")
		Mock.Reload()
		local t = AW().Lines()
		contains(t.madeBy, "per la gilda italiana NEBULA")
		contains(t.support, "Ko-fi")
	end)
end)
