# Birkin — Implementation Status (November 2026)

This document honestly catalogs the implementation status, verified capabilities, security posture, and deferred roadmap items of the Birkin project.

---

## 1. Security Plane & Policy Status

| Component | Status | Verified Capability | Tests / Evidence |
| :--- | :---: | :--- | :--- |
| **Fail-Closed Policy Engine** | **Production** | Path-component-aware containment, sibling-prefix collision defense, symlink traversal resolution, relative path domain enforcement, fail-closed handling | `policy.py`, `test_policy_enforcement_threat_model.py` |
| **Ed25519 Receipt Signing** | **Production** | Canonical JSON serialization, 12 cryptographically bound fields | `models.py`, `crypto.py`, `test_receipt_binding.py` |
| **Tamper-Evident Audit Ledger** | **Production** | SHA-256 forward-chained events, Merkle root checkpoints | `audit.py`, `test_tamper_matrix.py`, `tests/tamper-test.sh` |
| **Offline Verification CLI** | **Production** | 9-point offline verification (`birkin verify`) with zero server dependency | `verify.py`, `scripts/ci_smoke.sh` |
| **Human-in-the-Loop (HITL) Controls**| **Production** | Requesting-identity binding, cryptographic signature verification, duplicate transition prevention (`approve`/`reject`), argument hash binding on execution | `engine.py`, `test_policy_enforcement_threat_model.py` |
| **INFINI Action Gateway** | **Production** | Decoupled pre-action step authorization gateway | `adapters/infini_gateway.py`, `test_infini_integration.py` |
| **Hermes Adapter** | **Demonstration**| In-process tool registry demonstrating interception seam (`fs.write`, `shell.exec`) | `adapters/hermes.py`, `demos/end_to_end.py` |
| **NullAgent Adapter** | **Production** | Reference minimal adapter proving the AgentAdapter contract | `adapters/null_agent.py`, `test_null_adapter.py` |

---

## 2. Verified Test Suites & CI Gates

- **Unit & Security Suite (`pytest tests/`):** 56 tests passing.
- **Threat-Model Policy Suite (`test_policy_enforcement_threat_model.py`):** 14/14 tests passing (sibling-prefix collisions, symlink escapes, relative path rejection, malformed paths, symlink cycles, HITL identity/duplicate enforcement, args hash verification).
- **Tamper Detection Matrix (`tests/test_tamper_matrix.py`):** 7/7 attacks caught (signature flip, identity rewrite, policy swap, checkpoint rewrite, missing event, reordered event).
- **SQLite Hash-Chain Tamper Test (`bash tests/tamper-test.sh`):** 6/6 tests passing (trigger bypass detection, row rewrite detection).
- **CI Smoke Gate (`bash scripts/ci_smoke.sh`):** 7/7 vertical slice checks passing.

---

## 3. Security Limits & Threat Assumptions

1. **In-Process Boundary:** Birkin intercepts tool dispatches at the Python adapter layer. It does not replace OS-level cgroups, containers, or hypervisors. If an agent executes raw un-intercepted C extensions or sub-processes bypassing the adapter, Birkin cannot restrict them.
2. **Local Cryptographic Integrity vs. Storage Immutability:** Hash chains detect tampering retrospectively during offline verification; they do not physically prevent a root administrator from modifying or deleting local disk files.
3. **Filesystem Race Conditions (TOCTOU):** Policy evaluation checks path containment prior to execution. If symlinks or directory entries are swapped concurrently by an untrusted process between authorization and syscall execution, a TOCTOU race can occur. Full defense requires OS-level primitives like `openat2(..., RESOLVE_BENEATH)` or container mount namespaces at the runtime layer.
4. **Demonstration vs. Distributed Production:** The Hermes adapter is an in-process tool registry proving the policy interception seam. Production distributed Hermes deployments require network transport adapters.

---

## 4. Deliberately Deferred Enhancements

1. **Asynchronous Webhook-Based HITL Dashboard:** Currently HITL approvals are handled via deterministic API/CLI methods (`engine.approve`, `engine.reject`). A full web-based approval dashboard with Slack/PagerDuty webhooks is deferred to maintain a zero-external-dependency posture.
2. **Automated Key Rotation Protocols:** Ed25519 keypairs are generated per-session or loaded from environment variables. Automated KMS/Vault HSM key rotation protocols are deferred for enterprise deployment plugins.

