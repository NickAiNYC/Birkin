#!/usr/bin/env bash
# =============================================================================
# Birkin — Production Deployment Script
# Version:  1.0.0
# Author:   Nick (@NickAiNYC)
# Target:   Hetzner CX22 (2 vCPU, 4 GB RAM, 40 GB SSD, Ubuntu 24.04)
# Runtime:  ~12-15 minutes on a fresh server
#
# WHAT THIS SCRIPT DOES (7 phases):
#   1. Provision a Hetzner CX22 server via hcloud CLI
#   2. Harden the server (non-root user, UFW, fail2ban, auto-updates)
#   3. Install Hermes Agent + configure OpenRouter + initialize audit.db
#   4. Install Docker + Open WebUI (Hermes-connected)
#   5. Install Cloudflare Tunnel (token-based, no manual dashboard steps)
#   6. Transfer project files (skills, scripts, health endpoint)
#   7. Deploy systemd services, cron jobs, and run acceptance tests
#
# IDEMPOTENCY:
#   Re-running the script on an existing server is safe. Server creation,
#   SSH key upload, and tunnel creation are all guarded with existence checks.
#
# VERIFICATION NOTICE — READ BEFORE RUNNING:
#   This script references Hermes Agent v0.13.0 by NousResearch. Before
#   running in production, verify the following at the official source:
#
#   ⚠️  VERIFY: https://github.com/NousResearch/hermes-agent
#       - Confirm v0.13.0 is the current stable release
#       - Confirm the install.sh URL and method shown below
#       - Confirm ~/.local/bin/hermes is the correct binary path
#       - Confirm `hermes gateway` is the correct API-server subcommand
#       - Confirm config.yaml location and supported keys
#       - Confirm SKILL.md discovery path (default: ~/.hermes/skills/)
#       - Confirm OpenAI-compatible endpoint path (default: /v1/*)
#
#   ⚠️  VERIFY: Open WebUI Docker image
#       - Confirm ghcr.io/open-webui/open-webui:main is current
#       - Confirm OPENAI_API_BASE_URL env var name
#
#   If any of the above cannot be confirmed, edit the relevant variables
#   in the CONFIGURATION section below before running.
#
# USAGE:
#   ./deploy.sh \
#     --hetzner-token   <HETZNER_API_TOKEN>  \
#     --cf-token        <CLOUDFLARE_API_TOKEN> \
#     --domain          <DOMAIN_NAME>          \
#     --openrouter-key  <OPENROUTER_API_KEY>   \
#     [--telegram-token <TELEGRAM_BOT_TOKEN>]  \
#     [--telegram-chat  <TELEGRAM_CHAT_ID>]    \
#     [--location       <HETZNER_DATACENTER>]  \
#     [--ssh-key-path   <PATH_TO_SSH_KEY>]
#
# MINIMAL EXAMPLE:
#   ./deploy.sh \
#     --hetzner-token hz_xxx \
#     --cf-token cf_xxx \
#     --domain agent.scrutexity.com \
#     --openrouter-key sk-or-v1-xxx
#
# FULL EXAMPLE (with Telegram):
#   ./deploy.sh \
#     --hetzner-token hz_xxx \
#     --cf-token cf_xxx \
#     --domain agent.scrutexity.com \
#     --openrouter-key sk-or-v1-xxx \
#     --telegram-token 123456:ABC \
#     --telegram-chat  -1001234567890
#
# SECRETS:
#   Never commit your filled-in command to git history.
#   Use a .env file + `source .env && ./deploy.sh ...` pattern.
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# ── Terminal colours ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }
phase()   { echo -e "\n${BOLD}${CYAN}━━━  $*  ━━━${NC}"; }
step()    { echo -e "  ${BOLD}▶${NC} $*"; }
hline()   { echo -e "${CYAN}$(printf '─%.0s' {1..72})${NC}"; }

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<'USAGE'
Usage: ./deploy.sh [OPTIONS]

Required:
  --hetzner-token   TOKEN   Hetzner Cloud API token
  --cf-token        TOKEN   Cloudflare API token (Tunnel + DNS permissions)
  --domain          FQDN    Fully-qualified domain (e.g. agent.scrutexity.com)
  --openrouter-key  KEY     OpenRouter API key (sk-or-v1-...)

Optional:
  --telegram-token  TOKEN   Telegram Bot token (enables alerting)
  --telegram-chat   ID      Telegram Chat ID (personal or group)
  --location        LOC     Hetzner datacenter (default: nbg1)
  --ssh-key-path    PATH    SSH key path (default: ~/.ssh/scrutexity_agent)
  --skip-provision          Skip server creation (re-deploy to existing server)
  --dry-run                 Print configuration and exit
  --help                    Show this help
USAGE
    exit 0
}

# ── Defaults ──────────────────────────────────────────────────────────────────
HETZNER_TOKEN=""
CF_TOKEN=""
DOMAIN=""
OPENROUTER_KEY=""
TG_BOT_TOKEN=""
TG_CHAT_ID=""
SERVER_LOCATION="nbg1"
SSH_KEY_PATH="${HOME}/.ssh/scrutexity_agent"
SKIP_PROVISION=false
DRY_RUN=false

SERVER_NAME="birkin"
SERVER_TYPE="cx22"
SERVER_IMAGE="ubuntu-24.04"
CF_TUNNEL_NAME="birkin"

# Ports (all internal — only 22 and 443 are open externally via UFW + CF Tunnel)
HERMES_PORT=8686
WEBUI_PORT=3000
HEALTH_PORT=9999

