#!/bin/bash
# oluto-briefing.sh — Gather all data for the daily financial briefing
# Outputs a combined JSON object with dashboard, overdue invoices, overdue bills, and recent transactions
set -euo pipefail

# Ensure jq and other local binaries are in PATH
export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API="$SCRIPT_DIR/oluto-api.sh"

# Read business ID from config
CONFIG_FILE="$HOME/.oluto-config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  echo '{"error": "Config not found. Run oluto-setup.sh first."}' >&2
  exit 1
fi

BID=$(jq -r '.default_business_id' "$CONFIG_FILE")
if [ -z "$BID" ] || [ "$BID" = "null" ]; then
  echo '{"error": "No default_business_id in config."}' >&2
  exit 1
fi

BASE="/api/v1/businesses/$BID"

# Calculate yesterday's date
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null)
TODAY=$(date +%Y-%m-%d)

# Gather all data (continue on individual failures)
DASHBOARD=$($API GET "$BASE/transactions/summary" 2>/dev/null || echo '{}')
OVERDUE_INVOICES=$($API GET "$BASE/invoices/overdue" 2>/dev/null || echo '[]')
OVERDUE_BILLS=$($API GET "$BASE/bills/overdue" 2>/dev/null || echo '[]')
RECENT_TXN=$($API GET "$BASE/transactions?start_date=$YESTERDAY&limit=10" 2>/dev/null || echo '[]')

# Also get open bills (not yet overdue but upcoming)
OPEN_BILLS=$($API GET "$BASE/bills?status=open" 2>/dev/null || echo '[]')

# Combine into a single JSON output
jq -n \
  --arg date "$TODAY" \
  --argjson dashboard "$DASHBOARD" \
  --argjson overdue_invoices "$OVERDUE_INVOICES" \
  --argjson overdue_bills "$OVERDUE_BILLS" \
  --argjson open_bills "$OPEN_BILLS" \
  --argjson recent_transactions "$RECENT_TXN" \
  '{
    briefing_date: $date,
    dashboard: $dashboard,
    overdue_invoices: $overdue_invoices,
    overdue_bills: $overdue_bills,
    open_bills: $open_bills,
    recent_transactions: $recent_transactions
  }'
