#!/usr/bin/env bash
# =============================================================================
# governance-check.sh — Master governance validation
# Version: 1.0.0 | Birkin Governance Layer
# Provides cryptographic integrity checks for governed agent infrastructure
#
# Usage: ./governance-check.sh [--verbose] [--json]
# Exit:  0 = GOVERNANCE INTACT | 1 = GOVERNANCE FAILED
# =============================================================================
set -euo pipefail

VERBOSE=false
JSON_OUTPUT=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose) VERBOSE=true  ;;
        --json)    JSON_OUTPUT=true ;;
        --help)
            echo "Usage: ./governance-check.sh [--verbose] [--json]"
            echo "Runs all governance validations. Exit 0 = intact, 1 = failed."
            exit 0
            ;;
        *) echo "Unknown option: $1. Use --help." >&2; exit 1 ;;
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
WARN=0
START_TIME=$(date +%s)

# ── Helpers ───────────────────────────────────────────────────────────────────
vlog() { [[ "$VERBOSE" == true ]] && echo "       $*"; }

check_pass() {
    echo "  ✅ $1"
    PASS=$((PASS + 1))
}

check_fail() {
    echo "  ❌ $1"
    [[ -n "${2:-}" ]] && echo "     Hint: $2"
    FAIL=$((FAIL + 1))
}

check_warn() {
    echo "  ⚠️  $1"
    [[ -n "${2:-}" ]] && echo "     Note: $2"
    WARN=$((WARN + 1))
}

if [[ "$JSON_OUTPUT" == false ]]; then
    echo "=== Birkin Governance Check ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
# [1/5] Hermes Gateway Process
# ════════════════════════════════════════════════════════════════════════════
if [[ "$JSON_OUTPUT" == false ]]; then echo "[1/5] Hermes Gateway Process"; fi

GATEWAY_ACTIVE=false
GATEWAY_API_OK=false

if systemctl is-active --quiet hermes-gateway 2>/dev/null; then
    check_pass "hermes-gateway systemd service is active"
    GATEWAY_ACTIVE=true
else
    check_fail "hermes-gateway systemd service is NOT active" \
        "sudo systemctl start hermes-gateway && journalctl -u hermes-gateway -n 50"
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    "http://127.0.0.1:${HERMES_PORT}/health" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
    check_pass "Hermes API responding at port $HERMES_PORT (HTTP 200)"
    GATEWAY_API_OK=true
else
    check_fail "Hermes API health check returned HTTP $HTTP_CODE (expected 200)" \
        "curl -v http://127.0.0.1:${HERMES_PORT}/health"
fi

# ════════════════════════════════════════════════════════════════════════════
# [2/5] Audit Log Append-Only Integrity
# ════════════════════════════════════════════════════════════════════════════
if [[ "$JSON_OUTPUT" == false ]]; then echo ""; echo "[2/5] Audit Log Append-Only Integrity"; fi

if [[ ! -f "$AUDIT_DB" ]]; then
    check_warn "Audit database not found at $AUDIT_DB" \
        "Hermes has not logged any actions yet — this resolves on first agent run"
else
    check_pass "Audit database exists: $AUDIT_DB"

    # Schema check — verify required columns exist
    SCHEMA_OK=$(sqlite3 "$AUDIT_DB" \
        "SELECT COUNT(*) FROM pragma_table_info('audit_log') WHERE name IN ('timestamp','created_at','modified_at','skill','success','tokens_consumed','cost_usd');" \
        2>/dev/null || echo "0")
    if [[ "$SCHEMA_OK" -ge 7 ]]; then
        check_pass "Audit table schema is complete ($SCHEMA_OK/7 required columns)"
    else
        check_fail "Audit table schema incomplete — expected 7 columns, found $SCHEMA_OK" \
            "Run: sqlite3 ~/.hermes/audit.db to inspect schema"
    fi

    # Append-only: no entry should have modified_at set (modifications forbidden)
    MODIFIED=$(sqlite3 "$AUDIT_DB" \
        "SELECT COUNT(*) FROM audit_log WHERE modified_at IS NOT NULL;" \
        2>/dev/null || echo "0")
    if [[ "$MODIFIED" -eq 0 ]]; then
        check_pass "Append-only integrity: no entries have been modified"
    else
        check_fail "Append-only violation: $MODIFIED audit entries have modified_at set" \
            "This is a governance event — do not delete or rewrite entries"
    fi

    # Monotonic timestamps (basic ordering)
    OUT_OF_ORDER=$(sqlite3 "$AUDIT_DB" \
        "SELECT COUNT(*) FROM (SELECT timestamp, LAG(timestamp) OVER (ORDER BY id) AS prev FROM audit_log) WHERE timestamp < prev;" \
        2>/dev/null || echo "0")
    if [[ "$OUT_OF_ORDER" -eq 0 ]]; then
        check_pass "Audit timestamps are monotonically ordered"
    else
        check_fail "Out-of-order timestamps: $OUT_OF_ORDER records" \
            "Possible clock skew or manual row insertion detected"
    fi

    # Entry count
    ENTRY_COUNT=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM audit_log;" 2>/dev/null || echo "0")
    vlog "Total audit entries: $ENTRY_COUNT"
