#!/usr/bin/env python3
"""
main.py — Birkin HITL Proxy

Listens on :8687. Sits between nginx and Hermes.
Every /v1/ request is risk-classified and routed:

  LOW    → forward immediately, log as auto_approved
  MEDIUM → forward immediately, send async Telegram alert, log as auto_approved_with_alert
  HIGH   → hold, send Telegram message with Approve/Deny buttons,
            wait for callback or timeout, then allow/deny, log decision

All decisions are logged via audit-append.py with action_type='hitl_decision'.
"""
import json
import logging
import os
import subprocess
import sys
import threading
from typing import Optional

import requests
import yaml
from flask import Flask, Response, request, stream_with_context

from approval_queue import ApprovalQueue, ApprovalStatus
from risk_classifier import RiskClassifier, RiskLevel
from telegram_webhook import TelegramClient, parse_callback

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    level=logging.INFO,
)
log = logging.getLogger("hitl-proxy")

# ── Config ────────────────────────────────────────────────────────────────────
CONFIG_PATH  = os.environ.get("HITL_CONFIG",     "/app/config.yml")
AUDIT_DB     = os.environ.get("HERMES_AUDIT_DB", os.path.expanduser("~/.hermes/audit.db"))
HITL_DB      = os.environ.get("HITL_DB",         "/data/hitl.db")
HITL_ENABLED = os.environ.get("HITL_ENABLED",    "true").lower() == "true"
HITL_TIMEOUT = int(os.environ.get("HITL_TIMEOUT_SECONDS", "300"))
HITL_THRESHOLD = os.environ.get("HITL_RISK_THRESHOLD", "HIGH")
HITL_DEFAULT_ACTION = os.environ.get("HITL_DEFAULT_ACTION", "deny")

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
CHAT_ID   = os.environ.get("TELEGRAM_CHAT_ID",   "")

_cfg: dict = {}
if os.path.exists(CONFIG_PATH):
    with open(CONFIG_PATH) as f:
        raw = f.read()
    # Expand ${ENV_VAR} references
    import re
    raw = re.sub(r'\$\{(\w+)\}', lambda m: os.environ.get(m.group(1), ""), raw)
    _cfg = yaml.safe_load(raw) or {}

HERMES_URL = _cfg.get("hermes_url", os.environ.get("HERMES_URL", "http://host.docker.internal:8686"))
AUTO_APPROVE_SKILLS = set(_cfg.get("auto_approve_skills", ["daily-brief", "health-check"]))

if _cfg.get("telegram", {}).get("bot_token"):
    BOT_TOKEN = _cfg["telegram"]["bot_token"] or BOT_TOKEN
if _cfg.get("telegram", {}).get("chat_id"):
    CHAT_ID = _cfg["telegram"]["chat_id"] or CHAT_ID

# ── Services ──────────────────────────────────────────────────────────────────
classifier = RiskClassifier(CONFIG_PATH)
queue      = ApprovalQueue(HITL_DB, timeout_seconds=HITL_TIMEOUT)
telegram   = TelegramClient(BOT_TOKEN, CHAT_ID) if BOT_TOKEN and CHAT_ID else None

# ── Flask app ─────────────────────────────────────────────────────────────────
app = Flask(__name__)


# ── Audit helper ──────────────────────────────────────────────────────────────
_AUDIT_SCRIPT = os.environ.get("AUDIT_APPEND_SCRIPT", "/app/scripts/audit-append.py")


def _audit(skill: str, summary: str, action_type: str = "hitl_decision",
           resource: str = "", success: int = 1, params: Optional[dict] = None):
    if not os.path.exists(_AUDIT_SCRIPT):
        log.debug("audit-append.py not found at %s — skipping audit write", _AUDIT_SCRIPT)
        return
    cmd = [
        sys.executable, _AUDIT_SCRIPT,
        "--db",          AUDIT_DB,
        "--skill",       skill or "unknown",
        "--action",      summary,
        "--action-type", action_type,
        "--resource",    resource,
        "--success",     str(success),
    ]
    if params:
        cmd += ["--params", json.dumps(params)]
    try:
        subprocess.run(cmd, timeout=5, capture_output=True)
    except Exception as exc:
        log.warning("audit-append failed: %s", exc)


# ── Proxy helper ──────────────────────────────────────────────────────────────
def _forward(path: str) -> Response:
    target = HERMES_URL.rstrip("/") + "/" + path.lstrip("/")
    headers = {k: v for k, v in request.headers
               if k.lower() not in ("host", "content-length")}
    try:
        resp = requests.request(
            method=request.method,
            url=target,
            headers=headers,
            data=request.get_data(),
            params=request.args,
            stream=True,
            timeout=(10, 300),
        )
        excluded = {"content-encoding", "transfer-encoding", "content-length"}
        resp_headers = [(k, v) for k, v in resp.headers.items()
                        if k.lower() not in excluded]
        return Response(
            stream_with_context(resp.iter_content(chunk_size=4096)),
            status=resp.status_code,
            headers=resp_headers,
            content_type=resp.headers.get("Content-Type", "application/json"),
        )
    except requests.exceptions.ConnectionError:
        return Response(
            json.dumps({"error": "Hermes unreachable"}),
            status=502, content_type="application/json",
        )
    except requests.exceptions.Timeout:
        return Response(
            json.dumps({"error": "Hermes request timed out"}),
            status=504, content_type="application/json",
        )


