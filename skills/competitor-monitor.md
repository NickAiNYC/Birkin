---
name: competitor-monitor
description: |
  Use when the user asks to track competitors, monitor NYC aesthetic clinics, check competitor websites,
  detect pricing changes, or run a weekly competitor diff report. Triggers: "competitor monitor",
  "track clinics", "pricing changes", "new services", "weekly diff", "competitor intelligence",
  "aesthetic clinic NYC", "Google Business Profile changes".
version: 1.0.0
created_date: 2026-05-17
platforms: [linux]
metadata:
  hermes:
    tags: [competitive-intelligence, nyc, aesthetic, clinics, monitoring, diff]
    category: intelligence
    requires_toolsets: [web_research, file, messaging]
    fallback_for_toolsets: []
    config:
      - key: monitor.competitors
        description: "Comma-separated list of competitor clinic domains"
        default: ""
        prompt: "Enter competitor clinic domains to monitor"
---

# Competitor Monitor Skill

## When to Use
- Weekly automated competitor tracking (triggered by cron every Sunday 6 PM)
- User asks: "what are competitors doing", "check clinic X website", "pricing changes this week"
- Any request about NYC aesthetic clinic competitive landscape

## Target Competitors (Default Set)
Monitor these 5 NYC aesthetic clinics (expandable via config):
1. `kinemd.com` — Kinesiology + aesthetics hybrid
2. `skinney.com` — Skinney Medspa (NYC multi-location)
3. `tribecamedspa.com` — Tribeca Medspa
4. `everbody.com` — Ever/Body (tech-forward aesthetic chain)
5. `aldaesthetics.com` — ALDA Aesthetics

## What to Detect
For each competitor, check:
1. **New Services/Treatments** — New pages under /services/, /treatments/, or menu changes
2. **Pricing Changes** — Any price listed on treatment pages (capture before/after)
3. **New Providers/Staff** — New doctor/nurse practitioner listings on /team/ or /providers/
4. **New Locations** — Expansion announcements, new address listings
5. **Promotions** — New offers, package deals, membership programs
6. **Technology Upgrades** — New device mentions (e.g., "now offering Morpheus8", "newest laser")

## Procedure
1. Use web_search to find the current homepage and key subpages of each competitor
2. Use web_search with `site:DOMAIN` to discover new pages indexed since last check
3. Check Google Business Profile via `search "COMPETITOR_NAME" "Google Business"` for review changes, new photos, Q&A updates
4. Compare against baseline stored in `~/.hermes/drift/competitor-baseline-YYYY-MM-DD.json`
5. If no baseline exists, create one and report "Initial baseline established"

## Output Format
Weekly diff report as Markdown:

```markdown
# Competitor Diff Report — YYYY-MM-DD

## kinemd.com
- **NEW**: Added "EMSCulpt Neo" service page (detected via site:kinemd.com EMSCulpt)
- **PRICE CHANGE**: Botox unit price $14 -> $16 (page /botox-nyc/)
- **NEW PROVIDER**: Dr. Sarah Chen added to team page
- **SIGNIFICANCE**: HIGH — entering body contouring market, price hike signals demand

## skinney.com
- **NO CHANGES** since last check
- **SIGNIFICANCE**: LOW

## Summary
- Total changes: 3
- High significance: 1
- Recommended action: Research EMSCulpt Neo supplier; consider competitive pricing response
```

## Failure Recovery Steps
1. If a competitor site blocks scraping, use Google cache: `cache:DOMAIN/page`
2. If Google Business data is unavailable, check Yelp business page as secondary
3. If baseline file is corrupted, regenerate from current state and alert "baseline reset"
4. If all 5 competitors are unreachable, save report as `~/briefs/competitor-failed-YYYY-MM-DD.md` and alert
