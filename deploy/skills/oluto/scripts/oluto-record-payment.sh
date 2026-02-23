#!/usr/bin/env bash
# oluto-record-payment.sh — Record a customer payment (with optional invoice application)
# Usage: oluto-record-payment.sh 'JSON_PAYLOAD'
# JSON requires: customer_id, payment_date, amount, payment_method
# Optional: applications[{invoice_id, amount_applied}], reference_number, memo
#
# Example:
#   oluto-record-payment.sh '{"customer_id":"uuid","payment_date":"2026-02-20",
#     "amount":"1500.00","payment_method":"e-transfer",
#     "applications":[{"invoice_id":"inv-uuid","amount_applied":"1500.00"}]}'
#
# NOTE: This runs on Alpine/BusyBox — do NOT use grep -P (Perl regex).
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API="$SCRIPT_DIR/oluto-api.sh"
CONFIG_FILE="$HOME/.oluto-config.json"

if [ $# -lt 1 ]; then
    echo "Usage: oluto-record-payment.sh 'JSON_PAYLOAD'" >&2
    exit 1
fi

PAYLOAD="$1"

BID="${OLUTO_BUSINESS_ID:-$(jq -r '.default_business_id' "$CONFIG_FILE")}"

# Validate required fields
CUSTOMER_ID=$(echo "$PAYLOAD" | jq -r '.customer_id // empty')
AMOUNT=$(echo "$PAYLOAD" | jq -r '.amount // empty')
PAY_DATE=$(echo "$PAYLOAD" | jq -r '.payment_date // empty')
PAY_METHOD=$(echo "$PAYLOAD" | jq -r '.payment_method // empty')

if [ -z "$CUSTOMER_ID" ] || [ -z "$AMOUNT" ] || [ -z "$PAY_DATE" ] || [ -z "$PAY_METHOD" ]; then
    echo "Error: Missing required fields. Need: customer_id, amount, payment_date, payment_method" >&2
    exit 1
fi

RESULT=$("$API" POST "/api/v1/businesses/$BID/payments" "$PAYLOAD" 2>&1 || true)

PAY_ID=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null || true)

if [ -n "$PAY_ID" ]; then
    APP_COUNT=$(echo "$PAYLOAD" | jq '.applications | length' 2>/dev/null || echo 0)
    echo "Payment recorded: \$$AMOUNT on $PAY_DATE via $PAY_METHOD"
    if [ "$APP_COUNT" -gt 0 ]; then
        echo "Applied to $APP_COUNT invoice(s)."
    else
        echo "Payment is unapplied — can be applied to invoices later."
    fi
    echo "Payment ID: $PAY_ID"
else
    echo "Error: Could not record payment. $RESULT" >&2
    exit 1
fi
