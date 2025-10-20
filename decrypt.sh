#!/bin/bash
# decrypt_palace.sh
# Decrypt and extract PALACE Markdown notes
# Automatically finds the latest encrypted archive

# =====================================================================
# CONFIGURATION
# =====================================================================

PALACE_DIR="$(pwd)"                        # Directory containing your PALACE files
LATEST_FILE=$(ls -t palace-*.tar.gz.gpg 2>/dev/null | head -n 1)  # Find latest encrypted archive
DECRYPTED_TAR="palace-decrypted.tar.gz"
PALACE_SUBDIR="palace"

# =====================================================================
# START
# =====================================================================

echo "=============================================================="
echo "PALACE DECRYPTION SCRIPT"
echo "--------------------------------------------------------------"
echo "Working directory: $PALACE_DIR"
echo "=============================================================="
echo

# =====================================================================
# CHECK INPUT FILE
# =====================================================================

echo "[1] Checking for latest encrypted archive..."
if [ -z "$LATEST_FILE" ]; then
    echo "    ERROR: No encrypted file found (notes-*.tar.gz.gpg)."
    exit 1
else
    echo "    Found encrypted file: $LATEST_FILE"
fi
echo

# =====================================================================
# DECRYPT FILE
# =====================================================================

echo "[2] Decrypting with GPG..."
if gpg -o "$DECRYPTED_TAR" -d "$LATEST_FILE"; then
    echo "    Decryption successful: $DECRYPTED_TAR"
else
    echo "    ERROR: GPG decryption failed."
    exit 1
fi
echo

# =====================================================================
# EXTRACT ARCHIVE
# =====================================================================

echo "[3] Extracting archive contents..."
if tar xzf "$DECRYPTED_TAR"; then
    echo "    Notes extracted to: $PALACE_SUBDIR/"
else
    echo "    ERROR: Failed to extract tar archive."
    exit 1
fi
echo

# =====================================================================
# CLEANUP
# =====================================================================

echo "[4] Cleaning up temporary files..."
rm -f "$DECRYPTED_TAR"
echo "    Temporary decrypted archive removed."
echo

# =====================================================================
# SUMMARY
# =====================================================================

echo "=============================================================="
echo "DECRYPTION COMPLETE"
echo "--------------------------------------------------------------"
echo "Restored notes directory: $PALACE_SUBDIR/"
echo "=============================================================="
echo
