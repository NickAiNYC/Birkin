# Contributing to Birkin

Birkin is local-first, MIT-licensed, and built around one rule: the
credibility surface must stay closed. Most of this document is about
what that rule means in practice.

## The short version

1. Run `bash scripts/ci_smoke.sh` before you push. If it fails, the
   release is red. No exceptions.
2. Two test files are **sacred**. Read the rule below before touching them.
3. Adding features is fine. Weakening the verifier is not.
4. Keep the scope locks in the README. Multi-bot groups, full MCP
   gateway, and Attack Lab productization are *next cycle*, not this
   one. Do not pull them in piecemeal.

## Sacred tests

The following files encode the closed credibility surface that makes
Birkin worth taking seriously:

* `tests/test_tamper_matrix.py` — six realistic tampering attacks; every
  one must verify as `TAMPERED` or `INVALID`, never `AUTHENTIC`.
* `tests/test_receipt_binding.py` — twelve receipt fields, each
  cryptographically bound into the signed material; mutating any one
  field alone must invalidate the signature.

### The rule

> **No PR may merge if it removes, weakens, skips, or modifies a test in
> these two files in a way that accepts a previously-rejected mutation
> as `AUTHENTIC`.**

Concretely, the following changes are **release blockers** and require
a written design discussion before they are even attempted:

* Deleting or `pytest.skip`-ing any test in the two sacred files.
* Changing a test's assertion from `== "TAMPERED"` to anything weaker.
* Adding a mutation to the matrix and asserting it verifies as
  `AUTHENTIC` (this is the most insidious form — it looks like a new
  test, but it actually opens the surface).
* Removing a field from `AuthorizationReceipt.SIGN_FIELDS` so it is
  no longer covered by the receipt signature.
* Removing or weakening verifier check #8 (`Identity bound to run`)
  or check #0 (`Manifest + schema versions`).
* Relaxing `PolicySpec.evaluate`'s default-deny behavior so an
  unrecognized tool can pass without an explicit `allow` rule.

### When the rule is in tension with a feature

If a future feature genuinely requires a mutation that currently
verifies as `TAMPERED` to verify as `AUTHENTIC` — for example, a
multi-bot governance model where receipts are intentionally shared
across agents — that is a **design change**, not a test fix.

The right sequence is:

1. Open a design discussion (issue, not a PR).
2. Propose a new schema version (e.g. `birkin.receipt@2`) and a new
   manifest entry. Old verifiers continue to refuse the new packages
   rather than silently misinterpreting them.
3. Update the sacred tests to assert the *new* expected behavior, with
   a comment linking to the design discussion.
4. Bump `PACKAGE_MANIFEST["verifier_min_version"]` and document the
   migration.

The sacred tests are not in the way of progress. They are the
load-bearing wall. Move them deliberately, never by accident.

## Local-first

Birkin does not phone home. PRs that introduce network calls in the
core engine, the verifier, or the default policy will be rejected.
Network calls belong in adapters, behind the `AgentAdapter` seam.

## Adapters, not wrappers

A new runtime does not get folded into the engine. It gets a new
adapter under `birkin/adapters/` that implements the `AgentAdapter`
Protocol. `NullAgentAdapter` is the reference minimal implementation;
`HermesAdapter` is the reference real implementation. A new adapter
should be smaller than Hermes and clearer than NullAgent.

## CI

`.github/workflows/ci.yml` runs `scripts/ci_smoke.sh` on every push and
PR. The smoke gate is fail-fast and covers:

1. `pytest tests/`
2. `birkin demo` → `VERDICT: AUTHENTIC`
3. `birkin verify` on the exported package → `AUTHENTIC`
4. `birkin attack 1` (prompt injection) → blocked + `AUTHENTIC`
5. `birkin attack 2` (privilege escalation) → all three decisions + `AUTHENTIC`
6. `birkin attack 3` (tampering) → clean `AUTHENTIC`, tampered `TAMPERED`
7. `NullAgent` second-adapter proof → `AUTHENTIC`

If you add a feature, add a smoke-gate step that proves it. If you
cannot add such a step, the feature does not belong in this cycle.

## Licensing

All contributions are MIT-licensed. By submitting a PR you agree your
contributions are licensed under the project's MIT license.
