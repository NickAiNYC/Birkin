#!/usr/bin/env bash
# =============================================================================
# agent-lockdown.sh — Outbound network lockdown (kill switch #2)
# Version: 1.0.0 | Birkin Safety Layer
#
# Restricts outbound network access to only essential services:
#   - OpenRouter API (openrouter.ai)
#   - Cloudflare Tunnel (register.argotunnel.com, *.argotunnel.com)
#   - GitHub API (api.github.com)
#   - Telegram Bot API (api.telegram.org)
#   - DNS (port 53)
#
# All other outbound traffic is blocked (no random web_research, no
# arbitrary HTTP calls from the agent).
#
# Usage: ./agent-lockdown.sh [--unlock]
# Exit:  0 = success | 1 = failed
#
# CAUTION: This will break web_research toolset and any tool that makes
#          arbitrary HTTP calls. Use only in emergency or incident response.
# =============================================================================
set -euo pipefail

UNLOCK=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --unlock) UNLOCK=true ;;
        --help)
            echo "Usage: ./agent-lockdown.sh [--unlock]"
            echo "Restricts outbound network to essential services only."
            echo "--unlock: restore normal outbound access"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

echo "=== Birkin — $([ "$UNLOCK" = true ] && echo "UNLOCK" || echo "LOCKDOWN") ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

if [[ "$UNLOCK" == true ]]; then
    echo "  Restoring normal outbound access..."

    # Remove lockdown rules (added with --comment lockdown)
    sudo ufw delete deny out on eth0 2>/dev/null || true

    # Restore default allow-outgoing
    sudo ufw default allow outgoing 2>/dev/null || true

    echo "  ✅ Outbound access restored"
    echo ""
    echo "  ⚠️  WARNING: Agent can now make arbitrary outbound connections"
    echo "     Review agent activity log before resuming autonomous operations:"
    echo "     ./scripts/audit-log.sh --today"
    exit 0
fi

# ── Lockdown ──────────────────────────────────────────────────────────────────
echo "  ⚠️  APPLYING NETWORK LOCKDOWN"
echo "  Allowing outbound to: OpenRouter, Cloudflare, GitHub, Telegram, DNS only"
echo ""

# Step 1: Block all outbound by default
sudo ufw default deny outgoing

# Step 2: Allow essential services (domain-resolved to IPs — VERIFY these are current)
# DNS first (needed for hostname resolution)
sudo ufw allow out 53  comment "DNS lookups"

# Allow SSH out (so this session stays alive)
sudo ufw allow out 22 comment "SSH"

# HTTPS to essential services
# OpenRouter (Cloudflare-fronted, uses standard Cloudflare IPs)
sudo ufw allow out 443 to 104.21.0.0/16  comment "lockdown: OpenRouter/Cloudflare"
sudo ufw allow out 443 to 172.67.0.0/16  comment "lockdown: OpenRouter/Cloudflare"
sudo ufw allow out 443 to 188.114.96.0/20 comment "lockdown: Cloudflare Tunnel"

# Telegram Bot API
sudo ufw allow out 443 to 149.154.160.0/20 comment "lockdown: Telegram"
sudo ufw allow out 443 to 91.108.4.0/22    comment "lockdown: Telegram"

# GitHub API (for skill git operations)
sudo ufw allow out 443 to 140.82.112.0/20 comment "lockdown: GitHub"

sudo ufw --force enable 2>/dev/null || true
sudo ufw reload 2>/dev/null || true

echo ""
echo "  ✅ LOCKDOWN APPLIED"
echo "  Outbound access restricted to:"
echo "    - Cloudflare CDN (OpenRouter, Cloudflare Tunnel)"
echo "    - Telegram Bot API"
echo "    - GitHub API"
echo "    - DNS (port 53)"
echo ""
echo "  Web research and arbitrary HTTP calls are BLOCKED."
echo "  Agent will operate in degraded mode until unlocked."
echo ""
echo "  To unlock: ./scripts/agent-lockdown.sh --unlock"
echo "  To verify: sudo ufw status verbose"
