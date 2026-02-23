#!/usr/bin/env bash
# oluto-record-income.sh — Create a draft income transaction
# Usage: oluto-record-income.sh PAYER AMOUNT DATE [CATEGORY] [GST] [PST] [DESCRIPTION]
# Example: oluto-record-income.sh "Acme Corp" "5000.00" "2026-02-20" "Consulting Revenue" "250.00" "0.00" "February retainer"
#
# NOTE: This runs on Alpine/BusyBox — do NOT use grep -P (Perl regex).
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API="$SCRIPT_DIR/oluto-api.sh"
CONFIG_FILE="$HOME/.oluto-config.json"

if [ $# -lt 3 ]; then
    echo "Usage: oluto-record-income.sh PAYER AMOUNT DATE [CATEGORY] [GST] [PST] [DESCRIPTION]" >&2
    exit 1
fi

PAYER="$1"
AMOUNT="$2"
DATE="$3"
CATEGORY="${4:-Service Revenue}"
GST="${5:-0.00}"
PST="${6:-0.00}"
DESCRIPTION="${7:-Income from $PAYER}"

BID="${OLUTO_BUSINESS_ID:-$(jq -r '.default_business_id' "$CONFIG_FILE")}"

# Income is stored as positive amount with business_income classification
BODY=$(jq -n \
    --arg vendor "$PAYER" \
    --arg amount "$AMOUNT" \
    --arg date "$DATE" \
    --arg desc "$DESCRIPTION" \
    --arg category "$CATEGORY" \
    --arg gst "$GST" \
    --arg pst "$PST" \
    '{
        vendor_name: $vendor,
        amount: $amount,
        transaction_date: $date,
        description: $desc,
        classification: "business_income",
        category: $category,
        currency: "CAD",
        gst_amount: $gst,
        pst_amount: $pst
    }')

RESULT=$("$API" POST "/api/v1/businesses/$BID/transactions" "$BODY" 2>&1 || true)

TXN_ID=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null || true)

if [ -n "$TXN_ID" ]; then
    echo "Income recorded: \$$AMOUNT from $PAYER on $DATE (Category: $CATEGORY)"
    [ "$GST" != "0.00" ] && [ "$GST" != "0" ] && echo "GST/HST collected: \$$GST"
    [ "$PST" != "0.00" ] && [ "$PST" != "0" ] && echo "PST collected: \$$PST"
    echo "Saved as draft income (ID: $TXN_ID)."
else
    echo "Error: Could not record income. $RESULT" >&2
    exit 1
fi
