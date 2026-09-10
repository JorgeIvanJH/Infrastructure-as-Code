#!/usr/bin/env bash

set -euo pipefail

# auditd records operating-system events in its own raw log.
# Zeek records local connection summaries, including address, port, and bytes.
sudo install -d -o root -g root -m 0755 /etc/apt/keyrings
curl -fsSL \
  https://download.opensuse.org/repositories/security:/zeek/xUbuntu_24.04/Release.key \
  | sudo gpg --dearmor --yes -o /etc/apt/keyrings/zeek.gpg
echo "deb [signed-by=/etc/apt/keyrings/zeek.gpg] https://download.opensuse.org/repositories/security:/zeek/xUbuntu_24.04/ /" \
  | sudo tee /etc/apt/sources.list.d/zeek.list >/dev/null

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  auditd \
  jq \
  libpam-modules \
  logrotate \
  zeek-lts-core

# A dedicated no-login account runs Zeek and owns its output directory.
# Researchers can inspect with sudo but cannot modify the logs.
if ! id spe-netaudit >/dev/null 2>&1; then
  sudo useradd --system --user-group --no-create-home \
    --shell /usr/sbin/nologin spe-netaudit
fi
sudo install -d -o spe-netaudit -g spe-netaudit -m 0750 /var/log/spe-audit

# Configure Linux Audit and terminal input auditing. auditd keeps its own log
# at /var/log/audit/audit.log; the shipped auditd.conf bounds it to five files
# of 10 MB and otherwise matches the distribution default.
sudo install -o root -g root -m 0640 \
  /tmp/50-spe.rules \
  /etc/audit/rules.d/50-spe.rules
sudo install -o root -g root -m 0640 \
  /tmp/auditd.conf \
  /etc/audit/auditd.conf
sudo install -o root -g root -m 0644 \
  /tmp/spe-tty-audit \
  /etc/pam.d/spe-tty-audit
if ! grep -Fxq '@include spe-tty-audit' /etc/pam.d/common-session; then
  echo '@include spe-tty-audit' | sudo tee -a /etc/pam.d/common-session >/dev/null
fi

# Configure the small Zeek service and a stable JSONL path. Zeek calls its
# physical file network.log; the symlink gives students the clearer name used
# throughout this lesson.
sudo install -d -o root -g root -m 0755 /opt/zeek/share/zeek/site
sudo install -o root -g root -m 0644 \
  /tmp/spe-network-audit.zeek \
  /opt/zeek/share/zeek/site/spe-network-audit.zeek
sudo install -o root -g root -m 0755 \
  /tmp/spe-network-audit \
  /usr/local/sbin/spe-network-audit
sudo install -o root -g root -m 0644 \
  /tmp/spe-network-audit.service \
  /etc/systemd/system/spe-network-audit.service
sudo install -o root -g root -m 0644 \
  /tmp/spe-audit \
  /etc/logrotate.d/spe-audit
sudo ln -sfn network.log /var/log/spe-audit/network.jsonl

sudo rm -f \
  /tmp/50-spe.rules \
  /tmp/auditd.conf \
  /tmp/spe-tty-audit \
  /tmp/spe-network-audit.zeek \
  /tmp/spe-network-audit \
  /tmp/spe-network-audit.service \
  /tmp/spe-audit

# Validate configuration before saving the image.
sudo augenrules --check
sudo augenrules --load
sudo auditctl -l | grep -F spe_cli >/dev/null
sudo grep -Eq '^max_log_file = 10$' /etc/audit/auditd.conf
sudo grep -Eq '^num_logs = 5$' /etc/audit/auditd.conf
sudo grep -Eq '^max_log_file_action = ROTATE$' /etc/audit/auditd.conf
grep -Fxq '@include spe-tty-audit' /etc/pam.d/common-session
sudo systemd-analyze verify /etc/systemd/system/spe-network-audit.service
sudo /opt/zeek/bin/zeek -b /opt/zeek/share/zeek/site/spe-network-audit.zeek
sudo rm -f /var/log/spe-audit/network.log

sudo systemctl daemon-reload
sudo systemctl enable auditd.service spe-network-audit.service

# Restart auditd so the new log settings apply during this build. Its unit
# refuses manual stops, so the init script is used instead of systemctl.
sudo service auditd restart
sudo systemctl start spe-network-audit.service
sudo systemctl is-active auditd.service
for attempt in {1..10}; do
  if sudo systemctl is-active --quiet spe-network-audit.service; then
    break
  fi
  sleep 1
done
if ! sudo systemctl is-active --quiet spe-network-audit.service; then
  sudo systemctl --no-pager --full status spe-network-audit.service || true
  sudo journalctl --no-pager -u spe-network-audit.service -n 30 || true
  exit 1
fi

# Create a short connection after Zeek starts so its JSON output can be checked.
# The curl program itself is started by the build user, so it also proves that
# the execve rule fires.
curl --silent --show-error --output /dev/null --connect-timeout 5 https://example.com
sleep 2
# A graceful stop finalizes any connection that Zeek still considers open.
sudo systemctl stop spe-network-audit.service

# Confirm both outputs exist: a tagged execve record in auditd's raw log and
# valid JSON Lines from Zeek.
for attempt in {1..15}; do
  if sudo grep -q 'key="spe_cli"' /var/log/audit/audit.log && \
     [[ -s /var/log/spe-audit/network.log ]]; then
    break
  fi
  sleep 1
done
if ! sudo grep -q 'key="spe_cli"' /var/log/audit/audit.log || \
   [[ ! -s /var/log/spe-audit/network.log ]]; then
  sudo ls -la /var/log/audit /var/log/spe-audit
  sudo tail -n 20 /var/log/audit/audit.log || true
  sudo journalctl --no-pager -u auditd.service -u spe-network-audit.service -n 50 || true
  exit 1
fi
sudo ausearch -k spe_cli --start recent >/dev/null
sudo tail -n 1 /var/log/spe-audit/network.log | jq --exit-status . >/dev/null
sudo logrotate --debug /etc/logrotate.d/spe-audit >/dev/null

# Leave collection running in the build VM and enabled in every SPE made from
# the image.
sudo systemctl start spe-network-audit.service
sudo systemctl is-active spe-network-audit.service

sudo systemctl is-enabled auditd.service
sudo systemctl is-enabled spe-network-audit.service
