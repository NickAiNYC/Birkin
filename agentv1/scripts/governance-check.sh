#!/bin/bash
# =============================================================================
# governance-check.sh — Master governance validation script
# Version: 1.0.0 | Scrutexity Agent Governance Layer
# Mirrors Directora's governance-check.sh patterns
# Usage: ./governance-check.sh [--verbose]
# =============================================================================
set -euo pipefail

VERBOSE=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --verbose) VERBOSE=true ;;
        --help)
            echo "Usage: ./governance-check.sh [--verbose]"
            echo "Runs all governance validations and reports status."
            exit 0
            ;;
    esac
    shift
done

HERMES_PORT="${HERMES_API_PORT:-8686}"
HEALTH_PORT="${HEALTH_PORT:-9999}"
AUDIT_DB="${HERMES_AUDIT_DB:-$HOME/.hermes/audit.db}"
SKILLS_DIR="${HERMES_SKILLS_DIR:-$HOME/.hermes/skills}"
DRIFT_DIR="${HERMES_DRIFT_DIR:-$HOME/.hermes/drift}"

PASS=0
FAIL=0

check() {
    local name="$1"
    local cmd="$2"
    local critical="${3:-true}"

    if eval "$cmd" > /dev/null 2>&1; then
        echo "  ✅ $name"
        PASS=$((PASS + 1))
        return 0
    else
        if [ "$critical" = "true" ]; then
            echo "  ❌ $name"
            FAIL=$((FAIL + 1))
        else
            echo "  ⚠️  $name (non-critical)"
        fi
        return 1
    fi
}

echo "=== Scrutexity Agent Governance Check ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# 1. Hermes process running
echo "[1/5] Hermes Gateway Process"
check "Hermes gateway systemd service active" "systemctl is-active --quiet hermes-gateway" true || true
check "Hermes API responding" "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:${HERMES_PORT}/health | grep -q '^200$'" true || true

# 2. Audit log append-only
echo ""
echo "[2/5] Audit Log Append-Only Integrity"
if [ -f "$AUDIT_DB" ]; then
    check "Audit database exists" "test -f $AUDIT_DB" true

    # Check for modified entries (append-only means no entry should have a modified_at > created_at)
    MODIFIED_COUNT=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM audit_log WHERE modified_at IS NOT NULL AND modified_at > created_at;" 2>/dev/null || echo "0")
    if [ "$MODIFIED_COUNT" = "0" ] || [ -z "$MODIFIED_COUNT" ]; then
        echo "  ✅ No tampered audit entries detected (append-only intact)"
        PASS=$((PASS + 1))
    else
        echo "  ❌ $MODIFIED_COUNT audit entries show modification after creation"
        FAIL=$((FAIL + 1))
    fi

    # Check for sequential timestamps (basic ordering check)
    OUT_OF_ORDER=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM (SELECT timestamp, LAG(timestamp) OVER (ORDER BY id) as prev FROM audit_log) WHERE timestamp < prev;" 2>/dev/null || echo "0")
    if [ "$OUT_OF_ORDER" = "0" ]; then
        echo "  ✅ Audit timestamps are monotonically ordered"
        PASS=$((PASS + 1))
    else
        echo "  ❌ $OUT_OF_ORDER out-of-order timestamps detected"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  ⚠️  Audit database not found (Hermes may not have logged yet)"
fi

# 3. Skill versions consistent with git
echo ""
echo "[3/5] Skill Version Consistency"
cd "$SKILLS_DIR" 2>/dev/null || { echo "  ❌ Skills directory not found"; FAIL=$((FAIL + 1)); }
if [ -d .git ]; then
    check "Skills directory is a git repo" "test -d .git" true

    UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l)
    if [ "$UNCOMMITTED" -eq 0 ]; then
        echo "  ✅ No uncommitted skill changes"
        PASS=$((PASS + 1))
    else
        echo "  ⚠️  $UNCOMMITTED uncommitted skill changes (non-critical)"
    fi

    # Check each skill file has a version in frontmatter
    MISSING_VERSION=0
    for f in *.md; do
        [ -f "$f" ] || continue
        if ! grep -q "^version:" "$f"; then
            echo "  ❌ $f missing version in frontmatter"
            MISSING_VERSION=$((MISSING_VERSION + 1))
        fi
    done
    if [ "$MISSING_VERSION" -eq 0 ]; then
        echo "  ✅ All skills have version metadata"
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + MISSING_VERSION))
    fi
else
    echo "  ❌ Skills directory not under git version control"
    FAIL=$((FAIL + 1))
fi

# 4. Drift check passes
echo ""
echo "[4/5] Drift Detection"
if [ -f "$DRIFT_DIR/baseline.json" ]; then
    LATEST_RESULT=$(ls -t "$DRIFT_DIR"/drift-results-*.json 2>/dev/null | head -1)
    if [ -n "$LATEST_RESULT" ]; then
        DRIFT_STATUS=$(python3 -c "import json; d=json.load(open('$LATEST_RESULT')); print(d.get('status','UNKNOWN'))")
        if [ "$DRIFT_STATUS" = "PASS" ]; then
            echo "  ✅ Latest drift check passed ($(basename $LATEST_RESULT))"
            PASS=$((PASS + 1))
        else
            echo "  ❌ Latest drift check failed ($(basename $LATEST_RESULT))"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  ⚠️  Baseline exists but no drift results yet (run drift-check.sh)"
    fi
else
    echo "  ⚠️  No drift baseline found (run drift-check.sh --update-baseline)"
fi

# 5. Health endpoint responds
echo ""
echo "[5/5] Health Endpoint"
check "Health endpoint responds" "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:${HEALTH_PORT}/health | grep -q '^200$'" true
check "Health JSON is valid" "curl -s http://127.0.0.1:${HEALTH_PORT}/health | python3 -c 'import sys,json; json.load(sys.stdin)'" true

# Summary
echo ""
echo "=== Governance Check Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo "✅ AGENT GOVERNANCE INTACT"
    echo "   All critical checks passed. Agent is operating within governance boundaries."
    exit 0
else
    echo "❌ GOVERNANCE FAILED: $FAIL critical check(s) failed"
    echo "   Review failures above and remediate before resuming autonomous operations."
    exit 1
fi
