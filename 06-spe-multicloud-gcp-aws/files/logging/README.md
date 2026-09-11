# What is in this folder

Everything that produces a record on the SPE lives here, one subfolder per
producer. Each subfolder has its own README with the details: the files it
holds, where they land on the VM, what the raw output looks like, and how to
read it.

| subfolder | deals with | writes to, on the VM |
|---|---|---|
| [auditd/](auditd/) | the operating system: who logged in, what they typed in a terminal, which programs they started | `/var/log/audit/audit.log` |
| [zeek/](zeek/) | the network: one line per connection, with addresses, ports, bytes, and how it ended | `/var/log/spe-audit/network.jsonl`, archived hourly under `/var/log/spe-audit/YYYY-MM-DD/` |
| [heartbeat/](heartbeat/) | the SPE saying it is alive: its name, the time, whether the internet is reachable, plus everything the other two recorded since the last time, once per interval | the systemd journal, for now |

The first two are the audit evidence. The heartbeat is the health signal, the
only stream that already carries the SPE's name in every line, and since this
iteration the one that gathers the other two into one document, described
below.

For the plain-words picture of how these fit together, where the SPE's name
comes from, and who may read what, see
[HOW-THE-SPE-WORKS.md](../../HOW-THE-SPE-WORKS.md).

# The exported payload

The three streams are no longer three destinations. Every interval, the
heartbeat agent builds one JSON document that carries its own health fields
plus everything auditd and Zeek recorded since the previous document. The files
on the VM stay as they are and act as the local buffer: the agent reads them
incrementally and moves its bookmarks forward only once the document is out.
How it reads them is in [heartbeat/README.md](heartbeat/README.md).

Two steps, one done and one pending:

1. **build the document** (done): the agent prints it to stdout every interval,
   and systemd stores it in the journal. That is where to look today.
2. **send it** (next): one HTTPS POST per document to a collector outside the
   SPE, bookmarks moving only on a 2xx, the journal keeping just operational
   lines. The rules at the end of this file are written for that step.

One document per interval:

~~~json
{
  "spe_id": "spe-demo-006-gcp",
  "boot_id": "7f0b2c6e-3d9a-4a1e-9b2f-0c1d2e3f4a5b",
  "sequence": 42,
  "timestamp": "2026-09-10T14:30:00Z",
  "internet": "reachable",
  "os": [
    {"time": 1787762050.101, "serial": 940, "kind": "session", "ses": 3, "auid": "speuser", "uid": "root", "pid": 4210,
     "event": "USER_START", "acct": "speuser", "exe": "/usr/sbin/sshd", "terminal": "ssh", "addr": "203.0.113.10", "res": "success"},
    {"time": 1787762101.420, "serial": 966, "kind": "command", "ses": 3, "auid": "speuser", "uid": "speuser", "pid": 4321,
     "exe": "/usr/bin/python3.12", "args": ["python3", "--version"], "cwd": "/home/speuser/spe-data-lab", "success": true},
    {"time": 1787762110.330, "serial": 951, "kind": "tty", "ses": 3, "auid": "speuser", "uid": "speuser", "pid": 4321,
     "comm": "bash", "data": "cd ~/spe-data-lab\n"}
  ],
  "net": [
    {"time": 1787754601.25, "src_ip": "10.60.1.2", "src_port": 43210, "dst_ip": "93.184.216.34", "dst_port": 443,
     "proto": "tcp", "duration": 0.12, "bytes_out": 80, "bytes_in": 300, "state": "SF"}
  ]
}
~~~

`os` and `net` are often empty. An empty array means nothing happened in that
interval, and the document is still worth sending: its arrival is the
heartbeat.

## the envelope

| key | type | comes from | why it is there |
|---|---|---|---|
| `spe_id` | string | `SPE_ID` in `/etc/spe/identity.env` | the one key the collector partitions on. two SPEs are never confused |
| `boot_id` | string | `/proc/sys/kernel/random/boot_id` | changes at every reboot. a gap in `sequence` with a new `boot_id` is a restart, with the same `boot_id` it is lost data |
| `sequence` | integer | counter kept by the agent on disk, next to its cursors | one per document, never reused. the collector detects gaps and duplicates without trusting clocks |
| `timestamp` | string | the agent's clock, UTC, ISO 8601 with `Z` | when the document was built. the records inside carry their own times |
| `internet` | `reachable` or `blocked` | the TCP handshake probe already in the agent | measured on the wire, not read from what `spe-internet` says it set |
| `os` | array | `/var/log/audit/audit.log`, via auditd | one object per auditd *event*, not per line |
| `net` | array | `/var/log/spe-audit/current/network.log`, via Zeek | one object per connection, as Zeek closes them |

