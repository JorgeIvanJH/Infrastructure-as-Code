#!/usr/bin/env bash

set -euo pipefail

# Ubuntu 24.04 provides Python 3.12 through the python3 package.
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates python3

# Keep the same learning user and SSH design used in exercise 4.
if ! id terraform >/dev/null 2>&1; then
  sudo useradd --create-home --shell /bin/bash terraform
fi

echo "terraform ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/terraform >/dev/null
sudo chmod 0440 /etc/sudoers.d/terraform
sudo visudo --check --file=/etc/sudoers.d/terraform

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

sudo systemctl daemon-reload
sudo systemd-analyze verify /etc/systemd/system/spe-monitoring-agent.service
sudo systemctl enable spe-monitoring-agent.service

python3 --version
sudo systemctl is-enabled spe-monitoring-agent.service