def _skill_from_body(body: dict) -> str:
    """Best-effort skill name extraction from request metadata."""
    # Check X-Birkin-Skill header first
    skill = request.headers.get("X-Birkin-Skill", "")
    if skill:
        return skill
    # Fall back to model name as a proxy
    return body.get("model", "unknown")


# ── Main request handler ───────────────────────────────────────────────────────
@app.route("/v1/<path:path>", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
def proxy_v1(path: str) -> Response:
    if not HITL_ENABLED:
        return _forward(path)

    body = {}
    try:
        body = request.get_json(force=True, silent=True) or {}
    except Exception:
        pass

    skill  = _skill_from_body(body)
    result = classifier.classify(body)
    level  = result.level

    # Auto-approve configured skills regardless of risk
    if skill in AUTO_APPROVE_SKILLS:
        _audit(skill, f"auto_approved (skill in allowlist): {path}",
               action_type="hitl_decision", resource=path)
        return _forward(path)

    if level == RiskLevel.LOW:
        _audit(skill, f"auto_approved (LOW risk): {path}",
               action_type="hitl_decision", resource=path)
        return _forward(path)

    if level == RiskLevel.MEDIUM:
        _audit(skill, f"auto_approved_with_alert (MEDIUM risk): {path}",
               action_type="hitl_decision", resource=path)
        if telegram:
            threading.Thread(
                target=telegram.send_alert,
                args=(skill, result.matched_text or path, "MEDIUM", True),
                daemon=True,
            ).start()
        return _forward(path)

    # HIGH — hold for approval
    summary = result.matched_text or f"HIGH-risk request to {path}"
    action_id = queue.enqueue(
        skill=skill,
        action_summary=summary,
        risk_level="HIGH",
        request_json=json.dumps({"path": path, "rule": result.matched_rule}),
    )
    log.info("HIGH-risk action queued: %s (id=%s)", summary[:80], action_id[:8])

    msg_id = None
    if telegram:
        msg_id = telegram.send_approval_request(action_id, skill, summary, "HIGH")
        if msg_id:
            queue.set_telegram_msg_id(action_id, msg_id)

    decision = queue.poll_decision(action_id)

    approved = decision == ApprovalStatus.APPROVED
    _audit(
        skill,
        f"hitl_decision={decision.value}: {summary[:200]}",
        action_type="hitl_decision",
        resource=path,
        success=1 if approved else 0,
        params={"action_id": action_id, "decision": decision.value},
    )

    if approved:
        log.info("APPROVED: %s", action_id[:8])
        return _forward(path)

    log.info("DENIED (%s): %s", decision.value, action_id[:8])
    return Response(
        json.dumps({
            "error": "Request denied by HITL governance",
            "action_id": action_id,
            "decision": decision.value,
        }),
        status=403,
        content_type="application/json",
    )


# ── Telegram webhook endpoint ─────────────────────────────────────────────────
@app.route("/telegram/callback", methods=["POST"])
def telegram_callback() -> Response:
    update = request.get_json(force=True, silent=True) or {}
    cq = update.get("callback_query")
    if not cq:
        return Response("ok", 200)

    callback_data = cq.get("data", "")
    decision_str, action_id = parse_callback(callback_data)

    if not action_id:
        return Response("ok", 200)

    status = (ApprovalStatus.APPROVED if decision_str == "approve"
              else ApprovalStatus.DENIED)
    changed = queue.decide(action_id, status)

    if telegram:
        text = f"{'✅ Approved' if status == ApprovalStatus.APPROVED else '❌ Denied'}"
        if not changed:
            text = "Already decided or expired"
        telegram.answer_callback(cq["id"], text)

    return Response("ok", 200)


# ── Health ─────────────────────────────────────────────────────────────────────
@app.route("/health")
def health() -> Response:
    return Response(
        json.dumps({
            "service":      "hitl-proxy",
            "hitl_enabled": HITL_ENABLED,
            "hermes_url":   HERMES_URL,
            "threshold":    HITL_THRESHOLD,
        }),
        content_type="application/json",
    )


if __name__ == "__main__":
    port = int(os.environ.get("HITL_PORT", "8687"))
    log.info("HITL proxy starting on port %d → %s", port, HERMES_URL)
    app.run(host="0.0.0.0", port=port, threaded=True)
