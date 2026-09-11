#!/usr/bin/env bash

set -euo pipefail

# auditd records operating-system events in its own raw log.
# Zeek, run by ZeekControl, records local connection summaries: address, port,
# and bytes.
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
  zeek-lts-core \
  zeekctl-lts

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

# Configure ZeekControl: one standalone node, the site policy, and the archive
# directory. ZeekControl runs unprivileged as spe-netaudit, so its run-time
# data (spool) and its archive (LogDir) belong to that account. The live logs
# are reached through the "current" symlink ZeekControl keeps in LogDir; the
# network.jsonl symlink gives students the clearer name used in this lesson.
sudo install -d -o root -g root -m 0755 /opt/zeek/etc /opt/zeek/share/zeek/site
sudo install -o root -g root -m 0644 \
  /tmp/node.cfg \
  /opt/zeek/etc/node.cfg
sudo install -o root -g root -m 0644 \
  /tmp/networks.cfg \
  /opt/zeek/etc/networks.cfg
sudo install -o root -g root -m 0644 \
  /tmp/zeekctl.cfg \
  /opt/zeek/etc/zeekctl.cfg
sudo install -o root -g root -m 0644 \
  /tmp/local.zeek \
  /opt/zeek/share/zeek/site/local.zeek
sudo install -o root -g root -m 0755 \
  /tmp/zeek-set-interface \
  /usr/local/sbin/zeek-set-interface
sudo install -o root -g root -m 0644 \
  /tmp/zeek.service \
  /etc/systemd/system/zeek.service
sudo install -o root -g root -m 0644 \
  /tmp/zeek-cron.service \
  /etc/systemd/system/zeek-cron.service
sudo install -o root -g root -m 0644 \
  /tmp/zeek-cron.timer \
  /etc/systemd/system/zeek-cron.timer
sudo install -d -o spe-netaudit -g spe-netaudit -m 0750 /opt/zeek/spool
sudo chown -R spe-netaudit:spe-netaudit /opt/zeek/spool
sudo ln -sfn current/network.log /var/log/spe-audit/network.jsonl

sudo rm -f \
  /tmp/50-spe.rules \
  /tmp/auditd.conf \
  /tmp/spe-tty-audit \
  /tmp/node.cfg \
  /tmp/networks.cfg \
  /tmp/zeekctl.cfg \
  /tmp/local.zeek \
  /tmp/zeek-set-interface \
  /tmp/zeek.service \
  /tmp/zeek-cron.service \
  /tmp/zeek-cron.timer

# Validate configuration before saving the image.
sudo augenrules --check
sudo augenrules --load
sudo auditctl -l | grep -F spe_cli >/dev/null
sudo grep -Eq '^max_log_file = 10$' /etc/audit/auditd.conf
sudo grep -Eq '^num_logs = 5$' /etc/audit/auditd.conf
sudo grep -Eq '^max_log_file_action = ROTATE$' /etc/audit/auditd.conf
grep -Fxq '@include spe-tty-audit' /etc/pam.d/common-session
sudo systemd-analyze verify \
  /etc/systemd/system/zeek.service \
  /etc/systemd/system/zeek-cron.service \
  /etc/systemd/system/zeek-cron.timer
# The interface step must succeed on this build VM, and zeekctl check parses
# node.cfg, zeekctl.cfg, networks.cfg and local.zeek as the runtime account.
sudo /usr/local/sbin/zeek-set-interface
grep -Eq '^interface=[a-z0-9]+$' /opt/zeek/etc/node.cfg
sudo -u spe-netaudit /opt/zeek/bin/zeekctl check

sudo systemctl daemon-reload
sudo systemctl enable auditd.service zeek.service zeek-cron.timer

# Restart auditd so the new log settings apply during this build. Its unit
# refuses manual stops, so the init script is used instead of systemctl.
sudo service auditd restart
sudo systemctl is-active auditd.service

# Deploy the Zeek node through its unit, exactly as it will start on every
# SPE, and wait until ZeekControl reports it running.
sudo systemctl start zeek.service
for attempt in {1..20}; do
  if sudo -u spe-netaudit /opt/zeek/bin/zeekctl status | grep -q running; then
    break
  fi
  sleep 1
done
if ! sudo -u spe-netaudit /opt/zeek/bin/zeekctl status | grep -q running; then
  sudo systemctl --no-pager --full status zeek.service || true
  sudo journalctl --no-pager -u zeek.service -n 30 || true
  sudo -u spe-netaudit /opt/zeek/bin/zeekctl diag || true
  exit 1
fi

# Create a short connection so Zeek's JSON output can be checked. zeekctl
# reports the node running before Zeek has finished loading its scripts and
# started capturing, so repeat the connection until it shows up in the live
# log. The curl program itself is started by the build user, so it also proves
# that the execve rule fires.
for attempt in {1..15}; do
  curl --silent --show-error --output /dev/null --connect-timeout 5 https://example.com
  sleep 2
  if sudo test -s /var/log/spe-audit/current/network.log; then
    break
  fi
done
if ! sudo test -s /var/log/spe-audit/current/network.log; then
  echo "Zeek did not log the test connection." >&2
  sudo ls -laR /var/log/spe-audit /opt/zeek/spool/zeek || true
  sudo -u spe-netaudit /opt/zeek/bin/zeekctl status || true
  sudo -u spe-netaudit /opt/zeek/bin/zeekctl diag || true
  sudo journalctl --no-pager -u zeek.service -n 30 || true
  exit 1
fi
# Stopping the node flushes its logs and archives them into LogDir/<date>/,
# which exercises the same rotation path a running SPE uses every hour.
sudo systemctl stop zeek.service

# Confirm both outputs exist: a tagged execve record in auditd's raw log and
# a compressed, archived Zeek log holding valid JSON Lines.
for attempt in {1..15}; do
  if sudo grep -q 'key="spe_cli"' /var/log/audit/audit.log && \
     sudo find /var/log/spe-audit -name 'network.*.log.gz' | grep -q .; then
    break
  fi
  sleep 1
done
if ! sudo grep -q 'key="spe_cli"' /var/log/audit/audit.log || \
   ! sudo find /var/log/spe-audit -name 'network.*.log.gz' | grep -q .; then
  sudo ls -laR /var/log/audit /var/log/spe-audit
  sudo tail -n 20 /var/log/audit/audit.log || true
  sudo journalctl --no-pager -u auditd.service -u zeek.service -n 50 || true
  exit 1
fi
# ausearch is the reading tool; it must find the tagged events too. When its
# stdin is a pipe, as it is under Packer, ausearch reads events from there
# instead of the log; --input-logs forces the log files from auditd.conf.
sudo ausearch --input-logs -k spe_cli >/dev/null
sudo find /var/log/spe-audit -name 'network.*.log.gz' -exec zcat {} + \
  | tail -n 1 | jq --exit-status . >/dev/null

# The build VM's own traffic is not evidence for any SPE. Remove the archived
# build logs; the node is left stopped and starts through its unit on boot.
sudo find /var/log/spe-audit -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +

sudo systemctl is-enabled auditd.service
sudo systemctl is-enabled zeek.service
sudo systemctl is-enabled zeek-cron.timer
