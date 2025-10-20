#!/bin/bash
# encrypt_palace.sh
# Archive and encrypt PALACE Markdown notes
# Keeps only the latest encrypted archive (deletes old ones)

# =====================================================================
# CONFIGURATION
# =====================================================================

PALACE_DIR="$(pwd)"                       # Directory containing your PALACE notes
RECIPIENT="F4F078EB57EA2C67C23E0F5CB94FFCADE32BE35A"   # GPG key fingerprint or email
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")       # Timestamp for naming
TAR_FILE="palace-$TIMESTAMP.tar.gz"
GPG_FILE="$TAR_FILE.gpg"

# =====================================================================
# START
# =====================================================================

echo "=============================================================="
echo "PALACE ENCRYPTION SCRIPT"
echo "--------------------------------------------------------------"
echo "Working directory: $PALACE_DIR"
echo "Timestamp:         $TIMESTAMP"
echo "=============================================================="
echo

# =====================================================================
# CLEAN UP OLD FILES
# =====================================================================

echo "[1] Removing old encrypted archives..."
OLD_FILES=$(ls palace-*.tar.gz.gpg 2>/dev/null)

if [ -n "$OLD_FILES" ]; then
    for f in $OLD_FILES; do
        rm -f "$f" && echo "    Removed: $f"
    done
else
    echo "    No previous encrypted files found."
fi
echo

# =====================================================================
# CREATE TAR ARCHIVE
# =====================================================================

echo "[2] Creating tar archive..."
if tar czf "$TAR_FILE" "palace" 2>/dev/null; then
    echo "    Archive created: $TAR_FILE"
else
    echo "    ERROR: Failed to create tar archive."
    exit 1
fi
echo

# =====================================================================
# ENCRYPT TAR FILE
# =====================================================================

echo "[3] Encrypting archive with GPG..."
if gpg -e -r "$RECIPIENT" -o "$GPG_FILE" "$TAR_FILE"; then
    echo "    Encrypted file created: $GPG_FILE"
else
    echo "    ERROR: GPG encryption failed."
    rm -f "$TAR_FILE"
    exit 1
fi
echo

# =====================================================================
# CLEANUP
# =====================================================================

echo "[4] Removing unencrypted archive..."
rm "$TAR_FILE"
echo "    Unencrypted file removed."
echo

# =====================================================================
# SUMMARY
# =====================================================================

echo "=============================================================="
echo "ENCRYPTION COMPLETE"
echo "--------------------------------------------------------------"
echo "Encrypted archive: $GPG_FILE"
echo "=============================================================="
echo
