#!/bin/bash
# =============================================================================
# drift-check.sh — Weekly drift detection for agent behavior consistency
# Version: 1.0.0 | Scrutexity Agent Governance Layer
# Usage: ./drift-check.sh [--baseline PATH | --update-baseline]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIFT_DIR="${HERMES_DRIFT_DIR:-$HOME/.hermes/drift}"
BASELINE_FILE="${DRIFT_DIR}/baseline.json"
RESULTS_FILE="${DRIFT_DIR}/drift-results-$(date +%Y%m%d-%H%M%S).json"
HERMES_PORT="${HERMES_API_PORT:-8686}"
API_KEY="${API_SERVER_KEY:-}"
PASS_THRESHOLD=0.85

# 5 benchmark questions (stable, deterministic)
BENCHMARKS=(
    "What is the capital of France?"
    "Explain the concept of append-only audit logs in one sentence."
    "List three principles of governed AI agent infrastructure."
    "What does PHI stand for in healthcare technology?"
    "Describe the difference between a hash chain and a Merkle tree in one sentence."
)

show_help() {
    cat <<'HELP'
Usage: ./drift-check.sh [OPTION]

Run 5 benchmark questions against the agent and compare to baseline.
Flags significant response divergence (cosine similarity < 0.85).

Options:
  --baseline PATH    Use custom baseline file
  --update-baseline  Update baseline with current responses
  --help             Show this help message

Examples:
  ./drift-check.sh              # Run drift check against current baseline
  ./drift-check.sh --update-baseline  # Refresh baseline after intentional changes
HELP
}

# Parse arguments
UPDATE_BASELINE=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --baseline)    BASELINE_FILE="$2"; shift 2 ;;
        --update-baseline) UPDATE_BASELINE=true ;;
        --help)        show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
    shift
done

mkdir -p "$DRIFT_DIR"

echo "=== Scrutexity Agent Drift Check ==="
echo "Baseline: $BASELINE_FILE"
echo "Threshold: ${PASS_THRESHOLD} (cosine similarity)"
echo ""

# Check if Hermes API is reachable
if ! curl -s "http://127.0.0.1:${HERMES_PORT}/health" > /dev/null 2>&1; then
    echo "❌ Hermes API not reachable on port $HERMES_PORT"
    echo "   Is the gateway running? Try: sudo systemctl status hermes-gateway"
    exit 1
fi

# Function to get embedding from a simple local approach
# Since we don't have a dedicated embedding service, we use a character-level
# n-gram frequency vector as a lightweight proxy for semantic similarity
compute_similarity() {
    local text1="$1"
    local text2="$2"
    # Use Python for actual similarity calculation
    python3 -c "
import sys, json, math, re
from collections import Counter

def ngrams(text, n=2):
    text = re.sub(r'[^a-zA-Z0-9\s]', '', text.lower())
    words = text.split()
    return Counter([' '.join(words[i:i+n]) for i in range(max(1, len(words)-n+1))])

def cosine_sim(t1, t2):
    c1, c2 = ngrams(t1), ngrams(t2)
    all_keys = set(c1.keys()) | set(c2.keys())
    v1 = [c1.get(k, 0) for k in all_keys]
    v2 = [c2.get(k, 0) for k in all_keys]
    dot = sum(a*b for a,b in zip(v1,v2))
    mag1 = math.sqrt(sum(a*a for a in v1))
    mag2 = math.sqrt(sum(a*a for a in v2))
    if mag1 == 0 or mag2 == 0: return 0.0
    return dot / (mag1 * mag2)

print(f'{cosine_sim(sys.argv[1], sys.argv[2]):.4f}')
" "$text1" "$text2"
}

# Function to query Hermes API
query_hermes() {
    local prompt="$1"
    local auth_header=""
    [ -n "$API_KEY" ] && auth_header="-H Authorization: Bearer $API_KEY"

    curl -s http://127.0.0.1:${HERMES_PORT}/v1/chat/completions         $auth_header         -H "Content-Type: application/json"         -d "{\"model\": \"scrutexity-agent\", \"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}], \"max_tokens\": 200}"         2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('choices',[{}])[0].get('message',{}).get('content','ERROR'))" 2>/dev/null || echo "API_ERROR"
}

