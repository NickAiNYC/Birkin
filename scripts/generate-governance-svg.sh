#!/bin/bash
# =============================================================================
# generate-governance-svg.sh — Regenerate governance-pipeline.svg from live state
# Version: 1.0.0
#
# Usage: ./scripts/generate-governance-svg.sh > assets/governance-pipeline.svg
#        ./scripts/generate-governance-svg.sh --check  # just show pass/fail per gate
#
# This script runs governance-check.sh under the hood and generates an SVG
# reflecting current gate status. Embed the result in the README.
# =============================================================================
set -euo pipefail

HERMES_PORT="${HERMES_API_PORT:-8686}"
HEALTH_PORT="${HEALTH_PORT:-9999}"
AUDIT_DB="${HERMES_AUDIT_DB:-$HOME/.hermes/audit.db}"
SKILLS_DIR="${HERMES_SKILLS_DIR:-$HOME/.hermes/skills}"
DRIFT_DIR="${HERMES_DRIFT_DIR:-$HOME/.hermes/drift}"

# ─── Check each gate ──────────────────────────────────────────────────────────
check_gate() {
    local cmd="$1"
    if eval "$cmd" > /dev/null 2>&1; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# Gate 1: Hermes process
G1=$(check_gate "systemctl is-active --quiet hermes-gateway && curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:${HERMES_PORT}/health | grep -q '^200$'")

# Gate 2: Audit integrity
if [ -f "$AUDIT_DB" ]; then
    MOD=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM audit_log WHERE modified_at IS NOT NULL AND modified_at > created_at;" 2>/dev/null || echo "1")
    OOO=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM (SELECT timestamp, LAG(timestamp) OVER (ORDER BY id) as prev FROM audit_log) WHERE timestamp < prev;" 2>/dev/null || echo "1")
    if [ "$MOD" = "0" ] && [ "$OOO" = "0" ]; then G2="PASS"; else G2="FAIL"; fi
else
    G2="WARN"
fi

# Gate 3: Skill versioning
if [ -d "$SKILLS_DIR/.git" ]; then
    UC=$(cd "$SKILLS_DIR" && git status --porcelain 2>/dev/null | wc -l)
    MV=0
    for f in "$SKILLS_DIR"/*.md; do
        [ -f "$f" ] || continue
        grep -q "^version:" "$f" 2>/dev/null || MV=$((MV + 1))
    done
    if [ "$UC" -eq 0 ] && [ "$MV" -eq 0 ]; then G3="PASS"
    elif [ "$MV" -gt 0 ]; then G3="FAIL"
    else G3="WARN"; fi
else
    G3="FAIL"
fi

# Gate 4: Drift detection
if [ -f "$DRIFT_DIR/baseline.json" ]; then
    LATEST=$(ls -t "$DRIFT_DIR"/drift-results-*.json 2>/dev/null | head -1)
    if [ -n "$LATEST" ]; then
        DS=$(python3 -c "import json; d=json.load(open('$LATEST')); print(d.get('status','FAIL'))" 2>/dev/null || echo "FAIL")
        G4="$DS"
    else
        G4="WARN"
    fi
else
    G4="WARN"
fi

# Gate 5: Health endpoint
G5=$(check_gate "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:${HEALTH_PORT}/health | grep -q '^200$' && curl -s http://127.0.0.1:${HEALTH_PORT}/health | python3 -c 'import sys,json; json.load(sys.stdin)'")

# ─── Check-only mode ─────────────────────────────────────────────────────────
if [ "${1:-}" = "--check" ]; then
    echo "Gate 1 (Gateway Process): $G1"
    echo "Gate 2 (Audit Integrity): $G2"
    echo "Gate 3 (Skill Versioning): $G3"
    echo "Gate 4 (Drift Detection): $G4"
    echo "Gate 5 (Health Endpoint): $G5"
    exit 0
fi

# ─── Color mapper ─────────────────────────────────────────────────────────────
gate_fill()  { case "$1" in PASS) echo "#EAF3DE";; WARN) echo "#FAEEDA";; *) echo "#FCEBEB";; esac }
gate_stroke(){ case "$1" in PASS) echo "#639922";; WARN) echo "#BA7517";; *) echo "#A32D2D";; esac }
gate_text()  { case "$1" in PASS) echo "#27500A";; WARN) echo "#633806";; *) echo "#791F1F";; esac }
badge_text() { case "$1" in PASS) echo "✓ PASSING";; WARN) echo "⚠ WARNING";; *) echo "✗ FAILED";; esac }

OVERALL="PASS"
for g in "$G1" "$G2" "$G3" "$G4" "$G5"; do
    [ "$g" = "FAIL" ] && OVERALL="FAIL"
    [ "$g" = "WARN" ] && [ "$OVERALL" != "FAIL" ] && OVERALL="WARN"
done

BANNER_FILL=$(gate_fill "$OVERALL")
BANNER_STROKE=$(gate_stroke "$OVERALL")
BANNER_TEXT=$(gate_text "$OVERALL")
case "$OVERALL" in
    PASS) BANNER_LABEL="✅  AGENT GOVERNANCE INTACT";;
    WARN) BANNER_LABEL="⚠️  GOVERNANCE WARNINGS PRESENT";;
    *)    BANNER_LABEL="❌  GOVERNANCE FAILED";;
esac

GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ─── SVG output ──────────────────────────────────────────────────────────────
cat <<SVG
<svg width="100%" viewBox="0 0 680 420" role="img" xmlns="http://www.w3.org/2000/svg">
<title>Birkin Governance Pipeline — generated ${GENERATED_AT}</title>
<desc>5-gate governance pipeline showing current status: Gate 1 ${G1}, Gate 2 ${G2}, Gate 3 ${G3}, Gate 4 ${G4}, Gate 5 ${G5}. Overall: ${OVERALL}.</desc>
<defs>
  <style>
    .h { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; font-size: 10px; fill: #888780; letter-spacing: 0.08em; }
    .lm{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; font-size: 13px; font-weight: 600; }
    .ls{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; font-size: 11px; }
    .lt{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; font-size: 9px;  font-weight: 500; letter-spacing: 0.06em; }
    .bt{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; font-size: 11px; font-weight: 600; }
    .bm{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; font-size: 15px; font-weight: 600; }
    .bs{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; font-size: 11px; }
    .ft{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; font-size: 11px; fill: #888780; }
  </style>
</defs>
<text class="h" x="340" y="26" text-anchor="middle">AGEMES GOVERNANCE PIPELINE · GENERATED ${GENERATED_AT}</text>

<!-- Gate 1 -->
<rect x="20" y="44" width="108" height="130" rx="8" fill="$(gate_fill $G1)" stroke="$(gate_stroke $G1)" stroke-width="0.5"/>
<text class="lm" fill="$(gate_text $G1)" x="74" y="72" text-anchor="middle">Gateway</text>
<text class="lm" fill="$(gate_text $G1)" x="74" y="88" text-anchor="middle">Process</text>
<text class="ls" fill="$(gate_stroke $G1)" x="74" y="108" text-anchor="middle">Hermes running?</text>
<text class="ls" fill="$(gate_stroke $G1)" x="74" y="122" text-anchor="middle">API responding?</text>
<rect x="30" y="140" width="88" height="14" rx="7" fill="$(gate_fill $G1)" stroke="$(gate_stroke $G1)" stroke-width="0.5"/>
<text class="lt" fill="$(gate_text $G1)" x="74" y="151" text-anchor="middle">2 CHECKS</text>

<!-- Arrow 1→2 -->
<line x1="128" y1="109" x2="152" y2="109" stroke="$(gate_stroke $G2)" stroke-width="1" marker-end="none"/>
<path d="M148 105L153 109L148 113" fill="none" stroke="$(gate_stroke $G2)" stroke-width="1" stroke-linecap="round" stroke-linejoin="round"/>

<!-- Gate 2 -->
<rect x="152" y="44" width="108" height="130" rx="8" fill="$(gate_fill $G2)" stroke="$(gate_stroke $G2)" stroke-width="0.5"/>
<text class="lm" fill="$(gate_text $G2)" x="206" y="72" text-anchor="middle">Audit</text>
<text class="lm" fill="$(gate_text $G2)" x="206" y="88" text-anchor="middle">Integrity</text>
<text class="ls" fill="$(gate_stroke $G2)" x="206" y="108" text-anchor="middle">Append-only?</text>
<text class="ls" fill="$(gate_stroke $G2)" x="206" y="122" text-anchor="middle">Monotonic</text>
<text class="ls" fill="$(gate_stroke $G2)" x="206" y="136" text-anchor="middle">timestamps?</text>
<rect x="162" y="148" width="88" height="14" rx="7" fill="$(gate_fill $G2)" stroke="$(gate_stroke $G2)" stroke-width="0.5"/>
<text class="lt" fill="$(gate_text $G2)" x="206" y="159" text-anchor="middle">2 CHECKS</text>

<!-- Arrow 2→3 -->
<line x1="260" y1="109" x2="284" y2="109" stroke="$(gate_stroke $G3)" stroke-width="1"/>
<path d="M280 105L285 109L280 113" fill="none" stroke="$(gate_stroke $G3)" stroke-width="1" stroke-linecap="round" stroke-linejoin="round"/>

<!-- Gate 3 -->
<rect x="284" y="44" width="108" height="130" rx="8" fill="$(gate_fill $G3)" stroke="$(gate_stroke $G3)" stroke-width="0.5"/>
<text class="lm" fill="$(gate_text $G3)" x="338" y="72" text-anchor="middle">Skill</text>
<text class="lm" fill="$(gate_text $G3)" x="338" y="88" text-anchor="middle">Versioning</text>
<text class="ls" fill="$(gate_stroke $G3)" x="338" y="108" text-anchor="middle">Git repo?</text>
<text class="ls" fill="$(gate_stroke $G3)" x="338" y="122" text-anchor="middle">Committed?</text>
<text class="ls" fill="$(gate_stroke $G3)" x="338" y="136" text-anchor="middle">Versioned?</text>
<rect x="294" y="148" width="88" height="14" rx="7" fill="$(gate_fill $G3)" stroke="$(gate_stroke $G3)" stroke-width="0.5"/>
<text class="lt" fill="$(gate_text $G3)" x="338" y="159" text-anchor="middle">3 CHECKS</text>

<!-- Arrow 3→4 -->
<line x1="392" y1="109" x2="416" y2="109" stroke="$(gate_stroke $G4)" stroke-width="1"/>
<path d="M412 105L417 109L412 113" fill="none" stroke="$(gate_stroke $G4)" stroke-width="1" stroke-linecap="round" stroke-linejoin="round"/>

<!-- Gate 4 -->
<rect x="416" y="44" width="108" height="130" rx="8" fill="$(gate_fill $G4)" stroke="$(gate_stroke $G4)" stroke-width="0.5"/>
<text class="lm" fill="$(gate_text $G4)" x="470" y="72" text-anchor="middle">Drift</text>
<text class="lm" fill="$(gate_text $G4)" x="470" y="88" text-anchor="middle">Detection</text>
<text class="ls" fill="$(gate_stroke $G4)" x="470" y="108" text-anchor="middle">Baseline exists?</text>
<text class="ls" fill="$(gate_stroke $G4)" x="470" y="122" text-anchor="middle">Similarity</text>
<text class="ls" fill="$(gate_stroke $G4)" x="470" y="136" text-anchor="middle">≥ 0.85?</text>
<rect x="426" y="148" width="88" height="14" rx="7" fill="$(gate_fill $G4)" stroke="$(gate_stroke $G4)" stroke-width="0.5"/>
<text class="lt" fill="$(gate_text $G4)" x="470" y="159" text-anchor="middle">1 CHECK</text>

<!-- Arrow 4→5 -->
<line x1="524" y1="109" x2="548" y2="109" stroke="$(gate_stroke $G5)" stroke-width="1"/>
<path d="M544 105L549 109L544 113" fill="none" stroke="$(gate_stroke $G5)" stroke-width="1" stroke-linecap="round" stroke-linejoin="round"/>

<!-- Gate 5 -->
<rect x="548" y="44" width="108" height="130" rx="8" fill="$(gate_fill $G5)" stroke="$(gate_stroke $G5)" stroke-width="0.5"/>
<text class="lm" fill="$(gate_text $G5)" x="602" y="72" text-anchor="middle">Health</text>
<text class="lm" fill="$(gate_text $G5)" x="602" y="88" text-anchor="middle">Endpoint</text>
<text class="ls" fill="$(gate_stroke $G5)" x="602" y="108" text-anchor="middle">Port 9999</text>
<text class="ls" fill="$(gate_stroke $G5)" x="602" y="122" text-anchor="middle">HTTP 200?</text>
<text class="ls" fill="$(gate_stroke $G5)" x="602" y="136" text-anchor="middle">Valid JSON?</text>
<rect x="558" y="148" width="88" height="14" rx="7" fill="$(gate_fill $G5)" stroke="$(gate_stroke $G5)" stroke-width="0.5"/>
<text class="lt" fill="$(gate_text $G5)" x="602" y="159" text-anchor="middle">2 CHECKS</text>

<!-- Status badges -->
<rect x="20"  y="194" width="108" height="26" rx="6" fill="$(gate_fill $G1)" stroke="$(gate_stroke $G1)" stroke-width="0.5"/>
<text class="bt" fill="$(gate_text $G1)" x="74"  y="210" text-anchor="middle">$(badge_text $G1)</text>
<rect x="152" y="194" width="108" height="26" rx="6" fill="$(gate_fill $G2)" stroke="$(gate_stroke $G2)" stroke-width="0.5"/>
<text class="bt" fill="$(gate_text $G2)" x="206" y="210" text-anchor="middle">$(badge_text $G2)</text>
<rect x="284" y="194" width="108" height="26" rx="6" fill="$(gate_fill $G3)" stroke="$(gate_stroke $G3)" stroke-width="0.5"/>
<text class="bt" fill="$(gate_text $G3)" x="338" y="210" text-anchor="middle">$(badge_text $G3)</text>
<rect x="416" y="194" width="108" height="26" rx="6" fill="$(gate_fill $G4)" stroke="$(gate_stroke $G4)" stroke-width="0.5"/>
<text class="bt" fill="$(gate_text $G4)" x="470" y="210" text-anchor="middle">$(badge_text $G4)</text>
<rect x="548" y="194" width="108" height="26" rx="6" fill="$(gate_fill $G5)" stroke="$(gate_stroke $G5)" stroke-width="0.5"/>
<text class="bt" fill="$(gate_text $G5)" x="602" y="210" text-anchor="middle">$(badge_text $G5)</text>

<line x1="40" y1="254" x2="640" y2="254" stroke="#B4B2A9" stroke-width="0.5"/>

<rect x="120" y="270" width="440" height="52" rx="8" fill="${BANNER_FILL}" stroke="${BANNER_STROKE}" stroke-width="0.5"/>
<text class="bm" fill="${BANNER_TEXT}" x="340" y="293" text-anchor="middle">${BANNER_LABEL}</text>
<text class="bs" fill="${BANNER_STROKE}" x="340" y="312" text-anchor="middle">Overall: ${OVERALL} · Generated: ${GENERATED_AT}</text>

<text class="ft" x="340" y="356" text-anchor="middle">Run: ./scripts/governance-check.sh</text>
<text class="ft" x="340" y="374" text-anchor="middle">github.com/NickAiNYC/birkin</text>
</svg>
SVG
