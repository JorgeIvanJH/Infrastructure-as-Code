#!/usr/bin/env bash

set -euo pipefail

# Packer's temporary communicator keys are useful only while the image is
# being built. The runtime terraform account keeps the student's public key.
sudo rm -f \
  /home/ubuntu/.ssh/authorized_keys \
  /home/packer/.ssh/authorized_keys

# These caches are not needed in the reusable image and make snapshots larger.
sudo apt-get clean
sudo rm -rf \
  /root/.cache/pip \
  /home/ubuntu/.cache/pip \
  /home/packer/.cache/pip \
  /var/lib/apt/lists/*
