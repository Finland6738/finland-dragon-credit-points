# M7 — Polish and release

**Goal:** the complete look of the community site ([`docs/specs/ui-style.md`](../specs/ui-style.md)), the settings and profiles, diagnostics, packaging and the full manual in both languages; version 1.0 for the guild ([`docs/ANALISI.md` §9, §10, §12](../ANALISI.md#9-interfaccia-material-design-3-in-tinta-con-il-logo)).

**Exit criterion:** complete in code with green tests; `v1.0.0` is tagged only after the owner's release checklist passes in game.

### M7-1 — Site-style polish
- Branch: `step/m7-1-material-polish`
- Depends on: M1-7
- Analysis: §9.2; [`docs/specs/ui-style.md`](../specs/ui-style.md) (the whole spec, §5 verdicts)
- Scope: every window checked against `ui-style.md` and its previews: the "approximated" elements finished (glows in `ADD`, the one neon element per view, two-stop gradients, generated or Encounter Journal covers, the text glow of the title), shadows and the light highlight, hover 8% / pressed 12% layers and the 0.97 press, motion 120 / 200 / 320 ms with `OUT`, the "Animations: off" and "Neon effects" preferences, the three themes reviewed for contrast; remaining components (chips, snackbar, switch, slider, select without `UIDropDownMenu`, skeletons); the icon sheet complete; font and icon licences recorded in the repository.
- Done when:
  - [x] Every window uses the theme tokens and components; no hard-coded colours outside `UI/Theme.lua` (checked by `tools/check_addon.py`); every element marked "identical" or "approximated" in `ui-style.md` §5 is built.
  - [ ] The look and the speed in the game: glows, the light line, hover and press, the transitions and the two preferences, in the three themes. *(in game)*
- Tests: `Tests/test_theme.lua`.
- Docs: Interface Tour (EN + IT), CHANGELOG.
- Real client: look and performance in game.
- Suggested model/effort: `sonnet` / high

### M7-2 — Settings window and permissions table
- Branch: `step/m7-2-settings`
- Depends on: M5-8, M2-5
- Analysis: §3.9, §10
- Scope: `UI/Windows/Settings.lua`, the **Settings** tab with the sub-tabs Personal · Rules · Permissions · Site of [`docs/specs/ui-style.md`](../specs/ui-style.md) §6: theme (Nebula, Aurora, Drago), neon effects, animations, fonts (addon or game); rules read-only for everyone but the GM ("editable by the GM"), the GM's editor for costs, categories, responses, award mode, legendaries, late joiners, with explicit confirmation and an audit entry when the season is open; the permissions table by rank (GM only); personal preferences (popup position, sounds, personal weights, wishlist, language); also in the game's settings window.
- Done when:
  - [x] A non-GM cannot change rules from the UI and a forged change is refused by the domain; open-season changes ask for confirmation.
  - [ ] The window in the game, as the Guild Master and as an officer: the sub-tabs, the form on every page, the dropdowns, the confirmation dialog and the entry in the game's settings window. *(in game)*
- Tests: `Tests/test_ui_settings.lua`.
- Docs: wiki **Settings** (EN + IT), CHANGELOG.
- Real client: the window in game, GM and officer.
- Suggested model/effort: `sonnet` / high

### M7-2b — Automatic response labels
> **Superseded by [M7-5c](#m7-5c--three-button-popup-and-automatic-upgrade-badge)** (owner decision of 2026-11-22): the labels, the rule `responses.labelMode` and the label's origin are removed; the popup has three buttons and the addon computes the upgrade badge. The history below is kept as it was shipped.

- Branch: `step/m7-2b-auto-labels`
- Depends on: M7-2, M5-2, M5-3, M4-6
- Analysis: §5.1 ("Come è fatto (M7-2b)"), §8.4 (protocol 5), §10
- Scope: today the player picks the optional label of a main-spec response (BiS, big upgrade, small upgrade, situational) by hand in the popup (M4-6). A new rule `responses.labelMode` (Guild Master only, in the Settings window's Priority page) says who picks it: `auto` (the addon sets it and the player cannot change it), `suggest` (the default: the addon fills it in and the player may change or clear it) and `manual` (the player, as before). The addon's choice is the data it already has: the item is on the player's best-in-slot list (M5-3) → BiS; the main-spec verdict (M5-2) is a big upgrade → big upgrade, a small one → small upgrade; no upgrade, not comparable, not usable or no verdict → no label. The origin of the label (automatic, changed by the player, chosen by the player) travels in the response and the master looter's window shows it. Pure `Domain/Labels.lua`; the rule is validated by `Rules.Validate` and older rules are filled with `suggest`; the protocol goes to 5 with optional fields (`lm` of SOPEN / SSTATE, `lo` of SRESP), so an older client still follows the session; words through locale keys and the `LABEL_ORIGIN` group of `Domain/Reasons.lua`.
- Done when:
  - [x] The rule is validated, defaults to `suggest`, older rules are filled in, and a non-GM cannot change it (M7-2's gate).
  - [x] In `auto` the popup shows the addon's label and the chips are locked; in `suggest` it is prefilled and the player may change or clear it; in `manual` nothing changes; the answer carries who chose the label; the master looter's table says "auto" or "changed".
  - [x] A session from an older client (no `lm`, no `lo`) still works: the popup leaves the label to the player and the table shows no origin.
  - [ ] The popup and the master looter's window in the game, in the three modes, on a real item with a wishlist entry and a verdict. *(in game)*
- Tests: `Tests/test_labels.lua`, additions to `Tests/test_rules.lua`, `Tests/test_ui_settings.lua`, `Tests/test_ui_popup.lua`, `Tests/test_protocol_session.lua`, `Tests/test_session_fsm.lua`, `Tests/test_ui_ml_session.lua`.
- Docs: wiki **Rolling for Loot**, **Settings** and **Master Looter Guide** (EN + IT), analysis §5.1, CHANGELOG.
- Real client: the popup chips and the line under them, the master looter's column.
- Suggested model/effort: `sonnet` / medium

### M7-2c — Info and credits
- Branch: `step/m7-2c-info-credits`
- Depends on: M7-2
- Analysis: §3.9 (Settings), §10
- Scope: owner request of 2026-11-22. An **Info** sub-tab of Settings (the last one) and `/fdcp about` tell who made the addon and for whom: conceived and made by **Finland** (the public handle, never a real name) for the Italian guild **NEBULA**, its purpose, the licence (GPL-3.0), the third-party fonts and libraries, and how to support the project. The game cannot open a web page, so the GitHub repository, the issue tracker, the community site and the Ko-fi page (the one of `.github/FUNDING.yml`) are read-only copy boxes (click, Ctrl+C); the guild's logo (`Media/logo_256.tga`) heads the page. `/fdcp about` opens the page, `/fdcp about chat` prints it. Texts through locale keys (enUS, itIT); a Credits section in `README.md` + `README.it.md` and a wiki page **About** (EN + IT) linked from Home and the sidebar.
- Done when:
  - [x] The Info sub-tab shows the author, the guild, the purpose, the licence, the third-party list and four copy boxes that put an edit back and select their text on focus; no personal data beyond the handle.
  - [x] `/fdcp about` opens it and `/fdcp about chat` prints it; both languages read well.
  - [x] README (EN + IT), wiki **About** (EN + IT), CHANGELOG.
  - [ ] The page and the copy boxes in the game (does the box select and copy with Ctrl+C, does the logo show, does the text fit at the minimum window size). *(in game)*
- Tests: `Tests/test_ui_about.lua`.
- Docs: wiki **About** (EN + IT), Home and sidebar links, README (EN + IT), CHANGELOG.
- Real client: the copy boxes and the layout of the page.
- Suggested model/effort: `sonnet` / low

### M7-2d — Rolls only from the button, once per item
- Branch: `step/m7-2d-button-rolls`
- Depends on: M4-3, M4-6, M7-2
- Analysis: §4 ("Roll"), §4.1, §8.4 ("Come è fatto (M7-2d)", protocol 6)
- Scope: owner request of 2026-11-22. A player rolls **only by clicking the popup's Roll button**, and only **once per item**; a `/roll` typed by hand does not count, even from a player with the addon. The game cannot tell a typed `/roll` from `RandomRoll` called by a click, so the click first sends a small session message, the **roll intent** (`SRINT`: item, round, nonce; no roll value, so the trust rule of §8.4 holds) and then calls `RandomRoll`. The master looter's roll listener counts a server roll only when an intent of the same sender for that round goes with it, within a window (rule `session.buttonRollWindow`, 10 seconds, counted only outside a lockdown); otherwise the roll is discarded with the new code `NOT_FROM_BUTTON` and does not use the player's turn. One intent per player per round: a second intent or a second roll is a `DUPLICATE`; an intent without a roll does nothing. A rule `session.buttonRollsOnly` (Guild Master, default on) turns it off (the old behaviour). The player's own client warns when they type `/roll` during an open round; the game's `/roll` command is never overridden or blocked. Rerolls among the tied use the button too. Protocol 6 with optional fields: an older client ignores `SRINT` and `bo`, and its rolls are judged as before.
- Done when:
  - [x] A typed roll is discarded as `NOT_FROM_BUTTON` and a button roll is accepted, on the network simulator; the warning shows on the player's own client.
  - [x] A double click or a second roll is a duplicate; an intent without a roll does nothing; a lockdown that delays the intent stays within the window; a reroll works from the button.
  - [x] With `session.buttonRollsOnly` off the old behaviour comes back; the rule is validated and older rules are filled in; a client of protocol 5 still rolls.
  - [ ] In the game: the intent reaches the master looter before or shortly after the roll message, in and out of an instance, after a boss (the lockdown); the warning on a typed `/roll`. *(in game)*
- Tests: `Tests/test_button_rolls.lua` (network simulator: the rule, typed and button rolls, duplicates, an intent without a roll, the lockdown, a reroll, a forged or stale intent, the rule off, an older client); `Tests/test_protocol_session.lua` (protocol 6); the benches that roll by hand for other purposes turn the rule off.
- Docs: wiki **Rolling for Loot**, **Master Looter Guide** and **Loot Rules** (EN + IT), analysis §4, §4.1, §8.4, CHANGELOG.
- Real client: the order and delay between the addon message and the system roll message; `RandomRoll` from a click.
- Suggested model/effort: `opus` / high

### M7-3 — Profiles and presets
- Branch: `step/m7-3-profiles`
- Depends on: M7-2, M6-7
- Analysis: §10 (profiles, presets, import / export)
- Scope: AceDB profiles in the UI, the four presets ready to apply, a profile exported and imported as a string to paste on Discord, validation and a preview of the differences before applying.
- Done when:
  - [x] Each preset applies and round-trips through the string unchanged.
- Tests: `Tests/test_profiles.lua`.
- Docs: Settings (EN + IT), CHANGELOG.
- Real client: nothing beyond M7-2.
- Suggested model/effort: `sonnet` / medium

### M7-4 — Diagnostics and bug reports
- Branch: `step/m7-4-diagnostics`
- Depends on: M1-3
- Analysis: §11
- Scope: `/fdcp debug` in a selectable window (capabilities, versions, queue state, ledger size, last errors, no names), an error catcher for the addon's own errors, a "copy bug report" text; issue templates on GitHub (bug, feature) in English with an Italian note.
- Done when:
  - [x] The report contains no names in tests.
  - [x] An error raised by the addon is caught, cleaned and listed; the window and `/fdcp debug chat` show the same report; issue templates (bug, feature) exist in English with an Italian note.
  - [ ] The window in the game: it opens, the text is selected, Ctrl+C copies it, the report reads well. *(in game)*
- Tests: `Tests/test_diagnostics.lua`.
- Docs: wiki **Reporting Bugs** (EN + IT), CHANGELOG.
- Real client: the window in game.
- Suggested model/effort: `sonnet` / medium

### M7-5 — Performance and a long season
- Branch: `step/m7-5-performance`
- Depends on: M6-7
- Analysis: §11 (SavedVariables size, item cache)
- Scope: a simulated long season (20 nights, 40 raiders, hundreds of awards) for ledger compute time, snapshot effectiveness, SavedVariables size and network budget; fixes where the budgets are exceeded.
- Done when:
  - [x] Documented budgets hold in CI.
- Tests: `Tests/test_perf.lua`.
- Docs: CHANGELOG.
- Real client: load time and memory in game.
- Suggested model/effort: `sonnet` / medium

### M7-5b — Dynamic roster: late joiners at the minimum, absence penalty
- Branch: `step/m7-5b-absence-penalty`
- Depends on: M2-4, M3-3, M3-4, M3-7, M5-5
- Analysis: §3.1, §3.5, §6 ("Assenze")
- Scope: owner rules of 2026-11-22, which supersede the late joiners at the floor of the roster average. The roster is dynamic: a player who joins mid-season gets **the credits of the player with the fewest** (the "Patto" preset's `members.lateJoin.method = min`; the other presets keep theirs). **Absence penalty: +1 credit** (fewest credits wins, so a penalty adds) for a season roster member, on an official night, who did **not sign up** on the calendar, **signed up but did not attend**, or **benched themselves**; nothing for who played or was **benched by the officers**. `LINEUP_CHANGED` gains `self` (who benched themselves); a player benches themselves with **Bench myself** (the request `NBENCH` on GUILD reaches the night's runner). `Domain/Absence.lua` proposes the penalties at the close; the officer confirms them with one click unless the GM rule `penalties.autoApply` (default off; `penalties.absence`, default 1). Each penalty is a `CREDITS_ADJUSTED{reason = ABSENCE, night, cause}` through the permission gate (`night.run` because it names the night), audited and voidable.
- Done when:
  - [x] Not signed up → +1; signed up but absent → +1; self-bench → +1; officer bench → 0; present → 0 (offline tests).
  - [x] A late joiner gets the minimum; a confirmation is required unless `autoApply` is on; a void restores the previous credits.
  - [x] The Night window shows the proposed penalties with **Confirm the penalties** for the officer and **Bench myself** for the player; words through locale keys (enUS + itIT) and `Domain/Reasons.lua`.
  - [ ] In the game: the calendar's sign-ups at the close of a real night, the `NBENCH` request over GUILD, the Night window's new line and buttons. *(in game)*
- Tests: `Tests/test_absence.lua`; `Tests/test_rules.lua`, `Tests/test_season_window.lua` (the preset's new rule).
- Docs: analysis §3.1, §3.5, §6; wiki **Loot Rules**, **Roster and Nights**, **Master Looter Guide**, **Settings**, **Seasons**, **Credits** (EN + IT); README; CHANGELOG.
- Real client: the calendar sign-ups read at the close; GUILD addon messages from a member to the officer running the night.
- Suggested model/effort: `opus` / high

### M7-5c — Three-button popup and automatic upgrade badge
- Branch: `step/m7-5c-upgrade-badge`
- Depends on: M7-2d, M5-2, M5-4, M6-1b, M4-6
- Analysis: §5.1 ("Come è fatto (M7-5c)"), §5.2, §8.4 (protocol 7), §13 (question 8 resolved)
- Scope: owner decisions of 2026-11-22. **Popup:** the player only chooses with three buttons, **Pass**, **Roll Main-spec** and **Roll Off-spec**; a roll button sends the response and rolls in one click (the roll intent of M7-2d first, then `RandomRoll`), once per round; in a round that does not collect responses (a lower tier's turn, a reroll, a free roll) it only rolls. **Removed** (code, rules, locale keys, tests, docs, protocol fields): the player-chosen labels and M7-2b's `responses.labelMode`; the response note; the personal stat weights and the Pawn-like import (M5-3, `Domain/WeightImport.lua`, `/fdcp weights`); the BiS wishlist (`Domain/Wishlist.lua`, `/fdcp wish`); the stat-weight scoring of M5-1 / M5-2 (`Data/StatWeights.lua`, the weighted score and its thresholds). Kept: the proficiency and usability checks, the slot pairing (rings and trinkets against the worse, a two-hander against main hand + off hand). **Automatic upgrade badge**, computed by the player's addon from the item against the piece worn in that slot **during the fight** (a gear snapshot taken at `ENCOUNTER_START`, at `ENCOUNTER_END` when the start was missed; M7-5d reads the same snapshot): purple over purple of the same season → **minor**; over blue → **medium**; over green or lower, or an empty slot → **major**; a purple of an **older season** (its item level under the current season's band) counts one step below, like a blue; always with the **item-level difference** ("Medium upgrade · ilvl +13"); worse → "No upgrade", unusable → "Not usable". Each season gets an **item-level band** the Guild Master sets in the Season window (`SEASON_BAND_SET`), frozen on the session and sent to the raid (`ib`). The badge shows in the popup and in the master looter's / council's window; it never changes the winner. Protocol 7: SRESP without `lb` / `lo` / `n`, SOPEN / SSTATE without `lm` and with `ib`; an older client's fields are read and ignored. Rules written before keep validating (the retired keys are dropped on read). Issue #2 closed by the decision.
- Done when:
  - [x] Every tier case (same-season purple, blue, green, empty slot, an older season's purple, worse, unusable), rings and trinkets, two-hand vs main hand + off hand, the band and the item-level difference (offline tests).
  - [x] The snapshot of the fight is used instead of the gear worn when the item is rolled; the three buttons answer and roll in one click; an old client's label, note and BIG / SMALL verdict are ignored and its response still counts.
  - [x] The Season window sets the band with a confirmation; the master looter's Upgrade column, its sort and the council flags read the tiers; the removed features leave no code, rule, locale key or command behind (`tools/check_locale.py` clean).
  - [ ] In the game: the three buttons in a raid (one click answers and rolls), `GetItemQualityByID` and the item level of worn pieces, the snapshot at `ENCOUNTER_START` (also after a `/reload` during the fight), the Season window's band fields. *(in game)*
- Tests: `Tests/test_upgrade_score.lua` (rewritten), `Tests/test_inventory.lua` (adapter, snapshot, advisor, wire), `Tests/test_ui_popup.lua`, `Tests/test_flags.lua`, `Tests/test_protocol_session.lua`, `Tests/test_session_fsm.lua`, `Tests/test_ui_ml_session.lua`, `Tests/test_season.lua`, `Tests/test_season_window.lua`, `Tests/test_ui_settings.lua`, `Tests/test_sim_boss.lua`; `Tests/test_labels.lua` and `Tests/test_weights_import.lua` removed.
- Docs: analysis §5, §8.4, §13; issue #2 commented and closed; wiki **Rolling for Loot** (rewritten), **Upgrade Hints** (rewritten: the badge), **Master Looter Guide**, **Settings**, **Seasons**, **Loot Rules** (EN + IT); README (EN + IT); CHANGELOG.
- Real client: the quality and item level of worn links, `ENCOUNTER_START` and the snapshot, the popup's buttons.
- Suggested model/effort: `opus` / high

### M7-5d — Roll-cheating detection and the +2 penalty
- Branch: `step/m7-5d-cheat-penalty`
- Depends on: M7-5c, M7-5b, M7-2d, M5-4, M5-5
- Analysis: §3.6 ("Imbrogli sul tiro"), §5.2 ("Come è fatto (M7-5d)", with the trust limit)
- Scope: owner rule of 2026-11-22: **roll cheating is punished with +2 credits** (fewest credits wins, so a penalty adds). The addon **detects and flags** four cases with evidence, from the gear snapshot of the fight (M7-5c) against the gear worn when the response is sent: **gear swapped** for a lower item level (`GEAR_SWAP`), **a piece taken off** (`UNEQUIPPED`), **a pass on a medium or major main-spec upgrade** (`UPGRADE_PASSED`, extending M5-4's `UPGRADE_IGNORED`, which keeps flagging a pass on a major one and counts as this case), **an off-spec piece that hides the upgrade** (`OFFSPEC_HIDE`: the compared piece does not fit the declared MS1 and without it the item would be a medium or major upgrade, and the player did not ask for it at full cost). The evidence travels in the optional `cg` of SRESP (an older client ignores it); `Domain/Cheat.lua` detects, `Domain/Flags.lua` puts the `CHEAT` flag (with its cause) on the proposal; flags never change the winner (an `auto` award waits for the master looter). The master looter or a council member applies the penalty with **Penalize +2** and a second click to confirm (GM rules `penalties.cheat`, default 2, 0 in the other presets; `penalties.autoApply` from M7-5b, default off): a `CREDITS_ADJUSTED{reason = CHEAT, cause, item, sid}` through the permission gate, audited, voidable, never written twice for the same case, item and session. The master looter's client inspects a flagged player in range (`Adapters/InspectCheck.lua`, guarded and throttled through `Core/Compat.lua`) and says whether the gear worn now matches what their addon reported. Trust limit: the evidence comes from the player's own addon; only the gear worn now can be cross-checked.
- Done when:
  - [x] Each of the four cases is flagged with its sub-code; an honest player is not flagged; a pass on a major upgrade stays `UPGRADE_IGNORED` and counts as `UPGRADE_PASSED` (offline tests).
  - [x] The penalty is written only on the confirmation (second click), by itself only with `autoApply`; a duplicate is refused; a void restores the credits; a typed `/roll` is still discarded as `NOT_FROM_BUTTON` (M7-2d).
  - [x] The ML session window and the Council page show the evidence and **Penalize +2**; words through locale keys (enUS + itIT) and `Domain/Reasons.lua` (groups `FLAG`, `CORRECTION`, `CHEAT`).
  - [ ] In the game: the evidence of a real swap after a kill, `CanInspect` / `NotifyInspect` / `INSPECT_READY` in a raid, the button in both windows. *(in game)*
- Tests: `Tests/test_cheat.lua`; `Tests/test_absence.lua` (the `penalties` section).
- Docs: analysis §3.6, §5.2; wiki **Loot Rules**, **Master Looter Guide** (EN + IT); README; CHANGELOG.
- Real client: the inspection API in a raid, the snapshot against the gear at the response.
- Suggested model/effort: `opus` / high

### M7-6 — Packaging and the release workflow
- Branch: `step/m7-6-packaging`
- Depends on: M1-1
- Analysis: §12 (M7)
- Scope: `.github/workflows/release.yml` (on a `v*` tag: build the zip from `.pkgmeta`, attach it to a GitHub release with notes from `CHANGELOG.md`), `tools/release_notes.py`, `docs/RELEASING.md`; actions pinned by SHA.
- Done when:
  - [ ] A dry run of the release workflow builds the expected zip.
- Tests: the package check.
- Docs: `docs/RELEASING.md`, Installation (EN + IT), CHANGELOG.
- Real client: installing the zip.
- Suggested model/effort: `sonnet` / medium

### M7-7 — The complete manual
- Branch: `step/m7-7-manual`
- Depends on: M7-2, M7-3
- Analysis: §8.5 (documentation)
- Scope: every wiki page reviewed in both languages (Home, Installation, Interface Tour, Commands, Rolling for Loot, Credits, Master Looter Guide, Council, Loot Rules, Export, Settings, FAQ, Privacy and Data, Reporting Bugs), with design previews drawn from the addon's own layout and invented names until real screenshots exist.
- Done when:
  - [ ] Every page has its twin, is in the sidebar and matches the addon's behaviour.
- Tests: `check_docs.py`.
- Docs: wiki (EN + IT), both READMEs.
- Real client: nothing.
- Suggested model/effort: `sonnet` / medium

### M7-8 — Release checklist and v1.0.0
- Branch: `step/m7-8-release-checklist`
- Depends on: M7-1 … M7-7
- Analysis: §12 (M7 exit)
- Scope: `docs/checklists/release.md` (every earlier checklist plus a full raid night), README status; the `v1.0.0` section and tag only after the owner's confirmation.
- Done when:
  - [ ] The checklist exists and is linked from both READMEs.
  - [ ] The owner confirms the release in game; `v1.0.0` is tagged. *(in game)*
- Docs: checklist, README (EN + IT), CHANGELOG.
- Real client: the whole checklist.
- Suggested model/effort: `sonnet` / low
