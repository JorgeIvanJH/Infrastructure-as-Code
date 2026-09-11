The heartbeat service is a custom one created to send additional information about the SPE. every interval it builds one JSON document with the SPE id, to recognise it from the control plane, the time, whether the SPE is open or sealed from the internet, and, since this iteration, everything auditd and zeek recorded since the previous document. the shape of that document and why each field is in it is in [the logging README](../README.md). this file is about how the agent runs and how it collects.

the SPE id and the heartbeat interval are not baked inside the image. they are attached to the instance by `terraform apply` and read at boot through the instance metadata endpoint, `169.254.169.254`. that address is whitelisted in [spe-internet-disabled.nft](../../internet-control/spe-internet-disabled.nft) so it keeps working with the internet off, and [spe-metadata.nft](../../internet-control/spe-metadata.nft) restricts who may use its HTTP API, in both modes, to `root` (this boot step and the cloud agents) and `terraform` (the admin). the researcher cannot query it.

the actual daemon is the script in [spe-monitoring-agent.py](spe-monitoring-agent.py), configured to run as a systemd service through [spe-monitoring-agent.service](spe-monitoring-agent.service), and installed by [setup.sh](../../../scripts/image/setup.sh). before it can start, [spe-identity](spe-identity), run once at boot by [spe-identity.service](spe-identity.service), asks the metadata endpoint for the values terraform attached and writes them to `/etc/spe/identity.env`. the agent's unit `Requires=` that step and loads the file with `EnvironmentFile=`. if the identity is missing, there is no heartbeat at all rather than one with made-up values.

~~~mermaid
flowchart LR
    subgraph laptop["laptop: terraform apply"]
        V["terraform.tfvars<br>spe_id = ...<br>heartbeat_interval_seconds = ..."]
        M["instances/gcp/main.tf or instances/aws/main.tf<br>attach them to the instance as<br>spe-id and spe-heartbeat-interval"]
    end
    subgraph vm["the SPE, at boot"]
        E["169.254.169.254<br>instance metadata API<br>root and terraform only"]
        I["spe-identity.service<br>reads the two keys plus cloud, instance id, region"]
        F["/etc/spe/identity.env<br>SPE_ID, SPE_HEARTBEAT_INTERVAL,<br>SPE_CLOUD, SPE_INSTANCE_ID, SPE_REGION"]
        A["spe-monitoring-agent.service<br>EnvironmentFile= loads them<br>python prints one JSON document per interval"]
        J["systemd journal<br>journalctl -u spe-monitoring-agent"]
    end
    V --> M --> E --> I --> F --> A --> J
~~~

the variables live in [instances/gcp/variables.tf](../../../instances/gcp/variables.tf) and [instances/aws/variables.tf](../../../instances/aws/variables.tf), with the same names on both clouds: `spe_id` and `heartbeat_interval_seconds`. each cloud has its own way of attaching a key to an instance (GCP calls it metadata, AWS exposes tags through the endpoint), but from inside the VM both look the same: a key called `spe-id` and one called `spe-heartbeat-interval`, fetched by `spe-identity` with one small difference per cloud in the HTTP request. changing a value in `terraform.tfvars` and running `terraform apply` updates the instance in place; the VM picks it up at the next boot or with `sudo systemctl restart spe-identity spe-monitoring-agent`.

# how the agent collects the other two streams

the agent does not get the records pushed to it. every interval it goes and reads the two files the other producers write, from the point where it stopped last time, and puts what it finds under `os` and `net`. it runs as `terraform`, so both files had to be opened to that account: auditd writes its log for the `terraform` group (`log_group` in [auditd.conf](../auditd/auditd.conf)), and `terraform` is a member of the `spe-netaudit` group that owns the zeek directory. both are set up by [setup-auditing.sh](../../../scripts/image/setup-auditing.sh). no sudo is involved.

~~~mermaid
flowchart LR
    subgraph producers["written by others"]
        AL["/var/log/audit/audit.log<br>auditd, several lines per event"]
        ZL["/var/log/spe-audit/current/network.log<br>zeek, one JSON line per connection"]
        ZA["/var/log/spe-audit/YYYY-MM-DD/*.log.gz<br>zeek, the hourly archives"]
    end
    subgraph agent["spe-monitoring-agent, every interval"]
        AS["ausearch --checkpoint<br>events after the bookmark,<br>grouped, hex decoded, shaped"]
        ZR["read from the saved offset,<br>whole lines only; after a rotation,<br>finish the old file in its archive"]
        P["probe 1.1.1.1:443"]
        D["one JSON document<br>spe_id, boot_id, sequence, timestamp,<br>internet, os[], net[]"]
    end
    subgraph state["/var/lib/spe-monitoring-agent"]
        S["sequence<br>audit.checkpoint<br>zeek.cursor"]
    end
    AL --> AS --> D
    ZL --> ZR --> D
    ZA --> ZR
    P --> D
    S -. "read before" .-> AS
    S -. "read before" .-> ZR
    D -- "printed, then bookmarks move" --> S
