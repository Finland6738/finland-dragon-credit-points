"""Merges the community-site files FDCP saved in the SavedVariables into a checkout of the community site (M6-4).

The addon (Domain/SiteExport.lua, App/SiteExportService.lua) saves, at every night close and on request, the three files of
the site's WoW Forever page as JSON text in `FinlandDragonCreditPointsDB.global.guilds["<realm>/<guild>"].siteExport`. This
script reads them after a /reload or the end of the game session and MERGES them into `content/games/wow-forever/` of the
site: it writes only what FDCP knows (the guild's own faction) and keeps everything else (the other faction's players and
dates, older seasons, covers, locked instances, keys it does not know). It uses no git and touches only those three files.
docs/specs/site-export.md §5 and §6.2 say what is merged how; the rules checked before anything is written are the ones of the
site's scripts/validate.mjs (classes, roles, players in the season's roster, cost 0-2) plus dates and the known factions.

Usage:
  python -X utf8 tools/site_export.py --wow "<WoW folder>" --site ../nebula-community/nebula-community [--dry-run]
  python -X utf8 tools/site_export.py --saved <FinlandDragonCreditPoints.lua> --site <site folder> [--guild "<realm>/<guild>"]

  --wow DIR         the WoW folder; reads DIR/_forever_/WTF/Account/<account>/SavedVariables/FinlandDragonCreditPoints.lua
  --account NAME    the account folder, when there are several (default: the one that has the file)
  --flavor NAME     the game folder under --wow (default: _forever_)
  --saved FILE      the SavedVariables file itself (instead of --wow)
  --guild KEY       the guild's key "<realm>/<guild>" when the file has several guilds with an export
  --site DIR        the site's checkout (the folder that has content/)
  --only LIST       roster,loot,progress (default: all three)
  --dry-run         show what would change as a diff and write nothing
  --csv-dir DIR     also write roster.csv and awards.csv (the site's Google Sheets path) for the newest season
Exit code: 0 done (or nothing to change), 1 a rule of the site would fail (nothing is written), 2 a file or option is wrong.
Python 3, no other dependency.
"""
import argparse
import copy
import datetime
import difflib
import glob
import json
import os
import re
import sys

ADDON = "FinlandDragonCreditPoints"
DB_NAME = ADDON + "DB"
CONTENT = os.path.join("content", "games", "wow-forever")
CLASSES = ("warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid")
ROLES = ("tank", "healer", "dps")
FILES = ("roster", "loot", "progress")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


class ExportError(Exception):
    """A wrong file or option (exit code 2)."""


# ------------------------------------------------------------------------------------------------------------------
# The SavedVariables file: a Lua table literal

_WS = re.compile(r"(?:\s+|--(?!\[\[)[^\n]*)+")
_NUM = re.compile(r"-?(?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)")
_NAME = re.compile(r"[A-Za-z_][A-Za-z_0-9]*")
_ESC = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


class _Lua:
    def __init__(self, text):
        self.s, self.i = text, 0

    def skip(self):
        m = _WS.match(self.s, self.i)
        if m:
            self.i = m.end()

    def fail(self, what):
        line = self.s.count("\n", 0, self.i) + 1
        raise ExportError(f"SavedVariables: {what} at line {line}")

    def string(self):
        q = self.s[self.i]
        self.i += 1
        out = bytearray()   # a decimal escape is one byte of a UTF-8 text (the client writes them so): decoded at the end
        s = self.s
        while True:
            j = self.i
            while j < len(s) and s[j] not in (q, "\\"):
                j += 1
            if j >= len(s):
                self.fail("a string is not closed")
            out += s[self.i:j].encode("utf-8")
            self.i = j + 1
            if s[j] == q:
                return out.decode("utf-8", errors="replace")
            c = s[self.i]
            if c.isdigit():
                m = re.match(r"\d{1,3}", s[self.i:])
                out.append(int(m.group(0)) & 255)
                self.i += len(m.group(0))
            else:
                out += _ESC.get(c, c).encode("utf-8")
                self.i += 1

    def value(self):
        self.skip()
        s, i = self.s, self.i
        if i >= len(s):
            self.fail("unexpected end")
        c = s[i]
        if c == "{":
            return self.table()
        if c in "\"'":
            return self.string()
        m = _NUM.match(s, i)
        if m:
            self.i = m.end()
            t = m.group(0)
            try:
                if re.match(r"-?0[xX]", t):
                    return int(t, 16)
                return int(t) if re.fullmatch(r"-?\d+", t) else float(t)
            except ValueError:
                self.fail("bad number")
        m = _NAME.match(s, i)
        if m:
            self.i = m.end()
            word = m.group(0)
            if word == "true":
                return True
            if word == "false":
                return False
            if word == "nil":
                return None
            if word in ("inf", "math"):
                self.fail("unsupported value")
            self.fail(f"unexpected {word!r}")
        self.fail(f"unexpected {c!r}")

    def table(self):
        self.i += 1
        out, n = {}, 0
        while True:
            self.skip()
            c = self.s[self.i] if self.i < len(self.s) else ""
            if c == "}":
                self.i += 1
                return out
            if c == "":
                self.fail("a table is not closed")
            if c == "[":
                self.i += 1
                key = self.value()
                self.skip()
                if self.s[self.i] != "]":
                    self.fail("expected ]")
                self.i += 1
                self.skip()
                if self.s[self.i] != "=":
                    self.fail("expected =")
                self.i += 1
                out[key] = self.value()
            else:
                m = _NAME.match(self.s, self.i)
                after = self.s[m.end():m.end() + 8].lstrip() if m else ""
                if m and after.startswith("=") and not after.startswith("=="):
                    self.i = m.end()
                    self.skip()
                    self.i += 1
                    out[m.group(0)] = self.value()
                else:
                    n += 1
                    out[n] = self.value()
            self.skip()
            if self.i < len(self.s) and self.s[self.i] in ",;":
                self.i += 1


