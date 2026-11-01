# Rclone Storage Automation

Hands-on DevOps exercise demonstrating file transfers, synchronization, verification, and S3-compatible object storage using Rclone.

## Technology Stack
* Rclone v1.75.2
* Docker and Docker Compose
* MinIO (local S3-compatible object storage)
* Bash scripting
* Python 3
* Linux development environment (Ubuntu 22.04 LTS / WSL2)

## Project Structure
```text
rclone-storage-automation/
├── README.md                  # Project overview
├── commands.md                # Commands and examples
├── results.md                 # Experiment observations
├── DEVOPS_IMPLEMENTATION.md   # Architectural decisions & question answers
├── docker-compose.yml         # MinIO setup
├── transfer.sh                # Reusable transfer script
├── run_rclone.py              # Python subprocess transfer execution
├── cron-example.txt           # Cron automation example
├── .env.example               # Example MinIO environment variables
└── .gitignore                 # Excluded local files and credentials
```

## Quick Start

### Prerequisites
Git, Docker Compose, Rclone, Python 3 and Bash.

### 1. Clone the repository
```bash
git clone https://github.com/lakshana-byte/rclone-storage-automation.git
cd rclone-storage-automation
```

### 2. Configure MinIO
```bash
cp .env.example .env
```
Replace the placeholder password with a strong password. Never commit `.env`.

### 3. Start MinIO
```bash
docker compose up -d
docker compose ps
curl -i http://localhost:9000/minio/health/ready
```

### 4. Configure Rclone
```bash
set -a; source .env; set +a
export RCLONE_S3_PROVIDER=Minio RCLONE_S3_ACCESS_KEY_ID="$MINIO_ROOT_USER" RCLONE_S3_SECRET_ACCESS_KEY="$MINIO_ROOT_PASSWORD" RCLONE_S3_ENDPOINT=http://127.0.0.1:9000 RCLONE_S3_REGION=us-east-1
```

### 5. Create S3 buckets
```bash
rclone mkdir :s3:testpress-source --config /dev/null
rclone mkdir :s3:testpress-backup --config /dev/null
```

### 6. Generate sample files
```bash
python3 -c "from pathlib import Path; p=Path('samples/source/documents'); p.mkdir(parents=True, exist_ok=True); [(p / f'file-{i}.bin').write_bytes(bytes([i]) * 1048576) for i in range(1,5)]"
```

### 7. Run the transfer script
```bash
./transfer.sh copy samples/source/documents :s3:testpress-source/quickstart
```

### 8. Verify integrity
```bash
rclone check samples/source/documents :s3:testpress-source/quickstart --config /dev/null
```

### 9. Synchronize safely
```bash
./transfer.sh sync samples/source/documents :s3:testpress-backup/quickstart
```
The default is dry-run. To perform actual synchronization:
```bash
./transfer.sh sync samples/source/documents :s3:testpress-backup/quickstart --execute
```
*Warning: Real sync can delete destination-only files.*

### 10. Stop MinIO
```bash
docker compose down
```
The named volume preserves data. Do not use `docker compose down -v` unless you intend to delete it.

## Detailed Documentation
* [commands.md](commands.md) - Commands and exercises.
* [results.md](results.md) - Experiment results.
* [DEVOPS_IMPLEMENTATION.md](DEVOPS_IMPLEMENTATION.md) - DevOps architecture & answers to demonstration questions.

## Phase 1 - Fundamentals
Understood local file storage, S3 object storage, and the purpose of Rclone.

## Phase 2 - Environment Setup
Installed and verified Git, Docker, Docker Compose, and Rclone. Initialized and pushed the GitHub repository.

## Phase 3 - Local File Operations (Completed)
* Listed nested files with `rclone ls`.
* Tested initial, repeated, new-file, and modified-file copies.
* Confirmed that copy preserves destination-only files.
* Moved files and verified source removal.
* Previewed synchronization with `--dry-run`.
* Confirmed that sync removes destination-only files.
* Verified file integrity using `rclone check`.
* Deleted temporary files using `rclone delete`.  
See [commands.md](commands.md) and [results.md](results.md) for commands and observations.

## Phase 4 - Local S3 Storage with MinIO
This project runs an S3-compatible object storage server locally using Docker Compose. No paid cloud account is required.

### Prerequisites
* Docker and Docker Compose
* Rclone

### Setup
Clone this repository and enter the project directory.  
Create your local environment file:
```bash
cp .env.example .env
```
Replace the example password in `.env` with a strong password. Never commit `.env`.

