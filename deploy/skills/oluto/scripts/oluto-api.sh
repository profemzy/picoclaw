#!/usr/bin/env bash
# oluto-api.sh — Call LedgerForge API with automatic authentication.
# Usage: oluto-api.sh METHOD PATH [JSON_BODY]
# Examples:
#   oluto-api.sh GET /api/v1/businesses/{bid}/transactions/summary
#   oluto-api.sh POST /api/v1/businesses/{bid}/transactions '{"vendor_name":"Staples","amount":"50.00",...}'
#   oluto-api.sh PATCH /api/v1/businesses/{bid}/transactions/{id} '{"status":"posted"}'
#   oluto-api.sh DELETE /api/v1/businesses/{bid}/transactions/{id}
set -euo pipefail

# Ensure jq and other local binaries are in PATH
export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${HOME}/.oluto-config.json"

if [ $# -lt 2 ]; then
    echo "Usage: oluto-api.sh METHOD PATH [JSON_BODY]" >&2
    exit 1
fi

METHOD="$1"
PATH_ARG="$2"
BODY="${3:-}"

BASE_URL=$(jq -r '.base_url' "$CONFIG_FILE")
TOKEN=$("${SCRIPT_DIR}/oluto-auth.sh")

# Build curl args
CURL_ARGS=(-s -w "\n%{http_code}" -X "$METHOD")
CURL_ARGS+=(-H "Authorization: Bearer ${TOKEN}")
CURL_ARGS+=(-H "Content-Type: application/json")

if [ -n "$BODY" ]; then
    CURL_ARGS+=(-d "$BODY")
fi

# Make request
RESPONSE=$(curl "${CURL_ARGS[@]}" "${BASE_URL}${PATH_ARG}")

# Split response body and status code
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY_RESP=$(echo "$RESPONSE" | sed '$d')

# Handle non-2xx
if [ "${HTTP_CODE:0:1}" != "2" ]; then
    echo "ERROR (HTTP ${HTTP_CODE}):"
    if echo "$BODY_RESP" | jq . >/dev/null 2>&1; then
        ERROR_MSG=$(echo "$BODY_RESP" | jq -r '.error // .message // .detail // "Unknown error"')
        echo "$ERROR_MSG"
    else
        echo "$BODY_RESP"
    fi
    exit 1
fi

# Handle 204 No Content
if [ "$HTTP_CODE" = "204" ] || [ -z "$BODY_RESP" ]; then
    echo "Success (no content)"
    exit 0
fi

# Unwrap { success, data } envelope
if echo "$BODY_RESP" | jq -e '.success' >/dev/null 2>&1; then
    SUCCESS=$(echo "$BODY_RESP" | jq -r '.success')
    if [ "$SUCCESS" = "true" ]; then
        echo "$BODY_RESP" | jq '.data'
    else
        MSG=$(echo "$BODY_RESP" | jq -r '.error // .message // "API error"')
        echo "ERROR: $MSG" >&2
        exit 1
    fi
else
    # Raw response (health check, etc.)
    echo "$BODY_RESP" | jq . 2>/dev/null || echo "$BODY_RESP"
fi
