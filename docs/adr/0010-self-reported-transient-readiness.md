# 0010. Raid readiness is self-reported and transient

- Status: Accepted
- Date: 2026-11-24 (step M8-2)

## Context

On 2026-11-24 the owner asked for a readiness tool for the master looter and the officers. For everyone in the raid it shows two things:

- the missing enchants, and on which slot;
- the missing consumables: buff food, food, water, potions, flasks or elixirs, ammunition for hunters, pet food.

A "Notify" button then posts a short summary in `/raid` and whispers each player what they lack (step M8-3, built on the `/raid` notice of M3-6).

The game gives an addon only a little about other players. Inspecting a player shows their gear, but it needs them close by, one player at a time, and it is throttled. Nothing shows another player's bags. Another player's auras can be read in a group, but on Forever an aura may be a secret value. So the master looter's client cannot see the bags of the raid, and seeing the enchants of 40 players would take minutes of inspection.

Each player's own client sees everything about its player: its gear (the enchant is the second field of each item link), its own auras, and its bag counts. FDCP is mandatory in the raid (§4.1), so nearly every raider runs it.

## Decision

- **Self-reported.** When the master looter or an officer asks, each raider's own FDCP client builds a small snapshot of itself (`Adapters/SelfCheck.lua`) and whispers it to the asker (`Net/Readiness.lua`). The snapshot holds three things:
  - for each enchantable slot that holds an item, whether it is enchanted (yes, no or unknown). It never sends the enchant or the item.
  - the readiness buffs active: Well Fed, a flask, an elixir.
  - the bag count of each consumable category asked. The count is summed over the item ids of `Data/Readiness.lua`.

  Nothing else from the bags is read or sent: no other item, no link, no name.
- **Read safely.** The snapshot is never read in combat or during a boss encounter. A request heard then waits and is answered when the fight is over. A value that is secret or cannot be read becomes "unknown"; it is never guessed and never compared. A raider without FDCP, or with a version older than M8-2, shows as "unknown".
- **Asked, not pushed.** Nothing goes out unless someone asks. A raider answers only a request that came on `RAID` from a member of its own raid who is one of these:
  - the raid leader or an assistant;
  - the master looter;
  - someone whose guild rank holds `raid.addonCheck`.

  The asker sends at most one request every 30 seconds. A raider answers the same asker at most once every 20 seconds. The transport caps both message types too.
- **Transient.** The answers live only in the asker's memory (`App/ReadinessCheck.lua`). A new request, leaving the raid or a `/reload` drops them. Readiness is not part of the credits, so it is never written to the ledger, the saved data, the backup, the exports or the public API ([ADR 0009](0009-public-read-only-api.md)).
- **The requirements are rules.** Which slots need an enchant, which categories are required and their minimum counts are the new section `readiness` of the guild's rules (`Domain/Readiness.lua`). A requirement can be limited to some classes, some roles, or to the classes that use mana. The Guild Master changes it like every other rule: a `CONFIG_CHANGED` through the permission gate, in the audit. The defaults can be undone and are described in `docs/ANALISI.md` §4.2.
- **Compatibility of the rules.** A client older than M8-2 does not know the section `readiness`, so it would refuse a `CONFIG_CHANGED` that carries it. So `Rules.Stored` leaves the section out of the event while it equals its defaults, and `Rules.WithDefaults` puts it back when the rules are read. Old clients keep reading the rules of a guild that never changes the readiness requirements. Once the Guild Master changes them, every officer needs a version with M8-2.

## Alternatives considered

- **Inspect each raider from the master looter's client.** This works without FDCP on the other side, but only for gear, never for bags. It is slow (one player at a time, close by, throttled), and a hidden link would leave a hole.
- **Read the raiders' auras from the master looter's client.** This is possible in a group, but it covers only the buffs, and on Forever any aura may be secret. The raider's own client reads its own auras with fewer limits.
- **Send the whole bag contents.** This would be simpler and give the master looter more to see, but it would expose far more than the check needs. The owner's rule is counts only, for the configured consumables.
- **Keep a history of readiness in the ledger.** It is not part of the credits, it would grow the ledger every night, and it would turn a convenience into a record of each player's habits.
- **Push a snapshot at every raid join.** This would send traffic nobody asked for and read the bags at times nobody chose.

## Consequences

- The master looter sees a table with one verdict per raid member: OK, WARN, MISSING or UNKNOWN, with the slots and categories that fail. Step M8-3 draws it as a tab and turns each row into a `/raid` summary line and a whisper.
- The verdict is only as honest as the raider's client: a modified addon could say it is enchanted. Readiness is advice for the raid, not a rule with a penalty, so self-reporting is enough.
- The item and spell ids are those of the original game and must be checked on WoW Forever (`docs/checklists/M8.md`). A wrong id never breaks the check. At worst it gives a false "low" or "missing" until the table is fixed.
- Offline tests (`Tests/test_readiness.lua`) cover the verdict, the snapshot built on the mock client, and the round trip on the network simulator, including trust, combat and throttling.
- Not verified in the game:
  - the item and spell ids;
  - which auras Forever hides;
  - `C_Item.GetItemCount` and `C_UnitAuras.GetBuffDataByIndex` in the real client;
  - whisper delivery of the answers in a 40-player raid.
