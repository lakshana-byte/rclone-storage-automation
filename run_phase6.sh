#!/usr/bin/env bash
set -e
export PATH="$HOME/.local/bin:$PATH"
cd /home/hp2/workspace/rclone-storage-automation

set -a
source .env
set +a

echo "=== 1. Setting up Divergent Source and Destination Directories ==="
mkdir -p samples/sync_source samples/sync_dest

# Source has v2 of doc, new file, and missing old file
echo "Version 2 of course document" > samples/sync_source/doc.txt
echo "Brand new source file" > samples/sync_source/new_lesson.txt

# Destination has v1 of doc, and an orphaned obsolete file
echo "Version 1 of course document (old)" > samples/sync_dest/doc.txt
echo "Obsolete destination file that was removed from source" > samples/sync_dest/deprecated_module.txt

echo "Source files:"
rclone ls samples/sync_source --config /dev/null
echo "Destination files before sync:"
rclone ls samples/sync_dest --config /dev/null

echo "=== 2. Pre-Sync Verification with rclone check ==="
set +e
rclone check samples/sync_source samples/sync_dest --config /dev/null
set -e

echo "=== 3. Safe Dry-Run Simulation (--dry-run) ==="
# Notice: identifies that deprecated_module.txt would be DELETED and doc.txt would be UPDATED
rclone sync samples/sync_source samples/sync_dest --config /dev/null --dry-run -v

echo "Verify that destination was NOT modified during dry-run:"
rclone ls samples/sync_dest --config /dev/null

echo "=== 4. Executing Real Sync (Destructive Operation) ==="
rclone sync samples/sync_source samples/sync_dest --config /dev/null -v

echo "Destination files after real sync:"
rclone ls samples/sync_dest --config /dev/null
cat samples/sync_dest/doc.txt

echo "=== 5. Post-Sync Integrity Verification ==="
rclone check samples/sync_source samples/sync_dest --config /dev/null

echo "Phase 6 experiments completed successfully."