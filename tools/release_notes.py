"""Release notes from CHANGELOG.md, and the "Unreleased" to "[x.y.z]" step of a release (docs/RELEASING.md).

The changelog follows Keep a Changelog: a `## [Unreleased]` section and one `## [x.y.z] - date` section per version.

  python -I -X utf8 tools/release_notes.py v1.0.0 [--out notes.md]
      Prints (or writes) the notes of a tag: the `## [1.0.0]` section; for a pre-release tag such as v0.9.0-beta.1 the
      section of the exact name, else of the base version (0.9.0), else `Unreleased` (a build before the changelog
      was promoted). Without any of them it says to read CHANGELOG.md. The release workflow uses it for the body of the
      GitHub Release. A missing section is not an error (it must not stop a release); only a malformed tag is.

  python -I -X utf8 tools/release_notes.py --promote 1.0.0 [--date 2026-12-01]
      Rewrites CHANGELOG.md: `## [Unreleased]` becomes `## [1.0.0] - <date>` and a new empty `## [Unreleased]` goes on
      top. Run it in the release pull request, before the tag. It refuses a version that is already there.

Also called by tools/check_docs.py: `check(problems)` runs a self-test on made-up text and checks CHANGELOG.md has an
Unreleased section.
"""
import argparse
import datetime
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANGELOG = os.path.join(ROOT, "CHANGELOG.md")
HEADING = re.compile(r"^## \[([^\]]+)\](.*)$", re.M)
TAG = re.compile(r"^v(\d+\.\d+\.\d+)(-(?:alpha|beta|rc)(?:\.\d+)?)?$")


def sections(text):
    """{ name: body } of every `## [name]` section (the body without its heading, stripped)."""
    found = list(HEADING.finditer(text))
    out = {}
    for i, m in enumerate(found):
        end = found[i + 1].start() if i + 1 < len(found) else len(text)
        out[m.group(1)] = text[m.end():end].strip("\n")
    return out


# GitHub refuses a release body above 125000 characters; the first release holds the whole history, so the notes are cut
# at a line boundary well below that and point to the changelog for the rest.
MAX_NOTES = 60000
CHANGELOG_URL = "https://github.com/Finland6738/finland-dragon-credit-points/blob/main/CHANGELOG.md"


def cap(body):
    if len(body) <= MAX_NOTES:
        return body
    cut = body[:MAX_NOTES].rsplit("\n", 1)[0].rstrip()
    return cut + "\n\n...\n\nThe list is long: the complete notes are in [CHANGELOG.md](" + CHANGELOG_URL + ").\n"


def notes_for(tag, text):
    """(notes, which section was used) for a version tag."""
    m = TAG.match(tag)
    if not m:
        raise ValueError(f"{tag!r} is not a version tag")
    exact, base = tag[1:], m.group(1)
    found = sections(text)
    for name in (exact, base, "Unreleased"):
        body = found.get(name, "").strip()
        if body:
            return cap(body + "\n"), name
    return f"See [CHANGELOG.md](https://github.com/Finland6738/finland-dragon-credit-points/blob/main/CHANGELOG.md) for what changed.\n", None


def promote(text, version, date):
    """The changelog with `## [Unreleased]` renamed to `## [version] - date` and a fresh Unreleased on top."""
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError(f"{version!r} is not MAJOR.MINOR.PATCH")
    found = sections(text)
    if version in found:
        raise ValueError(f"CHANGELOG.md already has a section [{version}]")
    if "Unreleased" not in found or not found["Unreleased"].strip():
        raise ValueError("CHANGELOG.md has no Unreleased changes to promote")
    return text.replace("## [Unreleased]", f"## [Unreleased]\n\n## [{version}] - {date}", 1)


def check(problems):
    """Self-test on made-up text, and the real changelog has an Unreleased section."""
    sample = "# Changelog\n\n## [Unreleased]\n\n### Added\n\n- b\n\n## [0.9.0] - 2026-01-01\n\n- a\n"
    try:
        notes, used = notes_for("v0.9.0-beta.1", sample)
        if used != "0.9.0" or notes.strip() != "- a":
            problems.append("tools/release_notes.py: a beta tag should use the section of its base version")
        notes, used = notes_for("v1.0.0", sample)
        if used != "Unreleased" or "- b" not in notes:
            problems.append("tools/release_notes.py: a tag without a section should use Unreleased")
        notes, used = notes_for("v1.0.0", "# Changelog\n")
        if used is not None or "CHANGELOG.md" not in notes:
            problems.append("tools/release_notes.py: a changelog without sections should point to the file")
        out = promote(sample, "1.0.0", "2026-02-02")
        found = sections(out)
        if list(found) != ["Unreleased", "1.0.0", "0.9.0"] or found["Unreleased"].strip() or "- b" not in found["1.0.0"]:
            problems.append("tools/release_notes.py: --promote does not move Unreleased under the new version")
        for bad, args in (("a duplicate version", (out, "1.0.0", "x")), ("an empty Unreleased", (out, "1.1.0", "x")),
                          ("a bad version", (sample, "v1", "x"))):
            try:
                promote(*args)
                problems.append(f"tools/release_notes.py: --promote accepted {bad}")
            except ValueError:
                pass
        try:
            notes_for("1.0.0", sample)
            problems.append("tools/release_notes.py: a tag without the v was accepted")
        except ValueError:
            pass
    except Exception as e:  # noqa: BLE001 - a self-test that crashes is a problem, not a crash
        problems.append(f"tools/release_notes.py: self-test crashed: {e}")
    if os.path.isfile(CHANGELOG):
        with open(CHANGELOG, encoding="utf-8") as f:
            if "Unreleased" not in sections(f.read()):
                problems.append("CHANGELOG.md has no `## [Unreleased]` section")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("tag", nargs="?", help="a version tag such as v1.0.0")
    ap.add_argument("--out", help="write the notes to this file instead of printing them")
    ap.add_argument("--promote", metavar="VERSION", help="rename Unreleased to [VERSION] in CHANGELOG.md")
    ap.add_argument("--date", default=None, help="date of the promoted version (default: today)")
    a = ap.parse_args()
    with open(CHANGELOG, encoding="utf-8") as f:
        text = f.read()
    if a.promote:
        date = a.date or datetime.date.today().isoformat()
        try:
            new = promote(text, a.promote, date)
        except ValueError as e:
            print(f"Not promoted: {e}")
            return 1
        with open(CHANGELOG, "w", encoding="utf-8", newline="\n") as f:
            f.write(new)
        print(f"CHANGELOG.md: Unreleased is now [{a.promote}] - {date}")
        return 0
    if not a.tag:
        ap.error("give a tag, or --promote VERSION")
    try:
        notes, used = notes_for(a.tag, text)
    except ValueError as e:
        print(f"Bad tag: {e}", file=sys.stderr)
        return 1
    if a.out:
        with open(a.out, "w", encoding="utf-8", newline="\n") as f:
            f.write(notes)
    else:
        sys.stdout.write(notes)
    print(f"release notes: {'section [' + used + ']' if used else 'no section, pointing to CHANGELOG.md'}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