def parse_saved_variables(text):
    """{ variable name: value } for every top-level `Name = value` of a SavedVariables file (tables become dicts)."""
    lua = _Lua(text)
    out = {}
    while True:
        lua.skip()
        while lua.i < len(text) and text[lua.i] == ";":
            lua.i += 1
            lua.skip()
        if lua.i >= len(text):
            return out
        m = _NAME.match(text, lua.i)
        if not m:
            lua.fail("expected a variable name")
        lua.i = m.end()
        lua.skip()
        if text[lua.i] != "=":
            lua.fail("expected =")
        lua.i += 1
        out[m.group(0)] = lua.value()


def find_saved_file(wow, account=None, flavor="_forever_"):
    base = os.path.join(wow, flavor, "WTF", "Account")
    pattern = os.path.join(base, account or "*", "SavedVariables", ADDON + ".lua")
    found = sorted(glob.glob(pattern))
    if not found:
        raise ExportError(f"no {ADDON}.lua under {base} (play once with the addon, then /reload or leave the game)")
    if len(found) > 1:
        names = ", ".join(os.path.basename(os.path.dirname(os.path.dirname(p))) for p in found)
        raise ExportError(f"more than one account has the file ({names}): choose one with --account")
    return found[0]


def pick_record(db, guild=None):
    """The (guild key, siteExport record) to merge: the named guild, or the only one that has an export."""
    guilds = (db.get("global") or {}).get("guilds") or {}
    have = {k: g["siteExport"] for k, g in guilds.items() if isinstance(g, dict) and isinstance(g.get("siteExport"), dict)}
    if guild is not None:
        if guild not in have:
            raise ExportError(f"the guild {guild!r} has no export: {sorted(have) or 'none has one yet'}")
        return guild, have[guild]
    if not have:
        raise ExportError("no guild has an export yet: open History > Export > Site and press the save button, or close a night")
    if len(have) > 1:
        raise ExportError(f"several guilds have an export ({', '.join(sorted(have))}): choose one with --guild")
    key = next(iter(have))
    return key, have[key]


def load_record(path, guild=None):
    """Reads a SavedVariables file and returns (guild key, record, files) with the three files parsed from their JSON."""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        raise ExportError(f"cannot read {path} ({e.strerror or e})")
    db = parse_saved_variables(text).get(DB_NAME)
    if not isinstance(db, dict):
        raise ExportError(f"{path}: no {DB_NAME} in the file")
    key, rec = pick_record(db, guild)
    raw = rec.get("files")
    if not isinstance(raw, dict) or not all(isinstance(raw.get(n), str) for n in FILES):
        raise ExportError(f"the export of {key} has no three files: save it again from the addon")
    files = {}
    for n in FILES:
        try:
            files[n] = json.loads(raw[n])
        except ValueError as e:
            raise ExportError(f"the saved {n}.json is not valid JSON ({e})")
    faction = rec.get("faction")
    if not isinstance(faction, str) or not faction:
        raise ExportError(f"the export of {key} has no site faction")
    return key, rec, files


