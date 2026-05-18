#!/bin/bash
# =============================================================================
# install.sh — Birkin One-Command Installer
# Version: 1.0.0
#
# Usage (the only command you need to run):
#   curl -fsSL https://raw.githubusercontent.com/NickAiNYC/birkin/main/install.sh | bash
#
# Or, if you've cloned the repo:
#   ./install.sh
#
# What this does:
#   1. Checks prerequisites (hcloud CLI, curl, git)
#   2. Prompts for your credentials (interactively or via env vars)
#   3. Provisions a Hetzner CX22 server
#   4. Runs deploy.sh remotely (7 phases, ~12 minutes)
#   5. Verifies governance-check.sh passes before declaring success
#   6. Prints your agent URL and next steps
#
# Environment variables (skip prompts if set):
#   HETZNER_TOKEN       — Hetzner Cloud API token
#   CF_TOKEN            — Cloudflare API token
#   DOMAIN              — Your domain (e.g., agent.yourdomain.com)
#   OPENROUTER_API_KEY  — OpenRouter API key (sk-or-v1-xxx)
#   TELEGRAM_BOT_TOKEN  — Telegram bot token (optional but recommended)
#   TELEGRAM_CHAT_ID    — Telegram chat ID (optional)
#   SSH_KEY_NAME        — Name of your Hetzner SSH key (default: birkin)
#   SERVER_LOCATION     — Hetzner datacenter (default: nbg1)
#   SERVER_TYPE         — Hetzner server type (default: cx22, €4.51/mo)
#
# =============================================================================
set -euo pipefail

# ─── Colors and formatting ────────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ─── Defaults ─────────────────────────────────────────────────────────────────
SERVER_TYPE="${SERVER_TYPE:-cx22}"
SERVER_LOCATION="${SERVER_LOCATION:-nbg1}"
SSH_KEY_NAME="${SSH_KEY_NAME:-birkin}"
BIRKIN_REPO="https://github.com/NickAiNYC/birkin.git"

# ─── Helpers ──────────────────────────────────────────────────────────────────
log_step() {
    echo -e "\n${CYAN}${BOLD}▶  $1${NC}"
}

log_ok() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_fail() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

prompt_if_empty() {
    local var_name="$1"
    local prompt_text="$2"
    local secret="${3:-false}"

    if [ -z "${!var_name:-}" ]; then
        if [ "$secret" = "true" ]; then
            read -r -s -p "$(echo -e "${BOLD}$prompt_text${NC} ")" "$var_name"
            echo ""
        else
            read -r -p "$(echo -e "${BOLD}$prompt_text${NC} ")" "$var_name"
        fi
    fi
}

# ─── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║          BIRKIN — One-Command Installer v1.0.0               ║${NC}"
echo -e "${BOLD}║     A Self-Governing Hermes Agent · €13/mo · Open Source     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "This installer will:"
echo "  • Provision a Hetzner CX22 server (€4.51/mo)"
echo "  • Deploy Hermes + Open WebUI + governance layer"
echo "  • Set up Cloudflare Tunnel to your domain"
echo "  • Verify all 9 governance checks pass"
echo "  • Print your agent URL"
echo ""
echo "Total time: ~12 minutes"
echo ""

# ─── Phase 0: Prerequisites ───────────────────────────────────────────────────
log_step "Phase 0/7 — Checking prerequisites"

# Check hcloud CLI
if ! command -v hcloud &>/dev/null; then
    log_warn "hcloud CLI not found. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install hcloud 2>/dev/null || {
            log_fail "Install hcloud manually: https://github.com/hetznercloud/cli#installation"
        }
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -fsSL https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz \
            | tar -xz -C /tmp && sudo mv /tmp/hcloud /usr/local/bin/hcloud
    else
        log_fail "Please install hcloud CLI manually: https://github.com/hetznercloud/cli#installation"
    fi
fi
log_ok "hcloud CLI available: $(hcloud version)"

# Check other tools
for cmd in curl git ssh ssh-keygen; do
    command -v "$cmd" &>/dev/null || log_fail "$cmd is required but not installed"
done
log_ok "curl, git, ssh, ssh-keygen: all present"

