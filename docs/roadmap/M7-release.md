# M7 — Polish and release

**Goal:** the complete look of the community site ([`docs/specs/ui-style.md`](../specs/ui-style.md)), the settings and profiles, diagnostics, packaging and the full manual in both languages; version 1.0 for the guild ([`docs/ANALISI.md` §9, §10, §12](../ANALISI.md#9-interfaccia-material-design-3-in-tinta-con-il-logo)).

**Exit criterion:** complete in code with green tests; `v1.0.0` is tagged only after the owner's release checklist passes in game.

### M7-1 — Site-style polish
- Branch: `step/m7-1-material-polish`
- Depends on: M1-7
- Analysis: §9.2; [`docs/specs/ui-style.md`](../specs/ui-style.md) (the whole spec, §5 verdicts)
- Scope: every window checked against `ui-style.md` and its previews: the "approximated" elements finished (glows in `ADD`, the one neon element per view, two-stop gradients, generated or Encounter Journal covers, the text glow of the title), shadows and the light highlight, hover 8% / pressed 12% layers and the 0.97 press, motion 120 / 200 / 320 ms with `OUT`, the "Animations: off" and "Neon effects" preferences, the three themes reviewed for contrast; remaining components (chips, snackbar, switch, slider, select without `UIDropDownMenu`, skeletons); the icon sheet complete; font and icon licences recorded in the repository.
- Done when:
  - [ ] Every window uses the theme tokens and components; no hard-coded colours outside `UI/Theme.lua`; every element marked "identical" or "approximated" in `ui-style.md` §5 is built.
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
  - [ ] A non-GM cannot change rules from the UI and a forged change is refused by the domain; open-season changes ask for confirmation.
- Tests: `Tests/test_ui_settings.lua`.
- Docs: wiki **Settings** (EN + IT), CHANGELOG.
- Real client: the window in game, GM and officer.
- Suggested model/effort: `sonnet` / high

### M7-3 — Profiles and presets
- Branch: `step/m7-3-profiles`
- Depends on: M7-2, M6-7
- Analysis: §10 (profiles, presets, import / export)
- Scope: AceDB profiles in the UI, the four presets ready to apply, a profile exported and imported as a string to paste on Discord, validation and a preview of the differences before applying.
- Done when:
  - [ ] Each preset applies and round-trips through the string unchanged.
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
  - [ ] The report contains no names in tests.
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
  - [ ] Documented budgets hold in CI.
- Tests: `Tests/test_perf.lua`.
- Docs: CHANGELOG.
- Real client: load time and memory in game.
- Suggested model/effort: `sonnet` / medium

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
