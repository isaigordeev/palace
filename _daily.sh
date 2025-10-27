f="$(date +'%Y-%m-%d').md"

# Build directory path
dir="notes/management/daily/$(date +'%Y')/$(date +'%m')"

# Create the directory if it doesn't exist
mkdir -p "$dir"

# Create the file
touch "$dir/$f"