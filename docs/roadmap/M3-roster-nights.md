# M3 — Roster and nights

**Goal:** the master looter opens and closes an official raid night, the addon knows the pool, who plays and who is benched, records attendance per boss, and tells officers who in the raid does not have the addon ([`docs/ANALISI.md` §3.9, §4.1, §6](../ANALISI.md#6-roster-rotazione-panchina-e-cambi)).

**Exit criterion:** a night opened and closed from the addon with lineup, bench and per-boss attendance in the ledger; the "Addon in the raid" panel and the `/raid` notice work; the credits table is visible.

### M3-1 — Guild ranks and the permission service
- Branch: `step/m3-1-guild-ranks`
- Depends on: M2-5, M1-3
- Analysis: §3.9
- Scope: `Adapters/GuildRanks.lua` (self is GM, rank index of a member, rank names and count, officer per the game), the asynchronous roster load (events needing a rank wait in a queue until the roster is known), rank reorder / deletion detected and reported to the GM, GM change; `App/PermissionService.lua` wiring `Domain/Permissions.lua` to live ranks.
- Done when:
  - [ ] Events wait while the roster loads and are accepted or refused once it arrives; a GM change transfers the config power.
- Tests: `Tests/test_guild_ranks.lua` (mock roster).
- Docs: CHANGELOG.
- Real client: rank reading for GM, officer, member.
- Suggested model/effort: `opus` / high

### M3-2 — Season pool, declarations, mains and alts
- Branch: `step/m3-2-pool`
- Depends on: M2-4, M3-1
- Analysis: §6 (pool), §3.1 (MS1 = MS, MS2 = OS)
- Scope: `Domain/Roster.lua`: the season pool with MS1 (required), MS2, OS, role, class, faction, availability notes; declarations locked for the season except an officer correction (`roster.manage`); one main per faction; alt link declared by the player and approved by an officer; states active / trial / inactive; optional import from the guild note; ledger events `MEMBER_JOINED`, `MEMBER_LINKED_ALT`, `ROSTER_CHANGED`.
- Done when:
  - [ ] A declaration cannot change mid-season without an officer event; an alt never gets credits.
- Tests: `Tests/test_roster.lua`.
- Docs: CHANGELOG.
- Real client: nothing beyond M3-1.
- Suggested model/effort: `opus` / high

### M3-3 — Nights, lineup and attendance per boss
- Branch: `step/m3-3-nights`
- Depends on: M3-2, M2-6
- Analysis: §2 (Night), §6 (during the night), §3.1 (official raids only)
- Scope: `App/NightController.lua` (open/close an official night: date, instance, size, difficulty; `NIGHT_OPENED` / `NIGHT_CLOSED`), `Adapters/Group.lua` (`GetRaidRosterInfo`, `GROUP_ROSTER_UPDATE`), lineup in raid / bench / absent, every change logged with time and the boss of reference, `ENCOUNTER_END` → `ENCOUNTER_KILLED`, attendance per boss.
- Done when:
  - [ ] A simulated night with joins, leaves and three bosses gives the expected attendance per boss.
- Tests: `Tests/test_nights.lua`.
- Docs: CHANGELOG.
- Real client: group events in a real raid.
- Suggested model/effort: `opus` / medium

### M3-4 — Bench rotation and the calendar
- Branch: `step/m3-4-rotation`
- Depends on: M3-3
- Analysis: §6 (planning, effect on credits)
- Scope: `Domain/Rotation.lua` (proposed bench by fewest benches this season, role minimums for tanks and healers, declared preferences; the ML decides), `bench.creditEffect` (none in the preset, bonus or malus for other guilds), `Adapters/Calendar.lua` (link a night to the official raid event when it exists).
- Done when:
  - [ ] The proposal is fair over a simulated season and respects role minimums.
- Tests: `Tests/test_rotation.lua`.
- Docs: CHANGELOG.
- Real client: calendar reading.
- Suggested model/effort: `opus` / medium

### M3-5 — The addon presence protocol
- Branch: `step/m3-5-addon-check`
- Depends on: M1-6, M3-3
- Analysis: §4.1 (how it knows, states), §8.4
- Scope: `Net/Protocol.lua` first messages `HELLO?` / `HELLO{addonVersion, protocolVersion}` on `RAID` at night open, on every raid join and on request; `App/AddonCheck.lua` with the states active / outdated / incompatible / not active / waiting, the summary "37/40 with the addon", the rule "candidates are only members with a compatible addon" exposed for M4.
- Done when:
  - [ ] Simulated raids with old, incompatible and missing addons give the right states.
- Tests: `Tests/test_addon_check.lua` (network simulator).
- Docs: CHANGELOG.
- Real client: `RAID` delivery (spike S4).
- Suggested model/effort: `opus` / high

### M3-6 — "Addon in the raid" panel and the `/raid` notice
- Branch: `step/m3-6-addon-panel`
- Depends on: M3-5, M1-7
- Analysis: §4.1 (panel, notice in `/raid`)
- Scope: the panel (one row per raid member, state chip, summary also in the ML bar), the **Notify in /raid** button with GM-editable text and placeholders `{names}`, `{link}`, `{addon}`, split over several lines at 255 characters, an "outdated" variant, the whisper option, at most one notice every N minutes and never during an encounter, every notice logged; visible only with `raid.addonCheck`.
- Done when:
  - [ ] The notice text is in the guild language, splits correctly and is refused during an encounter in the mock.
- Tests: `Tests/test_addon_notice.lua`.
- Docs: wiki **Addon Check** page (EN + IT), CHANGELOG.
- Real client: sending to `/raid` from a click.
- Suggested model/effort: `sonnet` / medium

### M3-7 — Roster and Nights windows
- Branch: `step/m3-7-roster-nights-ui`
- Depends on: M3-4, M1-7
- Analysis: §6, §9.3
- Scope: `UI/Widgets/DataTable.lua` (sortable, ScrollBox), `UI/Windows/Roster.lua` (pool, declarations, alts and approvals), `UI/Windows/Nights.lua` (open / close a night, lineup, proposed bench, attendance only for officers per `view.attendance`).
- Done when:
  - [ ] Officers can manage the pool and run a night from the windows in the mock; members see no attendance.
- Tests: `Tests/test_ui_roster.lua`.
- Docs: wiki **Roster and Nights** page (EN + IT), CHANGELOG.
- Real client: the windows in game.
- Suggested model/effort: `sonnet` / medium

### M3-8 — Credits table
- Branch: `step/m3-8-credits-table`
- Depends on: M3-7
- Analysis: §9.3 point 4, §7
- Scope: `UI/Windows/Credits.lua`: credits of every main in the season, sortable, filters by class and role, position in the queue, the player's own row highlighted; computed from the local ledger.
- Done when:
  - [ ] The table matches the ledger totals in tests; sorting and filters work.
- Tests: `Tests/test_ui_credits.lua`.
- Docs: wiki **Credits** page (EN + IT), README features, CHANGELOG.
- Real client: the window in game.
- Suggested model/effort: `sonnet` / medium

### M3-9 — M3 in-game checklist
- Branch: `step/m3-9-checklist`
- Depends on: M3-8
- Analysis: §12 (M3 exit)
- Scope: `docs/checklists/M3.md` (open and close a night, lineup and bench, attendance per boss, addon check with someone without the addon, the `/raid` notice, credits table).
- Done when:
  - [ ] The checklist exists and is linked from the README.
  - [ ] The owner confirms M3 in game. *(in game)*
- Docs: checklist, README (EN + IT), CHANGELOG.
- Real client: the whole checklist.
- Suggested model/effort: `sonnet` / low
