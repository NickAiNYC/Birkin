# Contributing to Birkin

Want to add your own skill? It's 30 minutes. Here's how.

---

## The Skill Marketplace

Birkin ships with 5 production skills. We're building a community-driven marketplace.

**Wanted community skills:**
- [ ] Slack integration (post updates to Slack)
- [ ] Notion automation (log results to Notion)
- [ ] LinkedIn job tracker (monitor job postings)
- [ ] GitHub PR reviewer (automated code review)
- [ ] Stripe revenue dashboard (daily summary)
- [ ] Email summarizer (digest newsletters)
- [ ] Calendar optimizer (identify meeting overload)
- [ ] Competitor pricing tracker (monitor SaaS pricing)
- [ ] Hacker News alerts (monitor industry discussions)

---

## How to Add a Skill (30 minutes)

### Step 1: Clone the repo (2 min)

```bash
git clone https://github.com/NickAiNYC/birkin.git
cd birkin
```

### Step 2: Create your SKILL.md (10 min)

```bash
cat > skills/my-skill.md <<'SKILL'
---
name: my-skill
description: Brief description of what this skill does
version: 1.0.0
triggers:
  - cron: "0 9 * * *"
    description: Daily at 9 AM UTC
  - manual
tools_needed:
  - web_search
  - file_write
failure_recovery_steps:
  - "Check API connectivity: curl https://api.example.com"
  - "Verify credentials in ~/.hermes/.env"
  - "Re-run: hermes run --skill my-skill"
---

# My Skill

## Overview
What does this skill do? (2-3 sentences)

## Execution
1. Step one
2. Step two
3. Deliver results

## Delivery
Where do results go? (Telegram, file, etc.)

## Error Handling
- If X fails, do Y
- If Z fails, do W
SKILL
```

### Step 3: Test it locally (10 min)

```bash
hermes run --skill my-skill
./scripts/governance-check.sh  # Should pass 9/9 gates
```

### Step 4: Submit PR (5 min)

```bash
git add skills/my-skill.md
git commit -m "Add my-skill v1.0.0 — [brief description]"
git push origin main
```

Open a PR with this template:

```
## Skill: my-skill v1.0.0

### What it does
[One sentence]

### Governance
- Triggers: [cron / manual]
- Tools: [list]
- Error recovery: [yes/no]
- Gates passing: ✅ 9/9

### Testing
- [x] Tested locally
- [x] governance-check.sh passes
- [x] Ready to ship
```

---

## Governance Checklist

- [ ] Skill has YAML frontmatter (name, description, version, triggers, tools_needed, failure_recovery_steps)
- [ ] Skill has clear overview + execution steps
- [ ] No hardcoded secrets (use ~/.hermes/.env)
- [ ] Error handling covers ≥2 failure scenarios
- [ ] ./scripts/governance-check.sh passes 9/9
- [ ] Git commit message is clear
- [ ] No uncommitted changes

---

## Review Criteria

We merge if:
1. ✅ Governance compliant
2. ✅ Error handling documented
3. ✅ Adds value beyond the 5 shipped skills
4. ✅ All gates passing

---

## Questions?

Open an issue: [github.com/NickAiNYC/birkin/issues](https://github.com/NickAiNYC/birkin/issues)

Or tweet [@NickAiNYC](https://x.com/NickAiNYC)

---

**Every shipped skill makes Birkin stronger.**

⭐ Star this repo if you believe in agent governance.

