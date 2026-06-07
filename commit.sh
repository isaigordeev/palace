#!/bin/bash
# git_commit_encrypted.sh
# Archive, encrypt PALACE notes, stage, and commit the encrypted archive
#
# Usage: sh commit.sh [OPTIONS]
#
# Options:
#   --default, --no-tag   Use "default" as version tag instead of calculating from git
#   --no-encrypt          Skip encryption step (commits other changes only)
#   -y, --yes             Skip the confirm prompt before commit + push
#   --help                Show this help message
#
# Examples:
#   sh commit.sh                         # Full encrypt + auto tag (asks y/N/c)
#   sh commit.sh --no-tag                # Full encrypt + "default" tag
#   sh commit.sh --no-encrypt            # Skip encryption, no version update
#   sh commit.sh --no-encrypt --no-tag   # Combine flags
#   sh commit.sh -y                      # Non-interactive (no prompt)

# =====================================================================
# CONFIGURATION
# =====================================================================

PALACE_DIR="$(pwd)/palace"  # Directory containing your notes
RECIPIENT="F4F078EB57EA2C67C23E0F5CB94FFCADE32BE35A"

# Timestamp for archive and commit
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
TAR_FILE="palace-$TIMESTAMP.tar.gz"
GPG_FILE="$TAR_FILE.gpg"

# Commit message prefix
PREFIX="chore(encrypted-notes): update palace notes"

VERSION_FILE="version.txt"
STATS_FILE="version-stats.txt"
DAILY_ROOT_REL="palace/notes/management/daily"

# =====================================================================
# HELPERS  (build the rich version-stats.txt line)
# =====================================================================

fmt_bytes() {
    awk -v b="$1" 'BEGIN{
        b += 0
        if (b < 1024) printf "%d B", b
        else if (b < 1048576) printf "%.1f KB", b/1024
        else if (b < 1073741824) printf "%.1f MB", b/1048576
        else printf "%.2f GB", b/1073741824
    }'
}

current_streak() {
    local streak=0 i=0 d y m
    while [ "$i" -lt 366 ]; do
        d=$(date -j -v-${i}d +"%Y-%m-%d" 2>/dev/null) || break
        y="${d:0:4}"; m="${d:5:2}"
        if [ -f "$DAILY_ROOT_REL/$y/$m/$d.md" ]; then
            streak=$((streak + 1)); i=$((i + 1))
        else
            break
        fi
    done
    echo "$streak"
}

# Top remaining candidate at slot, excluding tags chosen at lower slots.
default_for_tag() {
    local slot="$1" line
    [ -z "$CAND_FILE" ] && return
    [ ! -s "$CAND_FILE" ] && return
    while IFS= read -r line; do
        if [ "$slot" -ge 2 ] && [ "$line" = "$TAG1" ]; then continue; fi
        if [ "$slot" -ge 3 ] && [ "$line" = "$TAG2" ]; then continue; fi
        printf "%s" "$line"
        return
    done < "$CAND_FILE"
}

# Prompt one tag slot. Input rules: empty = keep default; "a" = увы;
# digits = Nth candidate; anything else = literal word.
prompt_tag() {
    local slot="$1" current="$2" label new picked
    label="$current"
    [ -z "$label" ] && label="(none)"
    if [ -r /dev/tty ] && [ -w /dev/tty ]; then
        printf "Tag %d (default: %s): " "$slot" "$label" >/dev/tty
        read -r new </dev/tty
    else
        printf "Tag %d (default: %s): " "$slot" "$label" >&2
        read -r new
    fi
    case "$new" in
        '')        printf "%s" "$current" ;;
        a|A)       printf "%s" "увы" ;;
        *[!0-9]*)  printf "%s" "$new" ;;
        *)
            picked=$(sed -n "${new}p" "$CAND_FILE")
            if [ -n "$picked" ]; then
                printf "%s" "$picked"
            else
                printf "%s" "$new"
            fi
            ;;
    esac
}

