# 0003. Documentation languages: English, Italian, or both

- Status: Accepted
- Date: 2026-11-20 (owner's decision of 2026-11-19, `docs/ANALISI.md` §8.5 and §13 question 9)

## Context

The owner and the guild speak Italian; the repository is public and the addon is meant to be reusable by other guilds. The addon itself is multilingual from the start (itIT and enUS, more languages by adding one file). The documentation needs the same clarity about which language goes where, so that automated sessions do not mix them.

## Decision

| Material | Language |
|---|---|
| Code, comments, identifiers, commit messages, pull requests, issues | English |
| ADRs (`docs/adr/`), `CHANGELOG.md`, `ROADMAP.md`, `docs/roadmap/`, `CLAUDE.md` | English |
| Analysis and specifications (`docs/ANALISI.md`, any later `docs/specs/`) | Italian |
| `README.md` / `README.it.md` | both, kept in step |
| User manual (`docs/wiki/`, `<Page>.md` and `<Page>-it.md`) | both, kept in step ([ADR 0002](0002-github-wiki-generated-from-docs-wiki.md)) |
| Spike procedure (`docs/spike/`) | English, with the in-game steps also in Italian for the owner |
| Addon interface | no text in code: locale keys, enUS base, itIT translation, English fallback |

Conversation with the owner is in Italian.

## Alternatives considered

- **Everything in Italian**: closes the project to other guilds and to the shared tooling copied from Azeroth Accord.
- **Everything in English**: the analysis is the owner's working document and the guild's rules are written in Italian.

## Consequences

- Positive: each reader finds their language; sessions know where each language goes; `check_docs.py` keeps the two wiki languages paired.
- Negative: README and manual changes cost two edits.