# ── Argument parsing ──────────────────────────────────────────────────────────
[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hetzner-token)  HETZNER_TOKEN="$2";   shift 2 ;;
        --cf-token)       CF_TOKEN="$2";         shift 2 ;;
        --domain)         DOMAIN="$2";           shift 2 ;;
        --openrouter-key) OPENROUTER_KEY="$2";   shift 2 ;;
        --telegram-token) TG_BOT_TOKEN="$2";     shift 2 ;;
        --telegram-chat)  TG_CHAT_ID="$2";       shift 2 ;;
        --location)       SERVER_LOCATION="$2";  shift 2 ;;
        --ssh-key-path)   SSH_KEY_PATH="$2";     shift 2 ;;
        --skip-provision) SKIP_PROVISION=true;   shift   ;;
        --dry-run)        DRY_RUN=true;          shift   ;;
        --help|-h)        usage ;;
        *) fail "Unknown argument: $1. Run ./deploy.sh --help" ;;
    esac
done

# ── Validate required arguments ───────────────────────────────────────────────
[[ -z "$HETZNER_TOKEN"  ]] && fail "--hetzner-token is required"
[[ -z "$CF_TOKEN"       ]] && fail "--cf-token is required"
[[ -z "$DOMAIN"         ]] && fail "--domain is required"
[[ -z "$OPENROUTER_KEY" ]] && fail "--openrouter-key is required"

