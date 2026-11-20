#!/usr/bin/env python3
"""Install the FDCP_Probe spike addon into <WoW folder>/_forever_/Interface/AddOns/.

The WoW folder comes from --wow or from tools/local.ini (copy of tools/local.example.ini, git-ignored).
Default is a link (junction on Windows, symlink elsewhere) so edits show after /reload; --copy copies instead.
"""
import argparse
import configparser
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "probe" / "FDCP_Probe"
NAME = "FDCP_Probe"


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
    if dest.is_symlink() or (os.name == "nt" and dest.is_dir() and os.path.isjunction(dest)):
        dest.unlink() if dest.is_symlink() else os.rmdir(dest)
    elif dest.exists():
        shutil.rmtree(dest)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--wow", help="WoW folder (contains _forever_)")
    ap.add_argument("--copy", action="store_true", help="copy instead of linking")
    ap.add_argument("--uninstall", action="store_true", help="remove the installed probe")
    args = ap.parse_args()
    addons = wow_folder(args.wow) / "_forever_" / "Interface" / "AddOns"
    if not addons.is_dir():
        sys.exit(f"Not found: {addons}")
    dest = addons / NAME
    remove(dest)
    if args.uninstall:
        print(f"Removed {dest}")
        return
    if args.copy:
        shutil.copytree(SRC, dest)
        print(f"Copied to {dest}")
    elif os.name == "nt":
        subprocess.run(["cmd", "/c", "mklink", "/J", str(dest), str(SRC)], check=True, stdout=subprocess.DEVNULL)
        print(f"Linked (junction) {dest}")
    else:
        dest.symlink_to(SRC, target_is_directory=True)
        print(f"Linked {dest}")


if __name__ == "__main__":
    main()
