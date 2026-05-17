#!/usr/bin/env python3
# =============================================================================
# send_telegram_alert.py — Standalone Telegram alert sender
# Usage: python3 send_telegram_alert.py <SEVERITY> <TITLE> <MESSAGE>
# =============================================================================
import os
import sys
import json
import urllib.request
import urllib.parse

TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")

SEVERITY_EMOJI = {
    "INFO": "ℹ️",
    "WARNING": "⚠️",
    "CRITICAL": "🚨"
}


def send_alert(severity: str, title: str, message: str) -> bool:
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        print("❌ TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set", file=sys.stderr)
        return False

    emoji = SEVERITY_EMOJI.get(severity.upper(), "ℹ️")
    full_message = f"{emoji} *{title}*\n\n{message}"

    # Truncate if too long
    if len(full_message) > 4000:
        full_message = full_message[:3997] + "..."

    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    data = urllib.parse.urlencode({
        "chat_id": TELEGRAM_CHAT_ID,
        "text": full_message,
        "parse_mode": "Markdown",
        "disable_web_page_preview": "true"
    }).encode("utf-8")

    try:
        req = urllib.request.Request(url, data=data, method="POST")
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
        with urllib.request.urlopen(req, timeout=30) as response:
            result = json.loads(response.read().decode())
            if result.get("ok"):
                print(f"✅ Alert sent: {title}")
                return True
            else:
                print(f"❌ Telegram API error: {result}", file=sys.stderr)
                return False
    except Exception as e:
        print(f"❌ Failed to send alert: {e}", file=sys.stderr)
        return False


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python3 send_telegram_alert.py <SEVERITY> <TITLE> <MESSAGE>")
        print("Example: python3 send_telegram_alert.py CRITICAL 'Governance Failed' 'Drift check failed'")
        sys.exit(1)

    severity = sys.argv[1]
    title = sys.argv[2]
    message = sys.argv[3]

    success = send_alert(severity, title, message)
    sys.exit(0 if success else 1)
