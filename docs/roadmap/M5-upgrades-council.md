# M5 — Upgrades and council

**Goal:** the council works from the addon: upgrade hints computed on each raider's client, the flags "upgrade ignored" and "possible waste", council interventions with a mandatory reason, the optional vote, legendary projects, BoE and the guild bank fallback ([`docs/ANALISI.md` §3.6–§3.8, §5](../ANALISI.md#5-rilevamento-upgrade-e-chi-passa-per-fare-il-furbo)).

**Exit criterion:** in a simulated session the council sees the flags before closing the round, intervenes with a reason and every intervention lands in the audit; legendaries go to the project's builder.

Open question 8 ([#2](https://github.com/Finland6738/finland-dragon-credit-points/issues/2)) is still open: until the owner decides, M5 builds the reversible default (item level + editable default weights per spec; a Pawn-like import that is optional and off; no guild-wide BiS lists).

### M5-1 — Upgrade score
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
  - [ ] Both flags fire on the documented cases and never on MS2 or below the thresholds.
- Tests: `Tests/test_flags.lua`.
- Docs: CHANGELOG.
- Real client: nothing beyond M4.
- Suggested model/effort: `opus` / high

### M5-5 — Council interventions and vote
- Branch: `step/m5-5-council-actions`
- Depends on: M5-4, M3-1
- Analysis: §3.6, §3.4 (award modes)
- Scope: council membership (rank ≤ X and present, or explicit list); interventions with mandatory reason: correct category or cost **before** the roll opens, assign to another candidate (waste), assign to a non-roller at full cost, void an award (compensation event), adjust credits; the optional vote (each council member votes from their window, the ML sees votes before confirming); `awardMode` `auto` and `council`; every intervention in the audit.
- Done when:
  - [ ] Interventions without a reason are impossible; a category change after the roll opened is refused; votes reach the ML in the simulator.
- Tests: `Tests/test_council.lua`.
- Docs: CHANGELOG.
- Real client: nothing beyond M4.
- Suggested model/effort: `opus` / high

### M5-6 — Legendary projects
- Branch: `step/m5-6-legendaries`
- Depends on: M5-5
- Analysis: §3.7
- Scope: `Domain/Legendary.lua`: projects (name, final item, chain piece item ids, builder, pieces paid), modes `council` (preset), `vote`, `roll`, `queue`; a chain piece that drops is recognised and proposed to the builder at `legendary.chainPieceCost`; `LEGENDARY_PROJECT_*` events.
- Done when:
  - [ ] Each mode gives the documented result; a chain piece goes to the builder without a roll in `council` mode.
- Tests: `Tests/test_legendary.lua`.
- Docs: CHANGELOG.
- Real client: nothing.
- Suggested model/effort: `opus` / high

### M5-7 — BoE and the guild bank fallback
- Branch: `step/m5-7-boe-bank`
- Depends on: M2-2, M4-4
- Analysis: §3.8
- Scope: BoE rolled like any item; without main-spec answers `boe.fallback` = `bank` (preset) | `offspec` | `disenchant` | `freeroll`; with `bank` the item is awarded to the configured bank character and logged as the guild bank, an officer can add the gold from its sale later.
- Done when:
  - [ ] Every fallback mode is tested; bank awards never charge credits.
- Tests: `Tests/test_boe.lua`.
- Docs: Loot Rules (EN + IT), CHANGELOG.
- Real client: nothing.
- Suggested model/effort: `opus` / medium

### M5-8 — Council window and the M5 checklist
- Branch: `step/m5-8-council-ui`
- Depends on: M5-5, M5-6, M5-7
- Analysis: §9.3 (Council page), §12 (M5 exit); [`docs/specs/ui-style.md`](../specs/ui-style.md) §6
- Scope: `UI/Windows/Council.lua` as the **Loot › Council** sub-tab, look per `ui-style.md` (flags, intervention dialogs with reason, votes, legendary projects); `docs/checklists/M5.md` for the owner.
- Done when:
  - [ ] The council can do every action of M5-5 and M5-6 from the window in the mock.
  - [ ] The owner confirms the council flow in game. *(in game)*
- Tests: `Tests/test_ui_council.lua`.
- Docs: wiki **Council** (EN + IT), README features (EN + IT), CHANGELOG.
- Real client: the whole checklist.
- Suggested model/effort: `sonnet` / medium
