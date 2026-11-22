# M5 — Upgrades and council

**Goal:** the council works from the addon: upgrade hints computed on each raider's client, the flags "upgrade ignored" and "possible waste", council interventions with a mandatory reason, the optional vote, legendary projects, BoE and the guild bank fallback ([`docs/ANALISI.md` §3.6–§3.8, §5](../ANALISI.md#5-rilevamento-upgrade-e-chi-passa-per-fare-il-furbo)).

**Exit criterion:** in a simulated session the council sees the flags before closing the round, intervenes with a reason and every intervention lands in the audit; legendaries go to the project's builder.

Open question 8 ([#2](https://github.com/Finland6738/finland-dragon-credit-points/issues/2)) was open while M5 was built, so M5 built the reversible default (item level + editable default weights per spec; a Pawn-like import that is optional and off; no guild-wide BiS lists). **The owner resolved it on 2026-11-22 ([M7-5c](M7-release.md#m7-5c--three-button-popup-and-automatic-upgrade-badge)):** no stat weights at all; the upgrade badge is the quality tier against the gear worn during the fight, with the item-level difference. The stat-weight score of M5-1 / M5-2 and the whole of M5-3 are superseded; the history below is kept as it was shipped.

### M5-1 — Upgrade score
> The weighted stat score and its thresholds are **superseded by [M7-5c](M7-release.md#m7-5c--three-button-popup-and-automatic-upgrade-badge)** (the quality tiers); the proficiency table and the slot comparison stay.

- Branch: `step/m5-1-upgrade-score`
- Depends on: M2-1
- Analysis: §5.1 (can use, compare against, how much, verdict), §5.3
- Scope: `Domain/UpgradeScore.lua`: proficiency table per class (armour and weapon types), slot comparison (rings and trinkets against the worse of the two, two-hand vs main-hand + off-hand), item-level delta, weighted stat delta (`score = Σ weight × value`, `upgrade % = (new − equipped) / equipped`), verdicts *big* (≥ threshold, preset 5%), *small*, *none*, *not comparable*; default weights per class and spec (editable, reversible default of issue #2); item-level-only fallback when stats are unreliable (plan B of spike S5).
- Done when:
  - [x] Verdicts for a table of known item pairs per class match the expected ones.
- Tests: `Tests/test_upgrade_score.lua`.
- Docs: CHANGELOG.
- Real client: nothing (inputs come from M5-2).
- Suggested model/effort: `opus` / high

### M5-2 — Inventory adapter and verdicts in the popup
- Branch: `step/m5-2-popup-verdicts`
- Depends on: M5-1, M4-6
- Analysis: §5.1, §6 (MS1 / MS2 weights)
- Scope: `Adapters/Inventory.lua` (equipped items, `C_Item.GetItemStatDelta`, `GetDetailedItemLevelInfo`, `IsEquippableItem`, `DoesItemContainSpec`), the score computed twice (MS1 weights → Main-spec, MS2 weights → Off-spec), the verdict chip ("Upgrade +7.4% · ilvl +6"), auto-pass on unusable items (configurable), verdict and equipped links sent with the response.
- Done when:
  - [x] The popup shows the verdict per spec in the mock; unusable items preselect Pass.
  - [ ] The owner confirms in game that the verdicts of raid items read sensibly: the stat deltas and item levels of real drops, the spec lists (spike S5). *(in game)*
- Tests: `Tests/test_inventory.lua`, `Tests/test_ui_popup.lua` extended.
- Docs: wiki **Upgrade Hints** (EN + IT), CHANGELOG.
- Note: built as `Adapters/Inventory.lua` (the game reads), `App/UpgradeAdvisor.lua` (rules + declared specs + the score twice, cached) and a new rules section `upgrade` (thresholds, `useStats`, `autoPass`, `enabled`). The protocol is now version 3: `SRESP` carries `vd` (verdicts) and `eq` (worn pieces) as optional fields. The ML sees them in an *Upgrade* column of the candidates' table; hiding them from non-council clients is M5-4. The wiki text lives in the **Rolling for Loot** page (verdicts and their limits), not in a page of its own ([`docs/ANALISI.md`](../ANALISI.md) §5.1, "Come è fatto (M5-2)").
- Real client: stat deltas of raid items (spike S5).
- Suggested model/effort: `sonnet` / medium

### M5-3 — Weight import and wishlist
> **Superseded by [M7-5c](M7-release.md#m7-5c--three-button-popup-and-automatic-upgrade-badge)** (owner decision of 2026-11-22): the personal weights, the Pawn-like import (`/fdcp weights`) and the wishlist (`/fdcp wish`) are removed.

- Branch: `step/m5-3-weights-wishlist`
- Depends on: M5-2
- Analysis: §5.1 points 3 and 5, §13 question 8
- Scope: personal weights per spec, import from a Pawn-like string (optional, off by default, reversible per issue #2), the player's BiS wishlist reminded by the popup. Guild-wide BiS lists only if issue #2 asks for them.
- Done when:
  - [x] A valid import string sets the weights; an invalid one is refused with a message; the wishlist survives `/reload`. (Offline: `Tests/test_weights_import.lua`; how the popup row looks in a raid is for the owner's in-game check.)
- Tests: `Tests/test_weights_import.lua`.
- Docs: Upgrade Hints (EN + IT), CHANGELOG; comment on issue #2 with what was built (done).
- Real client: nothing beyond M5-2.
- Suggested model/effort: `sonnet` / medium

### M5-4 — Council flags
- Branch: `step/m5-4-council-flags`
- Depends on: M5-2, M4-4
- Analysis: §5.2, §6 (flags look only at MS1)
- Scope: `Domain/Flags.lua`: **upgrade ignored** (a raider with the addon passes or does not answer on a big MS1 upgrade) and **possible waste** (the first in the queue has a small upgrade, another candidate a big one, configurable ratio); flags shown to the ML as soon as responses arrive, before the round closes; verdicts visible only to the council (configurable); flags never change the winner by themselves.
- Done when:
  - [x] Both flags fire on the documented cases and never on MS2 or below the thresholds.
- Tests: `Tests/test_flags.lua`, `Tests/test_ui_ml_session.lua` extended.
- Docs: CHANGELOG; wiki **Master Looter Guide**, **Loot Rules** and **Rolling for Loot** (EN + IT).
- Note: built as `Domain/Flags.lua` (pure: codes and the players they name), `SessionFSM.Flags` (live from the responses, written with the proposal: codes in `proposal.flags` and the award's event, details on the item; not `INFO_FLAGS`, so an `auto` award waits for the master looter) and the board / ML window (lines under the candidates before the round closes, the *Notes* column). New rules keys in the `council` section: `flags`, `wasteRatio` (preset 2), `verdicts` (`council` preset, `officers`, `ml`); a council member now gets the read-only window with the verdicts even without `award.confirm`. "Possible waste" also fires when the first in line has no upgrade at all; an off-spec answer is not a pass; a player who never answers sends no verdict, so the "no answer" case fires only when a verdict is known ([`docs/ANALISI.md`](../ANALISI.md) §5.2, "Come è fatto (M5-4)").
- Real client: nothing beyond M4 (the look of the flag lines in the window's strip in a real raid).
- Suggested model/effort: `opus` / high

### M5-5 — Council interventions and vote
- Branch: `step/m5-5-council-actions`
- Depends on: M5-4, M3-1
- Analysis: §3.6, §3.4 (award modes)
- Scope: council membership (rank ≤ X and present, or explicit list); interventions with mandatory reason: correct category or cost **before** the roll opens, assign to another candidate (waste), assign to a non-roller at full cost, void an award (compensation event), adjust credits; the optional vote (each council member votes from their window, the ML sees votes before confirming); `awardMode` `auto` and `council`; every intervention in the audit.
- Done when:
  - [x] Interventions without a reason are impossible; a category change after the roll opened is refused; votes reach the ML in the simulator.
- Tests: `Tests/test_council.lua`.
- Docs: CHANGELOG; wiki **Master Looter Guide**, **Loot Rules** and **Commands** (EN + IT).
- Note: built as `Domain/Council.lua` (membership by the rules' new `council.members` list or the rank, presence; `Void` and `Adjust` through the permission gate; `Audit`), the vote in `Domain/SessionFSM.lua` (awardMode `council`, or `council.vote` in the other modes as advice; a dissenting vote holds an `auto` award), the corrections before the roll written with the award, and `App/CouncilService.lua` with `/fdcp council` as the interface until M5-8. The session protocol is now version 4: `SVOTE` (the sender's own vote, only from a council member), `vc` on `SPROP`, `vt` on `SSTATE`; older clients drop the new type ([`docs/ANALISI.md`](../ANALISI.md) §3.6, "Come è fatto (M5-5)").
- Real client: nothing beyond M4 (the `SVOTE` message on RAID, like `SRESP`).
- Suggested model/effort: `opus` / high

### M5-6 — Legendary projects
- Branch: `step/m5-6-legendaries`
- Depends on: M5-5
- Analysis: §3.7
- Scope: `Domain/Legendary.lua`: projects (name, final item, chain piece item ids, builder, pieces paid), modes `council` (preset), `vote`, `roll`, `queue`; a chain piece that drops is recognised and proposed to the builder at `legendary.chainPieceCost`; `LEGENDARY_PROJECT_*` events.
- Done when:
  - [x] Each mode gives the documented result; a chain piece goes to the builder without a roll in `council` mode.
- Tests: `Tests/test_legendary.lua`.
- Docs: CHANGELOG; wiki **Loot Rules** (the legendary section) and **Commands** (EN + IT).
- Note: built as `Domain/Legendary.lua` (pure: the projects folded from `LEGENDARY_PROJECT_OPENED` / `_PAID` / `_CLOSED`, whose payload checks it registers in the ledger; who receives a piece in each mode), the piece recognised by `Domain/SessionFSM.lua` at `LOOT_OPENED` (`env.legendary`, read from the ledger by `App/SessionController.lua` only when a corpse is opened) and proposed without a roll when its turn comes, and `App/LegendaryService.lua` with `/fdcp legendary` as the interface until M5-8. The project's id is its `OPENED` event's id; a piece belongs to one open project; `PAID` is written by the master looter's confirm next to the `ITEM_AWARDED` (which still charges the credits) and stops counting when the award is voided; in mode `roll` the project is not consulted ([`docs/ANALISI.md`](../ANALISI.md) §3.7, "Come è fatto (M5-6)").
- Real client: nothing (the `/fdcp legendary` output and item links typed into it are for the owner's M5 checklist).
- Suggested model/effort: `opus` / high

### M5-7 — BoE and the guild bank fallback
- Branch: `step/m5-7-boe-bank`
- Depends on: M2-2, M4-4
- Analysis: §3.8
- Scope: BoE rolled like any item; without main-spec answers `boe.fallback` = `bank` (preset) | `offspec` | `disenchant` | `freeroll`; with `bank` the item is awarded to the configured bank character and logged as the guild bank, an officer can add the gold from its sale later.
- Done when:
  - [x] Every fallback mode is tested; bank awards never charge credits.
- Tests: `Tests/test_boe.lua`.
- Docs: Loot Rules (EN + IT), Commands (EN + IT), CHANGELOG.
- Note: the fallbacks themselves were already in `Domain/Priority.lua` (M2-2) and the bank / disenchant awards in `Domain/SessionFSM.lua` (M2-6, M4-4) and the delivery (M4-7); this step adds `Domain/GuildBank.lua` (pure: the bank items of a season folded from `ITEM_AWARDED` with target `bank`, and `BANK_ITEM_SOLD{ref, copper}`, the gold of a sale, through the `night.run` gate; the last sale of an item counts, a voided award leaves the list), `App/BankService.lua` with `/fdcp bank` (the fallback in force, the bank character, the items and `sold <n> <price>`) and `Tests/test_boe.lua` (every fallback mode in the session, the costs, the sales, the gate, and the whole path on the mock client up to master loot to the bank character).
- Real client: nothing (the `/fdcp bank` output is for the owner's M5 checklist).
- Suggested model/effort: `opus` / medium

### M5-8 — Council window and the M5 checklist
- Branch: `step/m5-8-council-ui`
- Depends on: M5-5, M5-6, M5-7
- Analysis: §9.3 (Council page), §12 (M5 exit); [`docs/specs/ui-style.md`](../specs/ui-style.md) §6
- Scope: `UI/Windows/Council.lua` as the **Loot › Council** sub-tab, look per `ui-style.md` (flags, intervention dialogs with reason, votes, legendary projects); `docs/checklists/M5.md` for the owner.
- Done when:
  - [x] The council can do every action of M5-5 and M5-6 from the window in the mock.
  - [ ] The owner confirms the council flow in game. *(in game)*
- Tests: `Tests/test_ui_council.lua`.
- Docs: wiki **Council** (EN + IT), README features (EN + IT), CHANGELOG.
- Note: built as `UI/Windows/Council.lua`, hooked into `UI/Windows/MLSession.lua` as its third sub-tab, and `docs/checklists/M5.md`. The window decides nothing: it draws the session board, `CouncilService` and `LegendaryService` and sends the clicks back; new service methods `CanVote(board)`, `AwardMode()` and `Pool()`. The item on the table (proposal, flags, votes, the member's vote, the master looter's shortcuts to the Session tab's Modify / Correct dialogs), the views *Awards*, *Audit* and *Legendary*, and one reason dialog for cancelling an award, adjusting credits and opening a project; the bank has no window (`/fdcp bank`). The wiki page is **Council** (EN + IT); the checklist collects every "not verified in game" item of M5 ([`docs/ANALISI.md`](../ANALISI.md) §3.6, "Come è fatto (M5-8)").
- Real client: the whole checklist.
- Suggested model/effort: `sonnet` / medium
