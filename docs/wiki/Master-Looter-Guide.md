# Master Looter Guide

> **Built, not yet seen in the game.** The session window works in the offline tests with a simulated raid; how it looks and feels in a real raid, and the delivery of the item, are still to be confirmed. [Italiano](Master-Looter-Guide-it)

This page is for the **master looter**: the player who opens the boss's body and runs the roll. The addon does the sums and writes the proposal; **you confirm, reject or modify it**. You never calculate credits by hand and you never write the reason of a normal award: the addon does. You write a reason only when you depart from the rule.

## Before the raid

- Set the loot method to **Master Looter** (the addon works from the master looter's client only) and the threshold to the quality the guild rolls for.
- Everybody in the raid needs the addon active: only players with the addon can answer and roll. See [[Addon Check|Addon-Check]]. The Loot tab warns you, for example **3 raid members cannot roll**, with a **Notify in /raid** button (for who may use the addon check) that writes the notice for you.
- Open the night ([[Roster and Nights|Roster-and-Nights]]) so the kills and the awards belong to it.

## A boss, step by step

1. **Kill the boss.** The addon starts a session on your client when the boss dies. Nothing opens by itself during the fight: the session waits for the fight, an addon restriction or the chat lockdown to end.
2. **Open the body.** When you open the loot window the main window opens on **Loot › Session**. The items at or above the loot threshold are listed on the left, each with its category and cost (for example *Jewelry · 1 credit*), proposed by the addon from the guild's table. If the drops were read during a lockdown, the window says they are held and reads them as soon as it ends.
3. **Check the list.** Select an item to see it on the right. If a category or a cost is wrong, press **Correct** (see below). **Remove** takes an item you do not want in the session off the list.
4. **Press Start the session.** The categories and costs go to the raid. With the guild's usual settings (automatic advance) the first roll opens by itself; if not, press **Open the roll** on the item you want.
5. **The roll.** Every raider with the addon gets a popup, answers *Main-spec*, *Off-spec* or *Pass* (with an optional label and note) and rolls: see [[Rolling for Loot|Rolling-for-Loot]]. The right side of your window fills as the answers and the rolls arrive: for each candidate the credits, the answer, the roll and a note. A thin bar and a clock count down the round. The round closes by itself on its timer or when everybody has answered and rolled; you can close it earlier with **Close the round**. If nobody asked for the item in main-spec, the off-spec round opens by itself; if two players are tied on credits and roll, a reroll opens among them.
6. **The proposal.** When the round closes the addon writes **who, how much and why**, for example *Proposal: Bryn, 1 credit. Same credits as the others, highest roll.* The proposed player is marked in the list. Under the sentence, in amber, are the things to look at (rolls set aside, a cost the council has to fix, a tie the rules cannot break, a proposal after a rejection).
7. **You decide:**
   - **Confirm and assign** writes the award in the ledger with the addon's reason and charges the credits. Nothing else to type.
   - **Reject** charges nobody and puts the item back (see below).
   - **Modify** changes the winner or the cost, and needs a reason (see below).
8. **The next item.** With automatic advance the next roll opens by itself after each award, so a boss with five items is five confirmations. There is only ever **one item in progress**: the next roll opens after the previous award, so its winner's credits are already charged. For that reason there is no *Confirm all* button: there is never a second proposal waiting.
9. **End the session** with **End session** when the last item is done (it is available while no item is in progress). Items you never rolled stay listed as waiting. A new boss kill also ends the previous session if no item is in progress.

If the window is closed, `/fdcp` opens it on the Loot tab while a session runs.

> **Handing over the item.** **Confirm** records the award and the credits. The addon handing the item over itself (master loot, or by trade at the end of the night) comes with a later version: until then, give the item to the winner yourself.

## Reading the candidates table

| Column | Meaning |
|---|---|
| **Candidate** | The name, in the class colour. |
| **Credits** | The player's credits when this item's roll opened (frozen for the item, so the result is the one the raid rolled against). |
| **Response** | Main-spec, Off-spec or Pass, with the label the player declared (*BiS*, *Big upgrade*, *Small upgrade*, *Situational*) when they gave one; a dot when nothing yet. The label informs you and the council; it never changes the proposal. |
| **Roll** | The first 1-100 roll of the current round (a reroll replaces it for the tied players). |
| **Notes** | *Proposed* for the winner; *No answer yet* while the round is open; the note the player wrote in their popup (shown after the other texts); the reason a roll was set aside (a second roll, not 1-100, rolled too early, **the addon is not active**). |

Sort by clicking a header. The list is ordered main-spec first, then fewest credits, then the highest roll. In a reroll the players who are not tied are dimmed.

A player who rolls without the addon is **not** counted: the roll appears with *The addon is not active* so you see it, and they cannot answer.

## Modify

Press **Modify** on a proposal. A card opens with:

- **New winner**: the candidates first (with their answer and credits), then the rest of the raid, then **To the guild bank** and **To be disenchanted**. A new winner pays the cost of their own answer, or the full cost if they did not answer.
- **Cost in credits**: change it if the winner should pay something else.
- **Reason (required)**: one of the list, never free text:

| Reason | When |
|---|---|
| Obvious waste | Given to another candidate instead of the first in line. |
| Passed to game the system | Given to someone who did not roll, at full cost. |
| The council priced the item | A cost decided by the council. |
| The category or the cost was wrong | A correction after the fact. |
| A piece of a legendary chain | Legendary pieces. |
| A mistake by the master looter or the addon | A slip. |
| Another reason | Anything else (say it to the raid). |

While you choose, the card shows the proposal that would result and **how it departs from the rules**: *Out of line: Bryn was first in line, Corin instead.* and *Cost: 2 credits instead of the 1 credit the rules chose.* **Save** is refused, with the reason in plain words, while no reason is chosen or nothing changed. A modified proposal stays a proposal: you still press **Confirm and assign**. The award is flagged in the audit as an intervention, with the rule's winner and cost, your reason code and your name.

## Reject

**Reject** opens the choices of what happens to the item. Nobody is charged:

| Choice | Effect |
|---|---|
| Put the item back: reopen it later | It goes back to waiting, marked *On hold*; you open its roll when you want (select it and press **Open the roll**). Automatic advance does not reopen it. |
| Reopen the roll now | A fresh roll opens at once. |
| Go on to the next tier | The tiers up to the proposal's are skipped (for example main-spec finished, go to off-spec). |
| Send it to the guild bank / Disenchant it | A new proposal for the bank character or the disenchanter. |

The next proposal carries the note *This is a new proposal after a rejection.*

## Correct (before the roll)

**Correct** is available while the item has not been proposed: choose the right **category**, or type the **base cost** (the multiplier of each answer still applies), and give a reason. It is blocked once the item's roll is open when the guild's rules lock the category on opening.

## Pause, timers and the lockdown

- **Pause** stops the timers and the automatic steps and keeps the time that was left; **Resume** goes on. Your own buttons keep working while paused.
- The session never opens or closes anything during a boss fight or a chat lockdown: it waits and goes on afterwards. A roll the game hid during the lockdown is read when it ends, and the round does not close before then.
- If you `/reload` or disconnect, the session comes back as you left it, even in the middle of a reroll.

## Other officers

Officers who are not the master looter see the same window **read-only**: the items, the round, the proposal and its reasons, but no buttons and no table of candidates (the answers go to the master looter only). Players without the permission see their own popup instead.

## If the guild uses other modes

The guild may set the award to **automatic** (the addon confirms a clean proposal by itself after a short window, never after you intervene; the strip says *The addon confirms by itself in N s* and you can still Reject or Modify during it) or to **council** (the council votes; this arrives in a later version). Which mode is in force is a guild rule: see [[Loot Rules|Loot-Rules]].
