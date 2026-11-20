#!/usr/bin/env python3
"""Syntax check of the probe's Lua files with lupa (skipped with a notice when lupa is not installed)."""
import sys
from pathlib import Path

DIR = Path(__file__).resolve().parent / "probe" / "FDCP_Probe"


PATTERN_TEST = """
local P = { IsSecret = function() return false end, Has = function() return true end,
    Register = function() end, DB = function() return {} end }
CreateFrame = function() return { SetScript = function() end, RegisterEvent = function() end } end
local chunk = assert(loadfile(...))
chunk("FDCP_Probe", P)
local c = P.MatchFormat("%s rolls %d (%d-%d)", "Aurel rolls 42 (1-100)")
assert(c and c[1] == "Aurel" and c[2] == "42" and c[3] == "1" and c[4] == "100", "roll pattern")
assert(P.MatchFormat("%2$s got %1$s.", "Sword got Bryn.")[1] == "Bryn", "positional pattern")
assert(not P.MatchFormat("%s rolls %d (%d-%d)", "not a roll"), "non-roll")
"""


COMMS_TEST = """
local P = { IsSecret = function() return false end, PREFIX = "FDCPP", AFTER_WINDOW = 10 }
local db = {}
P.DB = function() return db end
P.Has = function() return true end
P.Register = function(id) P[id] = true end
P.Record = function(id, r, d) return { id = id, result = r, details = d } end
local handler
CreateFrame = function() return { SetScript = function(_, _, f) handler = f end, RegisterEvent = function() end } end
Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3 } }
local sent = {}
C_ChatInfo = { SendAddonMessage = function(pre, text, ch) sent[#sent + 1] = text; assert(#text <= 255); return 0 end,
    InChatMessagingLockdown = function() return false end, AreOutgoingAddonChatMessagesRestricted = function() return false end }
GetTime = function() return 1 end
GetServerTime = function() return 100 end
IsInInstance = function() return true end
loadfile(...)("FDCP_Probe", P)
local r = P.Ping("raid", 5)
assert(r.result == "ok" and #sent == 5, "ping raid")
P.PingBig("raid")
assert(#sent[#sent] == 255, "big payload is 255 bytes")
P.PingBurst("raid")
assert(#sent == 36, "burst of 30")
assert(db.comms.sent["instance.RAID.Success"] == 36, "send tally")
handler(nil, "CHAT_MSG_ADDON", "FDCPP", "abcd|1|98|", "RAID")
handler(nil, "CHAT_MSG_ADDON", "FDCPP", "abcd|3|98|", "RAID")
handler(nil, "CHAT_MSG_ADDON", "OTHER", "abcd|3|98|", "RAID")
local e = db.comms.runs.abcd
assert(e.count == 2 and e.min == 1 and e.max == 3 and e.maxDelay == 2, "received run")
"""


