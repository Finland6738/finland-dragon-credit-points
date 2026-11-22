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

	it("shows every link as a copy box that puts an edit back and selects its text on focus", function()
		Mock.Slash("/fdcp about")
		local want = {
			repo = "https://github.com/Finland6738/finland-dragon-credit-points",
			site = "https://nebula-community.github.io/giochi/wow-forever/",
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
		truthy(AW().card.links.issues)
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
