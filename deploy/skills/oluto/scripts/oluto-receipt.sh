#!/usr/bin/env bash
# oluto-receipt.sh — Full receipt processing: OCR → categorize → match → create transaction
# Usage: oluto-receipt.sh FILE_PATH
# Output: Human-readable summary (NOT raw JSON)
#
# NOTE: This runs on Alpine/BusyBox — do NOT use grep -P (Perl regex).
# Use grep -E (extended regex) or sed instead.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API="$SCRIPT_DIR/oluto-api.sh"
AUTH="$SCRIPT_DIR/oluto-auth.sh"
MATCH="$SCRIPT_DIR/oluto-match-transaction.sh"
ATTACH="$SCRIPT_DIR/oluto-attach-receipt.sh"
CONFIG_FILE="$HOME/.oluto-config.json"

if [ $# -lt 1 ]; then
    echo "Error: Please provide a file path."
    exit 1
fi

FILE_PATH="$1"

if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File not found at $FILE_PATH"
    exit 1
fi

BASE_URL=$(jq -r '.base_url' "$CONFIG_FILE")
BID="${OLUTO_BUSINESS_ID:-$(jq -r '.default_business_id' "$CONFIG_FILE")}"
TOKEN=$("$AUTH")

# Step 1: OCR extraction
OCR_RESP=$(curl -sf -H "Authorization: Bearer $TOKEN" \
    -F "file=@$FILE_PATH" \
    "${BASE_URL}/api/v1/businesses/${BID}/receipts/extract-ocr" 2>/dev/null || echo '{"success":false}')

SUCCESS=$(echo "$OCR_RESP" | jq -r '.success // false')
if [ "$SUCCESS" != "true" ]; then
    echo "Error: Could not read the receipt image."
    exit 1
fi

OCR_DATA=$(echo "$OCR_RESP" | jq '.data.ocr_data')
RAW_TEXT=$(echo "$OCR_DATA" | jq -r '.raw_text // ""')

# Extract fields from OCR
VENDOR=$(echo "$OCR_DATA" | jq -r '.vendor // "Unknown"')
AMOUNT=$(echo "$OCR_DATA" | jq -r '.amount // "0.00"')
DATE=$(echo "$OCR_DATA" | jq -r '.date // ""')
TAX_AMOUNTS=$(echo "$OCR_DATA" | jq '.tax_amounts // null')

# --- Helper: extract dollar amount from a line (BusyBox-compatible) ---
# Matches patterns like $19.00, US$19.00, CA$26.91, $1,234.56
extract_dollar() {
    sed -n 's/.*[US$CA]*\$\([0-9,]*[0-9]\.[0-9][0-9]\).*/\1/p' | tr -d ',' | head -1
}

# Always prefer TOTAL from raw text over OCR amount (OCR often returns subtotal)
PARSED_TOTAL=$(echo "$RAW_TEXT" | grep -i '^[[:space:]]*total' | extract_dollar || true)
if [ -n "$PARSED_TOTAL" ]; then
    AMOUNT="$PARSED_TOTAL"
elif [ "$AMOUNT" = "0.00" ] || [ "$AMOUNT" = "0" ] || [ "$AMOUNT" = "null" ]; then
    # Fallback: any line with "total" keyword
    PARSED_TOTAL=$(echo "$RAW_TEXT" | grep -i 'total' | extract_dollar || true)
    if [ -n "$PARSED_TOTAL" ]; then
        AMOUNT="$PARSED_TOTAL"
    fi
fi

# Check for CAD conversion (e.g. "Charged CA$26.91 using 1 USD = 1.4162 CAD")
CAD_AMOUNT=$(echo "$RAW_TEXT" | grep -i 'CA\$' | extract_dollar || true)
if [ -n "$CAD_AMOUNT" ]; then
    AMOUNT="$CAD_AMOUNT"
fi

# Normalize date to YYYY-MM-DD format
normalize_date() {
    local input="$1"
    [ -z "$input" ] || [ "$input" = "null" ] && return 1

    # Already YYYY-MM-DD
    if echo "$input" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        echo "$input"
        return 0
    fi

    # MM-DD-YYYY or MM/DD/YYYY
    if echo "$input" | grep -qE '^[0-9]{2}[-/][0-9]{2}[-/][0-9]{4}$'; then
        local m=$(echo "$input" | cut -c1-2)
        local d=$(echo "$input" | cut -c4-5)
        local y=$(echo "$input" | cut -c7-10)
        echo "${y}-${m}-${d}"
        return 0
    fi

    # Try date command (works for many formats on BusyBox)
    date -d "$input" +%Y-%m-%d 2>/dev/null && return 0

    # Last resort: replace slashes with dashes
    echo "$input" | sed 's|/|-|g'
    return 0
}

DATE=$(normalize_date "$DATE" || echo "")

# Parse date from raw text if OCR date is empty or invalid
if [ -z "$DATE" ]; then
    # Match "Month DD, YYYY" or "Month DD YYYY" patterns
    PARSED_DATE=$(echo "$RAW_TEXT" | sed -n 's/.*\(January\|February\|March\|April\|May\|June\|July\|August\|September\|October\|November\|December\|Jan\|Feb\|Mar\|Apr\|Jun\|Jul\|Aug\|Sep\|Oct\|Nov\|Dec\)[[:space:]]*\([0-9]\{1,2\}\)[,]*[[:space:]]*\([0-9]\{4\}\).*/\1 \2 \3/p' | head -1 || true)
    if [ -n "$PARSED_DATE" ]; then
        DATE=$(date -d "$PARSED_DATE" +%Y-%m-%d 2>/dev/null || echo "")
    fi
fi

# Calculate tax
GST_AMOUNT="0.00"
PST_AMOUNT="0.00"
if [ "$TAX_AMOUNTS" != "null" ] && [ -n "$TAX_AMOUNTS" ]; then
    GST_AMOUNT=$(echo "$TAX_AMOUNTS" | jq -r '.gst // "0.00"')
    PST_AMOUNT=$(echo "$TAX_AMOUNTS" | jq -r '.pst // "0.00"')
fi

# If tax amounts are still 0, try to find tax line in raw text
if [ "$GST_AMOUNT" = "0.00" ] || [ "$GST_AMOUNT" = "null" ]; then
    PARSED_TAX=$(echo "$RAW_TEXT" | grep -iE '^[[:space:]]*(tax|gst|hst)' | extract_dollar || true)
    if [ -n "$PARSED_TAX" ]; then
        GST_AMOUNT="$PARSED_TAX"
    fi
fi

[ "$GST_AMOUNT" = "null" ] && GST_AMOUNT="0.00"
[ "$PST_AMOUNT" = "null" ] && PST_AMOUNT="0.00"

# Clean vendor name
# Remove markdown image syntax like ![img-0.jpeg](img-0.jpeg)
VENDOR=$(echo "$VENDOR" | sed 's/!\[.*\](.*)//' | sed 's/^#[[:space:]]*//' | xargs)

# If vendor is empty, too short, or generic — try to extract from raw text
if [ -z "$VENDOR" ] || [ "$VENDOR" = "Unknown" ] || [ "$VENDOR" = "Receipt" ] || [ "${#VENDOR}" -lt 3 ]; then
    # Look for company name patterns in raw text (skip header lines like "Receipt", "Invoice")
    PARSED_VENDOR=$(echo "$RAW_TEXT" | sed 's/^#[[:space:]]*//' | grep -v '^\s*$' | grep -viE '^(receipt|invoice|order|bill|payment|date|total|subtotal|tax|amount)' | head -1 | xargs || true)
    if [ -n "$PARSED_VENDOR" ] && [ "${#PARSED_VENDOR}" -ge 3 ] && [ "${#PARSED_VENDOR}" -lt 60 ]; then
        VENDOR="$PARSED_VENDOR"
    fi
fi

# If amount is 0, don't try to create anything — just report what we found
if [ "$AMOUNT" = "0.00" ] || [ "$AMOUNT" = "0" ] || [ "$AMOUNT" = "null" ] || [ -z "$AMOUNT" ]; then
    echo "Receipt from $VENDOR (date: ${DATE:-unknown})"
    echo "Amount could not be extracted. Please provide the total so I can log it."
    exit 0
fi

# Step 2: Get AI category suggestion from LedgerForge
CATEGORY="Meals and Entertainment"
SUGGEST_BODY=$(jq -n --arg vendor "$VENDOR" --arg amount "$AMOUNT" \
    '{vendor_name: $vendor, amount: $amount}')
SUGGEST_RESP=$("$API" POST "/api/v1/businesses/$BID/transactions/suggest-category" "$SUGGEST_BODY" 2>/dev/null || true)
SUGGESTED=$(echo "$SUGGEST_RESP" | jq -r '.category // empty' 2>/dev/null || true)
if [ -n "$SUGGESTED" ]; then
    CATEGORY="$SUGGESTED"
fi

# Step 3: Try to match existing transaction
MATCHES="[]"
if [ -n "$DATE" ]; then
    MATCHES=$("$MATCH" "$AMOUNT" "$DATE" "$VENDOR" 2>/dev/null || echo '[]')
fi

MATCH_COUNT=$(echo "$MATCHES" | jq 'length' 2>/dev/null || echo 0)

# Step 4: Handle result
if [ "$MATCH_COUNT" -gt 0 ]; then
    # Found matching transaction — attach receipt to it
    MATCH_VENDOR=$(echo "$MATCHES" | jq -r '.[0].vendor_name // "Unknown"')
    MATCH_AMOUNT=$(echo "$MATCHES" | jq -r '.[0].amount // "0.00"')
    MATCH_DATE=$(echo "$MATCHES" | jq -r '.[0].transaction_date // "unknown"')
    MATCH_ID=$(echo "$MATCHES" | jq -r '.[0].id // ""')

    # Attach receipt image to the matched transaction (Azure Blob) and clean up local file
    if [ -n "$MATCH_ID" ]; then
        "$ATTACH" "$MATCH_ID" "$FILE_PATH" 2>/dev/null || true
    fi

    echo "Receipt matched existing transaction: \$$MATCH_AMOUNT at $MATCH_VENDOR on $MATCH_DATE (ID: $MATCH_ID)"
else
    # No match — create new expense
    TXN_DATE="${DATE:-$(date +%Y-%m-%d)}"
    DESCRIPTION="Receipt capture - $VENDOR"

    BODY=$(jq -n \
        --arg vendor "$VENDOR" \
        --arg amount "$AMOUNT" \
        --arg date "$TXN_DATE" \
        --arg desc "$DESCRIPTION" \
        --arg category "$CATEGORY" \
        --arg gst "$GST_AMOUNT" \
        --arg pst "$PST_AMOUNT" \
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

    # Check if creation succeeded
    TXN_ID=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null || true)

    if [ -n "$TXN_ID" ]; then
        # Attach receipt image to the new transaction (Azure Blob) and clean up local file
        "$ATTACH" "$TXN_ID" "$FILE_PATH" 2>/dev/null || true

        TAX_INFO=""
        [ "$GST_AMOUNT" != "0.00" ] && TAX_INFO=" | GST: \$$GST_AMOUNT"
        [ "$PST_AMOUNT" != "0.00" ] && TAX_INFO="$TAX_INFO | PST: \$$PST_AMOUNT"
        echo "Receipt processed: \$$AMOUNT at $VENDOR on $TXN_DATE"
        echo "Category: ${CATEGORY}${TAX_INFO}"
        echo "Saved as draft expense. Receipt image stored."
    else
        echo "Receipt from $VENDOR: \$$AMOUNT on $TXN_DATE"
        echo "Could not save to ledger. Please create manually."
    fi
fi
