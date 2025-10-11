#!/bin/bash

SRC_DIR="/src/"
DST_DIR="/dst/"

mkdir -p "$DST_DIR"

find "$SRC_DIR" -type f -print0 | while IFS= read -r -d '' SRC; do
    [[ "$(basename "$SRC")" == ".DS_Store" ]] && continue

    REL="${SRC#$SRC_DIR/}"
    DST="$DST_DIR/$REL"

    if [ -f "$DST" ]; then
        CREATION=$(stat -f %B "$SRC")
        CREATION_STR=$(date -r "$CREATION" +"%m/%d/%Y %H:%M:%S")
        CREATION_ISO=$(date -r "$CREATION" -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "\"$SRC\" > \"$DST\": $CREATION_STR"
        SetFile -d "$CREATION_STR" "$DST"
        xattr -w com.apple.metadata:kMDItemFSCreationDate "$CREATION_ISO" "$DST"
    fi
done