# 0009. A public read-only API for other addons

- Status: Accepted
- Date: 2026-11-24 (step M8-1)
- Revises: open question 6 of `docs/ANALISI.md` §13 (2026-11-19: "independent addon, no dependency and no in-game integration")

## Context

Azeroth Accord is the guild hub made by the same author. On 2026-11-24 its roadmap (M10 and M11) set the rules for working with other addons:

- the guild's officers choose one source for each kind of data;
- integrations are read-only, and they go only through a documented, versioned public API;
- Accord never reads another addon's SavedVariables and never writes another addon's data;
- level 0 is detection, level 1 is reading through the API.

When the guild picks FDCP as the source for loot and the raid roster, Accord wants to show several things: FDCP's season pool (MS1, MS2, OS), the lineup and the bench, a member's credits and queue place on its member card, and a short rules summary next to the handbook's loot page. Without an API, Accord can only detect FDCP and open it (level 0). On 2026-11-24 the owner agreed that FDCP exposes this API (Accord SPEC-10 Q10).

Not every client holds the same data. Only officers hold the ledger and sync it among themselves ([ADR 0005](0005-officer-ledger-sync.md)). Members receive only the read-only credits table that an officer sends ([ADR 0006](0006-read-only-credits-snapshot.md)). Attendance and absences are for officers only (§6).

## Decision

- **One global table with a fixed name: `FinlandDragonCreditPointsAPI`.** It is defined when FDCP loads (`App/PublicAPI.lua`), and its name never changes. FDCP never depends on the addon that reads it and never reads that addon's data.
- **Versioned.** `API_VERSION` is an integer, `1` today. It goes up only on a breaking change: a field or function removed, or a field whose meaning changes. New fields and new functions do not change it, so a reader ignores what it does not know. `GetVersion()` returns the addon's version and `API_VERSION`.
- **Read-only, by copies.** Each getter returns a new table of strings, numbers and booleans, built at the time of the call. It is never one of FDCP's own tables. The API table ignores writes, and its metatable is hidden. Nothing a caller does can change FDCP's state.
- **Nothing raises.** Every function runs protected. A wrong argument, data this client does not have, or an internal error gives `nil`, or an empty list where a list is expected.
- **Only what this client shows its player.** The getters read the same source as the Credits tab, through `GetSource()`:
  - an officer's client whose ledger has a season reads the ledger (`LEDGER`);
  - every other client reads the table an officer sent (`SNAPSHOT`);
  - a client that is not an officer never reads a ledger of its own, even an old one.

  So a member's client gives the season, the playing pool (character, faction, class, role, MS1, status, alts) and the credits and queue places. MS2, OS, the other-faction main, the availability days and the open night are on officers' clients only. **Attendance, absences, the player's free roster note, the audit, the log and the council are never exposed.** The night's lineup has only the raid and bench lists, never the absent list.
- **Getters:** `IsReady`, `GetVersion`, `GetSource`, `GetSeason`, `GetPool`, `GetMember` (an alt resolves to its main), `GetCredits`, `GetCreditList`, `GetNight`, `GetRules` (the preset, whether the guild changed it, the main costs and penalties; on a member's client the defaults of the Patto preset, marked `DEFAULT`), `GetEvents`.
- **Change notifications.** A caller registers with `RegisterCallback(event, fn)` and removes it with `UnregisterCallback(event, fn)`. The events are `READY`, `SEASON_CHANGED`, `POOL_CHANGED`, `CREDITS_CHANGED`, `NIGHT_CHANGED` and `RULES_CHANGED`. Each callback is called as `fn(event)` and runs protected: a failing callback is counted in `/fdcp debug` and logged, and FDCP and the other callbacks carry on. While any callback is registered, a ticker runs once a second. It compares a cheap key (the ledger's size, the kept snapshot, the guild, the source). When the key changes, it compares what each watched getter returns. So an event fires once for each change, and only when its own data changed. There are at most 32 callbacks per event.

## Alternatives considered

- **Stay independent (the 2026-11-19 answer).** Accord would stay at level 0 and show nothing from FDCP. A guild that uses both addons would have to type the same data twice.
- **Let Accord read FDCP's SavedVariables.** Accord's own rules forbid this. It would also tie Accord to FDCP's storage format, and it would give a member's client the officers' data whenever that member had once been an officer.
- **Send the data to Accord over addon messages.** Both addons run in the same client, so a global table is simpler and costs no traffic. Addon messages are also held back during the chat lockdown.
- **Expose FDCP's internal modules.** This would give out tables that a caller could change, with no version and no promise about what stays.
- **Callbacks through the internal bus.** The bus events follow FDCP's modules and change with them, and one write can raise several of them. The public events compare what the getters return, so they stay stable however FDCP changes inside.

## Consequences

- Accord can move to level 1 (its M10.2, M11.7 and SPEC-10 Q10). FDCP does not change for players who do not run Accord: the ticker runs only while a callback is registered.
- The API is a promise: a breaking change needs a new `API_VERSION`, an entry in `CHANGELOG.md` and the wiki page **API for Other Addons** updated in both languages.
- A member's client gives less than an officer's client. Accord must handle the missing fields: `nil` means "not on this client", not "empty".
- On a member's client the rules summary is the preset's defaults, because members do not receive the guild's rules. The summary says so (`source = "DEFAULT"`).
- Offline tests (`Tests/test_public_api.lua`) check: the copies, a member's client compared with an officer's client, the answers before the client is ready, the callbacks, and a failing callback being isolated.
- Not verified in the game:
  - another addon reading the table in the real client;
  - the order in which the two addons load;
  - the ticker's cost during a raid.
