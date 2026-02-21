#!/usr/bin/env bash
# oluto-setup.sh — First-time setup for Oluto LedgerForge integration.
# Creates ~/.oluto-config.json with API credentials.
# Usage: oluto-setup.sh [BASE_URL] [EMAIL] [PASSWORD] [BUSINESS_ID]
#   If args not provided, uses defaults or prompts.
set -euo pipefail

CONFIG_FILE="${HOME}/.oluto-config.json"

BASE_URL="${1:-http://localhost:3000}"
EMAIL="${2:-}"
PASSWORD="${3:-}"
BID="${4:-}"

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
    echo "Usage: oluto-setup.sh BASE_URL EMAIL PASSWORD [BUSINESS_ID]" >&2
    echo "Example: oluto-setup.sh http://localhost:3000 user@example.com mypassword" >&2
    exit 1
fi

# Test connection
echo "Testing connection to ${BASE_URL}..."
HEALTH=$(curl -sf "${BASE_URL}/api/v1/health" 2>/dev/null || true)
if [ -z "$HEALTH" ]; then
    echo "WARNING: Cannot reach ${BASE_URL}/api/v1/health" >&2
    echo "Config will be saved anyway — ensure LedgerForge is running before use." >&2
else
    echo "Connected: $(echo "$HEALTH" | jq -r '.status // "unknown"')"
fi

# Test login
echo "Testing login..."
LOGIN_RESP=$(curl -sf -X POST "${BASE_URL}/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"${EMAIL}\", \"password\": \"${PASSWORD}\"}" 2>/dev/null || true)

if [ -z "$LOGIN_RESP" ]; then
    echo "WARNING: Login test failed. Check credentials." >&2
else
    SUCCESS=$(echo "$LOGIN_RESP" | jq -r '.success // false')
    if [ "$SUCCESS" = "true" ]; then
        echo "Login successful!"
        # If no business_id provided, try to get it from user profile
        if [ -z "$BID" ]; then
            TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.access_token')
            USER_RESP=$(curl -sf -H "Authorization: Bearer ${TOKEN}" "${BASE_URL}/api/v1/auth/me" 2>/dev/null || true)
            if [ -n "$USER_RESP" ]; then
                BID=$(echo "$USER_RESP" | jq -r '.data.business_id // empty')
                if [ -n "$BID" ]; then
                    echo "Found default business: ${BID}"
                fi
            fi
        fi
    else
        echo "WARNING: Login failed. $(echo "$LOGIN_RESP" | jq -r '.error // .message // ""')" >&2
    fi
fi

# Write config
jq -n \
    --arg url "$BASE_URL" \
    --arg email "$EMAIL" \
    --arg pass "$PASSWORD" \
    --arg bid "${BID:-}" \
    '{base_url: $url, email: $email, password: $pass, default_business_id: $bid}' > "$CONFIG_FILE"

chmod 600 "$CONFIG_FILE"
echo "Config saved to ${CONFIG_FILE}"
