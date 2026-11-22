# Rolling for Loot

> **Built, not yet seen in the game.** The popup works in the offline tests with a simulated raid; how it looks in a real raid, the item tooltip with the comparison, the roll from the buttons and the upgrade badge on real raid items are still to be confirmed. [Italiano](Rolling-for-Loot-it)

This page is for **every raider**. When the master looter opens the roll of an item, the addon shows you a small window, the **item popup**. You choose with **three buttons**, and it goes away when the round closes. You never have to type `/roll` yourself.

You need the addon active: only raiders with the addon can answer and roll, and a `/roll` typed by a player without it is set aside (see [[Addon Check|Addon-Check]]).

## The popup

![Item popup](../specs/mockups/fdcp-roll-popup.webp)

From top to bottom:

- **The title line.** *ROLL OPEN · boss name* (or *REROLL*, or *FREE ROLL*, see below), and on the right the **timer** in minutes and seconds. It turns amber in the last five seconds and says *Paused* while the master looter pauses. The small cross hides the card for this round.
- **The item.** Its icon and name in the colour of its quality, and under it the slot, the kind (cloth, plate, one-handed sword...) and the item level. **Hover the icon or the name** to see the game's own tooltip for the item, with the comparison with what you wear.
- **The cost chip**, for example *WEAPON · 2 CREDITS*: the category the guild's table gave the item and what you pay if you win it with the answer you have chosen (before you answer, the full cost). *COUNCIL* means the cost is set by the council. Next to it, when this client knows the guild's credits table, **your credits and your estimated place in the queue**: *Your credits 2 · queue ~3*. The place is "1 + the raid members with fewer credits"; it is an estimate, because a tie is decided by the roll.
- **The upgrade badge**, for example *Medium upgrade · ilvl +13*: computed by your addon, see [Is it an upgrade?](#is-it-an-upgrade) below.
- **The timer bar**, which empties as the time runs out, and **the line of help**.
- **Three buttons: Pass, Roll Main-spec, Roll Off-spec.** That is all you choose.

The popup is a window of its own: **drag it by any card** to move it, and drag the thin handle on its right edge to make it wider. The place and the width are remembered for each character.

## The three buttons

- **Roll Main-spec** sends your answer *main-spec* **and rolls in the same click**: the addon tells the master looter "this player clicked", then asks the game for `/roll 1-100`. The roll is the game's and nobody can choose it. The button then says *Rolled* and every button is locked: you roll **once** per round, and after you roll your answer cannot change.
- **Roll Off-spec** sends your answer *off-spec*. Off-spec rolls only when nobody asks for the item for their main spec, so in the first round the click **only sends the answer** and the help line says *You roll only if nobody asks for the item before you: press the same button when your turn comes*. If the off-spec round opens, a new popup appears and **Roll Off-spec** rolls.
- **Pass** sends a pass and rolls nothing. Until you roll you may still change your mind and press a roll button.

If you do not answer at all, the rules treat it as a pass. There is **no label and no note** any more: the addon tells the master looter how much of an upgrade the item is for you.

## Is it an upgrade?

The badge under the cost chip tells you how the item compares with the piece you **wore during the boss fight** in its slot. Your own addon computes it; nobody has to ask you in chat, and it **never changes who wins**.

| You see | It means |
|---|---|
| **Major upgrade** (green) | You wear a **green or lower** piece there, or **nothing** (*Major upgrade · empty slot*). |
| **Medium upgrade** | You wear a **blue** piece there, or a **purple of an older season**. |
| **Minor upgrade** | You wear a **purple of this season** there. |
| **No upgrade** | The item is worse than what you wear (a lower item level), or the same level with nothing better. |
| **Not comparable** | The addon cannot compare it: a token, an off-hand while you wear a two-hander, or an item the game has not loaded yet. |
| **Not usable** (amber) | Your class cannot use it: armour or weapon type, dual wield, an item for other classes or for another specialization. |

The badge always shows the **item level difference** too: *Medium upgrade · ilvl +13*. Hover the badge to see both your specs, the pieces it was compared with, whether it used the gear of the fight, and the rule. Rings and trinkets are compared with the worse of your two; a two-hander with your main hand plus your off hand. The full rule is on [[Upgrade Hints|Upgrade-Hints]].

**An item you cannot use.** When the addon is sure that no spec of yours can use the item, **Pass is preselected** and the help line says so. **Nothing is sent by itself**: not answering counts as a pass anyway. If you disagree, press a roll button; pressing Pass sends the pass. The Guild Master can turn the preselection off.

**What the master looter gets.** Every answer you send, a pass included, carries the badge and the pieces you wore to the master looter (the *Upgrade* column of their table). Besides the master looter, only the council sees it (the guild may choose all officers, or the master looter alone). A **pass on a major upgrade for your main spec** is pointed out to them (*Upgrade ignored*), and so is a main-spec item that would go to someone with a minor upgrade while you have a major one (*Possible waste*): see the [[Master Looter Guide|Master-Looter-Guide]], "Council flags".

## How a roll goes

1. **Choose.** Press **Roll Main-spec**, **Roll Off-spec** or **Pass**. A main-spec answer rolls at once.
2. **Wait.** The round closes by itself on its timer, or when everyone has answered and rolled. The popup closes with it, and the master looter's window shows the proposal.

### Roll only with the buttons

By default the guild counts **only rolls made with the popup's roll buttons**, once per item. A `/roll` you type by hand does **not** count, even with the addon: the master looter sees it set aside as *Typed by hand: only the Roll button of the popup counts*, and your own addon tells you in the chat: *Use the roll buttons of the loot popup: rolls typed by hand do not count.* A typed roll does not use up your turn: press the roll button afterwards and that roll counts. A second roll after your counted one is a duplicate and is not counted. Rerolls among tied players use the button too.

Why: the game cannot tell a typed `/roll` from the button's roll, so the button sends a small "I clicked" message just before the roll. It carries no number: the roll is still the game's own. After a boss the message may wait a few seconds behind the game's chat lockdown; the master looter's addon waits for it. The Guild Master can turn the rule off (*Rolls count only from the popup's Roll button*, in the rules of the session), and then a typed `/roll 1-100` counts as before.

### Who rolls when

- **Main-spec** answers roll in the first round. If nobody answers main-spec, the **off-spec round** opens by itself: if you answered Off-spec, a new popup appears and **Roll Off-spec** rolls; if you answered Main-spec or Pass you see nothing.
- If two players are **tied** on credits and roll, a **reroll** opens among them only: the popup says *REROLL*, only the tied see it, and the button of your answer rolls.
- If nobody wanted the item and the guild uses a **free roll**, the popup says *FREE ROLL* and anyone may roll with either roll button.

The line of help under the bar tells you what to do now: *Pass, or roll for main-spec or off-spec: one click answers and rolls*; *The game makes the roll: /roll 1-100*; *You roll only if nobody asks for the item before you*; *You are tied: roll again*; *Rolled. The master looter has your roll*.

## If something goes wrong

- *Your answer could not be sent.* The addon could not hand your answer to the raid channel, and nothing was rolled; press the button again.
- *The game did not let the addon roll: type /roll 1-100 now.* Your answer went, but the client refused the roll from the button; press the button again or type the command yourself straight away: your click already told the master looter, so a roll typed within a few seconds (the guild's window, 10 seconds by default) counts the same.
- **You reloaded the interface or logged in during a roll.** The master looter's addon sends your popup back with your answer as it was. The gear of the boss fight is kept across the reload.
- **You joined the raid after the roll opened.** You see the popup, but the raid of an item is fixed when its roll opens: your answer is not counted for that item, only from the next one.

## What the master looter sees

Your answer and your upgrade badge, next to your credits, in the candidates table of the [[Master Looter Guide|Master-Looter-Guide]]. They travel on the raid's addon channel like every message of the loot session; other players' addons do not show them. Nobody can answer in your name: the master looter's addon takes the player from the sender of the message, never from what the message says.
