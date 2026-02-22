#!/usr/bin/env bash
# oluto-import-statement.sh — Parse a bank statement (CSV or PDF) via LedgerForge import API.
# Usage: oluto-import-statement.sh <file_path>
# CSV files return parsed transactions immediately.
# PDF files trigger async processing — this script polls until complete.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${HOME}/.oluto-config.json"

if [ $# -lt 1 ]; then
    echo "Usage: oluto-import-statement.sh <file_path>" >&2
    exit 1
fi

FILE_PATH="$1"

if [ ! -f "$FILE_PATH" ]; then
    echo "ERROR: File not found: $FILE_PATH" >&2
    exit 1
fi

# Get auth token
TOKEN=$("${SCRIPT_DIR}/oluto-auth.sh")
BASE_URL=$(jq -r '.base_url' "$CONFIG_FILE")

# Determine business_id
BID="${OLUTO_BUSINESS_ID:-}"
if [ -z "$BID" ]; then
    BID=$(jq -r '.default_business_id // empty' "$CONFIG_FILE" 2>/dev/null || true)
fi
if [ -z "$BID" ]; then
    echo "ERROR: No business_id available. Set OLUTO_BUSINESS_ID or default_business_id in config." >&2
    exit 1
fi

# Detect file type
FILENAME=$(basename "$FILE_PATH")
EXT="${FILENAME##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

if [ "$EXT_LOWER" != "csv" ] && [ "$EXT_LOWER" != "pdf" ]; then
    echo "ERROR: Unsupported file type '.$EXT_LOWER'. Only CSV and PDF are supported." >&2
    exit 1
fi

# Upload file to import/parse endpoint (multipart)
PARSE_URL="${BASE_URL}/api/v1/businesses/${BID}/transactions/import/parse"

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$PARSE_URL" \
    -H "Authorization: Bearer ${TOKEN}" \
    -F "file=@${FILE_PATH}" 2>&1)

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "${HTTP_CODE:0:1}" != "2" ]; then
    echo "ERROR (HTTP ${HTTP_CODE}): Failed to parse statement."
    if echo "$BODY" | jq . >/dev/null 2>&1; then
        echo "$BODY" | jq -r '.error // .message // .detail // "Unknown error"'
    else
        echo "$BODY"
    fi
    exit 1
fi

# Check if response has async job (PDF) or immediate results (CSV)
SUCCESS=$(echo "$BODY" | jq -r '.success // false')
if [ "$SUCCESS" != "true" ]; then
    MSG=$(echo "$BODY" | jq -r '.error // "Parse failed"')
    echo "ERROR: $MSG" >&2
    exit 1
fi

DATA=$(echo "$BODY" | jq '.data')

# Check if this is an async job response (has job_id)
JOB_ID=$(echo "$DATA" | jq -r '.job_id // empty' 2>/dev/null || true)

if [ -n "$JOB_ID" ]; then
    # PDF async processing — poll until complete
    echo "Processing PDF statement (job: $JOB_ID)..."
    MAX_POLLS=60  # 3 minutes max
    POLL_INTERVAL=3

    for i in $(seq 1 $MAX_POLLS); do
        sleep $POLL_INTERVAL

        JOB_URL="${BASE_URL}/api/v1/businesses/${BID}/transactions/jobs/${JOB_ID}"
        JOB_RESP=$(curl -s -X GET "$JOB_URL" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json")

        JOB_SUCCESS=$(echo "$JOB_RESP" | jq -r '.success // false')
        if [ "$JOB_SUCCESS" != "true" ]; then
            continue
        fi

        JOB_STATUS=$(echo "$JOB_RESP" | jq -r '.data.status // "pending"')

        if [ "$JOB_STATUS" = "completed" ]; then
            echo "$JOB_RESP" | jq '.data'
            exit 0
        elif [ "$JOB_STATUS" = "failed" ]; then
            ERROR=$(echo "$JOB_RESP" | jq -r '.data.error // "Processing failed"')
            echo "ERROR: PDF processing failed: $ERROR" >&2
            exit 1
        fi
        # Still processing — continue polling
    done

    echo "ERROR: PDF processing timed out after $((MAX_POLLS * POLL_INTERVAL)) seconds." >&2
    exit 1
else
    # CSV immediate response — output parsed transactions
    echo "$DATA"
fi
