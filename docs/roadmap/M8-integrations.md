# M8 — Integrations

**Goal:** other addons read FDCP's data through a public, read-only, versioned API, never through its SavedVariables. FDCP never depends on them and never reads their data ([ADR 0009](../adr/0009-public-read-only-api.md), [`docs/ANALISI.md` §8.6, §13 question 6](../ANALISI.md#86-api-pubblica-per-altri-addon)). Since 2026-11-24 the milestone also holds the raid readiness check the owner asked for: the master looter sees the missing enchants and consumables of the raid and notifies the players ([ADR 0010](../adr/0010-self-reported-transient-readiness.md), [`docs/ANALISI.md` §4.2](../ANALISI.md#42-controllo-di-prontezza-del-raid-m8-2-m8-3)).

**Exit criterion:** the API is complete in code with green tests and documented in the wiki in both languages. Azeroth Accord can read it from its M10.2 and M11.7 steps; that side is Accord's work, not FDCP's. The readiness check runs offline on a simulated raid (M8-2), and the master looter's tab shows it and notifies the raid (M8-3).

### M8-1 — Public read-only API for other addons
- Branch: `step/m8-1-public-api`
- Depends on: M6-5, M6-6, M3-7, M3-3, M7-2
- Analysis: §8.6, §13 (question 6 revised on 2026-11-24)
- Scope: owner decision of 2026-11-24 (Accord SPEC-10 Q10). New `App/PublicAPI.lua` defines the global `FinlandDragonCreditPointsAPI`:
  - `API_VERSION` (an integer, 1), `IsReady`, `GetVersion` and `GetSource` (`LEDGER` on an officer's client, `SNAPSHOT` on a member's client);
  - `GetSeason` (id, name, state);
  - `GetPool` and `GetMember`: per main, the character, faction, class, role, MS1, MS2, OS, status, alts, the other-faction main and the availability days;
  - `GetCredits` and `GetCreditList`: credits and queue place;
  - `GetNight`: instance, size, difficulty, and the raid and bench lists, without attendance;
  - `GetRules`: the preset, the main costs and the penalties;
  - `RegisterCallback` and `UnregisterCallback` for `READY`, `SEASON_CHANGED`, `POOL_CHANGED`, `CREDITS_CHANGED`, `NIGHT_CHANGED` and `RULES_CHANGED`.

  Every getter returns a copy, never raises, and gives `nil` or an empty list for data this client does not have. A member's client exposes only what the read-only credits table carries. Attendance and absences are never exposed.
- Done when:
  - [x] Copies: changing what a getter returned changes nothing in FDCP; the API table ignores writes; wrong arguments and internal errors give `nil` or the empty fallback.
  - [x] A member's client gives the snapshot's season, pool, credits and places, the same numbers as the officer's, no night, no MS2 / OS / availability, and the default rules marked `DEFAULT`; an officer's client gives the ledger's data, and the night's raid and bench lists, never the absent list.
  - [x] Before the guild roster is read, every getter gives `nil` or an empty list; `READY` fires once the roster is read.
  - [x] Callbacks fire once per change and only for the data that changed; a failing callback is counted and the others still run; an unregistered callback is not called again.
  - [x] ADR 0009, analysis §8.6 and §13, wiki **API for Other Addons** (EN + IT), README (EN + IT), CHANGELOG.
  - [ ] In the game: another addon (Azeroth Accord, or a `/run` script) reads the table on an officer's client and on a member's client, and the callbacks fire after a real night. *(in game)*
- Tests: `Tests/test_public_api.lua` (the global table, before ready, officer and member on the network simulator, copies, callbacks).
- Docs: ADR 0009; analysis §8.6, §13; wiki **API for Other Addons**, Home, Privacy and Data, sidebar (EN + IT); README (EN + IT); CHANGELOG.
- Real client: another addon reading the global; the load order of the two addons; the ticker's cost in a raid.
- Suggested model/effort: `opus` / high

