#!/usr/bin/env python3
"""
Post-normalisation cleanup for the palace notes:

  - chmod 644 every .md file (strip the stray executable bit)
  - untrack and delete .DS_Store / .ds_store Finder cruft
  - make sure .DS_Store is gitignored

Only the `notes` and `templates` subdirectories are touched.

Dry-run by default; pass --apply to make changes.

Usage:
    python3 fix_modes.py palace            # preview
    python3 fix_modes.py palace --apply     # do it
"""

import argparse
import os
import stat
import subprocess
import sys

SUBDIRS = ["notes", "templates"]
DS_STORE = {".DS_Store", ".ds_store"}
WANT_MODE = 0o644


def fix_md_modes(base, apply):
    """Return count of .md files whose mode was (or would be) fixed."""
    n = 0
    for dirpath, _dirs, files in os.walk(base):
        for name in files:
            if not name.endswith(".md"):
                continue
            path = os.path.join(dirpath, name)
            cur = stat.S_IMODE(os.lstat(path).st_mode)
            if cur == WANT_MODE:
                continue
            print(f"chmod {oct(cur)[2:]} -> 644 : {path}")
            if apply:
                os.chmod(path, WANT_MODE)
            n += 1
    return n


def find_ds_store(base):
    out = []
    for dirpath, _dirs, files in os.walk(base):
        for name in files:
            if name in DS_STORE:
                out.append(os.path.join(dirpath, name))
    return out


def remove_ds_store(paths, apply):
    """git rm --cached if tracked, then delete from disk."""
    for path in paths:
        print(f"remove : {path}")
        if not apply:
            continue
        # Ignore failure: file may not be tracked by git.
        subprocess.run(
            ["git", "rm", "--cached", "--quiet", path],
            stderr=subprocess.DEVNULL,
        )
        if os.path.exists(path):
            os.remove(path)


def ensure_gitignore(root, apply):
    path = os.path.join(root, ".gitignore")
    existing = ""
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            existing = f.read()
    if ".DS_Store" in existing.split():
        return
    print(f"add '.DS_Store' to {path}")
    if apply:
        sep = "" if existing.endswith("\n") or not existing else "\n"
        with open(path, "a", encoding="utf-8") as f:
            f.write(f"{sep}.DS_Store\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("root", help="palace root directory")
    ap.add_argument(
        "--apply",
        action="store_true",
        help="make changes (default is dry-run)",
    )
    args = ap.parse_args()

    if not os.path.isdir(args.root):
        sys.exit(f"not a directory: {args.root}")

    md = ds = 0
    for sub in SUBDIRS:
        base = os.path.join(args.root, sub)
        if not os.path.isdir(base):
            print(f"(skipping missing subdir: {base})")
            continue
        md += fix_md_modes(base, args.apply)
        ds_paths = find_ds_store(base)
        remove_ds_store(ds_paths, args.apply)
        ds += len(ds_paths)

    ensure_gitignore(args.root, args.apply)

    verb = "fixed" if args.apply else "to fix"
    print(f"\n{md} md modes {verb}, {ds} .DS_Store removed.")
    if not args.apply:
        print("(dry-run; re-run with --apply to make changes)")


if __name__ == "__main__":
    main()
