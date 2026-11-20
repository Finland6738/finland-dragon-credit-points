# Roadmap

This page is the index and the rules every step follows. **The development steps of each milestone are in [docs/roadmap/](docs/roadmap/README.md)**, one file per milestone; the analysis behind the plan is [docs/ANALISI.md](docs/ANALISI.md) (Italian, §12).

## Milestones

| Milestone | Steps | Content | Exit criterion |
|---|---|---|---|
| **[M0 – Workflow and spike](docs/roadmap/M0-spike.md)** | M0-0 … M0-7 | The development workflow; a probe addon (not distributed) for master loot, the loot window, rolls in instances, `RAID` addon messages, item stats, specializations, guild ranks, calendar | probe and `docs/spike/README.md` ready; results pending the owner's run |
| **[M1 – Foundations](docs/roadmap/M1-foundations.md)** | M1-1 … M1-8 | TOC, Ace3, offline tests, Compat, Config, Log, Locale (itIT + enUS), codec and guarded transport, theme, empty window | the addon loads; `/fdcp` opens an empty themed window |
| **[M2 – Engine and ledger](docs/roadmap/M2-engine-ledger.md)** | M2-1 … M2-7 | Classifier, pricing, priority, ledger, seasons and late joiners, rules, presets and permissions, session state machine | every rule works offline; the three regulation examples pass |
| **[M3 – Roster and nights](docs/roadmap/M3-roster-nights.md)** | M3-1 … M3-9 | Guild ranks, pool, mains and alts, nights, lineup, bench, attendance per boss, addon check and `/raid` notice, credits table | the ML opens and closes a night and knows who lacks the addon |
| **[M4 – Loot session](docs/roadmap/M4-loot-session.md)** | M4-1 … M4-9 | Session protocol, loot source, roll listener, session controller, ML window, player popup, delivery, announcements | a whole boss handled by the addon |
| **[M5 – Upgrades and council](docs/roadmap/M5-upgrades-council.md)** | M5-1 … M5-8 | Upgrade score and verdicts, weights and wishlist, council flags, interventions and vote, legendaries, BoE and bank | the council works from the addon |
| **[M6 – History and export](docs/roadmap/M6-history-export.md)** | M6-1 … M6-8 | History views, log and audit, Discord / CSV / JSON and site export, officer sync, credits for members, backup | the Discord table comes out of the addon |
| **[M7 – Polish and release](docs/roadmap/M7-release.md)** | M7-1 … M7-8 | Material Design polish, settings and permissions, profiles, diagnostics, performance, packaging, manual | first release for the guild, `v1.0.0` |

M2 and M3 may run in either order after M1; M4 depends on M0, M2 and M3. **Next step: M0-1.**

## The spike and plan B

M0 needs the real game client, which a session cannot run: its steps deliver the probe and the procedure, with the result "probe ready, results pending owner run". **Until the owner reports the spike results, later steps proceed with plan A plus the plan-B fallbacks of [§11](docs/ANALISI.md#11-rischi)** (delivery by trade, rolls read after the lockdown, sessions only after `ENCOUNTER_END`, item-level verdicts). Step M0-7 folds the results in once they exist; sessions skip it until then.

## Rules for every step

1. `git fetch origin`; take the next unticked step and branch from `origin/main` (`step/m<N>-<k>-<name>`). One step per session and per pull request; open an issue for anything outside it.
2. Update in the same branch: the step's checkboxes, `CHANGELOG.md`, the affected analysis sections and ADRs, `README.md` and `README.it.md` when features or status change, and **`docs/wiki/` in both languages for anything a user can see**.
3. Run `python -I -X utf8 tools/check_docs.py` (and the addon tests from M1-2).
4. Ship without asking: `python -I -X utf8 tools/ship_step.py --title "M<N>-<k>: <summary>" --body-file <pr.md>` squashes the step into one noreply commit, pushes, opens the pull request, waits for CI and fast-forwards `main` to it ([ADR 0001](docs/adr/0001-git-flow-and-automated-shipping.md)). The wiki is published automatically after the merge.
5. The pull request and the changelog entry say honestly what was **not** verified in the real client; the step ships anyway.
6. Open questions of the owner are never decided alone: an issue with the options and a reversible default ([#2](https://github.com/Finland6738/finland-dragon-credit-points/issues/2) stat weights, [#3](https://github.com/Finland6738/finland-dragon-credit-points/issues/3) site format).
