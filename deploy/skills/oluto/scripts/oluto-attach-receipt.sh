#!/usr/bin/env bash
# oluto-attach-receipt.sh — Attach a receipt file to a transaction (persists to Azure Blob)
# Usage: oluto-attach-receipt.sh TRANSACTION_ID FILE_PATH
# After successful upload, the local file is deleted to free disk space.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTH="$SCRIPT_DIR/oluto-auth.sh"
CONFIG_FILE="$HOME/.oluto-config.json"

if [ $# -lt 2 ]; then
    echo "Usage: oluto-attach-receipt.sh TRANSACTION_ID FILE_PATH" >&2
    exit 1
fi

TXN_ID="$1"
FILE_PATH="$2"

if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File not found at $FILE_PATH" >&2
    exit 1
fi

BASE_URL=$(jq -r '.base_url' "$CONFIG_FILE")
BID="${OLUTO_BUSINESS_ID:-$(jq -r '.default_business_id' "$CONFIG_FILE")}"
TOKEN=$("$AUTH")

# Upload receipt to LedgerForge → Azure Blob Storage
RESP=$(curl -sf -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    -F "file=@$FILE_PATH" \
    "${BASE_URL}/api/v1/businesses/${BID}/transactions/${TXN_ID}/receipts" 2>/dev/null || echo -e "\n000")

HTTP_CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

if [ "${HTTP_CODE:0:1}" = "2" ]; then
    # Upload succeeded — clean up local file
    rm -f "$FILE_PATH"
    RECEIPT_ID=$(echo "$BODY" | jq -r '.data.id // .id // "unknown"' 2>/dev/null || echo "unknown")
    echo "Receipt attached to transaction $TXN_ID (receipt ID: $RECEIPT_ID). Local file cleaned up."
else
    echo "Warning: Could not attach receipt to transaction (HTTP $HTTP_CODE). Local file kept at $FILE_PATH" >&2
    exit 1
fi
