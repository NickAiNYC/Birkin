# Birkin Threat Model

This document describes what the Birkin audit chain protects against, what it does not protect against, the verification methodology, and known limitations.

---

## What the Hash Chain Catches

The audit log is a SQLite table where each row stores:

```
row_hash = SHA-256( prev_row_hash || payload_json )
```

`verify-chain.py` walks every row in insertion order, recomputes each hash, and compares it to the stored value.

### Attacks that verification detects

**Row-level mutation** — any change to a row's payload (agent action, timestamp, parameters) breaks the hash of that row and every subsequent row.

**Row mutation after triggers are disabled** — the SQLite triggers (`BEFORE UPDATE`, `BEFORE DELETE`) enforce append-only at the database layer. An attacker who bypasses them via direct file-level writes (e.g. SQLite CLI, `sqlite3` binary) still cannot rewrite history undetected, because the hash chain is independent of the trigger mechanism. This is demonstrated concretely by `tests/tamper-test.sh`: the test drops all triggers, mutates a row, then calls `verify-chain.py` — which still detects the mutation.

**Row deletion** — deleting a row breaks the chain for all rows following it.

**Row insertion into the middle** — inserting a row between two existing rows recomputes hashes from that point forward, which is detectable by comparing any stored snapshot of the chain's tip hash.

---

## What the Hash Chain Does Not Catch

**Attacker controls the process before logging** — if an attacker can modify `audit-append.py` or the Hermes skill before an action is logged, they can forge a legitimate-looking chain entry. The chain proves that logged entries were not mutated after the fact; it does not prove that every agent action was logged in the first place.

**Attacker replaces the entire database** — if the `audit.db` file is replaced wholesale (rather than mutated), `verify-chain.py` will verify the replacement chain as valid. Mitigation: periodically record the chain tip hash out-of-band (e.g. Telegram alert with current tip hash, external monitoring endpoint).

**Log omission** — an agent action that is never written to the log cannot be detected by chain verification. This is a logging completeness problem, not a chain integrity problem.

**Verification tool compromise** — if `verify-chain.py` itself is modified to skip or silently pass broken chains, verification is meaningless. Mitigation: pin the scripts in git and check `git status` / `git diff` on the scripts directory.

**Insider / root access** — an attacker with root access can modify the SQLite file, replace the verification script, and overwrite the entire audit directory before you check. Birkin is not designed to defend against a fully compromised host.

**Behavioral accuracy** — the chain proves that a logged entry was not modified after writing. It does not prove that what was written accurately reflects what the agent actually did (e.g. a skill that logs "sourcing completed" but did nothing).

---

## Verification Methodology

### Automated (CI)

`tests/tamper-test.sh` runs in GitHub Actions on every push:

1. Creates a fresh in-memory SQLite database with the audit schema and triggers
2. Appends 5 hash-chained rows via `scripts/audit-append.py`
3. Verifies the clean chain (expected: PASS)
4. Attempts an `UPDATE` through the normal interface (expected: trigger blocks it)
5. Drops all triggers and directly rewrites row 3 via SQLite
6. Runs `scripts/verify-chain.py` (expected: CHAIN BROKEN detected)

The test exits non-zero if any step produces an unexpected result. The CI badge on the README reflects the last run.

### Manual

```bash
./tests/tamper-test.sh        # full tamper simulation
python3 scripts/verify-chain.py --db ~/.hermes/audit.db   # verify live chain
```

---

## Policy Engine Threat Model (Filesystem, Network, & HITL Lifecycle)

Birkin's policy engine (`birkin/policy.py`) evaluates tool invocations against structured rules prior to execution. The threat model defines defenses against common bypass techniques:

### 1. Filesystem Containment & Traversal Defense

