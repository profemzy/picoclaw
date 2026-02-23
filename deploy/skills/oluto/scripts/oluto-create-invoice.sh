#!/usr/bin/env bash
# oluto-create-invoice.sh — Create an invoice from a JSON payload
# Usage: oluto-create-invoice.sh 'JSON_PAYLOAD'
# The agent assembles the JSON with: invoice_number, customer_id, invoice_date,
# due_date, line_items[{line_number, item_description, quantity, unit_price, revenue_account_id}]
#
# Example:
#   oluto-create-invoice.sh '{"invoice_number":"INV-042","customer_id":"uuid",
#     "invoice_date":"2026-02-20","due_date":"2026-03-20",
#     "line_items":[{"line_number":1,"item_description":"Consulting",
#     "quantity":"10","unit_price":"150.00","revenue_account_id":"uuid"}]}'
#
# NOTE: This runs on Alpine/BusyBox — do NOT use grep -P (Perl regex).
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API="$SCRIPT_DIR/oluto-api.sh"
CONFIG_FILE="$HOME/.oluto-config.json"

if [ $# -lt 1 ]; then
    echo "Usage: oluto-create-invoice.sh 'JSON_PAYLOAD'" >&2
    exit 1
fi

PAYLOAD="$1"

BID="${OLUTO_BUSINESS_ID:-$(jq -r '.default_business_id' "$CONFIG_FILE")}"

# Validate required fields
INVOICE_NUM=$(echo "$PAYLOAD" | jq -r '.invoice_number // empty')
CUSTOMER_ID=$(echo "$PAYLOAD" | jq -r '.customer_id // empty')
INVOICE_DATE=$(echo "$PAYLOAD" | jq -r '.invoice_date // empty')
DUE_DATE=$(echo "$PAYLOAD" | jq -r '.due_date // empty')
LINE_COUNT=$(echo "$PAYLOAD" | jq '.line_items | length' 2>/dev/null || echo 0)

if [ -z "$INVOICE_NUM" ] || [ -z "$CUSTOMER_ID" ] || [ -z "$INVOICE_DATE" ] || [ -z "$DUE_DATE" ]; then
    echo "Error: Missing required fields. Need: invoice_number, customer_id, invoice_date, due_date" >&2
    exit 1
fi

if [ "$LINE_COUNT" -eq 0 ]; then
    echo "Error: At least one line_item is required." >&2
    exit 1
fi

RESULT=$("$API" POST "/api/v1/businesses/$BID/invoices" "$PAYLOAD" 2>&1 || true)

INV_ID=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null || true)
TOTAL=$(echo "$RESULT" | jq -r '.total_amount // empty' 2>/dev/null || true)

if [ -n "$INV_ID" ]; then
    echo "Invoice created: $INVOICE_NUM"
    echo "Date: $INVOICE_DATE | Due: $DUE_DATE"
    echo "Line items: $LINE_COUNT"
    [ -n "$TOTAL" ] && echo "Total: \$$TOTAL"
    echo "Status: draft (ID: $INV_ID)"
else
    echo "Error: Could not create invoice. $RESULT" >&2
    exit 1
fi
