---
name: sourcing-intel
description: |
  Use when the user asks to check 1688 or Korean sourcing pipelines, find new suppliers,
  run weekly sourcing intelligence, check OEM manufacturers, or evaluate peptide/raw material suppliers.
  Triggers: "sourcing intelligence", "1688 search", "Korean suppliers", "OEM factory", "peptide supplier",
  "red light therapy OEM", "PEMF OEM", "microcurrent OEM", "GMP factory China", "tradeKorea".
version: 1.0.0
created_date: 2026-05-17
platforms: [linux]
metadata:
  hermes:
    tags: [sourcing, procurement, 1688, korea, oem, medical-devices, peptides]
    category: procurement
    requires_toolsets: [web_research, file, messaging]
    fallback_for_toolsets: []
    config:
      - key: sourcing.directora_endpoint
        description: "Directora health endpoint for supplier vetting"
        default: "https://health.scrutexity.com"
        prompt: "Enter your Directora health endpoint URL"
---

# Sourcing Intelligence Skill

## When to Use
- Weekly automated sourcing pipeline check (triggered by cron every Monday 9 AM)
- User asks: "check 1688 for new suppliers", "run sourcing intel", "find peptide OEMs"
- Any request involving Chinese or Korean medical/aesthetic device or raw material sourcing

## Search Terms (1688 — Chinese B2B)
Execute these exact searches using web_search tool:
1. `site:1688.com 红光治疗仪 OEM`
2. `site:1688.com 红光面罩 批发`
3. `site:1688.com PEMF 理疗仪 OEM`
4. `site:1688.com 肽原料 GMP 工厂`
5. `site:1688.com 微针仪 OEM`
6. `site:1688.com 308nm 光疗仪 OEM`
7. `site:1688.com 射频美容仪 OEM`
8. `site:1688.com 超声刀 美容仪器 OEM`

## Korean Pipeline
1. Search `tradeKorea.com medical aesthetic device exporter 2026`
2. Search `KIMES 2026 exhibitor list aesthetic device`
3. Search `Korea medical device export deal announcement 2026`
4. Search `site:news.google.com Korean aesthetic clinic device export`

## Birkin Supplier Veto Checklist (6 Criteria)
For each candidate supplier, evaluate:
1. **Business License Valid** — Can verify 营业执照 or Korean business registration
2. **GMP/ISO Certified** — Factory holds relevant medical device manufacturing certification
3. **Export Experience** — Has shipped to US/EU/major markets (not just domestic)
4. **MOQ Realistic** — Minimum order quantity under $10,000 for initial test
5. **No Litigation/Blacklist** — No FDA warning letters, no major quality recalls
6. **Communication Responsive** — Replies to inquiry within 48 hours

## Procedure
1. Run all 8 Chinese search terms + 4 Korean search terms via web_search
2. For each result, extract: product name, supplier name, platform, URL, price hint (if visible)
3. Apply Veto Checklist — mark PASS/FAIL/UNKNOWN for each of 6 criteria
4. Flag any supplier scoring 5+ PASS as "PRIORITY CONTACT"
5. Flag any supplier scoring 3-4 PASS as "FURTHER DUE DILIGENCE"
6. Flag any supplier scoring <3 PASS as "VETOED"
7. Cross-reference with Directora health endpoint if available (optional API call)

## Output Format
Generate a Markdown table:

```markdown
| Product | Supplier | Platform | Veto Score | Status | Action |
|---------|----------|----------|------------|--------|--------|
| 红光治疗仪 300W | 深圳XX医疗 | 1688 | 5/6 | PRIORITY | Send inquiry, request FDA 510(k) doc |
```

Also generate a summary paragraph with:
- Total suppliers found
- Priority count
- Vetoed count  
- Top 3 recommended next actions

## Failure Recovery Steps
1. If web_search fails (rate limit), wait 60s and retry with `site:alibaba.com` fallback
2. If 1688 blocks scraping, use `site:made-in-china.com` as secondary source
3. If Korean sources are empty, expand to `site:globalsources.com Korea medical`
4. If Directora endpoint is unreachable, skip cross-reference and note "Directora offline"
5. On total failure: save partial results to `~/briefs/sourcing-failed-YYYY-MM-DD.md` and alert via Telegram
