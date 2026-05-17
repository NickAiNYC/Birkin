# Birkin — Press Kit

*Last updated: May 2026*

---

## One-Sentence Description

Birkin is an open-source, self-governing AI agent that runs on a €4 server, proves its own integrity through cryptographic governance checks, and is controlled entirely from an iPhone.

---

## The 100-Word Pitch

Most AI agents are black boxes. You don't know what they did, when, or why. Birkin is different. It keeps an append-only audit log (every action, timestamped and immutable), tracks skill versions with git, runs weekly behavioral drift detection, and exposes a 5-gate governance check that proves the agent is operating within its defined boundaries. All of this runs on a €4 Hetzner server, costs €13/month total, and is accessible via iPhone PWA. The governance patterns come from clinical infrastructure — applied for the first time to personal AI. The whole thing deploys in one command and is fully open source.

---

## What Makes It Different

| Claim | Evidence |
|-------|---------|
| "Governed" is not marketing | `governance-check.sh` runs 5 gates, 9 checks, exits 1 on failure |
| Audit log is truly append-only | SQLite with `modified_at > created_at` check; tampering is detected and reported |
| Drift detection works | Cosine similarity comparison against baseline; threshold 0.85; weekly cron |
| One-command deploy is real | `install.sh` runs all 7 phases unattended; 12 minutes to a live agent |
| €13/month is accurate | Hetzner €4.51 + Cloudflare $0 + OpenRouter ~$5-20 + domain ~$1 |
| iPhone control is complete | Open WebUI PWA with voice input, Telegram push alerts, Add to Home Screen |

---

## Technical Architecture

```
iPhone (Safari PWA + Telegram)
  → Cloudflare Tunnel (free tier, no open ports)
    → Hetzner CX22 (€4.51/mo, Ubuntu 24.04)
      → Hermes v0.13.0 (port 8686) + Open WebUI (Docker, port 3000)
        → OpenRouter API (Claude Sonnet 4 + Haiku fallback)
          → Governance Layer:
              audit-log.sh     (SQLite append-only)
              skill-diff.sh    (git version tracking)
              drift-check.sh   (cosine similarity baseline)
              governance-check.sh (5-gate master validation)
              health_endpoint.py (Flask, port 9999)
```

**Lines of code:**
- `deploy.sh`: 1,086 lines, 7 phases, fully idempotent
- `governance-check.sh`: 284 lines, 5 gates, 9 checks
- Skills: 5 production SKILL.md files with YAML frontmatter

---

## Creator

**Nick Ai**
- Founder, Birkin
- Creator, Directora v1.0.0 (governed clinical infrastructure)
- GitHub: [@NickAiNYC](https://github.com/NickAiNYC)
- Location: New York City

---

## Key Links

| Resource | URL |
|----------|-----|
| GitHub | https://github.com/NickAiNYC/birkin |
| Birkin | https://scrutexity.com |
| Directora | https://directora.scrutexity.com |
| Install script | `curl -fsSL https://raw.githubusercontent.com/NickAiNYC/birkin/main/install.sh \| bash` |

---

## Angle Ideas for Writers

**"The €13 AI agent with more governance than most enterprise tools"**
Most enterprise AI deployments have no audit trail, no drift detection, and no version tracking. A solo founder built all three into a personal agent running on a €4 server.

**"The clinical governance pattern, applied to personal AI"**
The same append-only audit log and drift detection patterns used in clinical software (where failures have regulatory consequences) are now available for your personal AI agent. Birkin ports this rigor to the consumer space.

**"One command from zero to a self-governing agent"**
`curl -fsSL .../install.sh | bash` — 12 minutes, all 7 phases, governance check must pass before the install completes. This is what "production-ready" means for personal infrastructure.

**"An iPhone-controlled agent that can prove it's behaving"**
Not just controlled from an iPhone — the agent can be interrogated from an iPhone. The health endpoint returns JSON governance status on demand. The governance check can be run from a mobile SSH client. The agent sends Telegram alerts if anything goes wrong.

---

## Stats and Numbers (Accurate as of May 2026)

- Deploy time: ~12 minutes from zero to live agent
- Governance gates: 5
- Checks per gate run: 9 total
- Skills (production, shipping): 5
- Monthly cost: €10–25 (depending on API usage)
- Server cost: €4.51/month (Hetzner CX22)
- Lines in deploy.sh: 1,086
- Lines in governance-check.sh: 284
- Cosine similarity drift threshold: 0.85
- Audit log: append-only SQLite, monotonic timestamps
- Hermes version: v0.13.0 "Tenacity"

---

## What Birkin Is Not

- **Not a product.** It's open-source infrastructure for technical users.
- **Not a managed service.** You run it on your own server. You own your data.
- **Not a replacement for supervised clinical systems.** The governance patterns are inspired by clinical infrastructure, not certified for clinical use.
- **Not a demo.** The deploy.sh is the actual deploy script. The governance check is the actual governance check. This is what runs in production.

---

## Usage Rights

Birkin is MIT licensed. You may:
- Clone and deploy for personal use
- Fork and build your own governed agent
- Reference the code in articles, talks, and blog posts
- Use the governance patterns in your own projects (attribution appreciated)

---

## Contact

For press inquiries, interview requests, or technical questions:
- **GitHub:** Open an issue at [github.com/NickAiNYC/birkin](https://github.com/NickAiNYC/birkin)
- **Email:** Available via GitHub profile

---

*Birkin is personal infrastructure. It is not a company, does not have investors, and does not have a commercial roadmap. It's an engineer's answer to the question: what does a governed personal AI agent actually look like?*