# ------------------------------------------------------------------------------------------------------------------
# The merge

def is_date(v):
    return isinstance(v, str) and bool(DATE_RE.match(v))


def _placeholder_seasons(data):
    return bool(data.get("example"))


def merge_roster(old, new, faction):
    """roster.json: the other factions' players are kept, the guild's faction is replaced by the export."""
    old = copy.deepcopy(old) if isinstance(old, dict) else {}
    sample = old.pop("example", False)
    players = [] if sample else [p for p in old.get("players", []) if isinstance(p, dict) and p.get("faction") != faction]
    out = old
    out["updated"] = new.get("updated", out.get("updated", ""))
    out["players"] = players + list(new.get("players", []))
    return out


def _raid_key(r, m0):
    m, d = (r.get("date") or "00/00").split("/")[::-1]
    try:
        return ((int(m) - m0) % 12) * 31 + int(d)
    except ValueError:
        return 0


def _merge_season(old, new, faction):
    """One season present in both: the faction's roster rows and raids are replaced, the others are kept."""
    out = copy.deepcopy(old)
    own_old = {p.get("name") for p in old.get("roster", []) if p.get("faction") == faction}
    own = own_old | {p["name"] for p in new.get("roster", [])}
    other = [p for p in old.get("roster", []) if p.get("faction") != faction]
    out["roster"] = other + list(new.get("roster", []))
    ours = list(new.get("raids", []))
    keep = []
    for r in old.get("raids", []):
        players = {a.get("player") for a in r.get("awards", [])}
        if players and players <= own:
            continue    # a raid of the guild (every award is a player of its roster): the export has the current state
        if not players and any(r.get("date") == o.get("date") and r.get("instance") == o.get("instance") for o in ours):
            continue    # an empty column of the same day and instance: the export's
        keep.append(r)
    used = {r.get("id") for r in keep}
    for r in ours:
        r = copy.deepcopy(r)
        if r.get("id") in used:
            r["id"] = f"{r['id']}-{faction}"
        used.add(r["id"])
        keep.append(r)
    if keep and ours:
        m0 = int((ours[0].get("date") or "01/01").split("/")[1] or 1)
        keep = [r for _, r in sorted(enumerate(keep), key=lambda t: (_raid_key(t[1], m0), t[0]))]
    out["raids"] = keep
    for k in ("season", "closed"):
        if k in new:
            out[k] = new[k]
    u1, u2 = old.get("updated"), new.get("updated")
    out["updated"] = max(u1, u2) if is_date(u1) and is_date(u2) else (u2 or u1)
    return out


def merge_loot(old, new, faction):
    """loot.json: seasons newest first; a season of the export replaces the guild's part of the same season of the site."""
    old = copy.deepcopy(old) if isinstance(old, dict) else {}
    sample = old.pop("example", False)
    seasons = [] if sample else [s for s in old.get("seasons", []) if isinstance(s, dict)]
    anchor = None   # where the previous (newer) season of the export sits: a season the site lacks goes right after it
    for s in new.get("seasons", []):
        i = next((k for k, x in enumerate(seasons) if str(x.get("season")) == str(s.get("season"))), None)
        if i is None:
            i = 0 if anchor is None else anchor + 1
            seasons.insert(i, copy.deepcopy(s))
        else:
            seasons[i] = _merge_season(seasons[i], s, faction)
        anchor = i
    old["seasons"] = seasons
    return old


def _factions_of(instances):
    keys = []
    for ins in instances:
        for b in ins.get("bosses", []):
            for k in b:
                if k != "name" and k not in keys:
                    keys.append(k)
    return keys


