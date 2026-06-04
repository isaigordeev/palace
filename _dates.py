#!/usr/bin/env python3
"""
Normalise legacy palace timestamps with the local-TZ offset preserved.

Recognised input shapes (all rewritten in place):

  SHORT          Thu 04 Jun 2026 at 10:36:44
  LONG (en)      Monday, July 07 2021, 21:25:00, W28-D193
  LONG (fr)      lundi, août 22 2022, 13:38:19, W34-D234 2022-08-22
  ISO + in       2021-07-13 in 04:22

The W##-D### / trailing YYYY-MM-DD on LONG entries are consumed as
part of the match. ISO + in is treated as HH:MM:00.

Output (time unchanged, numeric offset appended):
    isg 2026-06-04 10:36:44 +0200   (Paris summer, CEST)
    isg 2023-12-06 09:56:00 +0100   (Paris winter, CET)
    isg 2022-05-03 14:30:00 +0300   (pre-cutoff, MSK)

Timezone rules for choosing the offset:
    local < 2022-09-05 00:00      → Europe/Moscow  (fixed +3)
    local ≥ 2022-09-05 00:00      → Europe/Paris   (DST-aware)

Wall-clock time is NEVER shifted — only the offset is attached so
timestamps become self-describing. Files are modified in place (no
backup; rely on git). Output lines do not match any input pattern,
so reruns are no-ops.

Usage:
    _dates.py FILE [FILE ...]
    _dates.py DIR              # recurses into *.md
"""

from __future__ import annotations

import re
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

SHORT_PATTERN = re.compile(
    r"\b(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) "
    r"(?P<day>\d{2}) "
    r"(?P<mon>Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) "
    r"(?P<year>\d{4}) "
    r"at "
    r"(?P<h>\d{2}):(?P<m>\d{2}):(?P<s>\d{2})\b"
)

WEEKDAYS_LONG = (
    "Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday"
    "|lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche"
)
MONTHS_LONG = (
    "January|February|March|April|May|June"
    "|July|August|September|October|November|December"
    "|janvier|février|mars|avril|mai|juin"
    "|juillet|août|septembre|octobre|novembre|décembre"
)

LONG_PATTERN = re.compile(
    rf"(?:{WEEKDAYS_LONG}), "
    rf"(?P<mon>{MONTHS_LONG}) "
    rf"(?P<day>\d{{2}}) "
    rf"(?P<year>\d{{4}}), "
    rf"(?P<h>\d{{2}}):(?P<m>\d{{2}}):(?P<s>\d{{2}}), "
    rf"W\d+-D\d+"
    rf"(?: \d{{4}}-\d{{2}}-\d{{2}})?"
)

ISO_IN_PATTERN = re.compile(
    r"\b(?P<year>\d{4})-(?P<mon>\d{2})-(?P<day>\d{2}) "
    r"in (?P<h>\d{2}):(?P<m>\d{2})\b"
)

MONTH_INDEX = {
    m: i + 1
    for i, m in enumerate(
        ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
         "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    )
}

MONTH_LONG_INDEX = {
    "January": 1, "February": 2, "March": 3, "April": 4,
    "May": 5, "June": 6, "July": 7, "August": 8,
    "September": 9, "October": 10, "November": 11, "December": 12,
    "janvier": 1, "février": 2, "mars": 3, "avril": 4,
    "mai": 5, "juin": 6, "juillet": 7, "août": 8,
    "septembre": 9, "octobre": 10, "novembre": 11, "décembre": 12,
}

CUTOFF = datetime(2022, 9, 5, 0, 0, 0)
MOSCOW = ZoneInfo("Europe/Moscow")
PARIS = ZoneInfo("Europe/Paris")


def localize(local_naive: datetime) -> datetime:
    """Attach the right tz; time is NOT shifted."""
    if local_naive < CUTOFF:
        return local_naive.replace(tzinfo=MOSCOW)
    return local_naive.replace(tzinfo=PARIS)


def format_isg(local_naive: datetime) -> str:
    aware = localize(local_naive)
    offset = aware.strftime("%z")        # +0200, +0100, +0300
    return f"isg {aware:%Y-%m-%d %H:%M:%S} {offset}"


def convert_short(m: re.Match) -> str:
    return format_isg(datetime(
        int(m["year"]),
        MONTH_INDEX[m["mon"]],
        int(m["day"]),
        int(m["h"]),
        int(m["m"]),
        int(m["s"]),
    ))


def convert_long(m: re.Match) -> str:
    return format_isg(datetime(
        int(m["year"]),
        MONTH_LONG_INDEX[m["mon"]],
        int(m["day"]),
        int(m["h"]),
        int(m["m"]),
        int(m["s"]),
    ))


def convert_iso_in(m: re.Match) -> str:
    return format_isg(datetime(
        int(m["year"]),
        int(m["mon"]),
        int(m["day"]),
        int(m["h"]),
        int(m["m"]),
        0,
    ))


def process(path: Path) -> int:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        print(f"skip {path}: {e}", file=sys.stderr)
        return 0
    original = text
    text, n1 = SHORT_PATTERN.subn(convert_short, text)
    text, n2 = LONG_PATTERN.subn(convert_long, text)
    text, n3 = ISO_IN_PATTERN.subn(convert_iso_in, text)
    n = n1 + n2 + n3
    if n and text != original:
        path.write_text(text, encoding="utf-8")
    return n


def iter_targets(args: list[str]):
    for arg in args:
        p = Path(arg)
        if p.is_dir():
            yield from sorted(p.rglob("*.md"))
        elif p.is_file():
            yield p
        else:
            print(f"skip {arg}: not a file or directory", file=sys.stderr)


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__, file=sys.stderr)
        return 0 if argv else 1
    total = 0
    files_touched = 0
    for p in iter_targets(argv):
        n = process(p)
        if n:
            print(f"{p}: {n} replacement(s)")
            files_touched += 1
        total += n
    print(f"\nTotal: {total} replacement(s) across {files_touched} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
