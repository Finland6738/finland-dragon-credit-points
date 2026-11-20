"""Offline checks of the addon folder: both TOC files (interface and fields), listed files, embeds.xml (Libs only when
fetched) and the locale tables.

Adapted from Azeroth Accord (tools/check_addon.py), same owner, GPL-3.0.

Locale rules: every L["KEY"] used in the code has an English string in Locale/enUS.lua (AceLocale answers with the key
itself for a missing one, which would hide the mistake), and Locale/itIT.lua has exactly the English keys.

Usage: python -I -X utf8 tools/check_addon.py (also called by tools/check_docs.py)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "FinlandDragonCreditPoints"
ADDON = os.path.join(ROOT, NAME)
TOCS = (NAME + ".toc", NAME + "_Camelot.toc")
INTERFACE = "16001"
REQUIRED_TOC_KEYS = ("Title", "Author", "Version", "SavedVariables", "SavedVariablesPerCharacter",
                     "AddonCompartmentFunc")
SAVED = {"SavedVariables": NAME + "DB", "SavedVariablesPerCharacter": NAME + "CharDB"}
LUA_DIRS = ("Core", "Domain", "Adapters", "Net", "UI")
# The libraries embeds.xml must load (M1-1): Ace3 modules, LibDataBroker, LibDBIcon (ChatThrottleLib comes with AceComm).
REQUIRED_EMBEDS = ("AceAddon-3.0", "AceDB-3.0", "AceDBOptions-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceComm-3.0",
                   "AceLocale-3.0", "AceConfig-3.0", "LibDataBroker-1.1", "LibDBIcon-1.0")


def _path(base, rel):
    return os.path.join(base, *re.split(r"[\\/]", rel.strip()))


def check_embeds(embeds, problems, seen=None):
    base = os.path.dirname(embeds)
    with open(embeds, encoding="utf-8") as f:
        text = f.read()
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)   # a commented-out include (AceConfig does one) is not loaded
    if seen is not None:
        seen.append(text)
    for kind, rel in re.findall(r'<(Script|Include)\s+file="([^"]+)"', text):
        if re.split(r"[\\/]", rel)[0] == "Libs" and not os.path.isdir(os.path.join(ADDON, "Libs")):
            continue   # libraries are fetched, not committed
        target = _path(base, rel)
        if not os.path.isfile(target):
            problems.append(f"{os.path.relpath(embeds, ROOT)}: missing {rel}")
        elif kind == "Include" and rel.lower().endswith(".xml"):
            check_embeds(target, problems, seen)


def check_required_embeds(embeds, problems):
    with open(embeds, encoding="utf-8") as f:
        text = re.sub(r"<!--.*?-->", "", f.read(), flags=re.S)
    for lib in REQUIRED_EMBEDS:
        if lib not in text:
            problems.append(f"embeds.xml does not load {lib}")


def lua_files():
    for sub in LUA_DIRS:
        for folder, _, names in os.walk(os.path.join(ADDON, sub)):
            for name in names:
                if name.endswith(".lua"):
                    yield os.path.join(folder, name)


def locale_keys(name):
    path = os.path.join(ADDON, "Locale", name)
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as f:
        return set(re.findall(r'^L\["([^"]+)"\]\s*=', f.read(), re.M))


def check_locale(problems):
    have = locale_keys("enUS.lua")
    if have is None:
        problems.append(f"{NAME}/Locale/enUS.lua is missing")
        return
    for path in lua_files():
        with open(path, encoding="utf-8") as f:
            text = f.read()
        used = set(re.findall(r'L\["([A-Za-z0-9_]+)"\]', text))
        for key in sorted(used - have):
            problems.append(f"{os.path.relpath(path, ROOT)}: L[\"{key}\"] has no string in Locale/enUS.lua")
    italian = locale_keys("itIT.lua")
    if italian is None:
        problems.append(f"{NAME}/Locale/itIT.lua is missing")
        return
    for key in sorted(italian - have):
        problems.append(f"Locale/itIT.lua: L[\"{key}\"] is not an English key (typo?)")
    for key in sorted(have - italian):
        problems.append(f"Locale/itIT.lua: L[\"{key}\"] has no Italian string (the addon is in English and Italian)")


def read_toc(toc):
    with open(toc, encoding="utf-8") as f:
        lines = f.read().splitlines()
    meta, files = {}, []
    for line in lines:
        m = re.match(r"^##\s*([\w-]+)\s*:\s*(.*)$", line)
        if m:
            meta[m.group(1)] = m.group(2).strip()
        elif line.strip() and not line.startswith("#"):
            files.append(line.strip())
    return meta, files


def check_toc(name, problems):
    toc = os.path.join(ADDON, name)
    if not os.path.isfile(toc):
        problems.append(f"{NAME}/{name} is missing")
        return None
    meta, files = read_toc(toc)
    if meta.get("Interface") != INTERFACE:
        problems.append(f"{name}: Interface is {meta.get('Interface')!r}, expected {INTERFACE}")
    for key in REQUIRED_TOC_KEYS:
        if not meta.get(key):
            problems.append(f"{name}: missing ## {key}")
    for key, value in SAVED.items():
        if meta.get(key) and meta[key] != value:
            problems.append(f"{name}: ## {key} is {meta[key]!r}, expected {value!r}")
    if not files:
        problems.append(f"{name} lists no files")
    for rel in files:
        if not os.path.isfile(_path(ADDON, rel)):
            problems.append(f"{name} lists a missing file: {rel}")
        elif rel.lower().endswith("embeds.xml"):
            check_embeds(_path(ADDON, rel), problems)
            check_required_embeds(_path(ADDON, rel), problems)
    return meta, files


def check(problems):
    results = [check_toc(name, problems) for name in TOCS]
    if all(results):
        (meta_a, files_a), (meta_b, files_b) = results
        if files_a != files_b:
            problems.append(f"{TOCS[0]} and {TOCS[1]} list different files")
        if meta_a != meta_b:
            problems.append(f"{TOCS[0]} and {TOCS[1]} have different ## fields")
        listed = {f.replace("\\", "/") for f in files_a}
        for path in lua_files():
            rel = os.path.relpath(path, ADDON).replace(os.sep, "/")
            if rel not in listed:
                problems.append(f"{NAME}/{rel} is not listed in the TOC")
    check_locale(problems)


def main():
    problems = []
    check(problems)
    for p in problems:
        print(p)
    print(f"Addon check: {len(problems)} problem(s).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
