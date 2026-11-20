# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Design

- Functional and technical analysis in `docs/ANALISI.md` (Italian): domain model, the guild's rules as a configurable engine, loot session flow, mandatory addon and the `/raid` notice, upgrade hints, roster and rotation, history and the community-site export, architecture, localization, Material Design 3 interface, risks, milestones and open questions.

### Workflow

- M0-0: the development workflow, adapted from Azeroth Accord. `CLAUDE.md` (languages, where things are, the per-step automation, privacy and noreply rules, the "not verified in game" rule); `tools/ship_step.py` (one noreply squashed commit, push, pull request, wait for CI, fast-forward of `main`; only `git fetch origin` when `main` is checked out in another worktree), `tools/check_docs.py` (links, wiki sidebar and EN/IT twins, ADR index, roadmap format, privacy, LF), `tools/check_pr_docs.py` (docs rule) and `tools/sync_wiki.py` (`--warn-if-missing`); CI workflows `ci.yml` (Tests, and Lua tests that pass with a notice until `Tests/` exists), `docs-check.yml` and `wiki-sync.yml`, actions pinned by SHA; `.gitattributes` for LF endings.
- M0-0: the roadmap split into 65 steps, one session and one pull request each: `ROADMAP.md` and `docs/roadmap/M0-spike.md` … `M7-release.md`, each step with branch, dependencies, scope, acceptance criteria, tests, docs, real-client checks and a suggested model/effort.
- M0-0: ADRs 0001 (git flow, CI and automated shipping), 0002 (bilingual wiki generated from `docs/wiki/`), 0003 (documentation languages); `README.md` and `README.it.md`; the bilingual wiki skeleton (Home, Installation, sidebar, footer).
- M0-0: issues [#2](https://github.com/Finland6738/finland-dragon-credit-points/issues/2) (open question 8, stat weights and BiS lists) and [#3](https://github.com/Finland6738/finland-dragon-credit-points/issues/3) (open question 10, `start` / `kind` in the site's `loot.json`) with options and reversible defaults, referenced in `docs/ANALISI.md` §13.
- Not verified: nothing here needs the game client. The wiki is not published yet: GitHub creates the wiki repository only after the owner saves its first page, and until then the `Wiki sync` workflow passes with a warning.
