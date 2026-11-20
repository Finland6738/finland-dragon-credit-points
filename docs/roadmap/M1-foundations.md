# M1 — Foundations

**Goal:** a loadable addon with offline tests, Compat, configuration, locales, the guarded transport and the Material theme; `/fdcp` opens an empty themed window ([`docs/ANALISI.md` §8, §9, §12](../ANALISI.md#8-architettura)). Starts from copies of Azeroth Accord's foundations (`../azeroth-accord`), renamed and adapted; the two addons stay independent in game.

**Exit criterion:** the offline tests run in CI in both languages; in game the addon loads without errors and `/fdcp` opens the empty window (owner's check, M1-8).

Until the spike results arrive, M1 follows plan A and keeps every unverified API behind Compat with a fallback.

### M1-1 — Addon skeleton and packaging
- Branch: `step/m1-1-skeleton`
- Depends on: M0-0
- Analysis: §1, §8.2, §8.3
- Scope: `FinlandDragonCreditPoints/` with `FinlandDragonCreditPoints.toc` and `FinlandDragonCreditPoints_Camelot.toc` (Interface 16001, SavedVariables `FinlandDragonCreditPointsDB`, SavedVariablesPerCharacter `FinlandDragonCreditPointsCharDB`, AddOn Compartment), `embeds.xml` (Ace3: AceAddon, AceDB, AceDBOptions, AceEvent, AceTimer, AceComm, AceLocale, AceConfig; LibDataBroker, LibDBIcon, ChatThrottleLib), `Core/Init.lua` with the Forever check and `/fdcp help`; `.pkgmeta`, `.luarc.json` (types from `../WoW-Addons`), `tools/fetch_libs.py`, `tools/install_addon.py` (`<WoW folder>` from a git-ignored local file), `tools/check_addon.py` (TOC fields, file list), `tools/check_package.py`; all adapted from Azeroth Accord.
- Done when:
  - [x] `check_docs.py` runs the TOC and package checks; the addon folder installs with the script.
  - [ ] The addon loads without errors and `/fdcp help` answers. *(in game)*
- Tests: TOC and embeds checks.
- Docs: README status, wiki Installation (EN + IT) with the install script for testers, CHANGELOG.
- Real client: loading.
- Suggested model/effort: `sonnet` / medium

### M1-2 — Offline test harness
- Branch: `step/m1-2-test-harness`
- Depends on: M1-1
- Analysis: §8.1 (Domain testable offline), §8.2 (`Tests/`)
- Scope: `Tests/run_tests.py` (lupa, Lua 5.1), `Tests/lib/` (assertions, harness with `/reload` simulation), `Tests/mock/` (the mock client copied from Azeroth Accord and renamed: frames and events, timers, addon messages with lockdown, guild roster, `C_EncodingUtil`), `Tests/test_addon.lua` (boot, Forever check, slash command, `/reload` round trip); the CI job "Lua tests" now runs them.
- Done when:
  - [ ] Boot, slash command and `/reload` round trip are tested and green in CI.
- Tests: the harness itself.
- Docs: CLAUDE.md test command, CHANGELOG.
- Real client: nothing.
- Suggested model/effort: `sonnet` / medium

### M1-3 — Compat and capabilities
- Branch: `step/m1-3-compat`
- Depends on: M1-2
- Analysis: §1 (whole table), §8.1 (Adapters via Compat)
- Scope: `Core/Compat.lua` adapted from Accord (guarded calls, secret values, restrictions, chat lockdown) plus the FDCP areas: loot window and master loot, loot method and threshold, `RandomRoll` and the system-message patterns from globals, encounters, `C_Item.*` and item stats, specializations, guild ranks, group roster, calendar; `Compat:Probe()` with `available` / `missing` / `unknown` per feature; `/fdcp debug` in chat (no names). Mock client areas for each.
- Done when:
  - [ ] Every unverified API degrades without errors in the mock (missing, erroring, secret).
- Tests: `Tests/test_compat.lua`.
- Docs: CHANGELOG; wiki Commands page (EN + IT) with `/fdcp help` and `/fdcp debug`.
- Real client: `/fdcp debug` capability table.
- Suggested model/effort: `sonnet` / high

### M1-4 — Config, log, bus and guild key
- Branch: `step/m1-4-config`
- Depends on: M1-3
- Analysis: §8.1 (Core), §8.3, §10
- Scope: `Core/Config.lua` (AceDB, profiles, defaults, validation, schema version and step-by-step migrations, read-only on a newer schema), `Core/Log.lua` (ring buffer, levels, no names in debug output), `Core/Bus.lua`, a guild key `<realm>/<guild>` so data of different guilds never mixes.
- Done when:
  - [ ] Data is kept per guild; a newer schema opens read-only; migrations are tested.
- Tests: `Tests/test_config.lua`.
- Docs: CHANGELOG.
- Real client: SavedVariables survive `/reload` and relog.
- Suggested model/effort: `sonnet` / medium

### M1-5 — Locales and the no-text-in-code check
- Branch: `step/m1-5-locales`
- Depends on: M1-4
- Analysis: §8.5
- Scope: `Locale/enUS.lua` (base, every key) and `Locale/itIT.lua` with AceLocale; English fallback for missing keys; personal language override (needs `/reload`); the **guild language** setting for texts sent to everyone; number and date formatting per language; `tools/check_locale.py` (missing and unused keys, hard-coded visible text in `UI/` and `Domain/`) run by `check_docs.py`; the test suite runs in both languages.
- Done when:
  - [ ] Adding a language is one file plus one TOC line; the checks fail on a hard-coded string and on a missing key.
- Tests: `Tests/test_locale.lua`, the check's own cases.
- Docs: a short "Adding a language" section in README (EN + IT), CHANGELOG.
- Real client: Italian and English clients show their language.
- Suggested model/effort: `sonnet` / medium

### M1-6 — Codec and guarded transport
- Branch: `step/m1-6-transport`
- Depends on: M1-4
- Analysis: §8.4, §11 risk 3
- Scope: `Net/Codec.lua` (`<version>|<TYPE>|<payload>`, CBOR with optional Deflate in Base64 through `C_EncodingUtil`, unknown types and newer versions ignored), `Net/Transport.lua` adapted from Accord for `RAID`, `GUILD`, `OFFICER`, `WHISPER` with the prefix `FDCP1` (priorities, throttling, the queue that waits out lockdown and restrictions and `IsEncounterInProgress`, retries, the queue saved at logout and restored at login, own echoes ignored).
- Done when:
  - [ ] Messages survive lockdown, encounters and `/reload` in the mock; unknown versions are ignored.
- Tests: `Tests/test_codec.lua`, `Tests/test_transport.lua`.
- Docs: a protocol note in `docs/ANALISI.md` §8.4 if anything changes; CHANGELOG.
- Real client: delivery in raid (spike S4).
- Suggested model/effort: `opus` / high

### M1-7 — Theme and the empty main window
- Branch: `step/m1-7-theme-window`
- Depends on: M1-5
- Analysis: §9.1, §9.2, §9.3
- Scope: `UI/Theme.lua` (the palette tokens of §9.1, typography, spacing, state overlays), first widgets (`Button`, `Card`, `NavRail`, `TopAppBar`, `Dialog` base) from game textures and simple shapes, the main window with the rail (Session · Credits · Roster · Nights · Log · Council · Settings as empty pages), movable and remembered per character, Esc to close; `/fdcp` opens it; minimap button (LibDBIcon) and AddOn Compartment entry; the logo converted to power-of-two TGA (256 and 64) in `FinlandDragonCreditPoints/Media/`.
- Done when:
  - [ ] `/fdcp` opens a themed empty window in the mock; every visible text comes from the locales.
  - [ ] The window looks right in game. *(in game)*
- Tests: `Tests/test_ui_shell.lua`.
- Docs: wiki Interface Tour (EN + IT) and Commands, README status, CHANGELOG.
- Real client: look, scaling, Esc, minimap button.
- Suggested model/effort: `sonnet` / medium

### M1-8 — M1 in-game checklist
- Branch: `step/m1-8-checklist`
- Depends on: M1-7
- Analysis: §12 (M1 exit)
- Scope: `docs/checklists/M1.md`, the owner's in-game check of M1 (loading, `/fdcp`, `/fdcp debug`, the window, saved data, locales, two clients hearing each other); README status; the `v0.1.0` changelog section waits for the owner's confirmation.
- Done when:
  - [ ] The checklist exists and is linked from the README and the roadmap.
  - [ ] The owner confirms M1 in game. *(in game)*
- Docs: checklist, README (EN + IT), CHANGELOG.
- Real client: the whole checklist.
- Suggested model/effort: `sonnet` / low
