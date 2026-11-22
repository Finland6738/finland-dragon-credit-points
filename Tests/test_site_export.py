"""Tests of tools/site_export.py (M6-4): reads the SavedVariables the addon writes and merges the three site files into a
COPY of the site's content, in a temporary folder (the site's own checkout is never touched).

The three exports are the golden files of Tests/golden/site_*.json that Tests/test_site_export.lua builds from a ledger, so
the Lua side and the Python side are checked against the same bytes. The "site" is the fixture in Tests/fixtures/site/: both
factions, an older season, a cover, a locked instance, keys the addon does not know.

Usage: python -I -X utf8 -m unittest discover -s Tests -p "test_*.py"
"""
import contextlib
import importlib.util
import io
import json
import os
import shutil
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GOLDEN = os.path.join(HERE, "golden")
FIXTURE = os.path.join(HERE, "fixtures", "site")

spec = importlib.util.spec_from_file_location("site_export", os.path.join(ROOT, "tools", "site_export.py"))
se = importlib.util.module_from_spec(spec)
spec.loader.exec_module(se)


def golden(name):
    with open(os.path.join(GOLDEN, name), encoding="utf-8") as f:
        return f.read()


def lua_string(text):
    """A Lua string literal the way the client writes it in a SavedVariables file: UTF-8 bytes as they are, escapes for the rest."""
    out = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
    return '"' + out + '"'


def saved_variables(files, faction="Nebulah", guild="TestRealm/Keepers", extra_guilds=""):
    """The text of a FinlandDragonCreditPoints.lua with one guild's siteExport (the files as JSON text)."""
    return (
        "FinlandDragonCreditPointsDB = {\n"
        '["global"] = {\n'
        '["schema"] = 1,\n'
        '["guilds"] = {\n'
        f'[{lua_string(guild)}] = {{\n'
        '["ledger"] = {\n["events"] = {},\n["heads"] = {},\n["top"] = {},\n["snapshots"] = {},\n["schema"] = 1,\n},\n'
        '["siteExport"] = {\n'
        '["updated"] = "2026-10-29",\n["season"] = "S2",\n'
        f'["faction"] = {lua_string(faction)},\n["extended"] = false,\n'
        '["files"] = {\n'
        + "".join(f'[{lua_string(n)}] = {lua_string(files[n])},\n' for n in ("roster", "loot", "progress"))
        + "},\n"
        '["warnings"] = {\n"AWARD_NOT_MEMBER:1:2", -- [1]\n"NIGHT_OPEN:1:2", -- [2]\n},\n'
        "},\n},\n"
        + extra_guilds
        + "},\n},\n"
        '["profileKeys"] = { ["Aurel - TestRealm"] = "Default", },\n'
        "}\n"
        "FinlandDragonCreditPointsCharDB = {}\n"
    )


def golden_files():
    return {"roster": golden("site_roster.json"), "loot": golden("site_loot.json"), "progress": golden("site_progress.json")}


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="fdcp-site-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.site = os.path.join(self.tmp, "site")
        self.content = os.path.join(self.site, "content", "games", "wow-forever")
        os.makedirs(self.content)
        for name in ("game", "roster", "loot", "progress"):
            shutil.copy(os.path.join(FIXTURE, name + ".json"), os.path.join(self.content, name + ".json"))
        self.files = {n: json.loads(t) for n, t in golden_files().items()}
        self.log = []

    def put_example(self, name):
        shutil.copy(os.path.join(FIXTURE, name + "_example.json"), os.path.join(self.content, name + ".json"))

    def read(self, name):
        with open(os.path.join(self.content, name + ".json"), encoding="utf-8") as f:
            return json.load(f)

    def text(self, name):
        with open(os.path.join(self.content, name + ".json"), encoding="utf-8", newline="") as f:
            return f.read()

    def merge(self, **kw):
        return se.run(self.site, self.files, kw.pop("faction", "Nebulah"), out=self.log.append, **kw)


