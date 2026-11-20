-- Init: the addon object, the Forever check and the slash command (docs/ANALISI.md §8.2). Lua 5.1.
-- Adapted from Azeroth Accord (Core/Init.lua), same owner, GPL-3.0.
-- Later modules attach themselves to the private namespace `ns` and, when tests need them, to the addon object.
local ADDON_NAME, ns = ...
ns = ns or {}

local FDCP = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
local L = ns.L   -- Locale/Boot.lua: follows the active language
ns.addon = FDCP
FDCP.L, FDCP.Locale = L, ns.Locale   -- also reachable from tests
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
	{ name = "help", helpKey = "HELP_HELP", handler = function(self) self:PrintHelp() end },
	{ name = "language", helpKey = "HELP_LANGUAGE", handler = function(self, input) self:LanguageCommand(input) end },
}

function FDCP:PrintHelp()
	self:Print(L["HELP_HEADER"])
	for _, c in ipairs(self.commands) do
		self:Print("/fdcp " .. c.name .. " - " .. (c.helpKey and L[c.helpKey] or c.help))   -- looked up now: the language may have changed
	end
end

-- /fdcp language [auto|<code>]: shows or sets the personal language (applied at the next /reload).
function FDCP:LanguageCommand(input)
	local Locale, Config = ns.Locale, ns.Config
	local codes = {}
	for _, lang in ipairs(Locale.Languages()) do codes[#codes + 1] = lang.code end
	local list = table.concat(codes, ", ")
	local _, arg = self:GetArgs(input or "", 2)
	if not arg or arg == "" then
		local setting = Config and Config:GetLanguage() or "auto"
		self:Print(L["LANGUAGE_CURRENT"]:format(Locale.Active(), setting == "auto" and L["LANGUAGE_AUTO"] or setting, list))
		return
	end
	local ok, err = Config:SetLanguage(arg)
	if ok then
		self:Print(L["LANGUAGE_SET"]:format(arg == "auto" and L["LANGUAGE_AUTO"] or arg))
	elseif err == "READ_ONLY" then
		self:Print(L["LANGUAGE_READ_ONLY"])
	else
		self:Print(L["LANGUAGE_UNKNOWN"]:format(arg, list))
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
	if ns.Config then ns.Config:Setup() end   -- SavedVariables are loaded by now
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
