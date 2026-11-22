# History: nights, log, audit, members and items

> **Built, not yet seen in the game.** The History tab works in the offline tests with a simulated client; how it looks in the real game is still to be confirmed. [Italiano](History-it)

The **History** tab tells what happened in the guild's raid nights. Like the credits, everything is worked out from the ledger every time: nothing is stored apart, so every client with the same events shows the same history. The tab has four sub-tabs: **Nights**, **Log**, **Audit** and **Export**. All four are ready; **Export** is described in its own page, [[Export|Export]].

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

## Log

Everything that **dropped** in the season, given or not, oldest first by date (click a column to sort):

| Column | What it shows |
|---|---|
| **Date** | The night's date (day/month). |
| **Boss** | The boss the item dropped from, when it is known. |
| **Item** | The item in its quality colour; a cancelled award is dimmed and marked *(cancelled)*. |
| **To** | The member, or *Guild bank*, *Disenchant*, *Master looter*, or *Not given* for a drop nobody received. |
| **Response** | The response the winner gave (main spec, off spec...). |
| **Cost** | What the award cost. |

The buttons at the top filter by **All**, **Given**, **Not given** and **Cancelled**; the search box finds an item (name or number), a member or a boss. A line under the buttons counts what is shown out of the season's drops. The button at the top of the Nights tab picks the season for all three.

## Audit

What the council and the Guild Master did **outside the normal rules**, each entry with its author, its date and its **reason**:

- an award the master looter changed (who got it instead of whom, and why);
- a correction of category or cost made before the roll;
- an award confirmed by the council's vote;
- an award cancelled, and credits moved by hand;
- every change of the guild's **settings** (who, when, how many settings and which ones, and the preset it started from) and of the permissions.

Filter by **Council**, **Cancelled**, **Credits** or **Settings**, or search the words of a line. Like the credits, the audit is open to every member.

## Export

The **Export** sub-tab gives the credits table of the season shown as text to paste into Discord, or as CSV or JSON. Officers only (`export.public`); it never carries the attendance. See [[Export|Export]].

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
| The loot log and the audit | yes | yes |
| Who was in the raid or on the bench, attendance | no | yes |
