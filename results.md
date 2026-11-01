# Experimental Results & Observations

This document records the empirical findings, performance benchmarks, and behavior analysis from all transfer, synchronization, reliability, and security experiments.

---

## 1. Phase 2: Local File Operations

### 1.1 Initial vs. Repeated Transfers (Idempotency)
* **Initial Copy:**
  ```text
  Transferred: 6.000 MiB / 6.000 MiB, 100%, Elapsed time: 0.0s
  Transferred: 6 / 6 files
  ```
* **Repeated Copy:**
  ```text
  INFO : There was nothing to transfer
  Transferred: 0 B / 0 B, Checks: 6 / 6, 100%
  Elapsed time: 0.0s
  ```
* **Key Finding:** Rclone compares the file size and modification timestamp (`mtime`) by default. Unchanged files are skipped immediately without redundant disk writes.

### 1.2 Move Semantics & Source Cleanup
* **Command:** `rclone move samples/source/temp_move samples/dest_move -v`
* **Observation:** Rclone executes a server-side rename when both locations are on the same filesystem.
* **Verification:** `ls samples/source/temp_move/to_move.txt` returned `No such file or directory`. Source data was deleted only after destination receipt was verified.

### 1.3 Sync vs. Copy Behavior & Deletions
* Extra file added to destination: `samples/dest1/extra-dest-only.txt` (24 bytes).
* **Copy Behavior:** Preserved `extra-dest-only.txt`.
* **Sync (`--dry-run`):**
  ```text
  NOTICE: extra-dest-only.txt: Skipped delete as --dry-run is set (size 24)
  Deleted: 1 (files), 0 (dirs), 24 B (freed)
  ```
* **Sync (Real Execution):**
  ```text
  INFO : extra-dest-only.txt: Deleted
  Deleted: 1 (files), 24 B (freed)
  ```
* **Integrity Check:** `rclone check` reported `0 differences found, 6 matching files`.

---

## 2. Phase 3 & 4: S3 Object Storage & Config-Free Access

### 2.1 Bucket Operations & Object Listings
* Created buckets: `testpress-source` and `testpress-backup` using `rclone mkdir :s3:bucket-name`.
* Uploaded 6 documents (6 MiB) and 1 preview media file (100 MiB).
* Verified object hierarchy in MinIO using `rclone lsd` and `rclone ls`.

### 2.2 Server-Side Copying Between S3 Buckets
* **Command:** `rclone copy :s3:testpress-source :s3:testpress-backup -v`
* **Measurement:**
  ```text
  Transferred: 106.000 MiB / 106.000 MiB, 100%
  Server Side Copies: 7 @ 106.000 MiB
  Elapsed time: 0.6s
  ```
* **Analysis:** When copying between buckets on the same S3 provider endpoint, Rclone issues S3 `CopyObject` API calls. The data never transits through the client machine network interface, completing 106 MiB in **0.6 seconds**.

### 2.3 Configuration-Free Security & Auth Failure Tests
* **Environment Variables:** S3 operations executed successfully with `--config /dev/null` using `RCLONE_S3_*` variables.
* **CLI Flags:** Executed with explicit flags (`--s3-provider`, `--s3-endpoint`, `--s3-access-key-id`).
* **Authentication Failure Test:**
  ```text
  NOTICE: Failed to ls: operation error S3: ListObjectsV2: StatusCode: 403, api error InvalidAccessKeyId
  Exit Code: 1
  ```
  Verified that invalid credentials fail immediately with HTTP 403 Forbidden.

---

## 3. Phase 5: Large File Transfers & Reliability

### 3.1 1 GB Upload with Bandwidth Limiter
* **Test File:** `course-archive-1gb.bin` (1024.00 MiB).
* **Local MD5 Checksum:** `1ce845c7266a821cef2feb34cd78c59a`
* **Bandwidth Throttling:** `--bwlimit 50M`
* **Transfer Stats:**
  ```text
  INFO : Starting bandwidth limiter at 50Mi Byte/s
  INFO :   175.406 MiB / 1 GiB, 17%, 18.076 MiB/s, ETA 46s
  INFO :   575.000 MiB / 1 GiB, 56%, 35.081 MiB/s, ETA 12s
  INFO :   973.312 MiB / 1 GiB, 95%, 41.018 MiB/s, ETA 1s
  INFO : course-archive-1gb.bin: Multi-thread Copied (new)
  Transferred: 1 GiB / 1 GiB, 100%, 42.031 MiB/s, Elapsed: 24.3s
  ```
* **Repeated Upload:** Transferred `0 B / 0 B` in `0.0s`.

### 3.2 Interrupted Transfer & Resumption
1. Transfer started with `--bwlimit 10M` in background.
2. At ~30 MB (3 seconds), the transfer process was abruptly killed (`kill -9 $PID`).
3. Resumed transfer with `rclone copy ... --retries 5`.
4. Resumed transfer completed in `15.2s` at `64.000 MiB/s`.
5. **Cryptographic Verification:**
   ```bash
   rclone md5sum :s3:testpress-source/large/course-archive-1gb.bin
   # Result: 1ce845c7266a821cef2feb34cd78c59a  course-archive-1gb.bin
   ```
   Checksum matched local MD5 exactly. Zero corruption was introduced.

