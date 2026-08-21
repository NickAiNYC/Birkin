"""
telegram_webhook.py — Send approval requests and receive inline keyboard callbacks.

Telegram callback flow:
  1. main.py receives HIGH-risk request → calls send_approval_request()
  2. User taps Approve or Deny in Telegram
  3. Telegram POSTs callback_query to /telegram/callback on this server
  4. handle_callback() updates approval_queue with decision
  5. main.py's poll_decision() unblocks and allows/denies the request
"""
import json
import logging
import os
from typing import Optional

import requests

log = logging.getLogger(__name__)


class TelegramClient:
    def __init__(self, bot_token: str, chat_id: str):
        self._token = bot_token
        self._chat_id = chat_id
        self._base = f"https://api.telegram.org/bot{bot_token}"

    def send_approval_request(
        self, action_id: str, skill: str, summary: str, risk_level: str
    ) -> Optional[int]:
        """Send a Telegram message with Approve/Deny inline buttons. Returns message_id."""
        text = (
            f"🚨 <b>HITL Approval Required</b>\n\n"
            f"<b>Risk:</b> {risk_level}\n"
            f"<b>Skill:</b> {skill}\n"
            f"<b>Action:</b> {summary[:300]}\n\n"
            f"<code>{action_id[:8]}</code>"
        )
        keyboard = {
            "inline_keyboard": [[
                {"text": "✅ Approve", "callback_data": f"approve:{action_id}"},
                {"text": "❌ Deny",    "callback_data": f"deny:{action_id}"},
            ]]
        }
        try:
            resp = requests.post(
                f"{self._base}/sendMessage",
                json={
                    "chat_id":    self._chat_id,
                    "text":       text,
                    "parse_mode": "HTML",
                    "reply_markup": keyboard,
                },
                timeout=10,
            )
            data = resp.json()
            if data.get("ok"):
                return data["result"]["message_id"]
            log.warning("Telegram sendMessage failed: %s", data)
        except Exception as exc:
            log.error("Telegram error: %s", exc)
        return None

    def send_alert(self, skill: str, summary: str, risk_level: str, auto_approved: bool):
        """Send async MEDIUM-risk alert (no approval needed)."""
        emoji = "⚠️" if risk_level == "MEDIUM" else "ℹ️"
        status = "auto-approved" if auto_approved else "logged"
        text = (
            f"{emoji} <b>HITL Alert ({risk_level})</b> — {status}\n\n"
            f"<b>Skill:</b> {skill}\n"
            f"<b>Action:</b> {summary[:300]}"
        )
        try:
            requests.post(
                f"{self._base}/sendMessage",
                json={
                    "chat_id":    self._chat_id,
                    "text":       text,
                    "parse_mode": "HTML",
                },
                timeout=10,
            )
        except Exception as exc:
            log.error("Telegram alert error: %s", exc)

    def answer_callback(self, callback_query_id: str, text: str = ""):
        try:
            requests.post(
                f"{self._base}/answerCallbackQuery",
                json={"callback_query_id": callback_query_id, "text": text},
                timeout=5,
            )
        except Exception as exc:
            log.warning("answerCallbackQuery error: %s", exc)

    def set_webhook(self, webhook_url: str):
        resp = requests.post(
            f"{self._base}/setWebhook",
            json={"url": webhook_url},
            timeout=10,
        )
        return resp.json()


def parse_callback(callback_data: str):
    """Parse 'approve:uuid' or 'deny:uuid' → (decision, action_id)."""
    if ":" not in callback_data:
        return None, None
    decision, action_id = callback_data.split(":", 1)
    if decision not in ("approve", "deny"):
        return None, None
    return decision, action_id
