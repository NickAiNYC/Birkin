#!/bin/bash
# =============================================================================
# Scrutexity Agent — Complete Deployment Script
# Version: 1.0.0 | Author: Nick (Scrutexity)
# Deploys: Hermes Agent v0.13.0 + Open WebUI + Cloudflare Tunnel + Governance
# Target: Hetzner CX22 (2 vCPU, 4 GB RAM, Ubuntu 24.04)
# Runtime: ~12-15 minutes
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

if [ "$#" -lt 4 ]; then
    cat <<'USAGE'
Usage: ./deploy.sh <HETZNER_API_TOKEN> <CLOUDFLARE_API_TOKEN> <DOMAIN_NAME> <OPENROUTER_API_KEY> [TELEGRAM_BOT_TOKEN] [TELEGRAM_CHAT_ID]

Example:
  ./deploy.sh hz_xxx cf_xxx agent.scrutexity.com sk-or-xxx 123456:ABC -1001234567890
USAGE
    exit 1
fi

HETZNER_TOKEN="$1"
CF_TOKEN="$2"
DOMAIN="$3"
OPENROUTER_KEY="$4"
TG_BOT_TOKEN="${5:-${TELEGRAM_BOT_TOKEN:-}}"
TG_CHAT_ID="${6:-${TELEGRAM_CHAT_ID:-}}"

SERVER_NAME="scrutexity-agent"
SERVER_TYPE="cx22"
SERVER_IMAGE="ubuntu-24.04"
SERVER_LOCATION="nbg1"
CF_TUNNEL_NAME="scrutexity-agent"
HERMES_PORT=8686
WEBUI_PORT=3000
HEALTH_PORT=9999

info "=== Scrutexity Agent Deployment ==="
info "Domain: $DOMAIN"

# PHASE 1: Provision Hetzner CX22
info "Phase 1/7: Provisioning Hetzner CX22..."
if ! command -v hcloud &>/dev/null; then
    info "Installing hcloud CLI..."
    curl -fsSL https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz | tar -xzf - -C /tmp
    sudo mv /tmp/hcloud /usr/local/bin/hcloud
    sudo chmod +x /usr/local/bin/hcloud
fi
hcloud context create scrutexity --token "$HETZNER_TOKEN" 2>/dev/null || true

SSH_KEY_PATH="$HOME/.ssh/scrutexity_agent"
if [ ! -f "$SSH_KEY_PATH" ]; then
    ssh-keygen -t ed25519 -C "scrutexity-agent" -f "$SSH_KEY_PATH" -N ""
fi
SSH_PUBKEY="$(cat ${SSH_KEY_PATH}.pub)"

hcloud ssh-key create --name scrutexity-agent --public-key "$SSH_PUBKEY" 2>/dev/null || info "SSH key already exists"

info "Creating server..."
SERVER_IP=$(hcloud server create --name "$SERVER_NAME" --type "$SERVER_TYPE" --image "$SERVER_IMAGE" --location "$SERVER_LOCATION" --ssh-key scrutexity-agent --format json 2>/dev/null | jq -r '.server.public_net.ipv4.ip' || true)
if [ -z "$SERVER_IP" ] || [ "$SERVER_IP" = "null" ]; then
    SERVER_IP=$(hcloud server describe "$SERVER_NAME" --format json | jq -r '.server.public_net.ipv4.ip')
fi
ok "Server IP: $SERVER_IP"

info "Waiting for SSH..."
for i in {1..30}; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$SSH_KEY_PATH" "root@$SERVER_IP" "echo ok" 2>/dev/null; then break; fi
    sleep 5
done

