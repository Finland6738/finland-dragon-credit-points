# Loot Rules

> **In development.** This page describes the rules the addon's engine already follows (written and tested offline; nothing has run in the game yet). The windows that use them arrive in later versions. [Italiano](Loot-Rules-it)

The addon does the arithmetic, the master looter decides. These are the guild's rules ("Patto" preset) as the engine applies them. Every value below can be changed by the Guild Master in the rules, except where it says "fixed".

## Credits

- Credits are **never stored**: they are computed from the ledger, the list of everything that happened (awards, corrections, new members). A correction is a new entry, never an erasure.
- A season starts everyone at **0 credits**. A season is a pack of raids (10, 20 and 40 players share one credit table, Normal and Veteran too).
- **Only mains** earn and spend credits. An alt is linked to its main and uses the main's credits.
- Fewer credits means a better position: **the player with the fewest credits wins**, and the roll only breaks ties.
- A newly arrived member does not start at 0 in the middle of a season: they start at the **average of the roster's credits, rounded down**, so they neither jump the queue nor sit at the bottom. The number is written down once and stays stable.

## What an item costs

The cost is the first of these that answers:

1. a cost or category the council fixed for that item for the season;
2. the table of category by quality;
3. the response multiplier: main-spec x 1, off-spec x 0.

| Category | Cost (blue and purple) |
|---|---|
| Weapon, trinket, quest item or token | 2 |
| Everything else (armor, jewelry, shield, off-hand) | 1 |
| Recipes, mounts, cosmetics | 0 |
| Orange (legendary) | decided by the council |

Items below the group's loot threshold (green, normally) are not tracked and do not enter a session. The cost is announced **before** the roll and cannot be changed once the roll is open.

## Main-spec and off-spec

- **Main-spec (MS)**: you need it for your main spec. It is asked first and costs the full price.
- **Off-spec (OS)**: asked **only if nobody answered main-spec**. It costs **0 credits**.
- **Pass**: you do not roll.
- Transmog is available as a third tier, switched off in the preset.
- Only a `/roll` of **1-100**, **the first one of the round**, made by a character in the raid **with the addon active**, counts. Anything else is set aside and shown to the master looter with its reason.
- Whoever does not have the addon cannot answer or win (the master looter is told before the first roll).

## Ties and rerolls

1. Fewest credits wins.
2. Same credits: the **highest roll** wins.
3. Same credits and same roll: a **reroll among the tied only**, repeated until one is left. Players outside the tie who roll again are ignored. After five rerolls in a row the master looter decides.

## Bind-on-equip items

A BoE is rolled like any item. If **nobody answers main-spec**, it goes to the **guild bank** (a character chosen in the rules), not to the off-spec tier. The rules can send it to off-spec, disenchant or a free roll instead.

## Legendaries

A legendary is **not rolled**: the council picks who builds the legendary project, and every piece of the chain goes to them at **2 credits each**. The rules can switch to a council vote, a normal roll or a queue decided at the start of the season.

## What the master looter and the council may change

The addon prepares each result: who, how many credits and why, in words. The master looter then:

- **confirms**: the credits are charged and the result is announced;
- **rejects**: nothing is charged and the item goes back into the session (reopen the roll, next tier, bank or disenchant);
- **modifies**: a different winner or cost, always **with a reason** chosen from the list below. The addon shows how it differs from the rule ("out of line") and the event is marked as an intervention in the audit.

The council (guild officers in the raid) can, always with a reason that goes in the log: fix a category or cost **before** the roll opens; give an item to another candidate in a case of **obvious waste**; give it to someone who **did not roll but passed to game the system**, at full cost; assign a legendary; cancel an award; correct a member's credits by hand. Who counts as master looter, council or officer comes from the **guild ranks**, and only the **Guild Master** can change what each rank may do and the rules themselves.

## The three examples of the regulation

Aurel, Bryn and Corin all answer main-spec on a blue ring, a shoulder and a cloak. These are the cases the engine's tests run.

**The ring: same credits, the higher roll wins.** All three have 0 credits. Aurel rolls 45, Bryn 76, Corin 12. **Bryn** wins, pays 1 credit. The proposal says: *Main-spec: it is asked first, and the cost is paid. Same credits as the others, highest roll.*

**The shoulder: fewer credits win, the roll does not count.** Aurel has 0 credits, Bryn 2, Corin 3. They roll 34, 90 and 99. **Aurel** wins with the lowest roll. The proposal says: *Main-spec: it is asked first, and the cost is paid. Fewest credits: the roll did not matter.*

