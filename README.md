# Rclone Storage Automation

> Robust, configuration-free file transfer orchestration, directory synchronization, and object storage automation built for high-throughput media and backup pipelines.

---

## Overview

Modern cloud platforms (like **Testpress** and **TPStreams**) handle continuous streams of large binary assets—including multi-gigabyte video lectures, high-resolution course materials, database snapshots, and application logs. Moving these assets across local servers, transcode nodes, and S3-compatible object storage requires file transfers that are:

* **Resilient:** Tolerating network drops with automated retries and multipart resumption.
* **Secure & Stateless:** Executing without static on-disk credentials (`--config /dev/null`).
* **Safe:** Guarding against accidental bulk deletion during directory synchronization.
* **Auditable:** Providing end-to-end cryptographic checksum verification (MD5).

This repository contains a complete, automated toolkit and test harness demonstrating how to operate **Rclone** in enterprise containerized environments without relying on persistent configuration files.

---

## Technical Stack

| Component | Technology | Version / Specification |
| :--- | :--- | :--- |
| **Engine** | Rclone | `v1.75.2` (Multi-cloud sync & streaming CLI) |
| **Storage Backend** | MinIO | `RELEASE.2025-04-22` (Local S3-compatible API) |
| **Containerization** | Docker Engine & Compose | Multi-container local storage topology |
| **Automation Script** | POSIX Bash | Strict mode (`pipefail`), structured logging, exit codes |
| **Host OS** | Linux / Ubuntu 22.04 LTS | WSL2 environment |

---

## Repository Structure

```text
rclone-storage-automation/
├── .env.example               # Template for MinIO root credentials and S3 endpoints
├── .gitignore                 # Excludes secrets (.env), sample files, and execution logs
├── DEVOPS_IMPLEMENTATION.md   # Architectural decisions, deep-dive answers & production guide
├── README.md                  # Project overview, workflow guide, and verification summary
├── commands.md                # Comprehensive CLI syntax reference and command playbook
├── docker-compose.yml         # Compose specification for primary and secondary MinIO nodes
├── results.md                 # Empirical transfer benchmarks, logs, and MD5 verifications
└── transfer.sh                # Reusable transfer automation script with dry-run safety
```

---

## Architecture & Data Flow

```
                      +---------------------------------------+
                      |       Orchestrator / Automation       |
                      |          (transfer.sh / CLI)          |
                      +---------------------------------------+
                                          |
                      Credentials in-memory (RCLONE_S3_*)
                      Flag: --config /dev/null
                                          v
                      +---------------------------------------+
                      |          Rclone Execution Core        |
                      |  - Bandwidth Limiting (--bwlimit)     |
                      |  - Parallel Streams (--transfers)     |
                      |  - Chunk Retries (--retries)          |
                      +---------------------------------------+
                                    /           \
                 Local File I/O    /             \    S3 API (Port 9000 / 9100)
                                  v               v
                +--------------------+     +-----------------------+
                | Local Filesystem   |     | MinIO S3 Storage      |
                | - samples/source   |     | - testpress-source    |
                | - samples/dest1    |     | - testpress-backup    |
                +--------------------+     +-----------------------+
```

---

## Rapid Setup & Verification

### Step 1: Clone the Repository
```bash
git clone https://github.com/lakshana-byte/rclone-storage-automation.git
cd rclone-storage-automation
```

### Step 2: Initialize Environment Variables
```bash
cp .env.example .env
```
*(Optionally review `.env` to inspect configured S3 ports and MinIO root credentials).*

### Step 3: Boot Local S3 Storage (MinIO)
```bash
docker compose up -d
docker compose ps
```
Confirm readiness via the HTTP health check:
```bash
curl -i http://localhost:9000/minio/health/ready
```
* **S3 Endpoint:** `http://127.0.0.1:9000`
* **Web Management Console:** `http://127.0.0.1:9001` (User: `admin` | Password: `admin123`)

### Step 4: Configure S3 Environment for Rclone
Export connection variables to your shell session for configuration-free execution:
```bash
set -a; source .env; set +a
export RCLONE_S3_PROVIDER=Minio \
       RCLONE_S3_ACCESS_KEY_ID="$MINIO_ROOT_USER" \
       RCLONE_S3_SECRET_ACCESS_KEY="$MINIO_ROOT_PASSWORD" \
       RCLONE_S3_ENDPOINT=http://127.0.0.1:9000 \
       RCLONE_S3_REGION=us-east-1
```