def merge_progress(old, new, faction):
    """progress.json: the guild's key only; a date never moves forward; cover, locked, the instances to come, the other keys stay."""
    old = copy.deepcopy(old) if isinstance(old, dict) else {}
    sample = old.pop("example", False)
    instances = [i for i in old.get("instances", []) if isinstance(i, dict)]
    if sample:   # placeholders such as [[AAAA-MM-GG]] count as a kill on the site: only real dates stay
        for ins in instances:
            for b in ins.get("bosses", []):
                for k in list(b):
                    if k != "name" and not is_date(b[k]):
                        b[k] = None
    others = [k for k in _factions_of(instances) if k != faction]
    for n_ins in new.get("instances", []):
        ins = next((i for i in instances if i.get("id") == n_ins.get("id")), None)
        if ins is None:
            ins = next((i for i in instances if i.get("name") == n_ins.get("name")), None)
        if ins is None:
            ins = {"id": n_ins["id"], "name": n_ins["name"], "size": n_ins.get("size"), "bosses": []}
            at = next((j for j, i in enumerate(instances) if i.get("locked")), len(instances))
            instances.insert(at, ins)
        bosses = ins.setdefault("bosses", [])
        for pos, n_boss in enumerate(n_ins.get("bosses", [])):
            boss = next((b for b in bosses if b.get("name") == n_boss.get("name")), None)
            if boss is None:
                boss = {"name": n_boss["name"]}
                for k in others:
                    boss[k] = None
                bosses.insert(min(pos, len(bosses)), boss)
            date = n_boss.get(faction)
            cur = boss.get(faction)
            if is_date(date):
                boss[faction] = date if not is_date(cur) else min(cur, date)   # never a later date than the one already there
            elif faction not in boss:
                boss[faction] = None
    old["instances"] = instances
    return old


# ------------------------------------------------------------------------------------------------------------------
# The site's rules (scripts/validate.mjs) and a few more

def validate(roster, loot, progress, known_factions=None):
    """The problems of the three files, as a list of texts (empty = the site would build them)."""
    errors = []
    for p in roster.get("players", []):
        if p.get("class") not in CLASSES:
            errors.append(f"roster.json: unknown class {p.get('class')!r} ({p.get('name')})")
        if p.get("role") not in ROLES:
            errors.append(f"roster.json: invalid role {p.get('role')!r} ({p.get('name')})")
        if known_factions and p.get("faction") not in known_factions:
            errors.append(f"roster.json: faction {p.get('faction')!r} is not in game.json ({p.get('name')})")
    if "updated" in roster and not is_date(roster["updated"]):
        errors.append(f"roster.json: updated {roster['updated']!r} is not YYYY-MM-DD")
    for i, s in enumerate(loot.get("seasons", []), 1):
        names = {p.get("name") for p in s.get("roster", [])}
        for p in s.get("roster", []):
            if p.get("class") not in CLASSES:
                errors.append(f"loot.json: season {i}, unknown class {p.get('class')!r} ({p.get('name')})")
        for r in s.get("raids", []):
            for a in r.get("awards", []):
                if a.get("player") not in names:
                    errors.append(f"loot.json: {a.get('player')!r} is not in the roster of season {s.get('season')}")
                cost = a.get("cost")
                if isinstance(cost, bool) or cost not in (0, 1, 2):
                    errors.append(f"loot.json: cost {cost!r} is not valid for {a.get('player')} (0, 1 or 2)")
        if "updated" in s and not is_date(s["updated"]):
            errors.append(f"loot.json: season {s.get('season')}: updated {s['updated']!r} is not YYYY-MM-DD")
    for ins in progress.get("instances", []):
        for b in ins.get("bosses", []):
            for k, v in b.items():
                if k != "name" and v is not None and not is_date(v):
                    errors.append(f"progress.json: {ins.get('name')} / {b.get('name')}: {k} is {v!r}, not YYYY-MM-DD or null")
    return errors


def known_factions(site):
    """The faction names of the site's game.json (the ones the pages know), or None when it has none."""
    path = os.path.join(site, CONTENT, "game.json")
    try:
        with open(path, encoding="utf-8") as f:
            names = [x.get("name") for x in json.load(f).get("factions", []) if isinstance(x, dict)]
    except (OSError, ValueError):
        return None
    return set(names) or None


# ------------------------------------------------------------------------------------------------------------------
# Files

def dumps(data):
    """The site's JSON style: two spaces, UTF-8 as it is, LF, one final newline."""
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}
    except ValueError as e:
        raise ExportError(f"{path}: not valid JSON ({e})")


def read_text(path):
    try:
        with open(path, encoding="utf-8", newline="") as f:
            return f.read()
    except FileNotFoundError:
        return ""


def sheet_csv(loot):
    """The site's Google Sheets path (src/kit/Wow.jsx): roster(name,class,spec,faction) and awards(raid_id,instance,date,
    bosses,player,item,cost) of the newest season. The site splits a line on commas without quotes: a comma becomes a space."""
    def cell(v):
        return str(v).replace(",", " ").replace("\n", " ").strip()
    seasons = loot.get("seasons") or []
    if not seasons:
        return "name,class,spec,faction\n", "raid_id,instance,date,bosses,player,item,cost\n"
    s = seasons[0]
    roster = ["name,class,spec,faction"] + [",".join(cell(p.get(k, "")) for k in ("name", "class", "spec", "faction")) for p in s.get("roster", [])]
    awards = ["raid_id,instance,date,bosses,player,item,cost"]
    for r in s.get("raids", []):
        for a in r.get("awards", []):
            awards.append(",".join(cell(x) for x in (r.get("id"), r.get("instance"), r.get("date"), r.get("bosses"), a.get("player"), a.get("item"), a.get("cost"))))
    return "\n".join(roster) + "\n", "\n".join(awards) + "\n"


