#!/usr/bin/env bash
set -e
export PATH="$HOME/.local/bin:$PATH"
cd /home/hp2/workspace/rclone-storage-automation

echo "=== 1. Starting Secondary MinIO Container on Port 9100 ==="
docker rm -f minio-secondary 2>/dev/null || true
docker run -d --name minio-secondary \
  -p 127.0.0.1:9100:9000 \
  -p 127.0.0.1:9101:9101 \
  -e MINIO_ROOT_USER=admin \
  -e MINIO_ROOT_PASSWORD=admin123 \
  quay.io/minio/minio:RELEASE.2025-04-22T22-12-26Z-cpuv1 server /data --console-address ":9101"

sleep 3

echo "=== 2. Creating Bucket on Secondary MinIO Endpoint (9100) ==="
rclone mkdir ":s3,endpoint='http://127.0.0.1:9100',access_key_id='admin',secret_access_key='admin123',provider='Minio':remote-backup" --config /dev/null -v

echo "=== 3. Transferring Files Directly Between Two Different S3 Endpoints (9000 -> 9100) ==="
rclone copy \
  ":s3,endpoint='http://127.0.0.1:9000',access_key_id='admin',secret_access_key='admin123',provider='Minio':testpress-source/documents" \
  ":s3,endpoint='http://127.0.0.1:9100',access_key_id='admin',secret_access_key='admin123',provider='Minio':remote-backup/cross-endpoint-docs" \
  --config /dev/null -v

echo "=== 4. Listing Objects on Secondary Endpoint ==="
rclone ls ":s3,endpoint='http://127.0.0.1:9100',access_key_id='admin',secret_access_key='admin123',provider='Minio':remote-backup/cross-endpoint-docs" --config /dev/null

echo "=== 5. Checking Data Integrity Across Endpoints ==="
rclone check \
  ":s3,endpoint='http://127.0.0.1:9000',access_key_id='admin',secret_access_key='admin123',provider='Minio':testpress-source/documents" \
  ":s3,endpoint='http://127.0.0.1:9100',access_key_id='admin',secret_access_key='admin123',provider='Minio':remote-backup/cross-endpoint-docs" \
  --config /dev/null

echo "Cross-endpoint transfer test completed successfully."