# Basic domain validation (must contain at least one dot, no http/https)
[[ "$DOMAIN" =~ ^https?:// ]] && fail "--domain must not include http:// or https://"
[[ "$DOMAIN" != *"."* ]]      && fail "--domain must be a fully-qualified domain name"

# ── Dry-run ───────────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    info "=== DRY RUN — Configuration ==="
    echo "  Domain:          $DOMAIN"
    echo "  Hetzner Token:   [set, length=${#HETZNER_TOKEN}]"
    echo "  CF Token:        [set, length=${#CF_TOKEN}]"
    echo "  OpenRouter Key:  [set, length=${#OPENROUTER_KEY}]"
    echo "  Telegram Token:  ${TG_BOT_TOKEN:+[set]}"
    echo "  Telegram Chat:   ${TG_CHAT_ID:+[set]}"
    echo "  Location:        $SERVER_LOCATION"
    echo "  SSH Key:         $SSH_KEY_PATH"
    echo "  Skip Provision:  $SKIP_PROVISION"
    echo ""
    info "Dry run complete. Remove --dry-run to deploy."
    exit 0
fi

# ── Pre-flight: local dependency check ───────────────────────────────────────
phase "Pre-flight checks"

check_local_dep() {
    command -v "$1" &>/dev/null || fail "$1 is required but not installed. Install it and retry."
}
check_local_dep curl
check_local_dep jq
check_local_dep ssh
check_local_dep scp
check_local_dep ssh-keygen
ok "Local dependencies satisfied"

# ── SSH key ───────────────────────────────────────────────────────────────────
if [[ ! -f "$SSH_KEY_PATH" ]]; then
    step "Generating new SSH key at $SSH_KEY_PATH"
    ssh-keygen -t ed25519 -C "birkin-$(date +%Y%m%d)" -f "$SSH_KEY_PATH" -N ""
    ok "SSH key generated"
else
    ok "SSH key exists: $SSH_KEY_PATH"
fi
SSH_PUBKEY="$(cat "${SSH_KEY_PATH}.pub")"

# ── hcloud CLI ────────────────────────────────────────────────────────────────
if ! command -v hcloud &>/dev/null; then
    step "Installing hcloud CLI..."
    HCLOUD_VERSION=$(curl -s https://api.github.com/repos/hetznercloud/cli/releases/latest \
        | jq -r '.tag_name' 2>/dev/null || echo "v1.43.1")
    HCLOUD_URL="https://github.com/hetznercloud/cli/releases/download/${HCLOUD_VERSION}/hcloud-linux-amd64.tar.gz"
    curl -fsSL "$HCLOUD_URL" | tar -xzf - -C /tmp hcloud 2>/dev/null \
        || fail "Failed to download hcloud CLI from $HCLOUD_URL. Verify URL and retry."
    sudo mv /tmp/hcloud /usr/local/bin/hcloud
    sudo chmod +x /usr/local/bin/hcloud
    ok "hcloud CLI installed (${HCLOUD_VERSION})"
fi

# Configure hcloud context (idempotent)
hcloud context create scrutexity --token "$HETZNER_TOKEN" 2>/dev/null \
    || hcloud context use scrutexity 2>/dev/null \
    || true
ok "hcloud context configured"

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 1: Provision Hetzner CX22
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 1/7 — Provision Hetzner CX22"

if [[ "$SKIP_PROVISION" == false ]]; then
    # Register SSH key (idempotent)
    step "Registering SSH public key..."
    hcloud ssh-key create --name "birkin" --public-key "$SSH_PUBKEY" 2>/dev/null \
        || info "SSH key already registered (skipping)"

    # Create server (idempotent — check existence first)
    step "Creating server (${SERVER_TYPE}, ${SERVER_IMAGE}, ${SERVER_LOCATION})..."
    EXISTING_IP=$(hcloud server describe "$SERVER_NAME" --format json 2>/dev/null \
        | jq -r '.server.public_net.ipv4.ip' 2>/dev/null || true)

    if [[ -n "$EXISTING_IP" && "$EXISTING_IP" != "null" ]]; then
        SERVER_IP="$EXISTING_IP"
        info "Server already exists at $SERVER_IP — skipping creation"
    else
        SERVER_IP=$(hcloud server create \
            --name      "$SERVER_NAME" \
            --type      "$SERVER_TYPE" \
            --image     "$SERVER_IMAGE" \
            --location  "$SERVER_LOCATION" \
            --ssh-key   "birkin" \
            --format    json 2>/dev/null \
            | jq -r '.server.public_net.ipv4.ip')

        if [[ -z "$SERVER_IP" || "$SERVER_IP" == "null" ]]; then
            fail "Server creation failed. Check your Hetzner token and account limits."
        fi
        ok "Server created: $SERVER_IP"
    fi
else
    # --skip-provision: look up existing server
    SERVER_IP=$(hcloud server describe "$SERVER_NAME" --format json 2>/dev/null \
        | jq -r '.server.public_net.ipv4.ip' 2>/dev/null \
        || fail "Server '$SERVER_NAME' not found and --skip-provision was set. Create it first.")
    info "Using existing server: $SERVER_IP"
fi

ok "Server IP: ${BOLD}$SERVER_IP${NC}"

# Wait for SSH to become available (up to 3 minutes)
step "Waiting for SSH to be available..."
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes"
SSH_CMD="ssh $SSH_OPTS -i $SSH_KEY_PATH"
WAIT=0
until $SSH_CMD "root@$SERVER_IP" "echo ok" &>/dev/null; do
    WAIT=$((WAIT + 5))
    [[ $WAIT -ge 180 ]] && fail "SSH not available after 3 minutes. Check your server and SSH key."
    sleep 5
    echo -n "."
done
echo ""
ok "SSH available"

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 2: Server Hardening
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 2/7 — Server Hardening"

$SSH_CMD "root@$SERVER_IP" bash -s -- "$SSH_PUBKEY" <<'HARDEN'
set -euo pipefail

PUBKEY="$1"

echo "[HARDEN] Creating non-root user 'scrutexity'..."
id scrutexity &>/dev/null || useradd -m -s /bin/bash -G sudo scrutexity

# SSH key
mkdir -p /home/scrutexity/.ssh
chmod 700 /home/scrutexity/.ssh
echo "$PUBKEY" > /home/scrutexity/.ssh/authorized_keys
chmod 600 /home/scrutexity/.ssh/authorized_keys
chown -R scrutexity:scrutexity /home/scrutexity/.ssh

# Harden SSH (no root login, no passwords)
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/'            /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/'  /etc/ssh/sshd_config
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

echo "[HARDEN] Updating packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

apt-get install -y -qq \
    curl wget git jq sqlite3 python3 python3-pip python3-venv \
    ufw fail2ban unattended-upgrades \
    apt-transport-https ca-certificates gnupg lsb-release \
    software-properties-common htop logrotate

echo "[HARDEN] Configuring UFW firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp  comment 'SSH'
ufw allow 443/tcp comment 'Cloudflare Tunnel HTTPS'
ufw --force enable

echo "[HARDEN] Configuring fail2ban..."
cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3
backend  = systemd

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
JAIL
systemctl enable fail2ban --quiet
systemctl restart fail2ban

echo "[HARDEN] Configuring unattended-upgrades (security only)..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'UPGRADES'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UPGRADES
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AUTO'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTO
systemctl enable unattended-upgrades --quiet

echo "[HARDEN] Creating log directory..."
mkdir -p /var/log/scrutexity
chown scrutexity:scrutexity /var/log/scrutexity

echo "[HARDEN] Setting up logrotate..."
cat > /etc/logrotate.d/scrutexity <<'LOGROTATE'
/var/log/scrutexity/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 scrutexity scrutexity
}
LOGROTATE

echo "[HARDEN] Hardening complete."
HARDEN

ok "Server hardened"

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 3: Hermes Agent
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 3/7 — Hermes Agent v0.13.0"

info "⚠️  VERIFY BEFORE RUNNING: Confirm Hermes install URL at https://github.com/NousResearch/hermes-agent"
info "    If the install script URL below has changed, update HERMES_INSTALL_URL in this script."

$SSH_CMD "birkin@$SERVER_IP" bash -s -- "$OPENROUTER_KEY" "$HERMES_PORT" <<'HERMES'
set -euo pipefail
OPENROUTER_KEY="$1"
HERMES_PORT="$2"

echo "[HERMES] Installing Hermes Agent..."
# VERIFY: Confirm this URL is current at https://github.com/NousResearch/hermes-agent
# If this 404s, download the release tarball manually and adjust accordingly.
HERMES_INSTALL_URL="https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh"

if ! command -v hermes &>/dev/null; then
    if curl -fsSL --head "$HERMES_INSTALL_URL" 2>/dev/null | grep -q "200"; then
        curl -fsSL "$HERMES_INSTALL_URL" | bash
    else
        echo "ERROR: Hermes install script not reachable at $HERMES_INSTALL_URL"
        echo "VERIFY: Check https://github.com/NousResearch/hermes-agent for current installation instructions"
        echo "MANUAL: Download release tarball and extract to ~/.local/bin/ then re-run deploy.sh --skip-provision"
        exit 1
    fi
else
    echo "[HERMES] Hermes binary already installed, skipping installation"
fi

export PATH="$HOME/.local/bin:$PATH"

# Verify installation
if ! hermes --version &>/dev/null; then
    echo "ERROR: Hermes binary not found at ~/.local/bin/hermes after installation"
    echo "VERIFY: Check https://github.com/NousResearch/hermes-agent for correct binary path"
    exit 1
fi

HERMES_VERSION=$(hermes --version 2>/dev/null | head -1 || echo "unknown")
echo "[HERMES] Installed: $HERMES_VERSION"

# Directory structure
mkdir -p \
    ~/.hermes/skills \
    ~/.hermes/scripts \
    ~/.hermes/cron/output/daily-brief \
    ~/.hermes/cron/output/telegram-failures \
    ~/.hermes/cron/output/queued-alerts \
    ~/.hermes/drift \
    ~/briefs \
    /backups/hermes

# Generate a strong random API key for the Hermes gateway
API_KEY=$(openssl rand -hex 32)

echo "[HERMES] Writing .env..."
cat > ~/.hermes/.env <<ENV
# Birkin — Hermes Configuration
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# WARNING: Do not commit this file to git

OPENROUTER_API_KEY=${OPENROUTER_KEY}
API_SERVER_ENABLED=true
API_SERVER_PORT=${HERMES_PORT}
API_SERVER_HOST=127.0.0.1
API_SERVER_KEY=${API_KEY}
API_SERVER_MODEL_NAME=birkin
ENV
chmod 600 ~/.hermes/.env

echo "[HERMES] Writing config.yaml..."
# VERIFY: Check https://github.com/NousResearch/hermes-agent for current config.yaml schema
# Model names below use OpenRouter format — verify model slugs at https://openrouter.ai/models
cat > ~/.hermes/config.yaml <<'CONFIG'
# Birkin — Hermes Agent Configuration
# VERIFY: Config keys and model names before deploying to production

model: "openrouter"

provider_routing:
  sort: "price"
  ignore: ["Together", "Lepton"]
  require_parameters: true
  data_collection: "deny"

# Primary + fallback model chain
# VERIFY: These model slugs at https://openrouter.ai/models
models:
  primary:   "anthropic/claude-sonnet-4"
  fallback1: "anthropic/claude-haiku-4.5"
  fallback2: "google/gemini-2.5-flash"

auxiliary_models:
  session_title:       "google/gemini-2.5-flash"
  context_compression: "google/gemini-2.5-flash"
  web_summarization:   "google/gemini-2.5-flash"
  vision_analysis:     "anthropic/claude-haiku-4.5"

platforms:
  api_server:
    enabled: true
    toolsets: [core, web_research, terminal, file, messaging, skills]
  cron:
    enabled: true
    toolsets: [core, web_research, file, messaging, skills]

memory:
  provider: "built_in"
  max_tokens: 2200

audit:
  enabled: true
  store: "sqlite"
  db_path: "~/.hermes/audit.db"
  log_tokens: true
  log_costs: true

skills:
  # VERIFY: Confirm Hermes skills discovery path at https://github.com/NousResearch/hermes-agent
  path: "~/.hermes/skills"
  auto_discover: true
CONFIG

echo "[HERMES] Initializing hash-chained audit database schema..."
sqlite3 ~/.hermes/audit.db < "$(dirname "$0")/scripts/audit-init.sql"
echo "[HERMES] audit.db schema initialized (append-only triggers + SHA-256 chain)"

# Initialise skills git repo
cd ~/.hermes/skills
git init 2>/dev/null || true
git config --local user.email "agent@scrutexity.com"
git config --local user.name  "Birkin"

echo "[HERMES] Phase 3 complete."
HERMES

ok "Hermes Agent installed and configured"

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 4: Docker + Open WebUI
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 4/7 — Docker + Open WebUI"

$SSH_CMD "birkin@$SERVER_IP" bash -s -- "$HERMES_PORT" "$WEBUI_PORT" <<'DOCKER'
set -euo pipefail
HERMES_PORT="$1"
WEBUI_PORT="$2"

echo "[DOCKER] Installing Docker CE..."
# Only install if not already present
if ! command -v docker &>/dev/null; then
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
else
    echo "[DOCKER] Docker already installed, skipping"
fi

sudo usermod -aG docker scrutexity 2>/dev/null || true
sudo systemctl enable docker --quiet
sudo systemctl start docker

# Read API key from .env (already written in Phase 3)
API_KEY=$(grep '^API_SERVER_KEY=' ~/.hermes/.env | cut -d= -f2)
if [[ -z "$API_KEY" ]]; then
    echo "ERROR: API_SERVER_KEY not found in ~/.hermes/.env"
    exit 1
fi

echo "[DOCKER] Starting Open WebUI..."
# VERIFY: Confirm this image tag at https://github.com/open-webui/open-webui
WEBUI_IMAGE="ghcr.io/open-webui/open-webui:main"

# Stop existing container if present (idempotent)
docker rm -f open-webui 2>/dev/null || true

# Wait for Docker socket to be ready
sleep 3

docker run -d \
    -p "${WEBUI_PORT}:8080" \
    -e OPENAI_API_BASE_URL="http://host.docker.internal:${HERMES_PORT}/v1" \
    -e OPENAI_API_KEY="$API_KEY" \
    -e ENABLE_OLLAMA_API=false \
    -e ENABLE_SIGNUP=false \
    -e DEFAULT_MODELS="birkin" \
    --add-host=host.docker.internal:host-gateway \
    -v open-webui:/app/backend/data \
    --name open-webui \
    --restart always \
    --health-cmd  "curl -sf http://localhost:8080/health || exit 1" \
    --health-interval 15s \
    --health-timeout  5s \
    --health-retries  5 \
    "$WEBUI_IMAGE"

echo "[DOCKER] Waiting for Open WebUI to become healthy (up to 90 seconds)..."
WAIT=0
until docker inspect --format='{{.State.Health.Status}}' open-webui 2>/dev/null | grep -q "healthy"; do
    WAIT=$((WAIT + 5))
    if [[ $WAIT -ge 90 ]]; then
        echo "WARNING: Open WebUI health check did not pass in 90s — continuing anyway"
        echo "         Check: docker logs open-webui"
        break
    fi
    sleep 5
    echo -n "."
done
echo ""

CONTAINER_STATUS=$(docker ps --format '{{.Status}}' --filter name=open-webui 2>/dev/null | head -1)
echo "[DOCKER] Container status: $CONTAINER_STATUS"
echo "[DOCKER] Phase 4 complete."
DOCKER

ok "Docker + Open WebUI deployed"

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 5: Cloudflare Tunnel
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 5/7 — Cloudflare Tunnel"

info "Using token-based authentication — no browser dashboard steps required"
info "Tunnel will create DNS records automatically for: $DOMAIN and health.$DOMAIN"
warn "Manual step required: Ensure your Cloudflare token has 'Cloudflare Tunnel' + 'DNS:Edit' permissions for this zone"

$SSH_CMD "birkin@$SERVER_IP" bash -s -- "$CF_TOKEN" "$DOMAIN" "$WEBUI_PORT" "$HEALTH_PORT" <<'CF'
set -euo pipefail
CF_TOKEN="$1"
DOMAIN="$2"
WEBUI_PORT="$3"
HEALTH_PORT="$4"

echo "[CF] Installing cloudflared..."
if ! command -v cloudflared &>/dev/null; then
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
        | sudo tee /usr/share/keyrings/cloudflare-main.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] \
        https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" \
        | sudo tee /etc/apt/sources.list.d/cloudflared.list > /dev/null
    sudo apt-get update -qq && sudo apt-get install -y -qq cloudflared
