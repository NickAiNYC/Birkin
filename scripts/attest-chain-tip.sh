#!/usr/bin/env bash
# =============================================================================
# attest-chain-tip.sh — Hourly remote attestation of the audit chain tip
#
# Queries the latest row_hash from audit_log and posts it to Telegram so an
# external party can verify the chain hasn't been silently replaced.
#
# Crontab (add via: crontab -e):
#   0 * * * * /opt/birkin/scripts/attest-chain-tip.sh >> /var/log/birkin/attest.log 2>&1
#
# Required env vars:
#   TELEGRAM_BOT_TOKEN   — bot token from @BotFather
#   TELEGRAM_CHAT_ID     — target chat/channel ID
#   HERMES_AUDIT_DB      — path to audit.db (default: ~/.hermes/audit.db)
# =============================================================================
set -euo pipefail

AUDIT_DB="${HERMES_AUDIT_DB:-$HOME/.hermes/audit.db}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    echo "[$TIMESTAMP] ERROR: TELEGRAM_BOT_TOKEN not set" >&2
    exit 1
fi

if [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    echo "[$TIMESTAMP] ERROR: TELEGRAM_CHAT_ID not set" >&2
    exit 1
fi

if [[ ! -f "$AUDIT_DB" ]]; then
    echo "[$TIMESTAMP] WARN: audit db not found at $AUDIT_DB — skipping attestation" >&2
    exit 0
fi

CHAIN_TIP=$(sqlite3 "$AUDIT_DB" \
    "SELECT row_hash FROM audit_log ORDER BY id DESC LIMIT 1;" 2>/dev/null || echo "")

if [[ -z "$CHAIN_TIP" ]]; then
    MESSAGE="🔗 Chain tip attestation [$TIMESTAMP]: (empty chain — no entries yet)"
else
    MESSAGE="🔗 Chain tip attestation [$TIMESTAMP]: $CHAIN_TIP"
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    --data-raw "{\"chat_id\":\"${TELEGRAM_CHAT_ID}\",\"text\":$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$MESSAGE"),\"parse_mode\":\"HTML\"}" \
    --max-time 15 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
    echo "[$TIMESTAMP] OK: attested chain tip ${CHAIN_TIP:0:16}... (HTTP 200)"
else
    echo "[$TIMESTAMP] ERROR: Telegram returned HTTP $HTTP_CODE" >&2
    exit 1
fi