class TestGoldenFiles(unittest.TestCase):
    """The Lua exports are JSON the site's rules accept."""

    def test_the_golden_files_are_valid_json_and_pass_the_site_rules(self):
        files = {n: json.loads(t) for n, t in golden_files().items()}
        self.assertEqual(se.validate(files["roster"], files["loot"], files["progress"], {"Nebulah", "Nebulaa"}), [])
        for n in ("site_fragment_roster.json", "site_fragment_loot.json", "site_fragment_progress.json", "site_loot_extended.json"):
            json.loads(golden(n))

    def test_the_site_rules_refuse_what_validate_mjs_refuses(self):
        roster = {"players": [{"name": "A", "class": "monk", "role": "tank", "faction": "Nebulah"},
                              {"name": "B", "class": "mage", "role": "support", "faction": "Nebulah"}]}
        loot = {"seasons": [{"season": "1", "roster": [{"name": "A", "class": "mage"}, {"name": "C", "class": "dragon"}],
                              "raids": [{"awards": [{"player": "X", "cost": 1}, {"player": "A", "cost": 3},
                                                    {"player": "A", "cost": -1}, {"player": "A", "cost": 1.5}]}]}]}
        problems = se.validate(roster, loot, {"instances": []}, {"Nebulah"})
        text = "\n".join(problems)
        for needle in ("unknown class 'monk'", "invalid role 'support'", "unknown class 'dragon'", "'X' is not in the roster",
                       "cost 3 ", "cost -1 ", "cost 1.5 "):
            self.assertIn(needle, text)
        self.assertEqual(len(problems), 7)

    def test_unknown_faction_and_bad_dates_are_refused(self):
        problems = se.validate({"updated": "yesterday", "players": [{"name": "A", "class": "mage", "role": "dps", "faction": "Nebuloh"}]},
                               {"seasons": []}, {"instances": [{"name": "I", "bosses": [{"name": "B", "Nebulah": "[[AAAA-MM-GG]]"}]}]}, {"Nebulah"})
        self.assertEqual(len(problems), 3)


