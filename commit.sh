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

git filter-repo --strip-blobs-bigger-than 1M

sh encrypt.sh

# =====================================================================
# STAGE AND COMMIT
# =====================================================================

echo "=============================================================="
echo "STAGING AND COMMITTING"
echo "--------------------------------------------------------------"

git add .

COMMIT_MESSAGE="$PREFIX [$TIMESTAMP]"
git commit -m "$COMMIT_MESSAGE"

echo "Commit successful: $COMMIT_MESSAGE"
echo "=============================================================="
