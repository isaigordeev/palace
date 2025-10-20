#!/bin/bash
# git_commit_encrypted.sh
# Archive, encrypt PALACE notes, stage, and commit the encrypted archive

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

# =====================================================================
# VALIDATION
# =====================================================================

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "ERROR: Not inside a Git repository."
    exit 1
fi

if [ ! -d "$PALACE_DIR" ]; then
    echo "ERROR: Notes directory not found: $PALACE_DIR"
    exit 1
fi

# =====================================================================
# ENCRYPT NOTES
# =====================================================================

sh encrypt.sh

# =====================================================================
# STAGE AND COMMIT
# =====================================================================

echo "=============================================================="
echo "STAGING AND COMMITTING"
echo "--------------------------------------------------------------"

# git add "$GPG_FILE"
git add .

# =====================================================================
echo "Cleaning old archives from history (keeping last 2)..."

# List all historical archives
ALL_ARCHIVES=( $(git log --pretty=format: --name-only --diff-filter=A | grep 'palace-.*\.tar\.gz\.gpg' | sort -V | uniq) )
NUM=${#ALL_ARCHIVES[@]}
echo "Found $NUM archive(s) in history."

if [ $NUM -le 2 ]; then
    echo "Nothing to remove. Last 2 archives are already kept."
else
    # Keep last 2
    KEEP=( "${ALL_ARCHIVES[@]: -2}" )
    echo "Keeping last 2 archives:"
    for k in "${KEEP[@]}"; do
        echo "  $k"
    done

    # Remove all others from history
    echo "Removing older archives from history:"
    for OLD in "${ALL_ARCHIVES[@]}"; do
        if [[ ! " ${KEEP[@]} " =~ " ${OLD} " ]]; then
            echo "  Removing $OLD"
        fi
    done
    # Keep last 2
    KEEP=( "${ALL_ARCHIVES[@]: -2}" )

    # Build a list of files to remove (all except last 2)
    REMOVE_LIST=$(mktemp)
    for OLD in "${ALL_ARCHIVES[@]}"; do
        if [[ ! " ${KEEP[@]} " =~ " ${OLD} " ]]; then
            echo "$OLD" >> "$REMOVE_LIST"
            echo "Marked for removal: $OLD"
        fi
    done

    # Remove older archives from history
    git filter-repo --force --paths-from-file "$REMOVE_LIST" --invert-paths
    echo "History rewritten. Only last 2 archives remain."
fi
echo "Cleanup complete."
echo "============================================================="
echo "Cleanup complete."
echo "============================================================="

COMMIT_MESSAGE="$PREFIX [$TIMESTAMP]"
git commit -m "$COMMIT_MESSAGE"

echo "Commit successful: $COMMIT_MESSAGE"
echo "=============================================================="
