#!/usr/bin/env bash
# oluto-match-transaction.sh — Find transactions matching a receipt's amount and date
# Usage: oluto-match-transaction.sh AMOUNT DATE [VENDOR]
# Example: oluto-match-transaction.sh 49.99 2026-02-20 Staples
set -euo pipefail

# Ensure jq and other local binaries are in PATH
export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API="$SCRIPT_DIR/oluto-api.sh"
CONFIG_FILE="$HOME/.oluto-config.json"

if [ $# -lt 2 ]; then
    echo "Usage: oluto-match-transaction.sh AMOUNT DATE [VENDOR]" >&2
    exit 1
fi

AMOUNT="$1"
DATE="$2"
VENDOR="${3:-}"

BID="${OLUTO_BUSINESS_ID:-$(jq -r '.default_business_id' "$CONFIG_FILE")}"
if [ -z "$BID" ] || [ "$BID" = "null" ]; then
    echo '{"error": "No business_id provided and no default_business_id in config."}' >&2
    exit 1
fi

# Search transactions within +/- 3 days of the receipt date
START_DATE=$(date -d "$DATE - 3 days" +%Y-%m-%d 2>/dev/null || date -v-3d -j -f "%Y-%m-%d" "$DATE" +%Y-%m-%d 2>/dev/null)
END_DATE=$(date -d "$DATE + 3 days" +%Y-%m-%d 2>/dev/null || date -v+3d -j -f "%Y-%m-%d" "$DATE" +%Y-%m-%d 2>/dev/null)

BASE="/api/v1/businesses/$BID"
TRANSACTIONS=$($API GET "$BASE/transactions?start_date=$START_DATE&end_date=$END_DATE&limit=50" 2>/dev/null || echo '[]')

# Filter by amount match (exact or close) and optional vendor name
jq --arg amount "$AMOUNT" --arg vendor "$VENDOR" '
  if type == "array" then . else [] end
  | map(select(
      (.amount == $amount or
       ((.amount | tonumber) - ($amount | tonumber) | fabs) < 1.00)
      and
      (if $vendor != "" then
        (.vendor_name // "" | ascii_downcase | contains($vendor | ascii_downcase))
      else true end)
    ))
' <<< "$TRANSACTIONS"
