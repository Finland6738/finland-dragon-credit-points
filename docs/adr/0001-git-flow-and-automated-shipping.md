# 0001. Git flow, CI and automated shipping of roadmap steps

- Status: Accepted
- Date: 2026-11-20 (adapted from Azeroth Accord, ADR 0012 and 0014 there)

## Context

FDCP is developed one roadmap step at a time, each step in its own automated Claude Code session, often while the owner is away and the PC is unattended. The owner asked that every finished step is committed, pushed, opened as a pull request and merged **without asking**, and that the documentation and the wiki follow every change. The repository is public, so its history must not contain personal email addresses.

## Decision

1. `main` is always working; nobody commits to it directly.
2. One branch per step from an up-to-date `origin/main`: `step/m<N>-<k>-<name>` for roadmap steps (`docs/roadmap/`), `fix/…`, `docs/…`, `chore/…` for the rest. A session takes the next unticked step, and ticks it in the same pull request.
3. Every step updates in the same pull request: `CHANGELOG.md`, the affected analysis and ADRs, both READMEs when features or status change, and `docs/wiki/` (both languages) for anything a user can see.
4. **Checks**: `tools/check_docs.py` (links, wiki sidebar and languages, ADR index, roadmap format, privacy scan, LF endings) locally and in the CI job **Tests**; the CI job **Lua tests** runs the offline addon tests once `Tests/run_tests.py` exists (M1-2) and passes with a notice before; the **Docs rule** job (`tools/check_pr_docs.py`) fails a pull request that changes the addon without touching `CHANGELOG.md` and the documentation, unless it carries the label `no-docs-needed`.
5. **Authorized automation**: `tools/ship_step.py` runs the local checks, merges `origin/main` if it moved, squashes the step into **one commit authored and committed by the noreply address**, pushes, opens the pull request, waits for every CI check on that exact commit and, only if they are green, **fast-forwards `main` to it** and deletes the branch (GitHub then shows the pull request as merged). On any failure it stops and the pull request stays open with the reason.
6. The owner keeps `main` checked out in their main checkout while sessions work in worktrees. `ship_step.py` never touches that checkout: when `main` is checked out in another worktree it only runs `git fetch origin`.
7. GitHub's own merge buttons and `gh pr merge` are never used: GitHub authors the squash commit with the account's primary (personal) email and refuses the noreply address as author.
8. Every pull request says honestly what was **not** verified, in particular anything that needs the real game client; such a step still ships, and its `CHANGELOG.md` entry says the same.
9. Choices that belong to the owner (rules of the guild, names, scope, the open questions of the analysis) are not made autonomously: an issue is opened with the options and a reversible default is used meanwhile.
10. GitHub Actions are pinned by commit SHA.

## Alternatives considered

- **GitHub squash merge or `gh pr merge`**: writes the personal email into the history. Rejected.
- **Waiting for a human review**: the owner is not at the PC during sessions; the checks are the gate.
- **Branch protection with required checks**: not set up for now; `ship_step.py` waits for all checks anyway. It can be added later without changing the flow.

## Consequences

- Positive: one readable, noreply commit per step on `main`; no manual merge work; CI is the gate; the wiki and the docs move with the code.
- Negative: no human review before merge, so the checks must be good enough to be trusted; a step that only the game can verify reaches `main` unverified, which the changelog makes visible.
