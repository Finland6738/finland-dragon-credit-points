-- Minimap: the minimap button (LibDBIcon over LibDataBroker) with the guild logo, and the AddOn Compartment tooltip
-- helper (M1-7). Lua 5.1. Left click toggles the main window; the position is saved by LibDBIcon in the profile.
local ADDON_NAME, ns = ...
ns = ns or {}

local Minimap = {}
ns.Minimap = Minimap
if ns.addon then ns.addon.Minimap = Minimap end   -- also reachable from tests

local L = ns.L

Minimap.OBJECT = ADDON_NAME

-- Called once the SavedVariables are loaded (Init:OnInitialize). Safe to call again.
function Minimap:Setup()
	if self.registered then return true end
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	local icon = LibStub and LibStub("LibDBIcon-1.0", true)
	if not ldb or not icon then return false end
	local db = ns.Config and ns.Config.db and ns.Config.db.profile
	if not db then return false end
	db.minimap = db.minimap or { hide = false }
	self.data = ldb:NewDataObject(Minimap.OBJECT, {
		type = "launcher",
		text = L["ADDON_TITLE"],
		icon = ns.Assets.textures.logo_64.path,
		OnClick = function(_, button)
			if button == "LeftButton" and ns.MainWindow then ns.MainWindow:Toggle() end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine(L["ADDON_TITLE"])
			tooltip:AddLine(L["MINIMAP_HINT"])
		end,
	})
	icon:Register(Minimap.OBJECT, self.data, db.minimap)
	self.registered = true
	return true
end

-- Shows or hides the button and remembers it.
function Minimap:SetShown(shown)
	local icon = LibStub and LibStub("LibDBIcon-1.0", true)
	local db = ns.Config and ns.Config.db and ns.Config.db.profile
	if not icon or not db or not self.registered then return false end
	db.minimap.hide = not shown
	if shown then icon:Show(Minimap.OBJECT) else icon:Hide(Minimap.OBJECT) end
	return true
end
