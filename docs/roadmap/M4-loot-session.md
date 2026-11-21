# M4 — Loot session

**Goal:** a whole boss run by the addon: drops collected from the corpse, category and cost announced, a popup on every raider's client, server-side rolls, the computed proposal confirmed by the master looter in one click, credits charged and the item delivered ([`docs/ANALISI.md` §4, §8.4](../ANALISI.md#4-flusso-di-una-sessione-di-loot)).

**Exit criterion:** a simulated raid of 40 clients runs a boss end to end offline; in game a whole boss is handled by the addon (owner's check, M4-9).

M4 depends on M0, M2 and M3. Until the spike results arrive, every step builds plan A **and** the plan-B fallback of §11 named in it.

### M4-1 — Session protocol on RAID
- Branch: `step/m4-1-session-protocol`
- Depends on: M3-5, M2-6
- Analysis: §4, §8.4
- Scope: `Net/Protocol.lua` session messages (session opened with items, category and cost; roll opened for item N with tier and timer; response `{response, label, note}`; round closed; proposal; result; session closed), versioned, small; a member may send only their own response; resync of a late joiner or a `/reload` by `WHISPER`; everything through the guarded queue (plan B: sessions only after `ENCOUNTER_END`).
- Done when:
  - [x] A forged response for another player is refused; a client that reloads mid-session resyncs.
- Tests: `Tests/test_protocol_session.lua` (network simulator).
- Docs: §8.4 if the message list changes; CHANGELOG.
- Real client: `RAID` delivery in a raid.
- Suggested model/effort: `opus` / high

### M4-2 — Loot source and item cache
- Branch: `step/m4-2-loot-source`
- Depends on: M2-1, M1-3
- Analysis: §1 (loot window, items), §4 (collection)
- Scope: `Adapters/LootSource.lua` (`LOOT_OPENED` as master looter: slots at or above the threshold, links, source → boss), `Adapters/ItemCache.lua` (`C_Item.GetItemInfo` misses wait for `ITEM_DATA_LOAD_RESULT`), the collection list with the classifier's category and cost for the ML to confirm or correct before the roll (category locked once the roll opens).
- Done when:
  - [x] Collection from a mock corpse produces the expected list; cache misses resolve later.
- Tests: `Tests/test_loot_source.lua`.
- Docs: CHANGELOG.
- Real client: loot window reading (spike S2).
- Suggested model/effort: `sonnet` / medium

### M4-3 — Roll listener
- Branch: `step/m4-3-roll-listener`
- Depends on: M1-3, M3-5
- Analysis: §0 point 3, §4 (rolls), §11 risk 2
- Scope: `Adapters/RollListener.lua`: the `RANDOM_ROLL_RESULT` pattern built from the global string, only 1–100, only after the round opened, the first per player, from a character in the raid **with the addon active**; manual `/roll` from a player without the addon recorded as "discarded roll: addon not active"; secret values never compared (plan B: buffer the system messages and read them once the lockdown ends).
- Done when:
  - [x] Valid, duplicate, out-of-range, early, absent and no-addon rolls are classified correctly in the mock, in English and Italian clients.
- Tests: `Tests/test_roll_listener.lua`.
- Docs: CHANGELOG.
- Real client: roll messages in an instance (spike S3).
- Suggested model/effort: `opus` / high

### M4-4 — Session controller
- Branch: `step/m4-4-session-controller`
- Depends on: M4-1, M4-2, M4-3
- Analysis: §4 (whole flow)
- Scope: `App/SessionController.lua` wiring `Domain/SessionFSM.lua` to the adapters, the protocol and the ledger: waits after `ENCOUNTER_END` and while locked down, auto-advance and pause, timers, rerolls and the off-spec tier started automatically, state saved at every transition and resumed after `/reload` or disconnect, `ITEM_AWARDED` with reason codes on confirm, read-only view for other officers.
- Done when:
  - [x] A simulated boss with five items, a reroll and an empty main-spec tier ends with the right ledger events.
- Tests: `Tests/test_session_controller.lua` (simulator).
- Docs: CHANGELOG.
- Real client: a real boss (M4-9).
- Suggested model/effort: `opus` / high

### M4-5 — Master looter session window
- Branch: `step/m4-5-ml-window`
- Depends on: M4-4, M3-7
- Analysis: §4, §9.3 point 3, §3.4 (confirm, reject, modify); [`docs/specs/ui-style.md`](../specs/ui-style.md) §3, §6
- Scope: `UI/Windows/MLSession.lua`, the **Loot › Session** sub-tab (look per `ui-style.md`, preview `fdcp-loot-session.webp`; the window opens on it while a session runs): items with state on the left; candidates with credits, response, roll and flags on the right; **Open roll**, **Close**, **Pause**; the proposal (who, how much, why, written by the addon) with **Confirm**, **Reject**, **Modify** (new winner or cost, mandatory reason, "out of order" difference shown), **Confirm all** for proposals without flags; the warning "N raid members cannot roll" with the notice button.
- Done when:
  - [ ] The ML can run a whole simulated session from the window; Modify cannot be saved without a reason.
- Tests: `Tests/test_ui_ml_session.lua`.
- Docs: wiki **Master Looter Guide** (EN + IT), CHANGELOG.
- Real client: the window in a raid.
- Suggested model/effort: `sonnet` / high

### M4-6 — Player item popup
- Branch: `step/m4-6-item-popup`
- Depends on: M4-4, M1-7
- Analysis: §5.1 (popup), §6 (MS1 / MS2 buttons); [`docs/specs/ui-style.md`](../specs/ui-style.md) §3 (card, segmented, chips, timer bar, the one neon element)
- Scope: `UI/Windows/MemberLootPopup.lua` (look per `ui-style.md`, preview `fdcp-roll-popup.webp`): stackable cards per item (icon and name in quality colour, slot, comparison tooltip, chip "Weapon · 2 credits"), segmented **Main-spec / Off-spec / Pass** with the optional label (BiS, big upgrade, small upgrade, situational), the **Roll** button calling `RandomRoll(1, 100)`, own credits and estimated queue position, a note field, the timer bar; position and size remembered. No upgrade verdict yet (M5-2).
- Done when:
  - [ ] Responses reach the ML in the simulator; the popup closes when the round closes.
- Tests: `Tests/test_ui_popup.lua`.
- Docs: wiki **Rolling for Loot** (EN + IT), CHANGELOG.
- Real client: the popup in a raid; `RandomRoll` from a click.
- Suggested model/effort: `sonnet` / high

### M4-7 — Delivery
- Branch: `step/m4-7-delivery`
- Depends on: M4-5
- Analysis: §4 (delivery, deferred delivery), §11 risk 1
- Scope: `Adapters/MasterLoot.lua`: **Confirm** charges the credits and calls `GiveMasterLoot(slot, candidate)` in the same click; `CHAT_MSG_LOOT` confirms receipt; deferred delivery when the ML rolls everything at the end of the night (the item is tracked until it changes hands by trade); **plan B** when master loot is not available: the award stays in the ledger and the item is handed over by trade after group loot, with a "to deliver" list.
- Done when:
  - [ ] Both paths (master loot and trade) end with the item marked delivered in the mock.
- Tests: `Tests/test_delivery.lua`.
- Docs: Master Looter Guide (EN + IT), CHANGELOG.
- Real client: `GiveMasterLoot` (spike S2), trade tracking.
- Suggested model/effort: `sonnet` / high

### M4-8 — Raid announcements
- Branch: `step/m4-8-announcements`
- Depends on: M4-4
- Analysis: §4 (announcement, result to the raid), §8.5 (guild language)
- Scope: category and cost of each item and each result announced in `/raid` (on/off, editable text with placeholders), in the guild language chosen by the GM, never during an encounter, from the ML's click when the game needs one; the reason sentence composed from the reason codes.
- Done when:
  - [ ] Announcements are in the guild language whatever the ML's client language, in tests.
- Tests: `Tests/test_announcements.lua`.
- Docs: Master Looter Guide (EN + IT), CHANGELOG.
- Real client: chat sending in a raid.
- Suggested model/effort: `sonnet` / medium

### M4-9 — Full-boss simulation and the M4 checklist
- Branch: `step/m4-9-boss-simulation`
- Depends on: M4-5, M4-6, M4-7, M4-8
- Analysis: §12 (M4 exit)
- Scope: an end-to-end simulation (40 clients, lockdown windows, a member without the addon, a `/reload` mid-session, a tie and a reroll) in `Tests/sim/`; `docs/checklists/M4.md` for the owner (a whole boss in game, plan A and plan B paths).
- Done when:
  - [ ] The simulation passes in CI.
  - [ ] The owner confirms a whole boss handled by the addon. *(in game)*
- Tests: `Tests/test_sim_boss.lua`.
- Docs: checklist, README status (EN + IT), CHANGELOG.
- Real client: the whole checklist.
- Suggested model/effort: `opus` / medium
