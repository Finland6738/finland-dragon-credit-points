# Rolling for Loot

> **Built, not yet seen in the game.** The popup works in the offline tests with a simulated raid; how it looks in a real raid, the item tooltip with the comparison, the roll from the button and the upgrade verdicts on real raid items are still to be confirmed. [Italiano](Rolling-for-Loot-it)

This page is for **every raider**. When the master looter opens the roll of an item, the addon shows you a small window, the **item popup**. You answer in it, you roll from it, and it goes away when the round closes. You never have to type `/roll` yourself.

You need the addon active: only raiders with the addon can answer and roll, and a `/roll` typed by a player without it is set aside (see [[Addon Check|Addon-Check]]).

## The popup

![Item popup](../specs/mockups/fdcp-roll-popup.webp)

From top to bottom:

- **The title line.** *ROLL OPEN · boss name* (or *REROLL*, or *FREE ROLL*, see below), and on the right the **timer** in minutes and seconds. It turns amber in the last five seconds and says *Paused* while the master looter pauses. The small cross hides the card for this round.
- **The item.** Its icon and name in the colour of its quality, and under it the slot, the kind (cloth, plate, one-handed sword...) and the item level. **Hover the icon or the name** to see the game's own tooltip for the item, with the comparison with what you wear.
- **The cost chip**, for example *WEAPON · 2 CREDITS*: the category the guild's table gave the item and what you pay if you win it with the answer you have chosen (before you answer, the full cost). *COUNCIL* means the cost is set by the council. Next to it, when this client knows the guild's credits table, **your credits and your estimated place in the queue**: *Your credits 2 · queue ~3*. The place is "1 + the raid members with fewer credits"; it is an estimate, because a tie is decided by the roll.
- **The upgrade verdict**, one line for each of your specs: *Main-spec · Big upgrade +7.4% · ilvl +6*. See [Is it an upgrade?](#is-it-an-upgrade) below.
- **Your answer:** **Main-spec**, **Off-spec** or **Pass**. Click one and it is sent at once. You can change your mind until you roll.
- **A label, optional**, for a main-spec answer: **BiS**, **Big upgrade**, **Small upgrade** or **Situational**. Click one to set it, click it again to clear it. It only informs the master looter and the council; it never changes who wins. If you click a label before answering, it answers main-spec for you. Off-spec and Pass carry no label.
- **A note, optional.** Up to 80 characters (a few words fewer if you use accents). It is sent when you leave the box, press Enter, or press **Roll**.
- **The timer bar**, which empties as the time runs out.
- **The line of help** and the **Roll** button.

The popup is a window of its own: **drag it by any card** to move it, and drag the thin handle on its right edge to make it wider. The place and the width are remembered for each character.

## Is it an upgrade?

Under the cost chip the popup tells you how the item compares with what you wear, **once for your main-spec and once for your off-spec** (the specs you declared to the guild; if you declared none, the spec you play now counts as the main-spec and there is no off-spec line). It is a hint for you, computed by **your own addon** with your own gear: nobody has to ask you in chat.

| You see | It means |
|---|---|
| **Big upgrade** (green) | At least +5% on the stats of that spec (the guild can change the threshold). |
| **Small upgrade** | Better, but by less than that. |
| **No upgrade** | Not better than what you wear in that slot, or equal. |
| **Not comparable** | The addon cannot compare it: a token, a trinket with a use effect, a weapon that does not fit what you wear. |
| **Not usable** (amber) | Your class cannot use it: armour or weapon type, dual wield, an item for other classes or for another specialization. |

After the verdict come the percentage (`+7.4%`, the difference of the weighted stats) and the item level difference (`ilvl +6`). **An empty slot is always a big upgrade**, with no percentage. **Hover the line** to see why, what the comparison was made on (the stats of your spec, or the item level only when the game gives no stats), the pieces you wear that it was compared with, and a reminder that the hint is an approximation.

How it is worked out: the item is compared with the piece you wear in its slot (rings and trinkets with the worse of the two, a two-hander with your main hand plus your off hand, a one-hander with the worse hand only when you use two weapons). Each stat has a weight for your spec; the score is the sum of weight × value, and the upgrade is `(new − worn) / worn`. The weights are the addon's defaults for each specialization.

**An item you cannot use.** When the addon is sure that no spec of yours can use the item, **Pass is preselected** and the help line says so. **Nothing is sent by itself**: not answering counts as a pass anyway. If you disagree, pick another answer; clicking Pass sends it. The Guild Master can turn the preselection off.

**What the master looter gets.** Every answer you send, a pass included, carries the verdicts and the pieces you wear to the master looter (the *Upgrade* column of their table). It informs the council; it never changes who wins.

### The limits of the hint

- It is an **approximation**: procs, use effects, set bonuses and stat caps are not counted, and the default weights are not a guide to the best item for your build.
- The comparison starts from the **item itself**: its item level and stats are those of the base item, not of a variant with bonuses.
- A **token** for another class is shown as *not comparable*, not as *not usable*; a trinket with a use effect that you wear may be treated as the one to replace.
- If the game does not give an item's stats, the comparison falls back to the **item level only**, and the tooltip says so.
- Whether Forever gives the stats of raid items as the addon expects is still to be checked in the game.

The guild's thresholds (what counts as big, the item-level-only mode, the preselection, and a switch to turn the verdicts off) are the **`upgrade` section of the rules**, set by the Guild Master with the rest of the rules ([[Loot Rules|Loot-Rules]]).

## How a roll goes

1. **Answer.** Pick Main-spec, Off-spec or Pass (and a label or a note if you want).
2. **Roll.** Press **Roll**: the addon asks the game for `/roll 1-100`, exactly as if you had typed it. The roll is the game's and nobody can choose it. The button then says *Rolled*, and your answer is locked: after you roll you can no longer change it. You roll **once** per round; a second roll is not counted.
3. **Wait.** The round closes by itself on its timer, or when everyone has answered and rolled. The popup closes with it, and the master looter's window shows the proposal.

**Pass** needs no roll. If you do not answer at all, the rules treat it as a pass.

### Who rolls when

- **Main-spec** answers roll in the first round. If nobody answers main-spec, the **off-spec round** opens by itself: if you answered Off-spec, a new popup appears with just **Roll**; if you answered Main-spec or Pass you see nothing.
- If two players are **tied** on credits and roll, a **reroll** opens among them only: the popup says *REROLL* and only the tied see it.
- If nobody wanted the item and the guild uses a **free roll**, the popup says *FREE ROLL* and anyone may roll.

The line of help under the bar tells you what to do now: *Choose your response, then roll*; *The game makes the roll: /roll 1-100*; *You roll only if nobody asks for the item before you* (you answered a lower tier); *You are tied: roll again*; *Rolled. The master looter has your roll*.

## If something goes wrong

- *Your answer could not be sent.* The addon could not hand your answer to the raid channel; click your answer again.
- *The game did not let the addon roll: type /roll 1-100.* The client refused the roll from the button; type the command yourself, it counts the same.
- **You reloaded the interface or logged in during a roll.** The master looter's addon sends your popup back with your answer, label and note as they were.
- **You joined the raid after the roll opened.** You see the popup, but the raid of an item is fixed when its roll opens: your answer is not counted for that item, only from the next one.

## What the master looter sees

Your answer, label and note, next to your credits, in the candidates table of the [[Master Looter Guide|Master-Looter-Guide]]. They travel on the raid's addon channel like every message of the loot session; other players' addons do not show them. Nobody can answer in your name: the master looter's addon takes the player from the sender of the message, never from what the message says.

The upgrade verdicts you saw in your popup go with your answer too (see [Is it an upgrade?](#is-it-an-upgrade)); the master looter sees them in the *Upgrade* column of the table.