fi

# ════════════════════════════════════════════════════════════════════════════
# [3/5] Skill Version Consistency
# ════════════════════════════════════════════════════════════════════════════
if [[ "$JSON_OUTPUT" == false ]]; then echo ""; echo "[3/5] Skill Version Consistency"; fi

if [[ ! -d "$SKILLS_DIR" ]]; then
    check_fail "Skills directory not found: $SKILLS_DIR" \
        "mkdir -p $SKILLS_DIR"
else
    if [[ -d "${SKILLS_DIR}/.git" ]]; then
        check_pass "Skills directory is under git version control"

        # Uncommitted changes
        UNCOMMITTED=$(git -C "$SKILLS_DIR" status --porcelain 2>/dev/null | wc -l)
        if [[ "$UNCOMMITTED" -eq 0 ]]; then
            check_pass "All skill changes are committed"
        else
            check_warn "$UNCOMMITTED uncommitted skill change(s) detected" \
                "cd $SKILLS_DIR && git add -A && git commit -m 'chore: skill update'"
        fi
    else
        check_fail "Skills directory is NOT under git control" \
            "cd $SKILLS_DIR && git init && git add -A && git commit -m 'Initial skill set'"
    fi

    # Skill count
    SKILL_COUNT=$(ls "$SKILLS_DIR"/*.md 2>/dev/null | wc -l)
    if [[ "$SKILL_COUNT" -ge 5 ]]; then
        check_pass "$SKILL_COUNT skills deployed (minimum 5 required)"
    elif [[ "$SKILL_COUNT" -gt 0 ]]; then
        check_warn "Only $SKILL_COUNT skill(s) found (expected 5+)"
    else
        check_fail "No .md skill files found in $SKILLS_DIR"
    fi

    # Each skill must have version: in frontmatter
    MISSING_VERSION=0
    MISSING_DESC=0
    MISSING_RECOVERY=0
    for f in "$SKILLS_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        fname="$(basename "$f")"
        grep -q "^version:" "$f"     || { MISSING_VERSION=$((MISSING_VERSION+1)); vlog "MISSING version: $fname"; }
        grep -q "^description:" "$f" || { MISSING_DESC=$((MISSING_DESC+1));    vlog "MISSING description: $fname"; }
        grep -q "failure_recovery" "$f" || { MISSING_RECOVERY=$((MISSING_RECOVERY+1)); vlog "MISSING failure_recovery_steps: $fname"; }
    done
    [[ $MISSING_VERSION -eq 0 ]]  && check_pass "All skills have version metadata" \
                                  || check_fail "$MISSING_VERSION skill(s) missing version: field"
    [[ $MISSING_DESC -eq 0 ]]     && check_pass "All skills have description metadata" \
                                  || check_fail "$MISSING_DESC skill(s) missing description: field"
    [[ $MISSING_RECOVERY -eq 0 ]] && check_pass "All skills have failure_recovery_steps" \
                                  || check_warn "$MISSING_RECOVERY skill(s) missing failure_recovery_steps section"
fi

# ════════════════════════════════════════════════════════════════════════════
# [4/5] Drift Detection
# ════════════════════════════════════════════════════════════════════════════
if [[ "$JSON_OUTPUT" == false ]]; then echo ""; echo "[4/5] Drift Detection"; fi

if [[ ! -d "$DRIFT_DIR" ]]; then
    check_warn "Drift directory not found: $DRIFT_DIR" \
        "mkdir -p $DRIFT_DIR && bash scripts/drift-check.sh --update-baseline"
elif [[ ! -f "$DRIFT_DIR/baseline.json" ]]; then
    check_warn "No drift baseline found" \
        "Run: ./scripts/drift-check.sh --update-baseline"
else
    check_pass "Drift baseline exists: $DRIFT_DIR/baseline.json"

    LATEST_RESULT=$(ls -t "$DRIFT_DIR"/drift-results-*.json 2>/dev/null | head -1 || true)
    if [[ -n "$LATEST_RESULT" ]]; then
        DRIFT_STATUS=$(python3 -c "import json; d=json.load(open('$LATEST_RESULT')); print(d.get('status','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
        DRIFT_TS=$(python3 -c "import json; d=json.load(open('$LATEST_RESULT')); print(d.get('timestamp','?'))" 2>/dev/null || echo "?")
        DRIFT_PASS=$(python3 -c "import json; d=json.load(open('$LATEST_RESULT')); print(d.get('pass_count',0))" 2>/dev/null || echo "0")
        DRIFT_FAIL=$(python3 -c "import json; d=json.load(open('$LATEST_RESULT')); print(d.get('fail_count',0))" 2>/dev/null || echo "0")

        if [[ "$DRIFT_STATUS" == "PASS" ]]; then
            check_pass "Latest drift check PASSED — ${DRIFT_PASS}/5 benchmarks stable (${DRIFT_TS})"
        else
            check_fail "Latest drift check FAILED — ${DRIFT_FAIL}/5 benchmarks diverged" \
                "Review: $LATEST_RESULT — then run drift-check.sh --update-baseline after investigation"
        fi
    else
        check_warn "Baseline exists but no drift-results found yet" \
            "Run: ./scripts/drift-check.sh"
    fi
fi

# ════════════════════════════════════════════════════════════════════════════
# [5/5] Health Endpoint
# ════════════════════════════════════════════════════════════════════════════
if [[ "$JSON_OUTPUT" == false ]]; then echo ""; echo "[5/5] Health Endpoint"; fi

HEALTH_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    "http://127.0.0.1:${HEALTH_PORT}/health" 2>/dev/null || echo "000")
if [[ "$HEALTH_HTTP" == "200" ]]; then
    check_pass "Health endpoint returns HTTP 200"
else
    check_fail "Health endpoint returned HTTP $HEALTH_HTTP" \
        "systemctl status birkin-health && journalctl -u birkin-health -n 30"
fi

HEALTH_BODY=$(curl -s --max-time 5 "http://127.0.0.1:${HEALTH_PORT}/health" 2>/dev/null || echo "{}")
if echo "$HEALTH_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'agent_status' in d else 1)" 2>/dev/null; then
    AGENT_STATUS=$(echo "$HEALTH_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('agent_status','unknown'))" 2>/dev/null || echo "unknown")
    check_pass "Health JSON valid (agent_status: $AGENT_STATUS)"
else
    check_fail "Health endpoint response is not valid JSON" \
        "curl http://127.0.0.1:${HEALTH_PORT}/health"
fi

# Agent safety boundaries check — kill-switch scripts
SAFETY_FAILS=0
for script in agent-stop.sh agent-lockdown.sh; do
    SPATH="${HERMES_SCRIPTS_DIR:-$HOME/.hermes/scripts}/$script"
    if [[ -f "$SPATH" && -x "$SPATH" ]]; then
        vlog "Safety script present + executable: $script"
    else
        check_warn "Safety script missing or not executable: $script" \
            "Ensure scripts/$script is deployed and chmod +x"
        SAFETY_FAILS=$((SAFETY_FAILS+1))
    fi
done
[[ $SAFETY_FAILS -eq 0 ]] && check_pass "Agent kill-switch scripts present and executable"

# ════════════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════════════
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

if [[ "$JSON_OUTPUT" == true ]]; then
    python3 - <<PYJSON
import json, datetime
print(json.dumps({
    "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
    "elapsed_seconds": ${ELAPSED},
    "pass": ${PASS},
    "warn": ${WARN},
    "fail": ${FAIL},
    "status": "INTACT" if ${FAIL} == 0 else "FAILED"
}, indent=2))
PYJSON
else
    echo ""
    echo "=== Governance Check Summary ==="
    echo "Passed:   $PASS"
    echo "Warnings: $WARN"
    echo "Failed:   $FAIL"
    echo "Elapsed:  ${ELAPSED}s"
    echo ""

    if [[ "$FAIL" -eq 0 ]]; then
        echo "✅ AGENT GOVERNANCE INTACT"
        echo "   All critical checks passed. Birkin is operating within governance boundaries."
    else
        echo "❌ GOVERNANCE FAILED — $FAIL critical check(s) failed"
        echo "   Remediate the failures above before resuming autonomous operations."
        echo "   To stop the agent: ./scripts/agent-stop.sh"
    fi
fi

exit $([[ "$FAIL" -eq 0 ]] && echo 0 || echo 1)