class TestSavedVariables(unittest.TestCase):
    def test_reads_the_export_of_the_guild(self):
        path = os.path.join(tempfile.mkdtemp(prefix="fdcp-sv-"), "FinlandDragonCreditPoints.lua")
        self.addCleanup(shutil.rmtree, os.path.dirname(path), ignore_errors=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(saved_variables(golden_files()))
        key, rec, files = se.load_record(path)
        self.assertEqual(key, "TestRealm/Keepers")
        self.assertEqual(rec["faction"], "Nebulah")
        self.assertEqual(rec["warnings"][1], "AWARD_NOT_MEMBER:1:2")
        self.assertEqual(files["roster"], json.loads(golden("site_roster.json")))
        self.assertEqual(files["loot"]["seasons"][0]["roster"][5]["name"], "Édda", "UTF-8 names survive the round trip")
        self.assertEqual(files["progress"]["instances"][1]["name"], "Onyxia\u2019s Lair")

    def test_the_lua_syntax_the_client_writes(self):
        text = ('Name = {\n["a"] = "x\\ny \\"q\\" \\195\\137",\n["n"] = { 1, 2.5, -3, 0x10, 1e+3, true, false, },\n'
                '[1] = "one", -- [1]\nplain = nil,\n["t"] = {}, };\nOther = "s"\n')
        db = se.parse_saved_variables(text)
        self.assertEqual(db["Name"]["a"], 'x\ny "q" \u00c9')
        self.assertEqual(list(db["Name"]["n"].values()), [1, 2.5, -3, 16, 1000.0, True, False])
        self.assertEqual(db["Name"][1], "one")
        self.assertIsNone(db["Name"]["plain"])
        self.assertEqual(db["Name"]["t"], {})
        self.assertEqual(db["Other"], "s")

    def test_a_broken_file_is_an_error_with_a_line(self):
        with self.assertRaises(se.ExportError) as ctx:
            se.parse_saved_variables('A = {\n["x"] = "never closed,\n}\n')
        self.assertIn("line", str(ctx.exception))

    def test_several_guilds_need_a_choice_and_none_is_an_error(self):
        two = saved_variables(golden_files(), extra_guilds='["Other/Wolves"] = {\n["siteExport"] = {["faction"] = "Nebulaa", ["files"] = {}},\n},\n')
        db = se.parse_saved_variables(two)["FinlandDragonCreditPointsDB"]
        with self.assertRaises(se.ExportError) as ctx:
            se.pick_record(db)
        self.assertIn("--guild", str(ctx.exception))
        self.assertEqual(se.pick_record(db, "TestRealm/Keepers")[0], "TestRealm/Keepers")
        with self.assertRaises(se.ExportError):
            se.pick_record({"global": {"guilds": {"x/y": {"ledger": {}}}}})

    def test_finds_the_file_of_the_only_account(self):
        tmp = tempfile.mkdtemp(prefix="fdcp-wow-")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        sv = os.path.join(tmp, "_forever_", "WTF", "Account", "ACCOUNT1", "SavedVariables")
        os.makedirs(sv)
        path = os.path.join(sv, "FinlandDragonCreditPoints.lua")
        open(path, "w", encoding="utf-8").write("x = 1\n")
        self.assertEqual(se.find_saved_file(tmp), path)
        sv2 = os.path.join(tmp, "_forever_", "WTF", "Account", "ACCOUNT2", "SavedVariables")
        os.makedirs(sv2)
        open(os.path.join(sv2, "FinlandDragonCreditPoints.lua"), "w", encoding="utf-8").write("x = 1\n")
        with self.assertRaises(se.ExportError):
            se.find_saved_file(tmp)
        self.assertEqual(se.find_saved_file(tmp, "ACCOUNT1"), path)


class TestMerge(Base):
    def test_roster_keeps_the_other_faction_and_replaces_the_guilds(self):
        self.assertEqual(self.merge(), 0)
        r = self.read("roster")
        self.assertEqual(r["_readme"], "Roster raid attivo, per fazione. Solo main dichiarati (Raider e Trial).")
        self.assertEqual(r["updated"], "2026-10-29")
        names = [(p["name"], p["faction"]) for p in r["players"]]
        self.assertEqual(names[:2], [("Zed", "Nebulaa"), ("Yara", "Nebulaa")], "the other faction stays, first")
        self.assertNotIn(("Mordo", "Nebulah"), names, "a player of the guild who left the roster is gone")
        self.assertEqual([n for n, f in names if f == "Nebulah"], ["Corin", "Hadri", "Dara", "Ivo", "Bryn", "Aurel"])
        aurel = next(p for p in r["players"] if p["name"] == "Aurel")
        self.assertEqual((aurel["spec"], aurel["role"]), ("Protection", "tank"), "the export wins for the guild's players")

    def test_loot_merges_a_season_shared_by_the_two_factions_and_keeps_the_old_one(self):
        self.merge()
        loot = self.read("loot")
        self.assertEqual([s["season"] for s in loot["seasons"]], ["2", "1", "0"], "newest first, the season of before the addon stays")
        s2 = loot["seasons"][0]
        self.assertEqual({p["name"] for p in s2["roster"] if p["faction"] == "Nebulaa"}, {"Zed", "Yara"})
        self.assertEqual({p["name"] for p in s2["roster"] if p["faction"] == "Nebulah"},
                         {"Corin", "Hadri", "Dara", "Ivo", "Bryn", "\u00c9dda", "Aurel"}, "Mordo's old row is replaced by the export's")
        ids = [r["id"] for r in s2["raids"]]
        self.assertEqual(ids, ["s2-r1", "s2-r1-Nebulah", "s2-r2", "s2-r3"], "the other faction's raid stays; ours gets a free id")
        self.assertEqual([r["date"] for r in s2["raids"]], ["12/10", "14/10", "21/10", "21/10"], "by date")
        theirs = s2["raids"][0]
        self.assertEqual([a["player"] for a in theirs["awards"]], ["Zed", "Yara"])
        self.assertEqual(s2["updated"], "2026-10-21")
        s0 = loot["seasons"][2]
        self.assertEqual(s0["raids"][0]["awards"][0]["item"], "Cloak of the Shrouded Mists", "the older season is untouched")
        self.assertEqual(s0["roster"][0]["name"], "Mordo")
        s1 = loot["seasons"][1]
        self.assertEqual(s1["raids"][0]["awards"][0]["item"], "Item 77 of the Test", "a season the site did not have is added")
        self.assertEqual(loot["_readme"][:20], "Tabella crediti loot", "keys the addon does not know stay")

    def test_the_merged_loot_passes_the_site_rules_and_the_totals_add_up(self):
        self.merge()
        loot = self.read("loot")
        problems = se.validate(self.read("roster"), loot, self.read("progress"), {"Nebulah", "Nebulaa"})
        self.assertEqual(problems, [])
        totals = {}
        for r in loot["seasons"][0]["raids"]:
            for a in r["awards"]:
                totals[a["player"]] = totals.get(a["player"], 0) + a["cost"]
        self.assertEqual(totals["Zed"], 1); self.assertEqual(totals["Yara"], 2)
        self.assertEqual(totals["Aurel"], 5); self.assertEqual(totals["Ivo"], 3 + 2); self.assertEqual(totals["Hadri"], 1 + 1)

    def test_progress_never_moves_a_date_forward_and_keeps_cover_locked_and_the_other_key(self):
        self.merge()
        p = self.read("progress")
        mc = p["instances"][0]
        self.assertEqual(mc["cover"], "media/art/concept-nebula-inn.webp")
        by = {b["name"]: b for b in mc["bosses"]}
        self.assertEqual(by["Lucifron"]["Nebulah"], "2026-09-30", "an earlier first kill replaces a later date")
        self.assertEqual(by["Magmadar"]["Nebulah"], "2026-10-10", "a later date never replaces the one already there")
        self.assertEqual(by["Gehennas"]["Nebulah"], None)
        self.assertEqual(by["Lucifron"]["Nebulaa"], "2026-10-16"); self.assertEqual(by["Gehennas"]["Nebulaa"], "2026-10-19")
        self.assertEqual(len(mc["bosses"]), 10, "the bosses of the table the site did not have are added")
        self.assertIsNone(by["Garr"]["Nebulaa"], "a new boss has null for the other faction")
        ids = [i["id"] for i in p["instances"]]
        self.assertEqual(ids, ["mc", "ony", "next"], "a new instance goes before the ones still to come")
        nxt = p["instances"][2]
        self.assertTrue(nxt["locked"]); self.assertEqual(nxt["name"], "[[PROSSIMA ISTANZA]]")
        self.assertEqual(p["instances"][1]["bosses"], [{"name": "Onyxia", "Nebulaa": None, "Nebulah": "2026-10-21"}])

    def test_a_second_run_changes_nothing(self):
        self.merge()
        before = {n: self.text(n) for n in ("roster", "loot", "progress")}
        self.log.clear()
        self.assertEqual(self.merge(), 0)
        self.assertEqual({n: self.text(n) for n in ("roster", "loot", "progress")}, before)
        self.assertIn("Nothing to change.", self.log)

    def test_a_null_never_erases_a_date_and_the_rest_of_a_file_stays_the_sites(self):
        self.files["progress"]["instances"][0]["bosses"][1]["Nebulah"] = None
        self.merge()
        by = {b["name"]: b for b in self.read("progress")["instances"][0]["bosses"]}
        self.assertEqual(by["Magmadar"]["Nebulah"], "2026-10-10")

    def test_the_files_are_written_in_the_sites_style(self):
        self.merge()
        for n in ("roster", "loot", "progress"):
            t = self.text(n)
            self.assertTrue(t.endswith("}\n")); self.assertNotIn("\r", t); self.assertIn('\n  "', t)
        self.assertIn("\u2019", self.text("progress"), "typographic characters are written as they are")
        self.assertNotIn("\\u2019", self.text("progress"))

    def test_the_example_files_of_a_new_site_are_replaced_not_merged(self):
        for n in ("roster", "loot", "progress"):
            self.put_example(n)
        self.assertEqual(self.merge(), 0)
        r, loot, p = self.read("roster"), self.read("loot"), self.read("progress")
        for d in (r, loot, p):
            self.assertNotIn("example", d, "real data: the site's sample badge goes")
        self.assertEqual({q["name"] for q in r["players"]}, {"Corin", "Hadri", "Dara", "Ivo", "Bryn", "Aurel"})
        self.assertEqual([s["season"] for s in loot["seasons"]], ["2", "1"], "the placeholder season is gone")
        by = {b["name"]: b for b in p["instances"][0]["bosses"]}
        self.assertEqual(by["Lucifron"]["Nebulaa"], None, "a placeholder date would count as a kill on the site")
        self.assertTrue(p["instances"][-1]["locked"])

    def test_missing_files_are_created(self):
        for n in ("roster", "loot", "progress"):
            os.remove(os.path.join(self.content, n + ".json"))
        self.assertEqual(self.merge(), 0)
        self.assertEqual(self.read("roster")["players"][0]["name"], "Corin")
        self.assertEqual(len(self.read("loot")["seasons"]), 2)

    def test_only_one_file(self):
        before = self.text("loot")
        self.assertEqual(self.merge(only=("roster",)), 0)
        self.assertEqual(self.text("loot"), before)
        self.assertEqual(self.read("roster")["updated"], "2026-10-29")

    def test_a_second_faction_adds_its_own_part_without_touching_the_first(self):
        self.merge()
        first = self.text("roster")
        other = {"updated": "2026-11-05", "players": [{"name": "Kira", "class": "mage", "spec": "Frost", "role": "dps", "faction": "Nebulaa", "rank": "Raider"}]}
        self.files = {"roster": other, "loot": {"seasons": []}, "progress": {"instances": []}}
        self.assertEqual(self.merge(faction="Nebulaa"), 0)
        r = self.read("roster")
        self.assertEqual([p["name"] for p in r["players"] if p["faction"] == "Nebulah"], ["Corin", "Hadri", "Dara", "Ivo", "Bryn", "Aurel"])
        self.assertEqual([p["name"] for p in r["players"] if p["faction"] == "Nebulaa"], ["Kira"], "the faction's own players are the export's")
        self.assertNotEqual(first, self.text("roster"))


class TestRefusalsAndDryRun(Base):
    def test_a_file_the_site_would_refuse_writes_nothing(self):
        self.files["loot"]["seasons"][0]["raids"][0]["awards"][0]["cost"] = 5
        before = {n: self.text(n) for n in ("roster", "loot", "progress")}
        self.assertEqual(self.merge(), 1)
        self.assertEqual({n: self.text(n) for n in ("roster", "loot", "progress")}, before)
        self.assertTrue(any("cost 5" in line for line in self.log))

    def test_a_faction_the_site_does_not_know_is_refused(self):
        for p in self.files["roster"]["players"]:
            p["faction"] = "Elsewhere"
        self.assertEqual(self.merge(faction="Elsewhere"), 1)
        self.assertTrue(any("not in game.json" in line for line in self.log))

    def test_dry_run_shows_the_diff_and_writes_nothing(self):
        before = {n: self.text(n) for n in ("roster", "loot", "progress")}
        self.assertEqual(self.merge(dry_run=True), 0)
        self.assertEqual({n: self.text(n) for n in ("roster", "loot", "progress")}, before)
        joined = "\n".join(self.log)
        self.assertIn("roster.json: would change", joined)
        self.assertIn("+      \"name\": \"Corin\"", joined)
        self.assertIn("Dry run: nothing was written.", joined)

    def test_a_site_folder_without_content_is_an_error(self):
        with self.assertRaises(se.ExportError):
            se.run(self.tmp, self.files, "Nebulah", out=self.log.append)

    def test_a_broken_site_file_is_an_error(self):
        with open(os.path.join(self.content, "loot.json"), "w", encoding="utf-8") as f:
            f.write("{ nope")
        with self.assertRaises(se.ExportError):
            self.merge()


class TestSheetCsv(Base):
    def test_writes_the_roster_and_awards_sheets_of_the_newest_season(self):
        csv_dir = os.path.join(self.tmp, "csv")
        self.assertEqual(self.merge(csv_dir=csv_dir), 0)
        with open(os.path.join(csv_dir, "awards.csv"), encoding="utf-8") as f:
            lines = f.read().splitlines()
        self.assertEqual(lines[0], "raid_id,instance,date,bosses,player,item,cost")
        self.assertIn("s2-r1,Molten Core,12/10,3/10,Zed,Sash of Whispered Secrets,1", lines)
        self.assertIn("s2-r1-Nebulah,Molten Core,14/10,2/10,Bryn,Item 1023 of the Test,1", lines)
        with open(os.path.join(csv_dir, "roster.csv"), encoding="utf-8") as f:
            self.assertEqual(f.read().splitlines()[0], "name,class,spec,faction")

    def test_a_comma_in_a_name_cannot_break_the_sites_parser(self):
        loot = {"seasons": [{"roster": [], "raids": [{"id": "s1-r1", "instance": "I", "date": "01/01", "bosses": "1/1",
                                                        "awards": [{"player": "A", "item": "Sword, of Might", "cost": 1}]}]}]}
        _, awards = se.sheet_csv(loot)
        self.assertEqual(awards.splitlines()[1], "s1-r1,I,01/01,1/1,A,Sword  of Might,1")


class TestCommandLine(Base):
    def run_main(self, *args):
        out = io.StringIO()
        code = se.main(list(args), out=lambda s: out.write(s + "\n"))
        return code, out.getvalue()

    def sv(self, **kw):
        path = os.path.join(self.tmp, "FinlandDragonCreditPoints.lua")
        with open(path, "w", encoding="utf-8") as f:
            f.write(saved_variables(golden_files(), **kw))
        return path

    def test_merges_from_a_saved_variables_file(self):
        code, out = self.run_main("--saved", self.sv(), "--site", self.site)
        self.assertEqual(code, 0, out)
        self.assertIn("Export of TestRealm/Keepers: faction Nebulah", out)
        self.assertIn("note: AWARD_NOT_MEMBER:1:2", out)
        self.assertEqual(self.read("roster")["updated"], "2026-10-29")

    def test_dry_run_from_the_wow_folder(self):
        wow = os.path.join(self.tmp, "wow")
        sv = os.path.join(wow, "_forever_", "WTF", "Account", "ACCOUNT1", "SavedVariables")
        os.makedirs(sv)
        shutil.copy(self.sv(), os.path.join(sv, "FinlandDragonCreditPoints.lua"))
        before = self.text("loot")
        code, out = self.run_main("--wow", wow, "--site", self.site, "--dry-run")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.text("loot"), before)
        self.assertIn("would change", out)

    def test_wrong_options_exit_with_2(self):
        self.assertEqual(self.run_main("--site", self.site)[0], 2)
        self.assertEqual(self.run_main("--saved", self.sv(), "--wow", self.tmp, "--site", self.site)[0], 2)
        self.assertEqual(self.run_main("--saved", self.sv(), "--site", self.site, "--only", "bogus")[0], 2)
        self.assertEqual(self.run_main("--saved", os.path.join(self.tmp, "missing.lua"), "--site", self.site)[0], 2)

    def test_refused_files_exit_with_1(self):
        self.files["loot"]["seasons"][0]["raids"][0]["awards"][0]["cost"] = 9
        path = os.path.join(self.tmp, "bad.lua")
        with open(path, "w", encoding="utf-8") as f:
            f.write(saved_variables({n: json.dumps(self.files[n]) for n in self.files}))
        code, out = self.run_main("--saved", path, "--site", self.site)
        self.assertEqual(code, 1)
        self.assertIn("nothing was written", out)


if __name__ == "__main__":
    unittest.main()
