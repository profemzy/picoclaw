#!/usr/bin/env bash
# oluto-list-customers.sh — List customers, optionally filtered by name
# Usage: oluto-list-customers.sh [SEARCH_TERM]
# Example: oluto-list-customers.sh "Acme"
#
# NOTE: This runs on Alpine/BusyBox — do NOT use grep -P (Perl regex).
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API="$SCRIPT_DIR/oluto-api.sh"
CONFIG_FILE="$HOME/.oluto-config.json"

SEARCH="${1:-}"

BID="${OLUTO_BUSINESS_ID:-$(jq -r '.default_business_id' "$CONFIG_FILE")}"

RESULT=$("$API" GET "/api/v1/businesses/$BID/contacts/customers" 2>&1 || true)

if echo "$RESULT" | grep -q '^ERROR'; then
    echo "Could not list customers: $RESULT" >&2
    exit 1
fi

# If search term provided, filter by name (case-insensitive)
if [ -n "$SEARCH" ]; then
    FILTERED=$(echo "$RESULT" | jq --arg s "$SEARCH" '
        if type == "array" then
            map(select(.name | ascii_downcase | contains($s | ascii_downcase)))
        else [] end
    ')
else
    FILTERED="$RESULT"
fi

COUNT=$(echo "$FILTERED" | jq 'if type == "array" then length else 0 end')

if [ "$COUNT" -eq 0 ]; then
    if [ -n "$SEARCH" ]; then
        echo "No customers found matching \"$SEARCH\"."
    else
        echo "No customers found. You can create one first."
    fi
    exit 0
fi

# Format output: ID | Name | Email
echo "$FILTERED" | jq -r '
    if type == "array" then
        .[] | "\(.id) | \(.name) | \(.email // "no email")"
    else empty end
'
echo ""
echo "Found $COUNT customer(s)."
