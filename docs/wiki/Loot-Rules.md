# Loot Rules

> **In development.** This page describes the rules the addon's engine already follows (written and tested offline; nothing has run in the game yet). The windows that use them arrive in later versions. [Italiano](Loot-Rules-it)

The addon does the arithmetic, the master looter decides. These are the guild's rules ("Patto" preset) as the engine applies them. Every value below can be changed by the Guild Master in the rules, except where it says "fixed".

## Credits

- Credits are **never stored**: they are computed from the ledger, the list of everything that happened (awards, corrections, new members). A correction is a new entry, never an erasure.
- A season starts everyone at **0 credits**. A season is a pack of raids (10, 20 and 40 players share one credit table, Normal and Veteran too).
- **Only mains** earn and spend credits. An alt is linked to its main and uses the main's credits.
- Fewer credits means a better position: **the player with the fewest credits wins**, and the roll only breaks ties.
- The roster is **dynamic**: a player can join in the middle of a season. A newly arrived member starts with **the credits of the player who has the fewest** (among the members who played at least one night), so they do not jump the queue and do not start behind the last in line either. The number is written down once and stays stable.
- **Missing an official night costs +1 credit** (see [Absences](#absences) below).

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
- The roll must come from the **Roll button of the popup** (rule *Rolls count only from the popup's Roll button*, on by default): a `/roll` typed by hand is set aside as `NOT_FROM_BUTTON` and does not use up the player's turn. The button tells the master looter's addon about the click just before the game's roll; the roll itself is still the game's. A player whose addon is older than this rule rolls as before until they update.
- Whoever does not have the addon cannot answer or win (the master looter is told before the first roll).

## Ties and rerolls

1. Fewest credits wins.
2. Same credits: the **highest roll** wins.
3. Same credits and same roll: a **reroll among the tied only**, repeated until one is left. Players outside the tie who roll again are ignored. After five rerolls in a row the master looter decides.

## Bind-on-equip items

A BoE is rolled like any item: same category, same cost. Whoever takes it as **main-spec** pays its credits like for any other item. If **nobody answers main-spec** (or the main-spec players do not roll), the rules' *BoE fallback* decides:

| Fallback | What happens |
|---|---|
| **bank** (preset) | It goes to the **guild bank**: the bank character chosen in the rules receives it, **at no cost**. The log marks it *to the guild bank*. |
| **offspec** | The off-spec tier rolls for it, as for any item, at the off-spec cost. |
| **disenchant** | The disenchanter chosen in the rules receives it, at no cost. |
| **freeroll** | A free roll among the raid; the winner pays the rules' free roll cost (0 in the preset). |

An item for the bank **never costs credits to anybody**, also when the master looter sends a proposal to the bank or gives the bank's item to a raider to hold. If the rules name no bank character, the proposal has no winner and the master looter chooses who receives it. An item that binds on pickup never takes this fallback.

**The gold of the sale.** When the bank sells the item, an officer records the price with `/fdcp bank sold <n> <price>` (gold like `120` or `12.5`, or coins like `12g 30s 5c`): the sale goes in the log and nobody's credits change. Recording it again corrects the price; if the award to the bank is cancelled, its sale no longer counts. `/fdcp bank` shows the fallback in force, the bank character, the season's bank items with their price and the total (see [[Commands|Commands]]).

## Legendaries

A legendary is **not rolled** in the preset: the council opens a **legendary project** (a name, the final item, the item ids of the chain pieces and the **builder** it chooses), and when a piece of the chain drops the addon recognises it and proposes it directly to the builder at **2 credits** (the rules' *chain piece cost*). Both the mode and the cost are in the guild's rules:

| Mode | What happens to a chain piece |
|---|---|
| **council** (preset) | No roll: it goes to the project's builder, at the chain piece cost. |
| **vote** | No roll: the council votes (the builder is proposed first), the majority wins, same cost. The master looter closes the vote before confirming. |
| **roll** | Rolled like any other item: the category sets the cost and the project is not consulted. |
| **queue** | No roll: it goes to the first of the project's list, decided at the start of the season, who is in the raid; same cost. |

If the builder is not in the raid (or nobody of the list is), or the project has no builder, the proposal has no winner and a flag says why: the master looter chooses who gets the piece, with a reason, or sends it to the bank. A piece given to a character is recorded in the project as **paid** (the credits are the award's, so cancelling the award gives them back and the piece no longer counts). A piece can belong to one open project at a time. When the legendary is built the project is closed as **completed**; if the guild gives up, as **abandoned**. A project belongs to its season. Until the council window arrives, projects are managed with `/fdcp legendary` (see [[Commands|Commands]]).

## What the master looter and the council may change

The addon prepares each result: who, how many credits and why, in words. The master looter then:

- **confirms**: the credits are charged and the result is announced;
- **rejects**: nothing is charged and the item goes back into the session (reopen the roll, next tier, bank or disenchant);
- **modifies**: a different winner or cost, always **with a reason** chosen from the list below. The addon shows how it differs from the rule ("out of line") and the event is marked as an intervention in the audit.

The council (guild officers in the raid, or the list of characters the guild writes in its rules) can, always with a reason that goes in the log: fix a category or cost **before** the roll opens (once the roll is open the addon refuses); give an item to another candidate in a case of **obvious waste**; give it to someone who **did not roll but passed to game the system**, at full cost; assign a legendary; cancel an award (the award stays in the log, marked cancelled, and the credits come back); correct a member's credits by hand. Without a reason nothing is written, and every intervention is listed in the season's audit (`/fdcp council audit`, or **Loot › Council** in the window: [[Council|Council]]). Who counts as master looter, council or officer comes from the **guild ranks**, and only the **Guild Master** can change what each rank may do and the rules themselves.

**The council's vote.** Off in the preset. With the award mode **council** the council votes on every proposal and the master looter closes the vote before confirming: a strict majority decides (a tie, or no vote, leaves it to the master looter). With the **council vote** turned on in the other modes the votes only inform the master looter, who sees them before confirming; in automatic mode a vote for another player stops the automatic award. Each member votes only for themselves, from their own game; the votes are written with the award. See the [[Master Looter Guide|Master-Looter-Guide]], "The council: interventions and the vote".

**Council flags.** To make the obvious cases visible in time, the addon raises two flags as soon as the answers arrive: **upgrade ignored** (a raider passes on an item that is a big upgrade for their main spec) and **possible waste** (the first in line gains little or nothing, another main-spec candidate gains at least twice as much, with a big upgrade). They look only at the main spec (MS1), never change the winner by themselves and stop an automatic award until the master looter looks; acting on them is a modification with its reason. The guild's rules set whether the flags are on, the waste ratio (preset 2) and who besides the master looter sees the verdicts and the flags (preset: the council). See the [[Master Looter Guide|Master-Looter-Guide]], "Council flags".

## How a loot session runs

The session runs on the master looter's client only; nobody else has to do anything except answer and roll.

- **After the kill.** A loot session opens as soon as a boss dies, never during the fight, and only on the client of the master looter.
- **The corpse.** When the master looter opens the corpse, the items at or above the loot threshold go into the session with their category and cost. If the chat is locked down or another boss is engaged at that moment, the addon waits and takes the items as soon as it is over.
- **By itself.** The addon announces the items and opens the rolls one item at a time. It also opens the reroll among the tied, the off-spec round when nobody wants an item for main spec, and the fallback. A round closes when everybody has rolled or when its timer runs out. **Pause** stops every timer.
- **Rolls held by the game.** While the game hides the roll messages (in an instance, during a lockdown), a round never closes on its timer: rolls made in time still count.
- **The master looter decides.** The addon writes the proposal: who, how much and why. The item is charged only when the master looter confirms it. Each award goes into the ledger with its reasons and flags.
- **/reload or a disconnection.** The session is saved at every step. After a `/reload` or a disconnection it starts again from exactly where it was, and the raid's windows catch up.
- **The next boss.** When the next boss dies, the previous session ends if no item is in progress. Its items that were never rolled stay listed for the master looter.
- **Other officers.** They see the session read-only; the raiders see their item popup.

## The three examples of the regulation

Aurel, Bryn and Corin all answer main-spec on a blue ring, a shoulder and a cloak. These are the cases the engine's tests run.

**The ring: same credits, the higher roll wins.** All three have 0 credits. Aurel rolls 45, Bryn 76, Corin 12. **Bryn** wins, pays 1 credit. The proposal says: *Main-spec: it is asked first, and the cost is paid. Same credits as the others, highest roll.*

**The shoulder: fewer credits win, the roll does not count.** Aurel has 0 credits, Bryn 2, Corin 3. They roll 34, 90 and 99. **Aurel** wins with the lowest roll. The proposal says: *Main-spec: it is asked first, and the cost is paid. Fewest credits: the roll did not matter.*

**The cloak: a tie, so a reroll among the tied.** All three have 1 credit. Aurel rolls 40, Bryn and Corin both 88. Only **Bryn and Corin** roll again. Aurel rolls again too, but he is not part of the tie, so that roll is discarded (*Not part of this round*). Bryn rolls 20, Corin 61: **Corin** wins. The proposal says: *Main-spec: it is asked first, and the cost is paid. Tied on credits and roll, won the reroll among the tied.* with the flag *Some rolls were discarded: check the list.*

## The pool, declarations and alts

Each season the guild has **one rotating roster**: the pool of mains. Every main is declared once for the whole season:

- **MS1**: the main spec (required). It is the spec of the **Main-spec** button and the one the council's "ignored upgrade" flag looks at.
- **MS2**: the second spec. It is the **Off-spec** button: it costs 0 credits and opens only if nobody answered main-spec.
- **OS** (the spec you would like to play), **role**, **class**, **faction** and the **days** you can raid, with a short note, are roster information: the third spec gives no right to roll.

The declaration is **locked for the season**. If something is wrong, an officer corrects it, and the correction is written in the ledger with who did it and when. A member can be **active**, **in trial** (shown as Trial on the site) or **inactive** (keeps the credits, is not counted and is not exported).

**Alts.** An alt is linked to a main and **never has credits of its own**: what it wins is charged to its main. You ask for the link from the addon and an officer approves it, so nobody can attach a character to someone else. The same goes for joining the pool: you send your declaration and an officer approves it. **Two factions:** a player who plays both has **two mains, one per faction**, linked as the same player, each with their own credits.

An officer can fill in a declaration from the **guild note** (for example "Fury / Arms"): the addon only suggests the specs it recognises and the officer confirms.

## The bench

When more players come than the raid holds, the **master looter decides** who sits out; the addon only proposes. The proposal starts from the players who can come (a "no" on the calendar, or a weekday you did not declare, takes you out of the count: nobody benches an absent player), and benches the surplus in this order:

1. players who **asked** to sit out;
2. players who answered **maybe** on the calendar;
3. players with the **fewest benches** this season, so everybody sits out about as often;
4. then the ones who have **played the most nights**, then by name.

The raid always keeps its **minimum of tanks and healers** (2 and 4 by default, set in the rules); if the places cannot be filled otherwise, the minimum gives way and the master looter sees a warning. A night is linked to the guild's **official raid event** on the in-game calendar when there is one, and its sign-ups feed the proposal. The addon only reads the calendar.

**The bench never costs credits** in the guild's preset: someone who plays less earns fewer credits and so already has the precedence. A guild that wants it can give a **bonus** (fewer credits for every bench, never below 0) or a **malus**. Who benched how often is shown to officers only.

## Absences

A member of the season's roster gets **+1 credit** (remember: fewer credits wins, so this is a penalty) for an official night when they:

- **did not sign up** for the raid on the in-game calendar (no answer, or "no"), and did not play;
- **signed up but did not come** ("yes" or "maybe", and did not play);
- **benched themselves** on their own initiative (the **Bench myself** button in the Night tab).

**No penalty** for anyone who was in the raid (even for one boss) and for anyone the **officers benched**: the rotation never costs credits.

At the close of the night the addon lists the proposed penalties and an officer confirms them with **one click**; nothing is written before that, unless the Guild Master turns on *Write the absence penalties at the close, without confirmation*. Each penalty is a credit correction with the reason *Absence from an official night*: it shows in the log and in the audit, and an officer can cancel it like any correction (the credits go back to what they were). When the calendar has no raid event for the night, an absent member is still penalized (*absent, sign-ups unknown*). The amount (1) and the confirmation are guild rules, under Settings › Rules › Members.

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
| `LEGENDARY_BUILDER` | A piece of a legendary chain: it goes to the project's builder, no roll. |
| `LEGENDARY_QUEUE` | A piece of a legendary chain: it goes to the first of the project's queue who is present. |

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
| `UPGRADE_IGNORED` | Upgrade ignored: someone passed on a big upgrade for their main spec. |
| `POSSIBLE_WASTE` | Possible waste: the first in line gains little, another candidate a lot. |
| `NO_BUILDER` | Legendary piece: the project has no builder. Choose who gets it. |
| `BUILDER_ABSENT` | Legendary piece: the builder is not in the raid. Choose who gets it. |
| `QUEUE_EMPTY` | Legendary piece: nobody of the project's queue is in the raid. Choose who gets it. |

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
| `NOT_FROM_BUTTON` | Typed by hand: only the Roll button of the popup counts. |
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
| `DUPLICATE_AWARD` | The same item was awarded twice. |
| `PENALTY` | A penalty decided by the council. |
| `BONUS` | A bonus decided by the council. |
| `ABSENCE` | Absence from an official night. |

The last four, and some of the others, are the reasons of a cancelled award or of a manual credit correction.

### Why a missed night is penalized

| Code | Sentence |
|---|---|
| `NOT_SIGNED_UP` | not signed up |
| `NO_SHOW` | signed up, did not come |
| `SELF_BENCH` | benched themselves |
| `ABSENT` | absent, sign-ups unknown |

### Automatic phases

| Code | Sentence |
|---|---|
| `TIMER` | The round closed when the timer ran out. |
| `ALL_ROLLED` | The round closed because everyone had rolled. |
| `AUTO_FAILED` | The automatic award failed: the master looter decides. |

### Guild rank changes

The addon reads ranks from the guild roster, by their position, never by their name. After you log in it waits for the roster: until it arrives, events from other players that need a rank wait and are checked as soon as it does, and the buttons that write to the ledger stay off. When the Guild Master reorders, deletes or adds ranks, the Guild Master gets a chat message (again at every login until the permissions table has been checked), with the permissions that point to a rank that no longer exists. When the guild gets a new Guild Master, the power to change the rules passes to them as soon as the game shows it; the changes made by the previous Guild Master stay valid. Both players are told in chat.

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
| `NOT_COUNCIL_MODE` | The council does not vote in this session. |
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
| `MS1_REQUIRED` | The main spec (MS1) is required. |
| `CLASS_REQUIRED` | The class is required. |
| `ROLE_REQUIRED` | The role is required. |
| `DUPLICATE_SPEC` | The same spec is declared twice. |
| `SPEC_UNKNOWN` | Unknown specialization. |
| `SPEC_CLASS` | A declared spec does not belong to the class. |
| `ROLE_MISMATCH` | The role is not the role of the main spec. |
| `TWIN_SELF` | A main cannot be its own twin. |
| `TWIN_UNKNOWN` | The other-faction main is not in the pool. |
| `FACTION_REQUIRED` | Both mains need a faction to be linked as one player. |
| `TWIN_FACTION` | A player has one main per faction: the other main is in the same faction. |
| `TWIN_TAKEN` | That main already belongs to another player's pair. |
| `REQUEST_UNKNOWN` | That request does not exist. |
| `REQUEST_CLOSED` | That request has already been decided. |
| `REQUEST_PENDING` | Another request for this character is waiting for an officer. |
| `REQUEST_LIMIT` | Too many requests are waiting for an officer. |
| `NOT_COUNCIL` | Only a member of the loot council can do this. |
| `NO_PROPOSAL` | There is no proposal to vote on. |
| `BAD_CHOICE` | Name the player you vote for. |
| `BAD_DELTA` | Enter the credits as a number other than zero (at most 1000 either way). |
| `NO_SEASON` | No season is open. |
| `NOT_READY` | The guild's data is not loaded yet. |
| `PROJECT_UNKNOWN` | There is no such legendary project. |
| `PROJECT_CLOSED` | The legendary project is already closed. |
| `NOT_A_PIECE` | The item is not a piece of that legendary chain. |
| `PIECE_TAKEN` | Another open legendary project already has one of these pieces. |
| `BAD_NAME` | Give the project a name (at most 48 characters). |
| `BAD_ITEM` | The final item is not a valid item. |
| `BAD_PIECES` | List the chain pieces: from 1 to 40 different items. |
| `BAD_OUTCOME` | A project ends completed or abandoned. |
| `NOT_BANK_ITEM` | That item did not go to the guild bank. |
| `BANK_ITEM_VOIDED` | That award to the guild bank was cancelled. |
| `BAD_GOLD` | The price must be an amount of gold, 0 or more. |

### Status of a member of the pool

| Code | Sentence |
|---|---|
| `ACTIVE` | Active |
| `TRIAL` | Trial |
| `INACTIVE` | Inactive |

### Responses

| Code | Sentence |
|---|---|
| `MS` | Main-spec |
| `OS` | Off-spec |
| `TMOG` | Transmog |
| `PASS` | Pass |

### Upgrade verdicts

How an item compares with what a player wears (see [[Rolling for Loot|Rolling-for-Loot]]).

| Code | Sentence |
|---|---|
| `BIG` | Big upgrade |
| `SMALL` | Small upgrade |
| `NONE` | No upgrade |
| `NOT_COMPARABLE` | Not comparable |
| `UNUSABLE` | Not usable |

### Why an item cannot be used or compared

| Code | Sentence |
|---|---|
| `ARMOR_TYPE` | Your class cannot wear this type of armor. |
| `WEAPON_TYPE` | Your class cannot use this type of weapon. |
| `DUAL_WIELD` | Your class or spec cannot dual wield. |
| `CLASS_RESTRICTED` | This item is for other classes. |
| `SPEC_RESTRICTED` | This item is not for your specialization. |
| `UNKNOWN_CLASS` | The addon does not know your class. |
| `NOT_EQUIPPABLE` | This is not a piece of equipment: the addon cannot compare it. |
| `COSMETIC` | A shirt or a tabard: there is nothing to compare. |
| `EFFECT_TRINKET` | A trinket with a use effect: the stats cannot tell its worth. |
| `EFFECT_TRINKETS` | Both your trinkets have a use effect: the addon keeps them. |
| `TWO_HAND_EQUIPPED` | You wear a two-handed weapon: this item goes in the other hand. |
| `NO_ITEM_LEVEL` | The game gave no item level for this item. |

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
| `LINEUP_CHANGED` | Lineup changed |
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
| `BANK_ITEM_SOLD` | Guild bank item sold |
| `CONFIG_CHANGED` | Rules changed |
| `PERMISSIONS_CHANGED` | Permissions changed |

### How a legendary project ended

| Code | Sentence |
|---|---|
| `COMPLETED` | completed |
| `ABANDONED` | abandoned |

### Presets of the rules

| Code | Sentence |
|---|---|
| `PATTO` | Patto (the guild's current regulation) |
| `ROLL_ONLY` | Roll only |
| `LOOT_COUNCIL` | Pure loot council |
| `EPGP_SIMPLE` | Simple EPGP |