# Build COMMIT_MESSAGE (canonical) and STATS_LINE (rich).
build_messages() {
    if [ "$SKIP_ENCRYPT" = false ]; then
        if [ "$USE_DEFAULT_TAG" = true ]; then
            VERSION_TAG="version tag: \"default\""
        else
            VERSION_TAG="version tag: \"$TAG1\""
        fi
        COMMIT_MESSAGE="$PREFIX [$TIMESTAMP] $VERSION_TAG"
    else
        COMMIT_MESSAGE="$PREFIX [$TIMESTAMP]"
    fi
    if [ "$SKIP_ENCRYPT" = false ]; then
        local tags
        if [ "$USE_DEFAULT_TAG" = true ]; then
            tags="default"
        else
            tags="$TAG1"
            [ -n "$TAG2" ] && tags="$tags, $TAG2"
            [ -n "$TAG3" ] && tags="$tags, $TAG3"
        fi
        local files="(+$ADDED ~$MODIFIED"
        [ "$DELETED" -gt 0 ] && files="$files -$DELETED"
        files="$files)"
        STATS_LINE="[$TIMESTAMP] $NOTE_COUNT notes $files"
        STATS_LINE="$STATS_LINE +$LINES_ADDED/-$LINES_DELETED lines"
        STATS_LINE="$STATS_LINE  $BYTE_DELTA_STR"
        STATS_LINE="$STATS_LINE  tags: $tags"
        STATS_LINE="$STATS_LINE  streak: $STREAK"
        [ -n "$INNER_LAST_COMMIT" ] && \
            STATS_LINE="$STATS_LINE  last: \"$INNER_LAST_COMMIT\""
    else
        STATS_LINE=""
    fi
}

# =====================================================================
# PARSE ARGUMENTS
# =====================================================================

USE_DEFAULT_TAG=false
FORCE_SKIP_ENCRYPT=false
ASSUME_YES=false
for arg in "$@"; do
    case $arg in
        --default|--no-tag)
            USE_DEFAULT_TAG=true
            ;;
        --no-encrypt)
            FORCE_SKIP_ENCRYPT=true
            ;;
        -y|--yes)
            ASSUME_YES=true
            ;;
        --help)
            sed -n '3,18p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
    esac
done

# =====================================================================
# VALIDATION
# =====================================================================

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "ERROR: Not inside a Git repository."
    exit 1
fi

SKIP_ENCRYPT=false
if [ "$FORCE_SKIP_ENCRYPT" = true ]; then
    echo "Skipping encryption (--no-encrypt flag)."
    SKIP_ENCRYPT=true
elif [ ! -d "$PALACE_DIR" ]; then
    echo "WARNING: Notes directory not found: $PALACE_DIR"
    echo "Skipping encryption, version file will not be updated."
    SKIP_ENCRYPT=true
fi

# =====================================================================
# ENCRYPT NOTES
# =====================================================================

if [ "$SKIP_ENCRYPT" = false ]; then
    git filter-repo --force --strip-blobs-bigger-than 1M
    sh encrypt.sh
fi

# =====================================================================
# STAGE AND COMMIT
# =====================================================================

echo "=============================================================="
echo "STAGING AND COMMITTING"
echo "--------------------------------------------------------------"

# Get version tag from palace subdirectory's last commit
# Show debug info locally, but only capture the version tag line
CAND_FILE=""
TAG1=""; TAG2=""; TAG3=""
NOTE_COUNT=0
ADDED=0; MODIFIED=0; DELETED=0
LINES_ADDED=0; LINES_DELETED=0
BYTES_WRITTEN=0; BYTES_REMOVED=0; BYTES_DELTA=0
BYTE_DELTA_STR=""
STREAK=0
INNER_LAST_COMMIT=""

