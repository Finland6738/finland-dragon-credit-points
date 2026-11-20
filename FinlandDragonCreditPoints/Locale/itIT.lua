-- Stringhe italiane. Le chiavi sono le stesse di enUS.lua (tools/check_addon.py).
local L = LibStub("AceLocale-3.0"):NewLocale("FinlandDragonCreditPoints", "itIT")
if not L then return end

L["ADDON_TITLE"] = "Finland Dragon Credit Points"
L["HELP_HEADER"] = "Comandi:"
L["HELP_HELP"] = "mostra questo elenco"
L["UNKNOWN_COMMAND"] = "Comando sconosciuto: %s"
L["WARN_NOT_FOREVER"] = "Questo addon è pensato per WoW Forever; potrebbe non funzionare su questo client."
L["HELP_DEBUG"] = "mostra cosa offre questo client (API e funzioni)"
L["DEBUG_CLIENT"] = "Client: %s (build %s), interface %d, id progetto %s%s"
L["DEBUG_FOREVER"] = " (Forever)"
L["DEBUG_FEATURES"] = "Funzioni:"
L["DEBUG_APIS"] = "API: %d disponibili, %d mancanti, %d limitate, %d in errore"
