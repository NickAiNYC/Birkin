#!/usr/bin/env bash
# =============================================================================
# drift-check.sh — Weekly behavioral drift detection
# Version: 1.0.0 | Birkin Governance Layer
#
# Runs 5 deterministic benchmark questions against the Hermes API and
# compares responses to a stored baseline using bigram cosine similarity.
# Flags behavioral drift if similarity < PASS_THRESHOLD (default 0.85).
#
# Usage:
#   ./drift-check.sh                        # Compare to baseline
#   ./drift-check.sh --update-baseline      # Refresh baseline
#   ./drift-check.sh --baseline PATH        # Use custom baseline file
#   ./drift-check.sh --threshold 0.90       # Override similarity threshold
# Exit: 0 = PASS | 1 = DRIFT DETECTED or error
# =============================================================================
set -euo pipefail

DRIFT_DIR="${HERMES_DRIFT_DIR:-$HOME/.hermes/drift}"
BASELINE_FILE="${DRIFT_DIR}/baseline.json"
HERMES_PORT="${HERMES_API_PORT:-8686}"
PASS_THRESHOLD="0.85"
UPDATE_BASELINE=false

# Benchmark questions — stable, factual, deterministic
declare -a BENCHMARKS=(
    "What is the capital of France?"
    "Explain the concept of an append-only audit log in one sentence."
    "List three principles of governed AI agent infrastructure."
    "What does PHI stand for in healthcare technology?"
    "Describe the difference between a hash chain and a Merkle tree in one sentence."
)

show_help() {
    cat <<'HELP'
Usage: ./drift-check.sh [OPTIONS]

Runs 5 deterministic benchmark questions against the Hermes API and
compares responses to a stored baseline (bigram cosine similarity).
Flags divergence when similarity drops below the threshold (default 0.85).

Options:
  --baseline PATH     Use custom baseline file (default: ~/.hermes/drift/baseline.json)
  --update-baseline   Overwrite baseline with current responses and exit
  --threshold N       Override similarity threshold (default: 0.85, range 0.0-1.0)
  --help              Show this help

Exit codes:
  0 — All benchmarks within threshold (PASS)
  1 — One or more benchmarks diverged (DRIFT) or error
HELP
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --baseline)        BASELINE_FILE="$2"; shift 2 ;;
        --update-baseline) UPDATE_BASELINE=true; shift ;;
        --threshold)       PASS_THRESHOLD="$2"; shift 2 ;;
        --help)            show_help; exit 0 ;;
        *) echo "Unknown option: $1. Use --help." >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "$DRIFT_DIR"

RESULTS_FILE="${DRIFT_DIR}/drift-results-$(date +%Y%m%d-%H%M%S).json"

echo "=== Birkin Drift Check ==="
echo "Baseline:  $BASELINE_FILE"
echo "Threshold: $PASS_THRESHOLD (bigram cosine similarity)"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# ── Verify Hermes API is reachable ────────────────────────────────────────────
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    "http://127.0.0.1:${HERMES_PORT}/health" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" != "200" ]]; then
    echo "❌ Hermes API not reachable at port $HERMES_PORT (HTTP $HTTP_CODE)"
    echo "   Is the gateway running? Check: sudo systemctl status hermes-gateway"
    exit 1
fi
echo "✅ Hermes API reachable (HTTP 200)"
echo ""

# ── Read API key from .env ────────────────────────────────────────────────────
API_KEY=""
[[ -f "$HOME/.hermes/.env" ]] && API_KEY=$(grep '^API_SERVER_KEY=' "$HOME/.hermes/.env" 2>/dev/null | cut -d= -f2 || true)

# ── Similarity function (Python bigram cosine) ────────────────────────────────
compute_similarity() {
    local t1="$1"
    local t2="$2"
    python3 - "$t1" "$t2" <<'PYEOF'
import sys, math, re
from collections import Counter

def bigrams(text):
    text = re.sub(r'[^a-z0-9 ]', '', text.lower())
    words = text.split()
    return Counter([f"{a} {b}" for a, b in zip(words, words[1:])])

def cosine(t1, t2):
    c1, c2 = bigrams(t1), bigrams(t2)
    keys = set(c1) | set(c2)
    v1 = [c1.get(k, 0) for k in keys]
    v2 = [c2.get(k, 0) for k in keys]
    dot = sum(a * b for a, b in zip(v1, v2))
    m1  = math.sqrt(sum(a * a for a in v1))
    m2  = math.sqrt(sum(b * b for b in v2))
    if m1 == 0 or m2 == 0:
        return 0.0
    return dot / (m1 * m2)

print(f"{cosine(sys.argv[1], sys.argv[2]):.4f}")
PYEOF
}

# ── Query Hermes API ──────────────────────────────────────────────────────────
query_hermes() {
    local prompt="$1"
    local auth_header=""
    [[ -n "$API_KEY" ]] && auth_header="-H \"Authorization: Bearer $API_KEY\""

    local payload
    payload=$(python3 -c "import json,sys; print(json.dumps({'model':'birkin','messages':[{'role':'user','content':sys.argv[1]}],'max_tokens':200,'temperature':0}))" "$prompt")

    eval curl -sf \
        --max-time 30 \
        "http://127.0.0.1:${HERMES_PORT}/v1/chat/completions" \
        $auth_header \
        -H "'Content-Type: application/json'" \
        -d "'$payload'" 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" 2>/dev/null \
        || echo "API_ERROR"
}

