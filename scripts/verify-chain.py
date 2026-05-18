#!/usr/bin/env python3
"""
verify-chain.py — Walk the audit_log hash chain and verify every link.

Reads rows in id order. For each row, recomputes
    SHA-256(prev_hash || canonical_payload)
and compares to the stored row_hash. Also checks that each row's
prev_hash equals the previous row's row_hash (chain continuity).

Exit codes:
    0 — chain intact
    1 — chain broken (tamper detected)
    2 — db missing / unreadable

Usage:
    verify-chain.py [--db PATH] [--json]
"""
import argparse
import hashlib
import json
import os
import sqlite3
import sys
import time

GENESIS_PREV = "0" * 64
FIELDS = [
    "timestamp", "skill", "action_summary", "success",
    "tokens_consumed", "cost_usd", "error_message",
    "session_id", "model_used",
]


def canonical(row):
    return "\t".join("" if row[f] is None else str(row[f]) for f in FIELDS)


def compute(prev_hash, row):
    return hashlib.sha256(
        (prev_hash + "|" + canonical(row)).encode("utf-8")
    ).hexdigest()


def verify(db_path):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    rows = conn.execute("SELECT * FROM audit_log ORDER BY id ASC").fetchall()
    conn.close()

    expected_prev = GENESIS_PREV
    for row in rows:
        if row["prev_hash"] != expected_prev:
            return False, row["id"], "chain_break", \
                f"prev_hash mismatch (expected {expected_prev[:12]}..., got {row['prev_hash'][:12]}...)"
        recomputed = compute(expected_prev, row)
        if recomputed != row["row_hash"]:
            return False, row["id"], "row_tampered", \
                f"row_hash mismatch (expected {recomputed[:12]}..., got {row['row_hash'][:12]}...)"
        expected_prev = row["row_hash"]

    return True, len(rows), None, None


def main():
    p = argparse.ArgumentParser(description="Verify audit_log hash chain")
    p.add_argument("--db", default=os.environ.get(
        "HERMES_AUDIT_DB", os.path.expanduser("~/.hermes/audit.db")))
    p.add_argument("--json", action="store_true")
    args = p.parse_args()

    if not os.path.exists(args.db):
        msg = f"audit db not found: {args.db}"
        if args.json:
            print(json.dumps({"ok": False, "error": msg}))
        else:
            print(f"ERROR: {msg}", file=sys.stderr)
        return 2

    t0 = time.time()
    ok, marker, reason, detail = verify(args.db)
    elapsed_ms = int((time.time() - t0) * 1000)

    if args.json:
        print(json.dumps({
            "ok": ok,
            "rows_verified": marker if ok else None,
            "broken_at_row": None if ok else marker,
            "reason": reason,
            "detail": detail,
            "elapsed_ms": elapsed_ms,
        }))
    else:
        if ok:
            print(f"✅ CHAIN INTACT — {marker} rows verified in {elapsed_ms}ms")
        else:
            print(f"❌ CHAIN BROKEN at row {marker} ({reason})")
            print(f"   {detail}")
            print(f"   Verified in {elapsed_ms}ms")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
