# M2 — Rules engine and ledger

**Goal:** every rule of the guild works offline: item classification and cost, the award algorithm with tiers, tie-breaks and rerolls, the event ledger with computed credits, seasons and late joiners, the configurable rules, presets and rank permissions, and the session state machine ([`docs/ANALISI.md` §2, §3, §8.3](../ANALISI.md#3-regole-dal-regolamento-al-motore-configurabile)).

**Exit criterion:** the three examples of the regulation (ring, shoulder, cloak) and every rule of the "Patto" preset pass as offline tests; `Domain/` never calls the game.

Everything in this milestone is pure Lua in `FinlandDragonCreditPoints/Domain/`, tested with `Tests/`. No real client needed.

### M2-1 — Item classifier and pricing
- Branch: `step/m2-1-pricing`
- Depends on: M1-2
- Analysis: §3.1, §3.2
- Scope: `Domain/Classifier.lua` (`classID` / `subclassID` / `equipLoc` → category through an editable table; quest item = Quest class **or** starts a quest **or** in the season's token list; quality threshold "not tracked"), `Domain/Pricing.lua` (per-item override → category × quality matrix → response multiplier; raid-size and difficulty multipliers; decimal costs).
- Done when:
  - [x] Every cell of the §3.2 matrix and the override order are covered by tests.
- Tests: `Tests/test_pricing.lua`.
- Docs: CHANGELOG.
- Real client: nothing.
- Suggested model/effort: `opus` / high

### M2-2 — Priority and the award proposal
- Branch: `step/m2-2-priority`
- Depends on: M2-1
- Analysis: §3.3, §3.4, §3.8
- Scope: `Domain/Priority.lua`, a pure function from (responses, rolls, credits, config) to a result: tiers from the lowest, valid rolls only (1–100, first of the round, present, addon active), metric (credits, credits per night, roll only), tie-breaks, reroll rounds among the tied only, the next tier when a tier is empty, the fallback (BoE → bank, disenchant, free roll, ML); the **proposal** `{winner, cost, reason codes, flags}` with neutral reason codes (`LOWER_CREDITS`, `HIGHER_ROLL`, `REROLL_WON`, `OFFSPEC_TIER`, …), never sentences.
- Done when:
  - [x] The three regulation examples pass: ring (same credits, 76 wins), shoulder (fewer credits, 34 wins), cloak (tie on credits and roll, reroll between Bryn and Corin).
  - [x] Off-spec opens only when no main-spec; BoE without MS goes to the bank fallback.
- Tests: `Tests/test_priority.lua`.
- Docs: CHANGELOG.
- Real client: nothing.
- Suggested model/effort: `opus` / high

### M2-3 — The event ledger
- Branch: `step/m2-3-ledger`
- Depends on: M1-4
- Analysis: §0 point 2, §7, §8.3
- Scope: `Domain/Ledger.lua`: immutable events `{id, ts, author, season, type, payload}` with ids unique per author (author + sequence), append and idempotent merge, the event types of §8.3, compensation instead of deletion (`AWARD_VOIDED`, `CREDITS_ADJUSTED`), credits computed as the sum of the season's events, periodic snapshots that give the same totals, schema version of the payloads.
- Done when:
  - [x] Credits from snapshot + tail equal credits from the full ledger; merging the same events twice changes nothing; a void restores the previous credits.
- Tests: `Tests/test_ledger.lua` (including random event sequences).
- Docs: CHANGELOG.
- Real client: nothing.
- Suggested model/effort: `opus` / high

### M2-4 — Seasons, members and late joiners
- Branch: `step/m2-4-season`
- Depends on: M2-3
- Analysis: §2, §3.1, §3.5, §6 (pool, two mains per faction)
- Scope: `Domain/Season.lua` (open/close, the pack of instances 10/20/40 with one credit table for Normal and Veteran, `startCredits`), `Domain/Members.lua` (main only, alts linked to a main, one main per faction), late joiners (`average` | `median` | `min` | `zero` | `fixed`, rounding, base "members with at least N nights") written as `MEMBER_JOINED{initialCredits}` so the value stays stable.
- Done when:
  - [x] A late joiner gets the floor of the roster average and keeps it when the average changes later.
- Tests: `Tests/test_season.lua`.
- Docs: CHANGELOG.
- Real client: nothing.
- Suggested model/effort: `opus` / high

### M2-5 — Rules, presets and rank permissions
- Branch: `step/m2-5-rules-permissions`
- Depends on: M2-2, M2-4
- Analysis: §3.1, §3.9, §10
- Scope: `Domain/Rules.lua` (the configuration schema of §3 with validation and defaults), `Domain/Presets.lua` ("Patto", "Solo roll", "Loot council puro", "EPGP semplice"), `Domain/Permissions.lua` as pure functions: permission → minimum rank **index**; `config.rules` and `config.permissions` GM only; an event is accepted only if its author had the required rank when it was written; `CONFIG_CHANGED` / `PERMISSIONS_CHANGED` only from the GM; open-season changes need an explicit confirmation flag.
- Done when:
  - [ ] Events from an author without the rank are refused; a config event from a non-GM is refused; renamed ranks change nothing.
- Tests: `Tests/test_rules.lua`, `Tests/test_permissions.lua`.
- Docs: CHANGELOG.
- Real client: nothing.
- Suggested model/effort: `opus` / high

### M2-6 — Session state machine
- Branch: `step/m2-6-session-fsm`
- Depends on: M2-2, M2-3
- Analysis: §4 (diagram and details)
- Scope: `Domain/SessionFSM.lua`: states waiting → collecting → announcing → roll tier N → computing → (reroll | next tier | fallback) → proposal → (confirm | reject | modify with mandatory reason) → assigned → delivered; pause; `session.autoAdvance`; `session.awardMode` `confirm` | `auto` (intervention window) | `council`; serialisable state for `/reload`; produces ledger events (`ITEM_AWARDED` with reason codes, interventions flagged "out of order").
- Done when:
  - [ ] Every transition of the §4 diagram is tested, including reroll, empty tier, reject and modify; a serialised session resumes identically.
- Tests: `Tests/test_session_fsm.lua`.
- Docs: CHANGELOG.
- Real client: nothing.
- Suggested model/effort: `opus` / high

### M2-7 — The loot rules in the manual
- Branch: `step/m2-7-rules-manual`
- Depends on: M2-5
- Analysis: §3
- Scope: wiki pages **Loot Rules** / **Regole del loot** (`Loot-Rules.md`, `Loot-Rules-it.md`): credits, costs per category, main-spec and off-spec, ties and rerolls, late joiners, legendaries and BoE, what the master looter and the council may change; with the three regulation examples, written from the engine's tests; a reason-code → sentence table in the locales so the same words appear in game.
- Done when:
  - [ ] Both wiki pages exist and are in the sidebar; every reason code has an English and Italian sentence.
- Tests: locale check covers the reason codes.
- Docs: wiki (EN + IT), README features, CHANGELOG.
- Real client: nothing.
- Suggested model/effort: `sonnet` / medium
