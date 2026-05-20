"""
risk_classifier.py — Deterministic rule-based risk classification for HITL proxy.

No LLM calls. Pattern matching only. Returns LOW / MEDIUM / HIGH.
  LOW    → pass through immediately (<1ms)
  MEDIUM → pass through + async Telegram alert
  HIGH   → hold for human approval via Telegram inline keyboard
"""
import re
import yaml
import os
from dataclasses import dataclass
from enum import Enum
from typing import Any


class RiskLevel(str, Enum):
    LOW    = "LOW"
    MEDIUM = "MEDIUM"
    HIGH   = "HIGH"

    def __ge__(self, other):
        order = {RiskLevel.LOW: 0, RiskLevel.MEDIUM: 1, RiskLevel.HIGH: 2}
        return order[self] >= order[other]

    def __gt__(self, other):
        order = {RiskLevel.LOW: 0, RiskLevel.MEDIUM: 1, RiskLevel.HIGH: 2}
        return order[self] > order[other]


@dataclass
class ClassificationResult:
    level:          RiskLevel
    matched_rule:   str | None
    matched_text:   str | None


_PHI_PATTERNS = [
    r"\bssn\b", r"\bsocial security\b",
    r"\b\d{3}-\d{2}-\d{4}\b",          # SSN format
    r"\bdate of birth\b", r"\bdob\b",
    r"\bmedical record\b", r"\bdiagnosis\b",
    r"\bpatient (name|id|record)\b",
    r"\bhipaa\b",
]

_COMPILED_PHI = [re.compile(p, re.IGNORECASE) for p in _PHI_PATTERNS]

_DEFAULT_RULES = [
    {"pattern": r"tool_call:\s*delete_file",    "level": "HIGH"},
    {"pattern": r"tool_call:\s*rm\b",           "level": "HIGH"},
    {"pattern": r"tool_call:\s*exec\b",         "level": "HIGH"},
    {"pattern": r"external_api:\s*.+",          "level": "MEDIUM"},
    {"pattern": r"phi:\s*.+",                   "level": "HIGH"},
    {"pattern": r"send_email",                  "level": "MEDIUM"},
    {"pattern": r"send_message",                "level": "MEDIUM"},
    {"pattern": r"write_file",                  "level": "MEDIUM"},
    {"pattern": r"database.*drop",              "level": "HIGH"},
    {"pattern": r"DROP\s+TABLE",                "level": "HIGH"},
]


def _load_rules(config_path: str | None = None):
    if config_path and os.path.exists(config_path):
        with open(config_path) as f:
            cfg = yaml.safe_load(f)
        rules = cfg.get("risk_rules", [])
        default_level = cfg.get("default_level", "LOW")
    else:
        rules = _DEFAULT_RULES
        default_level = "LOW"
    compiled = [(re.compile(r["pattern"], re.IGNORECASE), RiskLevel(r["level"]))
                for r in rules]
    return compiled, RiskLevel(default_level)


def _extract_text(request_body: dict[str, Any]) -> str:
    """Pull all readable text out of a chat completion request body."""
    parts = []
    for msg in request_body.get("messages", []):
        content = msg.get("content", "")
        if isinstance(content, str):
            parts.append(content)
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    parts.append(block.get("text", ""))
    return "\n".join(parts)


class RiskClassifier:
    def __init__(self, config_path: str | None = None):
        self._rules, self._default = _load_rules(config_path)

    def classify(self, request_body: dict[str, Any]) -> ClassificationResult:
        text = _extract_text(request_body)
        if not text:
            return ClassificationResult(self._default, None, None)

        highest = self._default
        matched_rule = None
        matched_text = None

        # Check PHI patterns first (always HIGH)
        for pattern in _COMPILED_PHI:
            m = pattern.search(text)
            if m:
                return ClassificationResult(RiskLevel.HIGH, "phi_detection", m.group(0))

        # Check configured rules
        for compiled, level in self._rules:
            m = compiled.search(text)
            if m and level >= highest:
                highest = level
                matched_rule = compiled.pattern
                matched_text = m.group(0)
                if highest == RiskLevel.HIGH:
                    break  # Can't go higher

        return ClassificationResult(highest, matched_rule, matched_text)
