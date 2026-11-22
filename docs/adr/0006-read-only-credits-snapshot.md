# 0006. Read-only credits for members: an officer's snapshot, newest ledger wins

- Status: Accepted
- Date: 2026-11-22 (step M6-6)

## Context

Only the officers hold the guild's ledger: they keep it in sync on the `OFFICER` channel ([ADR 0005](0005-officer-ledger-sync.md)). The Credits tab (M3-8) and the player's loot popup (M4-6) compute the credits from the local ledger, so on a member's client they showed nothing. `docs/ANALISI.md` §8.4 plans a "signed" read-only table on `GUILD` for every member, and recovery by `WHISPER` for a member who joined late or reloaded. The client has no public-key cryptography that addons can use. What it does give is the sender's name with every addon message, and nobody can fake that name.

## Decision

- **A table, not the ledger.** The officer's client sends the credits table of the current season (the open one, else the newest): the label, the state, the newest eight nights (date, instance) and, per member of both factions, class, role, spec, status, faction, alts, total and what they spent in each of those nights (`Domain/CreditSnapshot.lua`). Nothing in it becomes a ledger event: members never hold the ledger, the attendance and the audit never leave the officers.
- **"Signed" means the sender's rank.** A snapshot counts only when its sender, as the client names it (never a field), currently has, in the member's own guild roster, a rank that may write ledger events. This is the same test as the officers' sync (`Sync:Trusted`). A snapshot from anybody else, or one heard before the roster is read, is ignored and counted. Every field is checked for type and size before it is kept.
- **The newest ledger wins.** A ledger only grows, so every snapshot carries `k`, the number of events in the officer's ledger. A member keeps a new snapshot only when its `k` is larger. When `k` is equal, the later one wins. A snapshot kept for more than seven days gives way to any later one. An officer who comes back behind therefore cannot take the members back.
- **Broadcast after a change, recovery by asking.** An officer's client broadcasts `CSNAP` on `GUILD` 30 seconds after its ledger grew, plus a few seconds of its own derived from its name. It never broadcasts twice within 60 seconds. When it first hears another officer's snapshot that is at least as new as its own ledger, it drops its plan. A member's client asks on `GUILD` (`CSNAPQ` with its own `k`) a few seconds after its guild roster is read. Every officer whose ledger is newer offers by `WHISPER` (`CSNAPO`). The member asks the best offer by `WHISPER`, and the next offer if no answer comes within 30 seconds. Only the chosen officer sends the whole table.
- **Saved with the guild's data.** The kept snapshot survives `/reload` and logout. The Credits tab and the popup read it whenever the player is not an officer, or the player's own ledger has no season. The tab marks it as read-only and names the officer who sent it.

## Alternatives considered

- **Send the ledger to everyone.** This would expose the attendance and the council's audit, which are for officers only (§7). It would also be much more traffic and give members a ledger they cannot judge.
- **A hash or shared secret as the signature.** A secret known to every officer's addon is known to every copy of the addon. A hash proves nothing about who made the table. The sender's rank is the only proof the client offers.
- **Every officer answers every request.** In a guild with several officers online, a login would cost one full table per officer. The offer round costs a few bytes per officer and one table in total.
- **Newest by time.** An officer whose ledger is behind would send a newer timestamp with older numbers. The ledger size cannot go back.

## Consequences

- Members see the same totals as the officers. This is tested on the network simulator: after a night, after a login, after a `/reload`, and with a forged snapshot from a member, which is ignored.
- An officer can still send a false table. Officers are trusted as they already are for the ledger.
- A member whose guild changed the permission table judges the sender with the preset table, because members never receive `PERMISSIONS_CHANGED`. A rank given ledger rights only by the change would not be trusted by members.
- Older seasons are not sent: a member sees the season in course (or the last one).
- Not verified in the game:
  - `GUILD` and `WHISPER` addon messages between a member and an officer;
  - how a table of about 2–5 KB is throttled.
