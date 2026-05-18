#!/usr/bin/env bash
# birkin-status.sh — Single-command health dashboard
# Usage: ./scripts/birkin-status.sh [--json]
set -euo pipefail

HEALTH_URL="${HEALTH_URL:-http://localhost:9999}"
PWA_URL="${PWA_URL:-http://localhost:3000}"
JSON_MODE=false
[[ "${1:-}" == "--json" ]] && JSON_MODE=true

# ── Helpers ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC}  $*"; }
fail() { echo -e "  ${RED}✗${NC}  $*"; }
warn() { echo -e "  ${YELLOW}!${NC}  $*"; }
sep()  { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── Fetch health JSON ─────────────────────────────────────────────────────────
HEALTH_JSON=$(curl -sf --max-time 5 "$HEALTH_URL/health" 2>/dev/null) || HEALTH_JSON=""
DETAIL_JSON=$(curl -sf --max-time 5 "$HEALTH_URL/health/detailed" 2>/dev/null) || DETAIL_JSON=""

if [[ -z "$HEALTH_JSON" ]]; then
    if [[ "$JSON_MODE" == true ]]; then
        echo '{"status":"unreachable","health_url":"'"$HEALTH_URL"'"}'
    else
        echo -e "${RED}✗ Birkin health endpoint unreachable at $HEALTH_URL${NC}"
        echo "  Is the stack running?  docker compose up -d"
    fi
    exit 1
fi

# ── Parse fields ──────────────────────────────────────────────────────────────
_jq() { echo "$HEALTH_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null || echo "${2:-?}"; }
_dq() { echo "$DETAIL_JSON"  | python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null || echo "${2:-?}"; }

AGENT_STATUS=$(_jq "d.get('agent_status','?')")
UPTIME_SEC=$(_jq "d.get('uptime_seconds',0)" 0)
SKILL_COUNT=$(_jq "d.get('skill_count',0)" 0)
AUDIT_ENTRIES=$(_jq "d.get('audit_log_entries',0)" 0)
DRIFT_STATUS=$(_jq "d.get('drift_check_status','UNKNOWN')")
LAST_ACTION=$(_jq "d.get('last_action_timestamp') or 'none'" "none")
GOV_STATUS=$(_dq "d.get('governance_status','unknown')")

UPTIME_HUMAN=$(python3 -c "
s=$UPTIME_SEC
h,m = divmod(s,3600); m,sc = divmod(m,60)
print(f'{h}h {m}m' if h else (f'{m}m {sc}s' if m else f'{sc}s'))
" 2>/dev/null || echo "${UPTIME_SEC}s")

if [[ "$JSON_MODE" == true ]]; then
    echo "$HEALTH_JSON"
    exit 0
fi

# ── Dashboard ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Birkin Status${NC}  —  $(date '+%Y-%m-%d %H:%M:%S')"
sep

# Agent
if [[ "$AGENT_STATUS" == "healthy" ]]; then
    ok "Agent: ${BOLD}healthy${NC}  (uptime ${UPTIME_HUMAN})"
else
    fail "Agent: ${BOLD}${AGENT_STATUS}${NC}  (uptime ${UPTIME_HUMAN})"
fi

# Governance
if [[ "$GOV_STATUS" == "intact" ]]; then
    ok "Governance: ${BOLD}intact${NC}  (5/5 gates)"
elif [[ "$GOV_STATUS" == "review_needed" ]]; then
    warn "Governance: ${BOLD}review needed${NC}  — run ./governance-check.sh"
else
    warn "Governance: ${BOLD}${GOV_STATUS}${NC}"
fi

# Drift
if [[ "$DRIFT_STATUS" == "PASS" ]]; then
    ok "Drift check: ${BOLD}PASS${NC}"
elif [[ "$DRIFT_STATUS" == "UNKNOWN" ]]; then
    warn "Drift check: ${BOLD}not yet run${NC}  — run ./drift-check.sh"
else
    fail "Drift check: ${BOLD}${DRIFT_STATUS}${NC}  — run ./drift-check.sh"
fi

sep

# Skills + audit
echo -e "  ${CYAN}Skills deployed:${NC}  $SKILL_COUNT"
echo -e "  ${CYAN}Audit entries:${NC}    $AUDIT_ENTRIES"
echo -e "  ${CYAN}Last action:${NC}      $LAST_ACTION"

sep

# Quick actions
echo -e "  ${BOLD}iPhone PWA${NC}         $PWA_URL"
echo -e "  ${BOLD}Governance${NC}         $HEALTH_URL/health"
echo -e "  ${BOLD}Full check${NC}         ./governance-check.sh --verbose"
echo -e "  ${BOLD}Tamper proof${NC}       ./tests/tamper-test.sh"
echo -e "  ${BOLD}Logs${NC}               docker compose logs -f"
echo ""
