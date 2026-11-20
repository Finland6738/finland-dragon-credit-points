#!/usr/bin/env python3
"""Syntax check of the probe's Lua files with lupa (skipped with a notice when lupa is not installed)."""
import sys
from pathlib import Path

DIR = Path(__file__).resolve().parent / "probe" / "FDCP_Probe"


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
    print(f"check_probe: {len(files)} Lua files, {len(tocs)} TOC files, {bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
