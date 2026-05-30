#!/bin/sh
# Find true orphan .md notes: no outbound [[link]] and no inbound link.
# Default runtime is zig (compiled to ~/.cache/palace/_orphans);
# pass --runtime sh to use the pure-shell fallback.

RUNTIME=zig
ROOT="palace/notes"
VERBOSE=0

show_help() {
    cat <<EOF
Usage: $0 [options]

Find true orphan .md notes — files with no outbound [[link]] in
their content AND no inbound link from any other note in the tree.

How a match is decided:
  An inbound link [[target|alias]], [[path/to/target]],
  [[target#heading]] or [[target^block]] is normalised to its
  bare basename ("target") and compared against each candidate
  file's basename (filename minus .md). Comparison is
  ASCII case-insensitive; non-ASCII bytes are matched exact.

Options:
  -R, --runtime BACKEND   zig | sh                  (default: zig)
  -r, --root DIR          Search root      (default: palace/notes)
  -v, --verbose           Show mtime + size next to each path
  -h, --help              This help

Examples:
  $0                            scan default root, zig backend
  $0 -v                         include mtime + size
  $0 -R sh                      use shell fallback (no zig needed)
  $0 -r palace/notes/management scan a subtree

Notes:
  The zig backend is compiled on first run to
  ~/.cache/palace/_orphans. Recompiled when _orphans.zig
  changes. Requires \`brew install zig\`.

Exit codes:
  0  ran successfully
  1  root not found, bad option, or compile failure
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -R|--runtime) RUNTIME="$2"; shift 2 ;;
        -r|--root)    ROOT="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=1; shift ;;
        -h|--help)    show_help; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Resolve script directory robustly.
SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || SCRIPT_DIR="$PWD"

# ---------------- ZIG BACKEND ----------------

run_zig() {
    if ! command -v zig >/dev/null 2>&1; then
        echo "_orphans.sh: zig not found." >&2
        echo "  Install it or rerun with --runtime sh." >&2
        exit 1
    fi
    SRC="$SCRIPT_DIR/_orphans.zig"
    if [ ! -f "$SRC" ]; then
        echo "_orphans.sh: $SRC missing." >&2
        exit 1
    fi
    CACHE_DIR="$HOME/.cache/palace"
    BIN="$CACHE_DIR/_orphans"
    mkdir -p "$CACHE_DIR"
    if [ ! -s "$BIN" ] || [ "$SRC" -nt "$BIN" ]; then
        echo "_orphans.sh: compiling zig binary…" >&2
        TMP_BIN="$BIN.new.$$"
        if (
            cd "$CACHE_DIR" \
            && zig build-exe -O ReleaseFast \
                   -femit-bin="$TMP_BIN" "$SRC"
        ) >&2; then
            mv "$TMP_BIN" "$BIN"
        else
            rm -f "$TMP_BIN"
            exit 1
        fi
    fi
    if [ "$VERBOSE" -eq 1 ]; then
        exec "$BIN" -r "$ROOT" -v
    else
        exec "$BIN" -r "$ROOT"
    fi
}

# ---------------- SH BACKEND ----------------

run_sh() {
    if [ ! -d "$ROOT" ]; then
        echo "Error: $ROOT not found (run ./decrypt.sh first?)" >&2
        exit 1
    fi
    T_START=$(perl -MTime::HiRes \
        -e 'printf "%d\n", Time::HiRes::time() * 1000')
    TMP_T=$(mktemp -t orphan_targets.XXXXXX) || exit 1
    TMP_N=$(mktemp -t orphan_noout.XXXXXX)   || exit 1
    TMP_O=$(mktemp -t orphan_out.XXXXXX)     || exit 1
    trap 'rm -f "$TMP_T" "$TMP_N" "$TMP_O"' EXIT INT HUP TERM

    total=$(find "$ROOT" -type f -name '*.md' \
             | wc -l | tr -d ' ')

    grep -rhoE '\[\[[^]]+\]\]' --include='*.md' "$ROOT" 2>/dev/null \
      | sed -E 's/^\[\[//; s/\]\]$//; s/\|.*//; s/#.*//; s/\^.*//; s|.*/||' \
      | tr 'A-Z' 'a-z' \
      | LC_ALL=C sort -u > "$TMP_T"

    grep -rLF '[[' --include='*.md' "$ROOT" \
      | LC_ALL=C sort > "$TMP_N"

    LC_ALL=C awk -v targets="$TMP_T" '
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
    ' "$TMP_N" > "$TMP_O"

    orphans=$(wc -l < "$TMP_O" | tr -d ' ')
    no_out=$(wc -l < "$TMP_N" | tr -d ' ')
    targets_n=$(wc -l < "$TMP_T" | tr -d ' ')

    printf "\n  True orphans:  %d / %d  (no outbound and no inbound)\n" \
        "$orphans" "$total"
    printf "    no outbound : %d   distinct inbound targets : %d\n\n" \
        "$no_out" "$targets_n"

    while IFS= read -r f; do
        if [ "$VERBOSE" -eq 1 ]; then
            sz=$(stat -f%z "$f")
            mt=$(stat -f "%Sm" -t "%Y-%m-%d" "$f")
            printf "  %s   %6d B   %s\n" "$mt" "$sz" "$f"
        else
            printf "  %s\n" "$f"
        fi
    done < "$TMP_O"

    T_END=$(perl -MTime::HiRes \
        -e 'printf "%d\n", Time::HiRes::time() * 1000')
    ELAPSED=$((T_END - T_START))
    printf "\n  ── runtime ───────────────────────\n"
    printf "  backend : sh\n"
    printf "  elapsed : %d ms\n" "$ELAPSED"
}

case "$RUNTIME" in
    zig) run_zig ;;
    sh)  run_sh ;;
    *)
        echo "Unknown runtime: $RUNTIME (expected zig|sh)" >&2
        exit 1 ;;
esac
