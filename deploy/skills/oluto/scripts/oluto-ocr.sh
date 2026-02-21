#!/usr/bin/env bash
# oluto-ocr.sh — Upload receipt image to LedgerForge OCR and return raw text
# Usage: oluto-ocr.sh FILE_PATH
# Output: Raw OCR text from the receipt (for LLM to parse)
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTH="$SCRIPT_DIR/oluto-auth.sh"
CONFIG_FILE="$HOME/.oluto-config.json"

if [ $# -lt 1 ]; then
    echo "Error: Please provide a file path." >&2
    exit 1
fi

FILE_PATH="$1"

if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File not found at $FILE_PATH" >&2
    exit 1
fi

BASE_URL=$(jq -r '.base_url' "$CONFIG_FILE")
BID=$(jq -r '.default_business_id' "$CONFIG_FILE")
TOKEN=$("$AUTH")

# Upload to LedgerForge OCR endpoint
OCR_RESP=$(curl -sf -H "Authorization: Bearer $TOKEN" \
    -F "file=@$FILE_PATH" \
    "${BASE_URL}/api/v1/businesses/${BID}/receipts/extract-ocr" 2>/dev/null || echo '{"success":false}')

SUCCESS=$(echo "$OCR_RESP" | jq -r '.success // false')
if [ "$SUCCESS" != "true" ]; then
    echo "Error: Could not read the receipt image." >&2
    exit 1
fi

# Output today's date as context (helps LLM disambiguate dates on receipts)
echo "TODAY: $(date +%Y-%m-%d)"
echo "---"
# Output the raw OCR text — the agent LLM will extract structured fields
echo "$OCR_RESP" | jq -r '.data.ocr_data.raw_text // ""'
