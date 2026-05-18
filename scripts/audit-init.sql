-- =============================================================================
-- audit-init.sql — Birkin audit log schema (hash-chained, append-only)
--
-- Two layers of defense:
--   1. SQLite triggers BLOCK any UPDATE or DELETE on audit_log
--   2. Every row carries SHA-256(prev_hash || canonical_payload) as row_hash;
--      a single mutated byte breaks the chain on the next verify-chain run
--
-- Rows are inserted via scripts/audit-append.py, which computes the chain link.
-- Genesis row has prev_hash = 64 zeros.
-- =============================================================================

CREATE TABLE IF NOT EXISTS audit_log (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp        INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    created_at       INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    modified_at      INTEGER,
    skill            TEXT    NOT NULL DEFAULT 'unknown',
    action_summary   TEXT,
    success          INTEGER NOT NULL DEFAULT 1 CHECK (success IN (0, 1)),
    tokens_consumed  INTEGER NOT NULL DEFAULT 0,
    cost_usd         REAL    NOT NULL DEFAULT 0.0,
    error_message    TEXT,
    session_id       TEXT,
    model_used       TEXT,
    prev_hash        TEXT    NOT NULL,
    row_hash         TEXT    NOT NULL UNIQUE
);

CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log(timestamp);
CREATE INDEX IF NOT EXISTS idx_audit_skill     ON audit_log(skill);
CREATE INDEX IF NOT EXISTS idx_audit_success   ON audit_log(success);

CREATE TRIGGER IF NOT EXISTS audit_log_no_update
BEFORE UPDATE ON audit_log
BEGIN
    SELECT RAISE(ABORT, 'audit_log is append-only: UPDATE forbidden');
END;

CREATE TRIGGER IF NOT EXISTS audit_log_no_delete
BEFORE DELETE ON audit_log
BEGIN
    SELECT RAISE(ABORT, 'audit_log is append-only: DELETE forbidden');
END;
