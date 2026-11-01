#!/usr/bin/env bash
# ==============================================================================
# Script: transfer.sh
# Purpose: Production-grade file transfer & synchronization automation using Rclone
# Features:
#   - Config-free execution (--config /dev/null)
#   - Safe synchronization (dry-run default; requires --execute)
#   - Real-time progress reporting and structured logging
#   - Strict input validation and exit code propagation
# ==============================================================================

set -o pipefail

LOG_FILE="${LOG_FILE:-transfer.log}"
BWLIMIT=""
TRANSFERS=4
CHECKERS=8
RETRIES=3
LOW_LEVEL_RETRIES=10
USE_CHECKSUM=false
VERBOSE=false
EXECUTE_SYNC=false

COLOR_RESET="\033[0m"
COLOR_RED="\033[1;31m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_CYAN="\033[1;36m"

log() {
    local level="$1"
    shift
    local timestamp
    timestamp="$(date "+%Y-%m-%d %H:%M:%S")"
    local message="$*"
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    case "$level" in
        INFO)    echo -e "${COLOR_CYAN}[INFO]${COLOR_RESET} $message" ;;
        SUCCESS) echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $message" ;;
        WARN)    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $message" ;;
        ERROR)   echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $message" >&2 ;;
        *)       echo "[$level] $message" ;;
    esac
}

show_help() {
    echo "Usage: ./transfer.sh <command> <source> <destination> [options]"
    echo ""
    echo "Commands:"
    echo "  copy                  Copy files from source to destination (preserves destination-only files)"
    echo "  sync                  Synchronize destination to match source (DRY-RUN by default)"
    echo "  check                 Verify data integrity between source and destination (read-only)"
    echo ""
    echo "Arguments:"
    echo "  <source>              Source local directory or remote (e.g., ./data or :s3:bucket-name)"
    echo "  <destination>         Destination local directory or remote (e.g., ./backup or :s3:backup-bucket)"
    echo ""
    echo "Options:"
    echo "  --execute             Perform real synchronization (required for sync to make actual changes)"
    echo "  --bwlimit <rate>      Bandwidth limit (e.g., 10M, 50M, 1G)"
    echo "  --transfers <N>       Number of concurrent file transfers (default: 4)"
    echo "  --checkers <N>        Number of concurrent checksum checkers (default: 8)"
    echo "  --retries <N>         Number of retry attempts on failure (default: 3)"
    echo "  --low-level-retries <N> Number of low-level HTTP retries (default: 10)"
    echo "  --checksum            Compare cryptographic checksums instead of modtime/size"
    echo "  --log-file <path>     Path to output log file (default: transfer.log)"
    echo "  -v, --verbose         Enable verbose rclone logging"
    echo "  -h, --help            Display this help message"
    echo ""
    echo "Exit Codes:"
    echo "  0 - Transfer completed successfully"
    echo "  1 - Invalid syntax or missing required arguments"
    echo "  2 - Rclone executable not found"
    echo "  3 - Source path invalid or unreachable"
    echo "  4 - S3 credentials/environment missing for :s3: remote"
    echo "  5 - Rclone transfer or verification operation failed"
}

check_dependencies() {
    if ! command -v rclone &> /dev/null; then
        log ERROR "rclone is not installed or not in PATH."
        exit 2
    fi
}

load_environment() {
    if [[ -f .env ]]; then
        set -a
        source .env
        set +a
    fi
}

validate_s3_env() {
    local target="$1"
    if [[ "$target" == :s3:* ]]; then
        if [[ -z "${RCLONE_S3_ACCESS_KEY_ID:-}" ]] || [[ -z "${RCLONE_S3_SECRET_ACCESS_KEY:-}" ]] || [[ -z "${RCLONE_S3_ENDPOINT:-}" ]]; then
            log ERROR "Target '$target' specifies an S3 backend (:s3:), but required environment variables are unset."
            log ERROR "Please set RCLONE_S3_ACCESS_KEY_ID, RCLONE_S3_SECRET_ACCESS_KEY, and RCLONE_S3_ENDPOINT (or provide a .env file)."
            exit 4
        fi
    fi
}

