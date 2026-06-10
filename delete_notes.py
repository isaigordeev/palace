#!/usr/bin/env python3
"""
Delete specific note files from the palace repo.

Give it the paths to remove (relative to the repo root, or absolute).
Reads paths from the command line and/or a --from-file list (one path
per line; blank lines and #comments ignored).

Dry-run by default; pass --apply to actually delete. Deletion removes
the file from disk; it remains recoverable from VCS history until you
prune it. In a colocated jj+git repo, just delete on disk and let
`jj` snapshot the removal on your next commit.

Usage:
    python3 delete_notes.py notes/me/films/durak.md          # preview
    python3 delete_notes.py notes/me/films/durak.md --apply    # delete
    python3 delete_notes.py --from-file to_delete.txt --apply  # batch
"""

import argparse
import os
import sys


def load_list(path):
    out = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                out.append(line)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("paths", nargs="*", help="files to delete")
    ap.add_argument(
        "--from-file",
        metavar="LIST",
        help="text file with one path to delete per line",
    )
    ap.add_argument(
        "--apply",
        action="store_true",
        help="actually delete (default is dry-run)",
    )
    args = ap.parse_args()

    targets = list(args.paths)
    if args.from_file:
        targets += load_list(args.from_file)
    if not targets:
        sys.exit("no paths given (pass paths or --from-file)")

    deleted = missing = skipped = 0
    for path in targets:
        if not os.path.exists(path):
            print(f"MISSING (skip)  : {path}")
            missing += 1
            continue
        if os.path.isdir(path):
            print(f"DIR (skip, refusing): {path}")
            skipped += 1
            continue
        print(f"{'DELETE' if args.apply else 'WOULD DELETE'} : {path}")
        if args.apply:
            os.remove(path)
            deleted += 1

    verb = "deleted" if args.apply else "to delete"
    print(
        f"\n{deleted if args.apply else len(targets) - missing - skipped}"
        f" {verb}, {missing} missing, {skipped} skipped."
    )
    if not args.apply:
        print("(dry-run; re-run with --apply to delete)")


if __name__ == "__main__":
    main()
