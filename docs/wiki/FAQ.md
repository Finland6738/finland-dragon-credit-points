# FAQ

> **Built, not yet seen in the game.** The answers follow the addon's code and its offline tests. [Italiano](FAQ-it)

## Installing and starting

**Where does the addon go?** In `<WoW folder>/_forever_/Interface/AddOns/FinlandDragonCreditPoints`. See [[Installation|Installation]].

**I typed `/fdcp` and nothing opens.** Check that the addon is enabled in the AddOns list and that the game is WoW: Forever (outside it the addon warns you once). Then `/reload`. If it still fails, make a [[bug report|Reporting-Bugs]].

**Can I change the language?** Yes: `/fdcp language itIT` or `enUS` (`auto` follows the game), then `/reload`. The guild's announcements in `/raid` always use the guild's language, whatever yours is.

## Rolling

**Why can I not roll?** Only a raider whose addon is active and compatible can roll. Open **Loot** as an officer or ask one: [[Addon Check|Addon-Check]] shows who is missing, needs an update or has an incompatible version.

**I typed `/roll` and it did not count.** A roll counts only when it comes from the popup's **Roll** button, once per item (the Guild Master can turn that rule off). See [[Rolling for Loot|Rolling-for-Loot]].

**I closed the popup by mistake.** If your window is closed, open it again with the item's row in **Loot** or reload: the session comes back by itself, even after a `/reload`.

**What do the upgrade colours mean?** The badge compares the item with the gear you wore during the boss fight: [[Upgrade Hints|Upgrade-Hints]].

**What is the +2 penalty?** Cheating the roll (swapping gear after the fight, passing on a big upgrade and so on) costs +2 credits once the master looter or the council confirms it. [[Loot Rules|Loot-Rules]], "Roll cheating".

## Credits

**Why does fewer credits mean more priority?** Credits are what you have already spent: the member with the fewest wins the roll before the others; ties are settled by the highest roll. [[Loot Rules|Loot-Rules]].

**My credits look different from an officer's.** Members get the credits table from an officer's addon (after each change and at login). Wait a moment or `/reload`; the table of someone who is not an officer is ignored. [[Credits Table|Credits]].

**Who can change credits?** Only the council, with a reason, and every correction is in the season's audit ([[Council|Council]], [[History|History]]).

**I joined late. How many credits do I start with?** The fewest of the roster. A missed night can cost +1 credit, which an officer confirms ([[Loot Rules|Loot-Rules]], "Absences").

## Officers

**Two officers ran different nights.** The officers' addons sync one ledger between them on the officer channel; give it a few minutes. `/fdcp debug` has a **Sync** line.

**How do I back up the data?** **History › Backup** copies the whole ledger as a string and restores it without removing any event: [[Backup and Seasons|Backup-and-Seasons]].

**How do I update the community site?** [[Site Export|Site-Export]].

## Other

**Does the addon make web requests?** No. It cannot, and it never sends anything outside the game: see [[Privacy and Data|Privacy-and-Data]].

**Where do I report a problem?** [[Reporting Bugs|Reporting-Bugs]].
