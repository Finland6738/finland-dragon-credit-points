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
4. **Press Start the session.** The categories and costs go to the raid, also written in `/raid` ([see below](#announcements-in-raid)). With the guild's usual settings (automatic advance) the first roll opens by itself; if not, press **Open the roll** on the item you want.
5. **The roll.** Every raider with the addon gets a popup, answers *Main-spec*, *Off-spec* or *Pass* (with an optional label and note) and rolls: see [[Rolling for Loot|Rolling-for-Loot]]. The right side of your window fills as the answers and the rolls arrive: for each candidate the credits, the answer, the roll and a note. A thin bar and a clock count down the round. The round closes by itself on its timer or when everybody has answered and rolled; you can close it earlier with **Close the round**. If nobody asked for the item in main-spec, the off-spec round opens by itself; if two players are tied on credits and roll, a reroll opens among them.
6. **The proposal.** When the round closes the addon writes **who, how much and why**, for example *Proposal: Bryn, 1 credit. Same credits as the others, highest roll.* The proposed player is marked in the list. Under the sentence, in amber, are the things to look at (rolls set aside, a cost the council has to fix, a tie the rules cannot break, a proposal after a rejection, and the [council flags](#council-flags)).
7. **You decide:**
   - **Confirm and assign** writes the award in the ledger with the addon's reason and charges the credits. Nothing else to type.
   - **Reject** charges nobody and puts the item back (see below).
   - **Modify** changes the winner or the cost, and needs a reason (see below).
8. **The next item.** With automatic advance the next roll opens by itself after each award, so a boss with five items is five confirmations. There is only ever **one item in progress**: the next roll opens after the previous award, so its winner's credits are already charged. For that reason there is no *Confirm all* button: there is never a second proposal waiting.
9. **End the session** with **End session** when the last item is done (it is available while no item is in progress). Items you never rolled stay listed as waiting. A new boss kill also ends the previous session if no item is in progress.

If the window is closed, `/fdcp` opens it on the Loot tab while a session runs.

> **Handing over the item.** **Confirm and assign** also hands the item over, in the same click: see [Handing over the item](#handing-over-the-item) below.

## Handing over the item

**Confirm and assign** does two things in the same click: it writes the award and charges the credits, and it asks the game to hand the item over to the winner by **master loot**. Your click is the one the game may ask for.

**Plan A: master loot.** The addon looks for the item in the open loot window (by the item, not by its position: the list closes its gaps as items go) and for the winner in the master loot list, and hands it over. The item then waits in **Loot › To deliver** as *Handed over: waiting for the loot message* until the winner's loot message in the chat (*Bryn receives loot*) is read: then it is **Delivered** and leaves the list. If you win an item yourself, your own *You receive loot* is the receipt.

**Plan B: by trade.** When master loot cannot do it, the award stays in the ledger (the credits are charged all the same) and the item goes to the **To deliver** list with the reason:

| The list says | What happened |
|---|---|
| Master loot is not in use here | You are not the master looter, or the group uses another loot method: the usual case of plan B. |
| The loot window is closed | You closed the body before confirming. Open it again: the addon tries again by itself. |
| The item is no longer in the loot window | Someone looted it, or it was already handed over. |
| The winner is not on the master loot list | Too far away, or not in the raid. Ask them to come closer and press **Hand over now**, or trade. |
| The game refused to hand the item over | The game did not accept the call. Press **Hand over now** (your click), or trade. |

Hand the item over with an **ordinary trade**: the addon never starts, fills or accepts a trade for you, it only watches the trades you make. When a trade that gives the item to its winner goes through (or you receive in a trade an item you won yourself), the item is marked **Delivered**. When a loot message shows who holds the item, the list says so (*Held by Corin*). An item the winner already looted before you confirmed is delivered at once.

**The To deliver tab** lists every awarded item that has not reached its winner: the item, the winner and where it stands. Select a row and use:

- **Hand over now (master loot)**: tries master loot again, from your click. Use it after reopening the body or when the game refused. It is hidden while the item is waiting for its loot message.
- **Mark as delivered**: your word that the item reached its winner (a trade the addon could not read, a loot message the game hid). It is written as delivered by hand.

The header of the Session tab counts the items still to deliver.

**Rolling everything at the end of the night.** You may roll all the items first and hand them over later: the items stay in the list, **End session** keeps them, and when the next boss dies they move to the next session's list, so nothing is lost between bosses, even after a `/reload`. When you open a body again, the items that were waiting for it are tried again by themselves (not the ones the game refused: those wait for your click).

> **Not yet checked in the game:** that an addon may call `GiveMasterLoot` from a click, that the loot window and the master loot list read as described, what the trade events carry and whether the loot messages are readable inside an instance. If a step does not work, the item waits in the list and you hand it over by trade.

## Announcements in /raid

Everything the addon writes in `/raid` is written in the **guild language** the Guild Master chose in the settings, whatever the language of your own game, so the whole raid reads the same words. The wording and the on/off switch are the Guild Master's (rules section `announce`).

## What the addon writes in /raid

- **When you press Start the session**, one line per item: the item's link, its **category** and its **cost**, for example *[Ring of Embers]: Jewelry, 1 credit.* The category is announced **before** the first roll opens. An item whose cost the council sets says so (*cost set by the council*).
- **If you correct an item after the start**, a line says *Correction: [item] is now Weapon, 2 credits.*
- **When you confirm an award**, one line with the item, the winner, the cost and **why**, composed by the addon from the reason codes, for example *[Ring of Embers]: Bryn, 1 credit. Same credits as the others, highest roll.* An item that goes to the guild bank or is disenchanted says so instead of a winner.
- Every line starts with **[FDCP]**, is at most 255 characters (a longer text is split, an item link is never cut) and is written in the guild language. Nothing is written outside a raid group: the popups and your window carry the same news.

**When it writes.** Never while a boss fight is going on: the lines wait in a queue and go out as soon as the fight is over and the game's chat accepts them (a chat lockdown also makes them wait), a few per second, in order. If the game refuses a line five times in a row the queue is emptied. A raider's popup and the window show everything whether or not the lines go out.

**Changing the wording (Guild Master).** The Guild Master can switch the announcements off, change the item text and the result text and leave out the reason sentence. In a text, `{item}`, `{category}` and `{cost}` are replaced for the item line; `{item}`, `{winner}`, `{cost}`, `{category}` and `{reason}` for the result line. An empty text uses the default of the guild language. The change is saved in the rules and the audit says who made it. There is no window for it yet.

> **Not yet verified in the game:** that the game lets the addon write in `/raid` from your click (and from the automatic award, which has no click), and how the chat throttles a long list.

## Reading the candidates table

| Column | Meaning |
|---|---|
| **Candidate** | The name, in the class colour. |
| **Credits** | The player's credits when this item's roll opened (frozen for the item, so the result is the one the raid rolled against). |
| **Response** | Main-spec, Off-spec or Pass, with the label the player declared (*BiS*, *Big upgrade*, *Small upgrade*, *Situational*) when they gave one; a dot when nothing yet. The label informs you and the council; it never changes the proposal. Next to it, *(auto)* means the addon set it from the player's best-in-slot list or upgrade verdict, *(changed)* means the addon suggested one and the player picked another; hover the row to read it in words. A label with neither was chosen by the player (or came from an older addon). Who picks the label is the Guild Master's rule in [[Settings|Settings]] › Rules › Priority. |
| **Upgrade** | What the player's own addon says about the item for the spec of their answer: *Big upgrade +7.4% · ilvl +6*, *Small upgrade*, *No upgrade*, *Not comparable*, *Not usable*; a dot when their addon sent nothing (an older version, or the guild turned the verdicts off). **Hover the row** to see both specs' verdicts and the pieces they wear. It is a hint for the council: it is an approximation, and it never changes the proposal (see [[Rolling for Loot|Rolling-for-Loot]], "Is it an upgrade?"). Click the header to sort: big upgrades first. |
| **Roll** | The first 1-100 roll of the current round (a reroll replaces it for the tied players). |
| **Notes** | *Proposed* for the winner; *No answer yet* while the round is open; the note the player wrote in their popup (shown after the other texts); the reason a roll was set aside (a second roll, not 1-100, rolled too early, **the addon is not active**); *Upgrade ignored* or *Possible waste* when a [council flag](#council-flags) names the player. |

Sort by clicking a header. The list is ordered main-spec first, then fewest credits, then the highest roll. In a reroll the players who are not tied are dimmed.

A player who rolls without the addon is **not** counted: the roll appears with *The addon is not active* so you see it, and they cannot answer.

## Council flags

Two flags help you and the council spot the cases the guild's rules say must be raised **before** the item is awarded. They appear under the candidates, in amber, **as soon as the answers arrive** (you do not have to wait for the round to close), stay with the proposal, and the candidate they name says so in the **Notes** column.

| Flag | When | Example |
|---|---|---|
| **Upgrade ignored** | A raider with the addon **passes** on an item that is a **big upgrade for their main spec** (MS1). | *Upgrade ignored: Bryn passed on it (Big upgrade +12.0%).* |
| **Possible waste** | The **first in line** of the main-spec answers has a **small upgrade or none**, while another main-spec candidate has a **big** one, at least **twice** as large (the ratio is a guild rule). | *Possible waste: Aurel is first in line (Small upgrade +1.5%), Corin has more to gain (Big upgrade +9.0%).* |

- **They never change the winner.** The proposal is still the rules' own. If the council agrees it is a case to act on, you **Modify** the proposal with the reason *Obvious waste* (another candidate) or *Passed to game the system* (to the player who passed, at full cost); the award keeps the flag in the audit.
- **Main spec only.** Both flags read the verdict for the player's **MS1**; an off-spec answer and the off-spec verdict never raise them. "Big" uses the guild's thresholds again, so a verdict under the threshold raises nothing; an item the player cannot use never counts.
- **Before the proposal** the "first in line" follows the credits and the roll; once the proposal is written, it is the player the rules chose (and if the item went to the off-spec round, the bank or your choice, there is no "possible waste").
- **Automatic award.** When the guild awards automatically, a proposal with a council flag is **not** confirmed by itself: it waits for you.
- **Who sees them.** You always do. Besides you, the guild decides who sees the verdicts and the flags: the **council** (the preset: the rank with the *council member* permission, who then gets the read-only window even without being an officer), **all officers**, or **only the master looter**. Others see only the codes of the proposal, without names. The flags can be turned off by the guild.
- **What they cannot know.** A raider who never answers sends no verdict, so a silent player is flagged only if their addon has already sent one. The verdict is computed by the player's own addon: an approximation (see [[Upgrade Hints|Upgrade-Hints]]).

## The council: interventions and the vote

**Who is on the council.** By default, the guild ranks with the *council member* permission (officers) who are **in the raid**. The guild may instead write an **explicit list of characters** in its rules: then the list replaces the rank (still only those in the raid, unless the guild turns the presence rule off). Type `/fdcp council` to see whether you are on it. The **Loot › Council** page does the same from the window, with buttons and dialogs: see [[Council|Council]].

**What the council can do, always with a reason.** You carry out the council's decisions from your window, and each one is written in the log with its reason and your name:

| What | How | Reason |
|---|---|---|
| Fix the category or the cost | **Correct**, before the item's roll opens. Once it is open the addon refuses (*The category cannot change once the roll is open.*). | *The category or the cost was wrong*, *The council priced the item* |
| Obvious waste: another candidate | **Modify**, pick the candidate. They pay the cost of their own answer. | *Obvious waste* |
| Passed to game the system | **Modify**, pick the player who did not roll. They pay the **full cost**. | *Passed to game the system* |
| Cancel an award | `/fdcp council awards`, then `/fdcp council void <n> <reason>`. The credits come back; the award stays in the log, marked cancelled. | *mistake*, *duplicate_award*, *obvious_waste*, *passed_to_game*, *council_vote*, *legendary*, *other* |
| Correct a member's credits by hand | `/fdcp council adjust <player> <credits> <reason>` (positive adds credits, like a cost; negative removes them; at most 1000). | *mistake*, *penalty*, *bonus*, *council_vote*, *other* |

Without a reason nothing is written. Cancelling and correcting credits need the *night* permission while a night of the season is open (you, the master looter, write the council's corrections) and the *credits correction* permission outside a night (the Guild Master in the preset). Other players' addons check the same permission when the event reaches them. `/fdcp council audit` lists the last interventions of the season: modified awards (with the rules' winner), corrections before the roll, votes, cancellations and credit corrections.

**The vote.** When the guild's award mode is **council**, or the guild turns the **council vote** on, every council member votes from their own game with `/fdcp council vote <player>` once the proposal is up (a member votes only for themselves; a vote from someone who is not on the council is ignored, and a member can change their vote until it is closed). You see the votes in the strip under the proposal, for example *Council votes (open): Corin 2, Bryn 1.*, and the main button becomes **Close the vote**:

- in **council** mode you cannot confirm before closing the vote. A strict majority decides; if it names someone else, the proposal changes with the reason *Decided by the council's vote*. A tie or no votes: you decide with **Modify**;
- with the vote in the other modes the votes only inform you: you may confirm at once, close the vote to apply the majority, or modify. In **automatic** mode a vote for another player stops the automatic award and waits for you (*A council vote disagrees: the master looter decides.*);
- the votes go into the award in the log.

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
- **Rolls only from the button** (rule *Rolls count only from the popup's Roll button*, on by default; *Seconds between the Roll click and the roll*, 10 by default): a raider's click on **Roll** tells your addon about it just before the game's roll. A roll without that click is a `/roll` typed by hand: your addon waits a few seconds for the click (longer during a lockdown, which does not count), then sets it aside as *Typed by hand: only the Roll button of the popup counts*. The raider can still click afterwards. A second click or a second roll is a duplicate. Raiders with an addon older than the rule roll as before. Turn the rule off in the session rules if your guild wants typed rolls to count.
- If you `/reload` or disconnect, the session comes back as you left it, even in the middle of a reroll: type `/fdcp` to see the window again. The raid is asked again who runs the addon; while the answers come back, everyone keeps the state the session knew, so nobody is left out of the next roll. The loot window closes with a `/reload`: an item you confirm before opening the body again waits in **To deliver** and is handed over as soon as you open the body.

## Other officers

Officers who are not the master looter see the same window **read-only**: the items, the round, the proposal and its reasons, but no buttons and no credits or rolls (they stay with the master looter). Where the guild lets them see the verdicts (the council, by default) they also see who answered what, the Upgrade column and the [council flags](#council-flags). Players without the permission see their own popup instead.

## If the guild uses other modes

The guild may set the award to **automatic** (the addon confirms a clean proposal by itself after a short window, never after you intervene and never with a [council flag](#council-flags) up; the strip says *The addon confirms by itself in N s* and you can still Reject or Modify during it) or to **council** (the council votes on every proposal and you close the vote before confirming: see [The council: interventions and the vote](#the-council-interventions-and-the-vote)). Which mode is in force is a guild rule: see [[Loot Rules|Loot-Rules]].
