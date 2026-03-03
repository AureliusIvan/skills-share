#!/usr/bin/env bash
# s3-migrate.sh - Migrate data between S3-compatible providers using rclone
#
# Usage: bash s3-migrate.sh <source_remote>:<bucket> <dest_remote>:<bucket> [options]
#
# Options:
#   --transfers N    Number of parallel transfers (default: 16)
#   --dry-run        Preview without transferring
#   --delete         Delete files in destination not in source (use with caution)
#
# Prerequisites:
#   - rclone installed and configured with both remotes
#   - Run 'rclone config' to set up remotes before using this script
#
# Examples:
#   bash s3-migrate.sh aws:my-bucket r2:my-bucket
#   bash s3-migrate.sh b2:old-bucket wasabi:new-bucket --transfers 32
#   bash s3-migrate.sh minio:data r2:data --dry-run

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Defaults
TRANSFERS=16
DRY_RUN=""
DELETE=""

# Parse arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <source_remote>:<bucket> <dest_remote>:<bucket> [options]"
    echo ""
    echo "Options:"
    echo "  --transfers N    Parallel transfers (default: 16)"
    echo "  --dry-run        Preview without transferring"
    echo "  --delete         Delete destination files not in source"
    exit 1
fi

SOURCE="$1"
DEST="$2"
shift 2

while [[ $# -gt 0 ]]; do
    case $1 in
        --transfers)
            TRANSFERS="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="--dry-run"
            shift
            ;;
        --delete)
            DELETE="--delete-after"
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Check rclone is installed
if ! command -v rclone &> /dev/null; then
    echo -e "${RED}Error: rclone is not installed.${NC}"
    echo "Install it from https://rclone.org/install/"
    exit 1
fi

# Verify remotes exist
SOURCE_REMOTE="${SOURCE%%:*}"
DEST_REMOTE="${DEST%%:*}"

if ! rclone listremotes | grep -q "^${SOURCE_REMOTE}:$"; then
    echo -e "${RED}Error: Source remote '${SOURCE_REMOTE}' not configured in rclone.${NC}"
    echo "Run 'rclone config' to set it up."
    exit 1
fi

if ! rclone listremotes | grep -q "^${DEST_REMOTE}:$"; then
    echo -e "${RED}Error: Destination remote '${DEST_REMOTE}' not configured in rclone.${NC}"
    echo "Run 'rclone config' to set it up."
    exit 1
fi

TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOG_FILE="/tmp/s3-migrate-${TIMESTAMP}.log"

echo -e "${GREEN}=== S3 Migration ===${NC}"
echo "Source:      $SOURCE"
echo "Destination: $DEST"
echo "Transfers:   $TRANSFERS"
echo "Log file:    $LOG_FILE"
[ -n "$DRY_RUN" ] && echo -e "${YELLOW}Mode: DRY RUN (no actual transfers)${NC}"
[ -n "$DELETE" ] && echo -e "${YELLOW}Delete mode: ON (extra files in destination will be removed)${NC}"
echo ""

# Get source size
echo -e "${GREEN}Checking source size...${NC}"
SOURCE_SIZE=$(rclone size "$SOURCE" --json 2>/dev/null || echo '{"count":0,"bytes":0}')
SOURCE_COUNT=$(echo "$SOURCE_SIZE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "unknown")
SOURCE_BYTES=$(echo "$SOURCE_SIZE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('bytes',0))" 2>/dev/null || echo "unknown")

echo "Source: $SOURCE_COUNT objects, $(echo "$SOURCE_BYTES" | numfmt --to=iec 2>/dev/null || echo "${SOURCE_BYTES} bytes")"
echo ""

# Run migration
echo -e "${GREEN}Starting migration...${NC}"
START_TIME=$(date +%s)

rclone copy "$SOURCE" "$DEST" \
    --transfers "$TRANSFERS" \
    --checkers 32 \
    --fast-list \
    --progress \
    --log-file "$LOG_FILE" \
    --log-level INFO \
    --retries 5 \
    --retries-sleep 10s \
    $DRY_RUN \
    $DELETE

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${GREEN}Migration completed in ${DURATION}s${NC}"

# Verify
if [ -z "$DRY_RUN" ]; then
    echo ""
    echo -e "${GREEN}Verifying...${NC}"

    DEST_SIZE=$(rclone size "$DEST" --json 2>/dev/null || echo '{"count":0,"bytes":0}')
    DEST_COUNT=$(echo "$DEST_SIZE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "unknown")
    DEST_BYTES=$(echo "$DEST_SIZE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('bytes',0))" 2>/dev/null || echo "unknown")

    echo "Source:      $SOURCE_COUNT objects"
    echo "Destination: $DEST_COUNT objects"

    if [ "$SOURCE_COUNT" = "$DEST_COUNT" ] 2>/dev/null; then
        echo -e "${GREEN}Object count matches.${NC}"
    else
        echo -e "${YELLOW}WARNING: Object count mismatch. Check the log file: $LOG_FILE${NC}"
    fi
fi

echo ""
echo "Log file: $LOG_FILE"