else
    echo "[CF] cloudflared already installed"
fi

echo "[CF] Authenticating tunnel (token-based)..."
# Token-based auth — no browser interaction needed
# MANUAL STEP: Create the tunnel token in Cloudflare dashboard -> Zero Trust -> Networks -> Tunnels
# Then pass it here as --cf-token
# If using API token (not tunnel token), the login flow below will work:
cloudflared tunnel login --token "$CF_TOKEN" 2>/dev/null \
    || cloudflared tunnel login 2>/dev/null \
    || {
        echo "WARNING: Token-based auth failed. If you're using an API token (not a tunnel token),"
        echo "         you may need to complete browser authentication separately."
        echo "         See: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/"
    }

echo "[CF] Creating tunnel (idempotent)..."
TUNNEL_ID=$(cloudflared tunnel list --output json 2>/dev/null \
    | jq -r ".[] | select(.name==\"birkin\") | .id" 2>/dev/null || echo "")

if [[ -z "$TUNNEL_ID" || "$TUNNEL_ID" == "null" ]]; then
    TUNNEL_CREATE_OUTPUT=$(cloudflared tunnel create "birkin" 2>&1)
    echo "$TUNNEL_CREATE_OUTPUT"
    TUNNEL_ID=$(echo "$TUNNEL_CREATE_OUTPUT" | grep -oP 'Created tunnel .+ with id \K[a-z0-9-]+' \
        || echo "$TUNNEL_CREATE_OUTPUT" | grep -oP '[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}' | head -1)