# ─── Phase 1: Credentials ─────────────────────────────────────────────────────
log_step "Phase 1/7 — Gathering credentials"

prompt_if_empty HETZNER_TOKEN "Hetzner Cloud API token (from https://console.hetzner.cloud → Security → API Tokens):" true
prompt_if_empty CF_TOKEN "Cloudflare API token (with Zone:Read and DNS:Edit permissions):" true
prompt_if_empty DOMAIN "Your domain for the agent (e.g., agent.yourdomain.com):"
prompt_if_empty OPENROUTER_API_KEY "OpenRouter API key (from https://openrouter.ai → Keys):" true

echo ""
read -r -p "$(echo -e "${BOLD}Set up Telegram alerts? (recommended — y/n):${NC} ")" SETUP_TELEGRAM
if [[ "$SETUP_TELEGRAM" =~ ^[Yy]$ ]]; then
    prompt_if_empty TELEGRAM_BOT_TOKEN "Telegram bot token (from @BotFather):" true
    prompt_if_empty TELEGRAM_CHAT_ID "Telegram chat ID (your user ID or group ID):"
else
    TELEGRAM_BOT_TOKEN=""
    TELEGRAM_CHAT_ID=""
    log_warn "Skipping Telegram. You can add it later in .env on the server."
fi

# Validate Hetzner token
export HCLOUD_TOKEN="$HETZNER_TOKEN"
hcloud server list &>/dev/null || log_fail "Invalid Hetzner token. Check your API token at console.hetzner.cloud"
log_ok "Hetzner token validated"

# ─── Phase 2: SSH Key ─────────────────────────────────────────────────────────
log_step "Phase 2/7 — Setting up SSH key"

SSH_KEY_PATH="$HOME/.ssh/birkin_ed25519"

if [ ! -f "$SSH_KEY_PATH" ]; then
    log_warn "Generating new SSH key pair for Birkin..."
    ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "birkin@$(hostname)"
    log_ok "SSH key generated: $SSH_KEY_PATH"
fi

# Upload to Hetzner if not already there
if ! hcloud ssh-key describe "$SSH_KEY_NAME" &>/dev/null; then
    hcloud ssh-key create --name "$SSH_KEY_NAME" --public-key-from-file "${SSH_KEY_PATH}.pub"
    log_ok "SSH key uploaded to Hetzner as '$SSH_KEY_NAME'"
else
    log_ok "SSH key '$SSH_KEY_NAME' already exists in Hetzner"
fi

# ─── Phase 3: Provision Server ────────────────────────────────────────────────
log_step "Phase 3/7 — Provisioning Hetzner ${SERVER_TYPE} server"

SERVER_NAME="birkin-$(date +%Y%m%d)"

# Check if server already exists (idempotent)
EXISTING_IP=$(hcloud server describe "$SERVER_NAME" --output json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['public_net']['ipv4']['ip'])" 2>/dev/null || echo "")

if [ -n "$EXISTING_IP" ]; then
    log_warn "Server '$SERVER_NAME' already exists at $EXISTING_IP — skipping provisioning"
    SERVER_IP="$EXISTING_IP"
else
    echo "  Creating ${SERVER_TYPE} in ${SERVER_LOCATION} (this takes ~30 seconds)..."
    SERVER_IP=$(hcloud server create \
        --name "$SERVER_NAME" \
        --type "$SERVER_TYPE" \
        --image ubuntu-24.04 \
        --location "$SERVER_LOCATION" \
        --ssh-key "$SSH_KEY_NAME" \
        --output json \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['server']['public_net']['ipv4']['ip'])")
    
    log_ok "Server provisioned: $SERVER_IP (€4.51/mo)"
    
    # Wait for SSH to be ready
    echo "  Waiting for SSH to be ready..."
    for i in $(seq 1 30); do
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$SSH_KEY_PATH" \
            root@"$SERVER_IP" "echo ready" &>/dev/null && break
        sleep 5
    done
    log_ok "SSH is ready"
fi

# ─── Phase 4: Clone and Configure ────────────────────────────────────────────
log_step "Phase 4/7 — Cloning Birkin to server"

ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" root@"$SERVER_IP" bash <<REMOTE
set -euo pipefail

