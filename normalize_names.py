#!/usr/bin/env python3
"""
Normalise palace file/directory names:

  - strip accents/diacritics  (é -> e, ç -> c, â -> a, ...)
  - replace spaces with underscores  ("Start Page" -> "start_page")
  - lowercase everything

Handles both NFC and NFD (combining-mark) accents.

Only the `notes` and `templates` subdirectories are touched; everything
else (hidden folders, .git, etc.) is left alone.

Dry-run by default; pass --apply to actually rename. Renames are done
bottom-up so directory renames never invalidate child paths. With
--git, uses `git mv` to preserve history.

Usage:
    python3 normalize_names.py palace               # preview
    python3 normalize_names.py palace --apply        # do it
    python3 normalize_names.py palace --apply --git   # via git mv
    python3 normalize_names.py palace --subdir notes  # restrict further
"""

SUBDIRS = ["notes", "templates"]
IGNORE_DIRS = {"daily", "weekly"}

import argparse
import os
import subprocess
import sys
import unicodedata


def normalize(name):
    """Return the cleaned version of a single path component."""
    nfkd = unicodedata.normalize("NFKD", name)
    no_accents = "".join(c for c in nfkd if not unicodedata.combining(c))
    return no_accents.replace(" ", "_").lower()


def collect_renames(base):
    """Yield (old_path, new_path) bottom-up so dirs rename last.

    Any directory named in IGNORE_DIRS (and everything inside it) is
    skipped entirely.
    """
    for dirpath, dirnames, filenames in os.walk(base, topdown=False):
        parts = dirpath.split(os.sep)
        if any(p in IGNORE_DIRS for p in parts):
            continue
        for name in filenames + dirnames:
            if name in IGNORE_DIRS:
                continue
            new_name = normalize(name)
            if new_name == name:
                continue
            old = os.path.join(dirpath, name)
            new = os.path.join(dirpath, new_name)
            yield old, new


def do_rename(old, new, use_git):
    if use_git:
        subprocess.run(["git", "mv", old, new], check=True)
    else:
        os.rename(old, new)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("root", help="palace root directory")
    ap.add_argument(
        "--subdir",
        action="append",
        metavar="NAME",
        help=f"subdir to process (repeatable; default: {SUBDIRS})",
    )
    ap.add_argument(
        "--apply",
        action="store_true",
        help="perform renames (default is dry-run)",
    )
    ap.add_argument(
        "--git",
        action="store_true",
        help="use `git mv` to preserve history",
    )
    args = ap.parse_args()

    if not os.path.isdir(args.root):
        sys.exit(f"not a directory: {args.root}")

    subdirs = args.subdir or SUBDIRS
    renames = []
    for sub in subdirs:
        base = os.path.join(args.root, sub)
        if not os.path.isdir(base):
            print(f"(skipping missing subdir: {base})")
            continue
        renames.extend(collect_renames(base))

    if not renames:
        print("nothing to rename.")
        return

    count = skipped = 0
    for old, new in renames:
        # On a case-insensitive FS a pure case change reads as "exists";
        # only treat it as a real collision if it's a different file.
        if os.path.exists(new) and not os.path.samefile(old, new):
            print(f"SKIP (target exists): {old} -> {new}")
            skipped += 1
            continue
        print(f"{'RENAME' if args.apply else 'WOULD'} : {old} -> {new}")
        if args.apply:
            do_rename(old, new, args.git)
        count += 1

    verb = "renamed" if args.apply else "to rename"
    print(f"\n{count} {verb}, {skipped} skipped.")
    if not args.apply:
        print("(dry-run; re-run with --apply to make changes)")


if __name__ == "__main__":
    main()
