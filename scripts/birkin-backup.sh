#!/usr/bin/env bash
# birkin-backup.sh — Back up Birkin data to iCloud Drive
#
# What gets backed up:
#   audit.db    — hash-chained audit log (from birkin-health container volume)
#   drift/      — weekly drift check results
#   skills/     — your skill definitions
#   .env        — runtime config (credentials excluded from git)
#
# Schedule with crontab:
#   crontab -e
#   0 2 * * * /path/to/birkin/scripts/birkin-backup.sh >> /tmp/birkin-backup.log 2>&1
#
# Restore:
#   tar xzf ~/Library/Mobile\ Documents/com~apple~CloudDocs/BirkinBackups/birkin-YYYYMMDD-HHMMSS.tar.gz
#   docker cp audit.db birkin-health:/data/audit.db
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIRKIN_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/BirkinBackups"
CONTAINER="${HEALTH_CONTAINER:-birkin-health}"
KEEP_DAYS="${KEEP_DAYS:-30}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC}  $*"; }
fail() { echo -e "${RED}✗${NC}  $*" >&2; }
warn() { echo -e "${YELLOW}!${NC}  $*"; }

echo "Birkin backup — $(date '+%Y-%m-%d %H:%M:%S')"

# ── Preflight ─────────────────────────────────────────────────────────────────
if [[ ! -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ]]; then
    fail "iCloud Drive not found. Is iCloud enabled in System Settings?"
    fail "Alternative: set BACKUP_DIR=/your/path before running."
    exit 1
fi

if ! command -v docker &>/dev/null; then
    fail "docker not found — is Docker Desktop running?"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

# ── Extract audit.db from Docker volume ───────────────────────────────────────
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

AUDIT_DB="$TMP_DIR/audit.db"
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    docker cp "${CONTAINER}:/data/audit.db" "$AUDIT_DB" 2>/dev/null && ok "audit.db extracted from ${CONTAINER}" || warn "audit.db not found in container (no runs yet?)"
else
    warn "Container ${CONTAINER} not running — skipping audit.db (stack may be stopped)"
fi

# Drift results (also inside the volume)
DRIFT_DIR="$TMP_DIR/drift"
mkdir -p "$DRIFT_DIR"
docker cp "${CONTAINER}:/data/drift/." "$DRIFT_DIR/" 2>/dev/null && ok "drift results extracted" || true

# ── Build archive ─────────────────────────────────────────────────────────────
STAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE="$BACKUP_DIR/birkin-$STAMP.tar.gz"

# Files from the repo dir (not in Docker volumes)
SOURCES=()
[[ -f "$AUDIT_DB" ]] && SOURCES+=("$AUDIT_DB")
[[ -d "$BIRKIN_DIR/skills" ]]  && SOURCES+=("$BIRKIN_DIR/skills")
[[ -f "$BIRKIN_DIR/.env" ]]    && SOURCES+=("$BIRKIN_DIR/.env")
[[ -d "$DRIFT_DIR" ]] && find "$DRIFT_DIR" -name "*.json" -q 2>/dev/null && SOURCES+=("$DRIFT_DIR")

if [[ ${#SOURCES[@]} -eq 0 ]]; then
    warn "Nothing to back up yet — run some skills first."
    exit 0
fi

tar czf "$ARCHIVE" "${SOURCES[@]}" 2>/dev/null
BYTES=$(du -sh "$ARCHIVE" | cut -f1)
ok "Archive: $ARCHIVE ($BYTES)"

# ── Rotate old backups (keep last N days) ─────────────────────────────────────
DELETED=$(find "$BACKUP_DIR" -name "birkin-*.tar.gz" -mtime "+${KEEP_DAYS}" -print -delete 2>/dev/null | wc -l | tr -d ' ')
[[ "$DELETED" -gt 0 ]] && ok "Rotated ${DELETED} backup(s) older than ${KEEP_DAYS} days"

# ── Summary ───────────────────────────────────────────────────────────────────
TOTAL=$(find "$BACKUP_DIR" -name "birkin-*.tar.gz" | wc -l | tr -d ' ')
echo ""
echo "  Backed up to iCloud: $ARCHIVE"
echo "  Total backups kept:  $TOTAL"