Left out on purpose: the fixed `message` string from today's heartbeat, since
the document's presence is the message; and cloud, instance id and region,
which are already in `identity.env` and one field away if a collector ever
needs them. `spe_id` is the identity.

## `os`: one object per auditd event

auditd writes several lines per event, all sharing the same
`msg=audit(time:serial)` stamp. The exporter groups them into one object,
decodes the hex, and keeps the `ENRICHED` names (`speuser`) instead of the
numbers (`1001`). Three kinds of event exist in the SPE, matching the three
triggers in [auditd/README.md](auditd/README.md), and `kind` says which one an
object is.

Fields present in every `os` object:

| key | from auditd | why |
|---|---|---|
| `time` | the `time` half of `msg=audit(time:serial)`, unix seconds | when it happened, stamped by the kernel. same unit as `net[].time` so the two arrays sort together |
| `serial` | the `serial` half | with `time` it is the event's identity, unique within a boot. lets the collector drop a duplicate |
| `kind` | derived: `command`, `session`, or `tty` | which of the three shapes below to expect |
| `ses` | `ses` | the login session. everything one person did in one sitting shares it, across `sudo` and across the three kinds |
| `auid` | `AUID` | the human who logged in. survives `sudo`, so a root shell still names the person |
| `uid` | `UID` | the account the process ran as. differs from `auid` after `sudo` |
| `pid` | `pid` | the process, to tie a `tty` line to the `command` that started the shell |

`kind: "command"`, from the `execve` rule (`key="spe_cli"`):

| key | from auditd | why |
|---|---|---|
| `exe` | `SYSCALL` line, `exe` | the binary that actually ran, resolved path |
| `args` | `EXECVE` line, `a0` … `an` in order | the command line as an array. `PROCTITLE` is the same thing hex-encoded and is dropped |
| `cwd` | `CWD` line | where it ran, which gives relative paths in `args` a meaning |
| `success` | `SYSCALL` line, `success=yes/no` as a boolean | a failed `execve` is still an attempt worth seeing |

`kind: "session"`, from the PAM events (`USER_LOGIN`, `USER_START`, `USER_END`,
`USER_AUTH`, `CRED_ACQ` and friends):

| key | from auditd | why |
|---|---|---|
| `event` | `type` | which step: `USER_START` opens a session, `USER_END` closes it, `USER_AUTH` with `res=failed` is a wrong password |
| `acct` | `acct` inside `msg='…'` | who the session is for. differs from `auid` when the event is about an account that has not logged in yet |
| `exe` | `exe` inside `msg='…'` | the program that opened it: `/usr/sbin/sshd`, `/usr/sbin/xrdp-sesman`, `/usr/bin/sudo`, `/usr/sbin/cron` |
| `terminal` | `terminal` | `ssh`, `xrdp`, `pts/0`, or `cron`. the human-friendly version of `exe` |
| `addr` | `addr` | the remote address for SSH and RDP, `?` for local. this is what ties a login to the laptop the firewall admitted |
| `res` | `res` | `success` or `failed` |

`kind: "tty"`, from the PAM `tty_audit` module:

| key | from auditd | why |
|---|---|---|
| `comm` | `comm` | the program that was reading the terminal, normally `bash` or `sudo` |
| `data` | `data`, hex decoded to text | what was typed, including shell built-ins that never reach `execve`. passwords are excluded at the source because `log_passwd` is off |

Dropped from `os`: `arch`, `syscall`, `key` (always `execve` and `spe_cli`),
`comm` on `command` events (redundant with `exe`), `ppid`, the `PATH` lines
(mode, owner, inode of the binary), `PROCTITLE`, `tty` device name, `major` and
`minor`, `hostname` (same value as `addr`), `op`, and every numeric twin of an
enriched name. The raw file on the VM keeps all of it for five rotations, so
this is a curated view for the collector, not the only copy.

## `net`: one object per connection

Zeek already writes one JSON object per connection with the 15 fields chosen in
[zeek/local.zeek](zeek/local.zeek). The exporter keeps ten of them and renames
them so the words match `os` and no key needs quoting in `jq`.

