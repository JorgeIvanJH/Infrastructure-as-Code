#!/usr/bin/env bash

set -euo pipefail

# Ubuntu 24.04 provides Python 3.12 through the python3 package.
# XFCE provides the desktop, and xrdp makes that desktop available through RDP.
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates \
  dbus-x11 \
  python3 \
  xfce4 \
  xfce4-terminal \
  xorg \
  xorgxrdp \
  xrdp

# Create a terraform user if it does not already exist.
if ! id terraform >/dev/null 2>&1; then
  sudo useradd --create-home --shell /bin/bash terraform
fi

# Allow the terraform user to run sudo commands without a password prompt.
echo "terraform ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/terraform >/dev/null
sudo chmod 0440 /etc/sudoers.d/terraform
sudo visudo --check --file=/etc/sudoers.d/terraform

# Create SSH folder and import the public key.
sudo install -d -o terraform -g terraform -m 0700 /home/terraform/.ssh
sudo install -o terraform -g terraform -m 0600 /tmp/tf-packer.pub /home/terraform/.ssh/authorized_keys
sudo rm -f /tmp/tf-packer.pub

# Create a separate end user for the graphical desktop. useradd leaves the
# account locked, so no reusable password is stored in the image. A password is
# set on the final VM after Terraform creates it.
if ! id speuser >/dev/null 2>&1; then
  sudo useradd --create-home --shell /bin/bash speuser
fi
printf '%s\n' '#!/bin/sh' 'exec startxfce4' | sudo tee /home/speuser/.xsession >/dev/null
sudo chown speuser:speuser /home/speuser/.xsession
sudo chmod 0755 /home/speuser/.xsession

# Allow xrdp to read its TLS key and start it automatically on every VM boot.
sudo usermod --append --groups ssl-cert xrdp
sudo systemctl enable xrdp.service

# Install the agent and its systemd service.
sudo install -d -o root -g root -m 0755 /opt/spe-agent
sudo install -o root -g root -m 0644 \
  /tmp/spe-monitoring-agent.py \
  /opt/spe-agent/spe-monitoring-agent.py
sudo install -o root -g root -m 0644 \
  /tmp/spe-monitoring-agent.service \
  /etc/systemd/system/spe-monitoring-agent.service
# The agent's document can be longer than the 48 KiB journald allows per stream
# line, which would leave two halves in the journal. Raise the limit.
sudo install -d -o root -g root -m 0755 /etc/systemd/journald.conf.d
sudo install -o root -g root -m 0644 \
  /tmp/spe-monitoring-agent-journald.conf \
  /etc/systemd/journald.conf.d/spe-monitoring-agent.conf
# The identity step runs at boot as root, reads what Terraform attached to the
# instance, and writes /etc/spe/identity.env for the agent. Nothing about a
# specific SPE is written into the image.
sudo install -d -o root -g root -m 0755 /etc/spe
sudo install -o root -g root -m 0755 \
  /tmp/spe-identity \
  /usr/local/sbin/spe-identity
sudo install -o root -g root -m 0644 \
  /tmp/spe-identity.service \
  /etc/systemd/system/spe-identity.service
sudo rm -f \
  /tmp/spe-monitoring-agent.py \
  /tmp/spe-monitoring-agent.service \
  /tmp/spe-monitoring-agent-journald.conf \
  /tmp/spe-identity \
  /tmp/spe-identity.service

# Verify both units and both programs, then enable them. The identity step
# cannot run here: the build VM carries no SPE metadata, and that is the point.
sudo systemctl daemon-reload
sudo systemd-analyze verify \
  /etc/systemd/system/spe-identity.service \
  /etc/systemd/system/spe-monitoring-agent.service
bash -n /usr/local/sbin/spe-identity
sudo python3 -m py_compile /opt/spe-agent/spe-monitoring-agent.py
sudo rm -rf /opt/spe-agent/__pycache__
sudo systemctl enable spe-identity.service spe-monitoring-agent.service

# Prove the journal keeps a long line whole: restart journald with the drop-in,
# send a 200,000-byte line through the same stream path the agent uses, and
# read it back at full length.
systemd-analyze cat-config systemd/journald.conf | grep -qx 'LineMax=16M'
sudo systemctl restart systemd-journald.service
head -c 200000 /dev/zero | tr '\0' 'a' | systemd-cat -t spe-linemax-check
for attempt in {1..10}; do
  if sudo journalctl -t spe-linemax-check -o cat --no-pager | awk '{ print length($0) }' | grep -qx 200000; then
    break
  fi
  sleep 1
done
sudo journalctl -t spe-linemax-check -o cat --no-pager | awk '{ print length($0) }' | grep -qx 200000

# Verify the main packages and both services before Packer saves the image.
python3 --version
dpkg-query --show xfce4 xrdp
sudo systemctl is-enabled spe-identity.service
sudo systemctl is-enabled spe-monitoring-agent.service
sudo systemctl is-enabled xrdp.service
