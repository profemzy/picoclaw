#!/usr/bin/env bash
# oluto-create-expense.sh — Create a draft expense transaction
# Usage: oluto-create-expense.sh VENDOR AMOUNT DATE [CATEGORY] [GST] [PST] [DESCRIPTION]
# Example: oluto-create-expense.sh "The Home Depot" "36.67" "2026-02-07" "Office Expenses" "1.75" "0.00"
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API="$SCRIPT_DIR/oluto-api.sh"
CONFIG_FILE="$HOME/.oluto-config.json"

if [ $# -lt 3 ]; then
    echo "Usage: oluto-create-expense.sh VENDOR AMOUNT DATE [CATEGORY] [GST] [PST] [DESCRIPTION]" >&2
    exit 1
fi

VENDOR="$1"
AMOUNT="$2"
DATE="$3"
CATEGORY="${4:-Meals and Entertainment}"
GST="${5:-0.00}"
PST="${6:-0.00}"
DESCRIPTION="${7:-Receipt capture - $VENDOR}"

BID="${OLUTO_BUSINESS_ID:-$(jq -r '.default_business_id' "$CONFIG_FILE")}"

BODY=$(jq -n \
    --arg vendor "$VENDOR" \
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
        classification: "expense",
        category: $category,
        currency: "CAD",
        gst_amount: $gst,
        pst_amount: $pst
    }')

RESULT=$("$API" POST "/api/v1/businesses/$BID/transactions" "$BODY" 2>&1 || true)

TXN_ID=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null || true)

if [ -n "$TXN_ID" ]; then
    echo "Expense created: \$$AMOUNT at $VENDOR on $DATE (Category: $CATEGORY)"
    [ "$GST" != "0.00" ] && [ "$GST" != "0" ] && echo "GST/HST: \$$GST"
    [ "$PST" != "0.00" ] && [ "$PST" != "0" ] && echo "PST: \$$PST"
    echo "Saved as draft expense (ID: $TXN_ID)."
else
    echo "Error: Could not create expense. $RESULT" >&2
    exit 1
fi
