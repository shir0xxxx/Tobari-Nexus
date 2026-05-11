#!/bin/bash

#TODO: insufficient-space detection function
#TODO: network error function(maybe global)
#TODO: step 4 delete and rebuild
#TODO: run this script, will collect to log, later(global)

# --- 1. Directory Configuration ---
BASE_DIR="$HOME/vndb-sync"
ORIGIN_DIR="$BASE_DIR/data-origin"
TEST_DIR="$BASE_DIR/data-test"
DATA_DIR="$BASE_DIR/data"
IMG_DIR="$BASE_DIR/vndb-img"

URL_PREFIX="https://dl.vndb.org/dump"
IMG_SRC="rsync://dl.vndb.org/vndb-img/"

# Ensure essential directories exist
mkdir -p "$ORIGIN_DIR" "$TEST_DIR" "$DATA_DIR" "$IMG_DIR"

echo "VNDB Sync Start: $(date)"

# --- 2. Sync Compressed Dumps (aria2c) ---
echo "Checking remote updates in $ORIGIN_DIR..."

FILES=("vndb-db-latest.tar.zst" "vndb-tags-latest.json.gz" "vndb-traits-latest.json.gz" "vndb-votes-latest.gz")
NEED_UPDATE=false

for file in "${FILES[@]}"; do
    echo "Processing $file..."
    # -o "$file": Ensures the local file name is fixed to 'latest' regardless of server redirect
    # --conditional-get: only downloads if server-side timestamp is newer than local
    if aria2c -s16 -x16 -k1M -c --conditional-get=true --allow-overwrite=true \
       --auto-file-renaming=false -o "$file" -d "$ORIGIN_DIR" "$URL_PREFIX/$file"; then
        echo "$file check completed."
    else
        echo "FATAL ERROR: $file download failed!" >&2
        exit 1
    fi
done

# --- 3. Process & Extract to Test Layer ---
SENTINEL="$TEST_DIR/vndb-db-latest.tar.zst.last"
ARCHIVE="$ORIGIN_DIR/vndb-db-latest.tar.zst"

if [ "$ARCHIVE" -nt "$SENTINEL" ]; then
    echo "Newer archive detected. Extracting to native structures in $TEST_DIR..."
    NEED_UPDATE=true

    # --- A. Extract Core DB Archive ---
    # This usually creates its own 'db' folder, but we put it in its own namespace for safety
    mkdir -p "$TEST_DIR/vndb-db-latest"
    tar -I zstd -xf "$ARCHIVE" -C "$TEST_DIR/vndb-db-latest"
    
    # --- B. Handle JSON & Other Files ---
    # We create a directory for each type to keep it "Original"
    
    # Tags
    mkdir -p "$TEST_DIR/vndb-tags-latest"
    gunzip -c "$ORIGIN_DIR/vndb-tags-latest.json.gz" > "$TEST_DIR/vndb-tags-latest/tags.json"
    
    # Traits
    mkdir -p "$TEST_DIR/vndb-traits-latest"
    gunzip -c "$ORIGIN_DIR/vndb-traits-latest.json.gz" > "$TEST_DIR/vndb-traits-latest/traits.json"
    
    # Votes
    mkdir -p "$TEST_DIR/vndb-votes-latest"
    gunzip -c "$ORIGIN_DIR/vndb-votes-latest.gz" > "$TEST_DIR/vndb-votes-latest/votes.sql"

    touch "$SENTINEL"
else
    echo "Files in $TEST_DIR are already natively organized."
fi

# --- 4. Deploy to Production Layer ---
if [ "$NEED_UPDATE" = true ]; then
    echo "Deploying verified data to production: $DATA_DIR"
    
    # rsync keeps production in sync while excluding internal metadata (.last)
    rsync -av --delete "$TEST_DIR/" "$DATA_DIR/" --exclude="*.last"
    
    echo "Production layer updated."
else
    echo "No changes detected. Production deploy skipped."
fi

# --- 5. Image Library Sync ---
echo "Syncing images via Rsync..."
if rsync -rtpvz --del --partial --timeout=60 "$IMG_SRC" "$IMG_DIR/"; then
    echo "Images synced successfully."
else
    echo "WARNING: Image sync encountered partial errors." >&2
fi

echo "VNDB Sync Finished: $(date)"