# ── Collect current responses ──────────────────────────────────────────────
declare -a CURRENT_RESPONSES
echo "Running $((${#BENCHMARKS[@]})) benchmark questions..."
for i in "${!BENCHMARKS[@]}"; do
    q="${BENCHMARKS[$i]}"
    echo "  Q$((i+1)): ${q:0:55}..."
    resp=$(query_hermes "$q")
    CURRENT_RESPONSES[$i]="$resp"
    if [[ "$resp" == "API_ERROR" ]]; then
        echo "        → API_ERROR — Hermes returned no response"
    else
        echo "        → ${resp:0:65}..."
    fi
done

# ── Update baseline mode ───────────────────────────────────────────────────
if [[ "$UPDATE_BASELINE" == true ]]; then
    echo ""
    echo "Updating baseline with current responses..."
    python3 - "$BASELINE_FILE" "${BENCHMARKS[@]}" "${CURRENT_RESPONSES[@]}" <<'PYEOF'
import sys, json
baseline_file = sys.argv[1]
n = (len(sys.argv) - 2) // 2
questions  = sys.argv[2:2+n]
responses  = sys.argv[2+n:]
baseline = {
    str(i): {"question": q, "response": r}
    for i, (q, r) in enumerate(zip(questions, responses))
}
with open(baseline_file, "w") as f:
    json.dump(baseline, f, indent=2)
print(f"Baseline saved: {baseline_file}")
PYEOF
    echo "✅ Baseline updated"
    exit 0
fi

# ── Create initial baseline if missing ────────────────────────────────────
if [[ ! -f "$BASELINE_FILE" ]]; then
    echo ""
    echo "⚠️  No baseline found — creating initial baseline..."
    python3 - "$BASELINE_FILE" "${BENCHMARKS[@]}" "${CURRENT_RESPONSES[@]}" <<'PYEOF'
import sys, json
baseline_file = sys.argv[1]
n = (len(sys.argv) - 2) // 2
questions  = sys.argv[2:2+n]
responses  = sys.argv[2+n:]
baseline = {
    str(i): {"question": q, "response": r}
    for i, (q, r) in enumerate(zip(questions, responses))
}
with open(baseline_file, "w") as f:
    json.dump(baseline, f, indent=2)
PYEOF
    echo "✅ Initial baseline created: $BASELINE_FILE"
    echo "   Run again next week to detect drift."
    exit 0
fi

# ── Compare against baseline ───────────────────────────────────────────────
echo ""
echo "Comparing against baseline..."
PASS_COUNT=0
FAIL_COUNT=0

for i in "${!BENCHMARKS[@]}"; do
    q="${BENCHMARKS[$i]}"
    current="${CURRENT_RESPONSES[$i]}"
    baseline_resp=$(python3 -c "
import json
d=json.load(open('$BASELINE_FILE'))
print(d.get('$i', {}).get('response', 'NO_BASELINE'))
")

    if [[ "$baseline_resp" == "NO_BASELINE" ]]; then
        echo "  Q$((i+1)): ⚠️  No baseline entry for this question"
        continue
    fi
    if [[ "$current" == "API_ERROR" ]]; then
        echo "  Q$((i+1)): ❌ API_ERROR — could not get response to compare"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    sim=$(compute_similarity "$current" "$baseline_resp")
    passes=$(python3 -c "import sys; sys.exit(0 if float('$sim') >= $PASS_THRESHOLD else 1)")
    if [[ $? -eq 0 ]]; then
        echo "  Q$((i+1)): ✅ PASS (similarity: $sim)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  Q$((i+1)): ❌ DRIFT (similarity: $sim < $PASS_THRESHOLD)"
        echo "       Baseline: ${baseline_resp:0:65}..."
        echo "       Current:  ${current:0:65}..."
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

# ── Save results ───────────────────────────────────────────────────────────
python3 - "$RESULTS_FILE" "$PASS_COUNT" "$FAIL_COUNT" \
    "${BENCHMARKS[@]}" "${CURRENT_RESPONSES[@]}" <<'PYEOF'
import sys, json
from datetime import datetime, timezone

results_file = sys.argv[1]
pass_count   = int(sys.argv[2])
fail_count   = int(sys.argv[3])
n = (len(sys.argv) - 4) // 2
questions  = sys.argv[4:4+n]
responses  = sys.argv[4+n:]
results = {
    "timestamp":   datetime.now(timezone.utc).isoformat(),
    "threshold":   0.85,
    "pass_count":  pass_count,
    "fail_count":  fail_count,
    "total":       n,
    "status":      "PASS" if fail_count == 0 else "FAIL",
    "responses":   {str(i): {"question": q, "response": r}
                    for i, (q, r) in enumerate(zip(questions, responses))}
}
with open(results_file, "w") as f:
    json.dump(results, f, indent=2)
PYEOF

echo ""
echo "=== Drift Check Results ==="
echo "Passed:  $PASS_COUNT / ${#BENCHMARKS[@]}"
echo "Failed:  $FAIL_COUNT / ${#BENCHMARKS[@]}"
echo "Results: $RESULTS_FILE"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo "✅ DRIFT CHECK PASSED — Agent behavior is consistent with baseline"
    exit 0
else
    echo "❌ DRIFT CHECK FAILED — $FAIL_COUNT benchmark(s) diverged significantly"
    echo "   Investigate: $RESULTS_FILE"
    echo "   If change was intentional: ./scripts/drift-check.sh --update-baseline"
    exit 1
fi