if [ "$SKIP_ENCRYPT" = false ]; then
    if [ "$USE_DEFAULT_TAG" = true ]; then
        TAG1="default"
    else
        ./tag.sh "$PALACE_DIR" --debug
        CAND_FILE=$(mktemp -t commit_cand.XXXXXX)
        ./tag.sh "$PALACE_DIR" --debug 2>/dev/null \
            | grep -E '^\s*len=' | head -10 \
            | awk '{print $NF}' > "$CAND_FILE"
        TAG1=$(sed -n '1p' "$CAND_FILE")
        TAG2=$(default_for_tag 2)
        TAG3=$(default_for_tag 3)
    fi

    NOTE_COUNT=$(find "$PALACE_DIR" -name '*.md' 2>/dev/null \
                  | wc -l | tr -d ' ')
    if [ -d "$PALACE_DIR/.git" ]; then
        INNER_LAST_COMMIT=$(git -C "$PALACE_DIR" log -1 \
            --pretty=%s 2>/dev/null || true)
        DIFF=$(git -C "$PALACE_DIR" show HEAD --name-status \
               --format= 2>/dev/null || true)
        ADDED=$(printf "%s\n"   "$DIFF" | grep -c '^A' || true)
        MODIFIED=$(printf "%s\n" "$DIFF" | grep -c '^M' || true)
        DELETED=$(printf "%s\n"  "$DIFF" | grep -c '^D' || true)
        NS=$(git -C "$PALACE_DIR" show HEAD --numstat \
             --format= 2>/dev/null || true)
        LINES_ADDED=$(printf "%s\n" "$NS" \
            | awk '$1 ~ /^[0-9]+$/{a+=$1} END{print a+0}')
        LINES_DELETED=$(printf "%s\n" "$NS" \
            | awk '$2 ~ /^[0-9]+$/{d+=$2} END{print d+0}')
        DIFF_RAW=$(git -C "$PALACE_DIR" show HEAD \
                   --format= 2>/dev/null || true)
        BYTES_PAIR=$(LC_ALL=C printf "%s\n" "$DIFF_RAW" \
            | LC_ALL=C awk '
                /^\+\+\+/ {next}
                /^---/    {next}
                /^\+/     {a += length($0) - 1}
                /^-/      {d += length($0) - 1}
                END       {printf "%d %d", a+0, d+0}
            ')
        BYTES_WRITTEN=${BYTES_PAIR% *}
        BYTES_REMOVED=${BYTES_PAIR#* }
        BYTES_DELTA=$((BYTES_WRITTEN - BYTES_REMOVED))
    fi
    if [ "$BYTES_DELTA" -ge 0 ]; then
        BYTE_DELTA_STR="+$(fmt_bytes "$BYTES_DELTA")"
    else
        BYTE_DELTA_STR="-$(fmt_bytes "$((0 - BYTES_DELTA))")"
    fi

    STREAK=$(current_streak)
fi

build_messages

# =====================================================================
# CONFIRM (re-prompts after each [c] choice)
# =====================================================================

read_tty() {
    if [ -r /dev/tty ]; then
        read -r "$1" </dev/tty
    else
        read -r "$1"
    fi
}

if [ "$ASSUME_YES" = false ]; then
    while true; do
        echo
        echo "--------------------------------------------------------------"
        echo "git commit  : $COMMIT_MESSAGE"
        [ -n "$STATS_LINE" ] && echo "stats line  : $STATS_LINE"
        echo "  [y] yes — commit and push"
        echo "  [n] no  — discard everything"
        echo "  [c] choose tags"
        printf "Choice [y/N/c]: "
        read_tty reply
        case "$reply" in
            y|Y|yes|YES|Yes)
                echo
                echo "=== Final check before push ==="
                echo "git commit  : $COMMIT_MESSAGE"
                [ -n "$STATS_LINE" ] && echo "stats line  : $STATS_LINE"
                printf "Push? [y/N]: "
                read_tty confirm
                case "$confirm" in
                    y|Y|yes|YES|Yes) break ;;
                    *)
                        echo "Cancelled. Returning to menu."
                        continue ;;
                esac
                ;;
            c|C|choose|CHOOSE)
                if [ -z "$CAND_FILE" ] || [ ! -s "$CAND_FILE" ]; then
                    echo "No candidates (--no-encrypt or --no-tag in effect)."
                    printf "Enter custom TAG1 (empty to cancel): "
                    read_tty new_tag
                    if [ -n "$new_tag" ]; then
                        TAG1="$new_tag"
                        build_messages
                    fi
                else
                    echo
                    echo "Top candidates:"
                    awk '{ printf "  [%d] %s\n", NR, $0 }' "$CAND_FILE"
                    echo "  [a] увы  (fallback)"
                    echo
                    n_cand=$(wc -l < "$CAND_FILE" | tr -d ' ')
                    echo "Per slot: number 1-$n_cand, a custom word,"
                    echo "          'a' for увы, or empty to keep default."
                    TAG1=$(prompt_tag 1 "$TAG1")
                    TAG2=$(default_for_tag 2)
                    TAG2=$(prompt_tag 2 "$TAG2")
                    TAG3=$(default_for_tag 3)
                    TAG3=$(prompt_tag 3 "$TAG3")
                    build_messages
                fi
                ;;
            *)
                echo "Aborted. Discarding all changes…"
                git restore --staged . 2>/dev/null || true
                git restore . 2>/dev/null || true
                [ -n "$GPG_FILE" ] && rm -f "$GPG_FILE"
                [ -n "$CAND_FILE" ] && rm -f "$CAND_FILE"
                echo "Working tree restored to HEAD. New archive removed."
                exit 0
                ;;
        esac
    done
fi

[ -n "$CAND_FILE" ] && rm -f "$CAND_FILE"

if [ "$SKIP_ENCRYPT" = false ]; then
    echo "Updating $VERSION_FILE and $STATS_FILE..."
    echo "$COMMIT_MESSAGE" >> "$VERSION_FILE"
    [ -n "$STATS_LINE" ] && echo "$STATS_LINE" >> "$STATS_FILE"
fi

git add .

git commit -m "$COMMIT_MESSAGE"
git remote add origin https://github.com/isaigordeev/palace.git
git push --force origin main
git branch --set-upstream-to=origin/main main

echo "Commit successful: $COMMIT_MESSAGE"
echo "=============================================================="
