#!/bin/sh
# Find true orphan notes: .md files with no [[wikilink]] outbound
# AND no other note pointing to them via [[basename]].
# Usage: ./_orphans.sh [-r ROOT] [-v]

ROOT="palace/notes"
VERBOSE=0

while [ $# -gt 0 ]; do
    case "$1" in
        -r|--root)    ROOT="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=1; shift ;;
        -h|--help)
            cat <<EOF
Usage: $0 [-r ROOT] [-v]

Find true orphan .md notes — no outbound [[link]] in content
AND no inbound link from any other note in the tree.

A note is "linked" by an inbound reference whose target
basename (after stripping path, |alias, #heading, ^block)
matches the note's filename. ASCII case-insensitive;
non-ASCII matched byte-exact.

Options:
  -r, --root DIR    Search root         (default: $ROOT)
  -v, --verbose     Show mtime + size
  -h, --help        This help
EOF
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [ ! -d "$ROOT" ]; then
    echo "Error: $ROOT not found (run ./decrypt.sh first?)" >&2
    exit 1
fi

TMP_TARGETS=$(mktemp -t orphan_targets.XXXXXX) || exit 1
TMP_NOOUT=$(mktemp -t orphan_noout.XXXXXX) || exit 1
TMP_OUT=$(mktemp -t orphan_out.XXXXXX) || exit 1
trap 'rm -f "$TMP_TARGETS" "$TMP_NOOUT" "$TMP_OUT"' EXIT INT HUP TERM

total=$(find "$ROOT" -type f -name '*.md' | wc -l | tr -d ' ')

# Phase 1: every basename referenced by [[...]] anywhere in the tree.
# Strip [[ ]], |alias, #heading, ^block, and any leading path segments.
grep -rhoE '\[\[[^]]+\]\]' --include='*.md' "$ROOT" 2>/dev/null \
  | sed -E 's/^\[\[//; s/\]\]$//; s/\|.*//; s/#.*//; s/\^.*//; s|.*/||' \
  | tr 'A-Z' 'a-z' \
  | LC_ALL=C sort -u > "$TMP_TARGETS"

# Phase 2: candidate files (no outbound [[).
grep -rLF '[[' --include='*.md' "$ROOT" | LC_ALL=C sort > "$TMP_NOOUT"

# Phase 3: keep only candidates whose basename isn't a referenced target.
LC_ALL=C awk -v targets="$TMP_TARGETS" '
    BEGIN {
        while ((getline line < targets) > 0) t[line] = 1
        close(targets)
    }
    {
        n = split($0, parts, "/")
        base = parts[n]
        sub(/\.md$/, "", base)
        if (!(tolower(base) in t)) print $0
    }
' "$TMP_NOOUT" > "$TMP_OUT"

orphans=$(wc -l < "$TMP_OUT" | tr -d ' ')
no_out=$(wc -l < "$TMP_NOOUT" | tr -d ' ')
targets_n=$(wc -l < "$TMP_TARGETS" | tr -d ' ')

printf "\n  True orphans:  %d / %d  (no outbound and no inbound)\n" "$orphans" "$total"
printf "    no outbound : %d   distinct inbound targets : %d\n\n" "$no_out" "$targets_n"

while IFS= read -r f; do
    if [ "$VERBOSE" -eq 1 ]; then
        sz=$(stat -f%z "$f")
        mt=$(stat -f "%Sm" -t "%Y-%m-%d" "$f")
        printf "  %s   %6d B   %s\n" "$mt" "$sz" "$f"
    else
        printf "  %s\n" "$f"
    fi
done < "$TMP_OUT"