fi

if [[ -z "$TUNNEL_ID" || "$TUNNEL_ID" == "null" ]]; then
    echo "ERROR: Could not create or find Cloudflare tunnel"
    echo "VERIFY: Run 'cloudflared tunnel list' manually on the server"
    exit 1
fi
echo "[CF] Tunnel ID: $TUNNEL_ID"

CREDENTIALS_FILE="/home/scrutexity/.cloudflared/${TUNNEL_ID}.json"

mkdir -p /home/scrutexity/.cloudflared

echo "[CF] Writing tunnel config..."
cat > /home/scrutexity/.cloudflared/config.yml <<CFCONFIG
tunnel: ${TUNNEL_ID}
credentials-file: ${CREDENTIALS_FILE}

ingress:
  - hostname: ${DOMAIN}
    service: http://localhost:${WEBUI_PORT}
    originRequest:
      noTLSVerify: false
      connectTimeout: 10s
  - hostname: health.${DOMAIN}
    service: http://localhost:${HEALTH_PORT}
    originRequest:
      noTLSVerify: false
      connectTimeout: 5s
  - service: http_status:404
CFCONFIG

echo "[CF] Routing DNS records (idempotent)..."
cloudflared tunnel route dns "birkin" "$DOMAIN"      2>/dev/null \
    || echo "WARNING: DNS route for $DOMAIN already exists or failed — check dashboard"
cloudflared tunnel route dns "birkin" "health.$DOMAIN" 2>/dev/null \
    || echo "WARNING: DNS route for health.$DOMAIN already exists or failed"

echo "[CF] Installing cloudflared as system service..."
sudo cloudflared service install 2>/dev/null || true
sudo systemctl enable cloudflared --quiet
sudo systemctl restart cloudflared

sleep 3
CLOUDFLARED_STATUS=$(systemctl is-active cloudflared 2>/dev/null || echo "unknown")
echo "[CF] cloudflared status: $CLOUDFLARED_STATUS"
echo "[CF] Phase 5 complete."
CF

ok "Cloudflare Tunnel deployed"

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 6: Transfer Project Files
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 6/7 — Transfer Project Files"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

$SSH_CMD "birkin@$SERVER_IP" "mkdir -p ~/birkin/scripts ~/birkin/skills ~/birkin/health ~/birkin/systemd"

