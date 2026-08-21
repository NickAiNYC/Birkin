"""
birkin.policy
============

The Birkin Policy Engine.

This is *not* a shell script. It is a structured rule evaluator that, given
a (tool, args) request, returns a :class:`PolicyDecision` containing the
``decision``, the ``policy`` (name@version), the ``rule`` id that fired, a
``risk_score`` in [0, 100], and a human-readable ``reason``.

Policy spec format
------------------
A policy is a JSON document::

    {
      "name": "default",
      "version": "1.0.0",
      "description": "...",
      "rules": [
        {
          "id": "shell.exec.deny",
          "match": {"tool": "shell.exec"},
          "decision": "deny",
          "risk_score": 90,
          "reason": "Shell execution forbidden by default policy"
        },
        ...
      ]
    }

Rule matching
-------------
Rules are evaluated top-down. The first rule whose ``match`` predicate
succeeds wins. ``match`` supports:

* ``tool``     — exact tool name (or list of names)
* ``args``     — dict of {arg_name: literal_value OR {"$in": [...]}}
* ``path_prefix`` — list of path prefixes; matched against ``args["path"]``
* ``host_in``  — list of host substrings; matched against ``args["url"]``
* ``runtime_in`` — list of runtime strings; matched against the identity

If no rule matches, the engine returns a synthetic default-deny decision
with ``risk_score=100`` so the run cannot proceed silently.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from .crypto import sha256_hex, canonical_json
from .models import PolicyDecision


class PolicySpec:
    """In-memory representation of a loaded policy file."""

    def __init__(self, spec: dict[str, Any]) -> None:
        if "name" not in spec or "version" not in spec or "rules" not in spec:
            raise ValueError("Policy spec must have name, version, rules")
        self.name: str = spec["name"]
        self.version: str = spec["version"]
        self.description: str = spec.get("description", "")
        self.rules: list[dict[str, Any]] = spec["rules"]
        self._raw = spec

    # --- loading --------------------------------------------------------
    @classmethod
    def load(cls, path: str | Path) -> "PolicySpec":
        path = Path(path)
        with path.open("r", encoding="utf-8") as fh:
            return cls(json.load(fh))

    @classmethod
    def from_dict(cls, spec: dict[str, Any]) -> "PolicySpec":
        return cls(spec)

    # --- introspection --------------------------------------------------
    @property
    def ref(self) -> str:
        return f"{self.name}@{self.version}"

    @property
    def sha256(self) -> str:
        return sha256_hex(canonical_json(self._raw))

    def to_dict(self) -> dict[str, Any]:
        return self._raw

    # --- evaluation -----------------------------------------------------
    def evaluate(
        self,
        *,
        tool: str,
        args: dict[str, Any] | None = None,
        runtime: str | None = None,
        identity_public_key: str | None = None,
    ) -> PolicyDecision:
        args = args or {}
        for rule in self.rules:
            if _match_rule(rule.get("match", {}), tool=tool, args=args, runtime=runtime):
                return PolicyDecision(
                    decision=rule.get("decision", "deny"),
                    policy=self.ref,
                    rule=rule.get("id", "unnamed"),
                    risk_score=int(rule.get("risk_score", 100)),
                    reason=rule.get("reason", "Matched rule"),
                )
        # No rule matched. Default deny. We do NOT silently allow.
        return PolicyDecision(
            decision="deny",
            policy=self.ref,
            rule="default.no_match",
            risk_score=100,
            reason=f"No rule matched tool={tool!r} under policy {self.ref}",
        )


# --------------------------------------------------------------------------- #
# Matching primitives
# --------------------------------------------------------------------------- #
def _match_rule(
    match: dict[str, Any],
    *,
    tool: str,
    args: dict[str, Any],
    runtime: str | None,
) -> bool:
    if not match:
        return True  # empty match = always matches (used for default rules)

    tool_match = match.get("tool")
    if tool_match is not None:
        if isinstance(tool_match, str):
            if tool != tool_match:
                return False
        elif isinstance(tool_match, list):
            if tool not in tool_match:
                return False
        else:
            return False

    runtime_match = match.get("runtime_in")
    if runtime_match is not None:
        if runtime is None or not any(r in runtime for r in runtime_match):
            return False

    args_match = match.get("args")
    if args_match is not None:
        for k, v in args_match.items():
            actual = args.get(k)
            if isinstance(v, dict) and "$in" in v:
                if actual not in v["$in"]:
                    return False
            else:
                if actual != v:
                    return False

    path_prefix = match.get("path_prefix")
    if path_prefix is not None:
        path = args.get("path")
        if not isinstance(path, str):
            return False
        if not any(path.startswith(p) for p in path_prefix):
            return False

    host_in = match.get("host_in")
    if host_in is not None:
        url = args.get("url", "") or ""
        if not any(h in url for h in host_in):
            return False

    # Negative matchers (allow-list / deny-list)
    path_not_prefix = match.get("path_not_prefix")
    if path_not_prefix is not None:
        path = args.get("path", "")
        if any(path.startswith(p) for p in path_not_prefix):
            return False

    return True


# --------------------------------------------------------------------------- #
# Helper: ensure policy dir exists
# --------------------------------------------------------------------------- #
DEFAULT_POLICY_PATH = os.environ.get(
    "BIRKIN_POLICY",
    str(Path(__file__).resolve().parent.parent / "policies" / "default.policy.json"),
)


def load_default_policy() -> PolicySpec:
    return PolicySpec.load(DEFAULT_POLICY_PATH)


__all__ = ["PolicySpec", "PolicyDecision", "DEFAULT_POLICY_PATH", "load_default_policy"]