| Attack Vector | Vulnerability Description | Birkin Mitigation |
| :--- | :--- | :--- |
| **Sibling-Prefix Collision** | Naive `norm_path.startswith(prefix)` matches `/tmp/birkin-unsafe` against allowed `/tmp/birkin`. | Component-aware containment via `Path.is_relative_to()` enforces strict ancestor tree membership. |
| **Directory Traversal** | Payload `/tmp/birkin/../../etc/shadow` escapes sandbox via relative dot-dot segments. | Normalized and canonical path resolution collapses segments before checking boundary ancestry. |
| **Symlink Escapes** | An attacker creates a symlink `/tmp/birkin/link_sys` pointing to `/etc`. | Both lexical paths AND canonical targets (`Path.resolve(strict=False)`) are evaluated. For `allow` rules, both lexical and resolved paths must stay within the boundary. For `deny` rules, triggering either lexical or resolved targets blocks execution. |
| **Relative / Unanchored Paths** | Candidate path `"relative/file.txt"` submitted against absolute sandbox `/tmp/birkin/`. | Absolute prefixes strictly reject relative candidates, preventing ambient `cwd` alias matching. Fails closed. |
| **Malformed Paths & Loops** | Embedded null bytes (`\x00`), empty paths, or circular symlinks (`a -> b -> a`). | Exception handling catches `ValueError`, `OSError`, `RuntimeError`, immediately failing closed to default deny. |

### 2. Time-of-Check to Time-of-Use (TOCTOU) Limitations

Policy evaluation verifies path containment at authorization time. If local directory contents or symlinks are swapped concurrently by an untrusted actor between authorization and syscall execution, a TOCTOU race can occur.

**Remediation & Defense-in-Depth:**
- Full mitigation against hostile local users requires OS-level primitives like `openat2(..., RESOLVE_BENEATH)` or Linux mount namespaces / cgroups at the execution runtime layer.
- Birkin guarantees that authorization receipts are cryptographically bound to the checked arguments (`args_hash`), and execution is refused if arguments or identity are tampered.

### 3. Human-in-the-Loop (HITL) State Machine Integrity

Actions requiring human approval (`require_approval`) produce an signed intermediate receipt:

- **Identity & Session Binding:** `engine.approve()` and `engine.reject()` verify that `receipt.agent_id` and `receipt.session_id` match the requesting caller. An approval or rejection cannot be hijacked by another agent or session.
- **Cryptographic Signature Validation:** The engine verifies its own control-plane signature before allowing any state transition on a receipt.
- **Non-Reusable State Transitions:** Once a receipt is approved or rejected, its `receipt_id` is permanently marked resolved. Attempting duplicate approvals, duplicate rejections, or cross-transitioning (approve after reject) raises an immediate `ValueError`.
- **Argument Integrity at Execution:** `engine.execute()` verifies that `sha256(canonical_json(request.args))` matches `receipt.args_hash`. Presenting an approved receipt with modified tool arguments triggers an immediate `execution.refused` alert.

---

## Known Limitations

**Single-machine trust boundary.** The audit log and the agent run on the same host. An attacker who owns the host owns both. Birkin is appropriate for personal agents and teams where you trust the infrastructure operators; it is not a substitute for a tamper-evident log backed by an independent write endpoint or a distributed ledger.

**SQLite file permissions.** The database is protected by OS-level file permissions. On a single-user system this is reasonable; in a multi-user or container environment, ensure `audit.db` is not world-writable.

**Drift detection covers 5 benchmarks.** Behavioral changes in areas not covered by the benchmark set will not be flagged. The benchmark set is tuned for general instruction-following stability, not domain-specific accuracy. See [README.md#drift-detection](README.md#drift-detection) for the full question set.

**No remote attestation.** The chain tip hash is not automatically published to an external witness. To close this gap manually, record the tip hash periodically via Telegram alerts or a separate monitoring endpoint.

**Governance check requires Hermes to be running.** If Hermes is down, Gates 1, 4, and 5 fail. This is a liveness check failure, not a security failure, but it means governance-check.sh is not a useful tool for post-mortem analysis on a stopped agent.

---

## Out of Scope

The following are not goals of Birkin's current security model:

- Protecting against a compromised Hermes binary
- Preventing prompt injection attacks on the agent
- Rate-limiting or content-filtering agent outputs
- Compliance certification (SOC 2, HIPAA, etc.)
