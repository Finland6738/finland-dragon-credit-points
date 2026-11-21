# M6 — History and export

**Goal:** everything that happened is readable and exportable: nights, members, items, the loot log and the audit; the credits table goes to Discord and to the community site straight from the addon; officers keep their ledgers in sync and every member sees the credits read-only ([`docs/ANALISI.md` §7, §8.4](../ANALISI.md#7-storico-log-e-audit)).

**Exit criterion:** the credits table posted on Discord comes from the addon; two officers who ran different nights converge on the same ledger.

Open question 10 ([#3](https://github.com/Finland6738/finland-dragon-credit-points/issues/3)) is still open: until the owner decides, the site export uses only the current `loot.json` fields (reversible default).

### M6-1 — History views: nights, member, item
- Branch: `step/m6-1-history-views`
- Depends on: M3-8, M4-4
- Analysis: §7 (views); [`docs/specs/ui-style.md`](../specs/ui-style.md) §6
- Scope: the **History** tab (sub-tabs Nights · Log · Audit · Export, look per `ui-style.md`): query functions over the ledger and the Nights sub-tab, `UI/Windows/Member.lua`, `UI/Windows/Item.lua`: nights by week (instance, bosses, lineup, bench, drops, credits spent), a member's items, credit curve, attendance and council actions about them (attendance visible only to officers), an item's drops and owners.
- Done when:
  - [ ] Views match the ledger in tests; members never see attendance.
- Tests: `Tests/test_history.lua`.
- Docs: wiki **History** (EN + IT), CHANGELOG.
- Real client: the windows in game.
- Suggested model/effort: `sonnet` / medium

### M6-1b — Season management window
- Branch: `step/m6-1b-season-window`
- Depends on: M2-5 (`Domain/Season.lua`), M2-6 (permissions), M4-9 (the gap found there), M1-7 (theme)
- Analysis: §6, §9.3 (windows), §8.3 (ledger events), permission `season.manage`
- Scope: a window for the season lifecycle, replacing the `/run` workaround of `docs/checklists/M4.md`. A holder of `season.manage` (the Guild Master by default) opens a season and closes it from the UI: picks the pack of instances from `Data/Instances.lua`, the raid size of each, and the late-join rule and the start credits; sees a summary and must confirm explicitly (closing a season asks a second, separate confirmation). Both actions are audited ledger events (`SEASON_OPEN`, `SEASON_CLOSE`) through `Season.Open` / `Season.Close` and the permission gate; nothing is deleted. Every member sees the current season (name, instances, rule, state) read-only; members without the permission get no buttons. Follows [`docs/specs/ui-style.md`](../specs/ui-style.md); every string through a locale key (itIT + enUS).
- Done when:
  - [ ] Offline: the window opens a season from the chosen pack, sizes, rule and start credits and the ledger holds one audited event; closing works the same; both ask for confirmation and do nothing without it.
  - [ ] Offline: without `season.manage` the buttons are absent and a forced call is refused; a member sees the season read-only; a second open season is refused with a clear message.
  - [ ] In game: the Guild Master opens and closes a season from the window and the officers' windows update; the `/run` lines of `docs/checklists/M4.md` are no longer needed.
- Tests: `Tests/test_season_window.lua` (windows driven by their buttons on the mock client).
- Docs: wiki **Seasons** page or section (EN + IT), update `docs/checklists/M4.md`, CHANGELOG, README status.
- Real client: layout and confirmation dialogs, the permission-based visibility.
- Suggested model/effort: `sonnet` / medium

### M6-2 — Loot log and audit
- Branch: `step/m6-2-log-audit`
- Depends on: M6-1, M5-5
- Analysis: §7 (log, audit); [`docs/specs/ui-style.md`](../specs/ui-style.md) §6
- Scope: the **History › Log** and **History › Audit** sub-tabs: `UI/Windows/Log.lua` (everything that dropped, assigned or not, from which boss, to whom, for which response, at what cost) and the audit view (council interventions with reasons, manual corrections, voids, configuration changes with date and author); filters and search.
- Done when:
  - [ ] Every intervention of the M5 tests appears in the audit with its reason.
- Tests: `Tests/test_log_audit.lua`.
- Docs: History (EN + IT), CHANGELOG.
- Real client: the windows in game.
- Suggested model/effort: `sonnet` / medium

### M6-3 — Discord, CSV and JSON export
- Branch: `step/m6-3-export`
- Depends on: M6-1
- Analysis: §7 (export), §8.5 (numbers, dates, guild language)
- Scope: `Domain/Export.lua` (credits table as Markdown ready for Discord, CSV, JSON; attendance never in public exports), a copy window with the text already selected; numbers and dates in the guild language; `export.public` permission; the copy window is the **History › Export** sub-tab, look per `ui-style.md` (preview `fdcp-site-export.webp`).
- Done when:
  - [ ] Exports are deterministic and match golden files in tests.
- Tests: `Tests/test_export.lua`.
- Docs: wiki **Export** (EN + IT), CHANGELOG.
- Real client: copying from the window.
- Suggested model/effort: `sonnet` / medium

### M6-4 — Community-site export
- Branch: `step/m6-4-site-export`
- Depends on: M6-3
- Analysis: §7.1, §13 question 10; [`docs/specs/site-export.md`](../specs/site-export.md) (the whole spec)
- Scope: `Domain/SiteExport.lua` (pure) building the **three site files** exactly as in `site-export.md` §3: `roster.json` (own faction's mains), `loot.json` (`seasons[]` newest first, nights as `raids[]`, valid awards with `cost` 0–2, voids and corrections folded in, late joiners' start credits as synthetic rows, bank items left out) and `progress.json` (first kills of M3-3b, own faction key only, never a later date); the copy window with "full file" and "fragment" forms and the warning of §6.1; the three objects saved in `FinlandDragonCreditPointsDB…siteExport` at every night close and on request; `tools/site_export.py` reading the SavedVariables and **merging** into `content/games/wow-forever/` of a site checkout (keeps the other faction, older seasons, covers, locked instances, unknown keys; the site's own validation rules; `--dry-run`); the `awards` CSV of the site's sheet path; the `start` / `kind` extension written only behind an option that is off and hidden (reversible default of issue #3).
- Done when:
  - [ ] The three exports match golden files and pass the rules of the site's `scripts/validate.mjs` (classes, roles, players in the season roster, `cost` 0–2) in tests.
  - [ ] `tools/site_export.py` merges into a fixture of the site's current files without losing data of the other faction or older seasons (Python tests).
  - [ ] The site builds and shows the three files exported from a real night. *(in game)*
- Tests: `Tests/test_site_export.lua`.
- Docs: Export and Site Export (EN + IT), CHANGELOG; comment on issue #3 with what was built.
- Real client: nothing beyond M6-3.
- Suggested model/effort: `sonnet` / medium

### M6-5 — Officer ledger sync
- Branch: `step/m6-5-officer-sync`
- Depends on: M1-6, M2-5, M3-1
- Analysis: §8.4 (`OFFICER`, trust), §0 point 2
- Scope: `Net/Sync.lua` on `OFFICER`: per-author high-water marks exchanged ("how far I have"), requests for missing ranges, events accepted only if their author had the required rank when they were written; no overwrites, only more events; budgets for traffic.
- Done when:
  - [ ] In the simulator, officers who ran different nights converge; a forged event from a member is refused everywhere.
- Tests: `Tests/test_sync.lua` (network simulator).
- Docs: §8.4 if anything changes; CHANGELOG.
- Real client: two officers in game.
- Suggested model/effort: `opus` / high

### M6-6 — Read-only credits for every member
- Branch: `step/m6-6-guild-snapshot`
- Depends on: M6-5
- Analysis: §8.4 (`GUILD`, `WHISPER`)
- Scope: a credits snapshot on `GUILD` from an officer (season, totals, ledger head), verified against the sender's rank; recovery by `WHISPER` for a member who joined late or reloaded; members' credits table and popup read it.
- Done when:
  - [ ] Members converge on the officers' totals in the simulator; a snapshot from a non-officer is ignored.
- Tests: `Tests/test_snapshot.lua`.
- Docs: Credits (EN + IT), CHANGELOG.
- Real client: guild messages in game.
- Suggested model/effort: `opus` / high

### M6-7 — Import, backup and end-of-season compaction
- Branch: `step/m6-7-backup-compaction`
- Depends on: M6-5
- Analysis: §7 (import), §8.3 (snapshots), §11 (SavedVariables size)
- Scope: configuration import / export as a string (shareable with other guilds), full ledger backup and restore, end-of-season compaction into a snapshot with an exportable archive, size estimates in `/fdcp debug`.
- Done when:
  - [ ] Backup → restore gives the same ledger; compaction keeps every total and the audit of the season.
- Tests: `Tests/test_backup.lua`.
- Docs: wiki **Backup and Seasons** (EN + IT), CHANGELOG.
- Real client: SavedVariables size after a long season.
- Suggested model/effort: `opus` / medium

### M6-8 — M6 in-game checklist
- Branch: `step/m6-8-checklist`
- Depends on: M6-4, M6-6, M6-7
- Analysis: §12 (M6 exit)
- Scope: `docs/checklists/M6.md` (history views, Discord export, the three site files merged by `tools/site_export.py` and shown by the site, two officers syncing, members reading credits, backup).
- Done when:
  - [ ] The checklist exists and is linked from the README.
  - [ ] The owner confirms M6 in game. *(in game)*
- Docs: checklist, README (EN + IT), CHANGELOG.
- Real client: the whole checklist.
- Suggested model/effort: `sonnet` / low
