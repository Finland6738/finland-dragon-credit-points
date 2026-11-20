"""Offline checks of the addon folder: both TOC files (interface and fields), listed files, embeds.xml (Libs only when
fetched).

Adapted from Azeroth Accord (tools/check_addon.py), same owner, GPL-3.0.

The locale tables are checked by tools/check_locale.py (M1-5).

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
LUA_DIRS = ("Core", "Domain", "Adapters", "App", "Net", "UI")
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


def check_assets(problems):
    """UI/Assets.lua is the one table of texture and font files: every path in it exists in Media/ and every file of
    Media/ (except the licence texts of Media/Fonts) is listed (M1-7)."""
    table = os.path.join(ADDON, "UI", "Assets.lua")
    media = os.path.join(ADDON, "Media")
    if not os.path.isfile(table):
        return   # the design phase has no UI yet
    with open(table, encoding="utf-8") as f:
        text = f.read()
    listed = {}
    for line in text.splitlines():
        m = re.search(r'(MEDIA|FONTS)\s*\.\.\s*"([^"]+\.(?:tga|ttf))"', line)
        if m:
            listed[("Fonts/" if m.group(1) == "FONTS" else "") + m.group(2)] = True
    for rel in listed:
        if not os.path.isfile(os.path.join(media, *rel.split("/"))):
            problems.append(f"UI/Assets.lua lists a missing file: Media/{rel}")
    for folder, _, names in os.walk(media):
        for name in names:
            rel = os.path.relpath(os.path.join(folder, name), media).replace(os.sep, "/")
            if rel.endswith("-OFL.txt") and rel.startswith("Fonts/"):
                continue
            if rel not in listed:
                problems.append(f"Media/{rel} is not listed in UI/Assets.lua")
    for family in ("Outfit", "JetBrainsMono", "Orbitron"):
        if not os.path.isfile(os.path.join(media, "Fonts", family + "-OFL.txt")):
            problems.append(f"Media/Fonts/{family}-OFL.txt (the licence) is missing")


def check(problems):
    check_assets(problems)
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


def main():
    problems = []
    check(problems)
    for p in problems:
        print(p)
    print(f"Addon check: {len(problems)} problem(s).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
