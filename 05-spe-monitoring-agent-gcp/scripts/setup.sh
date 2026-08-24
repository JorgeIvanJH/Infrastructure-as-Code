#!/usr/bin/env bash

set -euo pipefail

# Ubuntu 24.04 provides Python 3.12 through the python3 package.
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates python3

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

# Verify that Python 3 is installed and the systemd service is enabled.
python3 --version
sudo systemctl is-enabled spe-monitoring-agent.service