### M8-2 — Raid readiness data
- Branch: `step/m8-2-readiness-data`
- Depends on: M3-5, M3-6, M7-2, M4-1
- Analysis: §4.2, §8.4, §8.6, §10, §11; [ADR 0010](../adr/0010-self-reported-transient-readiness.md)
- Scope: owner request of 2026-11-24, the data half of the readiness check (no UI). Every raider's own client describes itself; the master looter's client asks and evaluates.
  - `Data/Readiness.lua`: the enchantable slots, the consumable categories with their item ids (`FOOD_BUFF`, `FOOD`, `WATER`, `POTION`, `FLASK`, `AMMO`, `PET_FOOD`), the buff spell ids (`WELL_FED`, `FLASK`, `ELIXIR`) and the mana classes, all **to verify on Forever**.
  - `Core/Compat.lua`: `Item.EquippedLinkState`, `Item.Count` (`C_Item.GetItemCount`), `Aura.PlayerBuffSpellIDs` (`C_UnitAuras.GetBuffDataByIndex`, `GetAuraDataByIndex` as the fallback), `Group.RaidRosterRow` gives `isML`; the API probe lists the new calls.
  - `Adapters/SelfCheck.lua`: the snapshot (enchant yes / no / unknown per slot, buff kinds, counts of the categories asked only), never in combat or during an encounter, unreadable values as unknown.
  - `Domain/Readiness.lua` (pure): the rules section `readiness` (`enabled`, `slots`, `needs` with `classes` / `roles` / `mana` filters, reversible defaults), `ValidateConfig`, `Applies`, `Categories`, `EnchantOf`, `Evaluate` (OK / WARN / MISSING / UNKNOWN with the missing slots and categories), `Summary`, the wire `Pack` / `Read`. `Domain/Rules.lua` gains the section; `Rules.Stored` leaves it out of a `CONFIG_CHANGED` while it is the default, so older officers still read the rules.
  - `Net/Readiness.lua`: `RDYQ` on `RAID`, `RDY` whispered to the asker; answered only to the raid leader, an assistant, the master looter or `raid.addonCheck`; deferred in combat; asker gap 30 s, answer gap 20 s per asker, transport rates, 60 s lifetime.
  - `App/ReadinessCheck.lua`: `Request`, `Rows`, `Row`, `Summary`, the reasons of an unknown row (`NOT_ASKED`, `WAITING`, `NO_ADDON`, `OFFLINE`, `NO_ANSWER`), bus event `READINESS_CHANGED`. Transient: nothing in the ledger, the saved data, the exports or the public API.
- Done when:
  - [x] The verdict: no snapshot is UNKNOWN; a missing enchant is MISSING on its slot; a low count is WARN; an active buff meets its category; an unreadable value is UNKNOWN and turns the raider WARN; class, role and mana filters; the larger minimum wins.
  - [x] The snapshot on the mock client: enchants by slot (empty slots, a held-in-off-hand item and non-enchant slots not listed), buff kinds, counts of the categories asked only; nothing in combat or during an encounter; hidden slots, auras and counts unknown; a client without the aura or count call still answers.
  - [x] The round trip on the network simulator: the officer asks, the raiders whisper, the table shows each verdict and the unknown reasons; throttling on both sides; only allowed askers are answered; an answer waits out combat and expires; damaged, misrouted and stale answers are refused.
  - [x] The rules: valid defaults, field codes for damaged requirements, the section left out of the ledger while it is the default and kept when changed.
  - [x] ADR 0010, analysis §4.2, §8.6, §10, §11, §12, the checklist [`docs/checklists/M8.md`](../checklists/M8.md), CHANGELOG, README (EN + IT).
  - [ ] In the game: the item and spell ids of `Data/Readiness.lua`, `C_Item.GetItemCount` and `C_UnitAuras.GetBuffDataByIndex` on Forever, which auras are secret, the whispered answers of a 40-player raid (checklist M8, section 1). *(in game)*
- Tests: `Tests/test_readiness.lua` (rules, verdict, links and slots, wire form, the snapshot on the mock client, the round trip on the network simulator).
- Docs: ADR 0010 and the ADR index; analysis §4.2, §8.6, §10, §11, §12; `docs/checklists/M8.md`; CHANGELOG; README (EN + IT); no wiki page yet (nothing visible to players until M8-3).
- Real client: everything listed in the in-game box above.
- Suggested model/effort: `opus` / high

