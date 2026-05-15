#!/bin/bash

#this TODO just application in this script
#TODO: 1. insufficient-space detection function
#TODO: 2. network error function(maybe global)
#TODO: 3.
#TODO: 4. run this script, will collect to log, later(global)
#TODO: 5.
#TODO: 6. 
#TODO: 7.
#TODO: 8. 
#TODO: 9. env safety check
#TODO: 10. different device sync vndb database without official
#TODO: 11. colected log error 1 2, like >&2 , later

# script location independent
BASE_DIR=$(cd "$(dirname "$0")"; pwd)
#source BASE_DIR, just support .env, can't variable

# --- 1. Directory Configuration ---
#TODO: 6. later variable name will be refactoring, maybe
ORIGIN_DIR="$BASE_DIR/data-origin"
TEST_DIR="$BASE_DIR/data-test"
DATA_DIR="$BASE_DIR/data"
IMG_DIR="$BASE_DIR/vndb-img"

#TODO: 5.if this url can't touch(project never maintain), or move to another url, fixed later
URL_PREFIX="https://dl.vndb.org/dump"
IMG_SRC="rsync://dl.vndb.org/vndb-img/"

# Ensure essential directories exist
mkdir -p "$ORIGIN_DIR" "$TEST_DIR" "$DATA_DIR" "$IMG_DIR"

echo "VNDB Sync Start: $(date)"

# --- 2. Sync Compressed Dumps (aria2c) ---
echo "Checking remote updates in $ORIGIN_DIR..."

FILES=("vndb-db-latest.tar.zst" "vndb-tags-latest.json.gz" "vndb-traits-latest.json.gz" "vndb-votes-latest.gz")
NEED_UPDATE=false

# 依次下载所有文件
for file in "${FILES[@]}"; do
    echo "Processing $file..."
    if aria2c -s16 -x16 -k1M -c --check-integrity=true --conditional-get=true --allow-overwrite=true \
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

    # 重点 1：解压前，先清空 Test 目录里的旧文件夹，防止上次失败的残骸污染这次的数据
    rm -rf "$TEST_DIR/vndb-db-latest" "$TEST_DIR/vndb-tags-latest" "$TEST_DIR/vndb-traits-latest" "$TEST_DIR/vndb-votes-latest"
    mkdir -p "$TEST_DIR/vndb-db-latest" "$TEST_DIR/vndb-tags-latest" "$TEST_DIR/vndb-traits-latest" "$TEST_DIR/vndb-votes-latest"

    # 重点 2：Fail-Fast 线性解压。加了 '!' 表示如果命令执行失败，就进入 if 里面报错退出。
    
    # A. 解压 Core DB
    if ! tar -I zstd -xf "$ARCHIVE" -C "$TEST_DIR/vndb-db-latest"; then
        echo "CRITICAL ERROR: vndb-db-latest.tar.zst is corrupted! Deleting..." >&2
        rm -f "$ARCHIVE"
        exit 1
    fi
    echo "vndb-db-latest decompressed successfully."

    # B. 解压 Tags
    if ! gunzip -c "$ORIGIN_DIR/vndb-tags-latest.json.gz" > "$TEST_DIR/vndb-tags-latest/vndb-tags-latest.json"; then
        echo "CRITICAL ERROR: vndb-tags-latest.json.gz is corrupted! Deleting..." >&2
        rm -f "$ORIGIN_DIR/vndb-tags-latest.json.gz"
        exit 1
    fi
    echo "vndb-tags-latest decompressed successfully."

    # C. 解压 Traits
    if ! gunzip -c "$ORIGIN_DIR/vndb-traits-latest.json.gz" > "$TEST_DIR/vndb-traits-latest/vndb-traits-latest.json"; then
        echo "CRITICAL ERROR: vndb-traits-latest.json.gz is corrupted! Deleting..." >&2
        rm -f "$ORIGIN_DIR/vndb-traits-latest.json.gz"
        exit 1
    fi
    echo "vndb-traits-latest decompressed successfully."

    # D. 解压 Votes
    if ! gunzip -c "$ORIGIN_DIR/vndb-votes-latest.gz" > "$TEST_DIR/vndb-votes-latest/vndb-votes-latest.sql"; then
        echo "CRITICAL ERROR: vndb-votes-latest.gz is corrupted! Deleting..." >&2
        rm -f "$ORIGIN_DIR/vndb-votes-latest.gz"
        exit 1
    fi
    echo "vndb-votes-latest decompressed successfully."

    # 只有上面四步全部通关，才会执行到这里，打上哨兵标记
    touch "$SENTINEL"
    echo "All files extracted safely."
else
    echo "Files in $TEST_DIR are already natively organized."
fi

# --- 4. Deploy to Production Layer ---
if [ "$NEED_UPDATE" = true ]; then
    echo "Deploying verified data to production: $DATA_DIR"
    
    #TODO: 3. need update true, then will be test for production env, complete no error, then deploy and sync to data dir
    # rsync keeps production in sync while excluding internal metadata (.last)
    rsync -av --delete "$TEST_DIR/" "$DATA_DIR/" --exclude="*.last"
    
    echo "Production layer updated."
else
    echo "No changes detected. Production deploy skipped."
fi

# --- 5. Image Library Sync ---
#TODO: 7. this sync will be reaction with TODO3
#TODO: 8. safety check for image sync, update later, need add backup mirror file sync, maybe
#backup a vndb-img, if official image delete
echo "Running Pre-sync Safety Check..."

# simulation rsync delete file count
DEL_COUNT=$(rsync -rtpvz --del --dry-run "$IMG_SRC" "$IMG_DIR/" | grep "^deleting " | wc -l)

# get vndb image file count
VNDB_IMAGE_COUNT_FILE="$BASE_DIR/.vndb_image_count_file"
if [ -f "$VNDB_IMAGE_COUNT_FILE" ]; then
    #if exist, read it to VNDB_IMAGE_COUNT
    VNDB_IMAGE_COUNT=$(cat "$VNDB_IMAGE_COUNT_FILE")
else
    LOCAL_COUNT=$(find "$IMG_DIR" -type f | wc -l)
    VNDB_IMAGE_COUNT=$LOCAL_COUNT
fi

# calculate if delete count exceed 10%, stop it
if [ "$VNDB_IMAGE_COUNT" -gt 0 ]; then
    # set threshold at 10%
    THRESHOLD=$((VNDB_IMAGE_COUNT / 10))
    
    if [ "$DEL_COUNT" -gt "$THRESHOLD" ]; then
        echo "CRITICAL: Remote attempts to delete $DEL_COUNT files (Exceeds 10% threshold: $THRESHOLD)." >&2
        echo "SYNC ABORTED FOR SAFETY." >&2
        # backup mirror file
        exit 1
    fi
fi

if rsync -rtpvz --del --partial --timeout=60 "$IMG_SRC" "$IMG_DIR/"; then
    echo "Images synced successfully."
    echo "Calculating IMG_DIR file count for .vndb_image_count_file..."
    NEW_VNDB_IMAGE_COUNT=$(find "$IMG_DIR" -type f | wc -l)
    echo "$NEW_VNDB_IMAGE_COUNT" > "$VNDB_IMAGE_COUNT_FILE"
else
    echo "WARNING: Image sync encountered partial errors." >&2
fi

echo "VNDB Sync Finished: $(date)"