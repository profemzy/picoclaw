#!/usr/bin/env bash
# oluto-confirm-import.sh — Confirm parsed transactions from a bank statement import.
# Usage: oluto-confirm-import.sh '<json_payload>'
# The JSON payload should match the format from oluto-import-statement.sh output.
# This creates draft transactions, then optionally posts them.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${HOME}/.oluto-config.json"

if [ $# -lt 1 ]; then
    echo "Usage: oluto-confirm-import.sh '<json_payload>'" >&2
    exit 1
fi

JSON_PAYLOAD="$1"

# Get auth token
TOKEN=$("${SCRIPT_DIR}/oluto-auth.sh")
BASE_URL=$(jq -r '.base_url' "$CONFIG_FILE")

# Determine business_id
BID="${OLUTO_BUSINESS_ID:-}"
if [ -z "$BID" ]; then
    BID=$(jq -r '.default_business_id // empty' "$CONFIG_FILE" 2>/dev/null || true)
fi
if [ -z "$BID" ]; then
    echo "ERROR: No business_id available." >&2
    exit 1
fi

# Step 1: Confirm import — create draft transactions
CONFIRM_URL="${BASE_URL}/api/v1/businesses/${BID}/transactions/import/confirm"

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$CONFIRM_URL" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "${HTTP_CODE:0:1}" != "2" ]; then
    echo "ERROR (HTTP ${HTTP_CODE}): Failed to confirm import."
    if echo "$BODY" | jq . >/dev/null 2>&1; then
        echo "$BODY" | jq -r '.error // .message // .detail // "Unknown error"'
    else
        echo "$BODY"
    fi
    exit 1
fi

SUCCESS=$(echo "$BODY" | jq -r '.success // false')
if [ "$SUCCESS" != "true" ]; then
    MSG=$(echo "$BODY" | jq -r '.error // "Confirm failed"')
    echo "ERROR: $MSG" >&2
    exit 1
fi

DATA=$(echo "$BODY" | jq '.data')

# Extract batch_id if present for bulk posting
BATCH_ID=$(echo "$DATA" | jq -r '.batch_id // empty' 2>/dev/null || true)
COUNT=$(echo "$DATA" | jq -r '.count // .transactions_count // 0' 2>/dev/null || echo "0")

echo "Imported $COUNT transactions as drafts."

# Step 2: Post the batch if we have a batch_id
if [ -n "$BATCH_ID" ]; then
    BULK_URL="${BASE_URL}/api/v1/businesses/${BID}/transactions/bulk-status"
    POST_BODY="{\"batch_id\": \"${BATCH_ID}\", \"status\": \"posted\"}"

    POST_RESP=$(curl -s -w "\n%{http_code}" -X PATCH "$BULK_URL" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$POST_BODY")

    POST_CODE=$(echo "$POST_RESP" | tail -1)
    POST_BODY_RESP=$(echo "$POST_RESP" | sed '$d')

    if [ "${POST_CODE:0:1}" = "2" ]; then
        echo "All $COUNT transactions posted successfully."
    else
        echo "Transactions imported as drafts but posting failed. They can be posted from the Dashboard."
    fi
fi

echo "$DATA"
