# Contributing to Birkin

Birkin welcomes two kinds of contributions: **skills** (agent behavior files) and **core features** (governance infrastructure). Both paths are documented here.

---

## Good First Issues

These are well-scoped, self-contained, and unblock higher-priority roadmap work:

| Issue | Label | What it unlocks |
|-------|-------|-----------------|
| Add risk patterns to HITL classifier | `good-first-issue` | Tier 2 gatekeeper (pre-execution gatekeeping) |
| Create systemd service file for Birkin | `good-first-issue` | Native Linux installs without Docker |
| Add Homebrew formula | `good-first-issue` | macOS one-line install |
| Write `--json` output for governance-check.sh | `good-first-issue` | Governance webhooks and CI integration |
| Add `action_type` column to audit schema | `good-first-issue` | Structured audit schema (Tier 1 roadmap) |
| Write CSV/JSON compliance export script | `good-first-issue` | Compliance export (Tier 1 roadmap) |
| Add PagerDuty/Datadog webhook on governance failure | `good-first-issue` | Governance webhooks (Tier 1 roadmap) |

See [ROADMAP.md](ROADMAP.md) to understand how each item unblocks the next tier.

---

## Contributing a Skill

### 1. Fork and clone

```bash
git clone https://github.com/NickAiNYC/Birkin.git && cd Birkin
```

### 2. Create your skill file

```bash
cp SKILL_TEMPLATE.md skills/your-skill-name.md
```

Fill in the YAML frontmatter:

```yaml
---
name: your-skill-name
description: What it does and when to trigger it
version: 1.0.0
triggers:
  - cron: "0 9 * * *"   # optional
  - manual
tools_needed:
  - web_search
  - file_write
failure_recovery_steps:
  - "If X fails, check Y"
  - "Manually trigger: hermes run --skill your-skill-name"
---
```

### 3. Write the skill body

Clear numbered steps. Assume the agent needs explicit instructions — no hand-waving.

### 4. Test it

```bash
hermes run --skill your-skill-name
```

### 5. Run governance gates (all 5 must pass)

```bash
./governance-check.sh
```

### 6. Submit a PR

One skill per PR. Include what the skill does and the `governance-check.sh` output in the PR description.

#### Skill PR checklist

- [ ] SKILL.md follows template (YAML frontmatter + Markdown body)
- [ ] Includes at least two `failure_recovery_steps`
- [ ] Tested locally (`hermes run --skill your-skill-name`)
- [ ] Version set to `1.0.0` (semantic versioning)
- [ ] All 5 governance gates pass (`./governance-check.sh`)

---

## Contributing Core Features

For governance infrastructure (audit schema, governance check gates, drift detection, kill switches):

1. Open an issue first — especially for anything touching the audit schema or hash chain logic
2. Link to the relevant ROADMAP.md tier so reviewers understand the dependency graph
3. All hash-chain changes must include a tamper-test update in `tests/tamper-test.sh`
4. All governance-check gate changes must update the gate description in README.md

---

## Skill Ideas

- Slack message summarizer
- Notion page creator
- LinkedIn job tracker
- GitHub PR reviewer
- Stripe revenue daily summary
- Email draft responder
- Calendar prep (next-meeting briefing)
- Weather + commute alert
- Hacker News thread monitor

---

## What Gets Merged

1. Governance-compliant YAML frontmatter
2. At least two documented failure recovery steps
3. All 5 gates passing (`./governance-check.sh`)
4. Skill not already shipped

For core features: follows the roadmap dependency graph and includes tests.

Questions: open an issue or tweet [@NickAiNYC](https://x.com/NickAiNYC).
