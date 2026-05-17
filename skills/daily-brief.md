---
name: daily-brief
description: |
  Use when the user asks for a daily briefing, morning summary, overnight report, or daily digest.
  Triggered automatically every day at 7 AM ET (11 AM UTC) via cron. Triggers: "daily brief",
  "morning report", "what happened overnight", "today's priorities", "brief me", "daily digest",
  "morning briefing".
version: 1.0.0
created_date: 2026-05-17
platforms: [linux]
metadata:
  hermes:
    tags: [daily-brief, morning, summary, telegram, productivity]
    category: productivity
    requires_toolsets: [web_research, file, messaging]
    fallback_for_toolsets: []
    config:
      - key: brief.calendar_url
        description: "iCal/ICS calendar URL for today's events"
        default: ""
        prompt: "Enter your calendar ICS URL (optional)"
      - key: brief.email_check
        description: "Enable email subject scanning"
        default: "false"
        prompt: "Enable email monitoring? (requires IMAP config)"
---

# Daily Brief Generator Skill

## When to Use
- Automated every morning at 7 AM ET (cron: `0 11 * * *`)
- User asks: "brief me", "morning report", "what's today look like"
- Any request for a consolidated daily summary

## Sections

### 1. Overnight Emails (if email_check enabled)
- Scan last 12 hours of email subjects
- Flag urgent: subjects containing "URGENT", "ASAP", "deadline", "meeting changed"
- Flag action needed: subjects containing "review", "approve", "sign", "feedback"
- List top 5 by urgency, with sender and timestamp
- If email not configured, skip with note: "Email monitoring not configured"

### 2. Today's Calendar
- If calendar_url configured: parse ICS for today's events
- List meetings with time, title, and location/link
- Highlight conflicts (overlapping events)
- If no calendar: skip with note

### 3. Sourcing Alerts (Past 24h)
- Check `~/.hermes/cron/output/weekly-sourcing/` for most recent sourcing report
- If report is < 24h old, extract top 3 new suppliers flagged as PRIORITY
- If no recent report, note: "No new sourcing alerts in last 24h"

### 4. Directora System Health
- Run directora-health skill (lightweight version)
- Report: status emoji + one-line summary
- Example: "✅ Directora healthy — 0 issues, ledger valid"

### 5. AI / Agent Industry Headline
- Search `AI agent news 2026` or `autonomous agent breakthrough 2026`
- Pick the single most significant headline from last 24h
- One sentence summary + source link

### 6. Top Priority for the Day
- Based on calendar, emails, and sourcing alerts, recommend ONE top priority
- Format: "Today's #1 priority: [action] because [reason]"

## Output Format
```markdown
# Daily Brief — YYYY-MM-DD

## 📧 Overnight Emails
1. [URGENT] FDA response due — Legal Team (2:14 AM)
2. [Action] Review Directora v1.0.1 PR — Dev Team (6:30 AM)
3. [Info] 1688 supplier quote received — Sourcing (11:42 PM)

## 📅 Today's Calendar
- 9:00 AM — Standup (Zoom)
- 11:00 AM — Vendor call: Shenzhen Medical (Google Meet)
- 2:00 PM — Deep work block — Directora roadmap

## 🏭 Sourcing Alerts (24h)
- New PRIORITY: 红光治疗仪 OEM — 深圳XX医疗 (1688)
- New PRIORITY: 肽原料 GMP — 上海YY生物 (1688)

## 🏥 Directora Health
✅ All systems healthy — ledger valid, 0 alerts

## 🤖 Industry Headline
OpenAI releases GPT-5 agent mode with persistent memory across sessions

## 🎯 Today's #1 Priority
Review and merge Directora v1.0.1 PR before 2 PM vendor call
```

## Delivery
1. Save to `~/briefs/YYYY-MM-DD.md`
2. Send to Telegram (if TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID configured)
3. If Telegram fails, log to `~/.hermes/cron/output/daily-brief/YYYY-MM-DD.md`

## Failure Recovery Steps
1. If email/calendar fetch fails, continue with other sections and note the failure
2. If Directora health check fails, report "⚠️ Directora unreachable — check network"
3. If web search for headlines fails, use cached last-known headline and note "News fetch failed"
4. If Telegram delivery fails, save to file and retry delivery in 30 minutes via cron
5. On total failure: save minimal brief with timestamp and error log to `~/briefs/failed-YYYY-MM-DD.md`
