#!/usr/bin/env bash

set -euo pipefail

# nftables is the Linux firewall used for this small outbound-control feature.
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  nftables

sudo install -d -o root -g root -m 0755 \
  /etc/spe-internet \
  /var/lib/spe-internet

sudo install -o root -g root -m 0755 \
  /tmp/spe-internet \
  /usr/local/sbin/spe-internet
sudo install -o root -g root -m 0644 \
  /tmp/spe-internet-disabled.nft \
  /etc/spe-internet/disabled.nft
sudo install -o root -g root -m 0644 \
  /tmp/spe-internet-allowlist.nft \
  /etc/spe-internet/allowlist.nft
sudo install -o root -g root -m 0644 \
  /tmp/spe-internet-restore.service \
  /etc/systemd/system/spe-internet-restore.service

# A new SPE begins online. Administrator changes are saved by spe-internet.
printf '%s\n' 'on' | sudo tee /var/lib/spe-internet/mode >/dev/null
sudo chmod 0644 /var/lib/spe-internet/mode

sudo rm -f \
  /tmp/spe-internet \
  /tmp/spe-internet-disabled.nft \
  /tmp/spe-internet-allowlist.nft \
  /tmp/spe-internet-restore.service

# Validate both the firewall rules and the boot service before exercising the two modes below.
sudo nft --check --file /etc/spe-internet/disabled.nft
sudo systemctl daemon-reload
sudo systemd-analyze verify /etc/systemd/system/spe-internet-restore.service
sudo systemctl enable spe-internet-restore.service

# Exercise both modes while Packer is still connected through SSH. A new HTTPS request must fail in off mode and succeed again in on mode. Leave the reusable image online so a new SPE can finish its normal first boot.
sudo /usr/local/sbin/spe-internet off
if curl --silent --head --connect-timeout 5 https://example.com >/dev/null 2>&1; then
  echo "Internet-off validation failed: the new HTTPS request succeeded." >&2
  exit 1
fi
echo "Internet-off validation passed."

sudo /usr/local/sbin/spe-internet on
curl --fail --silent --show-error --head --connect-timeout 10 \
  https://example.com >/dev/null
echo "Internet-on validation passed."

sudo systemctl start spe-internet-restore.service
sudo systemctl is-active spe-internet-restore.service
sudo /usr/local/sbin/spe-internet status
