#!/usr/bin/env bash
set -e
export PATH="$HOME/.local/bin:$PATH"
cd /home/hp2/workspace/rclone-storage-automation

# Load environment
set -a
source .env
set +a

echo "=== 1. Creating S3 Buckets Config-Free ==="
rclone mkdir :s3:testpress-source --config /dev/null -v
rclone mkdir :s3:testpress-backup --config /dev/null -v

echo "=== 2. Listing Buckets ==="
rclone lsd :s3: --config /dev/null

echo "=== 3. Uploading Sample Documents to S3 Bucket (using Environment Variables) ==="
rclone copy samples/source/documents :s3:testpress-source/documents --config /dev/null -v

echo "=== 4. Uploading 100MB Media File to S3 Bucket ==="
rclone copy samples/source/media/module-01-preview.mp4 :s3:testpress-source/media/ --config /dev/null -v

echo "=== 5. Listing Objects in S3 Bucket (ls & lsf) ==="
rclone ls :s3:testpress-source --config /dev/null
echo "--- Directory structure (lsd) in S3 ---"
rclone lsd :s3:testpress-source --config /dev/null

echo "=== 6. Verifying S3 Upload Integrity with rclone check ==="
rclone check samples/source/documents :s3:testpress-source/documents --config /dev/null

echo "=== 7. Copying between two S3 buckets (Server-Side Copy) ==="
rclone copy :s3:testpress-source :s3:testpress-backup --config /dev/null -v
echo "Backup bucket contents:"
rclone ls :s3:testpress-backup --config /dev/null

echo "=== 8. Downloading from S3 to Local and Verifying ==="
mkdir -p samples/downloaded
rclone copy :s3:testpress-source/documents samples/downloaded/documents --config /dev/null -v
rclone check samples/source/documents samples/downloaded/documents --config /dev/null

echo "=== 9. Config-Free Execution Method 2: Explicit CLI Flags ==="
# Unset env vars temporarily to prove CLI flags work completely independently
env -u RCLONE_S3_ACCESS_KEY_ID -u RCLONE_S3_SECRET_ACCESS_KEY \
rclone ls :s3:testpress-source \
  --config /dev/null \
  --s3-provider Minio \
  --s3-endpoint http://127.0.0.1:9000 \
  --s3-access-key-id admin \
  --s3-secret-access-key admin123 \
  --s3-region us-east-1

echo "=== 10. Deleting an Object from S3 Bucket ==="
echo "Create temp object in S3:"
echo "Temporary upload" | rclone rcat :s3:testpress-source/temp-delete.txt --config /dev/null
echo "Verify temp object exists:"
rclone ls :s3:testpress-source/temp-delete.txt --config /dev/null
echo "Delete temp object:"
rclone deletefile :s3:testpress-source/temp-delete.txt --config /dev/null -v
echo "Verify deletion:"
rclone ls :s3:testpress-source/temp-delete.txt --config /dev/null || echo "Object successfully deleted from S3!"

echo "=== 11. Security Test: Invalid Credentials Failure Test ==="
set +e
rclone ls :s3:testpress-source \
  --config /dev/null \
  --s3-provider Minio \
  --s3-endpoint http://127.0.0.1:9000 \
  --s3-access-key-id WRONG_USER \
  --s3-secret-access-key WRONG_PASS \
  --s3-region us-east-1 2>&1
echo "Invalid credential test exited with code: $?"
set -e

echo "Phase 3 and 4 tests completed successfully."