**The cloak: a tie, so a reroll among the tied.** All three have 1 credit. Aurel rolls 40, Bryn and Corin both 88. Only **Bryn and Corin** roll again. Aurel rolls again too, but he is not part of the tie, so that roll is discarded (*Not part of this round*). Bryn rolls 20, Corin 61: **Corin** wins. The proposal says: *Main-spec: it is asked first, and the cost is paid. Tied on credits and roll, won the reroll among the tied.* with the flag *Some rolls were discarded: check the list.*

## Words in the game

The engine never writes sentences: it records short codes, and the addon turns them into the sentences below in your language, so the proposal, the log and this manual say the same thing. The code is shown in the audit next to the sentence.

### Why a player won (reasons)

| Code | Sentence |
|---|---|
| `MAIN_SPEC_TIER` | Main-spec: it is asked first, and the cost is paid. |
| `OFFSPEC_TIER` | Off-spec: nobody needed it as main-spec, and it costs 0 credits. |
| `TRANSMOG_TIER` | Transmog: nobody needed it for their spec, and it costs 0 credits. |
| `ONLY_CANDIDATE` | The only one who could roll. |
| `LOWER_CREDITS` | Fewest credits: the roll did not matter. |
| `LOWER_CREDITS_PER_NIGHT` | Fewest credits per night played: the roll did not matter. |
| `HIGHER_ROLL` | Same credits as the others, highest roll. |
| `REROLL_WON` | Tied on credits and roll, won the reroll among the tied. |
| `BOE_BANK` | Bind-on-equip nobody asked for as main-spec: it goes to the guild bank. |
| `FALLBACK_ML` | Nobody could roll: the master looter decides. |
| `FALLBACK_DISENCHANT` | Nobody could roll: the item is disenchanted. |
| `FALLBACK_FREE_ROLL` | Nobody needed it: a free roll open to everyone present, highest roll wins. |
| `TIE_ML` | Still tied: the master looter decides. |
| `ML_CHOICE` | Chosen by the master looter. |
| `REJECTED_TO_BANK` | The proposal was rejected: the item goes to the guild bank. |
| `REJECTED_TO_DISENCHANT` | The proposal was rejected: the item is disenchanted. |

### Flags on a proposal (what to check)

| Code | Sentence |
|---|---|
| `DISCARDED_ROLLS` | Some rolls were discarded: check the list. |
| `COST_BY_COUNCIL` | The council sets the cost. |
| `NO_BANK_CHARACTER` | No bank character is set: choose who receives it. |
| `NO_DISENCHANTER` | No disenchanter is set: choose who receives it. |
| `TIE_UNRESOLVED` | A tie the rules cannot break: the master looter decides. |
| `REROLL_LIMIT` | Too many rerolls in a row: the master looter decides. |
| `FREE_ROLL_EMPTY` | Nobody rolled in the free roll. |
| `AFTER_REJECT` | This is a new proposal after a rejection. |
| `OUT_OF_ORDER` | Out of line: the winner is not the one the rules chose. |
| `COST_CHANGED` | The cost is not the one the rules chose. |
| `ML_DECIDED` | The rules had no winner or no cost: the master looter decided. |

### Why a roll was discarded

| Code | Sentence |
|---|---|
| `NOT_1_100` | Not a 1-100 roll. |
| `BAD_VALUE` | The roll value is not valid. |
| `BAD_ROLL` | The roll could not be read. |
| `BEFORE_OPEN` | Rolled before the round opened. |
| `AFTER_CLOSE` | Rolled after the round closed. |
| `NOT_PRESENT` | Not in the raid. |
| `NO_ADDON` | The addon is not active. |
| `NOT_ELIGIBLE` | Not part of this round. |
| `DUPLICATE` | A second roll in the same round: only the first counts. |
| `TIER_EMPTY` | Nobody in that tier could roll: these rolls were set aside. |

### Where a cost or a category comes from

| Code | Sentence |
|---|---|
| `OVERRIDE_COST` | Cost fixed for this item by the council. |
| `OVERRIDE_CATEGORY` | Category fixed for this item by the council. |
| `MATRIX` | Cost from the table of categories and quality. |
| `NOT_TRACKED` | Below the loot threshold: not part of the session. |
| `COUNCIL` | The council sets the cost. |
| `NO_CELL` | The table has no cost for this item: the council sets it. |
| `UNKNOWN_RESPONSE` | Unknown response. |
| `QUEST` | Quest item or token. |
| `SUBCLASS` | Category from the kind of item. |
| `EQUIPLOC` | Category from the slot. |
| `CLASS` | Category from the class of item. |
| `DEFAULT` | No rule matched: the category is Other. |

