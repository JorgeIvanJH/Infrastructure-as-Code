The heartbeat service is a custom one created to send additional information about the SPE: the SPE id, to recognise it from the control plane, the datetime, a fixed message, and whether the SPE is open or sealed from the internet.

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
        A["spe-monitoring-agent.service<br>EnvironmentFile= loads them<br>python prints one JSON line per interval"]
        J["systemd journal<br>journalctl -u spe-monitoring-agent"]
    end
    V --> M --> E --> I --> F --> A --> J
~~~

the variables live in [instances/gcp/variables.tf](../../../instances/gcp/variables.tf) and [instances/aws/variables.tf](../../../instances/aws/variables.tf), with the same names on both clouds: `spe_id` and `heartbeat_interval_seconds`. each cloud has its own way of attaching a key to an instance (GCP calls it metadata, AWS exposes tags through the endpoint), but from inside the VM both look the same: a key called `spe-id` and one called `spe-heartbeat-interval`, fetched by `spe-identity` with one small difference per cloud in the HTTP request. changing a value in `terraform.tfvars` and running `terraform apply` updates the instance in place; the VM picks it up at the next boot or with `sudo systemctl restart spe-identity spe-monitoring-agent`.

# the internet connection test

an SPE can be open or sealed. [spe-internet](../../internet-control/spe-internet) is the admin command that flips that: `sudo spe-internet off` loads an nftables table, `spe_egress`, whose rules in [spe-internet-disabled.nft](../../internet-control/spe-internet-disabled.nft) drop every new outbound connection except loopback, replies to the admin's own SSH and RDP sessions, the metadata endpoint, time sync and DHCP; `sudo spe-internet on` deletes the table again. the chosen mode is saved in `/var/lib/spe-internet/mode` and [spe-internet-restore.service](../../internet-control/spe-internet-restore.service) replays it at boot, so a sealed SPE stays sealed across reboots. a researcher inside the desktop cannot run it, only the admin over SSH can.

the heartbeat does not trust what `spe-internet` says it set, it checks the wire. every interval the agent opens a plain TCP connection to a stable public address, `1.1.1.1:443`, and if that fails, `8.8.8.8:443`, with a two second timeout each, and closes it straight away. no request is sent, no data, no DNS lookup, nothing downloaded. if a handshake completes the internet is `reachable`; if both fail it is `blocked`. a firewall edited by hand, a broken route, or a cloud outage all show up here, where the saved mode would not.

two addresses, so one provider having a bad day does not read as a sealed SPE. with the internet off the nftables policy drops the packets, so each attempt waits out its timeout: four seconds at most, inside the minimum five second interval.

the probe is itself a connection, so zeek records it while the internet is on: one `network.log` line per heartbeat to `1.1.1.1:443`, zero bytes, `SF`. that is a known signature, easy to recognise or filter, and it doubles as proof in the network audit that the agent is alive. with the internet off the SYN is dropped before it reaches the interface, so zeek records nothing for it; a heartbeat saying `blocked` with no matching network line is what a sealed SPE looks like.

# where each file lands on the VM

| here | on the VM | what it is |
|---|---|---|
| `spe-monitoring-agent.py` | `/opt/spe-agent/spe-monitoring-agent.py` | the agent. reads `SPE_ID` and `SPE_HEARTBEAT_INTERVAL` from the environment, probes the internet with one TCP handshake, prints one JSON heartbeat per interval, exits with a clear message if either variable is missing |
| `spe-monitoring-agent.service` | `/etc/systemd/system/spe-monitoring-agent.service` | runs the agent as `terraform`, output to the journal, restarts on failure. `Requires=spe-identity.service` and loads `/etc/spe/identity.env` |
| `spe-identity` | `/usr/local/sbin/spe-identity` | detects the cloud from DMI, fetches `spe-id`, `spe-heartbeat-interval`, instance id and region from the metadata endpoint, checks their shape, writes the env file atomically |
| `spe-identity.service` | `/etc/systemd/system/spe-identity.service` | oneshot at boot, as root, after the network is online and the internet mode is restored |

all installed by [setup.sh](../../../scripts/image/setup.sh). the build only verifies the units and compiles the python; it cannot run `spe-identity`, because the build VM carries no SPE metadata, and that is the point. `/etc/spe/identity.env` exists only on a deployed SPE.

# most relevant raw Heartbeat outputs

one line per interval, in the journal, not in a file:

~~~json
{"spe_id":"spe-demo-006-gcp","timestamp":"2026-09-10T14:30:00Z","message":"SPE monitoring agent is alive","internet":"reachable"}
~~~

- `spe_id`: the value from `terraform.tfvars`, so two SPEs are never confused at the collector.
- `timestamp`: UTC to the second, ISO 8601 with a `Z`.
- `message`: fixed. it is the presence of the line that matters, not its text.
- `internet`: `reachable` or `blocked`, measured with a real TCP handshake to a public address, not read from what the toggle says.

the journal wraps each line in its own envelope with fields the agent did not write and cannot fake, which are worth shipping alongside:

~~~bash
sudo journalctl -u spe-monitoring-agent -o json -n 1 | jq '{MESSAGE, __REALTIME_TIMESTAMP, _UID, _BOOT_ID, _HOSTNAME}'
~~~

- `MESSAGE`: the heartbeat, as a string. parse it as JSON before forwarding or it becomes JSON inside JSON.
- `__REALTIME_TIMESTAMP`: when journald received the line, in microseconds. stamped by systemd, not by the agent.
- `_BOOT_ID`: changes at every reboot, so gaps between heartbeats can be told apart from restarts.

# reading it

~~~bash
sudo journalctl -u spe-monitoring-agent -f                       # live
sudo journalctl -u spe-identity -n 3                             # what identity was read at boot
cat /etc/spe/identity.env                                        # the values the agent sees
sudo systemctl status spe-identity spe-monitoring-agent          # both should be active
~~~

the heartbeat is the only one of the three streams that already knows its `spe_id`. the two audit streams are described in [auditd/README.md](../auditd/README.md) and [zeek/README.md](../zeek/README.md), and [AUDIT-LOG-GUIDE.md](../AUDIT-LOG-GUIDE.md) shows how to read them together.
