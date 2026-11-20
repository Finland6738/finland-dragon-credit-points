# M1 — Foundations

**Goal:** a loadable addon with offline tests, Compat, configuration, locales, the guarded transport, the study of the community site and its theme; `/fdcp` opens an empty themed window ([`docs/ANALISI.md` §8, §9, §12](../ANALISI.md#8-architettura)). Starts from copies of Azeroth Accord's foundations (`../azeroth-accord`), renamed and adapted; the two addons stay independent in game.

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
  - [x] Boot, slash command and `/reload` round trip are tested and green in CI.
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
  - [x] Every unverified API degrades without errors in the mock (missing, erroring, secret).
  - [ ] `/fdcp debug` shows the capability table on the real client. *(in game)*
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
  - [x] Data is kept per guild; a newer schema opens read-only; migrations are tested.
  - [ ] SavedVariables survive `/reload` and relog. *(in game)*
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
  - [x] Adding a language is one file plus one TOC line; the checks fail on a hard-coded string and on a missing key.
  - [ ] Italian and English clients show their language. *(in game)*
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
  - [x] Messages survive lockdown, encounters and `/reload` in the mock; unknown versions are ignored.
  - [ ] A message sent in a real raid reaches the other members, and the queue waits out an encounter. *(in game)*
- Tests: `Tests/test_codec.lua`, `Tests/test_transport.lua`.
- Docs: a protocol note in `docs/ANALISI.md` §8.4 if anything changes; CHANGELOG.
- Real client: delivery in raid (spike S4).
- Suggested model/effort: `opus` / high

### M1-6b — Site study: UI style, site exports and Progress tab
- Branch: `step/m1-6b-site-study`
- Depends on: M1-6
- Analysis: §7.1, §9, §9.3
- Scope: an expert panel (web UI designer, WoW 12.0 addon UI engineer, data/integration engineer) studies the guild community site's WoW Forever page (`../nebula-community/nebula-community`: `src/styles/`, `src/ds/`, `src/kit/Wow.jsx`, `content/games/wow-forever/`); `docs/specs/ui-style.md` (tokens, components and how each is built in game, feasibility verdict per element, font decision and licences, window and tab layout: Roster · Credits · Progress · Loot · History · Settings) with design previews generated by `tools/make_mockups.py` into `docs/specs/mockups/`; `docs/specs/site-export.md` (the exact `roster.json`, `loot.json` and `progress.json` FDCP writes, field mapping, the two factions, how an officer exports, what FDCP must record, first kills included); §7.1, §9 and §9.3 of the analysis; the window, export and first-kill steps of the roadmap realigned to the two specs.
- Done when:
  - [x] Both specs exist, the analysis points to them and every later UI and export step names them.
  - [x] The mockups are generated by a script under `tools/` and shown in the spec.
- Tests: `check_docs.py` (links, images, the roadmap ids with a letter suffix).
- Docs: the two specs, ANALISI §7.1 / §9 / §9.3, roadmap, wiki Interface Tour and Site Export (EN + IT), CHANGELOG.
- Real client: nothing (a study); the in-game look is confirmed from M1-7 on.
- Suggested model/effort: `opus` / high

### M1-7 — Theme and the empty main window
- Branch: `step/m1-7-theme-window`
- Depends on: M1-5, M1-6b
- Analysis: §9.1, §9.2, §9.3; [`docs/specs/ui-style.md`](../specs/ui-style.md) §2, §3, §4, §6, §7
- Scope: `UI/Theme.lua` with the token table of `ui-style.md` §2 and the three themes (**Nebula** default, Aurora, Drago), a weak-key registry of tinted regions and `Theme.Apply` without `/reload`, font objects (Outfit, JetBrains Mono, Orbitron for titles; OFL files and `OFL.txt` in `FinlandDragonCreditPoints/Media/Fonts/` after checking the licence, the Reserved Font Name and the Italian glyphs; the game font as fallback when `SetFont` fails), the `Px()` helper for 1 px lines; white TGA textures generated by a script in `tools/` (9-slice fills and rings 8/12/18, shadow, glow, pill, circle, icon sheet); first widgets (`Button` primary / secondary / ghost / neon, `Card`, `TitleBar`, `Tabs` with the underline indicator, `Segmented`, `Badge`, `Dialog` base); the main window with the title bar and the six tabs of `ui-style.md` §6 (Roster · Credits · Progress · Loot · History · Settings as empty pages), movable, resizable from a minimum width and remembered per character, Esc to close; `/fdcp` opens it; minimap button (LibDBIcon) and AddOn Compartment entry; the logo converted to power-of-two TGA (256 and 64) in `FinlandDragonCreditPoints/Media/`; the in-game probes of `ui-style.md` §7 (ScrollBox templates, `ADD` blend, slicing at fractional scale, font objects) in `/fdcp debug`.
- Done when:
  - [ ] `/fdcp` opens a themed empty window in the mock with the six tabs; every visible text comes from the locales; switching the theme recolours every registered region.
  - [ ] Every texture and font path is listed in one assets table and exists (offline check).
  - [ ] The window looks right in game. *(in game)*
- Tests: `Tests/test_ui_shell.lua`, `Tests/test_theme.lua` (token parity across themes, WCAG contrast of text on surfaces).
- Docs: wiki Interface Tour (EN + IT, real layout replacing the design previews where possible) and Commands, README status and font credits, CHANGELOG.
- Real client: look against the previews of `ui-style.md` §8, fonts and accents, 1 px lines at the user's scale, Esc, minimap button.
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
