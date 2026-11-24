# Raid Readiness

> **Built, not yet seen in the game.** The tab, the notice and the whispers work in the offline tests; how the real client answers (the item and buff ids, the whispers of a full raid) is still to be confirmed in game. [Italiano](Raid-Readiness-it)

Before a pull, the master looter wants to know who is not ready: a missing enchant, no flask, no potions, no water for the healers, no ammunition for the hunters. FDCP asks every raider's own addon and shows the answers in one table, and a button tells the raid what is lacking.

## Who sees it

**Roster › Readiness** is there for the night's master looter and for anyone with the permission *see who lacks the addon and notify them* (officers by default), the same people who use the [[Addon Check|Addon-Check]]. For everybody else the sub-tab is not shown. Outside a raid it says so and the buttons are off.

## How it works

- **Check the raid** asks every raider's addon. Each addon looks at **its own** character (which gear slots have an enchant, which food, flask and elixir buffs are active, how many of each consumable are in the bags) and whispers a small answer back to you. Nothing else from the bags is read or sent. The check is never made in combat or during a boss: an answer waits for the end of the fight.
- You can ask once every 30 seconds; the button shows the seconds left.
- A raider without the addon, offline, or with an older version, is **Unknown**, and the row says why.
- Nothing is saved. A new check, leaving the raid or `/reload` clears the table. It never enters the ledger, the credits, the exports or the API for other addons.

## The table

One row per raid member, the ones who need attention first:

| Column | Meaning |
|---|---|
| **Name** | In the class colour. |
| **Status** | **OK**, **Low** (some, but fewer than required), **Missing**, or **Unknown** (no answer, or a value the game would not show). |
| **Missing enchants** | The slots without an enchant, by name (wrist, hands, back...). A row without an answer says why: not asked yet, waiting for an answer, no addon, offline, no answer. |
| Buff food, Food, Flask, Potions, Water, Ammo, Pet food | **OK**, *have/need* (amber when low, red when none), **?** when it could not be read, **-** when this raider is not asked for it (water is for mana users, ammunition and pet food for hunters). |

The summary above the table reads, for example, **31 ok · 5 warn · 3 missing · 1 unknown** and **36/40 answered**. The table redraws as the answers arrive.

A flask or an elixir counts if one is **active**, even with none in the bags; the same for a buff food. A value the addon cannot read is shown as unknown and never guessed.

## Notify the raid

**Notify the raid** asks you to confirm (*Write N lines in /raid and whisper M players?*) and then writes:

1. A short summary in `/raid`, for example `[FDCP] Readiness: 2 missing, 1 low. Check your whispers.`, followed by the names grouped by what they lack (`[FDCP] potions: Aurel, Corin`). Long lists are split over several lines of at most 255 characters, never cutting a name.
2. **One whisper to each raider** whose status is Missing or Low, saying exactly what and where: `[FDCP] Missing: enchant wrist, hands; potions 0/2; flask 0/1`. Raiders who are Unknown get no whisper. The lines are in **your** language.

The rules of the button:

- It only leaves **from your click**, never by itself.
- Never during a boss or while the game blocks chat: the notice **waits** and leaves when the fight ends (it is dropped after 10 minutes, because the table would be stale).
- The messages leave one by one, less than a second apart.
- At most **one notice every 5 minutes** (the Guild Master can change it in Settings › Rules › Messages in /raid, *Minutes between two notices*); the button shows the seconds left.
- Every notice is written to your character's log (when, how many lines and whispers, whether it had to wait).

## The requirements

The Guild Master decides what is required, in **Settings › Rules › Raid readiness**:

- the switch of the whole check;
- one switch per slot that needs an enchant (head, shoulder, chest, legs, feet, wrist, hands, back, main hand, off hand, ranged: the ranged slot is only asked of hunters);
- the **minimum** of each consumable (0 = not asked): buff food, food, flask or elixir, potions, water, ammunition, pet food;
- whether water is asked only of the classes with mana, and ammunition and pet food only of hunters;
- the wording of the `/raid` line and of the whisper (empty = the default of the language; placeholders `{missing} {low} {unknown} {total}` in the `/raid` line, `{list} {name}` in a whisper).

The defaults: chest, feet, wrist, hands, back and the weapon slots enchanted; 1 buff food, 5 food, 2 potions and 1 flask or elixir for everybody; 10 water for the classes with mana; 1000 ammunition and 10 pet food for hunters. Head, shoulder and legs are off.

> **For the Guild Master:** changing these requirements writes a new version of the rules that an addon older than this one cannot read. Ask every officer to update first. While the requirements are the default nothing changes for them.

See also [[Settings|Settings]], [[Addon Check|Addon-Check]] and [[Privacy and Data|Privacy-and-Data]].
