#!/usr/bin/env bash
# ==============================================================================
# Script: cron_backup.sh
# Purpose: Cron/systemd scheduled synchronization with flock concurrency control
# ==============================================================================

set -eo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="/tmp/rclone_backup.lock"
LOG_FILE="${WORKSPACE_DIR}/cron_backup.log"

# Load environment variables
if [[ -f "${WORKSPACE_DIR}/.env" ]]; then
    set -a
    source "${WORKSPACE_DIR}/.env"
    set +a
fi

# Prevent concurrent overlapping cron runs with flock
exec 200>"$LOCK_FILE"
flock -n 200 || {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] Previous backup still running. Exiting." >> "$LOG_FILE"
    exit 0
}

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Triggering scheduled backup via transfer.sh..." >> "$LOG_FILE"

# Execute real synchronization using transfer.sh
"${WORKSPACE_DIR}/transfer.sh" sync \
  "${WORKSPACE_DIR}/samples/source/documents" \
  ":s3:testpress-backup/scheduled-sync" \
  --execute \
  --transfers 4 \
  --retries 3 \
  --log-file "$LOG_FILE"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] Scheduled backup completed." >> "$LOG_FILE"