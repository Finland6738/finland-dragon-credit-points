# API for Other Addons

*Italiano: [[API per altri addon|API-for-Addons-it]]*

FDCP shares its data with other addons through one **read-only** table, `FinlandDragonCreditPointsAPI`. The table's name never changes. Azeroth Accord, the guild hub by the same author, reads it to show the season pool, the lineup and a member's credits. Any other addon may read it too.

This page is for **addon authors**. Players do not need to do anything: the API costs nothing until an addon uses it.

## The rules

- **Read-only.** Every function returns a **new copy**, never one of FDCP's own tables. Changing what you get back changes nothing in FDCP. Writes to the API table are ignored.
- **Never an error.** If you pass a wrong argument, or the data is not on this client, you get `nil`, or an empty list where a list is expected.
- **Versioned.** `API_VERSION` is a whole number, `1` today. It goes up only when a change would break a reader: a field or a function removed, or a field whose meaning changes. New fields and new functions do not change it, so ignore what you do not know.
- **Only what this player can already see in FDCP.** Attendance and absences are **never** shared, because they are for officers only. Neither are a player's free roster note, the audit, the log or the council.

## Officers' clients and members' clients

Not every client holds the same data:

- An **officer's** client holds the guild's ledger.
- A **member's** client holds only the credits table that an officer sent.

`GetSource()` tells you which one you are reading: `"LEDGER"` or `"SNAPSHOT"`, or `nil` when the client has no data yet. When a field is `nil`, it means "not on this client". It does not mean "empty".

| Function | Officer's client (`LEDGER`) | Member's client (`SNAPSHOT`) |
|---|---|---|
| `IsReady()` | `true` once the guild roster is read | the same |
| `GetVersion()` | the addon's version, `API_VERSION` | the same |
| `GetSeason()` | `id`, `name`, `state` (`"OPEN"` or `"CLOSED"`), `updated` (date of the newest night) | the same, plus `asOf` (the server time when the officer made the table) |
| `GetPool()` | every main of the season (see below) | the mains who play (active and trial), without `ms2`, `os`, `twin` and `avail` |
| `GetMember(name)` | one entry of the pool; an alt gives its main, with `viaAlt = true` | the same, from the table |
| `GetCredits(name)` | `name`, `credits`, `place`, `of`, `faction`, `viaAlt` | the same numbers |
| `GetCreditList()` | the credits and places of every playing main | the same |
| `GetNight()` | the open night: `date`, `instanceID`, `instance`, `size`, `difficulty`, `faction`, `raid` = names, `bench` = names | `nil`: members have no nights |
| `GetRules()` | the guild's rules summary, `source = "GUILD"` | the Patto preset's defaults, `source = "DEFAULT"` |
| `GetEvents()` | the event names you can register | the same |

Each entry of the pool has these fields:

- `name`: `"Name-Realm"`;
- `faction`, `class` and `role`;
- `ms1`, `ms2` and `os`: game spec ids. MS1 is the main spec and MS2 the off-spec used for loot. OS is the spec the player would like to play;
- `status`: `"ACTIVE"`, `"TRIAL"` or `"INACTIVE"`;
- `alts`: a list of names;
- `twin`: the same player's main in the other faction;
- `avail`: the weekdays the player can raid (`"MON"` … `"SUN"`).

`place` is the player's place in the loot queue, as the [[Credits Table|Credits]] shows it: fewest credits first, then the name. It is counted among the playing mains of the player's faction, and `of` is how many they are. An inactive member has credits but no place.

`GetRules()` gives:

- `preset` (for example `"PATTO"`), and `custom = true` when the guild changed the preset;
- `metric`, `startCredits` and `awardMode`;
- `costs[category][quality]`: a number, or `"council"`. Qualities are `3` (blue), `4` (purple) and `5` (orange);
- `responseMultiplier` (`MS`, `OS`, `TMOG`);
- `lateJoin`;
- `bench` (`effect`, `amount`);
- `penalties` (`absence`, `cheat`).

## Notifications

```lua
local api = FinlandDragonCreditPointsAPI
if api and api.API_VERSION == 1 then
  api.RegisterCallback("CREDITS_CHANGED", function(event)
    local mine = api.GetCredits(UnitName("player"))
    -- mine is nil when this client does not know your credits yet
  end)
end
```

The events are:

- `READY`: the guild roster is read;
- `SEASON_CHANGED`;
- `POOL_CHANGED`;
- `CREDITS_CHANGED`;
- `NIGHT_CHANGED`;
- `RULES_CHANGED`.

Your function is called with the event name only. Read the new data with the getters. It runs **protected**: if it fails, FDCP counts the error (`/fdcp debug`, line `API`) and carries on. An event fires once for each change, and only when its own data changed. FDCP checks for changes once a second, and only while at least one callback is registered. Each event takes up to 32 callbacks. Stop listening with `UnregisterCallback(event, fn)`.

Both `api.GetSeason()` and `api:GetSeason()` work.

## Load order

Your addon may load before FDCP. Look for the table after `PLAYER_LOGIN`, or add `## OptionalDeps: FinlandDragonCreditPoints` to your TOC. Before the guild roster is read, `IsReady()` is `false` and the getters give `nil` or empty lists: register `READY`.

## Not verified in the game yet

The API is tested offline (`Tests/test_public_api.lua`). Three things have not been tried in the real client yet:

- another addon reading it;
- the order in which the two addons load;
- the cost of the change check during a raid.

See also [[Privacy and Data|Privacy-and-Data]] and the decision record [ADR 0009](https://github.com/Finland6738/finland-dragon-credit-points/blob/main/docs/adr/0009-public-read-only-api.md).
