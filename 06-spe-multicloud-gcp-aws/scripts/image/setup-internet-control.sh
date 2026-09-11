#!/usr/bin/env bash

set -euo pipefail

# nftables is the Linux firewall used for this small outbound-control feature.
# chrony keeps the clock; accurate time keeps the audit timestamps trustworthy.
# nss-myhostname answers the VM's own hostname without DNS, see below.
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  chrony \
  libnss-myhostname \
  nftables

# The VM's own hostname must resolve without DNS. GCP sets it to a name only
# the metadata resolver knows, so with the internet off every sudo waited for a
# lookup that sealed mode drops. The package appends myhostname after dns;
# it has to come before dns so no query is ever made for the VM's own name.
sudo sed -i -E '/^hosts:/ { s/ myhostname//; s/ dns/ myhostname dns/ }' /etc/nsswitch.conf
grep -Eq '^hosts:[[:space:]]+files myhostname dns' /etc/nsswitch.conf

# GCP only: the guest environment ships its own logs to Cloud Logging and, with
# the internet off, its shutdown job waits ten minutes for that before the VM
# can reboot. The SPE keeps its logs on the VM. AWS has no such agent, so the
# file is not written there.
if command -v google_guest_agent >/dev/null; then
  printf '[Core]\ncloud_logging_enabled = false\n' \
    | sudo tee /etc/default/instance_configs.cfg >/dev/null
fi

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
  /tmp/spe-metadata.nft \
  /etc/spe-internet/metadata.nft
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
  /tmp/spe-metadata.nft \
  /tmp/spe-internet-restore.service

# Validate the firewall rules and the boot service before exercising the modes
# below. The metadata rules name two accounts; nft resolves them at check
# time, so a missing account fails the build here.
id root terraform >/dev/null
sudo nft --check --file /etc/spe-internet/disabled.nft
sudo nft --check --file /etc/spe-internet/metadata.nft
sudo systemctl daemon-reload
sudo systemd-analyze verify /etc/systemd/system/spe-internet-restore.service
sudo systemctl enable spe-internet-restore.service

# Exercise both modes while Packer is still connected through SSH. A new HTTPS request must fail in off mode and succeed again in on mode. Leave the reusable image online so a new SPE can finish its normal first boot.
sudo /usr/local/sbin/spe-internet off
if curl --silent --head --connect-timeout 5 https://example.com >/dev/null 2>&1; then
  echo "Internet-off validation failed: the new HTTPS request succeeded." >&2
  exit 1
fi
# The VM's own name must still resolve while sealed, with no DNS to ask.
getent hosts "$(hostname)" >/dev/null
echo "Internet-off validation passed."

sudo /usr/local/sbin/spe-internet on
curl --fail --silent --show-error --head --connect-timeout 10 \
  https://example.com >/dev/null
echo "Internet-on validation passed."

# The metadata policy holds while the internet is on. Any HTTP answer means the
# API was reachable; a refused connection means the policy applied. Name
# resolution must still work, because on GCP the same address is the resolver.
getent hosts example.com >/dev/null
if ! sudo curl --silent --output /dev/null --max-time 5 http://169.254.169.254/; then
  echo "Metadata validation failed: root cannot reach the metadata service." >&2
  exit 1
fi
if ! sudo -u terraform curl --silent --output /dev/null --max-time 5 http://169.254.169.254/; then
  echo "Metadata validation failed: terraform cannot reach the metadata service." >&2
  exit 1
fi
if sudo -u speuser curl --silent --output /dev/null --max-time 5 http://169.254.169.254/; then
  echo "Metadata validation failed: speuser reached the metadata service." >&2
  exit 1
fi
echo "Metadata access validation passed."

sudo systemctl start spe-internet-restore.service
sudo systemctl is-active spe-internet-restore.service
sudo /usr/local/sbin/spe-internet status