| key | Zeek field | why |
|---|---|---|
| `time` | `ts` | first packet, unix seconds. same unit as `os[].time` |
| `src_ip` | `id.orig_h` | who started it. for anything the SPE reached out to, the VM's private address |
| `src_port` | `id.orig_p` | ephemeral for outbound, `22` or `3389` for the admin's inbound sessions |
| `dst_ip` | `id.resp_h` | who answered. the field that says where data could have gone |
| `dst_port` | `id.resp_p` | what service: `443`, `53`, `22` |
| `proto` | `proto` | `tcp`, `udp`, or `icmp` |
| `duration` | `duration` | seconds from first to last useful packet |
| `bytes_out` | `orig_bytes` | payload bytes the originator sent. for outbound connections, what left the SPE |
| `bytes_in` | `resp_bytes` | payload bytes the responder sent back |
| `state` | `conn_state` | how it ended: `SF` normal, `S0` unanswered, `REJ` refused, see [zeek/README.md](zeek/README.md) |

Dropped from `net`: `uid` (Zeek's connection id, only useful to join the
protocol logs we disabled, and confusable with a Linux user id), and the four
wire-level counters `orig_pkts`, `resp_pkts`, `orig_ip_bytes`, `resp_ip_bytes`
(packets and header-inclusive bytes; the payload bytes already answer "how
much"). If the protocol logs ever come back, `uid` comes back with them.

The agent's own probe shows up in `net` while the internet is on: one `tcp`
connection to `1.1.1.1:443` per interval, zero bytes, `SF`. It stays in for
now because it is honest and easy to filter on the collector by `dst_ip`; the
`internet` field makes it redundant, so removing it at the source is an
option later.

## rules the exporter follows

- **Never loses a record for the collector being down.** Bookmarks move only
  after the document is out (today: printed; next: answered with a 2xx). The
  files are the buffer: about 50 MiB of auditd and seven days of Zeek archives.
  When the collector comes back, several intervals of records arrive in one
  document.
- **Rotation is handled, not hoped for.** auditd renames `audit.log` to
  `audit.log.1` at 10 MiB and ZeekControl moves `current/network.log` into
  `YYYY-MM-DD/` every hour. `ausearch --checkpoint` does the bookkeeping for
  auditd and groups the lines into events at the same time; for Zeek the agent
  remembers the inode and offset of the live file and finishes the old one from
  its archive when the inode changes.
- **Nothing is ever dropped.** Every record auditd or Zeek wrote is exported
  exactly once, however many pile up while the collector is unreachable. If a
  backlog ever needs splitting across several HTTP bodies, each part is a full
  document with its own `sequence`; that is a sending detail, decided when the
  sender is written, and it never discards a record.
- **It never sends over plain HTTP.** `tty.data` contains keystrokes. TLS is
  required, with a bearer token so the collector can reject noise.
- **It works while the SPE is sealed.** `spe_egress` drops every new outbound
  connection and DNS is blocked, so the collector is one fixed address and port,
  allowed in
  [spe-internet-allowlist.nft](../internet-control/spe-internet-allowlist.nft),
  the file reserved for exactly this. The URL and token travel like `spe-id`:
  attached by Terraform, read by `spe-identity`, written to `identity.env`.
- **It reads as `terraform`, no new account.** The agent already runs as the
  admin user, which cannot read either file today. `log_group = terraform` in
  `auditd.conf` makes auditd write its log as `0640 root:terraform`, and
  `terraform` joins the `spe-netaudit` group for `/var/log/spe-audit`. The
  account has passwordless sudo anyway, so this grants nothing it could not
  already reach.
- **It remembers where it stopped.** A state directory,
  `/var/lib/spe-monitoring-agent`, created by systemd for the unit, holds the
  last `sequence`, the auditd checkpoint, and the Zeek cursor (file and byte
  offset). That is what makes "since the previous document" survive a restart
  or a reboot without resending or skipping.

## what this buys and what it costs

The collector receives one stream keyed by `spe_id` in which every record has
a `time` in the same unit, a session (`ses`) to group by on the OS side, and an
address to group by on the network side. Matching "who did this" to "where did
it go" is a sort by `time` within one document, plus the `ses` and `auid` on the
nearest `command`.

The cost is that the export is a transformation. A bug in the parser can drop
a field the raw file still has, and a change to `50-spe.rules` or `local.zeek`
means revisiting the tables above. The raw files on the VM remain the record of
truth for as long as their rotation keeps them.
