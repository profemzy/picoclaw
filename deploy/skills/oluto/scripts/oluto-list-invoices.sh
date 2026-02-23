#!/usr/bin/env bash
# oluto-list-invoices.sh — List invoices, optionally filtered by status or customer
# Usage: oluto-list-invoices.sh [STATUS] [CUSTOMER_ID]
# Example: oluto-list-invoices.sh sent
# Example: oluto-list-invoices.sh "" "customer-uuid"
#
# NOTE: This runs on Alpine/BusyBox — do NOT use grep -P (Perl regex).
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API="$SCRIPT_DIR/oluto-api.sh"
CONFIG_FILE="$HOME/.oluto-config.json"

STATUS="${1:-}"
CUSTOMER_ID="${2:-}"

BID="${OLUTO_BUSINESS_ID:-$(jq -r '.default_business_id' "$CONFIG_FILE")}"

# Build query string
QUERY=""
[ -n "$STATUS" ] && QUERY="status=$STATUS"
if [ -n "$CUSTOMER_ID" ]; then
    [ -n "$QUERY" ] && QUERY="$QUERY&"
    QUERY="${QUERY}customer_id=$CUSTOMER_ID"
fi

PATH_STR="/api/v1/businesses/$BID/invoices"
[ -n "$QUERY" ] && PATH_STR="$PATH_STR?$QUERY"

RESULT=$("$API" GET "$PATH_STR" 2>&1 || true)

if echo "$RESULT" | grep -q '^ERROR'; then
    echo "Could not list invoices: $RESULT" >&2
    exit 1
fi

COUNT=$(echo "$RESULT" | jq 'if type == "array" then length else 0 end')

if [ "$COUNT" -eq 0 ]; then
    echo "No invoices found."
    exit 0
fi

# Format output: ID | Number | Total | Balance | Status | Due Date
echo "$RESULT" | jq -r '
    if type == "array" then
        .[] | "\(.id) | \(.invoice_number) | \(.total_amount) | \(.balance) | \(.status) | \(.due_date)"
    else empty end
'
echo ""
echo "Found $COUNT invoice(s)."
