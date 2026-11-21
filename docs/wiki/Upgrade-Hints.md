# Upgrade Hints

> **Built, not yet seen in the game.** Everything here works in the offline tests; how it looks and feels in a real raid is still to be confirmed. [Italiano](Upgrade-Hints-it)

The popup tells you whether an item is an upgrade ([[Rolling for Loot|Rolling-for-Loot]], "Is it an upgrade?"). Two **personal, optional** settings tune that hint for you. Both belong to your character only: they are never sent to the guild, never written in the ledger, and they never change who wins an item.

## Your own stat weights

The hint weighs each stat of the item for your specialization. The addon ships default weights for every spec; if you prefer your own, import them.

**Import.** `/fdcp weights import <spec> <string>`

- `<spec>` is a specialization id (for example `72`), or `ms` / `os` for your declared main-spec and off-spec.
- `<string>` is a list of `Stat=weight` pairs, optionally wrapped in the Pawn-like header: `( Pawn: v1: "My Fury": Strength=1, CritRating=0.85, HasteRating=0.6 )`. The bare form `Strength=1, CritRating=0.85` works too, in any letter case, and so do the addon's short codes (`STR=1, CRIT=0.85`).
- The stats the addon can weigh are: Strength, Agility, Stamina, Intellect, Spirit, Ap, Rap, SpellDamage, Healing, CritRating, HitRating, HasteRating, ExpertiseRating, ArmorPenetration, MasteryRating, Versatility, Mp5, Dps, Armor, DefenseRating, DodgeRating, ParryRating, BlockRating, BlockValue. Other names in the string (sockets, gems) are listed as ignored; the import is refused only when none is known.
- An import **replaces the whole row** of that spec and **turns your personal weights on**.

**A string that is not valid is refused with a message and changes nothing.** The addon names the piece at fault: an empty string, a string that is too long (over 2000 characters), a piece that is not `Stat=number`, a number that is not a plain decimal (no `0x10`, `1e3`, `inf`) or is beyond ±1000, or no stat the addon knows.

| Command | What it does |
|---|---|
| `/fdcp weights` | Says whether personal weights are on, for which specs you set them, and the usage. |
| `/fdcp weights show <spec>` | Prints the weights of that spec as a string: yours if you set them, else the defaults. You can share it. |
| `/fdcp weights off` / `on` | Goes back to the default weights / uses yours again. Nothing is lost. |
| `/fdcp weights reset <spec>` or `reset all` | Removes your weights for that spec, or for all. |

When your own weights are used, the tooltip of the verdict line says so, and the verdict that your answer carries to the master looter is the one computed with them. Default weights stay the rule until you import something. The Guild Master has not been asked to approve personal weights; the hint only informs, and the council decides.

## Your best-in-slot list

Mark the pieces you consider best in slot, and the popup reminds you when one is up for grabs.

| Command | What it does |
|---|---|
| `/fdcp wish add <item> ...` | Adds one or more items: shift-click an item link into the line, or type the item id. |
| `/fdcp wish remove <item> ...` | Removes them. |
| `/fdcp wish` or `/fdcp wish list` | Lists your items. |
| `/fdcp wish clear` | Empties the list. |

An item on your list shows an **On your BiS list** badge above the verdict lines (hover it for a reminder that only you see it). The list is saved per character, survives `/reload`, holds up to 300 items and is only a reminder: it sends nothing and changes nothing for anyone else. To tell the council that an answer is for a best-in-slot piece, use the **BiS** label of the popup ([[Rolling for Loot|Rolling-for-Loot]]).

## Not covered

- There are **no guild-wide BiS lists** and no shared weights: the question of whether the guild wants them is still open with the Guild Master.
- The hint remains an approximation (procs, use effects, set bonuses and caps are not counted), whatever the weights.
