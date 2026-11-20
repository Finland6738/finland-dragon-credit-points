# Installation

> **Test versions only.** There is no download of Finland Dragon Credit Points yet: the addon is still being built and nothing has been run in the game. Until the first release you install it from the source with the script below. [Italiano](Installation-it)

## For testers: install from the source

You need [Python](https://www.python.org/) 3.9 or newer and a copy of the repository (`git clone` or the zip of the repository).

1. Copy `tools/local.example.ini` to `tools/local.ini` and set `folder` to the folder that contains `_forever_` (your `<WoW folder>`). The file stays on your PC: it is never committed.
2. Download the libraries (Ace3 and friends, pinned in `.pkgmeta`):

```
python -I -X utf8 tools/fetch_libs.py
```

3. Install the addon into `<WoW folder>/_forever_/Interface/AddOns/FinlandDragonCreditPoints`:

```
python -I -X utf8 tools/install_addon.py
```

   Use `--link` to link the folder instead of copying it (edits show after `/reload`) and `--uninstall` to remove it.
4. In the game, enable **Finland Dragon Credit Points** in the AddOns list of the character screen, log in and type `/fdcp help`.

Every raider will need the addon to roll: a raider without it cannot take part in the rolls.

## Libraries and licences

The addon embeds Ace3, LibDataBroker-1.1 and LibDBIcon-1.0 (the version of each is pinned in `.pkgmeta`). Each library keeps its own licence file inside `FinlandDragonCreditPoints/Libs/`. The addon itself is GPL-3.0.

Back to [[Home|Home]].
