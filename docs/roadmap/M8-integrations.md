# M8 — Integrations

**Goal:** other addons read FDCP's data through a public, read-only, versioned API, never through its SavedVariables. FDCP never depends on them and never reads their data ([ADR 0009](../adr/0009-public-read-only-api.md), [`docs/ANALISI.md` §8.6, §13 question 6](../ANALISI.md#86-api-pubblica-per-altri-addon)).

**Exit criterion:** the API is complete in code with green tests and documented in the wiki in both languages. Azeroth Accord can read it from its M10.2 and M11.7 steps; that side is Accord's work, not FDCP's.

### M8-1 — Public read-only API for other addons
- Branch: `step/m8-1-public-api`
- Depends on: M6-5, M6-6, M3-7, M3-3, M7-2
- Analysis: §8.6, §13 (question 6 revised on 2026-11-24)
- Scope: owner decision of 2026-11-24 (Accord SPEC-10 Q10). New `App/PublicAPI.lua` defines the global `FinlandDragonCreditPointsAPI`:
  - `API_VERSION` (an integer, 1), `IsReady`, `GetVersion` and `GetSource` (`LEDGER` on an officer's client, `SNAPSHOT` on a member's client);
  - `GetSeason` (id, name, state);
  - `GetPool` and `GetMember`: per main, the character, faction, class, role, MS1, MS2, OS, status, alts, the other-faction main and the availability days;
  - `GetCredits` and `GetCreditList`: credits and queue place;
  - `GetNight`: instance, size, difficulty, and the raid and bench lists, without attendance;
  - `GetRules`: the preset, the main costs and the penalties;
  - `RegisterCallback` and `UnregisterCallback` for `READY`, `SEASON_CHANGED`, `POOL_CHANGED`, `CREDITS_CHANGED`, `NIGHT_CHANGED` and `RULES_CHANGED`.

  Every getter returns a copy, never raises, and gives `nil` or an empty list for data this client does not have. A member's client exposes only what the read-only credits table carries. Attendance and absences are never exposed.
- Done when:
  - [x] Copies: changing what a getter returned changes nothing in FDCP; the API table ignores writes; wrong arguments and internal errors give `nil` or the empty fallback.
  - [x] A member's client gives the snapshot's season, pool, credits and places, the same numbers as the officer's, no night, no MS2 / OS / availability, and the default rules marked `DEFAULT`; an officer's client gives the ledger's data, and the night's raid and bench lists, never the absent list.
  - [x] Before the guild roster is read, every getter gives `nil` or an empty list; `READY` fires once the roster is read.
  - [x] Callbacks fire once per change and only for the data that changed; a failing callback is counted and the others still run; an unregistered callback is not called again.
  - [x] ADR 0009, analysis §8.6 and §13, wiki **API for Other Addons** (EN + IT), README (EN + IT), CHANGELOG.
  - [ ] In the game: another addon (Azeroth Accord, or a `/run` script) reads the table on an officer's client and on a member's client, and the callbacks fire after a real night. *(in game)*
- Tests: `Tests/test_public_api.lua` (the global table, before ready, officer and member on the network simulator, copies, callbacks).
- Docs: ADR 0009; analysis §8.6, §13; wiki **API for Other Addons**, Home, Privacy and Data, sidebar (EN + IT); README (EN + IT); CHANGELOG.
- Real client: another addon reading the global; the load order of the two addons; the ticker's cost in a raid.
- Suggested model/effort: `opus` / high
