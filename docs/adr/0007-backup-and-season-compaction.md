# 0007. Backup by merge, guild-wide season compaction with tombstones

- Status: Accepted
- Date: 2026-11-22 (step M6-7)

## Context

The ledger is event-sourced (`Domain/Ledger.lua`): credits are computed from events, every officer holds the whole ledger and the officers keep it in sync by heads and missing ranges ([ADR 0005](0005-officer-ledger-sync.md)). `docs/ANALISI.md` §7 asks for an import of the configuration (to share rules with other guilds) and a full backup of the ledger; §11 lists the size of the SavedVariables after a long season as a risk, mitigated by "snapshots and compaction at the end of the season, with an exportable archive". The owner's rule: no user data is deleted without explicit consent, and a restore is explicit and audited.

Two things make compaction delicate. The sync is a set union: an event one officer drops comes back from any officer who still has it. The sync relies on contiguous heads: a hole in an author's seqs makes every peer ask for it forever. And the credits must not change: the bench bonus or malus (`Domain/Rotation.lua`) reads the lineups, which are the bulk of a long season.

## Decision

- **Three strings, one format.** `!FDCP:<CFG|BAK|ARC>:1:` followed by Base64 of CBOR (deflated when that is shorter), one line, no size limit (they never travel as addon messages). Spaces and line breaks are ignored on reading.
- **Configuration.** The rules in force without the guild's own values (the council's names, the site's faction name). Anybody exports. Only the Guild Master imports, after a preview of the settings that change and an explicit confirmation. The import is a `CONFIG_CHANGED`, so it is gated and audited like any rule change. The importing guild keeps its own values of those two settings. The permission table is not exported: it depends on one guild's ranks.
- **Restore is a merge.** A backup holds every event and the tombstones. A restore goes through the same trust gate as the sync (an author the rank history never saw is vouched for by the restorer). It adds what is missing and never removes or overwrites an event, so it is safe to repeat and safe with an old backup. Into an empty ledger it gives the same ledger. Every restore is a guild-level `LEDGER_RESTORED{kind, events, added}` event, shown in the audit.
- **Compaction is a ledger event, for the whole guild.** `LEDGER_COMPACTED{types, removed, ms, nights}` of a closed season (`season.manage`) removes that season's events of `Ledger.COMPACTABLE` types (only `LINEUP_CHANGED` today) from every ledger that holds it. The payload keeps every night's attendance: who played, who sat out, bosses present and possible. `Nights.Attendance` and `Nights.Lineup` read it, so the credits (bench effect included), the late-join rule and the history keep their numbers. Nothing that moves credits or enters the audit is ever compacted.
- **Tombstones.** A removed event leaves its seq in `L.gone[author]` as ranges `{f, l, season}`. The heads count it as present, a merge drops it (`compacted`), and a new write of that type in that season is refused (`SEASON_COMPACTED`). When a peer asks for such seqs, `LEVENTS` carries them in `g`. The peer takes a tombstone only for a seq it lacks and for a season whose compaction it already holds. An officer who was away therefore catches up without endless requests.
- **Consent before anything leaves.** The app refuses a compaction until the season's archive string (every event of the season) was generated in this session, then asks two separate confirmations. The compaction is in the audit of its season.
- **Size.** `Ledger.Seen` (events plus tombstones) only grows. It replaces `Ledger.Count` as the `k` of the members' read-only snapshot ([ADR 0006](0006-read-only-credits-snapshot.md)), so a compacted officer is not taken for an older one. `/fdcp debug` estimates the ledger's size in the saved data.

## Alternatives considered

- **Compaction local to one client.** Each officer would compact by hand. The sync would bring the events back from anyone who did not, and the totals of a client that got the tombstones without the summary would differ. A guild-wide event converges by construction.
- **Restore by replacement.** Wiping the ledger and loading the backup would delete events written after the backup, without the owners' knowledge. A merge cannot lose anything.
- **Compact into the fold snapshot only.** The credit snapshot (§8.3) holds totals, not the attendance the bench rotation and the history need, and it is local data that the sync does not carry.
- **Compact more types** (`DROP_SEEN`, `ROSTER_CHANGED`). The loot log and the past seasons' rosters would change. The list is one table and can grow later; the payload names the types it removed.

## Consequences

- Every total, the attendance and the audit of a compacted season are unchanged. This is tested on a whole season, on two officers who converge, and on an officer who was away and catches up with tombstones.
- The minute-by-minute lineup of a compacted night is gone from the game. The archive string is the only full copy, and the guild keeps it outside the game.
- A compacted event never comes back, not even from an older backup. In the game the compaction cannot be undone.
- A tombstone from a trusted officer can mark a missing seq as gone. Officers are trusted as they already are for the ledger.
