# Spike results (M0) / Risultati dello spike

Empty template: the owner's results are folded in by step M0-7. Plan A is what [`docs/ANALISI.md`](../ANALISI.md) assumes; plan B is the fallback of its §11. / Modello vuoto: i risultati del proprietario vengono inseriti dal passo M0-7.

Status / Stato: **probe ready, results pending owner run**.

| Check id | Area | Plan A result | Plan B needed? | Notes (plan A / plan B, steps affected) |
|---|---|---|---|---|
| `B1` | base | | | |
| `B2` | base | | | |
| `B3` | base | | | |
| `B4` | base | | | |
| `S1a` | S1 | | | Loot method APIs, master looter state |
| `S1b` | S1 | | | Master loot can be set (10/20/40, Normal/Veteran) |
| `S2a` | S2 | | | Slots, links, sources |
| `S2b` | S2 | | | Master loot candidates |
| `S2c` | S2 | | | `GiveMasterLoot` from an addon command (plan B: trade, M4-7) |
| `S2d` | S2 | | | Blocked / forbidden actions |
| `S3a` | S3 | | | Roll and loot patterns built from the globals (self-test) |
| `S3b` | S3 | | | Own roll with `RandomRoll(1, 100)` |
| `S3c` | S3 | | | Others' rolls readable, not secret, after `ENCOUNTER_END` and between bosses (plan B: M4-3) |
| `S3d` | S3 | | | Restriction state and encounter timeline |
| `S3e` | S3 | | | `CHAT_MSG_LOOT` matched by the `LOOT_ITEM` patterns |
| `S4a` | S4 | | | Prefix `FDCPP` registers; lockdown APIs exist |
| `S4b` | S4 | | | Last send (`/fdcpp ping`, `pingbig`, `burst`) |
| `S4c` | S4 | | | `RAID` sends succeed between bosses and after `ENCOUNTER_END`; lockdown timings (plan B: wait queue, M2-3) |
| `S4d` | S4 | | | Second client: delivery, losses, order, delays |
| `S4e` | S4 | | | CBOR + Deflate + Base64 round trip, fits 255 bytes |
| `S5a` | S5 | | | Item APIs and `C_TooltipInfo` exist |
| `S5b` | S5 | | | Instant info, cache miss, item levels (outside and inside the raid) |
| `S5c` | S5 | | | Stats, delta vs equipped, spec flags, tooltip comparison (plan B: item-level-only verdict) |
| `S6a` | S6 | | | Specializations readable (plan B: declared spec only) |
| `S6b` | S6 | | | Other specialization APIs |
| `S7a` | S7 | | | Guild APIs exist. Plan B: manual rank list. Steps: M1 roster, M3 permissions |
| `S7b` | S7 | | | Rank index, rank count, officer flags for GM / officer / member (one row per role). Steps: M1-x roles |
| `S7c` | S7 | | | Roster load timing after `GuildRoster()` |
| `S8a` | S8 | | | `GetLocale` and localized globals (itIT / enUS). Steps: M1 localization |
| `S8b` | S8 | | | Official raid event and attendees readable. Plan B: manual attendance. Steps: M3 attendance |
| `S8c` | S8 | | | `RAID` chat from a command vs from a click. Plan B: announce button. Steps: M4 `/raid` notice |

All checks S1 … S8 are in. / Tutti i check S1 … S8 sono presenti.
