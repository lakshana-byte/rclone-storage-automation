#!/usr/bin/env bash
set -e
export PATH="$HOME/.local/bin:$PATH"
cd /home/hp2/workspace/rclone-storage-automation

set -a
source .env
set +a

echo "=== 1. Uploading Encrypted Data to S3 using on-the-fly crypt backend ==="
# Obfuscate passwords using rclone obscure
OBSCURED_PW=$(rclone obscure "SuperSecretPassword123" --config /dev/null)

rclone copy samples/source/documents \
  ":crypt,remote=':s3:testpress-source/vault',password='$OBSCURED_PW':" \
  --config /dev/null -v

echo "=== 2. Viewing Raw Encrypted Objects in S3 (Demonstrating Encrypted Filenames and Data) ==="
rclone ls :s3:testpress-source/vault --config /dev/null

echo "=== 3. Downloading and Decrypting Transparently ==="
mkdir -p samples/decrypted
rclone copy \
  ":crypt,remote=':s3:testpress-source/vault',password='$OBSCURED_PW':" \
  samples/decrypted \
  --config /dev/null -v

echo "=== 4. Verifying Decrypted Content Matches Original ==="
rclone check samples/source/documents samples/decrypted --config /dev/null

echo "Crypt backend test completed successfully."