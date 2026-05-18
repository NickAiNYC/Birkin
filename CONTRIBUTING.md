# Contributing to Birkin

Skills are the only thing worth contributing. Everything else is personal config.

---

## Adding a Skill

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

One skill per PR. Include what the skill does and the `governance-check.sh` output.

---

## Skill ideas (things I'd actually use)

- Slack message summarizer
- Notion page creator
- LinkedIn job tracker
- GitHub PR reviewer
- Stripe revenue daily summary
- Email draft responder
- Calendar prep (next-meeting briefing)
- Weather + commute alert
- Hacker News thread monitor
- Crypto portfolio snapshot

---

## What gets merged

1. Governance-compliant YAML frontmatter
2. At least two documented failure recovery steps
3. All 5 gates passing (`./governance-check.sh`)
4. Adds a skill that isn't already shipped

Questions: open an issue or tweet [@NickAiNYC](https://x.com/NickAiNYC).
