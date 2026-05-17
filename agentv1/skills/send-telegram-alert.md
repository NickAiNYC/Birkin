---
name: send-telegram-alert
description: |
  Use when any other skill needs to send an alert, notification, or report to Telegram.
  This is a utility skill called by sourcing-intel, competitor-monitor, directora-health,
  daily-brief, and code-governance. Triggers: "send alert", "telegram alert", "notify me",
  "send report to Telegram", "alert on failure".
version: 1.0.0
created_date: 2026-05-17
platforms: [linux]
metadata:
  hermes:
    tags: [alerting, telegram, messaging, utility]
    category: infrastructure
    requires_toolsets: [messaging]
    fallback_for_toolsets: []
---

# Send Telegram Alert Skill

## When to Use
- Called automatically by other skills on failure, critical findings, or scheduled reports
- User asks: "send this to Telegram", "alert me", "notify on failure"
- Any skill that produces output needing immediate user attention

## Prerequisites
Environment variables must be set in `~/.hermes/.env`:
```
TELEGRAM_BOT_TOKEN=123456:ABC-your-bot-token-from-botfather
TELEGRAM_CHAT_ID=-1001234567890
```

## Procedure
1. Format the message as Markdown (Telegram supports basic Markdown)
2. Truncate if > 4096 characters (Telegram limit)
3. Send via Telegram Bot API:
   ```
   POST https://api.telegram.org/bot<TOKEN>/sendMessage
   chat_id=<CHAT_ID>
   text=<MESSAGE>
   parse_mode=Markdown
   disable_web_page_preview=true
   ```
4. If sending fails (network error, bot blocked), retry once after 30s
5. If retry fails, log to `~/.hermes/cron/output/telegram-failures/YYYY-MM-DD.txt`

## Message Format Template
```
🤖 *Scrutexity Agent Alert*

*Skill:* {skill_name}
*Time:* {timestamp}
*Status:* {emoji} {status}

{summary}

*Action Required:*
{action_items}
```

## Alert Severity Levels
| Level | Emoji | Use Case |
|-------|-------|----------|
| INFO | ℹ️ | Routine completion, daily brief delivered |
| WARNING | ⚠️ | Degraded performance, non-critical drift |
| CRITICAL | 🚨 | Governance failure, ledger broken, agent crashed |

## Failure Recovery Steps
1. If Telegram API returns 429 (rate limit), wait 60s and retry with exponential backoff
2. If bot token is invalid, log error and alert via health endpoint instead
3. If chat_id is invalid, log error and try to send to backup chat_id if configured
4. If network is completely down, queue alerts in `~/.hermes/cron/output/queued-alerts/` and flush when connectivity returns
5. On total failure: write to local log and trigger systemd health endpoint degradation status