### How a new member's credits were set

| Code | Sentence |
|---|---|
| `START` | Joined before the first night: the season's starting credits. |
| `AVERAGE` | Late joiner: the roster's average credits, rounded. |
| `MEDIAN` | Late joiner: the roster's median credits. |
| `MIN` | Late joiner: the lowest credits in the roster. |
| `ZERO` | Late joiner: starts at 0 credits. |
| `FIXED` | Late joiner: a fixed number of credits. |
| `EMPTY_BASIS` | Late joiner, but nobody to compare with: the season's starting credits. |

### Reasons the master looter picks to change a proposal or an item

| Code | Sentence |
|---|---|
| `WRONG_CATEGORY` | The category or the cost was wrong. |
| `COUNCIL_COST` | The council priced the item. |
| `OBVIOUS_WASTE` | Obvious waste: given to another candidate. |
| `PASSED_TO_GAME` | Passed to game the system: given to someone who did not roll, at full cost. |
| `COUNCIL_VOTE` | Decided by the council's vote. |
| `LEGENDARY` | A piece of a legendary chain. |
| `MISTAKE` | A mistake by the master looter or the addon. |
| `OTHER` | Another reason, written by the master looter. |

### Automatic phases

| Code | Sentence |
|---|---|
| `TIMER` | The round closed when the timer ran out. |
| `ALL_ROLLED` | The round closed because everyone had rolled. |
| `AUTO_FAILED` | The automatic award failed: the master looter decides. |

### Guild rank changes

| Code | Sentence |
|---|---|
| `RENAMED` | A guild rank was renamed: nothing to do. |
| `REORDERED` | Guild ranks were reordered: the Guild Master should check the permissions table. |
| `REMOVED` | A guild rank was removed: the Guild Master should check the permissions table. |
| `ADDED` | A guild rank was added: the Guild Master should check the permissions table. |

### Why an action was refused

| Code | Sentence |
|---|---|
| `BAD_STATE` | Not possible at this point of the session. |
| `LOCKDOWN` | The game is in lockdown (boss fight): wait for it to end. |
| `UNKNOWN_INPUT` | Unknown action. |
| `NOT_ML` | Only the master looter can do this. |
| `PAUSED` | The session is paused. |
| `NOT_PAUSED` | The session is not paused. |
| `ENDED` | The session has ended. |
| `READ_ONLY` | The saved data comes from a newer version of the addon: it is read-only. |
| `REASON_REQUIRED` | A reason is required. |
| `ITEM_SETTLED` | This item has already been awarded. |
| `CATEGORY_LOCKED` | The category cannot change once the roll is open. |
| `NOTHING_CHANGED` | Nothing was changed. |
| `ITEM_IN_PROGRESS` | Another item is still being decided. |
| `ITEM_NOT_PENDING` | This item is not waiting for its roll. |
| `RESPONSES_CLOSED` | Responses are closed. |
| `BAD_RESPONSE` | That response does not exist. |
| `RESPONSE_LOCKED` | You already rolled: the response can no longer change. |
| `NO_ROUND_OPEN` | No round is open. |
| `NO_TIER` | The proposal has no tier to go on from. |
| `NO_WINNER` | There is no winner yet. |
| `NO_COST` | The cost is not set yet. |
| `NO_LEDGER` | There is no ledger to write to. |
| `VOTE_OPEN` | The council's vote is still open. |
| `VOTE_CLOSED` | The council's vote is closed. |
| `NOT_COUNCIL_MODE` | Awards are not decided by council vote. |
| `NO_VOTES` | Nobody has voted. |
| `VOTE_TIE` | The vote is tied: the master looter decides. |
| `NOT_ASSIGNED` | This item has not been awarded yet. |
| `WRONG_PLAYER` | The item went to another player. |
| `NOT_PRESENT` | Not in the raid. |
| `NO_ADDON` | The addon is not active: they cannot roll. |
| `NOT_TRACKED` | Below the loot threshold: not part of the session. |
| `UNKNOWN_TYPE` | Unknown kind of event: it comes from a newer version of the addon. |
| `REF_MISSING` | The event to cancel is not in the ledger. |
| `REF_NOT_VOIDABLE` | Only an award or a credit correction can be cancelled. |
| `ALREADY_VOIDED` | Already cancelled. |
| `DUPLICATE` | Already in the ledger. |
| `CONFLICT` | Another event with the same id is already in the ledger. |
| `REFUSED` | Refused. |
| `PENDING` | Waiting for the guild roster to load: it will be checked again. |
| `NOT_IN_GUILD` | The author is not in the guild. |
| `NOT_GM` | Only the Guild Master can change this. |
| `RANK_TOO_LOW` | The guild rank is too low for this. |
| `CONFIRM_REQUIRED` | A season is open: confirm the change. |
| `UNCHANGED` | Nothing changed. |
| `UNKNOWN_PRESET` | Unknown preset. |
| `SEASON_UNKNOWN` | Unknown season. |
| `SEASON_CLOSED` | The season is closed. |
| `SEASON_EXISTS` | A season with this id already exists. |
| `SEASON_ALREADY_OPEN` | Another season is already open: close it first. |
| `NOT_IN_PACK` | That raid is not in the season's pack. |
| `DIFFICULTY` | Unknown difficulty. |
| `NOT_MEMBER` | Not a member of the pool. |
| `ALREADY_JOINED` | Already in the pool. |
| `IS_ALT` | This is a linked alt: the credits belong to its main. |
| `MAIN_UNKNOWN` | The main is not in the pool. |
| `ALT_IS_MAIN` | This character is a main: it cannot be an alt. |
| `ALREADY_LINKED` | Already linked to a main. |
| `FACTION_MISMATCH` | Main and alt are in different factions. |

