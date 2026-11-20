# M0 — Workflow and spike in the real client

**Goal:** set up the development workflow, then answer in the real WoW Forever client the questions the analysis cannot answer offline ([`docs/ANALISI.md` §1 "Non ancora verificato", §11, §12](../ANALISI.md#12-roadmap-proposta)).

**Who:** sessions build the probe and the procedure; **the owner runs it in game** (ideally as raid leader and master looter, with a second character or player for the two-client checks) and reports the results.

**Exit criterion:** the probe addon and `docs/spike/README.md` are ready (**"probe ready, results pending owner run"**). The milestone is complete once the owner's results are in `docs/spike/M0-results.md` and M0-7 has updated the analysis and the plan; later milestones do not wait for that and use plan A plus the plan-B fallbacks of §11 meanwhile.

The probe addon `FDCP_Probe` lives in `tools/probe/`, is **never distributed**, wraps every call in `pcall`, never compares a secret value, uses the test prefix `FDCPP` (never the real `FDCP1`), and never prints or stores player or guild names (counts and shapes only).

### M0-0 — Development workflow and step roadmap
- Branch: `step/m0-0-workflow`
- Depends on: —
- Analysis: §8.5, §12, §13
- Scope: `CLAUDE.md`; `tools/ship_step.py`, `tools/check_docs.py`, `tools/check_pr_docs.py`, `tools/sync_wiki.py` (adapted from Azeroth Accord, worktree-safe local `main`); `.github/workflows/` (`ci.yml` with Tests and Lua tests, `docs-check.yml`, `wiki-sync.yml`, actions pinned by SHA); `ROADMAP.md` and `docs/roadmap/`; `README.md` / `README.it.md`; `CHANGELOG.md`; ADRs 0001–0003; the bilingual `docs/wiki/` skeleton; issues for open questions 8 and 10.
- Done when:
  - [x] The workflow files exist and `check_docs.py` passes.
  - [x] Every milestone of §12 is split into numbered steps with a model/effort hint.
  - [x] Open questions 8 and 10 have issues with options and a reversible default, referenced in §13.
  - [x] The step is shipped to `main` by `ship_step.py` with a noreply commit.
- Tests: `check_docs.py` (links, wiki, ADR index, roadmap format, privacy, LF).
- Docs: everything above.
- Real client: nothing.
- Suggested model/effort: `sonnet` / high

### M0-1 — Probe addon skeleton and spike procedure
- Branch: `step/m0-1-probe-skeleton`
- Depends on: M0-0
- Analysis: §1, §12 (M0)
- Scope: `tools/probe/FDCP_Probe/` (`FDCP_Probe.toc` and `FDCP_Probe_Camelot.toc`, Interface 16001), a registry of checks, `/fdcpp list | run <id> | runall | export | reset`, results `{id, result, details, build, time}` in `FDCP_ProbeDB`, an export frame with all results as selected text; event recorder (event name, time, encounter state, restriction state, secret flags — never names); `tools/install_probe.py` (links or copies the probe into `<WoW folder>/_forever_/Interface/AddOns/`, path from `tools/local.example.ini` → `*.local.ini`, git-ignored); `docs/spike/README.md` with the in-game procedure skeleton (English, with the steps in Italian too) and `docs/spike/M0-results.md` as an empty results template (check id, plan A result, plan B needed?).
- Done when:
  - [ ] The probe loads on Forever and `/fdcpp list` lists the checks. *(in game)*
  - [x] Offline: files, commands, check registry, export frame and install script exist; `check_docs.py` passes.
- Tests: a small Lua syntax check of the probe files (luac-free: parsed with Python `lupa` if available, else skipped with a notice).
- Docs: `docs/spike/README.md`, `docs/spike/M0-results.md`, CHANGELOG.
- Real client: everything; result "probe ready, results pending owner run".
- Suggested model/effort: `sonnet` / medium

### M0-2 — Master loot and the loot window (S1, S2)
- Branch: `step/m0-2-master-loot`
- Depends on: M0-1
- Analysis: §1 (master loot, loot window), §4, §11 risk 1
- Scope: checks that record presence and behaviour of `C_PartyInfo.GetLootMethod/SetLootMethod`, `C_Loot.IsLegacyLootModeEnabled`, `IsMasterLooter`, `GetLootThreshold`, `OPEN_MASTER_LOOT_LIST` / `UPDATE_MASTER_LOOT_LIST`; on `LOOT_OPENED`: `GetNumLootItems`, `GetLootSlotLink`, `GetLootSlotInfo`, `GetLootSourceInfo` (source GUID shape → boss); `GetMasterLootCandidate` list size; `/fdcpp give <slot> <candidate#>` calls `GiveMasterLoot` on a test drop and records `LOOT_SLOT_CLEARED` and `CHAT_MSG_LOOT`; `ADDON_ACTION_BLOCKED` / `FORBIDDEN` log.
- Done when:
  - [ ] S1: can the loot method be set to master loot in a Forever raid (10/20/40, Normal/Veteran)? *(in game)*
  - [ ] S2: are slots, sources and candidates readable, and does `GiveMasterLoot` deliver from an addon click? *(in game)*
  - [x] Offline: checks and the procedure section exist; `check_docs.py` passes.
- Docs: `docs/spike/README.md` S1–S2 procedure (both languages), CHANGELOG.
- Real client: everything (plan B if negative: delivery by trade, M4-7).
- Suggested model/effort: `sonnet` / medium

### M0-3 — Rolls, system messages and encounters (S3)
- Branch: `step/m0-3-rolls`
- Depends on: M0-1
- Analysis: §1 (roll, restrictions), §3.4, §11 risk 2
- Scope: `/fdcpp roll` calls `RandomRoll(1, 100)`; `CHAT_MSG_SYSTEM` parsed with a pattern built from the global `RANDOM_ROLL_RESULT` (never written by hand); records whether the message text is a secret value (`issecretvalue`) outside instances, inside an instance between bosses, during an encounter (`IsEncounterInProgress`, `ENCOUNTER_START/END`) and right after `ENCOUNTER_END`; `C_RestrictedActions` / `ADDON_RESTRICTION_STATE_CHANGED` timeline; `CHAT_MSG_LOOT` pattern from `LOOT_ITEM` globals.
- Done when:
  - [ ] S3: rolls of other raiders are readable (and not secret) after `ENCOUNTER_END` and between bosses. *(in game)*
  - [x] Offline: checks, pattern builder and procedure section exist; `check_docs.py` passes.
- Docs: `docs/spike/README.md` S3, CHANGELOG.
- Real client: everything (plan B: rolls read once the lockdown ends, M4-3).
- Suggested model/effort: `sonnet` / medium

### M0-4 — Addon messages in raid (S4)
- Branch: `step/m0-4-addon-messages`
- Depends on: M0-1
- Analysis: §1 (addon messages), §4.1, §8.4, §11 risk 3
- Scope: `C_ChatInfo.RegisterAddonMessagePrefix("FDCPP")`; `/fdcpp ping raid|guild|officer|whisper` sends numbered messages and records send results (`Enum.SendAddonMessageResult`), `InChatMessagingLockdown()`, `AreOutgoingAddonChatMessagesRestricted()` and delivery on a second client (sequence numbers, delays, losses) outside instances, between bosses, during an encounter and after `ENCOUNTER_END`; a 255-byte payload and a burst of 30 messages for throttling; `C_EncodingUtil` CBOR + Deflate + Base64 round trip.
- Done when:
  - [ ] S4: `RAID` messages pass between bosses and after `ENCOUNTER_END`; lockdown timings known. *(in game)*
  - [x] Offline: checks and procedure section exist; `check_docs.py` passes.
- Docs: `docs/spike/README.md` S4, CHANGELOG.
- Real client: everything, with two clients (plan B: queue that waits, sessions only after encounters).
- Suggested model/effort: `sonnet` / medium

### M0-5 — Items, stats and specializations (S5, S6)
- Branch: `step/m0-5-items-stats`
- Depends on: M0-1
- Analysis: §1 (items, specializations), §5.1, §5.3, §11 risk 4
- Scope: `/fdcpp item <link>` records `C_Item.GetItemInfoInstant` (classID, subclassID, equipLoc), `C_Item.GetItemInfo` cache misses and `ITEM_DATA_LOAD_RESULT`, `C_Item.GetDetailedItemLevelInfo`, `C_Item.GetItemStats`, `C_Item.GetItemStatDelta` against the equipped piece, `IsEquippableItem`, `DoesItemContainSpec`, `GetItemSpecInfo`; compares the stats with the tooltip (`C_TooltipInfo`) for raid pieces inside and outside the raid ("contextual" bonuses); `C_SpecializationInfo.GetSpecialization` / `GetSpecializationInfo`; quest items and items that start a quest.
- Done when:
  - [ ] S5: stats and item levels of raid items match what the game applies in raid. *(in game)*
  - [ ] S6: specializations exist and are readable in Forever. *(in game)*
  - [x] Offline: checks and procedure section exist; `check_docs.py` passes.
- Docs: `docs/spike/README.md` S5–S6, CHANGELOG.
- Real client: everything (plan B: item-level-only verdict, declared spec only).
- Suggested model/effort: `sonnet` / medium

### M0-6 — Guild ranks, calendar, locale and procedure finalisation (S7, S8)
- Branch: `step/m0-6-guild-calendar-procedure`
- Depends on: M0-2, M0-3, M0-4, M0-5
- Analysis: §3.9, §6 (calendar), §8.5
- Scope: checks for `IsGuildLeader`, `GetGuildRosterInfo` (rank index of self, rank count, roster load timing), `GuildControlGetNumRanks` / `GuildControlGetRankName`, `C_GuildInfo.IsGuildOfficer`, `CanEditOfficerNote`; `C_Calendar` raid events (official raid event readable, attendees count); `GetLocale`; `SendChatMessage` to `RAID` from a click (hardware event needed?). Final pass over `docs/spike/README.md`: preparation, order of the runs, how to export and send the results, a results table per check with plan A / plan B and the steps each answer affects.
- Done when:
  - [ ] S7: rank checks work for GM, officer and member. *(in game)*
  - [ ] S8: calendar events and chat sending from a click. *(in game)*
  - [x] Offline: the complete procedure and results template exist in both languages; `check_docs.py` passes; result "probe ready, results pending owner run".
- Docs: `docs/spike/README.md`, `docs/spike/M0-results.md`, wiki untouched, CHANGELOG.
- Real client: everything.
- Suggested model/effort: `sonnet` / medium

### M0-7 — Fold in the spike results *(owner)*
- Branch: `step/m0-7-spike-results`
- Depends on: M0-6 and **the owner's probe run** (skip this step until the owner has reported the results; take the next unticked step meanwhile)
- Analysis: §1, §11, §12
- Scope: write the owner's results into `docs/spike/M0-results.md`; update §1 "Non ancora verificato", §11 and the affected steps of M1–M5 (go / plan B per area); new ADRs where a plan B becomes the plan.
- Done when:
  - [ ] Every S1–S8 check has a result and a go / plan-B decision.
  - [ ] The analysis, the roadmap and the ADR index reflect the decisions.
- Docs: analysis, roadmap, ADRs, README status, CHANGELOG.
- Real client: the results come from it.
- Suggested model/effort: `opus` / high
