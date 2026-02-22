#!/usr/bin/env bash
# oluto-update-expense.sh — Update fields on an existing transaction
# Usage: oluto-update-expense.sh TRANSACTION_ID [field=value ...]
# Examples:
#   oluto-update-expense.sh abc123 category="Software / Subscriptions"
#   oluto-update-expense.sh abc123 vendor_name="Moonshot AI" transaction_date=2026-02-15
#   oluto-update-expense.sh abc123 status=posted
#
# Supported fields: vendor_name, amount, currency, description,
#   transaction_date, category, classification, status, gst_amount, pst_amount
#
# NOTE: This runs on Alpine/BusyBox — do NOT use grep -P (Perl regex).
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API="$SCRIPT_DIR/oluto-api.sh"
CONFIG_FILE="$HOME/.oluto-config.json"

if [ $# -lt 2 ]; then
    echo "Usage: oluto-update-expense.sh TRANSACTION_ID field=value [field=value ...]" >&2
    exit 1
fi

TXN_ID="$1"
shift

BID="${OLUTO_BUSINESS_ID:-$(jq -r '.default_business_id' "$CONFIG_FILE")}"

# Build JSON body from key=value pairs
BODY="{}"
for arg in "$@"; do
    KEY="${arg%%=*}"
    VALUE="${arg#*=}"
    BODY=$(echo "$BODY" | jq --arg k "$KEY" --arg v "$VALUE" '. + {($k): $v}')
done

# Validate we have at least one field
FIELD_COUNT=$(echo "$BODY" | jq 'keys | length')
if [ "$FIELD_COUNT" -eq 0 ]; then
    echo "Error: No fields to update. Use field=value format." >&2
    exit 1
fi

RESULT=$("$API" PATCH "/api/v1/businesses/$BID/transactions/$TXN_ID" "$BODY" 2>&1 || true)

# Check for errors
if echo "$RESULT" | grep -q '^ERROR'; then
    echo "Could not update transaction $TXN_ID: $RESULT"
    exit 1
fi

# Extract updated fields for confirmation
UPDATED_VENDOR=$(echo "$RESULT" | jq -r '.vendor_name // empty' 2>/dev/null || true)
UPDATED_AMOUNT=$(echo "$RESULT" | jq -r '.amount // empty' 2>/dev/null || true)
UPDATED_DATE=$(echo "$RESULT" | jq -r '.transaction_date // empty' 2>/dev/null || true)
UPDATED_CATEGORY=$(echo "$RESULT" | jq -r '.category // empty' 2>/dev/null || true)
UPDATED_STATUS=$(echo "$RESULT" | jq -r '.status // empty' 2>/dev/null || true)

echo "Transaction $TXN_ID updated:"
[ -n "$UPDATED_VENDOR" ] && echo "  Vendor: $UPDATED_VENDOR"
[ -n "$UPDATED_AMOUNT" ] && echo "  Amount: \$$UPDATED_AMOUNT"
[ -n "$UPDATED_DATE" ] && echo "  Date: $UPDATED_DATE"
[ -n "$UPDATED_CATEGORY" ] && echo "  Category: $UPDATED_CATEGORY"
[ -n "$UPDATED_STATUS" ] && echo "  Status: $UPDATED_STATUS"
