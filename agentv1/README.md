# Scrutexity Agent — Governed, Self-Improving Personal AI Agent

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Governance](https://img.shields.io/badge/governance-intact-brightgreen)
![License](https://img.shields.io/badge/license-MIT-green)
![Monthly Cost](https://img.shields.io/badge/cost-%E2%82%AC4.50%2Fmonth-orange)

> **A 24/7 AI agent that learns from experience, writes its own skills, and is controlled entirely from an iPhone — over governed, audit-logged infrastructure.**

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              YOUR iPHONE                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                      │
│  │   Safari     │  │  Voice Input │  │  Telegram    │                      │
│  │  (PWA)       │  │  (Open WebUI)│  │   Alerts     │                      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘                      │
└───────┼────────────────┼────────────────┼──────────────────────────────────┘
        │                │                │
        ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CLOUDFLARE TUNNEL (Free)                            │
│              DDoS Protection • Custom Domain • Zero Open Ports               │
│                    https://agent.scrutexity.com                             │
└─────────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    HETZNER CX22 — €4/mo Ubuntu 24.04                        │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │  UFW (22, 443 only)  │  fail2ban  │  unattended-upgrades  │  SSH key  │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌─────────────────────┐    ┌─────────────────────┐    ┌───────────────┐  │
│  │   Hermes Agent      │◄──►│    Open WebUI        │    │  Health Endpoint│  │
│  │   v0.13.0 "Tenacity"│    │    (Docker)          │    │  Port 9999      │  │
│  │   Port 8686         │    │    Port 3000         │    │                 │  │
│  │                     │    │                      │    │                 │  │
│  │  • OpenRouter API   │    │  • Mobile PWA        │    │  • /health      │  │
│  │  • Claude Sonnet 4  │    │  • Voice Calls       │    │  • /detailed    │  │
│  │  • Haiku Fallback   │    │  • RAG + Tools       │    │  • JSON Status  │  │
│  │  • SKILL.md Loop    │    │  • Admin Panel       │    │                 │  │
│  │  • Cron Jobs        │    │                      │    │                 │  │
│  │  • SQLite Audit     │    │                      │    │                 │  │
│  └─────────────────────┘    └─────────────────────┘    └───────────────┘  │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    GOVERNANCE LAYER                                    │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐   │   │
│  │  │ audit-log.sh│ │ skill-diff.sh│ │ drift-check│ │ governance  │   │   │
│  │  │  (SQLite)   │ │   (Git)      │ │   (.json)  │ │  -check.sh  │   │   │
│  │  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘   │   │
│  │                                                                     │   │
│  │  • Append-only audit store    • Skill version tracking (Git)        │   │
│  │  • Weekly drift detection     • Master governance validation        │   │
│  │  • Telegram alerts on failure • Automatic daily backups           │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

**One command to deploy everything:**

```bash
# 1. Clone this repo
git clone https://github.com/NickAiNYC/scrutexity-agent.git
cd scrutexity-agent

# 2. Run deploy.sh with your credentials
./deploy.sh <HETZNER_API_TOKEN> <CLOUDFLARE_API_TOKEN> <DOMAIN> <OPENROUTER_API_KEY> [TELEGRAM_BOT_TOKEN] [TELEGRAM_CHAT_ID]

# Example:
./deploy.sh hz_xxx cf_xxx agent.scrutexity.com sk-or-v1-xxx 123456:ABC -1001234567890
```

**That's it.** In ~12 minutes, your agent is live at `https://your-domain.com`.

---

## Governance Layer

This agent doesn't just run — it is *governed*. Every mechanism below is borrowed from [Directora v1.0.0](https://github.com/Scrutexity/Directora) (284 passing tests, 9 governance gates, cryptographic signature binding, append-only hash-chained ledger).

| Component | Purpose | File |
|-----------|---------|------|
| **Audit Log** | Append-only SQLite store of every agent action with timestamp, skill, tokens, cost, success/failure | `scripts/audit-log.sh` |
| **Skill Versioning** | All SKILL.md files live in a git repo; every change is tracked, versioned, and diffable | `scripts/skill-diff.sh` |
| **Drift Detection** | 5 benchmark questions run weekly; responses compared to baseline via cosine similarity; flags if < 0.85 | `scripts/drift-check.sh` |
| **Governance Check** | Master validation: Hermes running? Audit append-only? Skills versioned? Drift passing? Health responding? | `scripts/governance-check.sh` |
| **Health Endpoint** | JSON status on port 9999: uptime, last action, skill count, audit entries, drift status | `health/health_endpoint.py` |
| **Telegram Alerts** | Automatic alerts for governance failures, drift failures, Directora degradation, token spikes | Built into skills |
| **Daily Backup** | `~/.hermes/` backed up to `/backups/hermes/` at 3 AM daily, 7-day retention | systemd timer |
| **Auto-Recovery** | If Hermes crashes 3× in 1 hour, auto-restart + Telegram alert | systemd `StartLimitBurst` |

### Running Governance Checks

```bash
# From the server (SSH in)
./scripts/audit-log.sh --today      # Today's actions
./scripts/audit-log.sh --failed     # Failed actions only
./scripts/audit-log.sh --cost       # Monthly cost estimate

./scripts/skill-diff.sh             # Recent skill changes
./scripts/drift-check.sh            # Run drift detection
./scripts/governance-check.sh       # Full validation
```

### Expected Output

```bash
$ ./scripts/governance-check.sh
=== Scrutexity Agent Governance Check ===
[1/5] Hermes Gateway Process
  ✅ Hermes gateway systemd service active
  ✅ Hermes API responding
[2/5] Audit Log Append-Only Integrity
  ✅ No tampered audit entries detected (append-only intact)
  ✅ Audit timestamps are monotonically ordered
[3/5] Skill Version Consistency
  ✅ Skills directory is a git repo
  ✅ No uncommitted skill changes
  ✅ All skills have version metadata
[4/5] Drift Detection
  ✅ Latest drift check passed (drift-results-20260517-060000.json)
[5/5] Health Endpoint
  ✅ Health endpoint responds
  ✅ Health JSON is valid

✅ AGENT GOVERNANCE INTACT
```

---

## Connection to Directora

The governance patterns in this agent are not theoretical — they are **production-proven** in Directora v1.0.0:

| Directora Feature | Agent Equivalent |
|-------------------|------------------|
| Append-only hash-chained ledger | SQLite audit.db with monotonic timestamps |
| Cryptographic signature binding | Git commit signatures on SKILL.md changes |
| Server-authoritative timestamps | UTC timestamps from server clock (no client trust) |
| 9 governance gates | 5 governance checks + drift detection |
| JWT revocation with jti blacklist | API key rotation via OpenRouter credential pools |
| 503 + Retry-After backpressure | systemd auto-restart with exponential backoff |
| PHI guard whitelist | Skill-level config for sensitive data access |
| Byte-identical idempotent replay | Git-versioned skills = reproducible agent behavior |

> **The thesis:** If you can govern clinical infrastructure with 284 tests and cryptographic proof, you can govern an AI agent with the same rigor.

---

## Built by the Founder of Scrutexity

**Nick** — founder of [Scrutexity](https://github.com/Scrutexity), builder of:

- **[Directora v1.0.0](https://github.com/Scrutexity/Directora)** — Governed clinical infrastructure engine. 284 passing tests. 9 governance gates. Append-only hash-chained tamper-evident ledger. Server-authoritative timestamps. Rotating secrets with 30-day grace. PostgreSQL RLS. JWT revocation. PHI guard whitelist. Real JWKS governance proof in CI.
- **LabBrief** (private) — React 18 + TypeScript clinical review interface. PHI-minimizing architecture. Async sign-off. Contract snapshot enforcement.

This agent is the **public resume piece** that proves: *I don't just use AI agents. I build governed, self-improving agent infrastructure.*

---

## Skills

The agent ships with 5 production-grade skills. Each is a `SKILL.md` file with YAML frontmatter, progressive disclosure, and failure recovery steps.

| Skill | Purpose | Trigger | Schedule |
|-------|---------|---------|----------|
| **sourcing-intel** | Weekly 1688/Korean supplier search with veto checklist | Manual or `/sourcing-intel` | Every Monday 9 AM |
| **competitor-monitor** | Track 3-5 NYC aesthetic clinics for changes | Manual or `/competitor-monitor` | Every Sunday 6 PM |
| **directora-health** | Check Directora health, ledger integrity, Prometheus metrics | Manual or `/directora-health` | Every 6 hours |
| **daily-brief** | Morning brief: emails, calendar, sourcing, health, headline, priority | Manual or `/daily-brief` | Every day 7 AM ET |
| **code-governance** | Post-push governance check: tests, contracts, locks, scripts | Manual or `/code-governance` | On every git push |

### Adding Your Own Skills

```bash
# Create a new skill directory
cd ~/.hermes/skills
mkdir my-new-skill
cat > my-new-skill/SKILL.md <<'SKILL'
---
name: my-new-skill
description: Use when the user asks about [topic]
version: 1.0.0
created_date: 2026-05-17
---

# My New Skill

## When to Use
...

## Procedure
1. Step one
2. Step two

## Failure Recovery Steps
1. If X fails, do Y
SKILL

# Commit to git
git add -A && git commit -m "Add my-new-skill v1.0.0"
```

---

## Cost Breakdown

| Service | Monthly Cost | Why |
|---------|-------------|-----|
| Hetzner CX22 | €4.51 (~$4.90) | 2 vCPU, 4 GB RAM, 40 GB SSD |
| Cloudflare Tunnel | $0 | Free tier, unlimited bandwidth |
| Domain (your own) | ~$12/yr (~$1/mo) | Cloudflare registrar |
| OpenRouter API | ~$5-20 | Claude Sonnet for complex tasks, Haiku/Flash for routine |
| Telegram Bot | $0 | Bot API is free |
| **Total** | **~€10-25 / ~$11-27** | Under €20 target with smart routing |

**Cost optimization:** The Hermes config uses `provider_routing: sort: price` with auxiliary models routed to Gemini Flash. This cuts API costs 40-60% vs. sending everything to Claude Sonnet.

---

## iPhone Setup

### Option A: Safari PWA (Recommended)

1. Open Safari → navigate to `https://your-domain.com`
2. Tap **Share** → **Add to Home Screen**
3. Name it "Scrutexity Agent"
4. Open from Home Screen — it runs full-screen like a native app
5. Tap the **microphone icon** in Open WebUI for voice input
6. Enable **Voice Calls** in Open WebUI settings for hands-free interaction

### Option B: Native iOS App

Search the App Store for **"Open WebUI"** or compatible clients. As of May 2026, the recommended native experience is the Safari PWA (Open WebUI does not have an official native iOS app; the PWA supports voice input, offline caching, and push notifications via service workers).

---

## Security & Hardening

- **No open inbound ports** except SSH (22) and Cloudflare Tunnel (443)
- **SSH key-only** authentication — no passwords
- **fail2ban** bans IPs after 3 failed SSH attempts
- **Automatic security updates** via unattended-upgrades
- **Non-root user** (`scrutexity`) runs Hermes and Open WebUI
- **API keys in systemd env files** — never in plain config files visible in repo
- **Rate limiting** via Cloudflare Tunnel WAF rules
- **Weekly full apt upgrade** via systemd timer

---

## Environment Variables

Copy `.env.example` to `.env` and fill in:

```bash
# Required
OPENROUTER_API_KEY=sk-or-v1-xxx

# Optional — for Telegram alerts
TELEGRAM_BOT_TOKEN=123456:ABC
TELEGRAM_CHAT_ID=-1001234567890

# Optional — for Directora health checks
DIRECTORA_BASE_URL=https://directora.yourdomain.com
DIRECTORA_PROMETHEUS_URL=https://prometheus.yourdomain.com
```

---

## License

MIT License — see [LICENSE](LICENSE)

---

## Contributing

This repo is designed to be **forked and extended**. To add your own governed skills:

1. Fork the repo
2. Add your `SKILL.md` to `skills/`
3. Update `scripts/governance-check.sh` if your skill adds new validation rules
4. Commit with semantic version bump in skill frontmatter
5. Open a PR with a governance summary

Every skill must include:
- YAML frontmatter with `name`, `description`, `version`, `created_date`
- `failure_recovery_steps` section
- Clear trigger conditions in `description`

---

## Support

- **Issues:** [GitHub Issues](https://github.com/NickAiNYC/scrutexity-agent/issues)
- **Directora:** [github.com/Scrutexity/Directora](https://github.com/Scrutexity/Directora)
- **Author:** [@NickAiNYC](https://github.com/NickAiNYC)
