#!/usr/bin/env python3
"""
Celery / Background Worker Integration Example for Rclone
---------------------------------------------------------
Demonstrates how a Python backend (e.g., Celery worker in Testpress/TPStreams)
can securely execute Rclone file transfers without creating an rclone.conf file on disk.

Security & Architecture Highlights:
1. Credentials passed dynamically via process environment (inherited or explicit dict).
2. Uses `--config /dev/null` to guarantee zero persistent configuration on disk.
3. Streams stdout/stderr and monitors process return codes.
"""

import os
import subprocess
import sys
import logging
from typing import Dict, Optional, List

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger("RcloneWorker")

def run_rclone_transfer(
    command: str,
    source: str,
    destination: str,
    s3_config: Optional[Dict[str, str]] = None,
    bwlimit: Optional[str] = None,
    transfers: int = 4,
    checkers: int = 8,
    retries: int = 3,
    extra_flags: Optional[List[str]] = None
) -> int:
    """
    Executes an Rclone command in a secure, configuration-free subprocess.
    """
    cmd = [
        "rclone",
        command,
        source,
        destination,
        "--config", "/dev/null",
        "--transfers", str(transfers),
        "--checkers", str(checkers),
        "--retries", str(retries),
        "--stats", "1s",
        "--stats-one-line"
    ]

    if bwlimit:
        cmd.extend(["--bwlimit", bwlimit])

    if extra_flags:
        cmd.extend(extra_flags)

    # Prepare isolated environment with S3 credentials
    env = os.environ.copy()
    if s3_config:
        env.update(s3_config)

    logger.info("Executing Rclone command: %s", " ".join(cmd))
    logger.info("Transferring from '%s' to '%s'", source, destination)

    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env
        )

        for line in process.stdout:
            print(line, end="")

        process.wait()
        exit_code = process.returncode

        if exit_code == 0:
            logger.info("Transfer completed successfully (exit code 0).")
        else:
            logger.error("Transfer failed with exit code %d.", exit_code)

        return exit_code

    except FileNotFoundError:
        logger.error("Rclone executable not found. Ensure rclone is installed in PATH.")
        return 2
    except Exception as e:
        logger.error("Unexpected error during transfer execution: %s", str(e))
        return 1

if __name__ == "__main__":
    # Example invocation: Celery task simulation
    src = sys.argv[1] if len(sys.argv) > 1 else "./samples/source/documents"
    dst = sys.argv[2] if len(sys.argv) > 2 else ":s3:testpress-source/python-test"

    # In production, these come from AWS Secrets Manager or Vault
    minio_credentials = {
        "RCLONE_S3_PROVIDER": "Minio",
        "RCLONE_S3_ACCESS_KEY_ID": os.getenv("MINIO_ROOT_USER", "admin"),
        "RCLONE_S3_SECRET_ACCESS_KEY": os.getenv("MINIO_ROOT_PASSWORD", "admin123"),
        "RCLONE_S3_ENDPOINT": os.getenv("MINIO_ENDPOINT", "http://127.0.0.1:9000"),
        "RCLONE_S3_REGION": "us-east-1"
    }

    exit_code = run_rclone_transfer(
        command="copy",
        source=src,
        destination=dst,
        s3_config=minio_credentials,
        bwlimit="50M",
        transfers=4
    )
    sys.exit(exit_code)
