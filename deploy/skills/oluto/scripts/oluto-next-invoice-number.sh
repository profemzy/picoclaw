#!/usr/bin/env bash
# oluto-next-invoice-number.sh — Suggest the next invoice number
# Usage: oluto-next-invoice-number.sh [PREFIX]
# Default prefix: INV
#
# NOTE: This runs on Alpine/BusyBox — do NOT use grep -P (Perl regex).
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API="$SCRIPT_DIR/oluto-api.sh"
CONFIG_FILE="$HOME/.oluto-config.json"

PREFIX="${1:-INV}"

BID="${OLUTO_BUSINESS_ID:-$(jq -r '.default_business_id' "$CONFIG_FILE")}"

RESULT=$("$API" GET "/api/v1/businesses/$BID/invoices?limit=100" 2>&1 || true)

# Extract the highest numeric suffix from existing invoice numbers
HIGHEST=$(echo "$RESULT" | jq -r --arg pfx "$PREFIX" '
    if type == "array" then
        [.[] | .invoice_number | select(startswith($pfx)) |
         ltrimstr($pfx) | ltrimstr("-") | tonumber? // 0] | max // 0
    else 0 end
' 2>/dev/null || echo 0)

NEXT=$((HIGHEST + 1))
PADDED=$(printf "%03d" "$NEXT")
echo "${PREFIX}-${PADDED}"
