# 0011. Roster requests over GUILD, direct additions, the raid group without a declaration

- Status: Accepted
- Date: 2026-11-24 (fix/roster-join)

## Context

When the owner tested 1.0.3 in the game, nobody could be added to the roster:

- `RosterController:RequestJoin` and `RequestAlt` existed, but no window and no command called them.
- Nothing sent a request to the officers: the requests table was local.
- The officers saw **Approve / Reject** for requests that never arrived, and they had no way to add a player themselves.

So the pool stayed empty, and nights, attendance and credits could not start. The offline tests wrote `MEMBER_JOINED` straight into the ledger, so they never saw it.

The ledger accepts `MEMBER_JOINED`, `MEMBER_LINKED_ALT` and `ROSTER_CHANGED` only from `roster.manage` (officers by default). Only officers hold the ledger ([ADR 0005](0005-officer-ledger-sync.md)); a member's client knows the season only from the credits snapshot ([ADR 0006](0006-read-only-credits-snapshot.md)). A member cannot send on the `OFFICER` channel.

In the game, Nebulah (Horde) and Nebulaa (Alliance) are two different guilds, so each ledger holds one faction only.

## Decision

- **The player asks on `GUILD`.** **Join the roster** (or **Link as alt**) sends a `RREQ` on `GUILD` (`Net/RosterNet.lua`). It carries the class the client gives, MS1 (required), MS2, OS, the weekdays and a short note. The member, or the alt, is always the **sender** the client gives, never a field, so a player only asks for their own character. Every client hears it; only a client whose own rank holds `roster.manage` stores it (`Roster.Receive`, checked again against its ledger).
- **The answer and the decision.** An officer's client whispers back `RACK`: the request is stored, or why it is refused. **Approve** or **Reject** sends a `RDEC` on `GUILD`. The other officers drop the request from their inbox. The player sees *approved* or *rejected*. A `RACK` or a `RDEC` counts only from a sender whose rank holds `roster.manage`. A request the ledger already settled (another officer approved it and the sync brought the event) leaves the inbox by itself (`Roster.Settle`).
- **Dedupe and throttling.** The request id is `<sender>#<q>`, where `q` is the player's number for it, so a request heard twice is stored once. A player's new request for the same character replaces their pending one. The player sends at most one request every 30 seconds. An officer's client takes at most one request per sender every 5 seconds. The transport caps each type. A request still waiting is sent again once, after the next login.
- **Officers add players directly.** **Add a player** lists the raid group's and the guild roster's characters who are not in the pool, with the class read from the game. MS1 is required. After a confirmation that shows the starting credits, it writes `MEMBER_JOINED` with the guild's late-joiner rule (`Roster.Join`, the nights played so far).
- **The raid group joins without a declaration.** **Add the raid group** adds, after a confirmation, every guild member of the raid who is not in the pool. Each joins with `Members.Join` and only the class, with the late-joiner rule. Each player then sends **Declare your specs**: the same form and the same request. The officer's approval writes it as a `ROSTER_CHANGED` with the reason `DECLARATION` (`Roster.Approve`). The status stays the officer's, and the credits do not change. Players outside the guild are never added.
- **No faction switch.** The Pool and the Credits tab show the faction of the player's own guild in their header. The faction stays in the events, in the domain and in the site export. The form does not ask for the other-faction twin: in the game it is a main of another guild, with another ledger, so it can never be in the same pool.

## Alternatives considered

- **The `OFFICER` channel.** A member cannot send on it.
- **Whisper each officer.** The client would need a list of officers who are online and run the addon, and it would send one message per officer. With `GUILD`, one message reaches all of them.
- **Open the form for each raid member in turn ("Add the raid group").** For 20 to 40 players this means 40 forms, and the officer would guess everybody's specs. The player knows their own specs; an undeclared member is already valid in the ledger.
- **Let the player write their own declaration in the ledger.** This breaks the rule that only `roster.manage` writes the roster, which the permission gate and the sync enforce on every event.
- **Keep the faction switch with data from the other guild.** One guild's ledger never holds the other guild's events, so the switch would always show an empty list.

## Consequences

- A guild that starts from zero works in the game. The Guild Master opens the season; the officers add players, or the players ask and the officers approve. Then an officer opens a night.
- Three new message types (`RREQ`, `RACK`, `RDEC`). A client older than this fix drops them unread: its player cannot send a request, but an officer can still add them directly. The session protocol (`Protocol.VERSION`) does not change.
- A request reaches only the officers who are online. If none is online, the player's line stays *sent*, and the request goes out again after the player's next login, or when the player sends it again.
- An undeclared member plays and pays credits like everyone else. Until they declare, the loot popup has no MS1 or MS2 for them (as before for a member added without a declaration), and the officers' Pool lists them under **Without a declaration**.
- Offline tests (`Tests/test_roster_join.lua`) cover the round trip on the network simulator (player, officers, approval, ledger sync), the direct and the bulk addition, dedupe, throttling, trust, and the windows.
- Not verified in the game:
  - `GUILD` and `WHISPER` addon messages between a member and the officers, and their throttling;
  - the guild roster's classes and the raid roster in the real client;
  - the forms and the dialogs themselves.
