"""Offline check of the locales and of the "no text in code" rule (docs/ANALISI.md §8.5, M1-5).

Rules:
  1. Every language file Locale/<code>.lua (code like itIT) has exactly the keys of Locale/enUS.lua, with the same
     printf placeholders in the same order, registers itself with NewLocale("<code>", ...) and is listed in both TOC
     files. Locale/Boot.lua is the loader, not a language.
  2. Every L["KEY"] used in the code has an English string (a missing one would show the key itself and hide the typo).
  3. Every English key is used somewhere in the code (its quoted name appears in a Lua file outside Locale/); a key that
     only a computed name reaches is declared with a comment `-- locale-key: NAME` next to the code.
  4. No visible text is written in UI/ or Domain/: a string literal that is an argument of a text call (SetText, Print,
     Printf, AddLine, SendChatMessage...), a value of text/title/label/tooltip/desc, or that reads like a sentence (two
     words) fails. A line with `-- nolocale` is exempt (for example a debug-only token).
  The check also runs fixed cases of rule 4 on itself, so a broken checker is reported.

Usage: python -I -X utf8 tools/check_locale.py (also called by tools/check_docs.py)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "FinlandDragonCreditPoints"
ADDON = os.path.join(ROOT, NAME)
LOCALE_DIR = os.path.join(ADDON, "Locale")
CODE_DIRS = ("Core", "Domain", "Adapters", "Net", "UI")
TEXT_DIRS = ("Domain", "UI")
BASE = "enUS"
TOCS = (NAME + ".toc", NAME + "_Camelot.toc")

SINKS = (r"(?:SetText|SetFormattedText|Print|Printf|AddLine|AddDoubleLine|SendChatMessage|print|SetTitle|"
         r"SetStatusText|SetLabel|SetTooltipText)")
FIELDS = r"(?:text|title|label|tooltip|desc|description|header|message|msg)"
WORD = r"[A-Za-zÀ-ɏ]{2,}"
PLACEHOLDER = r"%[\-\d\.]*[sdfxq%]"
COLOR = r"\|c[0-9a-fA-F]{8}|\|r"


def tokens(source):
    """Yields (line, kind, text, position) for every string literal of a Lua source, skipping comments. Literals on a
    line that has a `-- nolocale` comment come with kind 'exempt'."""
    exempt_lines = {source.count("\n", 0, m.start()) + 1 for m in re.finditer(r"--\s*nolocale\b", source)}
    i, n, line = 0, len(source), 1
    while i < n:
        c = source[i]
        if c == "\n":
            line += 1
            i += 1
        elif source.startswith("--", i):
            m = re.match(r"--\[(=*)\[", source[i:])
            if m:
                close = "]" + m.group(1) + "]"
                end = source.find(close, i)
                end = n if end < 0 else end + len(close)
                line += source.count("\n", i, end)
                i = end
            else:
                end = source.find("\n", i)
                i = n if end < 0 else end
        elif c in "\"'":
            j, buf = i + 1, []
            while j < n and source[j] != c and source[j] != "\n":
                if source[j] == "\\" and j + 1 < n:
                    buf.append(source[j:j + 2])
                    j += 2
                else:
                    buf.append(source[j])
                    j += 1
            yield line, ("exempt" if line in exempt_lines else "string"), "".join(buf), i
            i = j + 1
        elif c == "[" and re.match(r"\[=*\[", source[i:]):
            m = re.match(r"\[(=*)\[", source[i:])
            close = "]" + m.group(1) + "]"
            end = source.find(close, i)
            end = n if end < 0 else end + len(close)
            yield line, ("exempt" if line in exempt_lines else "string"), source[i:end], i
            line += source.count("\n", i, end)
            i = end
        else:
            i += 1


def words_of(text):
    return re.findall(WORD, re.sub(PLACEHOLDER + "|" + COLOR + r"|\\[nrt]", "", text))


def find_hardcoded(source, label):
    """The hard-coded visible text of one UI/Domain file: a list of 'label:line: message'."""
    problems = []
    for line, kind, text, pos in tokens(source):
        if kind == "exempt":
            continue
        words = words_of(text)
        if not words:
            continue
        before = source[:pos]
        before = before[before.rfind("\n") + 1:]
        sink = re.search(SINKS + r"\s*\(\s*(?:[^,()]*,\s*)?$", before)
        field = re.search(r"\b" + FIELDS + r"\s*=\s*$", before)
        sentence = len(words) >= 2 and " " in text
        if sink or field or sentence:
            problems.append(f"{label}:{line}: hard-coded visible text {text[:40]!r}: use a locale key (L[\"KEY\"])")
    return problems


def language_files():
    if not os.path.isdir(LOCALE_DIR):
        return {}
    return {name[:-4]: os.path.join(LOCALE_DIR, name) for name in sorted(os.listdir(LOCALE_DIR))
            if re.match(r"^[a-z]{2}[A-Z]{2}\.lua$", name)}


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def keys_of(path):
    """{key: text} of a language file."""
    return dict(re.findall(r'^L\["([^"]+)"\]\s*=\s*"((?:[^"\\]|\\.)*)"', read(path), re.M))


def placeholders(text):
    return re.findall(r"%[\-\d\.]*[sdfxq]", text)


def code_files(dirs):
    for sub in dirs:
        for folder, _, names in os.walk(os.path.join(ADDON, sub)):
            for name in sorted(names):
                if name.endswith(".lua"):
                    yield os.path.join(folder, name)


def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def check_languages(problems):
    files = language_files()
    if BASE not in files:
        problems.append(f"{NAME}/Locale/{BASE}.lua is missing")
        return {}
    base = keys_of(files[BASE])
    for code, path in files.items():
        if code != BASE:
            have = keys_of(path)
            for key in sorted(set(base) - set(have)):
                problems.append(f"{rel(path)}: missing key {key} (translate it; English is only the fallback)")
            for key in sorted(set(have) - set(base)):
                problems.append(f"{rel(path)}: key {key} is not in {BASE}.lua (typo?)")
            for key in sorted(set(base) & set(have)):
                if placeholders(base[key]) != placeholders(have[key]):
                    problems.append(f"{rel(path)}: {key} has placeholders {placeholders(have[key])}, "
                                    f"English has {placeholders(base[key])}")
        if f'NewLocale("{code}"' not in read(path):
            problems.append(f"{rel(path)}: must register itself with NewLocale(\"{code}\", \"<name>\")")
    for toc in TOCS:
        path = os.path.join(ADDON, toc)
        if not os.path.isfile(path):
            continue   # check_addon.py reports it
        listed = {line.strip().replace("\\", "/") for line in read(path).splitlines()}
        for code in files:
            if f"Locale/{code}.lua" not in listed:
                problems.append(f"{NAME}/{toc}: does not list Locale\\{code}.lua")
    return base


def check_usage(base, problems):
    used, text_all = {}, []
    boot = os.path.join(LOCALE_DIR, "Boot.lua")   # the loader formats numbers and dates with keys it reads by name
    if os.path.isfile(boot):
        text_all.append(read(boot))
    for path in code_files(CODE_DIRS):
        source = read(path)
        text_all.append(source)
        for key in re.findall(r'\bL\["([A-Za-z0-9_]+)"\]', source):
            used.setdefault(key, path)
    for key, path in sorted(used.items()):
        if key not in base:
            problems.append(f"{rel(path)}: L[\"{key}\"] has no string in Locale/{BASE}.lua")
    code = "\n".join(text_all)
    declared = set()
    for group in re.findall(r"--\s*locale-key:\s*([A-Z0-9_ ,]+)", code):
        declared.update(k for k in re.split(r"[ ,]+", group.strip()) if k)
    for key in sorted(base):
        if key not in used and key not in declared and f'"{key}"' not in code:
            problems.append(f"Locale/{BASE}.lua: key {key} is not used in the code (remove it, or mark a computed use "
                            f"with `-- locale-key: {key}`)")


def check_hardcoded(problems):
    for path in code_files(TEXT_DIRS):
        problems.extend(find_hardcoded(read(path), rel(path)))


CASES = [   # (source, number of problems expected)
    ('frame:SetText("Hello world")', 1),
    ('frame:SetText(L["HELLO"])', 0),
    ('local t = { title = "Credits" }', 1),
    ('local t = { name = "CREDITS_LIST" }', 0),
    ('x = "Two words"', 1),
    ('x = "READ_ONLY"', 0),
    ('x = "Interface\\\\Icons\\\\INV_Misc_Coin_01"', 0),
    ('x = "Two words" -- nolocale', 0),
    ('-- frame:SetText("Hello world")', 0),
    ('x = "%s: %d"', 0),
    ('self:Print("Done")', 1),
    ('x = [[Long text here]]', 1),
    ('self:Print(L["DONE"]:format("x"))', 0),
]


def selftest(problems):
    for source, expected in CASES:
        got = len(find_hardcoded(source, "case"))
        if got != expected:
            problems.append(f"tools/check_locale.py: {source!r} gave {got} problem(s), expected {expected}")


def check(problems):
    selftest(problems)
    base = check_languages(problems)
    if base:
        check_usage(base, problems)
    check_hardcoded(problems)


def main():
    problems = []
    check(problems)
    for p in problems:
        print(p)
    print(f"Locale check: {len(problems)} problem(s).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
