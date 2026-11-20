#!/usr/bin/env python3
"""Install the FinlandDragonCreditPoints addon (with the fetched libraries) into <WoW folder>/_forever_/Interface/AddOns/.

Adapted from Azeroth Accord (tools/install_addon.py), same owner, GPL-3.0.
The WoW folder comes from --wow or from tools/local.ini (copy of tools/local.example.ini, git-ignored).
Run tools/fetch_libs.py first. Default is a copy; --link links the folder instead (junction on Windows, symlink
elsewhere) so edits show after /reload.
Usage: python -I -X utf8 tools/install_addon.py [--wow <folder>] [--link] [--uninstall]
"""
import argparse
import configparser
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NAME = "FinlandDragonCreditPoints"
SRC = ROOT / NAME


def wow_folder(arg):
    if arg:
        return Path(arg)
    ini = ROOT / "tools" / "local.ini"
    if not ini.exists():
        sys.exit("No WoW folder: pass --wow <folder> or copy tools/local.example.ini to tools/local.ini and edit it.")
    cp = configparser.ConfigParser()
    cp.read(ini, encoding="utf-8")
    folder = cp.get("wow", "folder", fallback="").strip()
    if not folder or "<" in folder:
        sys.exit("tools/local.ini: set [wow] folder to the folder that contains _forever_.")
    return Path(folder)


def remove(dest):
    if dest.is_symlink():
        dest.unlink()
    elif os.name == "nt" and dest.is_dir() and os.path.isjunction(dest):
        os.rmdir(dest)
    elif dest.exists():
        shutil.rmtree(dest)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--wow", help="WoW folder (contains _forever_)")
    ap.add_argument("--link", action="store_true", help="link instead of copying")
    ap.add_argument("--uninstall", action="store_true", help="remove the installed addon")
    args = ap.parse_args()
    addons = wow_folder(args.wow) / "_forever_" / "Interface" / "AddOns"
    if not addons.is_dir():
        sys.exit(f"Not found: {addons}")
    dest = addons / NAME
    if args.uninstall:
        remove(dest)
        print(f"Removed {dest}")
        return
    if not (SRC / "Libs" / "Ace3" / "LibStub" / "LibStub.lua").is_file():
        sys.exit("The libraries are missing: run python -I -X utf8 tools/fetch_libs.py first.")
    remove(dest)
    if args.link and os.name == "nt":
        subprocess.run(["cmd", "/c", "mklink", "/J", str(dest), str(SRC)], check=True, stdout=subprocess.DEVNULL)
        print(f"Linked (junction) {dest}")
    elif args.link:
        dest.symlink_to(SRC, target_is_directory=True)
        print(f"Linked {dest}")
    else:
        shutil.copytree(SRC, dest, ignore=shutil.ignore_patterns(".fetched", "*.md", "tests", ".git*"))
        print(f"Copied to {dest}")
    print("In game: /reload, then /fdcp help.")


if __name__ == "__main__":
    main()
