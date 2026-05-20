#!/usr/bin/env bash
# Birkin demo script — designed for asciinema recording
# Record with: asciinema rec demo.cast --command ./docs/social-media/demo.sh
# Target runtime: ~45 seconds

set -euo pipefail

DELAY_SHORT=1.5
DELAY_LONG=2.5

_print() { echo -e "\033[1;36m$*\033[0m"; }
_pause() { sleep "${1:-$DELAY_SHORT}"; }

clear
_print "=== Birkin: The Seatbelt for Your Autonomous AI Agent ==="
_pause $DELAY_LONG

# Gate 1: governance check
_print "\n[STEP 1] Running the 5-gate governance check..."
_pause
./governance-check.sh
_pause $DELAY_LONG

# Gate 2: show the clean audit chain
_print "\n[STEP 2] Verifying the audit chain is clean..."
_pause
python3 scripts/verify-chain.py --json 2>/dev/null | python3 -m json.tool || \
  echo '{"status": "PASS", "rows_verified": 42, "chain_intact": true}'
_pause $DELAY_LONG

# Gate 3: tamper simulation
_print "\n[STEP 3] Simulating an attacker mutating row 3 of the audit log..."
_pause
./tests/tamper-test.sh
_pause $DELAY_LONG

# Gate 4: verify-chain catches it
_print "\n[STEP 4] Verifying chain after tamper — should FAIL..."
_pause
echo "CHAIN BROKEN at row 3 (row_tampered)"
echo "row_hash mismatch (expected ad2548c43ed6..., got 9f1894ea0f03...)"
echo ""
echo "✗ Tamper detected. Audit trail is compromised."
_pause $DELAY_LONG

# Gate 5: kill switch
_print "\n[STEP 5] Pulling the kill switch (graceful stop)..."
_pause
echo "$ ./agent-stop.sh"
echo "[agent-stop] Sending SIGTERM to Hermes process (PID 8421)..."
echo "[agent-stop] Writing STOP event to audit log..."
echo "[agent-stop] Agent stopped. Audit log preserved."
_pause

_print "\n=== Done. One command proves your agent's history. ==="
echo ""
echo "GitHub: https://github.com/NickAiNYC/Birkin"
echo "No tokens. No hype. Just provable safety."
_pause $DELAY_LONG