~~~

for auditd the agent leans on `ausearch`, the official reading tool. its `--checkpoint` option keeps a bookmark file with the last event seen, follows the log across rotations, and hands back only the events after it. the agent groups the lines of each event, decodes the hex fields, keeps the human names auditd adds (`AUID="speuser"`), and drops everything except the three kinds of event the SPE cares about: a command, a session opening or closing, and keystrokes. what stays of each is listed in [the logging README](../README.md).

for zeek the agent remembers which live file it was reading (by inode) and how far it got (byte offset), and reads only whole lines, since zeek may be in the middle of writing one. once an hour ZeekControl moves the live file into a dated, gzipped archive and starts a new one. the agent notices (new inode, or a file shorter than its offset), finishes the old file by reading its archive from the saved offset, then starts the new live file at zero. the archive takes a few seconds to appear, so the agent waits up to three intervals for it. the ten fields kept per connection, and their plainer names, are in the same README.

three small files under `/var/lib/spe-monitoring-agent` are the agent's memory: the last `sequence` number, ausearch's checkpoint, and the zeek cursor. systemd creates the directory for the unit (`StateDirectory=`) and owns it to `terraform`. the bookmarks only move after the document has been printed, so a crash in between repeats records rather than losing them. delete the directory and the agent starts again from the current boot.

`--once` builds one document and exits without moving any bookmark. it is how the build proves the agent works and how to peek at an SPE by hand.

# the internet connection test

an SPE can be open or sealed. [spe-internet](../../internet-control/spe-internet) is the admin command that flips that: `sudo spe-internet off` loads an nftables table, `spe_egress`, whose rules in [spe-internet-disabled.nft](../../internet-control/spe-internet-disabled.nft) drop every new outbound connection except loopback, replies to the admin's own SSH and RDP sessions, the metadata endpoint, time sync and DHCP; `sudo spe-internet on` deletes the table again. the chosen mode is saved in `/var/lib/spe-internet/mode` and [spe-internet-restore.service](../../internet-control/spe-internet-restore.service) replays it at boot, so a sealed SPE stays sealed across reboots. a researcher inside the desktop cannot run it, only the admin over SSH can.

the heartbeat does not trust what `spe-internet` says it set, it checks the wire. every interval the agent opens a plain TCP connection to a stable public address, `1.1.1.1:443`, and if that fails, `8.8.8.8:443`, with a two second timeout each, and closes it straight away. no request is sent, no data, no DNS lookup, nothing downloaded. if a handshake completes the internet is `reachable`; if both fail it is `blocked`. a firewall edited by hand, a broken route, or a cloud outage all show up here, where the saved mode would not.

two addresses, so one provider having a bad day does not read as a sealed SPE. with the internet off the nftables policy drops the packets, so each attempt waits out its timeout: four seconds at most, inside the minimum five second interval.

the probe is itself a connection, so zeek records it while the internet is on: one `net` entry per heartbeat to `1.1.1.1:443`, zero bytes, `SF`. that is a known signature, easy to recognise or filter, and it doubles as proof in the network audit that the agent is alive. with the internet off the SYN is dropped before it reaches the interface, so zeek records nothing for it; a document saying `blocked` with no matching `net` entry is what a sealed SPE looks like.

# where each file lands on the VM

| here | on the VM | what it is |
|---|---|---|
| `spe-monitoring-agent.py` | `/opt/spe-agent/spe-monitoring-agent.py` | the agent. reads `SPE_ID` and `SPE_HEARTBEAT_INTERVAL` from the environment, collects the new auditd events and zeek connections, probes the internet with one TCP handshake, prints one JSON document per interval, exits with a clear message if either variable is missing. `--once` prints a single document without moving any bookmark |
| `spe-monitoring-agent.service` | `/etc/systemd/system/spe-monitoring-agent.service` | runs the agent as `terraform`, output to the journal, restarts on failure. `Requires=spe-identity.service`, loads `/etc/spe/identity.env`, and owns `/var/lib/spe-monitoring-agent` through `StateDirectory=` |
| `spe-monitoring-agent-journald.conf` | `/etc/systemd/journald.conf.d/spe-monitoring-agent.conf` | raises journald's `LineMax` from 48 KiB to 16 MiB, so a long document is stored as one line and not cut in two |
| `spe-identity` | `/usr/local/sbin/spe-identity` | detects the cloud from DMI, fetches `spe-id`, `spe-heartbeat-interval`, instance id and region from the metadata endpoint, checks their shape, writes the env file atomically |
| `spe-identity.service` | `/etc/systemd/system/spe-identity.service` | oneshot at boot, as root, after the network is online and the internet mode is restored |

