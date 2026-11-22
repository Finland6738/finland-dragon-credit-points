# 0005. Officer ledger sync: pull by heads, gate per event, vouching for unknown authors

- Status: Accepted
- Date: 2026-11-22 (step M6-5)

## Context

Every officer's game holds the whole ledger (`Domain/Ledger.lua`, `docs/ANALISI.md` §8.3). Events are immutable, an event's id is `author:seq`, and a merge is a set union. Officers run nights on different days, so each officer's ledger misses what the others wrote while they were offline. §8.4 plans the sync on the `OFFICER` channel with per-author high-water marks. Addon messages are small (255 bytes per chunk), throttled, and held during the chat lockdown and boss fights (`Net/Transport.lua`). The permission gate of M2-5 judges an event by its author's rank when it was written. That rank comes from the rank history each client keeps from its own guild roster (M3-1), and the history is never exchanged between clients. A client therefore refuses, as `NOT_IN_GUILD`, every event of an officer who left the guild before that client read its first roster.

## Decision

- **Pull by heads.** Each client announces `LHEADS`: per author, the highest seq with no gap below it. A client that hears heads above its own sends `LWANT` with the missing ranges to the officer who has the most of them, one request at a time with a timeout. That officer answers with `LEVENTS`, a few events per message. Everyone who hears the events merges them, because merging twice changes nothing. A client that hears heads below its own announces its own heads. Announcements wait a few seconds after a change, are never closer than 20 seconds, and repeat at least every 5 minutes. An empty ledger is not announced: it learns from the others' heads.
- **Only more events.** The sync never overwrites. When an event with the same id but another content arrives, it is a conflict: the stored event wins and the conflict is counted.
- **Two trust checks.**
  - A sync message counts only when its sender, as the client names it (never a field), currently has a rank that may write ledger events.
  - Every event then goes through the permission gate one by one.
  - A refused event is not stored, and it is not asked for again until the rank history or the permission table changes.
- **Vouching for unknown authors.** Some authors have no record at all in the local rank history. Such an event is judged with the rank of the officer who relays it. An officer can therefore bring in only what they could have written themselves, and a member can bring in nothing. An author that the history knows is always judged by their own rank.
- **Budgets.**
  - At most 200 events per request and 600 events served every 5 minutes.
  - At most 1,800 bytes and 25 events per message.
  - Per-minute limits on `LHEADS` and `LWANT`.
  - `LEVENTS` is sent at `BULK` priority, behind the loot session and the announcements.

## Alternatives considered

- **Push every new event to the officers.** Events written while another officer is offline would be lost to that officer. A pull is needed anyway, so a push only adds traffic.
- **Exchange the rank history.** Any officer could rewrite another client's view of who held which rank, which is worse than vouching. Vouching is limited to authors the client has never seen, and to the relayer's own rank.
- **Refuse unknown authors, as before.** This is safe, but a newer officer's ledger would never converge with the older officers' ledgers once an officer leaves the guild.
- **Signed events.** The client has no public-key cryptography that addons can use, and a shared secret would be one more thing to leak.

## Consequences

- Officers converge without any action from them. This is tested on the network simulator, which now delivers `OFFICER` only to clients whose rank reads the officer chat and can log a player out and in.
- An officer can still forge an event in another officer's name, or in an invented author's name that is then vouched for. Officers are trusted as they were before, and the conflict counter shows two different contents for the same id.
- A client that lost its SavedVariables gets its own old events back from the others. If it writes before the sync completes, its new events get conflicting ids. Those events show as conflicts on the other clients and are not merged there.
- Not verified in the game:
  - who receives `OFFICER` addon messages;
  - how long texts are throttled;
  - the CBOR of `C_EncodingUtil` on the ledger's payloads.
- Members do not take part. The read-only credits for members are M6-6.