Start MinIO:
```bash
docker compose up -d
```
Verify the service:
```bash
docker compose ps
curl -i http://localhost:9000/minio/health/ready
```
A healthy MinIO server returns `HTTP/1.1 200 OK`.

### Local Endpoints
* S3 API: http://localhost:9000
* Web console: http://localhost:9001  
Use the credentials configured in `.env` to sign in to the console.

### Storage and Security
* MinIO data persists in the Docker-managed `minio-primary-data` volume.
* Both ports are bound to `127.0.0.1`, limiting access to the local machine.
* `.env` is excluded from Git; `.env.example` contains placeholder credentials only.
* The Docker image is pinned by release tag for version consistency.

## Phase 5 - S3 Operations and Config-Free Access (Completed)
* Connected Rclone to local MinIO using environment variables and the `:s3:` backend.
* Disabled persistent Rclone configuration using `--config /dev/null`.
* Created `testpress-source` and `testpress-backup` buckets.
* Uploaded objects totaling 106 MiB and verified their integrity.
* Downloaded the objects and verified the restored files.
* Copied objects between S3 buckets using server-side copying.
* Created and deleted a temporary S3 object without affecting the backup.
* Confirmed 0 differences and matching objects after deletion.  
See [commands.md](commands.md) and [results.md](results.md) for commands and observations.

## Phase 6 - Large Transfers and Reliability (Completed)
* Uploaded a 1 GiB file with bandwidth limits, concurrency settings, progress reporting, and retry configuration.
* Verified that repeating an unchanged upload transfers 0 B.
* Interrupted an upload at 30 MB (simulated network severance) and restarted it successfully.
* Verified recovered file integrity using matching MD5 checksums (`1ce845c7266a821cef2feb34cd78c59a`).
* Compared sequential and concurrent uploads under a shared bandwidth limit.
* Tested unlimited-bandwidth uploads and verified all transferred files.  
See [commands.md](commands.md) and [results.md](results.md) for commands and measurements.

## Phase 7 - Reusable Transfer Script and Sync Safety (Completed)
* Created an executable Bash script, `transfer.sh`, supporting copy and sync operations.
* Added argument validation, Rclone dependency checks, progress reporting, logging, and exit-code handling.
* Configured sync to use dry-run by default; `--execute` explicitly enables real synchronization.
* Confirmed that an invalid source returns exit code 3.
* Confirmed that missing S3 credentials return exit code 4.
* Demonstrated that dry-run preserves destination-only files and real sync removes them.
* Verified 0 differences and matching files after synchronization.
* Validated required S3 environment variables without blocking local-to-local transfers.
* Demonstrated config-free MinIO access using explicit S3 flags and `--config /dev/null`.
* Tested authentication failure handling returning exit code 1.  
See [commands.md](commands.md) and [results.md](results.md) for commands and observations.

## Security
Local sample data, credentials, environment files, and Rclone configuration files are excluded from Git using `.gitignore`. Real credentials must never be committed.

## Final Exercise Status
All mandatory Rclone exercise requirements were completed and verified.

### Mandatory Coverage
* Local listing, copy, move, sync, delete and integrity checks.
* Nested text, PDF and 100+ MiB sample files.
* Local MinIO S3-compatible storage using Docker Compose.
* Bucket creation, upload, download, object listing, bucket-to-bucket copy and object deletion.
* Config-free S3 using `:s3:`, environment variables, explicit CLI flags and `--config /dev/null`.
* Valid and invalid credential tests and endpoint switching.
* 1 GiB transfer, bandwidth limiting, concurrency, progress, retries and interrupted-transfer recovery.
* Safe synchronization using `--dry-run` before real deletion.
* Reusable `transfer.sh` with copy/sync, logging, validation and exit-code propagation.
* Fresh-clone and fresh-volume reproducibility tests.

### Bonus Work Completed
* Transfer between two separate MinIO S3 endpoints (9000 -> 9100).
* Compared same-endpoint server-side copying with cross-endpoint client-mediated transfer.
* Tested `--transfers`, `--checkers` and `--multi-thread-streams`.
* Investigated interrupted S3 multipart uploads and cleanup.
* Tested the `crypt` backend and confirmed encrypted/obfuscated underlying object names.
* Created a cron scheduling example (`cron-example.txt`).
* Invoked the reusable transfer workflow from Python using `subprocess` (`run_rclone.py`).

Detailed commands are in [commands.md](commands.md). Actual observations and timings are in [results.md](results.md). Architectural design and demonstration questions are answered in [DEVOPS_IMPLEMENTATION.md](DEVOPS_IMPLEMENTATION.md).