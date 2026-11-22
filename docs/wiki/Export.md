# Export: the credits table for Discord, CSV and JSON

> **Built, not yet seen in the game.** The export works in the offline tests with a simulated client; how the copy box behaves in the real game is still to be confirmed. [Italiano](Export-it)

The **History › Export** sub-tab turns the season's **credits table** into text you can paste: into a Discord channel, into a spreadsheet, or into any tool that reads JSON. The text is worked out from the ledger every time you open the tab, so it always matches the Credits tab. For the community site's own files (roster, loot, progress) see [[Site Export|Site-Export]].

## Who can export

The permission `export.public`: **officers** by default (the Guild Master can lower or raise it, like the other permissions). Anyone else sees a line saying their guild rank cannot export, and no text.

## How to copy

1. Open **History › Export** (the season shown is the one picked in the Nights tab).
2. Pick **Discord**, **CSV** or **JSON**.
3. Press **Select all**, then **Ctrl+C**. The game does not let an addon write to your clipboard, so the text is selected for you to copy. The box cannot be edited: a change by hand is put back.
4. Paste it where you want it.

## The three forms

| Form | What you get |
|---|---|
| **Discord** | A bold title with the season and the date of the last night, then a monospaced table in a code block: place in the queue, member, class, role, credits. Discord refuses messages over 2000 characters, so a long guild is split in **parts** (a button *Next part* steps through them; each part repeats the column line and ends with `(part 1/3)`). Paste one part per message. |
| **CSV** | One row per member: place, member, class, role, credits, then one column per night with what the member spent that night. In English the separator is a comma; in a language that writes the decimal comma (Italian) it is a **semicolon**, so a spreadsheet of that language opens it correctly. |
| **JSON** | The same data for programs: dates as `YYYY-MM-DD`, numbers with a decimal point, the keys always in the same order, the roles and classes as codes (`WARRIOR`, `TANK`). It does not change with the language. |

## Language

Discord and CSV use the **guild's language**: class and role names, the title, the date pattern (`21/10/2026` in Italian, `10/21/2026` in English) and the decimal mark (`1,5` or `1.5`). The JSON is the machine form and never changes.

## What is in it, and what never is

The table is the Credits tab's: the **playing mains of your faction**, in queue order (the fewest credits first), with the credits spent in each night. A cancelled award does not count, a correction does. Names are written without the realm.

**Attendance is never exported.** Who was in the raid, who sat on the bench and how often anyone played is for the officers' eyes in the addon only; no export carries it.

The same ledger always gives exactly the same text.
