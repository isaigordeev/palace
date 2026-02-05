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

VERSION_FILE="version.txt"
# =====================================================================
# VALIDATION
# =====================================================================

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "ERROR: Not inside a Git repository."
    exit 1
fi

SKIP_ENCRYPT=false
if [ ! -d "$PALACE_DIR" ]; then
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
if [ "$SKIP_ENCRYPT" = false ]; then
    ./tag.sh "$PALACE_DIR" --debug
    VERSION_TAG=$(./tag.sh "$PALACE_DIR")
    COMMIT_MESSAGE="$PREFIX [$TIMESTAMP] $VERSION_TAG"
    echo "Updating $VERSION_FILE with latest commit info..."
    echo "$COMMIT_MESSAGE" >> "$VERSION_FILE"
else
    COMMIT_MESSAGE="$PREFIX [$TIMESTAMP]"
fi

git add .

git commit -m "$COMMIT_MESSAGE"
git remote add origin https://github.com/isaigordeev/palace.git
git push --force origin main
git branch --set-upstream-to=origin/main main

echo "Commit successful: $COMMIT_MESSAGE"
echo "=============================================================="
