#!/bin/bash
# Règles UFW du Pi (LAN 192.168.40.0/24, VPN 10.8.0.0/24, réseau wg-easy 10.42.42.0/24)
# ⚠️ Les ports publiés par Docker contournent UFW : voir docs/durcissement.md, section 5.
set -e
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.40.0/24 to any port 22 proto tcp comment 'SSH LAN'
sudo ufw allow from 10.8.0.0/24     to any port 22 proto tcp comment 'SSH VPN'
sudo ufw allow from 10.42.42.0/24   to any port 22 proto tcp comment 'SSH via wg-easy'
sudo ufw allow 51820/udp comment 'WireGuard'
sudo ufw allow from 192.168.40.0/24 to any port 53 comment 'DNS Pi-hole'
sudo ufw allow from 192.168.40.0/24 to any port 80,443 proto tcp comment 'Reverse proxy'
sudo ufw enable
sudo ufw status numbered