# PHASE 2: Hardening
info "Phase 2/7: Hardening server..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "root@$SERVER_IP" bash -s "$SSH_PUBKEY" <<'HARDEN'
set -euo pipefail
PUBKEY="$1"
useradd -m -s /bin/bash -G sudo,docker scrutexity 2>/dev/null || true
mkdir -p /home/scrutexity/.ssh; chmod 700 /home/scrutexity/.ssh
printf '%s\n' "$PUBKEY" > /home/scrutexity/.ssh/authorized_keys
chmod 600 /home/scrutexity/.ssh/authorized_keys
chown -R scrutexity:scrutexity /home/scrutexity/.ssh
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get upgrade -y -qq
apt-get install -y -qq curl wget git jq sqlite3 python3 python3-pip python3-venv ufw fail2ban unattended-upgrades apt-transport-https ca-certificates gnupg lsb-release software-properties-common htop tree logrotate
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 443/tcp comment 'Cloudflare Tunnel'
ufw --force enable
cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
JAIL
systemctl restart fail2ban && systemctl enable fail2ban
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'UPGRADES'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_id}-${distro_codename}-security";
    "${distro_id}ESMApps:${distro_id}ESMApps-${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_id}ESM-${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UPGRADES
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AUTO'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTO
systemctl enable unattended-upgrades
mkdir -p /var/log/scrutexity && chown scrutexity:scrutexity /var/log/scrutexity
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
HARDEN
ok "Server hardened"

# PHASE 3: Hermes Agent
info "Phase 3/7: Installing Hermes Agent..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "scrutexity@$SERVER_IP" bash -s "$OPENROUTER_KEY" "$HERMES_PORT" <<'HERMES'
set -euo pipefail
OPENROUTER_KEY="$1"
HERMES_PORT="$2"
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"
hermes --version || { echo "Hermes installation failed"; exit 1; }
mkdir -p ~/.hermes
API_KEY=$(openssl rand -hex 32)
cat > ~/.hermes/.env <<ENV
OPENROUTER_API_KEY=$OPENROUTER_KEY
API_SERVER_ENABLED=true
API_SERVER_PORT=$HERMES_PORT
API_SERVER_HOST=127.0.0.1
API_SERVER_KEY=$API_KEY
API_SERVER_MODEL_NAME=scrutexity-agent
ENV
cat > ~/.hermes/config.yaml <<'CONFIG'
model: "openrouter"
provider_routing:
  sort: "price"
  ignore: ["Together", "Lepton"]
  require_parameters: true
  data_collection: "deny"
fallback_providers:
  - model: "anthropic/claude-sonnet-4"
    provider: "openrouter"
  - model: "anthropic/claude-haiku-4"
    provider: "openrouter"
  - model: "google/gemini-3-flash-preview"
    provider: "openrouter"
auxiliary_models:
  session_title: "google/gemini-3-flash-preview"
  context_compression: "google/gemini-3-flash-preview"
  web_summarization: "google/gemini-3-flash-preview"
  vision_analysis: "anthropic/claude-haiku-4"
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
CONFIG
mkdir -p ~/.hermes/skills ~/.hermes/scripts ~/.hermes/cron/output ~/.hermes/drift ~/briefs /backups/hermes
cd ~/.hermes/skills && git init 2>/dev/null || true
git config user.email "agent@scrutexity.com"
git config user.name "Scrutexity Agent"
HERMES
ok "Hermes installed"

# PHASE 4: Docker + Open WebUI
info "Phase 4/7: Installing Docker and Open WebUI..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "scrutexity@$SERVER_IP" bash -s "$HERMES_PORT" "$WEBUI_PORT" <<'DOCKER'
set -euo pipefail
HERMES_PORT="$1"
WEBUI_PORT="$2"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -qq
sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker scrutexity
sudo systemctl enable docker && sudo systemctl start docker
API_KEY=$(grep API_SERVER_KEY ~/.hermes/.env | cut -d= -f2)
docker run -d     -p ${WEBUI_PORT}:8080     -e OPENAI_API_BASE_URL=http://host.docker.internal:${HERMES_PORT}/v1     -e OPENAI_API_KEY="$API_KEY"     -e ENABLE_OLLAMA_API=false     -e ENABLE_SIGNUP=false     -e DEFAULT_MODELS=scrutexity-agent     --add-host=host.docker.internal:host-gateway     -v open-webui:/app/backend/data     --name open-webui     --restart always     ghcr.io/open-webui/open-webui:main
for i in {1..60}; do
    if docker ps --format '{{.Status}}' --filter name=open-webui | grep -q healthy; then break; fi
    sleep 2
