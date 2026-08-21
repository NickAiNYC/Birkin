#!/usr/bin/env python3
"""
Run the entire Birkin vertical slice in one shot:

  $ python3 scripts/demo_all.py

Runs the end-to-end demo (AUTHENTIC) and all three attacks (each blocked,
recorded, and verifiable). Total runtime < 60 seconds.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from demos.end_to_end import run_demo
from demos.attacks import (
    attack_1_prompt_injection,
    attack_2_privilege_escalation,
    attack_3_policy_tampering,
)


def main() -> int:
    print()
    print("#" * 60)
    print("# BIRKIN — UNDENIABLE VERTICAL SLICE")
    print("#" * 60)
    print()
    run_demo(show_events=True)
    print()
    attack_1_prompt_injection()
    attack_2_privilege_escalation()
    attack_3_policy_tampering()
    print("#" * 60)
    print("# Slice complete.")
    print("#" * 60)
    return 0


if __name__ == "__main__":
    sys.exit(main())
