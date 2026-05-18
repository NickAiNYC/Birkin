#!/usr/bin/env python3
"""
audit-append.py — Append a hash-chained row to the Birkin audit log.

Usage:
    audit-append.py --skill daily-brief --action "sent morning summary" \
        --success 1 --tokens 1842 --cost 0.012 [--db PATH]

Computes row_hash = SHA-256(prev_hash || canonical_payload) where
canonical_payload is a tab-joined, fixed-order serialization of the row.
The previous row's row_hash becomes this row's prev_hash, forming the chain.
"""
import argparse
import hashlib
import os
import sqlite3
import sys
import time
import uuid

GENESIS_PREV = "0" * 64

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


def main():
    p = argparse.ArgumentParser(description="Append a chained row to audit_log")
    p.add_argument("--db", default=os.environ.get(
        "HERMES_AUDIT_DB", os.path.expanduser("~/.hermes/audit.db")))
    p.add_argument("--skill", required=True)
    p.add_argument("--action", required=True)
    p.add_argument("--success", type=int, choices=[0, 1], default=1)
    p.add_argument("--tokens", type=int, default=0)
    p.add_argument("--cost", type=float, default=0.0)
    p.add_argument("--error", default=None)
    p.add_argument("--session", default=None)
    p.add_argument("--model", default=None)
    args = p.parse_args()

    if not os.path.exists(args.db):
        print(f"ERROR: audit db not found at {args.db}", file=sys.stderr)
        print("Initialize with: sqlite3 $HERMES_AUDIT_DB < scripts/audit-init.sql",
              file=sys.stderr)
        return 2

    row = {
        "timestamp": int(time.time()),
        "skill": args.skill,
        "action_summary": args.action,
        "success": args.success,
        "tokens_consumed": args.tokens,
        "cost_usd": args.cost,
        "error_message": args.error,
        "session_id": args.session or str(uuid.uuid4()),
        "model_used": args.model,
    }

    conn = sqlite3.connect(args.db)
    try:
        conn.execute("BEGIN IMMEDIATE")
        prev = get_last_hash(conn)
        row_hash = compute_row_hash(prev, row)
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
