#!/bin/bash
# =============================================================================
# audit-log.sh — Query the Hermes SQLite audit database
# Version: 1.0.0 | Scrutexity Agent Governance Layer
# Usage: ./audit-log.sh [--today | --failed | --cost]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_DB="${HERMES_AUDIT_DB:-$HOME/.hermes/audit.db}"
LIMIT="${LIMIT:-20}"

show_help() {
    cat <<'HELP'
Usage: ./audit-log.sh [OPTION]

Query the Hermes append-only audit log.

Options:
  --today       Show only today's actions
  --failed      Show only failed actions (success=false)
  --cost        Show token usage and estimated cost summary
  --all         Show all entries (no limit)
  --help        Show this help message

Examples:
  ./audit-log.sh              # Last 20 actions
  ./audit-log.sh --today      # Today's actions only
  ./audit-log.sh --failed     # Failed actions only
  ./audit-log.sh --cost       # Monthly cost estimate
HELP
}

# Check if audit DB exists
if [ ! -f "$AUDIT_DB" ]; then
    echo "❌ Audit database not found: $AUDIT_DB"
    echo "   Hermes may not have logged any actions yet."
    exit 1
fi

# Parse arguments
MODE="recent"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --today)   MODE="today" ;;
        --failed)  MODE="failed" ;;
        --cost)    MODE="cost" ;;
        --all)     LIMIT="999999" ;;
        --help)    show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
    shift
done

echo "=== Scrutexity Agent Audit Log ==="
echo "Database: $AUDIT_DB"
echo "Mode: $MODE"
echo ""

case "$MODE" in
    recent)
        sqlite3 "$AUDIT_DB" <<SQL
SELECT 
    datetime(timestamp, 'unixepoch') as time,
    skill,
    CASE WHEN success = 1 THEN '✅' ELSE '❌' END as status,
    tokens_consumed,
    cost_usd,
    substr(action_summary, 1, 60) as summary
FROM audit_log
ORDER BY timestamp DESC
LIMIT $LIMIT;
SQL
        ;;

    today)
        sqlite3 "$AUDIT_DB" <<SQL
SELECT 
    datetime(timestamp, 'unixepoch') as time,
    skill,
    CASE WHEN success = 1 THEN '✅' ELSE '❌' END as status,
    tokens_consumed,
    cost_usd,
    substr(action_summary, 1, 60) as summary
FROM audit_log
WHERE date(timestamp, 'unixepoch') = date('now')
ORDER BY timestamp DESC;
SQL
        ;;

    failed)
        echo "⚠️  FAILED ACTIONS:"
        sqlite3 "$AUDIT_DB" <<SQL
SELECT 
    datetime(timestamp, 'unixepoch') as time,
    skill,
    tokens_consumed,
    substr(action_summary, 1, 60) as summary,
    error_message
FROM audit_log
WHERE success = 0
ORDER BY timestamp DESC;
SQL
        FAILED_COUNT=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM audit_log WHERE success = 0;")
        echo ""
        echo "Total failed actions: $FAILED_COUNT"
        if [ "$FAILED_COUNT" -gt 0 ]; then
            echo "❌ GOVERNANCE ALERT: $FAILED_COUNT failed actions detected"
        fi
        ;;

    cost)
        sqlite3 "$AUDIT_DB" <<SQL
SELECT
    strftime('%Y-%m', timestamp, 'unixepoch') as month,
    COUNT(*) as actions,
    SUM(tokens_consumed) as total_tokens,
    ROUND(SUM(cost_usd), 4) as total_cost,
    ROUND(AVG(cost_usd), 6) as avg_cost_per_action
FROM audit_log
GROUP BY month
ORDER BY month DESC
LIMIT 12;
SQL
        echo ""
        MONTHLY_ESTIMATE=$(sqlite3 "$AUDIT_DB" "SELECT ROUND(SUM(cost_usd), 2) FROM audit_log WHERE timestamp > strftime('%s', 'now', '-30 days');")
        echo "Estimated last-30-day cost: \$${MONTHLY_ESTIMATE:-0.00}"
        ;;
esac

echo ""
echo "=== End Audit Log ==="
