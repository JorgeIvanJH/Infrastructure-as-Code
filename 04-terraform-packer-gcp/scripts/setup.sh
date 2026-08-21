#!/usr/bin/env bash

set -euo pipefail

# Install the tools needed by the demo application.
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates git golang-go

# Create the user only when it does not already exist.
if ! id terraform >/dev/null 2>&1; then
  sudo useradd --create-home --shell /bin/bash terraform
fi

# This broad sudo rule is only for the learning VM.
echo "terraform ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/terraform >/dev/null
sudo chmod 0440 /etc/sudoers.d/terraform
sudo visudo --check --file=/etc/sudoers.d/terraform

# Install the public key that Packer uploaded to the temporary VM.
sudo install -d -o terraform -g terraform -m 0700 /home/terraform/.ssh
sudo install -o terraform -g terraform -m 0600 /tmp/tf-packer.pub /home/terraform/.ssh/authorized_keys
sudo rm -f /tmp/tf-packer.pub

# Put the demo source code in the terraform user's home folder.
if [ ! -d /home/terraform/learn-go-webapp-demo ]; then
  sudo -H -u terraform git clone \
    https://github.com/hashicorp/learn-go-webapp-demo.git \
    /home/terraform/learn-go-webapp-demo
fi

go version
