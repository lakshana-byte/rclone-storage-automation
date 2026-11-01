#!/usr/bin/env bash
set -e
export PATH="$HOME/.local/bin:$PATH"
cd /home/hp2/workspace/rclone-storage-automation

echo "=== 1. Testing transfer.sh copy to S3 ==="
./transfer.sh copy samples/source/documents :s3:testpress-source/script-test --bwlimit 50M

echo "=== 2. Testing transfer.sh check ==="
./transfer.sh check samples/source/documents :s3:testpress-source/script-test

echo "=== 3. Testing transfer.sh sync (Dry-Run by Default) ==="
./transfer.sh sync samples/source/documents :s3:testpress-source/script-test

echo "=== 4. Testing transfer.sh sync with --execute ==="
./transfer.sh sync samples/source/documents :s3:testpress-source/script-test --execute

echo "=== 5. Testing Exit Code on Nonexistent Source (Expect Exit Code 3) ==="
set +e
./transfer.sh copy ./nonexistent_source_path :s3:testpress-source/script-test
EXIT_CODE_3=$?
echo "Nonexistent source exited with code: $EXIT_CODE_3 (Expected: 3)"
set -e

echo "=== 6. Testing Exit Code on Missing S3 Environment Variables (Expect Exit Code 4) ==="
set +e
env -u RCLONE_S3_ACCESS_KEY_ID -u RCLONE_S3_SECRET_ACCESS_KEY -u RCLONE_S3_ENDPOINT \
  bash -c 'mv .env .env.temp && ./transfer.sh copy samples/source/documents :s3:testpress-source/noenv; RET=$?; mv .env.temp .env; exit $RET'
EXIT_CODE_4=$?
echo "Missing S3 env exited with code: $EXIT_CODE_4 (Expected: 4)"
set -e

echo "=== 7. Verifying transfer.log entries ==="
tail -n 25 transfer.log

echo "Phase 7 tests completed successfully."