### Responses

| Code | Sentence |
|---|---|
| `MS` | Main-spec |
| `OS` | Off-spec |
| `TMOG` | Transmog |
| `PASS` | Pass |

### What a proposal does with the item

| Code | Sentence |
|---|---|
| `AWARD` | To a player |
| `BANK` | To the guild bank |
| `DISENCHANT` | To be disenchanted |
| `ML` | The master looter decides |

### What happens to a rejected item

| Code | Sentence |
|---|---|
| `PENDING` | Put the item back: reopen it later |
| `REOPEN` | Reopen the roll now |
| `NEXT_TIER` | Go on to the next tier |
| `BANK` | Send it to the guild bank |
| `DISENCHANT` | Disenchant it |

### States of a session and of an item

| Code | Sentence |
|---|---|
| `WAITING` | Waiting for a boss to be killed and its body to be opened |
| `COLLECTING` | Reading the drops |
| `ANNOUNCING` | Announcing the items to the raid |
| `ROLLING` | Responses and rolls open |
| `COMPUTING` | Computing the winner |
| `PROPOSAL` | Waiting for the master looter's decision |
| `ENDED` | Session ended |
| `PENDING` | Not rolled yet |
| `ASSIGNED` | Awarded, not delivered yet |
| `DELIVERED` | Delivered |

### Kinds of ledger event (the History tab)

| Code | Sentence |
|---|---|
| `SEASON_OPENED` | Season opened |
| `SEASON_CLOSED` | Season closed |
| `MEMBER_JOINED` | Member joined the pool |
| `MEMBER_LINKED_ALT` | Alt linked to a main |
| `NIGHT_OPENED` | Night opened |
| `NIGHT_CLOSED` | Night closed |
| `ROSTER_CHANGED` | Roster changed |
| `ENCOUNTER_KILLED` | Boss killed |
| `PROGRESS_SET` | Progress set by hand |
| `DROP_SEEN` | Drop seen |
| `ITEM_AWARDED` | Item awarded |
| `AWARD_VOIDED` | Award or correction cancelled |
| `CREDITS_ADJUSTED` | Credits corrected by hand |
| `LEGENDARY_PROJECT_OPENED` | Legendary project opened |
| `LEGENDARY_PROJECT_PAID` | Legendary piece paid |
| `LEGENDARY_PROJECT_CLOSED` | Legendary project closed |
| `CONFIG_CHANGED` | Rules changed |
| `PERMISSIONS_CHANGED` | Permissions changed |

### Presets of the rules

| Code | Sentence |
|---|---|
| `PATTO` | Patto (the guild's current regulation) |
| `ROLL_ONLY` | Roll only |
| `LOOT_COUNCIL` | Pure loot council |
| `EPGP_SIMPLE` | Simple EPGP |

