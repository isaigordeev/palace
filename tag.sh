#!/bin/bash
# Script to find the longest word in the last commit diff
# and output a version tag. Called from sh_commit hook.
# If equal length, picks the most frequent word.
# Words must be at least MIN_WORD_LEN characters.
#
# Usage: tag.sh [repo_dir] [--debug]
#   repo_dir: defaults to ./palace
#   --debug: show detailed analysis

set -e
export LC_ALL=en_US.UTF-8

REPO_DIR="./palace"
DEBUG=false
MIN_WORD_LEN=3

for arg in "$@"; do
    case $arg in
        --debug)
            DEBUG=true
            ;;
        *)
            REPO_DIR="$arg"
            ;;
    esac
done

# Resolve to absolute path
REPO_DIR=$(cd "$REPO_DIR" && pwd)

# Check if this directory has its own .git
if [ ! -d "$REPO_DIR/.git" ]; then
    echo "Error: $REPO_DIR is not a git repository (no .git directory)" >&2
    exit 1
fi

# Force git to use THIS repo's .git, not a parent
GIT_CMD="git --git-dir=$REPO_DIR/.git --work-tree=$REPO_DIR"

# Get the diff from the last commit (added/removed content only, no metadata)
diff_content=$($GIT_CMD show HEAD --format="" --unified=0 2>/dev/null | grep -E '^[+-]' | grep -vE '^[+-]{3}' | sed 's/^[+-]//' || true)

# Rank candidates from diff content. Emits TSV `len<TAB>count<TAB>word`,
# sorted longest-first then most-frequent. Filters: min MIN_WORD_LEN chars, Cyrillic only.
rank_candidates() {
    echo "$1" | \
        perl -CSD -ne 'for (split /[^\w]+/, lc($_)) { print "$_\n" if length($_) >= '"$MIN_WORD_LEN"' && /^\p{Cyrillic}+$/ }' | \
        LC_ALL=C sort | LC_ALL=C uniq -c | \
        perl -CSD -e '
            my @rows;
            while (<>) {
                chomp; s/^\s+//;
                my ($c, $w) = split /\s+/, $_, 2;
                push @rows, [length($w), $c+0, $w];
            }
            @rows = sort { $b->[0] <=> $a->[0] || $b->[1] <=> $a->[1] } @rows;
            for my $r (@rows) {
                printf("%d\t%d\t%s\n", $r->[0], $r->[1], $r->[2]);
            }
        '
}

if $DEBUG; then
    echo "=== DEBUG: Repository ==="
    echo "Dir: $REPO_DIR"
    echo "Git dir: $REPO_DIR/.git"
    echo ""
    echo "=== DEBUG: Diff scope ==="
    echo "Source: git show HEAD (last 1 commit only — not a range)"
    echo ""
    echo "=== DEBUG: Last commit ==="
    $GIT_CMD log -1 --oneline
    echo ""
    echo "=== DEBUG: Raw diff lines ==="
    echo "$diff_content" | head -20
    echo ""
    echo "=== DEBUG: Top 10 candidates (longest first, freq tiebreak, min ${MIN_WORD_LEN} chars, Cyrillic only) ==="
    rank_candidates "$diff_content" | head -10 | \
        awk -F'\t' '{ printf "  len=%-2d count=%-3d  %s\n", $1, $2, $3 }'
    echo ""
fi

if [ -z "$diff_content" ]; then
    echo "version tag: \"увы\""
    exit 0
fi

# Pick the longest word, ties broken by frequency (first row of ranked candidates)
most_frequent=$(rank_candidates "$diff_content" | head -1 | cut -f3)

if [ -z "$most_frequent" ]; then
    most_frequent="увы"
fi

echo "version tag: \"$most_frequent\""