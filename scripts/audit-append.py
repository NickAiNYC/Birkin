#!/usr/bin/env python3
"""
audit-append.py — Append a hash-chained row to the Birkin audit log.

Usage (basic):
    audit-append.py --skill daily-brief --action "sent morning summary" \
        --success 1 --tokens 1842 --cost 0.012 [--db PATH]

Usage (structured, with new fields):
    audit-append.py --skill weather \
        --action "external_api_call" \
        --action-type external_api_call \
        --resource api.open-meteo.com \
        --params '{"lat":52.52,"lon":13.41}' \
        --summary "Fetching Berlin weather"

New fields (action_type, resource, parameters_hash) are stored in the DB but
are NOT part of the hash-chain canonical payload — existing chains continue to
verify correctly after the 002 migration is applied.
"""
import argparse
import hashlib
import json
import os
import sqlite3
import sys
import time
import uuid

GENESIS_PREV = "0" * 64

# These fields form the canonical payload for hash computation.
# Do NOT add new fields here — that would break existing chains.
FIELDS = [
    "timestamp", "skill", "action_summary", "success",
    "tokens_consumed", "cost_usd", "error_message",
    "session_id", "model_used",
]


def canonical(row):
    return "\t".join("" if row[f] is None else str(row[f]) for f in FIELDS)


def compute_row_hash(prev_hash, row):
    payload = prev_hash + "|" + canonical(row)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def get_last_hash(conn):
    cur = conn.execute("SELECT row_hash FROM audit_log ORDER BY id DESC LIMIT 1")
    row = cur.fetchone()
    return row[0] if row else GENESIS_PREV


def hash_params(params_json):
    """SHA-256 of the canonical JSON string (sorted keys)."""
    if not params_json:
        return ""
    try:
        parsed = json.loads(params_json)
        canonical_json = json.dumps(parsed, sort_keys=True, separators=(",", ":"))
    except (json.JSONDecodeError, TypeError):
        canonical_json = params_json
    return hashlib.sha256(canonical_json.encode("utf-8")).hexdigest()


def _has_column(conn, table, column):
    rows = conn.execute(f"PRAGMA table_info({table})").fetchall()
    return any(r[1] == column for r in rows)


def main():
    p = argparse.ArgumentParser(description="Append a chained row to audit_log")
    p.add_argument("--db", default=os.environ.get(
        "HERMES_AUDIT_DB", os.path.expanduser("~/.hermes/audit.db")))
    p.add_argument("--skill", required=True)
    # --action is the legacy short-form summary; --summary is the new long-form alias
    p.add_argument("--action", default=None,
                   help="Action summary (legacy positional; use --summary for new code)")
    p.add_argument("--summary", default=None,
                   help="Action summary (alias for --action)")
    p.add_argument("--action-type", dest="action_type", default="unknown",
                   help="Structured action type (e.g. external_api_call, file_write)")
    p.add_argument("--resource", default="",
                   help="Resource accessed (URL, file path, service name)")
    p.add_argument("--params", default=None,
                   help="JSON-encoded parameters (will be SHA-256 hashed for storage)")
    p.add_argument("--success", type=int, choices=[0, 1], default=1)
    p.add_argument("--tokens", type=int, default=0)
    p.add_argument("--cost", type=float, default=0.0)
    p.add_argument("--error", default=None)
    p.add_argument("--session", default=None)
    p.add_argument("--model", default=None)
    args = p.parse_args()

    action_summary = args.summary or args.action
    if not action_summary:
        p.error("one of --action or --summary is required")

    if not os.path.exists(args.db):
        print(f"ERROR: audit db not found at {args.db}", file=sys.stderr)
        print("Initialize with: sqlite3 $HERMES_AUDIT_DB < scripts/audit-init.sql",
              file=sys.stderr)
        return 2

    params_hash = hash_params(args.params)

    row = {
        "timestamp":      int(time.time()),
        "skill":          args.skill,
        "action_summary": action_summary,
        "success":        args.success,
        "tokens_consumed": args.tokens,
        "cost_usd":       args.cost,
        "error_message":  args.error,
        "session_id":     args.session or str(uuid.uuid4()),
        "model_used":     args.model,
    }

    conn = sqlite3.connect(args.db)
    try:
        conn.execute("BEGIN IMMEDIATE")
        prev = get_last_hash(conn)
        row_hash = compute_row_hash(prev, row)

        # Detect whether the 002 migration columns are present
        has_extended = _has_column(conn, "audit_log", "action_type")

        if has_extended:
            conn.execute(
                """INSERT INTO audit_log
                   (timestamp, skill, action_summary, success, tokens_consumed,
                    cost_usd, error_message, session_id, model_used,
                    action_type, resource, parameters_hash,
                    prev_hash, row_hash)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (row["timestamp"], row["skill"], row["action_summary"],
                 row["success"], row["tokens_consumed"], row["cost_usd"],
                 row["error_message"], row["session_id"], row["model_used"],
                 args.action_type, args.resource, params_hash,
                 prev, row_hash),
            )
        else:
            conn.execute(
                """INSERT INTO audit_log
                   (timestamp, skill, action_summary, success, tokens_consumed,
                    cost_usd, error_message, session_id, model_used,
                    prev_hash, row_hash)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
                (row["timestamp"], row["skill"], row["action_summary"],
                 row["success"], row["tokens_consumed"], row["cost_usd"],
                 row["error_message"], row["session_id"], row["model_used"],
                 prev, row_hash),
            )
        conn.commit()
        print(row_hash)
        return 0
    except sqlite3.IntegrityError as e:
        conn.rollback()
        print(f"ERROR: append failed (integrity): {e}", file=sys.stderr)
        return 1
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
