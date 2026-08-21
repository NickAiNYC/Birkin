# Birkin Roadmap

Birkin's roadmap is driven by concrete failure modes in agentic AI security — not speculation, just engineering. Each tier closes specific attack surface identified in [THREAT_MODEL.md](THREAT_MODEL.md).

---

## Tier 1: Closing Critical Gaps

*Target: Weeks 1–2*

These items close the most severe gaps in the current threat model.

| Item | Closes | Status |
|------|--------|--------|
| **Remote Chain Tip Attestation** | Full DB replacement attack — posts chain tip hash to Telegram/Nostr hourly so a wholesale replacement produces a detectable tip mismatch | Open |
| **Structured Audit Schema** | Log is currently unstructured JSON payload — adds `action_type`, `resource`, `parameters_hash` columns for queryable compliance exports | Open |
| **Compliance Export** | CSV/JSON export with embedded chain tip hash for auditors and SIEM integration | Open |
| **Governance Webhooks** | POST governance failures to PagerDuty/Datadog in real time; right now failures only go to Telegram | Open |

**Dependency:** Remote Chain Tip Attestation is the highest-priority item. It closes the only unmitigated attack vector from THREAT_MODEL.md.

---

## Tier 2: The Gatekeeper

*Target: Weeks 3–4 | Requires Tier 1 complete*

This tier converts Birkin from an audit layer into a control plane.

| Item | Description | Status |
|------|-------------|--------|
| **HITL Proxy** | Deterministic risk classifier intercepts high-risk agent actions before they execute. Telegram approval flows with configurable timeout/deny policy. Zero overhead on low-risk actions. | Open |
| **Supply Chain Skill Signing** | GPG-signed SKILL.md files. Governance check verifies signatures. Closes the skill injection attack vector. | Open |
| **Audit Log Encryption** | AES-256-GCM encryption at rest. Multi-user ready with per-user keys. | Open |

**Dependency:** HITL Proxy requires Structured Audit Schema (Tier 1) so risk decisions are loggable with structured metadata.

---

## Tier 3: Enterprise Hardening

*Target: After Tier 2 | Requires Tier 2 complete*

| Item | Description | Status |
|------|-------------|--------|
| **RBAC Per Skill** | Skills declare required permissions in YAML frontmatter. Governance check enforces them. Least-privilege for agent actions. | Open |
| **Semantic Drift Detection** | Embedding-based similarity to complement bigram cosine similarity. Catches reasoning drift that preserves surface vocabulary. | Open |
| **Distributed Merkle Anchoring** | Merkle tree anchored to Certificate Transparency log. Survives single-witness compromise. | Open |
| **Multi‑Agent Governance** | Extend to multiple Hermes instances with cross-referenceable audit chains. | Open |

---

## Dependency Graph

```
Structured Audit Schema (T1)
    └── Compliance Export (T1)
    └── HITL Proxy (T2)
            └── RBAC Per Skill (T3)

Remote Chain Tip Attestation (T1)
    └── Distributed Merkle Anchoring (T3)

Governance Webhooks (T1)
    └── [standalone — no T2 dependency]

Supply Chain Skill Signing (T2)
    └── [standalone within T2]

Audit Log Encryption (T2)
    └── [standalone within T2]
```

---

## Contributing to Roadmap Items

See [CONTRIBUTING.md](CONTRIBUTING.md) for good-first-issue tickets that directly unblock Tier 1 and Tier 2 items.

If you want to take on a full roadmap item, open an issue first to discuss the design — especially for anything touching the audit schema or hash chain.