---

## 4. Phase 6: Synchronization Safety & Data Integrity

### 4.1 Divergent Dataset Scenario
* `sync_source`: `doc.txt` (v2, 29 bytes), `new_lesson.txt` (new, 22 bytes).
* `sync_dest`: `doc.txt` (v1, 35 bytes), `deprecated_module.txt` (orphaned, 55 bytes).

### 4.2 Pre-Sync Audit (`rclone check`)
```text
ERROR : deprecated_module.txt: file not in Local file system at samples/sync_source
ERROR : new_lesson.txt: file not in Local file system at samples/sync_dest
ERROR : doc.txt: sizes differ
NOTICE: 3 differences found, 3 errors while checking
```

### 4.3 Dry-Run Simulation vs. Real Execution
* **Dry-Run Output:**
  ```text
  NOTICE: new_lesson.txt: Skipped copy as --dry-run is set (size 22)
  NOTICE: doc.txt: Skipped copy as --dry-run is set (size 29)
  NOTICE: deprecated_module.txt: Skipped delete as --dry-run is set (size 55)
  Deleted: 1 (files), 55 B (freed)
  ```
  Verified `samples/sync_dest` remained unchanged after dry-run.
* **Real Sync:**
  `deprecated_module.txt` was removed, `doc.txt` updated to v2, and `new_lesson.txt` copied.
* **Post-Sync Check:** `0 differences found, 2 matching files`.

---

## 5. Phase 7: Automation Script (`transfer.sh`)

| Test Scenario | Command Executed | Expected Exit Code | Actual Exit Code | Result |
| :--- | :--- | :---: | :---: | :---: |
| Normal Copy to S3 | `./transfer.sh copy ./documents :s3:bucket/docs` | 0 | 0 | PASS |
| Integrity Check | `./transfer.sh check ./documents :s3:bucket/docs` | 0 | 0 | PASS |
| Sync Safety Guard | `./transfer.sh sync ./documents :s3:bucket/docs` | 0 (Dry-Run) | 0 | PASS |
| Real Sync Execution | `./transfer.sh sync ./documents :s3:bucket/docs --execute` | 0 (Executed) | 0 | PASS |
| Nonexistent Source | `./transfer.sh copy ./invalid_path :s3:bucket/docs` | 3 | 3 | PASS |
| Missing S3 Credentials | `env -u RCLONE_S3_ACCESS_KEY_ID ./transfer.sh ...` | 4 | 4 | PASS |

### Log Verification (`transfer.log`)
All operations generated timestamped structured logs:
```text
[2026-11-02 02:29:05] [INFO] Starting 'copy' operation from 'samples/source/documents' to ':s3:testpress-source/script-test'...
[2026-11-02 02:29:05] [SUCCESS] Operation 'copy' completed successfully in 1s.
[2026-11-02 02:29:06] [WARN] SYNC SAFETY: Running in DRY-RUN mode. No changes will be committed.
[2026-11-02 02:29:07] [ERROR] Source path './nonexistent_source_path' does not exist.
```

---

## 6. Bonus Challenges & Performance Benchmarks

### 6.1 Direct Cross-Endpoint Transfer (MinIO 9000 -> MinIO 9100)
* **Configuration:** Two distinct MinIO instances running on ports 9000 and 9100.
* **Command:**
  ```bash
  rclone copy \
    ":s3,endpoint='http://127.0.0.1:9000',access_key_id='admin',secret_access_key='admin123',provider='Minio':testpress-source/documents" \
    ":s3,endpoint='http://127.0.0.1:9100',access_key_id='admin',secret_access_key='admin123',provider='Minio':remote-backup/cross-endpoint-docs" \
    --config /dev/null -v
  ```
* **Result:** Transferred 6 MiB across separate endpoints in **0.1s**.
* **Verification:** `rclone check` across endpoints confirmed `0 differences found, 6 matching files`.
* **Server-Side vs Client-Mediated:** Because the endpoints were distinct, server-side copying was unavailable. Rclone streamed the data in memory between endpoints without intermediate disk storage.

### 6.2 Concurrency & Stream Tuning
* **Sequential vs. Concurrent Transfers (6 nested files):**
  * `--transfers 1 --checkers 1`: **1050 ms**
  * `--transfers 4 --checkers 8`: **528 ms** (1.98x speedup)
* **Multi-Thread Streaming (100 MB file):**
  * `--multi-thread-streams 1`: **2117 ms**
  * `--multi-thread-streams 4`: **2029 ms**

### 6.3 End-to-End Client Encryption (`crypt` backend)
* **Encryption Test:** Files uploaded through `:crypt,remote=':s3:testpress-source/vault':`
* **Raw S3 Inspection:**
  Object names and data were scrambled into ciphertext (e.g., `954rin3d88v1d4jvt5v2cnd9i4`).
* **Decryption Verification:** Files downloaded and decrypted cleanly; `rclone check` reported `0 differences found`.

### 6.4 Python Celery Worker Simulation
* `transfer_worker.py` invoked Rclone via `subprocess.Popen` with credentials injected dynamically into process memory.
* Return code: `0`. Output streamed in real-time. Zero disk config files generated.