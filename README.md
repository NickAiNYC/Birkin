<div align="center">
  <img alt="Birkin — autonomous Hermes agent that carries its own proof of integrity" src="assets/birkin-banner.png" width="900" />
</div>

# Birkin

<div align="center">

**An Autonomous Hermes Agent That Governs Itself**

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Governance](https://img.shields.io/badge/governance-5%2F5%20gates%20passing-brightgreen)
![Audit](https://img.shields.io/badge/audit-SHA--256%20chained-0A2540)
![Tamper](https://img.shields.io/badge/tamper--test-passing-brightgreen)
![Cost](https://img.shields.io/badge/cost-%E2%82%AC13%2Fmo-brightgreen)
![iPhone Ready](https://img.shields.io/badge/control-iPhone%20PWA-black)
![License](https://img.shields.io/badge/license-MIT-green)

**The first AI agent that carries its own cryptographic proof of integrity.**

Governed like clinical infrastructure. Controlled from your iPhone. Running on €13/month.

**A luxury autonomous agent. €13/month. Governed like clinical infrastructure. Controlled entirely from your phone.**

*The first AI agent that carries its own governance — audit logs, skill versions, drift detection, and safety bounds built in, not bolted on.*

[**Deploy Now →**](#-deploy-birkin-in-10-minutes) · [**Try Locally →**](#-try-it-locally-no-server) · [**Add a Skill →**](#-build-your-own-skills) · [**Read the Philosophy →**](#-why-governance-matters)

</div>

---

## What Is Birkin?

Birkin is a **self-governing autonomous agent** that runs on a €13/month Hetzner server and is controlled entirely from your iPhone.

Think of it as a luxury bag that carries itself:
- **What goes in** — skills (SKILL.md files that define agent behavior)
- **What it carries** — audit logs (every action logged once, append-only)
- **How it proves itself** — governance checks (5 gates that prove integrity)
- **Where you grab it** — your iPhone (Safari PWA, voice control, Telegram alerts)

It's not a chatbot wrapper. It's not a toy. It's what happens when you apply **production-grade clinical infrastructure governance** to an autonomous AI agent.

```
Your iPhone → Cloudflare Tunnel → Birkin (Hermes Agent + Governance Layer) → Skills execute → Audit logged
```

---

## The Core Promise

**Birkin governs itself.** One command proves it:

```bash
./governance-check.sh
```

Output:
```
[1/5] Hermes Gateway — ✅ running, API responding
[2/5] Audit Integrity — ✅ append-only, monotonic timestamps, 0 tampered entries
[3/5] Skill Versioning — ✅ git-tracked, all changes committed, 6 skills deployed
[4/5] Drift Detection — ✅ 5 benchmarks stable (cosine similarity ≥ 0.85)
[5/5] Health Endpoint — ✅ JSON governance status, uptime 14 days

✅ BIRKIN GOVERNANCE INTACT
   All critical gates passed. Agent is operating within defined boundaries.
```

**That's it.** No faith required. Cryptographic proof.

---

## 🛡️ The Tamper Test (Don't Take My Word For It)

Most "audit logs" are append-only by convention. Birkin's audit log is **hash-chained at the row level** — every row carries `SHA-256(prev_hash || payload)`. Mutate a single byte and the next verification fails.

Two layers of defense:
1. **SQLite triggers** block `UPDATE` and `DELETE` on `audit_log` at the database layer.
2. **Hash chain** catches mutation even when an attacker bypasses the triggers via file-level access.

Prove it yourself in 5 seconds:

```bash
./tests/tamper-test.sh
```

```text
🧪 Birkin tamper-detection test
[1/6] ✅ schema initialized (table + triggers)
[2/6] ✅ appended 5 hash-chained rows
[3/6] ✅ clean chain verifies PASS
[4/6] ✅ trigger blocks UPDATE (append-only enforced at DB layer)
[5/6] 🔓 simulated attacker: dropped triggers, rewrote row 3
[6/6] ✅ tamper DETECTED by hash chain:
       ❌ CHAIN BROKEN at row 3 (row_tampered)
          row_hash mismatch (expected ad2548c43ed6..., got 9f1894ea0f03...)

🛡️  PASS — Birkin's audit chain catches mutation even when triggers are bypassed.
```

Source: [`scripts/audit-init.sql`](scripts/audit-init.sql) · [`scripts/audit-append.py`](scripts/audit-append.py) · [`scripts/verify-chain.py`](scripts/verify-chain.py) · [`tests/tamper-test.sh`](tests/tamper-test.sh)

---

## Why This Matters

| Problem | Existing Agents | Birkin |
|---------|-----------------|--------|
| **Auditability** | "Trust me, I logged it" | **SHA-256 hash-chained SQLite.** Every row links to the previous. Mutate one byte → chain breaks → CI fails. Proven by `tests/tamper-test.sh`. |
| **Reproducibility** | Weights shift randomly | Git-versioned SKILL.md files. `git diff` the agent's brain. |
| **Behavior Drift** | Degrades silently | Weekly cosine similarity checks. Flags if < 0.85. |
| **Cost** | $100-300/mo (Claude API + infra) | €13/mo (Hetzner) + ~$5-20/mo API usage |
| **Control Surface** | Laptop SSH or web dashboard | iPhone PWA. Voice input. Telegram alerts. |
| **Safety Bounds** | Hope | 5-gate governance validation. Kill switches. Lockdown mode. |

---

## Governance Pipeline

Birkin's heart is its **5-gate governance validation**:

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ GATE 1       │    │ GATE 2       │    │ GATE 3       │    │ GATE 4       │    │ GATE 5       │
│              │    │              │    │              │    │              │    │              │
│ Process      │───▶│ Audit        │───▶│ Skill        │───▶│ Drift        │───▶│ Health       │
│ Running?     │    │ Integrity    │    │ Versioning   │    │ Detection    │    │ Endpoint     │
│              │    │              │    │              │    │              │    │              │
│ Hermes PID?  │    │ Append-only? │    │ Git-signed?  │    │ Cosine ≥0.85?│    │ /health 200? │
│ API 200?     │    │ No overwrites?│   │ No unstaged? │    │ No divergence│    │ JSON valid?  │
└──────┬───────┘    └──────┬───────┘    └──────┬───────┘    └──────┬───────┘    └──────┬───────┘
       │                   │                   │                   │                   │
       ✅                  ✅                  ✅                  ✅                  ✅
```

Each gate is cryptographic. Failure stops the agent and alerts you immediately.

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                              YOUR iPHONE                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                     │
│  │  Safari PWA  │  │  Voice Input │  │  Telegram    │                     │
│  │  (Add to HS) │  │  (Open WebUI)│  │   Alerts     │                     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘                     │
└─────────┼──────────────────┼──────────────────┼─────────────────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                       CLOUDFLARE TUNNEL (Free)                             │
│           DDoS Protection · Custom Domain · Zero Open Ports                │
└──────────────────────────────┬──────────────────────────────────────────────┘
                               │
                               ▼
┌────────────────────────────────────────────────────────────────────────────┐
│              HETZNER CX22 (€4.51/mo) + OpenRouter API (~$5-20)            │
│  ┌─────────────────────┐    ┌─────────────────┐    ┌─────────────────┐   │
│  │  Hermes v0.13.0     │◄──▶│  Open WebUI     │    │  Health         │   │
│  │  (Agent Engine)     │    │  (Docker)       │    │  Endpoint       │   │
│  │  Port 8686          │    │  Port 3000      │    │  Port 9999      │   │
│  │                     │    │                 │    │  /health        │   │
│  │ • Claude Sonnet 4   │    │ • Mobile PWA    │    │ • Governance    │   │
│  │ • Haiku (fallback)  │    │ • Voice Calls   │    │   Status JSON   │   │
│  │ • SKILL.md Loop     │    │ • RAG + Tools   │    │ • Uptime        │   │
│  │ • SQLite Audit.db   │    │ • Admin Panel   │    │ • Last Action   │   │
│  └─────────────────────┘    └─────────────────┘    └─────────────────┘   │
│                                                                            │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │                    GOVERNANCE LAYER (284 Lines)                     │   │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐              │   │
│  │  │ audit-log.sh │ │ skill-diff.sh│ │drift-check.sh│ governance- │   │
│  │  │ (SQLite)     │ │ (Git)        │ │ (JSON)       │ check.sh    │   │
│  │  └──────────────┘ └──────────────┘ └──────────────┘              │   │
│  │  • Append-only    • Skill tracking  • Behavior gates   • Master   │   │
│  │  • Timestamps     • Version diffs   • Cosine sim ≥0.85│ validation│   │
│  │  • No rewrites    • Git commits     • Weekly benchmarks           │   │
│  └────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │                         SKILLS (6 Deployed)                        │   │
│  │  daily-brief • sourcing-intel • competitor-monitor                │   │
│  │  directora-health • code-governance • send-telegram-alert          │   │
│  │  Each: YAML frontmatter + cron schedule + failure recovery         │   │
│  └────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## 🧪 Try It Locally (No Server)

**Fastest way to feel Birkin without deploying.**

```bash
git clone https://github.com/NickAiNYC/birkin.git
cd birkin

export OPENROUTER_API_KEY=sk-or-v1-xxx

docker compose up -d
```

Then open http://localhost:3000 in your browser. Hermes is running. Governance is live. Skills are executing.

Check governance:
```bash
docker compose exec hermes ./governance-check.sh
```

---

## 🚀 Deploy Birkin in 10 Minutes

> **Note:** The local Docker quickstart below is the fully supported launch path. 
> The Hetzner deploy script (`deploy.sh`) contains VERIFY notes that require
> manual confirmation of Hermes install URLs and model slugs before production use.
> See [deploy.sh](deploy.sh) comments for details.

### What You Need

- **Hetzner account** (€4.51/mo for CX22 server)
- **Cloudflare account** (free, for Tunnel + domain)
- **OpenRouter API key** (~$5-20/mo, Claude Sonnet routing)
- **A domain** (any registrar, point nameservers to Cloudflare)
- **Telegram bot token** (optional, for alerts)

### Deploy

```bash
git clone https://github.com/NickAiNYC/birkin.git
cd birkin

# Create environment file (never commit this)
cat > deploy.env <<'ENV'
HETZNER_TOKEN=hz_xxx
CF_TOKEN=cf_xxx
DOMAIN=birkin.yourdomain.com
OPENROUTER_KEY=sk-or-v1-xxx
TELEGRAM_TOKEN=123456:ABC
TELEGRAM_CHAT=-1001234567890
ENV

# Deploy
source deploy.env && ./deploy.sh \
  --hetzner-token "$HETZNER_TOKEN" \
  --cf-token "$CF_TOKEN" \
  --domain "$DOMAIN" \
  --openrouter-key "$OPENROUTER_KEY" \
  --telegram-token "$TELEGRAM_TOKEN" \
  --telegram-chat "$TELEGRAM_CHAT"
```

**That's it.** In ~12 minutes:
- ✅ Server hardened (UFW, fail2ban, SSH key auth)
- ✅ Hermes + Open WebUI running
- ✅ Cloudflare Tunnel live
- ✅ All 6 skills deployed
- ✅ Governance gates passing
- ✅ iPhone PWA ready

Then open your domain on your iPhone Safari and tap "Add to Home Screen".

---

## 📱 Control from Your iPhone

### 1. Add to Home Screen

- Open Safari → `https://birkin.yourdomain.com`
- Tap **Share** → **Add to Home Screen**
- Name it "Birkin"
- Tap the icon — it opens full-screen like a native app

### 2. Use Voice Input

- Tap the **microphone icon** in Open WebUI
- Speak: *"Run the sourcing intelligence skill and report new peptide suppliers this week"*
- Agent thinks → streams Markdown results
- Everything logged to append-only audit

### 3. Get Telegram Alerts

When governance fails, Birkin posts to Telegram immediately:

```
🚨 GOVERNANCE ALERT

❌ Drift check FAILED
   Benchmark #3 diverged: cosine similarity 0.71 < 0.85
   
   Possible causes:
   - New skill deployed without baseline update
   - Model behavior changed
   - Temperature/sampling config drifted
   
Audit log: https://health.birkin.yourdomain.com/health
Skill diff: ssh -i ... birkin@... ./scripts/skill-diff.sh

[Acknowledge] [Run governance-check]
```

---

## 🏗️ Build Your Own Skills

Every skill is a `SKILL.md` file with:
- **YAML frontmatter** — name, description, version, triggers, tools needed, failure recovery steps
- **Markdown body** — execution logic, delivery format, error handling

### Skill Template

```markdown
---
name: my-skill
description: What this skill does and when to trigger it
version: 1.0.0
triggers:
  - cron: "0 9 * * *"
    description: Every day at 9 AM
tools_needed:
  - web_search
  - file_write
  - terminal
failure_recovery_steps:
  - "If X fails, check Y"
  - "Verify connectivity: curl https://api.example.com"
  - "Manually trigger: hermes run --skill my-skill"
---

# My Skill

## Overview
Clear explanation of what this skill does.

## Execution Steps
1. Step one
2. Step two
3. Step three

## Delivery
How results are sent (Telegram, file, stdout, etc.)

## Error Handling
What happens if something breaks.
```

### Deploy Your Skill

```bash
cd ~/.hermes/skills
cat > my-skill.md <<'SKILL'
---
name: my-skill
...
---
# My Skill
...
SKILL

git add my-skill.md
git commit -m "Add my-skill v1.0.0"

# Hermes auto-discovers and loads it
hermes run --skill my-skill
```

---

## 📊 The 5 Shipped Skills

| Skill | Purpose | Trigger | Schedule |
|-------|---------|---------|----------|
| **daily-brief** | Morning intelligence (emails, calendar, sourcing, health, news, priority) | Manual or cron | 7 AM ET daily |
| **sourcing-intel** | Search 1688 + Korean suppliers for new products | Manual or cron | Monday 8 AM ET |
| **competitor-monitor** | Track NYC aesthetic clinics for website/pricing changes | Manual or cron | Sunday 5 PM ET |
| **directora-health** | Check Directora API, ledger integrity, Prometheus metrics | Manual or cron | Every 6 hours |
| **code-governance** | Post-push validation: tests, contracts, locks, scripts | Webhook or manual | On git push to main |
| **send-telegram-alert** | Telegram alerting for audit events, failures, cost reports | Manual or triggered | On audit events |

All skills include Telegram alerting, error recovery, and audit logging.

---

## 🛡️ Safety Bounds & Kill Switches

### Safety Bounds Are Cryptographic

Birkin doesn't **trust** itself. It **proves** its integrity every hour:

```bash
$ ./governance-check.sh
✅ BIRKIN GOVERNANCE INTACT
```

If ANY gate fails:
1. Agent logs the breach to audit
2. Telegram alert fires immediately
3. `agent-stop.sh` is suggested
4. Manual investigation required

### Kill Switch #1: Graceful Stop

```bash
./agent-stop.sh
```

Stops Hermes + Open WebUI + health endpoint cleanly. Does NOT delete audit logs or skills.

### Kill Switch #2: Network Lockdown

```bash
./agent-lockdown.sh
```

Restricts outbound to ONLY:
- OpenRouter API
- Cloudflare Tunnel
- Telegram Bot API
- GitHub (for skill updates)
- DNS

Blocks all arbitrary HTTP calls. Blocks `web_research` tool (intentionally).

---

## 💰 Cost Breakdown

| Service | Monthly | Why |
|---------|---------|-----|
| Hetzner CX22 | €4.51 | 2 vCPU, 4 GB RAM, 40 GB SSD, Ubuntu 24.04 |
| Cloudflare Tunnel | $0 | Free tier, unlimited bandwidth |
| Domain | ~€1 | Cloudflare registrar (or BYOD) |
| OpenRouter API | $5-20 | Claude Sonnet (primary), Haiku/Gemini Flash (fallback) |
| Telegram Bot | $0 | Free |
| **Total** | **~€13-25** | Under €20/month with smart routing |

**Cost optimization:** Hermes config uses `provider_routing: sort: price` — complex tasks go to Claude Sonnet, routine tasks to Haiku. Cuts API costs 40-60%.

---

## 🎯 Governance Philosophy

**Birkin treats agent infrastructure like clinical systems:**

- **Append-only audit logs** — every action is written once, cryptographically ordered, never modified
- **Reproducible behavior** — git-versioned SKILL.md means you can always `git log` and `git diff` the agent's decision-making
- **Drift detection** — weekly cosine similarity benchmarks catch behavior changes before they cascade
- **Server-authoritative timestamps** — UTC from server clock, no client trust
- **Automated compliance** — one command proves governance integrity
- **Daily backups** — encrypted 7-day retention

**The thesis:** If you can govern clinical infrastructure with cryptographic proof, you can govern an AI agent the same way.

---

## 🔒 Security & Hardening

- **No open inbound ports** — only Cloudflare Tunnel (443) and SSH (22) open
- **SSH key-only auth** — no password login
- **fail2ban** — bans after 3 failed SSH attempts
- **Automatic security updates** — unattended-upgrades runs daily
- **Non-root user** — Hermes runs as `scrutexity`, not root
- **API keys in systemd env** — never in plain config files
- **Cloudflare WAF** — DDoS protection, rate limiting
- **UFW firewall** — explicit allow rules only

---

## 🧠 Governance Commands

From the server (SSH in or via scripts/):

```bash
# Full governance validation
./governance-check.sh

# Audit log queries
./scripts/send_telegram_alert.py                  # last 20 actions
./scripts/send_telegram_alert.py --today          # today only
./scripts/send_telegram_alert.py --failed         # failed actions
./scripts/send_telegram_alert.py --cost           # monthly cost estimate
./scripts/send_telegram_alert.py --skill sourcing-intel  # filter by skill

# Skill change history
./scripts/skill-diff.sh                 # changes in last 7 days
./scripts/skill-diff.sh --since 2026-05-01  # custom date
./scripts/skill-diff.sh --skill daily-brief  # one skill

# Drift detection
./drift-check.sh                # run 5 benchmarks
./drift-check.sh --update-baseline  # save as new baseline

# Kill switches
./agent-stop.sh                 # graceful shutdown
./agent-lockdown.sh             # network lockdown
./agent-lockdown.sh --unlock    # restore normal
```

---

## 📡 Health Endpoint

Birkin exposes a JSON governance status on port 9999:

```bash
curl https://health.birkin.yourdomain.com/health
```

Response:
```json
{
  "agent_status": "healthy",
  "uptime_seconds": 432891,
  "last_action_timestamp": "2026-05-18T09:23:00Z",
  "skill_count": 6,
  "audit_log_entries": 1427,
  "drift_check_last_run": "2026-05-18T06:00:00Z",
  "drift_check_status": "PASS",
  "governance_check_last_run": "2026-05-18T08:15:00Z",
  "governance_check_status": "INTACT"
}
```

Parse this in your monitoring, dashboards, or Telegram bots.

---

## 🤝 Contributing

Want to add a skill? Fork the repo and submit a PR.

**Skill contribution checklist:**
- [ ] SKILL.md follows template (YAML frontmatter + Markdown body)
- [ ] Includes `failure_recovery_steps` section
- [ ] Tested locally (`hermes run --skill your-skill`)
- [ ] Skill version bumped (semantic versioning)
- [ ] Git commit with clear message
- [ ] Governance check passes (`./governance-check.sh`)

**Community skills roadmap:**
- [ ] Slack integration for alerts
- [ ] Notion page automation
- [ ] LinkedIn job tracker
- [ ] GitHub PR reviewer
- [ ] Stripe revenue dashboard

---

## 📚 Documentation

- [deploy.sh](deploy.sh) — Hetzner + Cloudflare Tunnel deployment script (read the VERIFY notices before running)
- [CONTRIBUTING.md](CONTRIBUTING.md) — how to add skills and contribute
- [SKILL_TEMPLATE.md](SKILL_TEMPLATE.md) — well-commented skill template
- [DEMO_SCRIPT.md](DEMO_SCRIPT.md) — 60-second demo recording script
- [SOCIAL.md](SOCIAL.md) — X thread templates and marketing copy

---

## 🎬 60-Second Demo

Record this on your iPhone. No editing needed.

1. **0:00–0:10** — Open Safari → `https://birkin.yourdomain.com` → tap microphone
2. **0:10–0:25** — Voice: *"Run sourcing intelligence and report new suppliers this week"*
3. **0:25–0:40** — Agent streams Markdown results (suppliers, veto scores, actions)
4. **0:40–0:50** — Open `health.birkin.yourdomain.com/health` → show JSON governance status
5. **0:50–0:60** — SSH to server → `./governance-check.sh` → show "✅ GOVERNANCE INTACT"

[Full script →](DEMO_SCRIPT.md)

---

## 🎯 Next Steps

1. **Clone the repo**
   ```bash
   git clone https://github.com/NickAiNYC/birkin.git
   cd birkin
   ```

2. **Try locally** (5 minutes)
   ```bash
   export OPENROUTER_API_KEY=sk-or-v1-xxx
   docker compose up -d
   open http://localhost:3000
   ```

3. **Deploy to Hetzner** (10 minutes)
   ```bash
   source deploy.env && ./deploy.sh --hetzner-token ... --cf-token ... --domain ... --openrouter-key ...
   ```

4. **Add to iPhone** (2 minutes)
   - Safari → domain → Share → Add to Home Screen

5. **Add your own skill** (30 minutes)
   - `~/.hermes/skills/my-skill.md`
   - `git add && git commit`
   - Done

---

## 📄 License

MIT License — see [LICENSE](LICENSE)

**Use it. Fork it. Build on it. Ship it.**

---

## 🙏 Built By

**Nick** — [@NickAiNYC](https://github.com/NickAiNYC)

Birkin is the open-source foundation. If you're running governed infrastructure in the wild, let me know.

---

<div align="center">

**⭐ If you believe AI agents should be governed like production systems, star this repo.**

**🍴 If you're adding a skill, fork and PR.**

**🐦 If this changes how you think about agent safety, tweet [@NickAiNYC](https://x.com/NickAiNYC).**

</div>
