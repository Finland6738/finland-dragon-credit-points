# Backup and Seasons

> **Built, not yet seen in the game.** Everything on this page works in the offline tests with a simulated client; the look of the pane, the paste of a long string and the size of the saved data after a long season are still to be confirmed in the real game. [Italiano](Backup-and-Seasons-it)

The guild's ledger lives in the saved data of every officer's game. This page explains how to keep a copy of it outside the game, how to share the guild's rules with another guild, and how to make the saved data smaller at the end of a season.

## Where it is

**History › Backup** (the History tab, fifth sub-tab). It has three modes, **Settings**, **Backup** and **Archive**, over one text box. **Generate** puts a string in the box; **Select all** selects it so **Ctrl+C** copies it (an addon cannot write to the clipboard). To import or restore, paste a string into the box with **Ctrl+V** first.

Every string starts with `!FDCP:` and says what it is: `!FDCP:CFG:` (settings), `!FDCP:BAK:` (backup), `!FDCP:ARC:` (archive). Spaces and line breaks are ignored, so a string that a chat window or Discord wrapped still works. A string from a newer version of the addon is refused with a message.

## Settings: share the rules

- **Everybody** can generate the settings string: the rules are already shown to every member read-only.
- The string carries the whole configuration (costs, priorities, session, council, legendaries, bench, notices, upgrade hints) **except what belongs to your guild only**: the council's list of names and the faction name on the community site. When another guild imports it, those two keep that guild's own values.
- **Only the Guild Master** imports. Paste the string and click **Import…**: a dialog says how many settings change and which ones; nothing is written until you click **Confirm**. The import is one rule change, written in the audit with your name (History › Audit, *Settings*). If nothing would change, the pane says so.

## Backup: a copy of the whole ledger

- **Officers** (`view.attendance`) generate the backup string: every event of the ledger, including the attendance, so keep it private. Save it in a text file outside the game from time to time, and before anything risky (reinstalling the game, cleaning the `WTF` folder).
- **Restore** (`season.manage`, the Guild Master by default): paste the string and click **Restore…**. The dialog says how many events the backup holds and how many are missing here. A restore **only adds what is missing**: it never removes an event and never overwrites one. Restoring the same backup twice, or an older backup, changes nothing. Every event still goes through the guild's permission check, as in the officers' sync.
- Every restore is written in the audit (*restored a backup*), with your name and how many events it added.
- Restored into an empty ledger (a new computer, lost saved data), a backup gives back exactly the same ledger. The other officers then receive it through the sync as usual.

## Archive and compaction: the end of a season

A long season fills the saved data mostly with **lineup changes** (who was in the raid or on the bench at every moment). Once a season is **closed** (see [[Seasons|Seasons]]), the Guild Master can compact it:

1. In **Archive**, pick the closed season. The list says how many events would be removed.
2. Click **Generate**: the box gets the season's **archive** string, with **every** event of the season. Save it outside the game: it is the only full copy of what the compaction removes.
3. Click **Compact…**. It works only after the archive was generated in this session. The first dialog says how many lineup changes will be removed and what stays; **Continue** leads to a second, separate confirmation, **Compact**. Cancelling at either step changes nothing.

What the compaction keeps, tested offline on a whole season:

- every **credit total** (also with a bench bonus or malus), every award, void and correction, the nights, the kills and the **audit**;
- each member's **attendance** of every night (who played, who sat out, bosses present and possible), so the History views, the late joiners' rule and the bench rotation give the same numbers. Only the minute-by-minute lineup inside a night is gone (the night's detail shows who played and who sat out).

The compaction is an event of the ledger (*compacted the season*, in that season's audit). It reaches the other officers through the sync and their games compact too, so every officer's data shrinks. An officer who was away gets the events that are left and a note for each removed one, and stays in step. A compacted event never comes back, not even from an older backup. In the game it cannot be undone: the archive string is the way back to the details.

## Size of the saved data

`/fdcp debug` has two lines about the ledger: how many events it holds, about how many kilobytes they take in the saved data, how many were compacted (and of which seasons), and the four kinds of event that take the most room.

## Good to know

- Who may do what: settings string everybody, settings import the Guild Master; backup and archive the officers; restore and compaction `season.manage` (the Guild Master by default).
- The members' read-only credits table (see [[Credits Table|Credits]]) is not affected by a compaction.