ITEMS_TEST = """
local P = { IsSecret = function() return false end, Has = function() return true end }
local db = {}
P.DB = function() return db end
P.Register = function(id, _, _, fn) P[id] = fn end
CreateFrame = function() return { SetScript = function() end, RegisterEvent = function() end } end
IsInInstance = function() return true, "raid" end
C_Item = {
    GetItemInfoInstant = function() return 1, "Armor", "INVTYPE_HEAD", 4, 3 end,
    GetItemInfo = function() return "x", "l", 3, 600, 70, "t", "s", 1, "INVTYPE_HEAD", 0, 0, 4, 3, 1 end,
    GetDetailedItemLevelInfo = function() return 610, false, 600 end,
    GetItemStats = function() return { ITEM_MOD_STRENGTH_SHORT = 150, ITEM_MOD_CRIT_RATING_SHORT = 90 } end,
    GetItemStatDelta = function() return { ITEM_MOD_STRENGTH_SHORT = 10 } end,
    IsEquippableItem = function() return true end,
    DoesItemContainSpec = function() return true end,
    GetItemSpecInfo = function() return { 71, 72 } end,
}
GetInventoryItemLink = function() return "equipped" end
C_TooltipInfo = { GetHyperlink = function() return { lines = { { leftText = "+150 Strength" }, { leftText = "+90 Critical Strike" } } } end }
GetNumSpecializations = function() return 3 end
GetSpecialization = function() return 1 end
GetSpecializationInfo = function(i) return 70 + i, "n", "d", 0, "DAMAGER" end
UnitClass = function() return "Warrior", "WARRIOR", 1 end
loadfile(...)("FDCP_Probe", P)
local r = P.ProbeItem("item:1")
assert(r.equipLoc == "INVTYPE_HEAD" and r.classID == 4, "instant info")
assert(r.tooltipMismatch == 0, "tooltip matches stats")
assert(r.delta:find("ITEM_MOD_STRENGTH_SHORT=10"), "delta")
assert(r.containSpec == "true,true,true", "spec flags")
assert(#db.items == 1, "recorded")
local res = P.S5c()
assert(res == "ok", "S5c ok")
assert(P.S6a() == "ok", "S6a")
"""


def items_test(lua):
    """Offline test of the S5/S6 item probe (Items.lua), run with a stub client."""
    try:
        fn = lua.eval("function(src, path) local l = loadstring or load; local ok, e = pcall(l(src), path);"
                      " if ok then return '' end; return tostring(e) end")
        err = fn(ITEMS_TEST, str(DIR / "Items.lua"))
    except Exception as exc:  # noqa: BLE001
        err = str(exc)
    if err:
        print(f"FAIL items: {err}")
        return 1
    return 0


def comms_test(lua):
    """Offline test of the S4 sender and receiver (Comms.lua), run with a stub client."""
    try:
        fn = lua.eval("function(src, path) local l = loadstring or load; local ok, e = pcall(l(src), path);"
                      " if ok then return '' end; return tostring(e) end")
        err = fn(COMMS_TEST, str(DIR / "Comms.lua"))
    except Exception as exc:  # noqa: BLE001
        err = str(exc)
    if err:
        print(f"FAIL comms: {err}")
        return 1
    return 0


def pattern_test(lua):
    """Offline test of the S3 pattern builder (Rolls.lua), run with a stub client."""
    try:
        fn = lua.eval("function(src, path) local l = loadstring or load; local ok, e = pcall(l(src), path);"
                      " if ok then return '' end; return tostring(e) end")
        err = fn(PATTERN_TEST, str(DIR / "Rolls.lua"))
        ok = not err
    except Exception as exc:  # noqa: BLE001
        ok, err = False, str(exc)
    if not ok:
        print(f"FAIL pattern builder: {err}")
        return 1
    return 0


def main():
    try:
        import lupa
    except ImportError:
        print("check_probe: lupa not installed, Lua syntax check skipped (pip install lupa)")
        return 0
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    load = lua.eval("function(src, name) local l = loadstring or load; local f, err = l(src, '=' .. name); return err end")
    bad = 0
    files = sorted(DIR.glob("*.lua"))
    for f in files:
        err = load(f.read_text(encoding="utf-8"), f.name)
        if err:
            bad += 1
            print(f"FAIL {f.name}: {err}")
    tocs = sorted(DIR.glob("*.toc"))
    for t in tocs:
        text = t.read_text(encoding="utf-8")
        if "## Interface: 16001" not in text:
            bad += 1
            print(f"FAIL {t.name}: Interface 16001 missing")
        for line in text.splitlines():
            if line.endswith(".lua") and not (DIR / line.strip()).exists():
                bad += 1
                print(f"FAIL {t.name}: {line} not found")
    bad += pattern_test(lua)
    bad += comms_test(lua)
    bad += items_test(lua)
    print(f"check_probe: {len(files)} Lua files, {len(tocs)} TOC files, {bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
