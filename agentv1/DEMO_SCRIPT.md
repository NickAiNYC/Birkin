# 60-Second Demo Script — Scrutexity Agent

> Record this on your iPhone screen. No editing needed — one continuous take.

---

## Setup (Before Recording)

1. Ensure agent is deployed and running
2. Open Safari on iPhone
3. Ensure microphone permission is granted for Safari
4. Have Telegram open in background (to show alert receipt)
5. Have a second device (laptop) SSH'd into the server to run scripts

---

## The Script (60 seconds, timed)

### 0:00 — 0:05 | Open the Agent
- **Action:** Unlock iPhone → tap "Scrutexity Agent" icon on Home Screen (PWA)
- **Screen shows:** Open WebUI loads, dark mode, model dropdown shows "scrutexity-agent"
- **Voiceover:** *"This is my agent. I control it entirely from my phone."*

### 0:05 — 0:20 | Voice Command: Sourcing Intelligence
- **Action:** Tap microphone icon in Open WebUI input bar
- **Speak clearly:** *"Run the sourcing intelligence skill and report new peptide suppliers this week"*
- **Screen shows:** Voice input transcribes → message sends → agent thinks (spinner) → tool indicators appear: `🔍 searching...`, `🌐 web_search: 1688.com 肽原料 GMP 工厂`
- **Screen shows:** Markdown table streams in real-time with suppliers, veto scores, actions
- **Voiceover:** *"It searches 1688, applies my supplier veto checklist, and streams results live."*

### 0:20 — 0:35 | Show Governance: Health Endpoint
- **Action:** Open new Safari tab → type `health.yourdomain.com/health`
- **Screen shows:** Raw JSON:
  ```json
  {
    "agent_status": "healthy",
    "uptime_seconds": 18472,
    "last_action_timestamp": "2026-05-17T11:23:00Z",
    "skill_count": 5,
    "audit_log_entries": 1427,
    "drift_check_status": "PASS"
  }
  ```
- **Voiceover:** *"Every action is logged. The health endpoint proves governance is intact."*

### 0:35 — 0:50 | Show Audit Log
- **Action:** Switch to laptop (or use Safari split view) → SSH into server
- **Type:** `./scripts/audit-log.sh --today`
- **Screen shows:**
  ```
  === Scrutexity Agent Audit Log ===
  2026-05-17 11:23:00 | sourcing-intel    | ✅ | 2847 tokens | $0.0042 | 1688 search: peptide OEM
  2026-05-17 11:15:00 | directora-health  | ✅ |  892 tokens | $0.0018 | Health check: all pass
  2026-05-17 11:00:00 | daily-brief       | ✅ | 3421 tokens | $0.0051 | Morning brief generated
  ```
- **Voiceover:** *"Append-only audit log. Every skill, every token, every cost — tracked."*

### 0:50 — 0:60 | Final Governance Check
- **Action:** On laptop, type: `./scripts/governance-check.sh`
- **Screen shows:**
  ```
  [1/5] Hermes Gateway Process
    ✅ Hermes gateway systemd service active
    ✅ Hermes API responding
  [2/5] Audit Log Append-Only Integrity
    ✅ No tampered audit entries detected
  ...
  ✅ AGENT GOVERNANCE INTACT
  ```
- **Voiceover:** *"Governed, self-improving agent infrastructure — not just a chatbot."*
- **End card:** Fade to black → show `https://github.com/NickAiNYC/scrutexity-agent`

---

## Recording Tips

- **Orientation:** Landscape for laptop shots, portrait for iPhone shots. Or film iPhone in portrait throughout.
- **Lighting:** Face a window or use a ring light. The iPhone screen should be clearly visible.
- **Audio:** Use AirPods or wired headphones for clean voiceover. Avoid speakerphone.
- **Pacing:** Speak deliberately. The 60 seconds is tight — practice once before recording.
- **Backup plan:** If voice input fails, type the command manually and say *"I can also type commands."*

---

## Post-Recording

1. Trim start/end if needed (keep under 65 seconds)
2. Add captions (iOS auto-captions work well)
3. Post to:
   - Twitter/X (primary)
   - LinkedIn (professional)
   - GitHub repo README (embed as GIF or link)
   - Personal website

## Suggested Caption

> "I built a 24/7 AI agent that runs on a €4 server, learns from experience, and is controlled entirely from my iPhone. Every action is audit-logged. Every skill is version-tracked. Every week it checks itself for drift. This isn't a chatbot — it's governed, self-improving agent infrastructure. Open source: [link]"
