---
name: directora-health
description: |
  Use when the user asks about Directora system health, wants to check the ledger integrity,
  verify audit chain, check sign latency, or monitor Directora infrastructure. Triggers:
  "Directora health", "check Directora", "ledger integrity", "audit verify", "sign latency",
  "409 rate", "503 events", "Directora status", "health check Directora".
version: 1.0.0
created_date: 2026-05-17
platforms: [linux]
metadata:
  hermes:
    tags: [directora, health-monitoring, ledger, audit, governance, infrastructure]
    category: devops
    requires_toolsets: [web_research, file, messaging]
    fallback_for_toolsets: []
    config:
      - key: directora.base_url
        description: "Directora deployment base URL"
        default: "https://directora.scrutexity.com"
        prompt: "Enter your Directora base URL"
      - key: directora.prometheus_url
        description: "Prometheus metrics endpoint"
        default: ""
        prompt: "Enter Prometheus /metrics URL (optional)"
---

# Directora Health Watch Skill

## When to Use
- Automated health check (triggered every 6 hours via cron)
- User asks: "how is Directora doing", "check system health", "ledger integrity"
- Any request about Directora infrastructure, uptime, or governance state

## Health Checks
Execute these checks in order:

### 1. Basic Health Endpoint
```
GET ${directora.base_url}/health
```
Expected: HTTP 200, JSON with `status: "ok"` or `status: "healthy"`
Alert if: HTTP != 200, response time > 2s, or status != healthy

### 2. Ledger Hash-Chain Integrity
```
GET ${directora.base_url}/api/labs/audit/verify
```
Expected: HTTP 200, `integrity: "valid"`, `chain_intact: true`
Alert if: integrity != valid, chain_intact != true, or HTTP != 200
This is CRITICAL — a broken chain indicates tampering or corruption

### 3. Prometheus Metrics (if configured)
```
GET ${directora.prometheus_url}/metrics
```
Look for:
- `sign_latency_seconds` — alert if p99 > 500ms
- `http_requests_total{status="409"}` — alert if rate > 5/min over 10min window
- `http_requests_total{status="503"}` — alert if any 503 in last hour
- `jwt_revocation_check_duration_seconds` — alert if > 100ms

### 4. Governance Proof Verification
```
GET ${directora.base_url}/api/governance/proof
```
Expected: HTTP 200, valid JWKS signature, timestamp within 5 minutes of server time
Alert if: signature invalid, timestamp drift > 5 min, or HTTP != 200

## Alert Thresholds
| Metric | Warning | Critical |
|--------|---------|----------|
| /health response time | > 1s | > 3s or non-200 |
| Ledger chain intact | — | false |
| Sign latency p99 | > 300ms | > 800ms |
| 409 rate | > 2/min | > 10/min |
| 503 events | any in 1h | > 5 in 1h |
| Governance proof age | > 2 min | > 5 min |

## Output Format
```markdown
# Directora Health Report — YYYY-MM-DD HH:MM UTC

## Status Summary
- Overall: ✅ HEALTHY / ⚠️ DEGRADED / ❌ CRITICAL

## Checks
| Check | Status | Detail |
|-------|--------|--------|
| /health | ✅ 200 (180ms) | All systems operational |
| Ledger Chain | ✅ Valid | 1,247 entries, hash intact |
| Sign Latency p99 | ⚠️ 420ms | Above 300ms threshold |
| 409 Rate | ✅ 0/min | No conflicts |
| 503 Events | ✅ 0 | No backpressure events |
| Governance Proof | ✅ Valid | Age: 45s |

## Action Required
- [ ] Investigate sign latency spike (check PostgreSQL connection pool)
```

## Failure Recovery Steps
1. If /health fails, retry once after 10s; if still failing, mark CRITICAL and alert immediately
2. If ledger verify fails, DO NOT retry automatically — this is a governance event. Alert CRITICAL and log to audit
3. If Prometheus is unreachable, skip metrics section and note "Prometheus offline"
4. If all checks fail (network partition), save report locally and queue alert for when Telegram recovers
5. On any CRITICAL alert, send Telegram message with full report and tag @NickAiNYC