# Collect current responses
declare -a CURRENT_RESPONSES
echo "Running benchmark questions..."
for i in "${!BENCHMARKS[@]}"; do
    q="${BENCHMARKS[$i]}"
    echo "  Q$((i+1)): ${q:0:50}..."
    resp=$(query_hermes "$q")
    CURRENT_RESPONSES[$i]="$resp"
    echo "       -> ${resp:0:60}..."
done

# Update baseline mode
if [ "$UPDATE_BASELINE" = true ]; then
    echo ""
    echo "Updating baseline..."
    python3 -c "
import json
baseline = {str(i): {'question': q, 'response': r} for i, (q, r) in enumerate(zip(sys.argv[1:], sys.argv[6:]))}
with open('$BASELINE_FILE', 'w') as f:
    json.dump(baseline, f, indent=2)
" "${BENCHMARKS[@]}" "${CURRENT_RESPONSES[@]}"
    echo "✅ Baseline updated: $BASELINE_FILE"
    exit 0
fi

# Check baseline exists
if [ ! -f "$BASELINE_FILE" ]; then
    echo "⚠️  No baseline found. Creating initial baseline..."
    python3 -c "
import json
baseline = {str(i): {'question': q, 'response': r} for i, (q, r) in enumerate(zip(sys.argv[1:], sys.argv[6:]))}
with open('$BASELINE_FILE', 'w') as f:
    json.dump(baseline, f, indent=2)
" "${BENCHMARKS[@]}" "${CURRENT_RESPONSES[@]}"
    echo "✅ Initial baseline created. Run again next week to detect drift."
    exit 0
fi

# Compare against baseline
echo ""
echo "Comparing against baseline..."

PASS_COUNT=0
FAIL_COUNT=0
RESULTS="[]"

for i in "${!BENCHMARKS[@]}"; do
    q="${BENCHMARKS[$i]}"
    current="${CURRENT_RESPONSES[$i]}"
    baseline_resp=$(python3 -c "import json; d=json.load(open('$BASELINE_FILE')); print(d.get('$i',{}).get('response','NO_BASELINE'))")

    if [ "$baseline_resp" = "NO_BASELINE" ]; then
        echo "  Q$((i+1)): ⚠️  No baseline for this question"
        continue
    fi

    sim=$(compute_similarity "$current" "$baseline_resp")
    sim_float=$(python3 -c "print(float('$sim'))")

    if python3 -c "import sys; sys.exit(0 if float('$sim') >= $PASS_THRESHOLD else 1)"; then
        echo "  Q$((i+1)): ✅ PASS (similarity: $sim)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  Q$((i+1)): ❌ FAIL (similarity: $sim) — DRIFT DETECTED"
        echo "       Baseline: ${baseline_resp:0:60}..."
        echo "       Current:  ${current:0:60}..."
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

# Save results
python3 -c "
import json, datetime
results = {
    'timestamp': datetime.datetime.utcnow().isoformat() + 'Z',
    'threshold': $PASS_THRESHOLD,
    'pass_count': $PASS_COUNT,
    'fail_count': $FAIL_COUNT,
    'total': $((${#BENCHMARKS[@]})),
    'status': 'PASS' if $FAIL_COUNT == 0 else 'FAIL',
    'responses': {str(i): {'question': q, 'response': r} for i, (q, r) in enumerate(zip(sys.argv[1:], sys.argv[6:]))}
}
with open('$RESULTS_FILE', 'w') as f:
    json.dump(results, f, indent=2)
" "${BENCHMARKS[@]}" "${CURRENT_RESPONSES[@]}"

echo ""
echo "=== Drift Check Results ==="
echo "Passed: $PASS_COUNT / ${#BENCHMARKS[@]}"
echo "Failed: $FAIL_COUNT / ${#BENCHMARKS[@]}"
echo "Results saved: $RESULTS_FILE"

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo ""
    echo "✅ DRIFT CHECK PASSED — Agent behavior consistent with baseline"
    exit 0
else
    echo ""
    echo "❌ DRIFT CHECK FAILED — $FAIL_COUNT benchmark(s) diverged significantly"
    echo "   Review: $RESULTS_FILE"
    exit 1
fi
