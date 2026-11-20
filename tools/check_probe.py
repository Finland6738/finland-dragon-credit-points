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
    print(f"check_probe: {len(files)} Lua files, {len(tocs)} TOC files, {bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
