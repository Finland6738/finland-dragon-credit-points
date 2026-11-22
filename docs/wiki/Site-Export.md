# Site Export

> **Built, not yet seen in the game.** The export and the script work offline, tested with a simulated client and with copies of the site's files; how the copy window behaves in the real game and how the site shows the result of a real night is still to be confirmed. [Italiano](Site-Export-it)

The guild community site's WoW Forever page reads three files. FDCP writes all three, in the site's current format, so they can go into the site's `content/games/wow-forever/` folder **without touching them**:

| File | Site tab | What FDCP writes |
|---|---|---|
| `roster.json` | Roster | Your guild's season mains. Each has name, class, main-spec, role, faction, and Raider or Trial. |
| `loot.json` | Loot | One entry per season, newest first, and one column per raid night. Each night lists the items awarded, with costs 0, 1 or 2. The site adds up the credits itself. |
| `progress.json` | Progress | The date of your guild's first kill of every boss. |

## Two guilds, two factions

Nebulah (Horde) and Nebulaa (Alliance) are two guilds in the game, so each one has its own addon data. Each guild exports only its own faction and keeps the other one's data as it is. The Guild Master can change the faction name the site uses in Settings › Site.

## How first kills are recorded

The Progress tab and `progress.json` show the date of the first kill of every boss. The addon records them; the Progress tab shows them.

- **In an official raid night**, the master looter's addon records every boss kill.
- **Outside a raid night**, the addon of an officer who may run nights records a boss's first kill when the group counts as a guild group in the game and stands in a raid of the season's pack (Molten Core, Onyxia's Lair). A later kill of the same boss adds nothing. A season must be open.
- **By hand.** An officer with the permission `progress.edit` can enter a first kill from before the addon, or the other guild's date as it appears on the site. A wrong date entered by hand can be corrected or removed. A date the addon recorded can only be replaced by an older one.

The date never moves forward: the first kill is always the oldest date. Each change is a ledger event, so it appears in the audit. The faction name on the site is Nebulah for a Horde guild and Nebulaa for an Alliance guild, unless the Guild Master writes another name in the rules.

## How an officer exports

You need the permission `export.public` (officers by default). There are two ways; the second one is recommended.

### The script (recommended)

1. **After the night**, close the game or type `/reload`. At every night close the addon has already saved the three files in its saved data. To save them without closing a night, open **History › Export › Site** and press **Save for the script**.
2. On your computer, run the script from the addon's repository against a checkout of the site:

   ```bash
   python -X utf8 tools/site_export.py --wow "<WoW folder>" --site <site folder>
   ```

   Add `--dry-run` to see what would change without writing anything. The script needs only Python 3.
3. Look at the changed files in the site folder and commit them as usual.

The script **merges**, it does not overwrite. It keeps the other faction's players and dates, the older seasons, the cover pictures, the instances still to come and every key it does not know. It never moves a first-kill date forward. If the site's files are still the example files, they are replaced and the "example data" badge goes away.

Before it writes anything the script checks the same rules the site checks when it publishes (classes, roles, every award's player in the season's roster, costs 0, 1 or 2, dates, the faction names of the site's `game.json`). If a rule fails it says which and writes **nothing**, so the live site cannot be broken by an export.

Other options: `--account NAME` when the WoW folder has several accounts, `--guild "<realm>/<guild>"` when the saved data has several guilds with an export, `--only roster,loot,progress` for some files only, `--saved FILE` to point at the saved-data file itself, and `--csv-dir DIR` to also write `roster.csv` and `awards.csv`, the two sheets of the site's Google Sheets path.

### The copy window

Open **History › Export › Site**, pick the file (**roster.json**, **loot.json**, **progress.json**) and the form, then press **Select all** and **Ctrl+C**. The game does not let an addon write files or reach the internet, so this is text to paste.

| Form | What you get | Use it when |
|---|---|---|
| **Full file** | The whole file, with only FDCP's data | The site has nothing else to keep (the first time, a single faction, no season from before the addon). **It replaces the other faction and the earlier seasons**, and the window says so. |
| **Fragment** | `roster.json`: the list of your players. `loot.json`: the current season, to put at the top of `seasons`. `progress.json`: the boss rows with your faction's key. | You edit the site's file by hand on GitHub or in a content editor. |

Above the text the window lists what the site cannot show (see below), if anything.

## What is in the files

- **roster.json**: the active (Raider) and trial (Trial) mains of your faction, with the English name of their main spec and the site's role word. Inactive members, alts and the other faction are not in it.
- **loot.json**: every season of your ledger, newest first. A season lists every main who was in its pool, even one who left. Each **closed** raid night is a column (a night still open is added when it closes), with the day and month, the English instance name and `killed/total` bosses. The rows are the awards that count today: a cancelled award is left out, a corrected one has its corrected cost, an off-spec award has the cost 0 and the words "(off-spec)" after the item.
- **Starting credits.** The site has no field for the credits a member starts with (a late joiner's average). They are written as rows "Starting credits (roster average)" in the member's first night, of 2 and 1, so the site's total matches the addon's. The words are in the guild's language.
- **progress.json**: for each boss of the raids of the season's pack, the date of your faction's first kill, or `null`. Only your faction's key is written.

## What the site cannot show

The site accepts only costs of 0, 1 and 2 and only players of the season's roster. So the export leaves out, and the window and the script tell you how many:

- awards to the guild bank, to be disenchanted or to the master looter (they have no player);
- awards to someone who is not a pool main of your faction;
- manual credit adjustments (the site cannot show a negative or fractional row);
- awards of a night that is still open;
- members who have no declared spec (the site needs one).

A cost that is not a whole number is rounded to 0, 1 or 2 and a cost over 2 is split in rows of 2 and 1. With the preset rules this never happens.

## What never leaves the addon

The exports never include:

- attendance or bench;
- notes;
- council reasons;
- who does not have the addon;
- alts;
- realms.

Corrections and voided awards are already applied, so the site's totals match the addon's.

## An option for later

The Guild Master has not yet decided whether the site's format may grow two optional fields, `start` (starting credits) and `kind` (award or adjustment), see [issue #3](https://github.com/Finland6738/finland-dragon-credit-points/issues/3). Until then they are **off**: the files use the current format only. The switch exists in the rules (`site.extended`) but is not in any window.

## Details

The exact file contents and the field mapping are in the specification [`docs/specs/site-export.md`](https://github.com/Finland6738/finland-dragon-credit-points/blob/main/docs/specs/site-export.md) (Italian).

Related: [[Export|Export]] · [[Interface Tour|Interface-Tour]]
