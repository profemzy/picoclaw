#!/usr/bin/env bash
# oluto-auth.sh — Authenticate with LedgerForge and output a valid JWT token.
# If OLUTO_JWT_TOKEN env var is set (mobile app passthrough), outputs it directly.
# Otherwise, uses config-based login with caching at ~/.oluto-token.json.
set -euo pipefail

# Ensure jq and other local binaries are in PATH
export PATH="$HOME/.local/bin:$PATH"

# Mobile app JWT passthrough: if token is provided via env, use it directly
if [ -n "${OLUTO_JWT_TOKEN:-}" ]; then
    echo "$OLUTO_JWT_TOKEN"
    exit 0
fi

CONFIG_FILE="${HOME}/.oluto-config.json"
TOKEN_FILE="${HOME}/.oluto-token.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found at $CONFIG_FILE" >&2
    echo "Run oluto-setup.sh first or create it manually." >&2
    exit 1
fi

BASE_URL=$(jq -r '.base_url' "$CONFIG_FILE")
EMAIL=$(jq -r '.email' "$CONFIG_FILE")
PASSWORD=$(jq -r '.password' "$CONFIG_FILE")

# Check if we have a cached token that's still valid
if [ -f "$TOKEN_FILE" ]; then
    EXPIRY=$(jq -r '.expiry // 0' "$TOKEN_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    # Use token if it expires more than 60 seconds from now
    if [ "$EXPIRY" -gt $((NOW + 60)) ] 2>/dev/null; then
        jq -r '.access_token' "$TOKEN_FILE"
        exit 0
    fi

    # Try refresh token first
    REFRESH_TOKEN=$(jq -r '.refresh_token // empty' "$TOKEN_FILE" 2>/dev/null || true)
    if [ -n "$REFRESH_TOKEN" ]; then
        RESP=$(curl -sf -X POST "${BASE_URL}/api/v1/auth/refresh" \
            -H "Content-Type: application/json" \
            -d "{\"refresh_token\": \"${REFRESH_TOKEN}\"}" 2>/dev/null || true)
        if [ -n "$RESP" ]; then
            SUCCESS=$(echo "$RESP" | jq -r '.success // false')
            if [ "$SUCCESS" = "true" ]; then
                ACCESS=$(echo "$RESP" | jq -r '.data.access_token')
                # Decode JWT exp claim (base64 decode the payload)
                PAYLOAD=$(echo "$ACCESS" | cut -d. -f2 | base64 -d 2>/dev/null || true)
                EXP=$(echo "$PAYLOAD" | jq -r '.exp // 0' 2>/dev/null || echo 0)
                jq -n --arg at "$ACCESS" --arg rt "$REFRESH_TOKEN" --argjson exp "$EXP" \
                    '{access_token: $at, refresh_token: $rt, expiry: $exp}' > "$TOKEN_FILE"
                echo "$ACCESS"
                exit 0
            fi
        fi
    fi
fi

# Full login
RESP=$(curl -sf -X POST "${BASE_URL}/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"${EMAIL}\", \"password\": \"${PASSWORD}\"}")

SUCCESS=$(echo "$RESP" | jq -r '.success // false')
if [ "$SUCCESS" != "true" ]; then
    MSG=$(echo "$RESP" | jq -r '.error // .message // "Login failed"')
    echo "ERROR: $MSG" >&2
    exit 1
fi

ACCESS=$(echo "$RESP" | jq -r '.data.access_token')
REFRESH=$(echo "$RESP" | jq -r '.data.refresh_token // empty')

# Decode JWT exp claim
PAYLOAD=$(echo "$ACCESS" | cut -d. -f2 | base64 -d 2>/dev/null || true)
EXP=$(echo "$PAYLOAD" | jq -r '.exp // 0' 2>/dev/null || echo 0)

jq -n --arg at "$ACCESS" --arg rt "$REFRESH" --argjson exp "$EXP" \
    '{access_token: $at, refresh_token: $rt, expiry: $exp}' > "$TOKEN_FILE"

echo "$ACCESS"