# Transfer skills
step "Transferring SKILL.md files..."
if ls "$SCRIPT_DIR/skills/"*.md &>/dev/null 2>&1; then
    scp $SSH_OPTS -i "$SSH_KEY_PATH" "$SCRIPT_DIR/skills/"*.md "birkin@$SERVER_IP:~/birkin/skills/"
    ok "Skills transferred ($(ls "$SCRIPT_DIR/skills/"*.md | wc -l) files)"
else
    warn "No .md files found in $SCRIPT_DIR/skills/ — skills not transferred"
fi

# Transfer scripts
step "Transferring governance scripts..."
if ls "$SCRIPT_DIR/scripts/"*.sh &>/dev/null 2>&1; then
    scp $SSH_OPTS -i "$SSH_KEY_PATH" "$SCRIPT_DIR/scripts/"*.sh "birkin@$SERVER_IP:~/birkin/scripts/"
fi
if ls "$SCRIPT_DIR/scripts/"*.py &>/dev/null 2>&1; then
    scp $SSH_OPTS -i "$SSH_KEY_PATH" "$SCRIPT_DIR/scripts/"*.py "birkin@$SERVER_IP:~/birkin/scripts/"
fi
ok "Governance scripts transferred"

# Transfer health endpoint
step "Transferring health endpoint..."
if ls "$SCRIPT_DIR/health/"*.py &>/dev/null 2>&1; then
    scp $SSH_OPTS -i "$SSH_KEY_PATH" "$SCRIPT_DIR/health/"*.py "birkin@$SERVER_IP:~/birkin/health/"
    ok "Health endpoint transferred"
else
    warn "No .py files found in $SCRIPT_DIR/health/"
fi

ok "Phase 6 complete"

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 7: Deploy Services + Acceptance Tests
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 7/7 — Deploy Services + Acceptance Tests"

$SSH_CMD "birkin@$SERVER_IP" bash -s -- "$HERMES_PORT" "$HEALTH_PORT" "$DOMAIN" "$TG_BOT_TOKEN" "$TG_CHAT_ID" <<'FINAL'
set -euo pipefail
HERMES_PORT="$1"
HEALTH_PORT="$2"
DOMAIN="$3"
TG_BOT_TOKEN="$4"
TG_CHAT_ID="$5"

export PATH="$HOME/.local/bin:$PATH"

# ── Python dependencies for health endpoint ──────────────────────────────────
echo "[FINAL] Installing Python dependencies..."
python3 -m pip install --user --quiet flask requests 2>/dev/null \
    || sudo apt-get install -y -qq python3-flask python3-requests 2>/dev/null \
    || echo "WARNING: Could not install Flask — health endpoint may fail to start"

# ── Copy files into place ────────────────────────────────────────────────────
echo "[FINAL] Deploying files..."