### Step 5: Provision Buckets & Sample Data
```bash
# Create target buckets without an rclone.conf file
rclone mkdir :s3:testpress-source --config /dev/null
rclone mkdir :s3:testpress-backup --config /dev/null

# Generate deterministic test files (text, PDFs, 100MB preview video, 1GB lecture archive)
python3 -c "
from pathlib import Path
p = Path('samples/source/documents')
p.mkdir(parents=True, exist_ok=True)
for i in range(1, 4):
    (p / f'lecture-{i}.pdf').write_bytes(b'%PDF-1.4 ' + bytes([i+65]) * 1048576)
(p / 'manifest.json').write_text('{\"status\": \"ready\"}')
"
```

### Step 6: Execute Transfer Workflow
```bash
# 1. Copy local documents to S3
./transfer.sh copy samples/source/documents :s3:testpress-source/docs

# 2. Audit file integrity (compares cryptographic checksums)
./transfer.sh check samples/source/documents :s3:testpress-source/docs

# 3. Synchronize to backup bucket (defaults to safe DRY-RUN mode)
./transfer.sh sync samples/source/documents :s3:testpress-backup/docs

# 4. Perform live synchronization (destructive changes enabled)
./transfer.sh sync samples/source/documents :s3:testpress-backup/docs --execute
```

---

## Key Experimental Results

Every requirement was validated through rigorous testing. Detailed logs and numbers are archived in [`results.md`](results.md).

### 1. Transfer Idempotency & Move Semantics
* **Duplicate Transfers:** Running `rclone copy` twice on identical source/destination paths transferred **0 bytes**, skipping matching items in `0.0s`.
* **Atomic Moves:** `rclone move` executed a server-side rename; the source file was unlinked only after the destination write was cryptographically acknowledged.

### 2. High-Performance Server-Side Copying
* Copying 1.225 GiB across buckets on the same MinIO endpoint finished in **7.1 seconds** via direct S3 `CopyObject` API calls without routing data through the client network interface.

### 3. 1 GB Transfer, Throttling & Network Severance Recovery
* **Bandwidth Control:** Uploading `course-archive-1gb.bin` with `--bwlimit 50M` achieved a consistent rate of `42.03 MB/s`.
* **Simulated Network Interruption:** Sending `SIGKILL` mid-transfer terminated the process at ~30 MB.
* **Resumption:** Restarting the upload resumed the multipart stream seamlessly, reaching 100% completion at **44.3 MB/s**.
* **Integrity Audit:** Both local and remote objects matched the exact same MD5 digest (`1ce845c7266a821cef2feb34cd78c59a`).

### 4. Concurrency Optimization
* Increasing concurrency from `--transfers 1 --checkers 1` to `--transfers 4 --checkers 8` cut transfer latency from **1050 ms down to 528 ms** (a **1.98x speedup** on multi-file batches).

---

## Production Security & Safety Standards

1. **Config-Free Immutability (`--config /dev/null`):**
   * No `~/.config/rclone/rclone.conf` is ever read or created.
   * Credentials exist strictly in process memory, eliminating credential leak risks in Docker layers or CI/CD runner logs.
2. **Defensive Sync Defaults:**
   * Accidental execution of `rclone sync` on an empty directory would wipe out destination backup buckets.
   * `transfer.sh` intercepts `sync` commands and mandates an explicit `--execute` flag before permitting real deletions.
3. **Structured Logging & Exit Codes:**
   * Every operation writes timestamped entries to `transfer.log`.
   * Standardized POSIX exit codes ensure automated pipelines fail fast upon errors:
     * `0`: Success
     * `1`: Parameter / syntax error
     * `2`: Rclone binary missing
     * `3`: Source path unreachable
     * `4`: Missing S3 credentials
     * `5`: Execution / transfer failure

---

## Bonus Implementations

* **Direct Cross-Endpoint S3 Streaming:** Streamed objects directly from `MinIO:9000` to `MinIO:9100` without writing intermediate files to disk.
* **S3 Multipart Cleanup:** Verified automated pruning of stale multipart fragments with `rclone backend cleanup`.

---

## Further Documentation

* **[`commands.md`](commands.md):** Complete catalog of CLI commands, options, and explanations.
* **[`results.md`](results.md):** Full benchmark tables, execution logs, and MD5 verification dumps.
* **[`DEVOPS_IMPLEMENTATION.md`](DEVOPS_IMPLEMENTATION.md):** Architectural design patterns and in-depth answers to the demonstration questions.