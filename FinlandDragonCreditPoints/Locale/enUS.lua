-- English strings (the base language). Every visible text goes through a key (CLAUDE.md, ADR 0003).
local L = LibStub("AceLocale-3.0"):NewLocale("FinlandDragonCreditPoints", "enUS", true)
if not L then return end

L["ADDON_TITLE"] = "Finland Dragon Credit Points"
L["HELP_HEADER"] = "Commands:"
L["HELP_HELP"] = "show this list"
L["UNKNOWN_COMMAND"] = "Unknown command: %s"
L["WARN_NOT_FOREVER"] = "This addon is built for WoW Forever; it may not work on this client."
