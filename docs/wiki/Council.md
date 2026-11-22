# Council

> **Built, not yet seen in the game.** The council's page works in the offline tests with a simulated raid; how it looks and feels in a real raid is still to be confirmed. [Italiano](Council-it)

This page is for the **loot council**: the officers (or the characters the guild lists) who watch the awards, vote when the guild asks for it and correct what went wrong. Everything the council does has its own page in the main window: **Loot › Council**, the third sub-tab after *Session* and *To deliver*. The master looter's own tasks (running the roll, confirming) are in the [[Master Looter Guide|Master-Looter-Guide]]; the rules behind them are in [[Loot Rules|Loot-Rules]].

The page shows what the addon already knows and sends your clicks to the same rules as the chat commands: it never decides anything by itself. Every action that changes the log asks for a **reason**, and without a reason nothing is written.

## Who is on the council

By default, the guild ranks with the *council member* permission (officers) who are **in the raid**. The guild may write an **explicit list of characters** in its rules: then the list replaces the rank. The line at the top of the page tells you whether **you are on the council**, whether it is set by rank or by list, and how an award is decided in this guild:

- **the master looter confirms each proposal** (the preset);
- **the addon awards by itself** unless a flag or a vote holds it;
- **the council's vote decides.**

When the guild asks for the vote in the other modes, the line adds *The council's vote is advice.*

## The item on the table

The card on the left follows the item the Session tab shows (select another item there to look at it here). It has:

- the **item** and the **proposal** the addon wrote (who, how much, why);
- the **flags** that name a player: *upgrade ignored* and *possible waste* ([[Master Looter Guide|Master-Looter-Guide]], "Council flags"). They are live while the round is open. They never change the winner by themselves. *No flag on this item.* when there is none;
- the **votes** cast so far, for example *Council votes (open): Corin 2, Bryn 1.*;
- **Your vote:** a list with the proposed player first and then the candidates, and the **Vote** button. A member votes for **one** player and can change the vote until the master looter closes it. The line next to the title says *you voted Corin* once it is sent, or *no vote open on this item* (the guild's mode has no vote, the item has no proposal yet, or the vote is closed), or *only council members vote*;
- **Modify** and **Correct**, only on the master looter's client: they open the same reason dialogs as the Session tab (the winner or the cost with a reason; the category or the cost before the roll opens). Another officer's window is read-only and has no such buttons.

You see the card from a **read-only view** if you are not the master looter: the item, the proposal and, where the guild lets you (the council by default), the candidates, the upgrade badges and the flags.

## Cancel an award

**Awards** lists the awards of the open season, newest first, with the item, the winner and the credits. Select one and press **Cancel award…**: a dialog asks for the **reason** (*mistake*, *duplicate award*, *obvious waste*, *passed to game the system*, *the council's vote*, *legendary*, *other*). The credits come back; the award stays in the log, marked cancelled, and the audit shows who cancelled it and why.

## Adjust credits

**Adjust credits…** (top right) moves a member's credits by hand. Pick the member of the season's pool, write the number (positive adds credits, like a cost; negative removes them, with `-`; at most 1000 either way) and pick the reason (*mistake*, *penalty*, *bonus*, *the council's vote*, *other*). A missing member, a number that is not a number, zero, or no reason is refused in the dialog and nothing is written.

## The audit

**Audit** lists every council intervention of the open season, newest first: awards that departed from the rule (with the rule's winner), corrections of category or cost before a roll, votes that decided an award, cancellations and credit corrections, each with its author and reason. An intervention that a later cancellation undid is shown dimmed.

## Legendary projects

**Legendary** shows how the guild's rules treat a chain piece (*they go to the builder chosen by the council, no roll*; *the council votes*; *rolled like any item*; *they go to the first of the project's queue who is in the raid*) and the cost of a piece, then the season's projects: name, builder, pieces paid out of the total, and the state (*open*, *Completed*, *Abandoned*).

- **Open project…** asks for the **name**, the **final item**, the **chain pieces** and, if you want, the **builder** (the list is the season's pool, or *Nobody yet*) and a **queue** of names. Items are item ids, or item links: click into the field and **shift-click** the item in your bags or the chat. A piece that another open project already holds, an item that is missing and a name outside the pool are refused in the dialog.
- **Mark as built** and **Abandon** close the selected open project. A closed project stays in the list.

A chain piece that drops is recognised by the session and proposed as the rules say (no roll for the builder in the preset); every piece paid is recorded in the project.

## Who can do what

The council page itself is open to everyone who can see the Loot tab, but each action goes through the same permission gate as everywhere else: cancelling an award, adjusting credits and opening or closing a project need the *night* permission while a night of the season is open (the master looter writes the council's corrections) and the *credits correction* or officer permission outside a night (the Guild Master in the preset). If your rank is too low, the dialog says so and nothing is written. Other players' addons check the same permission when the event reaches them.

## The commands still work

`/fdcp council` (status, `vote`, `awards`, `void`, `adjust`, `audit`) and `/fdcp legendary` do the same things from the chat box: see [[Commands|Commands]].