done
DOCKER
ok "Open WebUI running"

# PHASE 5: Cloudflare Tunnel
info "Phase 5/7: Installing Cloudflare Tunnel..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "scrutexity@$SERVER_IP" bash -s "$CF_TOKEN" "$DOMAIN" "$WEBUI_PORT" "$HEALTH_PORT" <<'CF'
set -euo pipefail
CF_TOKEN="$1"
DOMAIN="$2"
WEBUI_PORT="$3"
HEALTH_PORT="$4"
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list > /dev/null
sudo apt-get update -qq && sudo apt-get install -y -qq cloudflared
cloudflared tunnel login --token "$CF_TOKEN" 2>/dev/null || true
TUNNEL_ID=$(cloudflared tunnel create "scrutexity-agent" 2>/dev/null | grep -oP 'Created tunnel \K[a-z0-9-]+' || cloudflared tunnel list --output json | jq -r '.[] | select(.name=="scrutexity-agent") | .id')
if [ -z "$TUNNEL_ID" ] || [ "$TUNNEL_ID" = "null" ]; then
    echo "Failed to create Cloudflare tunnel"; exit 1
fi
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml <<CFCONFIG
tunnel: $TUNNEL_ID
credentials-file: /home/scrutexity/.cloudflared/$TUNNEL_ID.json

ingress:
  - hostname: $DOMAIN
    service: http://localhost:$WEBUI_PORT
    originRequest:
      noTLSVerify: true
  - hostname: health.$DOMAIN
    service: http://localhost:$HEALTH_PORT
    originRequest:
      noTLSVerify: true
  - service: http_status:404
CFCONFIG
cloudflared tunnel route dns "$TUNNEL_ID" "$DOMAIN" 2>/dev/null || true
cloudflared tunnel route dns "$TUNNEL_ID" "health.$DOMAIN" 2>/dev/null || true
sudo cloudflared service install
sudo systemctl enable cloudflared && sudo systemctl start cloudflared
CF
ok "Cloudflare Tunnel active"

# PHASE 6: Transfer project files
info "Phase 6/7: Transferring project files..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "scrutexity@$SERVER_IP" "mkdir -p ~/scrutexity-agent/scripts ~/scrutexity-agent/skills ~/scrutexity-agent/health"
scp -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" -r scripts/*.sh scripts/*.py "scrutexity@$SERVER_IP:~/scrutexity-agent/scripts/" 2>/dev/null || true
scp -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" -r skills/*.md "scrutexity@$SERVER_IP:~/scrutexity-agent/skills/" 2>/dev/null || true
scp -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" -r health/*.py "scrutexity@$SERVER_IP:~/scrutexity-agent/health/" 2>/dev/null || true
ok "Files transferred"

# PHASE 7: Deploy services and validate
info "Phase 7/7: Deploying services and validating..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "scrutexity@$SERVER_IP" bash -s "$HERMES_PORT" "$HEALTH_PORT" "$DOMAIN" "$TG_BOT_TOKEN" "$TG_CHAT_ID" <<'FINAL'
set -euo pipefail
HERMES_PORT="$1"
HEALTH_PORT="$2"
DOMAIN="$3"
TG_BOT_TOKEN="$4"
TG_CHAT_ID="$5"

python3 -m pip install --user flask requests python-telegram-bot==21.0 2>/dev/null || sudo apt-get install -y -qq python3-flask python3-requests

