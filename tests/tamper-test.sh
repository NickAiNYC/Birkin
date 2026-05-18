#!/usr/bin/env bash
# =============================================================================
# tamper-test.sh — Prove the audit log chain detects tampering.
#
# What this does:
#   1. Creates a fresh sandbox audit.db in a temp dir
#   2. Appends 5 chained rows via scripts/audit-append.py
#   3. Runs scripts/verify-chain.py — expects PASS
#   4. Drops the append-only triggers (simulating an attacker with file access)
#   5. Mutates a single byte in row 3's action_summary
#   6. Re-runs verify-chain.py — expects FAIL at row 3
#   7. Cleans up
#
# Exit 0 = tamper was detected (governance works).
# Exit 1 = tamper went undetected (governance broken — fix immediately).
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$(mktemp -d)"
DB="$SANDBOX/audit.db"
trap 'rm -rf "$SANDBOX"' EXIT

echo "🧪 Birkin tamper-detection test"
echo "   sandbox: $SANDBOX"
echo ""

# ── Step 1: init schema ──────────────────────────────────────────────────────
sqlite3 "$DB" < "$REPO_ROOT/scripts/audit-init.sql"
echo "[1/6] ✅ schema initialized (table + triggers)"

# ── Step 2: append 5 rows ────────────────────────────────────────────────────
export HERMES_AUDIT_DB="$DB"
for i in 1 2 3 4 5; do
    python3 "$REPO_ROOT/scripts/audit-append.py" \
        --skill "daily-brief" \
        --action "row $i: morning summary delivered" \
        --tokens "$((i * 100))" \
        --cost "0.0$i" > /dev/null
done
echo "[2/6] ✅ appended 5 hash-chained rows"

# ── Step 3: verify clean chain ───────────────────────────────────────────────
if ! python3 "$REPO_ROOT/scripts/verify-chain.py" --db "$DB" > /dev/null; then
    echo "[3/6] ❌ clean chain failed verification — bug in append/verify"
    exit 1
fi
echo "[3/6] ✅ clean chain verifies PASS"

# ── Step 4: confirm triggers actually block UPDATE in production state ───────
if sqlite3 "$DB" "UPDATE audit_log SET action_summary='hacked' WHERE id=3;" 2>/dev/null; then
    echo "[4/6] ❌ trigger did NOT block UPDATE — append-only enforcement broken"
    exit 1
fi
echo "[4/6] ✅ trigger blocks UPDATE (append-only enforced at DB layer)"

# ── Step 5: simulate attacker who drops triggers, then mutates row 3 ─────────
sqlite3 "$DB" <<'SQL'
DROP TRIGGER IF EXISTS audit_log_no_update;
DROP TRIGGER IF EXISTS audit_log_no_delete;
UPDATE audit_log SET action_summary = 'silently rewritten' WHERE id = 3;
SQL
echo "[5/6] 🔓 simulated attacker: dropped triggers, rewrote row 3"

# ── Step 6: verify chain — must FAIL ────────────────────────────────────────
if python3 "$REPO_ROOT/scripts/verify-chain.py" --db "$DB" > "$SANDBOX/verify.out" 2>&1; then
    echo "[6/6] ❌ tamper went UNDETECTED — hash chain broken"
    cat "$SANDBOX/verify.out"
    exit 1
fi

echo "[6/6] ✅ tamper DETECTED by hash chain:"
sed 's/^/       /' "$SANDBOX/verify.out"
echo ""
echo "🛡️  PASS — Birkin's audit chain catches mutation even when triggers are bypassed."
