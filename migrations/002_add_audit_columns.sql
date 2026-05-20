-- =============================================================================
-- 002_add_audit_columns.sql — Add structured audit fields to audit_log
--
-- Applied automatically by scripts/run-migrations.sh on startup.
-- Backward-compatible: all new columns have sensible defaults and are NOT
-- included in the hash-chain canonical payload, so existing chains continue
-- to verify correctly.
-- =============================================================================

ALTER TABLE audit_log ADD COLUMN action_type      TEXT NOT NULL DEFAULT 'unknown';
ALTER TABLE audit_log ADD COLUMN resource         TEXT NOT NULL DEFAULT '';
ALTER TABLE audit_log ADD COLUMN parameters_hash  TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_audit_action_type ON audit_log(action_type);
CREATE INDEX IF NOT EXISTS idx_audit_resource     ON audit_log(resource);
