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
sudo rm -f /tmp/spe-monitoring-agent.py /tmp/spe-monitoring-agent.service

# Activate the systemd service and verify that it is enabled.
sudo systemctl daemon-reload
sudo systemd-analyze verify /etc/systemd/system/spe-monitoring-agent.service
sudo systemctl enable spe-monitoring-agent.service

# Verify the main packages and both services before Packer saves the image.
python3 --version
dpkg-query --show xfce4 xrdp
sudo systemctl is-enabled spe-monitoring-agent.service
sudo systemctl is-enabled xrdp.service
