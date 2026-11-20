# Site Export

> **Planned, not built yet.** This page describes how officers will update the community site from the addon. The feature arrives with the history and export milestone. [Italiano](Site-Export-it)

The guild community site's WoW Forever page reads three files. FDCP writes all three, in the site's current format, so they can go into the site's `content/games/wow-forever/` folder **unchanged**:

| File | Site tab | What FDCP writes |
|---|---|---|
| `roster.json` | Roster | Your guild's season mains. Each has name, class, main-spec, role, faction, and Raider or Trial. |
| `loot.json` | Loot | One entry per season, newest first, and one column per raid night. Each night lists the items awarded, with costs 0, 1 or 2. The site adds up the credits itself. |
| `progress.json` | Progress | The date of your guild's first kill of every boss. |

## Two guilds, two factions

Nebulah (Horde) and Nebulaa (Alliance) are two guilds in the game, so each one has its own addon data. Each guild exports only its own faction and keeps the other one's data as it is. The Guild Master can change the faction name the site uses in Settings › Site.

## How an officer exports

- **Copy window (in game).** Open History › Export and choose a file. The text is already selected: press Ctrl+C and paste it on the site. "Full file" replaces the whole file. "Fragment" gives you only your part, to paste by hand.
- **Script (recommended).** After the night, close the game or type `/reload`, then run the following on your computer. It merges your guild's data into the site's files and keeps everything else (the other faction, older seasons, cover pictures). Then commit the three files to the site as usual.

  ```bash
  python -X utf8 tools/site_export.py --wow "<WoW folder>" --site <site folder>
  ```

## What never leaves the addon

The exports never include:

- attendance or bench;
- notes;
- council reasons;
- who does not have the addon;
- alts;
- realms.

Corrections and voided awards are already applied, so the site's totals match the addon's.

## Details

The exact file contents and the field mapping are in the specification [`docs/specs/site-export.md`](https://github.com/Finland6738/finland-dragon-credit-points/blob/main/docs/specs/site-export.md) (Italian).

Related: [[Interface Tour|Interface-Tour]]
