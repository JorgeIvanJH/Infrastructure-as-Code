#!/usr/bin/env bash

set -euo pipefail

# auditd collects operating-system events. Laurel turns them into JSON Lines.
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
  laurel \
  libpam-modules \
  logrotate \
  zeek-lts-core

# Laurel's package provides the dedicated _laurel account. Both local audit
# writers use it; researchers can inspect with sudo but cannot modify the logs.
sudo install -d -o _laurel -g _laurel -m 0750 /var/log/spe-audit

# Configure Linux Audit, terminal input auditing, and Laurel's JSON output.
sudo install -o root -g root -m 0640 \
  /tmp/spe-audit.rules \
  /etc/audit/rules.d/50-spe.rules
# Keep auditd's original-format safety copy bounded as well as the two JSONL
# outputs used by this lesson.
sudo sed -i -E 's/^[[:space:]]*max_log_file[[:space:]]*=.*/max_log_file = 10/' /etc/audit/auditd.conf
sudo sed -i -E 's/^[[:space:]]*num_logs[[:space:]]*=.*/num_logs = 5/' /etc/audit/auditd.conf
sudo sed -i -E 's/^[[:space:]]*max_log_file_action[[:space:]]*=.*/max_log_file_action = ROTATE/' /etc/audit/auditd.conf
sudo install -o root -g root -m 0644 \
  /tmp/spe-pam-tty-audit \
  /etc/pam.d/spe-tty-audit
if ! grep -Fxq '@include spe-tty-audit' /etc/pam.d/common-session; then
  echo '@include spe-tty-audit' | sudo tee -a /etc/pam.d/common-session >/dev/null
fi
sudo install -d -o root -g root -m 0755 /etc/laurel
sudo install -o root -g root -m 0640 \
  /tmp/spe-laurel.toml \
  /etc/laurel/config.toml

# Configure the small Zeek service and a stable JSONL path. Zeek calls its
# physical file network.log; the symlink gives students the clearer name used
# throughout this lesson.
sudo install -d -o root -g root -m 0755 /etc/zeek
sudo install -o root -g root -m 0644 \
  /tmp/spe-network-audit.zeek \
  /etc/zeek/spe-network-audit.zeek
sudo install -o root -g root -m 0755 \
  /tmp/spe-network-audit \
  /usr/local/sbin/spe-network-audit
sudo install -o root -g root -m 0644 \
  /tmp/spe-network-audit.service \
  /etc/systemd/system/spe-network-audit.service
sudo install -o root -g root -m 0644 \
  /tmp/spe-audit-logrotate \
  /etc/logrotate.d/spe-audit
sudo ln -sfn network.log /var/log/spe-audit/network.jsonl

sudo rm -f \
  /tmp/spe-audit.rules \
  /tmp/spe-pam-tty-audit \
  /tmp/spe-laurel.toml \
  /tmp/spe-network-audit.zeek \
  /tmp/spe-network-audit \
  /tmp/spe-network-audit.service \
  /tmp/spe-audit-logrotate

# Validate configuration before saving the image.
sudo /usr/sbin/laurel --config /etc/laurel/config.toml --dry-run
sudo augenrules --check
sudo augenrules --load
sudo auditctl -l | grep -F spe_cli >/dev/null
grep -Fxq '@include spe-tty-audit' /etc/pam.d/common-session
sudo /opt/zeek/bin/zeek -b /etc/zeek/spe-network-audit.zeek
sudo rm -f /var/log/spe-audit/network.log

sudo systemctl daemon-reload
sudo systemctl enable auditd.service spe-network-audit.service

# Reload auditd so its Laurel plug-in sees our configuration during this build.
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
pgrep -x laurel >/dev/null

# Create a short connection after Zeek starts so its JSON output can be checked.
curl --silent --show-error --output /dev/null --connect-timeout 5 https://example.com
sleep 2
# A graceful stop finalizes any connection that Zeek still considers open.
sudo systemctl stop spe-network-audit.service

# Confirm both current outputs are valid JSON Lines. Network activity from this
# build will reach Zeek; Linux Audit creates a configuration event above.
for attempt in {1..15}; do
  if [[ -s /var/log/spe-audit/os.jsonl ]] && \
     [[ -s /var/log/spe-audit/network.log ]]; then
    break
  fi
  sleep 1
done
if [[ ! -s /var/log/spe-audit/os.jsonl ]] || \
   [[ ! -s /var/log/spe-audit/network.log ]]; then
  sudo ls -la /var/log/spe-audit
  sudo journalctl --no-pager -u auditd.service -u spe-network-audit.service -n 50 || true
  exit 1
fi
sudo tail -n 1 /var/log/spe-audit/os.jsonl | jq --exit-status . >/dev/null
sudo tail -n 1 /var/log/spe-audit/network.log | jq --exit-status . >/dev/null
sudo logrotate --debug /etc/logrotate.d/spe-audit >/dev/null

# Leave collection running in the build VM and enabled in every SPE made from
# the image.
sudo systemctl start spe-network-audit.service
sudo systemctl is-active spe-network-audit.service

sudo systemctl is-enabled auditd.service
sudo systemctl is-enabled spe-network-audit.service
