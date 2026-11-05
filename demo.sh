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

# Find or ensure repository-local virtualenv / editable install
if [ -d ".venv" ]; then
  # shellcheck source=/dev/null
  source .venv/bin/activate
elif [ -d "venv" ]; then
  # shellcheck source=/dev/null
  source venv/bin/activate
elif command -v birkin >/dev/null 2>&1; then
  : # birkin already in PATH
else
  PYTHON_BIN=""
  for candidate in python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      if "$candidate" -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" 2>/dev/null; then
        PYTHON_BIN="$candidate"
        break
      fi
    fi
  done

  if [ -z "$PYTHON_BIN" ]; then
    echo "ERROR: Birkin requires Python >= 3.10, but none was found in PATH." >&2
    exit 1
  fi

  echo "Setting up repository virtual environment (.venv) using $PYTHON_BIN..."
  "$PYTHON_BIN" -m venv .venv
  # shellcheck source=/dev/null
  source .venv/bin/activate
  python -m pip install --upgrade pip -q
  pip install -q -e ".[dev]"
fi

# Isolated temporary workspace for demonstration artifacts
DEMO_DIR="$(mktemp -d "${TMPDIR:-/tmp}/birkin-demo-XXXXXX")"
DEMO_OUT="${DEMO_DIR}/run_package.json"
trap 'rm -rf "${DEMO_DIR}"' EXIT

echo "1. Running authentic agent session through policy control plane..."
birkin demo --out "$DEMO_OUT"
if [ ! -s "$DEMO_OUT" ]; then
  echo "ERROR: Expected run package was not created: $DEMO_OUT" >&2
  exit 1
fi
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

