# Seasons

> **Built, not yet seen in the game.** The window works in the offline tests with a simulated client; how it looks in the real game is still to be confirmed. [Italiano](Seasons-it)

A **season** is the guild's unit of credits: one pack of raids (the instances released with one content update), one credit table, and a start. A loot session can only run inside an **open season**. Only one season is open at a time.

## Where it is

**Settings › Season** (the Settings tab). **Every member** sees the current season, read-only: its name, whether it is open, the raids of the pack with their size, the rule for late joiners, the start credits and the **item-level band**. If no season is open it says so.

## Opening a season (Guild Master)

Only who holds the `season.manage` permission (the **Guild Master** by default) sees the form; for everybody else there are no buttons at all, and a forced call is refused.

1. Type an optional **name** (otherwise the season is called S1, S2…).
2. Type the **start credits** (what a member present from the start begins with; the guild's rule is proposed, 0 in the *Patto* preset).
3. Pick the **raids** of the pack (click a raid to select it) and the **size** of each (10, 20 or 40 players).
4. Optionally type the **item-level band** (min – max): the item levels of this season's epic items. The upgrade badge of the popup counts an epic a player wears **below** it as an epic of an older season (one step down, like a blue): see [[Upgrade Hints|Upgrade-Hints]]. You can also set it later.
5. Pick the **late-join rule**: what a member who joins after the first night starts with (fewest credits of the pool, the guild's preset; average of the pool, median, zero or a fixed value). If you change it, the new rule is written in the guild's rules as an audited change, just before the season.
6. Click **Open the season**. A summary appears: nothing is written until you click **Confirm**; **Cancel** leaves everything as it was.

The season is written in the guild's ledger as an audited event and **cannot be deleted**, only closed. A second season cannot be opened while one is open: the window says so and tells you to close the first.

## The item-level band (Guild Master)

While a season is open, the Guild Master sees two boxes, **min** and **max**, and **Save the band**. Type two whole numbers (min not above max, 1 to 2000) and confirm in the dialog: the band is written in the ledger (`SEASON_BAND_SET`), and the next loot session sends it to the raid with the items. Without a band, every epic counts as this season's in the badge. You can set it again at any time; the latest one counts.

## Closing a season (Guild Master)

Click **Close the season**. Closing asks **two separate confirmations**: the first (**Continue**) shows what is about to happen, the second (**Close it for good**) warns that a closed season cannot be reopened. Cancelling at either step changes nothing. The season's history stays: nothing is deleted. A season with a night still open cannot be closed: close the night first (see [[Roster and Nights|Roster-and-Nights]]).

## Good to know

- Every action is an event of the ledger (`SEASON_OPENED`, `SEASON_BAND_SET`, `SEASON_CLOSED`) with author and date, so officers can audit them; the other officers' windows update when the event reaches them.
- The raids are the ones of the addon's table (Molten Core and Onyxia's Lair for now).
- A closed season can be archived and compacted to keep the saved data small: see [[Backup and Seasons|Backup-and-Seasons]].
