# Rclone Commands Reference & Playbook

This document details all Rclone commands used throughout the storage automation project, complete with CLI options, practical explanations, and output analysis.

---

## 1. Environment & Setup

### Verifying Tools
```bash
rclone version
docker --version
docker-compose --version
```

### Starting MinIO S3-Compatible Local Storage
```bash
# Start MinIO via Docker Compose
docker-compose up -d

# Verify MinIO health check
curl -i http://localhost:9000/minio/health/ready
```

---

## 2. Basic Local File Operations

### 2.1 Listing Files and Directories
```bash
# List all files recursively with human-readable sizes
rclone ls samples/source/documents --config /dev/null

# List subdirectories only (similar to ls -d)
rclone lsd samples/source --config /dev/null

# List files with exact modification timestamps and sizes
rclone lsl samples/source/documents --config /dev/null

# List directory tree
rclone tree samples/source/documents --config /dev/null
```

### 2.2 Copying Files (`rclone copy`)
```bash
# Copy files from source to destination (skips identical files, preserves destination-only files)
rclone copy samples/source/documents samples/dest1 --config /dev/null -v

# Repeating the same copy command (0 bytes transferred; validates idempotency)
rclone copy samples/source/documents samples/dest1 --config /dev/null -v
```

### 2.3 Checking File Integrity (`rclone check`)
```bash
# Verify checksums and sizes between source and destination (returns 0 differences when identical)
rclone check samples/source/documents samples/dest1 --config /dev/null
```

### 2.4 Moving Files (`rclone move`)
```bash
# Transfer file from source to destination and delete source file upon verified completion
rclone move samples/source/temp_move samples/dest_move --config /dev/null -v
```

### 2.5 Safe Synchronization (`rclone sync`)
```bash
# Preview changes without modifying destination (dry-run mode)
rclone sync samples/source/documents samples/dest1 --config /dev/null --dry-run -v

# Perform actual synchronization (DELETES destination-only files to mirror source)
rclone sync samples/source/documents samples/dest1 --config /dev/null -v
```

### 2.6 Deleting Files (`rclone delete`)
```bash
# Delete all files in a directory without removing the directory structure
rclone delete samples/delete_test --config /dev/null -v

# Delete a single specific file
rclone deletefile samples/dest1/notes.txt --config /dev/null -v
```

---

## 3. S3-Compatible Object Storage Operations

### 3.1 Creating Buckets
```bash
# Create buckets on local MinIO
rclone mkdir :s3:testpress-source --config /dev/null
rclone mkdir :s3:testpress-backup --config /dev/null

# List all S3 buckets
rclone lsd :s3: --config /dev/null
```

### 3.2 Uploading to S3
```bash
# Upload directory to S3 bucket
rclone copy samples/source/documents :s3:testpress-source/documents --config /dev/null -v

# Upload single 100MB media file
rclone copy samples/source/media/module-01-preview.mp4 :s3:testpress-source/media/ --config /dev/null -v
```

### 3.3 Listing S3 Objects
```bash
# Recursively list all objects and sizes in bucket
rclone ls :s3:testpress-source --config /dev/null

# List top-level object prefixes (directories) in S3
rclone lsd :s3:testpress-source --config /dev/null
```

### 3.4 Bucket-to-Bucket Server-Side Copying
```bash
# Copy directly between two S3 buckets on the same endpoint (performed server-side)
rclone copy :s3:testpress-source :s3:testpress-backup --config /dev/null -v
```

### 3.5 Downloading from S3
```bash
# Download objects from S3 to local filesystem
rclone copy :s3:testpress-source/documents samples/downloaded/documents --config /dev/null -v
```

### 3.6 Deleting S3 Objects
```bash
# Delete specific object from S3
rclone deletefile :s3:testpress-source/temp-delete.txt --config /dev/null -v

# Empty an S3 bucket
rclone delete :s3:testpress-source/temporary-data --config /dev/null -v
```

---

## 4. Configuration-Free Execution

### Method 1: Environment Variables (Recommended for Containers & Workers)
```bash
export RCLONE_S3_PROVIDER=Minio
export RCLONE_S3_ACCESS_KEY_ID=admin
export RCLONE_S3_SECRET_ACCESS_KEY=admin123
export RCLONE_S3_ENDPOINT=http://127.0.0.1:9000
export RCLONE_S3_REGION=us-east-1

# Execute S3 operations without any rclone.conf
rclone ls :s3:testpress-source --config /dev/null
```

