-- Init: the addon object, the Forever check and the slash command (docs/ANALISI.md §8.2). Lua 5.1.
-- Adapted from Azeroth Accord (Core/Init.lua), same owner, GPL-3.0.
-- Later modules attach themselves to the private namespace `ns` and, when tests need them, to the addon object.
local ADDON_NAME, ns = ...
ns = ns or {}

local FDCP = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
ns.addon, ns.L = FDCP, L
_G.FDCP = FDCP

local FOREVER_MIN_INTERFACE, FOREVER_MAX_INTERFACE = 16001, 19999

-- True on WoW Forever: the project id constant when the client has it, else the Interface number.
function FDCP:IsForever()
	if WOW_PROJECT_ID ~= nil and WOW_PROJECT_CAMELOT ~= nil then
		return WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
	end
	local build = select(4, GetBuildInfo())
	return type(build) == "number" and build >= FOREVER_MIN_INTERFACE and build <= FOREVER_MAX_INTERFACE
end

function FDCP:Print(msg)
	self:Printf("|cffd4af37%s|r %s", L["ADDON_TITLE"], msg)
end

-- The commands in help order; later steps add theirs here.
FDCP.commands = {
	{ name = "help", help = L["HELP_HELP"], handler = function(self) self:PrintHelp() end },
}

function FDCP:PrintHelp()
	self:Print(L["HELP_HEADER"])
	for _, c in ipairs(self.commands) do
		self:Print("/fdcp " .. c.name .. " - " .. c.help)
	end
end

function FDCP:OnSlashCommand(input)
	local cmd = (self:GetArgs(input or "", 1) or ""):lower()
	if cmd == "" or cmd == "help" then
		return self:PrintHelp()   -- until the window exists (M1-8) a bare /fdcp shows the help
	end
	for _, c in ipairs(self.commands) do
		if c.name == cmd then
			return c.handler(self, input)
		end
	end
	self:Print(L["UNKNOWN_COMMAND"]:format(cmd))
	self:PrintHelp()
end

function FDCP:OnInitialize()
	self:RegisterChatCommand("fdcp", "OnSlashCommand")
	if not self:IsForever() then
		self:Print(L["WARN_NOT_FOREVER"])   -- OnInitialize runs once per session
	end
end

-- AddOn Compartment entry points (globals named in the TOC). The window arrives in M1-8: until then they show help.
function FinlandDragonCreditPoints_OnAddonCompartmentClick()
	FDCP:PrintHelp()
end

function FinlandDragonCreditPoints_OnAddonCompartmentEnter(_, menuButtonFrame)
	if not GameTooltip then return end
	GameTooltip:SetOwner(menuButtonFrame or UIParent, "ANCHOR_LEFT")
	GameTooltip:SetText(L["ADDON_TITLE"])
	GameTooltip:Show()
end

function FinlandDragonCreditPoints_OnAddonCompartmentLeave()
	if GameTooltip then GameTooltip:Hide() end
end