all installed by [setup.sh](../../../scripts/image/setup.sh). the build verifies the units and compiles the python there, restarts journald with the drop-in and reads back a 200,000-byte line whole, and later, at the end of [setup-auditing.sh](../../../scripts/image/setup-auditing.sh), once auditd and zeek have both written something, runs the agent with `--once` as `terraform` and checks that the document holds the build's own `curl` command under `os` and its HTTPS connection under `net`. it cannot run `spe-identity`, because the build VM carries no SPE metadata, and that is the point. `/etc/spe/identity.env` exists only on a deployed SPE.

# most relevant raw Heartbeat outputs

one document per interval, in the journal, not in a file. a quiet interval looks like this:

~~~json
{"spe_id":"spe-demo-006-gcp","boot_id":"7f0b2c6e-3d9a-4a1e-9b2f-0c1d2e3f4a5b","sequence":42,"timestamp":"2026-09-10T14:30:00Z","internet":"reachable","os":[],"net":[{"time":1787754595.31,"src_ip":"10.60.1.2","src_port":51544,"dst_ip":"1.1.1.1","dst_port":443,"proto":"tcp","duration":0.001,"bytes_out":0,"bytes_in":0,"state":"SF"}]}
~~~

- `spe_id`: the value from `terraform.tfvars`, so two SPEs are never confused at the collector.
- `boot_id`: linux's random id for this boot. new after every reboot.
- `sequence`: one per document, kept on disk, never reused.
- `timestamp`: when the document was built. UTC to the second, ISO 8601 with a `Z`.
- `internet`: `reachable` or `blocked`, measured with a real TCP handshake to a public address, not read from what the toggle says.
- `os`: the auditd events since the previous document, empty when nobody did anything. shaped as in [the logging README](../README.md).
- `net`: the zeek connections since the previous document. the one above is the agent's own probe.

the journal wraps each line in its own envelope with fields the agent did not write and cannot fake:

~~~bash
sudo journalctl -u spe-monitoring-agent -o json -n 1 | jq '{MESSAGE, __REALTIME_TIMESTAMP, _UID, _BOOT_ID, _HOSTNAME}'
~~~

- `MESSAGE`: the document, as a string. parse it as JSON before forwarding or it becomes JSON inside JSON.
- `__REALTIME_TIMESTAMP`: when journald received the line, in microseconds. stamped by systemd, not by the agent.
- `_BOOT_ID`: the same value the agent puts in `boot_id`, stamped by systemd.

the journal is a stop on the way, not the destination. out of the box it cuts a stream line at 48 KiB (`LineMax`), and a busy interval goes past that: 400 commands in one interval made a 54 KiB document during testing, and the journal held it as two halves that did not parse. [spe-monitoring-agent-journald.conf](spe-monitoring-agent-journald.conf) raises the limit to 16 MiB, far above any document the SPE produces. the real answer is still the next step, sending the document to a collector instead of printing it.

# reading it

~~~bash
sudo journalctl -u spe-monitoring-agent -f                       # live, one document per interval
sudo journalctl -u spe-monitoring-agent -o cat -n 1 | jq .       # the last document, pretty
sudo journalctl -u spe-monitoring-agent -o cat -n 1 | jq '{sequence, internet, os: (.os | length), net: (.net | length)}'
sudo -u terraform env SPE_ID=peek SPE_HEARTBEAT_INTERVAL=5 python3 /opt/spe-agent/spe-monitoring-agent.py --once | jq .   # what the next document would hold, without moving any bookmark
sudo ls -la /var/lib/spe-monitoring-agent                        # the three bookmarks
sudo journalctl -u spe-identity -n 3                             # what identity was read at boot
cat /etc/spe/identity.env                                        # the values the agent sees
sudo systemctl status spe-identity spe-monitoring-agent          # both should be active
~~~

`-o cat` prints only the message, which is what `jq` wants. with `--once` run from an ssh session, `os` will hold that very command, and the keystrokes that typed it a moment later.

the heartbeat is the only one of the three streams that already knows its `spe_id`, and now the one that carries the other two. they are described in [auditd/README.md](../auditd/README.md) and [zeek/README.md](../zeek/README.md); [the logging README](../README.md) is the short index of all three and holds the shape of the exported document.
