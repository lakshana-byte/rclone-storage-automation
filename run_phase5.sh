#!/usr/bin/env bash
set -e
export PATH="$HOME/.local/bin:$PATH"
cd /home/hp2/workspace/rclone-storage-automation

set -a
source .env
set +a

echo "=== 1. Calculating Local MD5 Hash of 1 GB File ==="
md5sum samples/source/large/course-archive-1gb.bin > samples/source/large/1gb.md5
cat samples/source/large/1gb.md5

echo "=== 2. Uploading 1 GB File with Bandwidth Throttling (50M) and Progress Stats ==="
rclone copy samples/source/large/course-archive-1gb.bin :s3:testpress-source/large/ \
  --config /dev/null \
  --bwlimit 50M \
  --transfers 2 \
  --stats 2s \
  --stats-one-line \
  --retries 3 \
  -v

echo "=== 3. Testing Repeated Upload (Demonstrating 0 Bytes Transferred) ==="
rclone copy samples/source/large/course-archive-1gb.bin :s3:testpress-source/large/ \
  --config /dev/null \
  -v

echo "=== 4. Simulating Interrupted Transfer and Recovery ==="
# Delete file from S3 first to test fresh interrupted upload
rclone deletefile :s3:testpress-source/large/course-archive-1gb.bin --config /dev/null

echo "Starting upload with 10M bandwidth throttle in background to simulate network cut..."
rclone copy samples/source/large/course-archive-1gb.bin :s3:testpress-source/large/ \
  --config /dev/null \
  --bwlimit 10M \
  --stats 1s \
  --stats-one-line &
PID=$!

echo "Sleeping for 3 seconds to let partial data transfer (approx 30 MB)..."
sleep 3
echo "Simulating network severance: Sending SIGKILL to transfer PID $PID"
kill -9 $PID 2>/dev/null || true
wait $PID 2>/dev/null || true
echo "Transfer abruptly terminated."

echo "Resuming transfer without bandwidth limit..."
rclone copy samples/source/large/course-archive-1gb.bin :s3:testpress-source/large/ \
  --config /dev/null \
  --stats 1s \
  --stats-one-line \
  --retries 5 \
  -v

echo "=== 5. Verifying Integrity of Uploaded 1 GB File via rclone check ==="
rclone check samples/source/large :s3:testpress-source/large --include "course-archive-1gb.bin" \
  --config /dev/null \
  --checksum

echo "Phase 5 tests completed successfully."