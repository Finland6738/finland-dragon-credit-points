"""Documentation checks run by CI (job "Tests") and before every PR (ADR 0001).

  1. Every relative link in a tracked Markdown file points to an existing file (anchors are not checked).
  2. Every page of docs/wiki/ is listed in docs/wiki/_Sidebar.md, and wiki links ([[Text|Page]] or (Page)) resolve.
  3. The ADR index (docs/adr/README.md) lists every ADR file, and every listed ADR exists.
  4. Privacy: no tracked text file contains an email address (except GitHub noreply addresses) or a personal path
     (a drive letter path, /home/<name> or /Users/<name>).
  5. Text files use LF line endings.
  6. The rules of tools/check_pr_docs.py behave as documented (a few fixed cases).
  7. Roadmap: ROADMAP.md links every milestone file of docs/roadmap/, every step has an id, a branch and a
     "Suggested model/effort" hint, and step ids are unique.
  8. Wiki languages: every English page of docs/wiki/ has its Italian twin <Page>-it.md and the other way round
     (ADR 0003).
  9. From M1 on: the addon TOC (tools/check_addon.py), the release package (tools/check_package.py) and the locales
     (tools/check_locale.py), and the design previews of docs/specs/ (tools/make_mockups.py: every scene builds and has
     its image). Each check runs only once its tool exists, so the design-phase repository passes
     without them.

Usage: python -I -X utf8 tools/check_docs.py      (exit code 0 = all good, 1 = problems, listed one per line)
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEXT_EXT = (".md", ".py", ".yml", ".yaml", ".lua", ".toc", ".xml", ".html", ".css", ".js", ".sh", ".json", ".txt",
            ".gitignore", ".gitattributes", ".pkgmeta")
LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)\)|!\[[^\]]*\]\(([^)\s]+)\)")
WIKI_LINK = re.compile(r"\[\[(?:[^\]|]*\|)?([^\]]+)\]\]")
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
PERSONAL_PATH = re.compile(r"(?<![A-Za-z])[A-Za-z]:[\\/](?:Users|Documents|repository|Program|Blizzard|SteamLibrary)"
                           r"|/home/[a-z]|/Users/[A-Za-z]", re.IGNORECASE)
THIRD_PARTY_LICENCES = ("FinlandDragonCreditPoints/Media/Fonts/",)
ALLOWED_EMAIL = ("users.noreply.github.com", "example.com", "noreply@anthropic.com")


def tracked_files():
    out = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout
    return [f for f in out.splitlines() if f and os.path.isfile(os.path.join(ROOT, f))]


def read(path):
    with open(os.path.join(ROOT, path), "rb") as f:
        return f.read()


def check_links(md_files, problems):
    for path in md_files:
        text = read(path).decode("utf-8", errors="replace")
        text = re.sub(r"```.*?```", "", text, flags=re.S)       # skip code blocks
        text = re.sub(r"`[^`\n]*`", "", text)                   # skip inline code
        base = os.path.dirname(os.path.join(ROOT, path))
        for m in LINK.finditer(text):
            target = m.group(1) or m.group(2)
            if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I) or target.startswith("#"):
                continue
            target = target.split("#")[0].split("?")[0]
            if not target:
                continue
            if path.startswith("docs/wiki/") and "/" not in target and "." not in target:
                continue   # a wiki page link, checked below
            if not os.path.exists(os.path.normpath(os.path.join(base, target))):
                problems.append(f"{path}: broken link -> {target}")


def check_wiki(problems):
    folder = os.path.join(ROOT, "docs", "wiki")
    if not os.path.isdir(folder):
        problems.append("docs/wiki/ is missing")
        return
    pages = {f[:-3] for f in os.listdir(folder) if f.endswith(".md")}
    if "Home" not in pages:
        problems.append("docs/wiki/Home.md is missing")
    sidebar = read("docs/wiki/_Sidebar.md").decode("utf-8") if "_Sidebar" in pages else ""
    listed = set(WIKI_LINK.findall(sidebar)) | set(re.findall(r"\]\(([A-Za-z0-9-]+)\)", sidebar))
    for page in sorted(pages - {"_Sidebar", "_Footer"}):
        if page not in listed:
            problems.append(f"docs/wiki/{page}.md is not listed in docs/wiki/_Sidebar.md")
    for page in sorted(pages):
        text = read(f"docs/wiki/{page}.md").decode("utf-8")
        refs = WIKI_LINK.findall(text) + re.findall(r"\]\(([A-Za-z0-9-]+)(?:#[^)]*)?\)", text)
        for ref in refs:
            if ref.split("#")[0] not in pages:
                problems.append(f"docs/wiki/{page}.md: link to a missing wiki page -> {ref}")


def check_adr_index(problems):
    folder = os.path.join(ROOT, "docs", "adr")
    files = sorted(f for f in os.listdir(folder) if re.match(r"^\d{4}-.+\.md$", f))
    index = read("docs/adr/README.md").decode("utf-8")
    listed = set(re.findall(r"\((\d{4}-[^)]+\.md)\)", index))
    for f in files:
        if f not in listed:
            problems.append(f"docs/adr/README.md does not list {f}")
    for f in sorted(listed - set(files)):
        problems.append(f"docs/adr/README.md lists a missing ADR: {f}")


def check_text_files(files, problems):
    for path in files:
        if not path.endswith(TEXT_EXT) and os.path.basename(path) not in TEXT_EXT:
            continue
        data = read(path)
        if b"\r\n" in data:
            problems.append(f"{path}: CRLF line endings (use LF)")
        text = data.decode("utf-8", errors="replace")
        if path == "tools/check_docs.py":
            continue   # this file contains the patterns themselves
        for m in EMAIL.finditer(text):
            if path.startswith(THIRD_PARTY_LICENCES):
                break   # the unmodified licence text of a font author (an OFL.txt may name its author's address)
            if not m.group(0).lower().endswith(ALLOWED_EMAIL):
                problems.append(f"{path}: email address -> {m.group(0)}")
        for m in PERSONAL_PATH.finditer(text):
            problems.append(f"{path}: personal path -> {m.group(0)}")


def check_rules(problems):
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import check_pr_docs as rule
    cases = [
        (["docs/ANALISI.md"], [], True),
        (["FinlandDragonCreditPoints/Core/Config.lua"], [], False),
        (["FinlandDragonCreditPoints/Core/Config.lua", "CHANGELOG.md"], [], False),
        (["FinlandDragonCreditPoints/Core/Config.lua", "CHANGELOG.md", "docs/wiki/Home.md"], [], True),
        (["FinlandDragonCreditPoints/Core/Config.lua"], ["no-docs-needed"], True),
    ]
    for files, labels, expected in cases:
        ok, _ = rule.evaluate(files, labels)
        if ok != expected:
            problems.append(f"tools/check_pr_docs.py: {files} {labels} gave {ok}, expected {expected}")


STEP_HEAD = re.compile(r"^### (M\d+-\d+[a-z]?) [—-] .+$", re.M)   # a step inserted later keeps its neighbours' ids: M1-6b


def check_roadmap(problems):
    folder = os.path.join(ROOT, "docs", "roadmap")
    if not os.path.isdir(folder):
        problems.append("docs/roadmap/ is missing")
        return
    index = read("ROADMAP.md").decode("utf-8") if os.path.isfile(os.path.join(ROOT, "ROADMAP.md")) else ""
    seen = {}
    for name in sorted(os.listdir(folder)):
        if not re.match(r"^M\d+-.+\.md$", name):
            continue
        if f"docs/roadmap/{name}" not in index:
            problems.append(f"ROADMAP.md does not link docs/roadmap/{name}")
        text = read(f"docs/roadmap/{name}").decode("utf-8")
        parts = STEP_HEAD.split(text)
        if len(parts) < 3:
            problems.append(f"docs/roadmap/{name}: no step found (heading '### M<N>-<k> — Title')")
        for i in range(1, len(parts), 2):
            step, body = parts[i], parts[i + 1]
            if step in seen:
                problems.append(f"docs/roadmap/{name}: step {step} also in {seen[step]}")
            seen[step] = name
            if not name.startswith(step.split("-")[0] + "-"):
                problems.append(f"docs/roadmap/{name}: step {step} belongs to another milestone")
            if "- Branch: `step/" + step.lower() + "-" not in body:
                problems.append(f"docs/roadmap/{name}: step {step} has no branch line `step/{step.lower()}-<name>`")
            if not re.search(r"- Suggested model/effort: `(opus|sonnet|haiku)` / (low|medium|high)", body):
                problems.append(f"docs/roadmap/{name}: step {step} has no 'Suggested model/effort' line")
            if "- [" not in body:
                problems.append(f"docs/roadmap/{name}: step {step} has no checkbox")


def check_wiki_languages(problems):
    folder = os.path.join(ROOT, "docs", "wiki")
    if not os.path.isdir(folder):
        return
    pages = {f[:-3] for f in os.listdir(folder) if f.endswith(".md")} - {"_Sidebar", "_Footer"}
    for page in sorted(pages):
        twin = page[:-3] if page.endswith("-it") else page + "-it"
        if twin not in pages:
            problems.append(f"docs/wiki/{page}.md has no {'English' if page.endswith('-it') else 'Italian'} twin "
                            f"docs/wiki/{twin}.md")


def check_optional(module, problems):
    """Runs tools/<module>.py's check() once that tool exists (from M1-1 on)."""
    if not os.path.isfile(os.path.join(ROOT, "tools", module + ".py")):
        return
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    __import__(module).check(problems)


def main():
    problems = []
    files = tracked_files()
    check_links([f for f in files if f.endswith(".md")], problems)
    check_wiki(problems)
    check_adr_index(problems)
    check_text_files(files, problems)
    check_rules(problems)
    check_roadmap(problems)
    check_wiki_languages(problems)
    check_optional("check_addon", problems)
    check_optional("check_package", problems)
    check_optional("release_notes", problems)
    check_optional("check_locale", problems)
    check_optional("make_mockups", problems)
    for p in problems:
        print(p)
    print(f"{len(files)} files checked, {len(problems)} problem(s).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
