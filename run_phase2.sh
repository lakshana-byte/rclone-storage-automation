#!/usr/bin/env bash
set -e
export PATH="$HOME/.local/bin:$PATH"
cd /home/hp2/workspace/rclone-storage-automation

echo "=== 1. Listing files in samples/source/documents ==="
rclone ls samples/source/documents --config /dev/null

echo "=== 2. Listing directories (lsd) ==="
rclone lsd samples/source --config /dev/null

echo "=== 3. Listing with timestamps (lsl) ==="
rclone lsl samples/source/documents --config /dev/null

echo "=== 4. Copying documents to samples/dest1 ==="
rclone copy samples/source/documents samples/dest1 --config /dev/null -v

echo "=== 5. Re-running copy (demonstrating skipping unchanged files) ==="
rclone copy samples/source/documents samples/dest1 --config /dev/null -v

echo "=== 6. Checking whether files at two locations are identical ==="
rclone check samples/source/documents samples/dest1 --config /dev/null

echo "=== 7. Moving a file to samples/move_test and verifying source removal ==="
mkdir -p samples/source/temp_move samples/dest_move
echo 'Move test content' > samples/source/temp_move/to_move.txt
rclone move samples/source/temp_move samples/dest_move --config /dev/null -v
echo "Checking if source file still exists:"
ls -la samples/source/temp_move/to_move.txt 2>&1 || echo "Source file successfully removed by rclone move!"
echo "Checking destination file:"
cat samples/dest_move/to_move.txt

echo "=== 8. Synchronizing directories and observing deletion of extra files ==="
echo 'Extra file only at dest' > samples/dest1/extra-dest-only.txt
echo "Destination files before sync:"
rclone ls samples/dest1 --config /dev/null

echo "--- Running rclone sync with --dry-run ---"
rclone sync samples/source/documents samples/dest1 --config /dev/null --dry-run -v

echo "--- Running rclone sync (for real) ---"
rclone sync samples/source/documents samples/dest1 --config /dev/null -v

echo "Destination files after real sync:"
rclone ls samples/dest1 --config /dev/null

echo "=== 9. Deleting files from destination ==="
mkdir -p samples/delete_test
echo 'File 1' > samples/delete_test/file1.txt
echo 'File 2' > samples/delete_test/file2.txt
rclone delete samples/delete_test --config /dev/null -v
echo "Contents of delete_test after rclone delete:"
rclone ls samples/delete_test --config /dev/null || true
echo "Phase 2 tests completed successfully."