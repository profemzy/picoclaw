#!/usr/bin/env bash
# oluto-dashboard.sh — Get dashboard summary for the default business.
# Usage: oluto-dashboard.sh [BUSINESS_ID]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${HOME}/.oluto-config.json"

BID="${OLUTO_BUSINESS_ID:-${1:-$(jq -r '.default_business_id // empty' "$CONFIG_FILE")}}"
if [ -z "$BID" ]; then
    echo "ERROR: No business_id provided and no default_business_id in config" >&2
    exit 1
fi

"${SCRIPT_DIR}/oluto-api.sh" GET "/api/v1/businesses/${BID}/transactions/summary"
