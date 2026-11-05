#!/usr/bin/env bash
# Birkin 60-Second Reproducible Demonstration
# Proves: policy-controlled tool execution, Ed25519 authorization receipts,
# offline cryptographic verification, and adversarial tamper detection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================================"
echo "  Birkin — 60-Second Reproducible Demonstration"
echo "  Agent Authorization & Cryptographic Evidence Layer"
echo "============================================================"
echo ""

# Find or ensure virtualenv / editable install
if [ -d "/Users/nick/infini/venv" ]; then
  # shellcheck source=/dev/null
  source /Users/nick/infini/venv/bin/activate
elif command -v birkin >/dev/null 2>&1; then
  : # birkin already in PATH
else
  echo "Installing birkin locally in temporary virtual environment..."
  python3 -m venv .demo_venv
  # shellcheck source=/dev/null
  source .demo_venv/bin/activate
  pip install -q -e ".[dev]"
fi

DEMO_OUT="/tmp/birkin-demo-run.json"

echo "1. Running authentic agent session through policy control plane..."
birkin demo --out "$DEMO_OUT"
echo ""

echo "2. Verifying package offline (zero network calls, standalone Ed25519 & hash chain)..."
birkin verify "$DEMO_OUT"
echo ""

echo "3. Simulating Attack 1 (Prompt injection / goal hijacking)..."
birkin attack 1
echo ""

echo "4. Simulating Attack 3 (Tampering with ledger flips verdict to TAMPERED)..."
birkin attack 3
echo ""

echo "============================================================"
echo "  ✓ Demonstration Complete"
echo "  Policy Enforced. Receipts Signed. Tampering Caught."
echo "============================================================"
