#!/usr/bin/env bash
set -e
export PATH="$HOME/.local/bin:$PATH"
cd /home/hp2/workspace/rclone-storage-automation

set -a
source .env
set +a

echo "=== Verifying 1 GB File Checksum via rclone check ==="
rclone check samples/source/large :s3:testpress-source/large --config /dev/null

echo "=== Remote MD5 checksum via rclone md5sum ==="
rclone md5sum :s3:testpress-source/large/course-archive-1gb.bin --config /dev/null

echo "=== Local MD5 checksum ==="
cat samples/source/large/1gb.md5