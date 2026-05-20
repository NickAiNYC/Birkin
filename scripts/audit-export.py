#!/usr/bin/env python3
"""
audit-export.py — Export audit_log to CSV or signed JSON for compliance.

Usage:
    ./audit-export.py --format csv --since 2026-04-01 --output report.csv
    ./audit-export.py --format json --signed
    ./audit-export.py --format json --since 2026-05-01 --output audit.json --signed

Options:
    --format  csv|json          Output format (default: csv)
    --since   YYYY-MM-DD        Only include entries on or after this date
    --until   YYYY-MM-DD        Only include entries before this date
    --output  PATH              Write to file instead of stdout
    --signed                    Embed chain tip in output for integrity verification
    --db      PATH              Path to audit.db (default: $HERMES_AUDIT_DB or ~/.hermes/audit.db)
"""
import argparse
import csv
import io
import json
import os
import sqlite3
import sys
import time
from datetime import datetime, timezone


def parse_date(s):
    """Parse YYYY-MM-DD to a UTC Unix timestamp (start of day)."""
    dt = datetime.strptime(s, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    return int(dt.timestamp())


def get_chain_tip(conn):
    row = conn.execute(
        "SELECT row_hash FROM audit_log ORDER BY id DESC LIMIT 1"
    ).fetchone()
    return row[0] if row else None


def fetch_rows(conn, since_ts=None, until_ts=None):
    clauses = []
    params = []
    if since_ts is not None:
        clauses.append("timestamp >= ?")
        params.append(since_ts)
    if until_ts is not None:
        clauses.append("timestamp < ?")
        params.append(until_ts)
    where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
    sql = f"""
        SELECT
            id,
            timestamp,
            skill,
            COALESCE(action_type, 'unknown') AS action_type,
            COALESCE(resource, '')           AS resource,
            action_summary,
            success,
            tokens_consumed,
            cost_usd,
            error_message,
            session_id,
            model_used,
            prev_hash,
            row_hash,
            COALESCE(parameters_hash, '')    AS parameters_hash
        FROM audit_log
        {where}
        ORDER BY id ASC
    """
    return conn.execute(sql, params).fetchall()


def export_csv(rows, out):
    writer = csv.writer(out)
    writer.writerow([
        "id", "timestamp", "timestamp_iso", "skill", "action_type",
        "resource", "action_summary", "success", "tokens_consumed",
        "cost_usd", "error_message", "session_id", "model_used",
        "row_hash",
    ])
    for r in rows:
        ts_iso = datetime.fromtimestamp(r[1], tz=timezone.utc).isoformat()
        writer.writerow([
            r[0], r[1], ts_iso, r[2], r[3], r[4], r[5],
            r[6], r[7], r[8], r[9], r[10], r[11], r[13],
        ])


def export_json(rows, chain_tip, signed, out):
    events = []
    for r in rows:
        ts_iso = datetime.fromtimestamp(r[1], tz=timezone.utc).isoformat()
        events.append({
            "id":               r[0],
            "timestamp":        r[1],
            "timestamp_iso":    ts_iso,
            "skill":            r[2],
            "action_type":      r[3],
            "resource":         r[4],
            "action_summary":   r[5],
            "success":          bool(r[6]),
            "tokens_consumed":  r[7],
            "cost_usd":         r[8],
            "error_message":    r[9],
            "session_id":       r[10],
            "model_used":       r[11],
            "row_hash":         r[13],
        })
    export_ts = datetime.now(tz=timezone.utc).isoformat()
    payload = {
        "export_timestamp": export_ts,
        "event_count":      len(events),
        "events":           events,
    }
    if signed:
        payload["chain_tip"] = chain_tip
    json.dump(payload, out, indent=2)
    out.write("\n")


def main():
    p = argparse.ArgumentParser(description="Export Birkin audit log")
    p.add_argument("--db", default=os.environ.get(
        "HERMES_AUDIT_DB", os.path.expanduser("~/.hermes/audit.db")))
    p.add_argument("--format", choices=["csv", "json"], default="csv")
    p.add_argument("--since", default=None, help="YYYY-MM-DD")
    p.add_argument("--until", default=None, help="YYYY-MM-DD")
    p.add_argument("--output", default=None, help="Output file path (default: stdout)")
    p.add_argument("--signed", action="store_true",
                   help="Embed chain tip for integrity verification (JSON only)")
    args = p.parse_args()

    if not os.path.exists(args.db):
        print(f"ERROR: audit db not found at {args.db}", file=sys.stderr)
        return 2

    since_ts = parse_date(args.since) if args.since else None
    until_ts = parse_date(args.until) if args.until else None

    conn = sqlite3.connect(args.db)
    try:
        rows = fetch_rows(conn, since_ts, until_ts)
        chain_tip = get_chain_tip(conn) if args.signed else None
    finally:
        conn.close()

    if args.output:
        out_file = open(args.output, "w", newline="" if args.format == "csv" else None)
    else:
        out_file = sys.stdout

    try:
        if args.format == "csv":
            export_csv(rows, out_file)
        else:
            export_json(rows, chain_tip, args.signed, out_file)
    finally:
        if args.output:
            out_file.close()

    if args.output:
        print(f"Exported {len(rows)} events → {args.output}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