if [[ $# -lt 3 ]]; then
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        show_help
        exit 0
    fi
    log ERROR "Insufficient arguments provided."
    show_help
    exit 1
fi

COMMAND="$1"
SOURCE="$2"
DESTINATION="$3"
shift 3

while [[ $# -gt 0 ]]; do
    case "$1" in
        --execute)           EXECUTE_SYNC=true; shift ;;
        --bwlimit)           BWLIMIT="$2"; shift 2 ;;
        --transfers)         TRANSFERS="$2"; shift 2 ;;
        --checkers)          CHECKERS="$2"; shift 2 ;;
        --retries)           RETRIES="$2"; shift 2 ;;
        --low-level-retries) LOW_LEVEL_RETRIES="$2"; shift 2 ;;
        --checksum)          USE_CHECKSUM=true; shift ;;
        --log-file)          LOG_FILE="$2"; shift 2 ;;
        -v|--verbose)        VERBOSE=true; shift ;;
        -h|--help)           show_help; exit 0 ;;
        *)                   log ERROR "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

case "$COMMAND" in
    copy|sync|check) ;;
    *) log ERROR "Unsupported command '$COMMAND'. Must be 'copy', 'sync', or 'check'."; exit 1 ;;
esac

check_dependencies
load_environment
validate_s3_env "$SOURCE"
validate_s3_env "$DESTINATION"

if [[ "$SOURCE" != :s3:* ]] && [[ ! -e "$SOURCE" ]]; then
    log ERROR "Source path '$SOURCE' does not exist."
    exit 3
fi

RCLONE_ARGS=(
    "--config" "/dev/null"
    "--stats" "1s"
    "--stats-one-line"
    "--transfers" "$TRANSFERS"
    "--checkers" "$CHECKERS"
    "--retries" "$RETRIES"
    "--low-level-retries" "$LOW_LEVEL_RETRIES"
)

if [[ -n "$BWLIMIT" ]]; then
    RCLONE_ARGS+=("--bwlimit" "$BWLIMIT")
fi
if [[ "$USE_CHECKSUM" == true ]]; then
    RCLONE_ARGS+=("--checksum")
fi
if [[ "$VERBOSE" == true ]]; then
    RCLONE_ARGS+=("-vv")
fi

IS_DRY_RUN=false
if [[ "$COMMAND" == "sync" ]]; then
    if [[ "$EXECUTE_SYNC" != true ]]; then
        IS_DRY_RUN=true
        RCLONE_ARGS+=("--dry-run")
        log WARN "SYNC SAFETY: Running in DRY-RUN mode. No changes will be committed."
        log WARN "To perform actual deletion and synchronization, pass '--execute'."
    else
        log WARN "SYNC EXECUTE: Real synchronization enabled. Destination-only files will be DELETED."
    fi
fi

START_TIME=$(date +%s)
log INFO "Starting '$COMMAND' operation from '$SOURCE' to '$DESTINATION'..."
log INFO "Parameters: Config-Free (--config /dev/null), Transfers=$TRANSFERS, Checkers=$CHECKERS, Retries=$RETRIES"
if [[ -n "$BWLIMIT" ]]; then
    log INFO "Bandwidth Throttling: $BWLIMIT"
fi

rclone "$COMMAND" "$SOURCE" "$DESTINATION" "${RCLONE_ARGS[@]}" --progress 2>&1 | tee -a "$LOG_FILE"
RCLONE_STATUS=${PIPESTATUS[0]}

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if [[ $RCLONE_STATUS -eq 0 ]]; then
    if [[ "$IS_DRY_RUN" == true ]]; then
        log SUCCESS "Dry-run simulation completed successfully in ${DURATION}s. Inspect $LOG_FILE to review planned actions."
    else
        log SUCCESS "Operation '$COMMAND' completed successfully in ${DURATION}s."
    fi
    exit 0
else
    log ERROR "Operation '$COMMAND' failed with exit code $RCLONE_STATUS after ${DURATION}s."
    exit 5
fi