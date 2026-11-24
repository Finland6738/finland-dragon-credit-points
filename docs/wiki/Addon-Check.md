# Addon Check

> **Built, not yet seen in the game.** The panel and the notice work in the offline tests; how the real client delivers the messages is still to be confirmed in game. [Italiano](Addon-Check-it)

Every raider needs the addon active. FDCP checks it by itself and helps the Guild Master, the officers and the master looter chase who is missing.

## Who has the addon

When the night opens, when someone joins the raid, and whenever you ask again, the addon asks the raid and every addon answers with its version. Each member then has one of these states:

| State | Meaning |
|---|---|
| **Active** | Answered, up to date. |
| **Needs an update** | Answered with an older version: can still roll, and is asked to update. |
| **Incompatible version** | Answered with a protocol this version does not understand: cannot roll from the addon. |
| **Addon not active** | No answer within 15 seconds. "Not installed" and "disabled" look the same, so the addon says "not active". |
| **Waiting** | Offline, not asked yet, or asked a moment ago: it is checked again by itself. |

Only members with an active or outdated addon are candidates for an item.

## The panel

**Roster › Addon** is visible to anyone with the permission *see who lacks the addon and notify them* (officers by default) and to the night's master looter. It shows one row per raid member (name, state, version), the ones who need attention first, and the summary, for example **37/40 with the addon**. The same summary appears as a chip in the title bar.

| Button | What it does |
|---|---|
| **Ask again** | Asks the whole raid once more. |
| **Notify in /raid** | Writes one message in raid chat naming everyone whose addon is not active. |
| **Notify outdated** | The same for members who only need an update. |

## The notice in /raid

The message looks like this (in your language):

> [FDCP] Corin, Dara: you are missing the loot addon (Finland Dragon Credit Points). Download it from <link> before the next boss, it is needed to roll.

- If the names do not fit in one chat message (255 characters), they are split over several lines.
- The Guild Master can change the text of both notices, the download link (by default the notice just says **CurseForge**: the addon carries no web link), how often a notice may go out, and choose **whisper** instead of /raid (one whisper to each name). In the text, `{names}`, `{link}` and `{addon}` are replaced by the list, the link and the addon's name.
- At most **one notice every 5 minutes** (the Guild Master can change it), counted per night.
- Never during a boss fight: the button answers "a boss fight is in progress" and you click again after it.
- It only goes out when someone with the permission clicks: the addon never writes it by itself.
- Every notice is logged: who, when, to whom, how many lines.

## Which rolls count

Rolls are the game's own `/roll` results: the addon reads them from the system chat in your client's language and never makes one up. A roll counts only when it is:

- a **1-100** roll (`/roll 50` or `/roll 1-1000` does not count, and does not use up your turn);
- made **after the master looter opened the round** (an earlier roll is ignored);
- your **first** valid roll of that round (a second one is ignored);
- from a character **in the raid** with the **addon active**. A manual `/roll` from someone without the addon is set aside, and the master looter sees it as "discarded roll: addon not active", so nobody thinks it was lost by mistake.

During a boss fight the game may hide the chat from addons: the addon then keeps those messages and reads them when the fight ends, with the time they arrived, so a roll still counts for the round it was made in.