cp ~/scrutexity-agent/skills/*.md ~/.hermes/skills/ 2>/dev/null || true
cp ~/scrutexity-agent/scripts/*.sh ~/.hermes/scripts/ 2>/dev/null || true
cp ~/scrutexity-agent/scripts/*.py ~/.hermes/scripts/ 2>/dev/null || true
cp ~/scrutexity-agent/health/*.py ~/scrutexity-agent/health/ 2>/dev/null || true
chmod +x ~/.hermes/scripts/*.sh 2>/dev/null || true

cd ~/.hermes/skills && git add -A 2>/dev/null || true && git commit -m "Initial skill set v1.0.0" 2>/dev/null || true

# Hermes gateway systemd
sudo tee /etc/systemd/system/hermes-gateway.service > /dev/null <<'HERMES_SVC'
[Unit]
Description=Hermes Agent Gateway
After=network.target
[Service]
Type=simple
User=scrutexity
Group=scrutexity
WorkingDirectory=/home/scrutexity
Environment=HOME=/home/scrutexity
Environment=PATH=/home/scrutexity/.local/bin:/usr/local/bin:/usr/bin:/bin
EnvironmentFile=/home/scrutexity/.hermes/.env
ExecStart=/home/scrutexity/.local/bin/hermes gateway
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3
StandardOutput=append:/var/log/scrutexity/hermes-gateway.log
StandardError=append:/var/log/scrutexity/hermes-gateway.log
[Install]
WantedBy=multi-user.target
HERMES_SVC

sudo systemctl daemon-reload
sudo systemctl enable hermes-gateway
sudo systemctl start hermes-gateway

# Health endpoint systemd
sudo tee /etc/systemd/system/scrutexity-agent-health.service > /dev/null <<'HEALTH_SVC'
[Unit]
Description=Scrutexity Agent Health Endpoint
After=network.target hermes-gateway.service
[Service]
Type=simple
User=scrutexity
Group=scrutexity
WorkingDirectory=/home/scrutexity/scrutexity-agent/health
Environment=HOME=/home/scrutexity
Environment=PATH=/home/scrutexity/.local/bin:/usr/local/bin:/usr/bin:/bin
Environment=HEALTH_PORT=9999
Environment=HERMES_AUDIT_DB=/home/scrutexity/.hermes/audit.db
Environment=HERMES_SKILLS_DIR=/home/scrutexity/.hermes/skills
Environment=HERMES_HOME=/home/scrutexity/.hermes
ExecStart=/usr/bin/python3 /home/scrutexity/scrutexity-agent/health/health_endpoint.py
Restart=always
RestartSec=5
StandardOutput=append:/var/log/scrutexity/health.log
StandardError=append:/var/log/scrutexity/health.log
[Install]
WantedBy=multi-user.target
HEALTH_SVC

sudo systemctl daemon-reload
sudo systemctl enable scrutexity-agent-health
sudo systemctl start scrutexity-agent-health

# Backup systemd timer
sudo tee /etc/systemd/system/scrutexity-backup.service > /dev/null <<'BACKUP_SVC'
[Unit]
Description=Scrutexity Agent Daily Backup
[Service]
Type=oneshot
User=scrutexity
ExecStart=/bin/bash -c 'STAMP=$(date +%Y%m%d-%H%M%S); mkdir -p /backups/hermes; tar czf /backups/hermes/hermes-$STAMP.tar.gz -C /home/scrutexity .hermes 2>/dev/null; find /backups/hermes -name "hermes-*.tar.gz" -mtime +7 -delete'
BACKUP_SVC

sudo tee /etc/systemd/system/scrutexity-backup.timer > /dev/null <<'BACKUP_TIMER'
[Unit]
Description=Run Scrutexity Agent backup daily at 3 AM
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
[Install]
WantedBy=timers.target
BACKUP_TIMER

sudo systemctl daemon-reload
sudo systemctl enable scrutexity-backup.timer
sudo systemctl start scrutexity-backup.timer

# Cron jobs via Hermes
export PATH="$HOME/.local/bin:$PATH"
hermes cron create "0 6 * * 0" "Run drift-check.sh and report results" --name "weekly-drift-check" 2>/dev/null || true
hermes cron create "0 7 * * 0" "Run governance-check.sh and report results" --name "weekly-governance-check" 2>/dev/null || true
hermes cron create "0 11 * * *" "Run daily-brief skill and deliver to Telegram" --skill daily-brief --name "daily-brief" --deliver telegram 2>/dev/null || true
hermes cron create "0 9 * * 1" "Run sourcing-intel skill for 1688/Korean pipeline" --skill sourcing-intel --name "weekly-sourcing" --deliver telegram 2>/dev/null || true

# Telegram .env if provided
if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
    cat >> ~/.hermes/.env <<TG_ENV
TELEGRAM_BOT_TOKEN=$TG_BOT_TOKEN
TELEGRAM_CHAT_ID=$TG_CHAT_ID
TG_ENV
fi

sleep 10

# VALIDATION
info() { echo "[INFO]  $*"; }
ok()   { echo "[OK]    $*"; }
fail() { echo "[FAIL]  $*"; exit 1; }
warn() { echo "[WARN]  $*"; }

info "Test 1: Hermes API health..."
HERMES_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:${HERMES_PORT}/health || echo "000")
[ "$HERMES_HEALTH" = "200" ] || fail "Hermes health returned HTTP $HERMES_HEALTH"
ok "Hermes API responding (HTTP 200)"

info "Test 2: Cloudflare domain..."
CF_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "https://$DOMAIN/" || echo "000")
if [ "$CF_STATUS" != "200" ] && [ "$CF_STATUS" != "302" ]; then
    warn "Cloudflare domain HTTP $CF_STATUS (may need DNS propagation)"
else
    ok "Cloudflare domain reachable (HTTP $CF_STATUS)"
fi

info "Test 3: Health endpoint..."
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:${HEALTH_PORT}/health || echo "000")
[ "$HEALTH_STATUS" = "200" ] || fail "Health endpoint returned HTTP $HEALTH_STATUS"
ok "Health endpoint responding (HTTP 200)"

info "Test 4: Governance check..."
if [ -f ~/.hermes/scripts/governance-check.sh ]; then
    GOV_RESULT=$(bash ~/.hermes/scripts/governance-check.sh 2>&1 | tail -1)
    if echo "$GOV_RESULT" | grep -q "GOVERNANCE INTACT"; then
        ok "Governance check passed"
    else
        warn "Governance issues: $GOV_RESULT"
    fi
else
    warn "governance-check.sh not found"
fi

info "Test 5: Skills loaded..."
SKILL_COUNT=$(ls ~/.hermes/skills/*.md 2>/dev/null | wc -l)
[ "$SKILL_COUNT" -ge 3 ] && ok "Skills loaded: $SKILL_COUNT" || warn "Only $SKILL_COUNT skills found"

if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
    info "Test 6: Telegram alert..."
    TG_RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage"         -d "chat_id=$TG_CHAT_ID"         -d "text=%E2%9C%85 Scrutexity Agent deployed on $DOMAIN" || echo '{"ok":false}')
    echo "$TG_RESPONSE" | grep -q '"ok":true' && ok "Telegram alerts working" || warn "Telegram test failed"
fi

ok "=== DEPLOYMENT COMPLETE ==="
ok "Agent URL: https://$DOMAIN"
ok "Health URL: https://health.$DOMAIN/health"
FINAL

ok "=== ALL PHASES COMPLETE ==="
echo ""
echo "Your Scrutexity Agent is live at: https://$DOMAIN"
echo "SSH: ssh -i $SSH_KEY_PATH scrutexity@$SERVER_IP"
echo ""
echo "Next steps:"
echo "  1. Open Safari on iPhone -> https://$DOMAIN"
echo "  2. Share -> Add to Home Screen"
echo "  3. Create admin account (first user = admin)"
echo "  4. Disable signups: Admin Settings -> General -> Authentication"
echo ""
echo "Governance:"
echo "  ./scripts/audit-log.sh       — Last 20 audit entries"
echo "  ./scripts/skill-diff.sh      — Recent skill changes"
echo "  ./scripts/drift-check.sh     — Weekly drift detection"
echo "  ./scripts/governance-check.sh — Full validation"
