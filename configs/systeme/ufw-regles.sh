#!/bin/bash
# Règles UFW du Pi (LAN 192.168.40.0/24, Tailscale sur l'interface tailscale0)
# ⚠️ Les ports publiés par Docker contournent UFW : voir docs/durcissement.md, section 5.
# Aucun port n'est redirigé sur le routeur : l'accès à distance passe par Tailscale (docs/tailscale.md).
# L'ancienne règle 51820/udp (WireGuard) a été retirée le 4 novembre 2026.
set -e
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.40.0/24 to any port 22 proto tcp comment 'SSH LAN'
sudo ufw allow from 192.168.40.0/24 to any port 53 comment 'DNS Pi-hole'
sudo ufw allow from 192.168.40.0/24 to any port 80,443 proto tcp comment 'Reverse proxy'
sudo ufw allow in on tailscale0 comment 'Tailscale'
sudo ufw route allow in on tailscale0 out on wlan0 comment 'Tailscale exit node'

# Anciennes règles SSH via WireGuard, à garder seulement si wg-easy est relancé :
# sudo ufw allow from 10.8.0.0/24   to any port 22 proto tcp comment 'SSH VPN'
# sudo ufw allow from 10.42.42.0/24 to any port 22 proto tcp comment 'SSH via wg-easy'

sudo ufw enable
sudo ufw status numbered
