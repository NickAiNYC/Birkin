---
# ─── REQUIRED FRONTMATTER ─────────────────────────────────────────────────────
#
# name: The unique identifier for this skill. Use kebab-case.
#        Must match the filename (e.g., skill name "my-skill" → my-skill.md).
#        This is what you say to trigger the skill: "run my-skill"
#
name: your-skill-name

# description: Tells Hermes WHEN to use this skill. Write it as "Use when..."
#              Include trigger phrases the user might say. Be specific.
#              Hermes uses this to route incoming requests — vague descriptions
#              mean the skill gets invoked at the wrong time.
#
description: |
  Use when the user asks about [topic] or says [trigger phrases].
  Triggered automatically [if scheduled]. Triggers: "[phrase1]", "[phrase2]",
  "[phrase3]".

# version: Semantic version. Increment MINOR for new features, PATCH for fixes.
#          MAJOR changes (breaking behavior changes) should reset to X.0.0.
#          This is checked by governance-check.sh gate 3.
#
version: 1.0.0

# created_date: ISO 8601 date (YYYY-MM-DD). Set once, never change.
#
created_date: 2026-05-17

# updated_date: Update this every time you bump the version.
#
updated_date: 2026-05-17

# platforms: Where this skill runs. Usually [linux].
#
platforms: [linux]

# ─── HERMES METADATA ──────────────────────────────────────────────────────────
metadata:
  hermes:
    # tags: Keywords for discoverability. Used in future skill marketplace search.
    tags: [tag1, tag2, tag3]

    # category: One of: productivity, monitoring, research, communication,
    #           governance, data, infrastructure, personal
    category: productivity

    # requires_toolsets: Hermes toolsets this skill needs.
    # Options: web_research, file, messaging, code, calendar, email, database
    requires_toolsets: [web_research]

    # schedule: Cron expression if this skill runs automatically. Leave empty
    #           if manual-only. Uses server timezone (UTC by default).
    # Examples:
    #   "0 7 * * *"        → Every day at 7 AM UTC
    #   "0 9 * * 1"        → Every Monday at 9 AM UTC
    #   "0 */6 * * *"      → Every 6 hours
    #   ""                 → Manual only
    schedule: ""

    # config: Environment-specific settings the user must configure.
    #         These become prompts during skill setup.
    config:
      - key: your_skill.setting_one
        description: "Brief description of what this setting does"
        default: ""
        prompt: "Enter [what to enter]:"

      # Add more config keys as needed:
      # - key: your_skill.setting_two
      #   description: "..."
      #   default: "false"
      #   prompt: "..."
---

# [Your Skill Name] Skill

<!--
GOVERNANCE NOTE: This file is under git version control.
Every change must be committed. governance-check.sh gate 3 will fail
if there are uncommitted changes to skills.

Commit convention:  skill-name: short description (vX.Y.Z)
Example:            my-skill: add error handling for empty results (v1.0.1)
-->

## When to Use

<!-- 
One paragraph. Be specific about conditions. Include:
- What triggers this skill (user phrases, scheduled events)
- What the skill produces (outputs, side effects)
- What it does NOT do (helps Hermes avoid false positives)
-->

Use this skill when the user asks about [specific topic] or requests [specific output].
This skill [produces X] by [doing Y]. It does not [do Z — clarify what's out of scope].

## Prerequisites

<!--
List everything that must be true before this skill runs.
Hermes will check these and fail gracefully if they're not met.
-->

- [ ] `[ENV_VAR]` must be set (see `.env.example`)
- [ ] [External service] must be accessible
- [ ] [Other condition]

## Procedure

<!--
Step-by-step instructions. Hermes follows these literally.
Be explicit. Don't assume context. Use numbered steps.
Each step should be a single, verifiable action.
-->

### Step 1: [First major action]

[Detailed instruction for Hermes. What to fetch, where to look, what to do with the result.]

```
[Example command or API call if relevant]
```

### Step 2: [Second major action]

[Instruction.]

### Step 3: [Third major action]

[Instruction.]

### Step 4: Format and deliver output

Structure the response as:

```
[SKILL NAME] — [date/time]

[SECTION 1 HEADER]
  [Content]

[SECTION 2 HEADER]
  [Content]

[ACTION ITEMS]
  [List of required actions, if any]
```

## Output Format

<!--
Describe exactly what the output looks like. Include an example.
If output is sent via Telegram, describe the Telegram message format.
-->

**Console/Chat output:**
```
[Your Skill Name] — [timestamp]

[Example output section]
  • Item one
  • Item two

[Another section]
  Status: [value]
```

**Telegram alert (if triggered):**
```
[EMOJI] SKILL NAME — [timestamp]
[Brief summary for push notification]
Action: [What user should do, if anything]
```

## Failure Recovery Steps

<!--
REQUIRED for governance-check.sh. This section must exist.
List specific recovery actions for each failure mode.
Be concrete — "check the logs" is not a recovery step.
-->

### If [Step 1] fails:
1. Verify `[ENV_VAR]` is correctly set: `echo $ENV_VAR`
2. Test connectivity: `curl -v [endpoint]`
3. Check [service] status: `[command]`
4. If all else fails: [fallback action]

### If [Step 2] fails:
1. [Specific action]
2. [Specific action]

### If [external API] returns an error:
1. Log the error to audit: `./scripts/audit-log.sh --write --skill "your-skill" --status failed --detail "[error]"`
2. Send Telegram alert if configured
3. Skip gracefully and note in output: "⚠️ [Service] unavailable — [section] skipped"

### If the skill produces no results:
1. Verify the query parameters are correct
2. Check if [source] has changed format
3. Return an informative message rather than empty output

## Changelog

<!--
One line per version. Most recent first.
This is what governance-check.sh skill-diff shows.
-->

| Version | Date | Change |
|---------|------|--------|
| 1.0.0 | 2026-05-17 | Initial release |

---

<!--
GOVERNANCE REMINDER:
After editing this file, you MUST commit it:
  cd ~/.hermes/skills
  git add your-skill-name.md
  git commit -m "your-skill-name: [description] (vX.Y.Z)"

Then verify:
  ./scripts/governance-check.sh

Gate 3 will flag any uncommitted changes as a warning.
-->
