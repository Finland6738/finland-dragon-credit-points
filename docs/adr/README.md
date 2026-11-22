# Project decisions (ADRs)

The architecture and method decisions of Finland Dragon Credit Points, one per file, in the [MADR](https://adr.github.io/madr/) format in English: **context**, **decision**, **alternatives considered**, **consequences**.

They record *why* the project is built a certain way. A decision that changes is not rewritten: a new ADR supersedes it, and the old one moves to the "superseded" status. The functional and technical analysis is in [docs/ANALISI.md](../ANALISI.md) (Italian).

## Index

| No. | Decision | Status |
|---|---|---|
| [0001](0001-git-flow-and-automated-shipping.md) | Git flow, CI and automated shipping of roadmap steps | accepted |
| [0002](0002-github-wiki-generated-from-docs-wiki.md) | The GitHub wiki: a bilingual user manual generated from `docs/wiki/` | accepted |
| [0003](0003-documentation-languages.md) | Documentation languages: English, Italian, or both | accepted |
| [0004](0004-interface-style-of-the-community-site.md) | The interface follows the community site's style | accepted |
| [0005](0005-officer-ledger-sync.md) | Officer ledger sync: pull by heads, gate per event, vouching for unknown authors | accepted |
| [0006](0006-read-only-credits-snapshot.md) | Read-only credits for members: an officer's snapshot, newest ledger wins | accepted |
| [0007](0007-backup-and-season-compaction.md) | Backup by merge, guild-wide season compaction with tombstones | accepted |
