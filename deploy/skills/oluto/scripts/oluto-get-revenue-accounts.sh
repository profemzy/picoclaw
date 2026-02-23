#!/usr/bin/env bash
# oluto-get-revenue-accounts.sh — List revenue accounts from the chart of accounts
# Usage: oluto-get-revenue-accounts.sh
#
# NOTE: This runs on Alpine/BusyBox — do NOT use grep -P (Perl regex).
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API="$SCRIPT_DIR/oluto-api.sh"
CONFIG_FILE="$HOME/.oluto-config.json"

BID="${OLUTO_BUSINESS_ID:-$(jq -r '.default_business_id' "$CONFIG_FILE")}"

RESULT=$("$API" GET "/api/v1/businesses/$BID/accounts?account_type=Revenue" 2>&1 || true)

if echo "$RESULT" | grep -q '^ERROR'; then
    echo "Could not list revenue accounts: $RESULT" >&2
    exit 1
fi

COUNT=$(echo "$RESULT" | jq 'if type == "array" then length else 0 end')

if [ "$COUNT" -eq 0 ]; then
    echo "No revenue accounts found. A default revenue account may need to be created."
    exit 0
fi

echo "$RESULT" | jq -r '
    if type == "array" then
        .[] | "\(.id) | \(.code // "—") | \(.name)"
    else empty end
'
echo ""
echo "Found $COUNT revenue account(s)."
