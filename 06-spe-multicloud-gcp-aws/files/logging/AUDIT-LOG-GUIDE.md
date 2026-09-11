# What is in this folder

Everything that produces a record on the SPE lives here, one subfolder per
producer. Each subfolder has its own README with the details: the files it
holds, where they land on the VM, what the raw output looks like, and how to
read it.

| subfolder | deals with | writes to, on the VM |
|---|---|---|
| [auditd/](auditd/) | the operating system: who logged in, what they typed in a terminal, which programs they started | `/var/log/audit/audit.log` |
| [zeek/](zeek/) | the network: one line per connection, with addresses, ports, bytes, and how it ended | `/var/log/spe-audit/network.jsonl`, archived hourly under `/var/log/spe-audit/YYYY-MM-DD/` |
| [heartbeat/](heartbeat/) | the SPE saying it is alive: its name, the time, and whether the internet is reachable, once per interval | the systemd journal |

The first two are the audit evidence. The heartbeat is a health signal and the
only stream that already carries the SPE's name in every line.

For the plain-words picture of how these fit together, where the SPE's name
comes from, and who may read what, see
[HOW-THE-SPE-WORKS.md](../../HOW-THE-SPE-WORKS.md).
