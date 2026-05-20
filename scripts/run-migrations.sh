#!/usr/bin/env bash
# =============================================================================
# run-migrations.sh — Apply pending SQL migrations to the audit database
#
# Tracks applied migrations in a schema_migrations table so each script
# runs exactly once. Safe to call on every startup.
#
# Usage: ./scripts/run-migrations.sh [--db PATH]
# =============================================================================
set -euo pipefail

AUDIT_DB="${HERMES_AUDIT_DB:-$HOME/.hermes/audit.db}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="$(cd "$SCRIPT_DIR/../migrations" && pwd)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db) AUDIT_DB="$2"; shift 2 ;;
        *)    echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ ! -f "$AUDIT_DB" ]]; then
    echo "INFO: audit db not found at $AUDIT_DB — skipping migrations"
    exit 0
fi

# Ensure migrations tracking table exists
sqlite3 "$AUDIT_DB" "
CREATE TABLE IF NOT EXISTS schema_migrations (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL UNIQUE,
    applied_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
);
"

APPLIED=0
SKIPPED=0

for sql_file in $(ls "$MIGRATIONS_DIR"/*.sql 2>/dev/null | sort); do
    migration_name=$(basename "$sql_file")

    already=$(sqlite3 "$AUDIT_DB" \
        "SELECT COUNT(*) FROM schema_migrations WHERE name='$migration_name';" 2>/dev/null || echo "0")

    if [[ "$already" -gt 0 ]]; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    echo "Applying migration: $migration_name"
    # Run migration in a transaction; record it only on success
    sqlite3 "$AUDIT_DB" "
BEGIN;
$(cat "$sql_file")
INSERT INTO schema_migrations (name) VALUES ('$migration_name');
COMMIT;
" 2>&1 && {
        echo "  ✅ Applied: $migration_name"
        APPLIED=$((APPLIED + 1))
    } || {
        echo "  ❌ Failed: $migration_name — rolling back" >&2
        sqlite3 "$AUDIT_DB" "ROLLBACK;" 2>/dev/null || true
        exit 1
    }
done

echo "Migrations: $APPLIED applied, $SKIPPED already current"