# Skills to Hermes skills dir
if ls ~/birkin/skills/*.md &>/dev/null 2>&1; then
    cp ~/birkin/skills/*.md ~/.hermes/skills/
fi

# Governance scripts
if ls ~/birkin/scripts/*.sh &>/dev/null 2>&1; then
    cp ~/birkin/scripts/*.sh ~/.hermes/scripts/
    chmod +x ~/.hermes/scripts/*.sh
fi
if ls ~/birkin/scripts/*.py &>/dev/null 2>&1; then
    cp ~/birkin/scripts/*.py ~/.hermes/scripts/
    chmod +x ~/.hermes/scripts/*.py
fi

# Convenience symlinks to home directory
ln -sf ~/.hermes/scripts ~/scripts 2>/dev/null || true

# ── Commit initial skill set to git ─────────────────────────────────────────
cd ~/.hermes/skills
git add -A 2>/dev/null || true
git diff --cached --quiet || git commit -m "chore: initial skill set v1.0.0 [$(date -u +%Y-%m-%dT%H:%M:%SZ)]" 2>/dev/null || true

# ── Append Telegram credentials to .env (if provided) ────────────────────────
if [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
    echo "[FINAL] Adding Telegram credentials to .env..."
    # Remove any existing Telegram lines first (idempotent)
    sed -i '/^TELEGRAM_BOT_TOKEN=/d; /^TELEGRAM_CHAT_ID=/d' ~/.hermes/.env
    cat >> ~/.hermes/.env <<TG_ENV
TELEGRAM_BOT_TOKEN=${TG_BOT_TOKEN}
TELEGRAM_CHAT_ID=${TG_CHAT_ID}
TG_ENV
fi

# ── systemd: Hermes Gateway ───────────────────────────────────────────────────
echo "[FINAL] Writing hermes-gateway.service..."
sudo tee /etc/systemd/system/hermes-gateway.service > /dev/null <<HERMES_SVC
[Unit]
Description=Hermes Agent Gateway (Birkin)
Documentation=https://github.com/NousResearch/hermes-agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=scrutexity
Group=scrutexity
WorkingDirectory=/home/scrutexity
Environment=HOME=/home/scrutexity
Environment=PATH=/home/scrutexity/.local/bin:/usr/local/bin:/usr/bin:/bin
EnvironmentFile=/home/scrutexity/.hermes/.env
# VERIFY: Confirm 'hermes gateway' is the correct subcommand
ExecStart=/home/scrutexity/.local/bin/hermes gateway
Restart=always
RestartSec=10
StartLimitIntervalSec=60
StartLimitBurst=3
StandardOutput=append:/var/log/scrutexity/hermes-gateway.log
StandardError=append:/var/log/scrutexity/hermes-gateway.log
SyslogIdentifier=hermes-gateway

[Install]
WantedBy=multi-user.target
HERMES_SVC

# ── systemd: Health Endpoint ──────────────────────────────────────────────────
echo "[FINAL] Writing birkin-health.service..."
sudo tee /etc/systemd/system/birkin-health.service > /dev/null <<HEALTH_SVC
[Unit]
Description=Birkin Health Endpoint
After=network.target hermes-gateway.service

[Service]
Type=simple
User=scrutexity
Group=scrutexity
WorkingDirectory=/home/scrutexity/birkin/health
Environment=HOME=/home/scrutexity
Environment=PATH=/home/scrutexity/.local/bin:/usr/local/bin:/usr/bin:/bin
Environment=HEALTH_PORT=${HEALTH_PORT}
Environment=HERMES_AUDIT_DB=/home/scrutexity/.hermes/audit.db
Environment=HERMES_SKILLS_DIR=/home/scrutexity/.hermes/skills
Environment=HERMES_HOME=/home/scrutexity/.hermes
ExecStart=/usr/bin/python3 /home/scrutexity/birkin/health/health_endpoint.py
Restart=always
RestartSec=5
StandardOutput=append:/var/log/scrutexity/health.log
StandardError=append:/var/log/scrutexity/health.log
SyslogIdentifier=scrutexity-health

[Install]
WantedBy=multi-user.target
HEALTH_SVC

# ── systemd: Daily Backup ─────────────────────────────────────────────────────
echo "[FINAL] Writing backup service + timer..."
sudo tee /etc/systemd/system/scrutexity-backup.service > /dev/null <<'BACKUP_SVC'
[Unit]
Description=Birkin Daily Backup

[Service]
Type=oneshot
User=scrutexity
ExecStart=/bin/bash -c ' \
    STAMP=$(date +%%Y%%m%%d-%%H%%M%%S); \
    mkdir -p /backups/hermes; \
    tar czf /backups/hermes/hermes-${STAMP}.tar.gz \
        --exclude=~/.hermes/audit.db-wal \
        --exclude=~/.hermes/audit.db-shm \
        -C /home/scrutexity .hermes 2>/dev/null; \
    find /backups/hermes -name "hermes-*.tar.gz" -mtime +7 -delete; \
    echo "Backup complete: hermes-${STAMP}.tar.gz" '
StandardOutput=append:/var/log/scrutexity/backup.log
StandardError=append:/var/log/scrutexity/backup.log
BACKUP_SVC

sudo tee /etc/systemd/system/scrutexity-backup.timer > /dev/null <<'BACKUP_TIMER'
[Unit]
Description=Birkin — daily backup at 03:00 UTC

[Timer]
OnCalendar=*-*-* 03:00:00 UTC
Persistent=true

[Install]
WantedBy=timers.target
BACKUP_TIMER

# ── Enable and start all services ────────────────────────────────────────────
echo "[FINAL] Enabling and starting services..."
sudo systemctl daemon-reload
sudo systemctl enable hermes-gateway birkin-health scrutexity-backup.timer --quiet
sudo systemctl start hermes-gateway birkin-health || true
sudo systemctl start scrutexity-backup.timer

sleep 8

# ── Hermes cron jobs ─────────────────────────────────────────────────────────
echo "[FINAL] Registering Hermes cron jobs..."
# VERIFY: Confirm 'hermes cron create' syntax at https://github.com/NousResearch/hermes-agent
# If this command doesn't exist, register jobs via Hermes config.yaml cron section or system cron
hermes cron create \
    "0 11 * * *" \
    "Run daily-brief skill and deliver to Telegram" \
    --name "daily-brief" \
    --skill daily-brief 2>/dev/null \
    || echo "WARNING: Could not register daily-brief cron — register manually in Hermes"

hermes cron create \
    "0 13 * * 1" \
    "Run sourcing-intel skill for 1688/Korean pipeline" \
    --name "weekly-sourcing" \
    --skill sourcing-intel 2>/dev/null \
    || echo "WARNING: Could not register weekly-sourcing cron"

hermes cron create \
    "0 22 * * 0" \
    "Run competitor-monitor skill" \
    --name "competitor-monitor" \
    --skill competitor-monitor 2>/dev/null \
    || echo "WARNING: Could not register competitor-monitor cron"

hermes cron create \
    "0 0,6,12,18 * * *" \
    "Run directora-health check" \
    --name "directora-health" \
    --skill directora-health 2>/dev/null \
    || echo "WARNING: Could not register directora-health cron"

echo "[FINAL] Cron jobs registered."

# ════════════════════════════════════════════════════════════════════════════
# ACCEPTANCE TESTS
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ACCEPTANCE TESTS"
echo "═══════════════════════════════════════════════════════════"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

atest_pass() { echo "  ✅ $1"; PASS_COUNT=$((PASS_COUNT+1)); }
atest_fail() { echo "  ❌ $1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
atest_warn() { echo "  ⚠️  $1"; WARN_COUNT=$((WARN_COUNT+1)); }

# T1: Health endpoint
HTTP_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${HEALTH_PORT}/health" 2>/dev/null || echo "000")
[[ "$HTTP_HEALTH" == "200" ]] \
    && atest_pass "T1: Health endpoint returns HTTP 200" \
    || atest_fail "T1: Health endpoint returned HTTP $HTTP_HEALTH (expected 200)"

# T2: Health JSON valid
HEALTH_JSON=$(curl -s "http://127.0.0.1:${HEALTH_PORT}/health" 2>/dev/null)
echo "$HEALTH_JSON" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null \
    && atest_pass "T2: Health endpoint returns valid JSON" \
    || atest_fail "T2: Health endpoint JSON is invalid"

# T3: Hermes API
HTTP_HERMES=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${HERMES_PORT}/health" 2>/dev/null || echo "000")
[[ "$HTTP_HERMES" == "200" ]] \
    && atest_pass "T3: Hermes API health returns HTTP 200" \
    || atest_fail "T3: Hermes API health returned HTTP $HTTP_HERMES — check: systemctl status hermes-gateway"

# T4: Skills loaded
SKILL_COUNT=$(ls ~/.hermes/skills/*.md 2>/dev/null | wc -l)
[[ "$SKILL_COUNT" -ge 5 ]] \
    && atest_pass "T4: Skills loaded ($SKILL_COUNT .md files in ~/.hermes/skills/)" \
    || { [[ "$SKILL_COUNT" -gt 0 ]] \
        && atest_warn "T4: Only $SKILL_COUNT skill(s) found (expected 5+)" \
        || atest_fail "T4: No skills found in ~/.hermes/skills/"; }

# T5: Governance check
GOV_OUTPUT=$(bash ~/.hermes/scripts/governance-check.sh 2>&1 || true)
echo "$GOV_OUTPUT" | grep -q "AGENT GOVERNANCE INTACT" \
    && atest_pass "T5: Governance check passes (AGENT GOVERNANCE INTACT)" \
    || atest_warn "T5: Governance check has issues — review output above"

# T6: Safety kill-switch scripts present
[[ -f ~/.hermes/scripts/agent-stop.sh && -x ~/.hermes/scripts/agent-stop.sh ]] \
    && atest_pass "T6: agent-stop.sh present and executable" \
    || atest_warn "T6: agent-stop.sh missing — deploy scripts and re-run"
[[ -f ~/.hermes/scripts/agent-lockdown.sh && -x ~/.hermes/scripts/agent-lockdown.sh ]] \
    && atest_pass "T6: agent-lockdown.sh present and executable" \
    || atest_warn "T6: agent-lockdown.sh missing"

# T7: Services survive (systemd enabled check)
systemctl is-enabled hermes-gateway       --quiet && atest_pass "T7: hermes-gateway enabled for boot" || atest_fail "T7: hermes-gateway not enabled"
systemctl is-enabled birkin-health --quiet && atest_pass "T7: birkin-health enabled for boot" || atest_fail "T7: health endpoint not enabled"
systemctl is-enabled scrutexity-backup.timer --quiet && atest_pass "T7: daily backup timer enabled" || atest_warn "T7: backup timer not enabled"

# T8: Telegram test
if [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
    TG_RESP=$(curl -sf -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "text=%E2%9C%85+Birkin+Agent+deployed+and+passing+acceptance+tests+on+${DOMAIN}" \
        2>/dev/null || echo '{"ok":false}')
    echo "$TG_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('ok') else 1)" 2>/dev/null \
        && atest_pass "T8: Telegram test message delivered successfully" \
        || atest_warn "T8: Telegram test failed — check BOT_TOKEN and CHAT_ID"
else
    atest_warn "T8: Telegram not configured (--telegram-token / --telegram-chat not provided)"
fi

# T9: Cloudflare domain (may need DNS propagation)
CF_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "https://${DOMAIN}/" 2>/dev/null || echo "000")
[[ "$CF_STATUS" == "200" || "$CF_STATUS" == "302" || "$CF_STATUS" == "301" ]] \
    && atest_pass "T9: Cloudflare domain reachable (HTTP $CF_STATUS)" \
    || atest_warn "T9: https://$DOMAIN returned HTTP $CF_STATUS — DNS may still be propagating (wait 5-10 min)"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  RESULTS: ✅ $PASS_COUNT passed | ⚠️  $WARN_COUNT warnings | ❌ $FAIL_COUNT failed"
echo "═══════════════════════════════════════════════════════════"

[[ "$FAIL_COUNT" -gt 0 ]] && echo "  ❌ Deployment has $FAIL_COUNT critical failures — review above" && exit 1
echo "  ✅ Deployment complete — all critical tests passing"
echo "[FINAL] Phase 7 complete."
FINAL

# ════════════════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ════════════════════════════════════════════════════════════════════════════
hline
echo ""
echo -e "${BOLD}${GREEN}  🚀  Birkin v1.0.0 — DEPLOYMENT COMPLETE${NC}"
echo ""
echo -e "  ${BOLD}Agent URL:${NC}   https://${DOMAIN}"
echo -e "  ${BOLD}Health URL:${NC}  https://health.${DOMAIN}/health"
echo -e "  ${BOLD}Server:${NC}      ssh -i ${SSH_KEY_PATH} birkin@${SERVER_IP}"
echo ""
echo -e "${BOLD}  iPhone Setup:${NC}"
echo "  1. Open Safari → https://${DOMAIN}"
echo "  2. Share → Add to Home Screen → tap the icon to open as PWA"
echo "  3. Enable Voice in Open WebUI settings for hands-free control"
echo ""
echo -e "${BOLD}  Governance Commands (on server):${NC}"
echo "  ./scripts/governance-check.sh      — Full validation"
echo "  ./scripts/audit-log.sh --today     — Today's agent actions"
echo "  ./scripts/audit-log.sh --cost      — Monthly cost estimate"
echo "  ./scripts/drift-check.sh           — Behavior drift detection"
echo "  ./scripts/skill-diff.sh            — Recent skill changes"
echo ""
echo -e "${BOLD}  Kill Switches:${NC}"
echo "  ./scripts/agent-stop.sh            — Gracefully stop all services"
echo "  ./scripts/agent-lockdown.sh        — Restrict outbound access"
hline
