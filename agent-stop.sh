#!/usr/bin/env bash
# =============================================================================
# agent-stop.sh — Graceful agent shutdown (kill switch #1)
# Version: 1.0.0 | Birkin Safety Layer
#
# Stops Hermes gateway, Open WebUI, health endpoint, and all cron jobs.
# Does NOT delete data, configuration, or audit logs.
#
# Usage: ./agent-stop.sh [--force]
# Exit:  0 = stopped successfully | 1 = stop failed
# =============================================================================
set -euo pipefail

FORCE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=true ;;
        --help)
            echo "Usage: ./agent-stop.sh [--force]"
            echo "Gracefully stops all Birkin services."
            echo "--force: use SIGKILL if graceful stop fails"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

echo "=== Birkin — STOP ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

STOP_ERRORS=0

stop_service() {
    local svc="$1"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo "  Stopping $svc..."
        if [[ "$FORCE" == true ]]; then
            sudo systemctl kill "$svc" 2>/dev/null || true
        fi
        sudo systemctl stop "$svc" 2>/dev/null && echo "  ✅ $svc stopped" \
            || { echo "  ❌ Failed to stop $svc"; STOP_ERRORS=$((STOP_ERRORS+1)); }
    else
        echo "  ⚪ $svc not running (skip)"
    fi
}

# Stop systemd services
stop_service "hermes-gateway"
stop_service "birkin-health"
stop_service "scrutexity-backup.timer"

# Stop Open WebUI Docker container (graceful: allow 30s for shutdown)
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^open-webui$"; then
    echo "  Stopping open-webui container..."
    docker stop --time 30 open-webui 2>/dev/null && echo "  ✅ open-webui stopped" \
        || { echo "  ❌ Failed to stop open-webui"; STOP_ERRORS=$((STOP_ERRORS+1)); }
else
    echo "  ⚪ open-webui not running (skip)"
fi

# Kill any stray hermes processes
HERMES_PIDS=$(pgrep -f "hermes gateway" 2>/dev/null || true)
if [[ -n "$HERMES_PIDS" ]]; then
    echo "  Killing stray hermes gateway processes: $HERMES_PIDS"
    if [[ "$FORCE" == true ]]; then
        kill -9 $HERMES_PIDS 2>/dev/null || true
    else
        kill $HERMES_PIDS 2>/dev/null || true
    fi
    sleep 2
    # Verify they stopped
    pgrep -f "hermes gateway" &>/dev/null && echo "  ⚠️  hermes still running — use --force" || echo "  ✅ hermes gateway processes stopped"
fi

echo ""
echo "=== Agent Stop Summary ==="
if [[ $STOP_ERRORS -eq 0 ]]; then
    echo "✅ All services stopped cleanly"
    echo ""
    echo "To restart the agent:"
    echo "  sudo systemctl start hermes-gateway birkin-health"
    echo "  docker start open-webui"
else
    echo "❌ $STOP_ERRORS service(s) failed to stop — check logs above"
    exit 1
fi