### Method 2: Command-Line Flags (Explicit Override)
```bash
rclone ls :s3:testpress-source \
  --config /dev/null \
  --s3-provider Minio \
  --s3-endpoint http://127.0.0.1:9000 \
  --s3-access-key-id admin \
  --s3-secret-access-key admin123 \
  --s3-region us-east-1
```

### Method 3: Connection String Syntax (Multi-Endpoint Support)
```bash
rclone ls ":s3,endpoint='http://127.0.0.1:9000',access_key_id='admin',secret_access_key='admin123',provider='Minio':testpress-source" \
  --config /dev/null
```

---

## 5. Large File Transfers & Reliability

### 5.1 Bandwidth Throttling & Progress Reporting
```bash
# Upload 1 GB file throttled to 50 MB/s with progress stats every 2 seconds
rclone copy samples/source/large/course-archive-1gb.bin :s3:testpress-source/large/ \
  --config /dev/null \
  --bwlimit 50M \
  --transfers 2 \
  --stats 2s \
  --stats-one-line \
  --retries 3 \
  -v
```

### 5.2 Network Interruption and Resumption
```bash
# Start throttled transfer in background
rclone copy samples/source/large/course-archive-1gb.bin :s3:testpress-source/large/ \
  --config /dev/null \
  --bwlimit 10M \
  --stats 1s \
  --stats-one-line &
TRANSFER_PID=$!

# Terminate process abruptly
kill -9 $TRANSFER_PID

# Resume transfer with retries
rclone copy samples/source/large/course-archive-1gb.bin :s3:testpress-source/large/ \
  --config /dev/null \
  --stats 1s \
  --retries 5 \
  -v

# Verify integrity with MD5 checksum
rclone check samples/source/large :s3:testpress-source/large \
  --include "course-archive-1gb.bin" \
  --config /dev/null \
  --checksum
```

---

## 6. Automation with `transfer.sh`

```bash
# Copy local directory to S3
./transfer.sh copy samples/source/documents :s3:testpress-source/quickstart

# Safe sync (DRY-RUN simulation by default)
./transfer.sh sync samples/source/documents :s3:testpress-backup/quickstart

# Real sync with destructive deletion enabled
./transfer.sh sync samples/source/documents :s3:testpress-backup/quickstart --execute

# Integrity check
./transfer.sh check samples/source/documents :s3:testpress-source/quickstart

# Copy with custom concurrency, retries, and bandwidth throttling
./transfer.sh copy samples/source/media :s3:testpress-source/media \
  --bwlimit 25M \
  --transfers 4 \
  --checkers 8 \
  --retries 5 \
  --log-file ./custom_transfer.log
```

---

## 7. Bonus Challenges

### 7.1 Cross-Endpoint Direct S3 Transfer (9000 -> 9100)
```bash
rclone copy \
  ":s3,endpoint='http://127.0.0.1:9000',access_key_id='admin',secret_access_key='admin123',provider='Minio':testpress-source/documents" \
  ":s3,endpoint='http://127.0.0.1:9100',access_key_id='admin',secret_access_key='admin123',provider='Minio':remote-backup/cross-endpoint-docs" \
  --config /dev/null -v
```

### 7.2 On-the-Fly Client-Side Encryption (`crypt` backend)
```bash
# Obfuscate encryption password
ENC_PW=$(rclone obscure "SuperSecretPassword123" --config /dev/null)

# Upload encrypted objects to S3 (encrypts both data and filenames)
rclone copy samples/source/documents \
  ":crypt,remote=':s3:testpress-source/vault',password='$ENC_PW':" \
  --config /dev/null -v

# Download and transparently decrypt
rclone copy \
  ":crypt,remote=':s3:testpress-source/vault',password='$ENC_PW':" \
  samples/decrypted \
  --config /dev/null -v
```

### 7.3 Multipart Upload Cleanup
```bash
# Abort and remove dangling incomplete multipart uploads older than 24 hours
rclone backend cleanup :s3:testpress-source --config /dev/null -v
```

### 7.4 Python Microservice / Celery Worker Invocation
```bash
python3 transfer_worker.py ./samples/source/documents :s3:testpress-source/python-test
```

### 7.5 Scheduled Cron Execution
```bash
./cron_backup.sh
```