def run(site, files, faction, only=FILES, dry_run=False, csv_dir=None, out=print):
    """Merges `files` (the three parsed objects of the export) into the site checkout. Returns the exit code."""
    content = os.path.join(site, CONTENT)
    if not os.path.isdir(content):
        raise ExportError(f"{content} does not exist: --site must be the folder of the site's checkout")
    old = {n: read_json(os.path.join(content, n + ".json")) for n in FILES}
    merged = dict(old)
    if "roster" in only:
        merged["roster"] = merge_roster(old["roster"], files["roster"], faction)
    if "loot" in only:
        merged["loot"] = merge_loot(old["loot"], files["loot"], faction)
    if "progress" in only:
        merged["progress"] = merge_progress(old["progress"], files["progress"], faction)
    problems = validate(merged["roster"] if isinstance(merged["roster"], dict) else {}, merged["loot"] if isinstance(merged["loot"], dict) else {},
                        merged["progress"] if isinstance(merged["progress"], dict) else {}, known_factions(site))
    if problems:
        out("The site would refuse these files, so nothing was written:")
        for p in problems:
            out("  - " + p)
        return 1
    changed = 0
    for n in FILES:
        if n not in only:
            continue
        path = os.path.join(content, n + ".json")
        before, after = read_text(path).replace("\r\n", "\n"), dumps(merged[n])
        if before == after:
            out(f"{n}.json: no change")
            continue
        changed += 1
        if dry_run:
            out(f"{n}.json: would change")
            for line in difflib.unified_diff(before.splitlines(), after.splitlines(), f"a/{n}.json", f"b/{n}.json", lineterm="", n=2):
                out(line)
        else:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(after)
            out(f"{n}.json: written")
    if csv_dir and "loot" in only:
        roster_csv, awards_csv = sheet_csv(merged["loot"])
        if dry_run:
            out(f"--csv-dir: would write roster.csv and awards.csv in {csv_dir}")
        else:
            os.makedirs(csv_dir, exist_ok=True)
            for name, text in (("roster.csv", roster_csv), ("awards.csv", awards_csv)):
                with open(os.path.join(csv_dir, name), "w", encoding="utf-8", newline="\n") as f:
                    f.write(text)
            out(f"roster.csv and awards.csv written in {csv_dir}")
    if not changed:
        out("Nothing to change.")
    elif dry_run:
        out("Dry run: nothing was written.")
    else:
        out("Done. Commit the changed files in the site checkout as usual.")
    return 0


def main(argv=None, out=print):
    ap = argparse.ArgumentParser(description="Merge the FDCP export into the community site's content.", add_help=True)
    ap.add_argument("--wow")
    ap.add_argument("--account")
    ap.add_argument("--flavor", default="_forever_")
    ap.add_argument("--saved")
    ap.add_argument("--guild")
    ap.add_argument("--site", required=True)
    ap.add_argument("--only", default=",".join(FILES))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--csv-dir")
    args = ap.parse_args(argv)
    try:
        only = tuple(x.strip() for x in args.only.split(",") if x.strip())
        if not only or any(x not in FILES for x in only):
            raise ExportError("--only takes roster, loot and progress, separated by commas")
        if bool(args.wow) == bool(args.saved):
            raise ExportError("give either --wow or --saved")
        path = args.saved or find_saved_file(args.wow, args.account, args.flavor)
        guild, record, files = load_record(path, args.guild)
        out(f"Export of {guild}: faction {record.get('faction')}, saved {record.get('updated', '?')}")
        warnings = record.get("warnings") or {}
        for w in (warnings if isinstance(warnings, list) else [v for _, v in sorted(warnings.items(), key=lambda kv: str(kv[0]))]):
            out(f"  note: {w}")
        return run(args.site, files, record["faction"], only, args.dry_run, args.csv_dir, out)
    except ExportError as e:
        sys.stderr.write(f"error: {e}\n")
        return 2


if __name__ == "__main__":
    sys.exit(main())