# Clone repo if not already there
if [ ! -d /opt/birkin ]; then
    git clone ${BIRKIN_REPO} /opt/birkin
    echo "✅ Repo cloned to /opt/birkin"
else
    cd /opt/birkin && git pull --ff-only
    echo "✅ Repo updated"
fi

# Write environment file
cat > /opt/birkin/.env <<'ENV'
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}
DOMAIN=${DOMAIN}
CF_TOKEN=${CF_TOKEN}
ENV

chmod 600 /opt/birkin/.env
echo "✅ Environment file written"
REMOTE

log_ok "Repo cloned and configured on server"

# ─── Phase 5: Run Deploy ──────────────────────────────────────────────────────
log_step "Phase 5/7 — Running deploy.sh (7 phases, ~10 minutes)"
echo ""
echo "  Streaming deploy output from server..."
echo "  ────────────────────────────────────────"

ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" root@"$SERVER_IP" \
    "source /opt/birkin/.env && cd /opt/birkin && ./deploy.sh \
        --hetzner-token '${HETZNER_TOKEN}' \
        --cf-token '${CF_TOKEN}' \
        --domain '${DOMAIN}' \
        --openrouter-key '${OPENROUTER_API_KEY}' \
        --telegram-token '${TELEGRAM_BOT_TOKEN}' \
        --telegram-chat '${TELEGRAM_CHAT_ID}'"

echo "  ────────────────────────────────────────"
log_ok "deploy.sh completed"

# ─── Phase 6: Governance Check ───────────────────────────────────────────────
log_step "Phase 6/7 — Running governance check (all 9 checks must pass)"
echo ""

GOVERNANCE_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" root@"$SERVER_IP" \
    "cd /opt/birkin && ./scripts/governance-check.sh" 2>&1)

echo "$GOVERNANCE_OUTPUT"
echo ""

if echo "$GOVERNANCE_OUTPUT" | grep -q "✅ AGENT GOVERNANCE INTACT"; then
    log_ok "All governance checks passed"
else
    log_fail "Governance check failed. Review output above and fix before using the agent."
fi

# ─── Phase 7: Done ───────────────────────────────────────────────────────────
log_step "Phase 7/7 — Done!"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                    🎉 BIRKIN IS LIVE                        ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Agent URL:    ${CYAN}${BOLD}https://${DOMAIN}${NC}"
echo -e "  Health check: ${CYAN}${BOLD}https://${DOMAIN}:9999/health${NC}"
echo -e "  Server IP:    ${CYAN}${BOLD}${SERVER_IP}${NC}"
echo -e "  SSH:          ${CYAN}${BOLD}ssh -i ~/.ssh/birkin_ed25519 root@${SERVER_IP}${NC}"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Open https://${DOMAIN} in Safari on your iPhone"
echo "  2. Tap Share → 'Add to Home Screen' → name it 'Birkin'"
echo "  3. Open the app and say: 'Run the daily brief'"
echo ""
echo -e "${BOLD}Governance:${NC}"
echo "  ssh -i ~/.ssh/birkin_ed25519 root@${SERVER_IP} \\"
echo "    'cd /opt/birkin && ./scripts/governance-check.sh'"
echo ""
echo -e "${BOLD}Monthly cost breakdown:${NC}"
echo "  Hetzner ${SERVER_TYPE}:  €4.51/mo"
echo "  Cloudflare Tunnel: €0.00/mo"
echo "  OpenRouter API:    ~€5-20/mo (usage-based)"
echo "  Domain:            ~€1.00/mo"
echo "  ─────────────────────────────"
echo "  Total:             ~€10-25/mo"
echo ""
echo -e "${BOLD}GitHub:${NC} https://github.com/NickAiNYC/birkin"
echo ""

# ─── Save connection info ─────────────────────────────────────────────────────
cat > "$HOME/.birkin" <<INFO
# Birkin connection info — created $(date -u)
BIRKIN_SERVER_IP=${SERVER_IP}
BIRKIN_SERVER_NAME=${SERVER_NAME}
BIRKIN_DOMAIN=${DOMAIN}
BIRKIN_SSH_KEY=${SSH_KEY_PATH}
BIRKIN_INSTALLED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
INFO

log_ok "Connection info saved to ~/.birkin"
