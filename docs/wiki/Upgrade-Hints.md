# Upgrade Hints

> **Built, not yet seen in the game.** Everything here works in the offline tests; whether the game gives the quality and the item level of worn pieces as expected, and the gear snapshot at the start of a boss fight, are still to be confirmed. [Italiano](Upgrade-Hints-it)

The popup shows an **upgrade badge** for every item up for roll ([[Rolling for Loot|Rolling-for-Loot]], "Is it an upgrade?"). The addon computes it by itself, the same way for everybody: there is nothing to set up, no stat weights to import and no list to keep. It **informs** you, the master looter and the council; it **never changes who wins**.

## The rule

The item is compared with the piece you wore **in that slot during the boss fight**:

| You wore | A purple item of this season is |
|---|---|
| a **purple of this season** | **Minor upgrade** |
| a **blue**, or a **purple of an older season** | **Medium upgrade** |
| a **green or lower**, or **nothing** | **Major upgrade** |

- The badge always shows the **item level difference**: *Minor upgrade · ilvl +13*. An empty slot says *Major upgrade · empty slot*.
- An item **worse** than yours (a lower item level, or the same level with nothing better) is **No upgrade**. An item your class cannot use is **Not usable**, and Pass is preselected for you.
- A legendary counts like a purple. A blue item is read the same way, one step down: over a green it is a medium upgrade, over a blue a minor one.
- **Rings and trinkets** are compared with the worse of your two (an empty one first, then the lower colour, then the lower item level). A **two-hander** is compared with your main hand plus your off hand (the lower colour of the two, their average item level). A one-hander is compared with the worse hand only when you use two weapons.

## New raids: the season's item-level band

When a new season brings new raids, last season's purples are no longer what they were. Each season has an **item-level band**, the item levels of its epic items, that the Guild Master sets in **Settings › Season** ([[Seasons|Seasons]]). A purple you wear **below the band** counts as a purple of an older season, one step down, like a blue: a new purple over it is a **medium** upgrade, not a minor one. Without a band every purple counts as this season's.

## The gear of the fight

The addon takes a snapshot of your gear when the boss fight **starts** (if you reloaded during the fight, when it ends) and compares the loot of that boss with it, for up to an hour. Taking a piece off after the kill does not make an item look like a bigger upgrade. Outside a boss fight (for example a test roll) it compares with what you wear now; the badge's tooltip says which.

## Removed

Earlier versions had personal stat weights with a Pawn-like import (`/fdcp weights`), a best-in-slot wishlist (`/fdcp wish`), and labels and a note on the popup. The Guild Master decided to replace them with this badge: they are gone, and the commands no longer exist.

## Limits

- The badge reads **colour and item level**, not stats: two purples of this season with different stats for your spec are both a minor upgrade if the new one has a higher item level.
- The item on offer is read from its id, so its item level is the base one; the pieces you wear are read from their own links, with their upgrades.
- A token for another class shows as *not comparable*, not *not usable*.
- The badge comes from your own addon: a modified client could lie about it. It informs the council, which decides.
