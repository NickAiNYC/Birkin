"""Threat-model-driven security tests for Birkin policy enforcement and HITL lifecycle."""
from __future__ import annotations

import os
from pathlib import Path
import pytest

from birkin import (
    Engine,
    NullAgentAdapter,
    SigningKey,
    load_default_policy,
    PolicySpec,
    ActionRequest,
    AuthorizationReceipt,
)


def _setup_engine(policy_spec: PolicySpec | None = None) -> tuple[Engine, any, any]:
    sk = SigningKey.generate()
    p = policy_spec or load_default_policy()
    adapter = NullAgentAdapter()
    engine = Engine(birkin_signing_key=sk, policy=p, adapter=adapter)
    identity = adapter.make_identity(agent_id="security-agent", policy_ref=p.ref)
    engine.start_session(identity)
    return engine, identity, adapter


def test_path_traversal_blocked():
    """Path traversal sequences (e.g., ../../etc/passwd) must be normalized and not match sandbox prefixes."""
    engine, identity, adapter = _setup_engine()

    # Attempting to escape /tmp/birkin/ using relative directory traversal
    traversal_path = "/tmp/birkin/../../etc/shadow"
    req = adapter.build_action_request(tool="fs.write", args={"path": traversal_path, "data": "evil"})
    receipt = engine.attempt_action(identity, req)

    # Must be denied (by system deny rule), NEVER allowed
    assert receipt.decision == "deny", (
        f"PATH TRAVERSAL VULNERABILITY: path {traversal_path} was granted {receipt.decision} under rule {receipt.rule}"
    )
    assert receipt.rule in ("fs.write.system.deny", "default.deny")


def test_sandbox_write_allowed():
    """Legitimate writes inside the sandbox are allowed."""
    engine, identity, adapter = _setup_engine()

    clean_path = "/tmp/birkin/sandbox_output.txt"
    req = adapter.build_action_request(tool="fs.write", args={"path": clean_path, "data": "clean"})
    receipt = engine.attempt_action(identity, req)

    assert receipt.decision == "allow"
    assert receipt.rule == "fs.write.sandbox.allow"


def test_host_spoofing_in_query_param_blocked():
    """Urls containing trusted hosts in query params must not bypass host matching."""
    policy_dict = {
        "name": "network_policy",
        "version": "1.0.0",
        "rules": [
            {
                "id": "http.trusted.allow",
                "match": {"tool": "http.get", "host_in": ["internal.api.corp"]},
                "decision": "allow",
                "risk_score": 20,
            },
            {
                "id": "http.default.deny",
                "match": {"tool": "http.get"},
                "decision": "deny",
                "risk_score": 90,
            },
        ],
    }
    policy = PolicySpec.from_dict(policy_dict)
    engine, identity, adapter = _setup_engine(policy)

    # Attacker host with trusted host in query parameter
    malicious_url = "https://attacker.com/steal?target=internal.api.corp"
    req = adapter.build_action_request(tool="http.get", args={"url": malicious_url})
    receipt = engine.attempt_action(identity, req)

    assert receipt.decision == "deny"
    assert receipt.rule == "http.default.deny"


def test_hitl_approval_lifecycle_granted():
    """Test human-in-the-loop: require_approval -> approval granted -> execution allowed."""
    engine, identity, adapter = _setup_engine()

    # An action that requires approval under default policy (e.g. fs.write outside sandbox in /home/)
    req = adapter.build_action_request(tool="fs.write", args={"path": "/home/user/export.csv", "data": "row1"})
    receipt = engine.attempt_action(identity, req)
    assert receipt.decision == "require_approval"

    # Execution is refused without approval
    res, ev = engine.execute(identity, req, receipt)
    assert res is None
    assert ev.payload["alert"] == "execution.refused"

    # Human grants approval
    approved_receipt = engine.approve(
        identity,
        receipt,
        approved_by="secops@corp.internal",
        reason="Verified business need for one-time export",
    )
    assert approved_receipt.decision == "allow"
    assert approved_receipt.verify(engine.birkin_signing_key.public_b64)

    # Execution now succeeds
    res_approved, ev_approved = engine.execute(identity, req, approved_receipt)
    assert res_approved is not None
    assert ev_approved.type == "tool.executed"


def test_hitl_approval_lifecycle_rejected():
    """Test human-in-the-loop: require_approval -> approval rejected -> execution denied."""
    engine, identity, adapter = _setup_engine()

    req = adapter.build_action_request(tool="fs.write", args={"path": "/home/user/config.json", "data": "{}"})
    receipt = engine.attempt_action(identity, req)
    assert receipt.decision == "require_approval"

    # Explicit rejection
    rejected_receipt = engine.reject(
        identity,
        receipt,
        rejected_by="secops@corp.internal",
        reason="Unauthorized configuration modification attempt",
    )
    assert rejected_receipt.decision == "deny"
    assert rejected_receipt.verify(engine.birkin_signing_key.public_b64)

    # Execution is refused
    res_rejected, ev_rejected = engine.execute(identity, req, rejected_receipt)
    assert res_rejected is None
    assert ev_rejected.payload["alert"] == "execution.refused"
