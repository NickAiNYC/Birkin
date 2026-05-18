#!/usr/bin/env bash
# =============================================================================
# Birkin — One-Command Installer
#
# What this does:
#   1. Verifies Docker + git are installed
#   2. Clones the Birkin repo into ./birkin (or your chosen path)
#   3. Generates a .env with sensible defaults
#   4. Brings up Open WebUI + governance services with docker compose
#   5. Prints the URL you can open on your iPhone
#
# Connects to your existing Hermes Agent — does NOT install Hermes.
# Hermes docs: https://hermes-agent.nousresearch.com/
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/NickAiNYC/Birkin/main/install.sh | bash
#
# Or with a custom Hermes URL:
#   curl -fsSL https://raw.githubusercontent.com/NickAiNYC/Birkin/main/install.sh \
#     | HERMES_URL=http://192.168.1.50:8686 bash
# =============================================================================
set -euo pipefail

# ── Config (override via env) ────────────────────────────────────────────────
HERMES_URL="${HERMES_URL:-http://host.docker.internal:8686}"
INSTALL_DIR="${INSTALL_DIR:-$PWD/birkin}"
BIRKIN_REPO="https://github.com/NickAiNYC/Birkin.git"

# ── Colors ───────────────────────────────────────────────────────────────────
BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

say()   { echo -e "${CYAN}▶${NC}  $*"; }
ok()    { echo -e "${GREEN}✓${NC}  $*"; }
warn()  { echo -e "${YELLOW}!${NC}  $*"; }
fail()  { echo -e "${RED}✗${NC}  $*" >&2; exit 1; }

# ── Banner ───────────────────────────────────────────────────────────────────
cat <<'BANNER'

   ____  _      _    _
  | __ )(_)_ __| | _(_)_ __
  |  _ \| | '__| |/ / | '_ \
  | |_) | | |  |   <| | | | |
  |____/|_|_|  |_|\_\_|_| |_|

  iPhone control + hash-chained audit for your Hermes agent.
  https://github.com/NickAiNYC/Birkin

BANNER

# ── Preflight ────────────────────────────────────────────────────────────────
say "Checking prerequisites…"
command -v docker >/dev/null 2>&1 || fail "docker not found. Install Docker Desktop: https://docs.docker.com/get-docker/"
docker compose version >/dev/null 2>&1 || fail "docker compose v2 not found. Update Docker Desktop."
command -v git    >/dev/null 2>&1 || fail "git not found. Install git first."
ok "docker $(docker --version | awk '{print $3}' | tr -d ,) + docker compose v2 + git"

# ── Clone or update ──────────────────────────────────────────────────────────
if [[ -d "$INSTALL_DIR/.git" ]]; then
    say "Updating existing install at $INSTALL_DIR"
    git -C "$INSTALL_DIR" pull --ff-only
else
    say "Cloning Birkin into $INSTALL_DIR"
    git clone --depth 1 "$BIRKIN_REPO" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
ok "Repo ready"

# ── Generate .env ────────────────────────────────────────────────────────────
if [[ ! -f .env ]]; then
    say "Writing .env (override HERMES_URL via env to change later)"
    cat > .env <<ENV
# Birkin runtime config — edit and \`docker compose up -d\` to apply
HERMES_URL=${HERMES_URL}

# Optional: Telegram alerts on governance failure
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
ENV
    ok ".env created"
else
    warn ".env already exists — leaving it alone"
fi

# ── Sanity-check Hermes reachability (non-fatal) ─────────────────────────────
say "Probing Hermes at $HERMES_URL (non-fatal)…"
if curl -sf --max-time 3 "${HERMES_URL}/health" >/dev/null 2>&1; then
    ok "Hermes is responding at $HERMES_URL"
else
    warn "Hermes did not respond at $HERMES_URL — Birkin will still start,"
    warn "  but the iPhone PWA won't have a backend until Hermes is reachable."
    warn "  Start Hermes, or edit HERMES_URL in $INSTALL_DIR/.env and re-run."
fi

# ── Bring up services ────────────────────────────────────────────────────────
say "Starting Birkin services (Open WebUI + health + governance)…"
docker compose up -d
ok "Services up"

# ── Run the tamper test as live proof ───────────────────────────────────────
if [[ -x ./tests/tamper-test.sh ]]; then
    say "Running the hash-chain tamper test (this is your live proof)…"
    if ./tests/tamper-test.sh >/tmp/birkin-tamper.log 2>&1; then
        ok "Tamper test PASSED — governance chain is intact"
    else
        warn "Tamper test had issues (see /tmp/birkin-tamper.log)"
    fi
fi

# ── Final message ────────────────────────────────────────────────────────────
cat <<DONE

${GREEN}${BOLD}✓ Birkin is running.${NC}

  ${BOLD}iPhone PWA${NC}    →  http://localhost:3000
  ${BOLD}Governance${NC}    →  http://localhost:9999/health
  ${BOLD}Hermes target${NC} →  ${HERMES_URL}

  Next:
    1. Open http://localhost:3000 in Safari on your iPhone (same WiFi as this machine)
    2. Share → Add to Home Screen → name it "Birkin"
    3. Tap the icon — full-screen PWA, voice input, everything logged

  Manage:
    cd ${INSTALL_DIR}
    docker compose logs -f       # tail logs
    docker compose down          # stop
    ./governance-check.sh        # run all 5 gates
    ./tests/tamper-test.sh       # prove the audit chain

DONE
