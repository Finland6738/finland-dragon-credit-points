# Settings

> **Built, not yet seen in the game.** The tab works in the offline tests with a simulated client; how it looks in the real game is still to be confirmed. [Italiano](Settings-it)

The **Settings** tab has five sub-tabs: **Personal**, **Rules**, **Permissions**, **Site** and **Season**. Everybody sees all of them. **Only the Guild Master** (the player with the first guild rank, rank index 0) can change the guild's **rules** and **permissions**: for everybody else the controls are off, the **Save** button is not there and a note says so. Your **personal** preferences are yours and anybody can change them.

The addon also has a small entry in the game's own settings window (**Options › AddOns › Finland Dragon Credit Points**): the neon effects, animations and sounds switches and a button that opens this tab.

## Personal

Only for you: nothing here is shared with the guild.

| Setting | What it does |
|---|---|
| **Theme** | Nebula, Aurora or Drago, applied at once (`/fdcp theme`). |
| **Fonts** | The addon's own fonts, or the game's. |
| **Neon effects** | Glows and shadows on or off (`/fdcp effects`). |
| **Animations** | The 120–320 ms transitions on or off (`/fdcp animations`). |
| **Sounds** | A short chime when a loot popup appears. |
| **Language** | `auto` (the game's) or another language; it needs `/reload`. |
| **Language of messages for everyone** | The language of what the addon writes in `/raid`. |
| **Loot popup › Reset position** | Puts the popup back at the centre, at its starting width. |
| **My own stat weights** | Turns your imported weights on or off (import them with `/fdcp weights`, see [[Upgrade Hints|Upgrade-Hints]]). |
| **Wishlist › Clear** | Empties your best-in-slot list, after a confirmation. |

## Rules

A list of pages on the left, the fields of the page on a card:

- **Night and session**: whether an officer must open the night, who confirms an award (the master looter, automatic after a pause, or the council), the automatic steps, the seconds of a roll round.
- **Priority**: who goes first (fewest credits, fewest credits per night, highest roll), the tie-breaks, the rerolls in a row, whether the addon is required, which responses are allowed, what happens to an item nobody wants or a BoE.
- **Costs**: the cost of each category and quality, in a grid (*Council* in the legendary column means the council sets the cost; type the word to put it back).
- **Multipliers**: the cost factor of each response, of the raid size and of the difficulty.
- **Members and credits**: main characters only, how late joiners start (average, median, lowest, zero, fixed), the rounding, and the credits a season starts with.
- **Loot council**: whether its members must be in the raid, the vote, the flags for wasteful requests, who sees the verdicts, and the list of council names (empty: whoever has the rank).
- **Legendaries and bench**: how a legendary is awarded, the cost of a chain piece, and what the bench earns.
- **Messages in /raid**: the wording of the notice for players without the addon and of the item and result lines (placeholders `{names}`, `{link}`, `{addon}`).
- **Upgrade verdict**: how the popup says whether an item is an upgrade ([[Upgrade Hints|Upgrade-Hints]]).

Everyone sees the values. The Guild Master edits them: a label turns amber while its value differs from the rules in force, and the line at the bottom counts the changes not saved yet. A number that is not valid is marked at once and never reaches the draft. **Save** checks the whole configuration (if something is not valid it opens the page and names the field), then writes **one** change to the guild's ledger; **Discard changes** brings the form back to the rules in force.

**With a season open** Save first asks for your explicit confirmation: a dialog lists the changes, and the change is kept in the ledger with your name and the confirmation, so the officers can see it in **History › Audit** (*Settings*). Nothing is written until you click **Confirm and save**.

A change is a signed event of the ledger, not a setting of your game: another player cannot make one by any means. The addon refuses it when you ask, and the rest of the guild's addons refuse it if it ever arrives from someone who was not the Guild Master when it was written.

## Permissions

The table of **who may do what**, by guild rank: for each permission, the **lowest rank** that holds it (that rank and every higher one have it). The ranks are the guild's own, by position, so renaming a rank changes nothing. *Change the rules* and *Change the permissions* are fixed at the Guild Master. Like the rules, only the Guild Master edits the table, and a change with a season open asks for the same confirmation.

If the guild **reorders, adds or removes ranks**, the Guild Master sees a notice at the top of the tab (and in chat, at every login until it is closed) with the permissions that now point to a rank that does not exist; click **I have checked the table** once it is right.

## Site

The guild's key on the community site (empty: your faction), used by the files of [[Site Export|Site-Export]]. It is a rule like the others: everybody sees it, the Guild Master edits it.

## Season

The season's page ([[Seasons|Seasons]]).
