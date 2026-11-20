# 0002. The GitHub wiki: a bilingual user manual generated from `docs/wiki/`

- Status: Accepted
- Date: 2026-11-20 (adapted from Azeroth Accord, ADR 0013 there)

## Context

Raiders, officers and the Guild Master need a manual that is easy to navigate, has no developer content and exists in English and Italian (`docs/ANALISI.md` §8.5). A GitHub wiki is a separate git repository, outside pull requests and reviews, and GitHub creates it only after the first page is saved in the browser.

## Decision

1. `docs/wiki/*.md` is the **only source** of the wiki; the wiki is a generated mirror and is **never edited on GitHub**.
2. English pages have plain names (`Home.md`, `Installation.md`); each has an Italian twin with the suffix `-it` (`Home-it.md`, `Installation-it.md`). `_Sidebar.md` lists both languages; `_Footer.md` is one bilingual line. `tools/check_docs.py` fails when a page has no twin or is missing from the sidebar.
3. `tools/sync_wiki.py` clones the wiki, copies the pages with a "generated, do not edit here" note, copies the images they show, removes what is gone, and pushes as `github-actions[bot]`.
4. The **Wiki sync** workflow runs it on every push to `main` that changes `docs/wiki/`, `assets/` or the script. Since every change reaches `main` through a shipped pull request ([ADR 0001](0001-git-flow-and-automated-shipping.md)), the wiki follows every merged change automatically.
5. Until the wiki repository exists, `sync_wiki.py --warn-if-missing` prints a warning and exits 0, so CI stays green; the manual stays readable in `docs/wiki/` meanwhile. The owner creates the first page once by hand.
6. Developer documentation (analysis, roadmap, ADRs) stays in the repository.

## Alternatives considered

- **Editing the wiki on GitHub**: no review, drifts from the code. Rejected.
- **Language folders** (`en/`, `it/`): GitHub wikis are flat; a suffix keeps page names unique and readable.

## Consequences

- Positive: one reviewed source; the manual cannot drift from the repository; both languages stay in step.
- Negative: every user-visible change must update two wiki pages in the same pull request.
