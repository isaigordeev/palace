#!/bin/bash
# encrypt_palace.sh
# Script to archive and encrypt PALACE Markdown notes
# Overwrites previous encrypted archive if it exists

# ----- CONFIGURATION -----
PALACE_DIR="$(pwd)"                       # Directory containing your PALACE notes
RECIPIENT="F4F078EB57EA2C67C23E0F5CB94FFCADE32BE35A"   # Primary key fingerprint or email
OUTPUT_DIR="encrypted"                    # Directory to store encrypted archives
mkdir -p "$OUTPUT_DIR"

# Archive and encrypted file names
TAR_FILE="$OUTPUT_DIR/notes.tar.gz"
GPG_FILE="$TAR_FILE.gpg"

# ----- REMOVE OLD FILES IF THEY EXIST -----
if [ -f "$TAR_FILE" ]; then
    echo "Removing existing archive $TAR_FILE..."
    rm "$TAR_FILE"
fi

if [ -f "$GPG_FILE" ]; then
    echo "Removing existing encrypted file $GPG_FILE..."
    rm "$GPG_FILE"
fi

# ----- CREATE TAR ARCHIVE -----
echo "Creating tar archive..."
tar czf "$TAR_FILE" "notes"

# ----- ENCRYPT TAR FILE -----
echo "Encrypting archive with GPG..."
gpg -e -r "$RECIPIENT" -o "$GPG_FILE" "$TAR_FILE"

# ----- DELETE ORIGINAL TAR -----
rm "$TAR_FILE"

echo "Done! Encrypted archive created at:"
echo "$GPG_FILE"

