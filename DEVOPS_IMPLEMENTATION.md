# DevOps Implementation Guide: Rclone Storage Automation

This document details the architectural decisions, production integration patterns, and operational answers for running Rclone at scale within cloud-native architectures (e.g., Testpress and TPStreams).

---

## 1. Architectural Design & Storage Topology

```
+-----------------------------------------------------------------------------------+
|                              Application Tier                                      |
|  (Celery Worker / Django API / Cron Job / CLI Workflow)                           |
+-----------------------------------------------------------------------------------+
       |                                                    |
       | 1. In-Memory S3 Config                             | 2. Exec subprocess / Bash
       v                                                    v
+-----------------------------------------------------------------------------------+
|                         Rclone Engine (--config /dev/null)                        |
|   Features: Multi-thread streaming, Bandwidth throttle, Retries, Dry-run safety    |
+-----------------------------------------------------------------------------------+
       |                                                    |
       v (Local FS)                                         v (S3 API :9000 / :9100)
+-----------------------+                    +--------------------------------------+
| Local Volumes         |                    | MinIO S3 Object Storage              |
| /samples/source       |                    | Buckets: testpress-source, backup    |
+-----------------------+                    +--------------------------------------+
```

### Key Principles
1. **Config-Free Immutability:** No persistent `rclone.conf` on disk. Secrets exist only as process environment variables or memory-injected parameters.
2. **Safe Synchronization by Default:** All `sync` commands require explicit `--execute` to perform destructive deletions; default execution is strictly `--dry-run`.
3. **Deterministic Idempotency:** Transfers skip identical objects by comparing modification time and size (or MD5 checksums).

---

## 2. Answers to Demonstration Questions

### Question 1: What happens when `rclone copy` is executed twice with the same source and destination?
* **Observation:** Rclone inspects the size and modification timestamp (`mtime`) by default (within 1-second tolerance).
* **Behavior:** Because all destination attributes match the source, **0 bytes are re-transferred**. Rclone reports `Checks: N/N, Transferred: 0 / 0`. Disk I/O and network bandwidth are preserved.

### Question 2: What happens if a file exists at the destination but not at the source when `rclone sync` runs?
* **Observation:** `rclone sync` enforces strict 1:1 mirroring of destination to source.
* **Behavior:** Any destination file absent from the source is **permanently deleted**.
* **Safety Guard:** In our `transfer.sh` implementation, running `transfer.sh sync` runs `--dry-run` to log proposed deletions (`Skipped delete as --dry-run is set`). Only when `--execute` is supplied does real deletion take place.

### Question 3: How does rclone determine whether a file needs to be transferred?
1. **Size + ModTime (Default):** Checks file size and modification time. Fastest method because it avoids hashing file contents.
2. **Cryptographic Checksum (`--checksum`):** Compares MD5/SHA-256 hashes instead of timestamps. Required for object storage systems where modification timestamps might change upon upload.
3. **Size Only (`--size-only`):** Compares solely byte size.

### Question 4: Can rclone transfer data directly between two S3 providers without downloading it to the local machine?
* **Same Provider & Region:** Yes. Rclone initiates an S3 `CopyObject` API call (server-side copy). In our tests, copying 1.225 GiB completed in 7.1 seconds without traversing local host interfaces.
* **Different Providers (e.g., AWS S3 to MinIO or Wasabi):** Cloud object storage APIs do not allow third-party cross-account server-side copying. However, Rclone streams chunks in-memory directly from Provider A into Provider B without staging files on the local disk.

### Question 5: What happens when a network connection is interrupted halfway through a 1 GB upload?
* Files over 200 MiB use S3 Multipart Uploads (split into parts, e.g., 5 MiB to 64 MiB).
* If the connection fails, Rclone retries failed parts via `--low-level-retries` and `--retries`.
* If abruptly aborted, completed parts remain buffered in S3. Resuming the upload re-uploads the remaining parts and cleanly finalizes the multipart upload.
* Abandoned multipart parts can be pruned with:
  ```bash
  rclone backend cleanup :s3:bucket-name --config /dev/null
  ```

### Question 6: How would you securely execute rclone from a Celery worker without maintaining an `rclone.conf` file?
1. In the Celery worker task, fetch S3 credentials dynamically from AWS Secrets Manager or HashiCorp Vault.
2. Inject credentials as environment variables into `subprocess.Popen(..., env=env)`.
3. Pass `--config /dev/null` as a command-line argument.
4. Stream `process.stdout` and capture return codes.
*(See working implementation in `run_rclone.py`)*.

---

## 3. Production Deployment Scenarios

### Celery Background Task (Python)
```python
# Executed via Python subprocess invocation

def process_video_upload(video_id: str, local_path: str):
    s3_config = {
        "RCLONE_S3_PROVIDER": "Minio",
        "RCLONE_S3_ACCESS_KEY_ID": get_vault_secret("s3_user"),
        "RCLONE_S3_SECRET_ACCESS_KEY": get_vault_secret("s3_pass"),
        "RCLONE_S3_ENDPOINT": "http://minio:9000",
    }
    exit_code = run_rclone_transfer(
        command="copy",
        source=local_path,
        destination=f":s3:testpress-source/videos/{video_id}",
        s3_config=s3_config,
        bwlimit="50M",
        transfers=4
    )
    if exit_code != 0:
        raise RuntimeError(f"Video upload failed with exit code {exit_code}")
```

### Systemd Timer / Kubernetes CronJob
For scheduled incremental syncs:
* Set `flock` file locking to avoid race conditions.
* Pass secrets via Kubernetes Secret environment variables.
* Run with `--execute` for synchronized backups.