### M8-3 — Readiness tab and notify button
- Branch: `step/m8-3-readiness-tab`
- Depends on: M8-2, M3-6, M7-1, M7-2
- Analysis: §4.1 (the `/raid` notice), §4.2, §9, §10
- Scope: the visible half of the readiness check, built on M8-2's `ns.ReadinessCheck` (no protocol change).
  - **Where.** A new sub-tab **Roster › Readiness** next to **Roster › Addon** (`UI/AddonPanel.lua` is the model), shown to whoever `ReadinessCheck:CanManage()` allows (the runner of the night or `raid.addonCheck`); others do not see it. Outside a raid it says so and the buttons are off.
  - **Check button.** Calls `ReadinessCheck:Request()`. While `ReadinessCheck:Wait()` > 0 the button shows the seconds left; a refusal code (`NOT_IN_RAID`, `DISABLED`, `TOO_SOON`, the permission codes, a transport reason) becomes a locale message.
  - **Table.** One row per `ReadinessCheck:Rows()` entry: name (class colour), a status pill (OK / WARN / MISSING / UNKNOWN in the theme's colours), the missing enchants as slot names (`result.enchants`, a locale key per slot: head, shoulder, chest, legs, feet, wrist, hands, back, main hand, off hand, ranged), the consumables as "category have/need" (`result.items`, a locale key per category code; `AMMO` counts pieces). An UNKNOWN row shows its `reason` (`NOT_ASKED`, `WAITING`, `NO_ADDON`, `OFFLINE`, `NO_ANSWER`). Sort by status (MISSING first), then name; a summary line from `ReadinessCheck:Summary()` ("31 ok · 5 warn · 3 missing · 1 unknown", answered / asked). Refresh on the bus event `READINESS_CHANGED`. Uses `UI/Widgets/DataTable.lua` and the site style (`docs/specs/ui-style.md`).
  - **Notify button.** Reuses the M3-6 notice path (`Domain/Notice.lua` splitting, `App/AddonNotice.lua` protections: never during a boss, one notice per `notice.minutes`, always from a click, the chat lockdown): (1) one short `/raid` summary, for example `[FDCP] Readiness: 3 missing, 5 low. Check your whispers.`; (2) one whisper per player whose row is MISSING or WARN, built from `result.enchants` and `result.items` in the language of the player who clicks, split at 255 bytes, for example `[FDCP] Missing: enchant wrist, hands; potions 0/2; flask 0/1`. UNKNOWN rows get no whisper (the `/raid` line may name how many are unknown). Add a pure `Domain/Readiness` helper (or a new pure module) that turns a verdict into message parts, with tests. Record the notice in the character's notice log like M3-6; nothing in the ledger.
  - **Rules form.** A page **Readiness** in `Domain/RuleFields.lua` / `UI/Windows/RulesForm.lua`: `readiness.enabled`, the slots to enchant (one switch per slot of `ReadinessData.SLOTS`; the hunter-only ranged slot keeps its class filter), and per category its minimum (0 = not required) and, where the defaults have one, its filter (mana users, hunters). Keep any other filters the GM's rules already carry. Saving goes through `SettingsController:ApplyRules` (GM only, confirmation with an open season). Remove the `readiness` exception of the test "covers every section of the rules" in `Tests/test_ui_settings.lua`.
  - **Locale.** Every visible string through a key in `enUS` and `itIT` (slot names, category names, statuses, reasons, button labels, refusals, the two message templates).
- Done when:
  - [x] The tab: visible only to allowed players; Check with the wait and the refusal codes; one row per raid member with status, slots, categories and reasons; the summary; refresh on `READINESS_CHANGED`.
  - [x] Notify: the `/raid` summary and one whisper per MISSING / WARN player, split at 255 bytes, in the clicking player's language; the M3-6 protections; nothing in the ledger.
  - [x] The rules form page: every value of the `readiness` section, validated by `Rules.Validate`, saved through `ApplyRules`.
  - [x] Wiki: the page for the readiness tab (EN + IT), the Settings page's rules list, Home and sidebar; README (EN + IT); CHANGELOG.
  - [ ] In the game: the tab, the Check and Notify buttons, the whispers and the rules page in a real raid (checklist M8, section 2). *(in game)*
- As built (2026-11-24): the table has a column per consumable category with its own badge ("OK", have/need, "?" or "-" when the raider is not asked for it) next to the status and the missing enchants; the notify button waits in a queue behind a boss fight or the chat lockdown instead of refusing (dropped after 10 minutes), leaves one message every 0.4 s and asks for a confirmation in the tab; the guild's wording is `readiness.texts` (`raid`, `whisper`), part of the `readiness` section (the defaults still leave the ledger untouched); the rules page has 24 fields (the switch, a switch per slot, a minimum per category, the mana and hunter filters, the two texts). New files: `Domain/ReadinessNotice.lua` (pure), `App/ReadinessNotifier.lua`, `UI/ReadinessPanel.lua`; tests in `Tests/test_readiness_notice.lua`.
- Tests: a UI test like `Tests/test_ui_roster.lua` (the tab on the mock client with a simulated raid), the message parts (pure), the notify path on the network simulator, the rules form fields.
- Docs: analysis §4.2 (mark the UI as done), §10 (the rules page); wiki (EN + IT); `docs/checklists/M8.md` section 2; README (EN + IT); CHANGELOG.
- Real client: the tab, the buttons, the `/raid` line and the whispers in a raid; the chat limits of 40 whispers in a row.
- Suggested model/effort: `opus` / high
