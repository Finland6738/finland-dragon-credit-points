# History: nights, members and items

> **Built, not yet seen in the game.** The History tab works in the offline tests with a simulated client; how it looks in the real game is still to be confirmed. [Italiano](History-it)

The **History** tab tells what happened in the guild's raid nights. Like the credits, everything is worked out from the ledger every time: nothing is stored apart, so every client with the same events shows the same history. The tab has four sub-tabs: **Nights**, **Log**, **Audit** and **Export**. Only **Nights** is ready; the other three say they arrive in a later version (the loot log and the audit in M6-2, the exports in M6-3).

## Nights

A table of the season's nights, **newest first**, grouped by **week** (a week runs from Monday to Sunday and is named by its Monday; the first night of a week shows it in the first column).

| Column | What it shows |
|---|---|
| **Week** | The Monday of the week, on the first night of the week. |
| **Date** | The night's date (day/month). |
| **Instance** | The raid. |
| **Bosses** | The bosses killed and the instance's total (for example `3/10`). |
| **Drops** | Every award of the night, a cancelled one and a guild bank item included. |
| **Credits** | What the valid awards to members cost that night. |

The button at the top right steps through the seasons. Click a night to see its **detail** on the right: the date, the instance, the size and the difficulty, the bosses killed in order, and every award with the item (in its quality colour), the recipient (or *Guild bank*, *Disenchant*, *Master looter*) and the cost. A cancelled award stays in the list, marked *(cancelled)*, and costs nothing.

**Officers** also see who was **in the raid** and who was **on the bench** at the end of the night. Members do not: that data is not even in their window.

## A member's history

Click a drop and press **Member** to open the member's window:

- **Credits** now and at the start of the season.
- **Items won**, newest first, with the night and the cost. A cancelled award is shown dimmed. Click an item to open its window.
- **Credits over time**: the start, then each award and each correction, ending at the number of the credits table.
- **Council actions**: every time the council modified an award, cancelled one or corrected the member's credits, with the reason.
- **Attendance** (officers only): the nights played and benched, the bosses attended out of the ones possible, and the state for each night.

## An item's history

Press **Item** (or click an item in a member's window) to see how many times the item **dropped**, was **given** and was **seen**, **who has it** (and how many times) and **every drop** with the night, the recipient and the cost, across all seasons. Click a name to open that member.

## Who sees what

| | Everyone | Officers (`view.attendance`) |
|---|---|---|
| Nights, drops, bosses, credits spent | yes | yes |
| A member's items, credits and council actions | yes | yes |
| An item's drops and owners | yes | yes |
| Who was in the raid or on the bench, attendance | no | yes |
