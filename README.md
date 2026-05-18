<div align="center">
  <img alt="Birkin — tamper-evident audit log for autonomous agents" src="assets/birkin-banner.png" width="900" />
</div>

# Birkin

**A tamper-evident audit log for autonomous agents. One command proves it.**

[![Tamper Test](https://github.com/NickAiNYC/Birkin/actions/workflows/tamper-test.yml/badge.svg)](https://github.com/NickAiNYC/Birkin/actions/workflows/tamper-test.yml)
![License](https://img.shields.io/badge/license-MIT-blue)
![Topics](https://img.shields.io/badge/topics-ai--agent%20%7C%20audit--log%20%7C%20hash--chain%20%7C%20hermes%20%7C%20governance-lightgrey)

Birkin wraps a running [Hermes Agent](https://hermes-agent.nousresearch.com/) with a **SHA-256 hash-chained SQLite audit log**, a 5-gate governance check, an iPhone PWA, and kill switches — without modifying your Hermes install.

---

## The Tamper Test

Most audit logs are append-only by convention. Birkin's is hash-chained at the row level: every row stores `SHA-256(prev_hash || payload)`. Mutate a single byte anywhere in the chain and verification fails, even if database triggers were disabled first.

<div align="center">
  <img alt="Birkin tamper-test demo" src="static/tamper-demo.gif" width="700" />
</div>

Run it yourself:

```bash
./tests/tamper-test.sh
```

```text
Birkin tamper-detection test
[1/6]  schema initialized (table + triggers)
[2/6]  appended 5 hash-chained rows
[3/6]  clean chain verifies PASS
[4/6]  trigger blocks UPDATE (append-only enforced at DB layer)
[5/6]  simulated attacker: dropped triggers, rewrote row 3
[6/6]  tamper DETECTED by hash chain:
       CHAIN BROKEN at row 3 (row_tampered)
       row_hash mismatch (expected ad2548c43ed6..., got 9f1894ea0f03...)

PASS — hash chain catches mutation even when triggers are bypassed.
```

Source: [`scripts/audit-init.sql`](scripts/audit-init.sql) · [`scripts/audit-append.py`](scripts/audit-append.py) · [`scripts/verify-chain.py`](scripts/verify-chain.py) · [`tests/tamper-test.sh`](tests/tamper-test.sh)

For a full description of what this protects against and what it does not, see [THREAT_MODEL.md](THREAT_MODEL.md).

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/NickAiNYC/Birkin/main/install.sh | bash
```

Or clone and compose directly:

```bash
git clone https://github.com/NickAiNYC/Birkin && cd Birkin
HERMES_URL=http://host.docker.internal:8686 docker compose up -d
```

Then open `http://localhost:3000` in Safari on your iPhone → **Share → Add to Home Screen**.

---

## What It Ships

- **Hash-chained audit log** — SHA-256 chain, append-only triggers, tamper test in CI
- **5-gate governance check** — process, audit integrity, skill versioning, drift, health
- **iPhone PWA** — Open WebUI configured to talk to your Hermes, installable from Safari
- **Drift detection** — 5 deterministic benchmark questions, bigram cosine similarity, 0.85 threshold (see [Drift Detection](#drift-detection))
- **Kill switches** — `agent-stop.sh` (graceful), `agent-lockdown.sh` (network lockdown)
- **Telegram alerts** — optional, fires on governance failure
- **6 example SKILL.md files** — templates for daily-brief, sourcing-intel, competitor-monitor, health-check, code-governance, and Telegram alerting

## What It Does Not Ship

- Hermes Agent itself — bring your own ([hermes-agent.nousresearch.com](https://hermes-agent.nousresearch.com/))
- An LLM key — your Hermes already has one
- A hosted service — runs on your machine; your data stays local

Runs on a laptop, Raspberry Pi, or free-tier VPS. Optional `deploy.sh` provisions a Hetzner box with Cloudflare Tunnel for phone access outside your LAN (~€4.51/mo).

---

## How to Get Your Hermes API Key

The `HERMES_API_KEY` Birkin needs is the `API_SERVER_KEY` from your Hermes config — not your model provider key.

```bash
# Check if you already have one
grep API_SERVER_KEY ~/.hermes/.env

# If missing, generate one
echo "API_SERVER_KEY=$(openssl rand -hex 16)" >> ~/.hermes/.env
```

Confirm `~/.hermes/config.yaml` has the API server enabled:

```yaml
platforms:
  api_server:
    enabled: true
    port: 8686
```

Restart Hermes and verify: `curl http://localhost:8686/health -H "Authorization: Bearer $API_SERVER_KEY"` should return `{"status": "ok"}`.

---

## Governance Check

```bash
./governance-check.sh
```

```
[1/5] Hermes Gateway     — running, API responding
[2/5] Audit Integrity    — append-only, monotonic timestamps, 0 tampered entries
[3/5] Skill Versioning   — git-tracked, all changes committed, 6 skills deployed
[4/5] Drift Detection    — 5 benchmarks stable (cosine similarity >= 0.85)
[5/5] Health Endpoint    — JSON governance status, uptime 14 days

BIRKIN GOVERNANCE INTACT
```

If any gate fails, the agent logs the breach, fires a Telegram alert, and suggests a stop.

---

## Architecture

Birkin sits between you and your existing Hermes Agent:

```
              YOUR HERMES AGENT
              (anywhere, any host)
                     |
                     | OpenAI-compatible /v1
                     v
        ┌──────────────────────────────────┐
        │            BIRKIN                │
        │  Open WebUI      Governance      │
        │  (Docker)        Layer           │
        │  iPhone PWA      SHA-256 audit   │
        │  Voice input     Drift check     │
        │                  Kill switches   │
        │  Health Endpoint /health JSON    │
        └──────────────────────────────────┘
                     |
                     v
                YOUR iPHONE
```

---

## Drift Detection

Gate 4 runs 5 deterministic benchmark questions against your Hermes instance and compares responses to a stored baseline using bigram cosine similarity:

**Benchmark set:**
1. "What is the capital of France?"
2. "Explain the concept of an append-only audit log in one sentence."
3. "List three principles of governed AI agent infrastructure."
4. "What does PHI stand for in healthcare technology?"
5. "Describe the difference between a hash chain and a Merkle tree in one sentence."

**Methodology:** bigram cosine similarity between current and baseline response. Pass threshold: 0.85. Temperature is forced to 0 for determinism.

**What it catches:** model swaps, config changes that shift output style, unexpected behavior changes after a Hermes upgrade.

**What it does not catch:** subtle reasoning changes that preserve surface similarity, or drift in areas not covered by the 5 benchmarks.

```bash
./drift-check.sh                     # compare to baseline
./drift-check.sh --update-baseline   # save new baseline after intentional change
./drift-check.sh --threshold 0.90    # stricter threshold
```

Baseline stored at `~/.hermes/drift/baseline.json`. Update it after any intentional model or config change.

---

## Kill Switches

```bash
./agent-stop.sh        # graceful stop — does not delete logs or skills
./agent-lockdown.sh    # restrict outbound to: OpenRouter, Cloudflare, Telegram, GitHub, DNS
./agent-lockdown.sh --unlock
```

---

## Optional: Deploy to VPS (~€4.51/mo)

For PWA access outside your LAN, `deploy.sh` provisions a Hetzner CX22 + Cloudflare Tunnel:

```bash
source deploy.env && ./deploy.sh \
  --hetzner-token "$HETZNER_TOKEN" \
  --cf-token      "$CF_TOKEN"      \
  --domain        "$DOMAIN"        \
  --openrouter-key "$OPENROUTER_KEY"
```

Read the `VERIFY:` comments at the top of `deploy.sh` before running — this path is alpha.

---

## Skills

The repo ships 6 SKILL.md files as templates. Drop into `~/.hermes/skills/` and edit for your own services:

| Skill | Purpose | Default trigger |
|-------|---------|-----------------|
| **daily-brief** | Morning intelligence summary | Cron 7 AM ET |
| **sourcing-intel** | Search suppliers for new products | Cron Monday 8 AM ET |
| **competitor-monitor** | Track competitor website/pricing changes | Cron Sunday 5 PM ET |
| **directora-health** | External API health check (template) | Every 6 hours |
| **code-governance** | Post-push validation: tests, locks, scripts | Git push webhook |
| **send-telegram-alert** | Telegram alerting helper | On audit events |

See [SKILL_TEMPLATE.md](SKILL_TEMPLATE.md) for the schema. Skills are git-versioned; `git diff` the agent's behavior at any point.

---

## Health Endpoint

```bash
curl http://localhost:9999/health
```

```json
{
  "agent_status": "healthy",
  "uptime_seconds": 432891,
  "audit_log_entries": 1427,
  "drift_check_status": "PASS",
  "governance_check_status": "INTACT"
}
```

---

## Governance Commands Reference

```bash
./governance-check.sh                          # full 5-gate check
./drift-check.sh                               # behavioral drift check
./agent-stop.sh                                # graceful shutdown
./agent-lockdown.sh                            # network lockdown
./scripts/skill-diff.sh                        # skill changes last 7 days
./scripts/skill-diff.sh --since 2026-05-01     # custom date range
```

---

## Threat Model

See [THREAT_MODEL.md](THREAT_MODEL.md) for a complete description of:
- What attacks the hash chain catches
- What it explicitly does not catch
- Verification methodology
- Known limitations

---

## Contributing

Skill contribution checklist:
- [ ] SKILL.md follows template (YAML frontmatter + Markdown body)
- [ ] Includes `failure_recovery_steps`
- [ ] Tested locally (`hermes run --skill your-skill`)
- [ ] Version bumped (semantic versioning)
- [ ] Governance check passes (`./governance-check.sh`)

---

## Documentation

- [THREAT_MODEL.md](THREAT_MODEL.md) — what the chain catches and what it doesn't
- [CONTRIBUTING.md](CONTRIBUTING.md) — how to add skills
- [SKILL_TEMPLATE.md](SKILL_TEMPLATE.md) — annotated skill template
- [deploy.sh](deploy.sh) — Hetzner + Cloudflare Tunnel (read VERIFY notices first)

---

## License

MIT — see [LICENSE](LICENSE)

Built by **Nick** — [@NickAiNYC](https://github.com/NickAiNYC)
