# Privacy and Data

> **Built, not yet seen in the game.** [Italiano](Privacy-and-Data-it)

## What the addon keeps

Everything is saved by the game in the addon's SavedVariables file on **your own PC** (`<WTF>/Account/<account>/SavedVariables/FinlandDragonCreditPoints.lua`):

- your personal settings and profiles (theme, language, effects, window positions);
- the guild's data, kept per guild so two guilds never mix: the **ledger** of events (nights, drops, awards, corrections with their reasons, season changes), the pool of the season with the players' declarations, the lineups and the attendance, the rules, and the credits table last received;
- a short log and the last errors of the addon itself.

Credits are never stored: they are computed from the ledger. The ledger stores codes and numbers, not sentences.

## What the addon sends

Only **addon messages inside the game**, on the channels the game offers, never to the internet:

| Channel | What | Who |
|---|---|---|
| Raid | The loot session (items, costs, rounds, answers, result) and the presence answer with the addon version | raiders with the addon |
| Raid and whisper | The readiness check: a request from the master looter or an officer, and your own small answer (which slots have an enchant, which buffs are active, how many of each consumable you carry) whispered back to them only | the person who asked |
| Officer | The ledger sync between officers | officers |
| Guild and whisper | The read-only credits table | everybody in the guild |

A raider can only send their own answer, and the readiness answer is never saved by the one who receives it. Rolls are made by the game itself. The announcements written in `/raid` are ordinary chat lines.

## What leaves the game

Nothing, unless **you** take it out: the **Export** and **Site** pages of History and the **Backup** sub-tab build text that you copy (Ctrl+C) and paste yourself; the credits table for Discord and the files of the community site are produced by officers only, and the attendance is never in them. The addon has no network access and collects no statistics.

## Other addons

Another addon running in your game, such as Azeroth Accord, can **read** part of FDCP's data through a read-only API: the season, the pool, the credits and queue places, the open night's raid and bench, and a summary of the rules. It gets only what FDCP already shows you on this client. On a member's client that is the credits table an officer sent. Attendance and absences are never shared. No other addon can change FDCP's data. FDCP never reads other addons' data. See [[API for Other Addons|API-for-Addons]].

## The bug report

`/fdcp debug` builds a report with no player, guild, realm or item names, made to be pasted in a public issue. Read it before you paste it: [[Reporting Bugs|Reporting-Bugs]].

## Deleting the data

Remove the SavedVariables file with the game closed, or the addon folder to uninstall. The guild's ledger lives in every officer's file: deleting yours does not erase theirs, and an officer's addon will give you the credits table again. Only officers can restore a ledger from a backup string ([[Backup and Seasons|Backup-and-Seasons]]).
