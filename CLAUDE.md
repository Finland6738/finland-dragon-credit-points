# Instructions for development sessions

Finland Dragon Credit Points (FDCP, `/fdcp`) is a WoW: Forever addon (Interface 16001, 12.0 engine, Lua 5.1, TOC suffix `_Camelot`) that runs a guild's credit-based loot system. The owner speaks Italian: **talk to them in Italian**.

## Languages ([ADR 0003](docs/adr/0003-documentation-languages.md), `docs/ANALISI.md` §8.5)

- **English**: code, code comments, commit messages, pull requests, issues, ADRs, `CHANGELOG.md`, `CLAUDE.md`, the roadmap files.
- **Italian**: the analysis and the specifications (`docs/ANALISI.md`, any later `docs/specs/`), the spike procedure's in-game notes may be bilingual.
- **Both**: `README.md` + `README.it.md`, and the user manual in `docs/wiki/` (every English page `<Page>.md` has an Italian twin `<Page>-it.md`; `check_docs.py` enforces it).
- The addon itself is multilingual (itIT and enUS first): no visible text in code, every string through a locale key.

## Where things are

- Analysis (Italian): `docs/ANALISI.md`. §8 architecture, §8.5 languages, §11 risks and plan-B fallbacks, §12 milestones, §13 open questions.
- Plan: `ROADMAP.md` (index and rules) and one file per milestone in `docs/roadmap/` (`M0-spike.md` … `M7-release.md`).
- Decisions: `docs/adr/` (index in `docs/adr/README.md`; MADR format, English).
- User manual: `docs/wiki/` (the only source of the GitHub wiki, [ADR 0002](docs/adr/0002-github-wiki-generated-from-docs-wiki.md)).
- Spike: `docs/spike/` (in-game procedure and results) and the probe addon in `tools/probe/` (from M0-1).
- WoW Forever API dump: `../WoW-Addons/docs/api.json` (build 1.60.1.70170). **Consult only**, never copy it into this repository. Every new API is checked there and guarded by `Core/Compat.lua`.
- Sister project to copy foundations from: `../azeroth-accord` (same owner, GPL-3.0): `Core/Compat.lua` (guarded calls, secret values, restrictions), the send queue with lockdown wait, the versioned protocol, the offline test rig with `lupa` and the mock client, `tools/` and CI. Copy and adapt (rename identifiers, prefixes, SavedVariables, env vars); the two addons stay independent in game. Accord reads FDCP only through the public read-only API `FinlandDragonCreditPointsAPI` ([ADR 0009](docs/adr/0009-public-read-only-api.md), `App/PublicAPI.lua`); keep it backward compatible and bump `API_VERSION` only on a breaking change.

## Git automation (authorized by the owner, [ADR 0001](docs/adr/0001-git-flow-and-automated-shipping.md))

Every session does **one step** and ships it **without asking** (the PC is unattended):

1. `git fetch origin`; branch from `origin/main`: `step/m<N>-<k>-<name>` for roadmap steps (`fix/…`, `docs/…`, `chore/…` otherwise). Never commit to `main`.
2. Take the **next unticked step** of the current milestone in `docs/roadmap/`. Skip a step marked *(owner)* while it waits for the owner's input (for example the spike results) and take the next one; until the owner reports the spike results, later steps build on plan A plus the plan-B fallbacks of `docs/ANALISI.md` §11.
3. Do the work. In the same branch: tick the step's checkboxes in its milestone file, add an entry to `CHANGELOG.md` ("Unreleased"), update the affected analysis/ADRs (and the ADR index), `README.md` + `README.it.md` when features or status change, and `docs/wiki/` (both languages) for anything a user can see.
4. Run the checks: `python -I -X utf8 tools/check_docs.py` plus the offline addon tests `python -X utf8 Tests/run_tests.py [filter] [-v]` (needs `lupa==2.8`; run `python -X utf8 tools/fetch_libs.py` once for the libraries; no `-I` locally if `lupa` is a user-site install).
5. Write the pull request body in a file (what and why; **what was not verified in the real client**) and ship:
   `python -I -X utf8 tools/ship_step.py --title "M<N>-<k>: <summary>" --body-file <file> --commit "<message>"`
   It runs the checks, squashes the step into one noreply commit on top of `origin/main`, pushes, opens the PR, waits for every CI check and fast-forwards `main` to that exact commit. When `main` is checked out in another worktree (the owner's main checkout) it only runs `git fetch origin`. If it stops, leave the PR open and report why.
6. The wiki is published by the `Wiki sync` workflow after the merge; never edit the wiki on GitHub. Until the owner creates the first wiki page by hand, the sync warns that the wiki repository does not exist and passes.

**Steps that need the real game client.** A session cannot run the game. When a step's result can only be confirmed in game, the PR body **and** the `CHANGELOG.md` entry say explicitly what was **not** verified in game, and the step **still ships** (its "in game" checkboxes stay unticked; the offline ones are ticked).

**Never merge** from the GitHub web UI or with `gh pr merge` (GitHub would author the commit with the owner's personal email): only the fast-forward of `ship_step.py`. Never `--force` on `main`, never rewrite published history, never skip hooks.

**Owner decisions.** Do not decide alone what belongs to the owner (licence, names, scope, rules of the guild, deleting data, the open questions of `docs/ANALISI.md` §13): open a GitHub issue with the options, pick a **reversible** default, write the default and the issue link in §13, and continue. Open now: question 8 (stat weights / BiS import, [#2](https://github.com/Finland6738/finland-dragon-credit-points/issues/2)) and question 10 (`start` / `kind` in the community site's `loot.json`, [#3](https://github.com/Finland6738/finland-dragon-credit-points/issues/3)).

## Privacy

No personal data in the repository: no real names, no personal emails (only GitHub noreply addresses), no personal paths such as drive letters or home folders (write `<WoW folder>`, `../azeroth-accord`, `../WoW-Addons`). `tools/check_docs.py` fails on emails and personal paths. Player names in examples are invented (Aurel, Bryn, Corin…).

Git author and committer are always the noreply identity `Finland6738` / `200480737+Finland6738@users.noreply.github.com` (set in the local git config; `ship_step.py` forces it on the squashed commit and stops if `main` ends up with another address). `prompt.txt` (the owner's notes) and `*.local.json` are git-ignored and never committed.

## Code rules (from M1 on)

- `Domain/` is pure Lua: it never calls the game. Everything that touches the game goes through `Adapters/` and `Core/Compat.lua`.
- Never read or compare a secret value; sessions open after `ENCOUNTER_END`; addon messages wait out the chat lockdown.
- Lua 5.1: no `goto`, no 64-bit integers. Use `C_Item.*`, not the removed globals.
- Credits are never stored: they are computed from the ledger of events. The ledger stores codes and numbers, not sentences.
