"""
approval_queue.py — SQLite-backed queue for HITL pending approvals.

Each HIGH-risk action is held here until a human approves/denies via Telegram,
or until approval_timeout_seconds elapses (at which point it auto-denies).
"""
import sqlite3
import time
import uuid
from dataclasses import dataclass
from enum import Enum
from typing import Optional


class ApprovalStatus(str, Enum):
    PENDING  = "pending"
    APPROVED = "approved"
    DENIED   = "denied"
    EXPIRED  = "expired"


@dataclass
class PendingAction:
    action_id:     str
    timestamp:     int
    risk_level:    str
    skill:         str
    action_summary: str
    status:        ApprovalStatus
    decided_at:    Optional[int]


SCHEMA = """
CREATE TABLE IF NOT EXISTS approval_queue (
    action_id       TEXT PRIMARY KEY,
    timestamp       INTEGER NOT NULL,
    risk_level      TEXT NOT NULL,
    skill           TEXT NOT NULL DEFAULT 'unknown',
    action_summary  TEXT NOT NULL DEFAULT '',
    request_json    TEXT NOT NULL DEFAULT '{}',
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK(status IN ('pending','approved','denied','expired')),
    decided_at      INTEGER,
    telegram_msg_id INTEGER
);
CREATE INDEX IF NOT EXISTS idx_aq_status    ON approval_queue(status);
CREATE INDEX IF NOT EXISTS idx_aq_timestamp ON approval_queue(timestamp);
"""


class ApprovalQueue:
    def __init__(self, db_path: str, timeout_seconds: int = 300):
        self._db = db_path
        self._timeout = timeout_seconds
        self._init_db()

    def _connect(self):
        conn = sqlite3.connect(self._db)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self):
        conn = self._connect()
        conn.executescript(SCHEMA)
        conn.commit()
        conn.close()

    def enqueue(self, skill: str, action_summary: str, risk_level: str,
                request_json: str = "{}") -> str:
        action_id = str(uuid.uuid4())
        ts = int(time.time())
        conn = self._connect()
        conn.execute(
            """INSERT INTO approval_queue
               (action_id, timestamp, risk_level, skill, action_summary, request_json)
               VALUES (?,?,?,?,?,?)""",
            (action_id, ts, risk_level, skill, action_summary, request_json),
        )
        conn.commit()
        conn.close()
        return action_id

    def set_telegram_msg_id(self, action_id: str, msg_id: int):
        conn = self._connect()
        conn.execute(
            "UPDATE approval_queue SET telegram_msg_id=? WHERE action_id=?",
            (msg_id, action_id),
        )
        conn.commit()
        conn.close()

    def decide(self, action_id: str, decision: ApprovalStatus) -> bool:
        """Record approve or deny. Returns True if action was still pending."""
        conn = self._connect()
        row = conn.execute(
            "SELECT status FROM approval_queue WHERE action_id=?", (action_id,)
        ).fetchone()
        if not row or row["status"] != ApprovalStatus.PENDING:
            conn.close()
            return False
        conn.execute(
            "UPDATE approval_queue SET status=?, decided_at=? WHERE action_id=?",
            (decision.value, int(time.time()), action_id),
        )
        conn.commit()
        conn.close()
        return True

    def poll_decision(self, action_id: str) -> ApprovalStatus:
        """Block-poll until a decision is made or timeout expires."""
        deadline = time.time() + self._timeout
        while time.time() < deadline:
            conn = self._connect()
            row = conn.execute(
                "SELECT status FROM approval_queue WHERE action_id=?", (action_id,)
            ).fetchone()
            conn.close()
            if not row:
                return ApprovalStatus.DENIED
            status = ApprovalStatus(row["status"])
            if status != ApprovalStatus.PENDING:
                return status
            time.sleep(1)
        # Timed out — mark as expired
        self._expire(action_id)
        return ApprovalStatus.EXPIRED

    def _expire(self, action_id: str):
        conn = self._connect()
        conn.execute(
            "UPDATE approval_queue SET status='expired', decided_at=? "
            "WHERE action_id=? AND status='pending'",
            (int(time.time()), action_id),
        )
        conn.commit()
        conn.close()

    def expire_stale(self):
        """Mark all pending entries past their timeout as expired."""
        cutoff = int(time.time()) - self._timeout
        conn = self._connect()
        conn.execute(
            "UPDATE approval_queue SET status='expired', decided_at=? "
            "WHERE status='pending' AND timestamp < ?",
            (int(time.time()), cutoff),
        )
        conn.commit()
        conn.close()

    def get(self, action_id: str) -> Optional[dict]:
        conn = self._connect()
        row = conn.execute(
            "SELECT * FROM approval_queue WHERE action_id=?", (action_id,)
        ).fetchone()
        conn.close()
        return dict(row) if row else None
