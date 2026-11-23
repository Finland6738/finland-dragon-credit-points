# Releasing

> Adapted from Azeroth Accord (`docs/RELEASING.md`), same owner, GPL-3.0.

**No tag exists yet, and none is created by the development sessions.** The owner decides the real `v1.0.0` in [M7-8](roadmap/M7-release.md) after the in-game checks. The workflow below has never run: its first run is the dry run in *Try it without publishing anything*.

How a version of Finland Dragon Credit Points is built and published. The workflow is [release.yml](../.github/workflows/release.yml); what the package contains is set by [.pkgmeta](../.pkgmeta). Only the repository owner tags and adds secrets.

## What a tag does

Pushing a tag `vMAJOR.MINOR.PATCH` (optionally `-alpha`, `-beta` or `-rc`, with `.N`: `v1.0.0`, `v0.9.0-beta.1`) starts the workflow **Release**, which:

1. checks what the package will contain (`tools/check_package.py`);
2. builds the zip with the [BigWigs packager](https://github.com/BigWigsMods/packager): libraries from `.pkgmeta`, `## Version` filled in with the tag, `Tests/`, `docs/`, `tools/` and Markdown left out, `LICENSE` kept;
3. checks the zip itself (`tools/check_package.py --zip`) and keeps it as a workflow artifact for 14 days;
4. creates the **GitHub Release** with that zip (a pre-release when the tag has `-alpha`, `-beta` or `-rc`); its body is the section of `CHANGELOG.md` for the version (`tools/release_notes.py`: the section of the exact tag, else of the base version, else *Unreleased*);
5. uploads to **CurseForge**, only if both the `CF_API_KEY` secret and a `## X-Curse-Project-ID: <number>` line in the TOC exist (never for `-rc` tags). Otherwise it says "CurseForge skipped" and the run stays green. CurseForge is **off**: it is the owner's decision.

All actions are pinned by commit SHA. Check the package locally at any time, with no network and no secrets:

```bash
python -I -X utf8 tools/check_package.py --list
```

## Try it without publishing anything

1. **Dry run**: Actions → *Release* → *Run workflow* on `main`, leave `draft_tag` empty. It builds and checks the zip; download it from the run's artifacts and look inside. Nothing is published.
2. **Draft release**: run it again with `draft_tag` = `v0.0.1-alpha.1`. It creates a **draft** GitHub Release with the zip; only you can see drafts. Open it, then delete the draft. No tag is pushed.

## Releasing a version

1. Everything merged on `main`, CI green, the in-game checklists passed and their results reported.
2. In a normal pull request: promote the changelog with `python -I -X utf8 tools/release_notes.py --promote 1.0.0` (*Unreleased* becomes `## [1.0.0] - <date>`, a new empty *Unreleased* goes on top) and update the status of both READMEs and the wiki. Preview the notes: `python -I -X utf8 tools/release_notes.py v1.0.0`.
3. Tag the merge commit and push the tag. **Check your git identity first**: an annotated tag records the tagger's email, and the rule here is the GitHub noreply address ([CLAUDE.md](../CLAUDE.md), Privacy).

   ```bash
   git tag -a v1.0.0 -m "Finland Dragon Credit Points 1.0.0"
   git push origin v1.0.0
   ```

4. Watch the run in the Actions tab, then download the zip once: the folder must be `FinlandDragonCreditPoints/` with the TOC inside.
5. Wrong release? Delete the GitHub Release and the tag (`gh release delete vX --cleanup-tag --yes`), fix, and tag again with a new patch number; never reuse a public tag.

## Setting up CurseForge (once, optional)

Create the project, put its number in the TOC (`## X-Curse-Project-ID: 12345`) in a normal pull request, create an API token and add it yourself as the repository secret `CF_API_KEY` (Settings → Secrets and variables → Actions). Never paste the token in an issue, a pull request or a chat. Push a `-beta` tag first and look at the CurseForge file.
