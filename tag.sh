#!/bin/bash
# Script to find the most frequent word in the last commit diff
# and output a version tag. Called from sh_commit hook.
# If equal frequency, picks the longest word.
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

if $DEBUG; then
    echo "=== DEBUG: Repository ==="
    echo "Dir: $REPO_DIR"
    echo "Git dir: $REPO_DIR/.git"
    echo ""
    echo "=== DEBUG: Last commit ==="
    $GIT_CMD log -1 --oneline
    echo ""
    echo "=== DEBUG: Raw diff lines ==="
    echo "$diff_content" | head -20
    echo ""
    echo "=== DEBUG: Word frequency (top 10, min ${MIN_WORD_LEN} chars) ==="
    echo "$diff_content" | \
        perl -CSD -ne 'for (split /[^\w]+/, lc($_)) { print "$_\n" if length($_) >= '"$MIN_WORD_LEN"' && /^\p{Cyrillic}+$/ }' | \
        LC_ALL=C sort | LC_ALL=C uniq -c | LC_ALL=C sort -rn | head -10
    echo ""
fi

if [ -z "$diff_content" ]; then
    echo "version tag: \"увы\""
    exit 0
fi

# Pick the most frequent word, ties broken by longest, min MIN_WORD_LEN chars
most_frequent=$(echo "$diff_content" | \
    perl -CSD -ne 'for (split /[^\w]+/, lc($_)) { print "$_\n" if length($_) >= '"$MIN_WORD_LEN"' && /^\p{Cyrillic}+$/ }' | \
    LC_ALL=C sort | LC_ALL=C uniq -c | LC_ALL=C sort -rn | \
    perl -CSD -e '
        my ($best_count, $best_len, $best_word) = (0, 0, "");
        while (<>) {
            chomp;
            s/^\s+//;
            my ($count, $word) = split /\s+/, $_, 2;
            my $len = length($word);
            if ($count > $best_count || ($count == $best_count && $len > $best_len)) {
                $best_count = $count;
                $best_len = $len;
                $best_word = $word;
            }
        }
        print "$best_word\n";
    ')

if [ -z "$most_frequent" ]; then
    most_frequent="увы"
fi

echo "version tag: \"$most_frequent\""