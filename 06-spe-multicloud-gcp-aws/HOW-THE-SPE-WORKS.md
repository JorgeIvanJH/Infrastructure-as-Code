# How the SPE works, in plain words

This is the intuition page. It answers four questions people ask after their
first deploy: where does the SPE get its name, how can the heartbeat keep going
with the internet off, where do the audit records land, and who is allowed to
do what inside the VM. The detailed files are linked from each section.

## 1. The image knows nothing about any SPE

Packer bakes one image per cloud. Terraform later creates VMs from it. The trick
is that the name of the SPE and its heartbeat interval are **not** in the image.
They travel with the VM instead, as cloud metadata Terraform attaches at
`terraform apply`.

~~~mermaid
flowchart LR
    subgraph build["packer build, once"]
        R["recipe: scripts + files"] --> I["image<br>no spe-id, no interval,<br>no /etc/spe/identity.env"]
    end
    subgraph deploy["terraform apply, per SPE"]
        T["terraform.tfvars<br>spe_id, heartbeat_interval_seconds"] --> V["VM created from the image<br>+ metadata: spe-id, spe-heartbeat-interval"]
    end
    subgraph boot["first boot, inside the VM"]
        V --> M["169.254.169.254<br>the cloud's metadata API,<br>a hypervisor address, not the internet"]
        M --> S["spe-identity (root)<br>asks for the two keys"]
        S --> F["/etc/spe/identity.env<br>SPE_ID=spe-demo-006-gcp<br>SPE_HEARTBEAT_INTERVAL=30"]
        F --> A["spe-monitoring-agent"]
    end
    I -.-> V
~~~

Why it is done this way:

- **one image, many SPEs.** The same image starts `spe-demo-006-gcp` today and
  `spe-lab-042` tomorrow. Nothing has to be rebuilt to change a name or an
  interval; change `terraform.tfvars`, apply, reboot.
- **the build VM proves it.** The Packer build VM has no `spe-*` metadata, so
  `spe-identity` is deliberately never run during the build. If someone tried to
  bake an identity in, that step would fail.
- **no identity, no heartbeat.** The agent's unit `Requires=` the identity step
  and loads the file it wrote. A VM started outside this Terraform has no
  metadata keys, the identity step fails, and there is simply no heartbeat,
  rather than one with made-up values.

The metadata API is the address `169.254.169.254` on port 80. Each cloud speaks
a slightly different dialect (GCP wants a header, AWS wants a short-lived token
first), and `spe-identity` handles both. Files:
[spe-identity](files/logging/heartbeat/spe-identity),
[spe-identity.service](files/logging/heartbeat/spe-identity.service),
[instances/gcp/main.tf](instances/gcp/main.tf), [instances/aws/main.tf](instances/aws/main.tf).

## 2. Sealed mode, and why the heartbeat does not care

`sudo spe-internet off` seals the SPE. It loads a firewall table that drops every
**new outgoing** connection except a short list. It applies to everyone on the
VM, the administrator included.

~~~mermaid
flowchart TB
    subgraph vm["sealed SPE: what may still leave"]
        L["loopback<br>jupyter, rstudio, local programs"]
        E["replies on connections that already exist<br>the admin's SSH and RDP keep working"]
        M["169.254.169.254 port 80<br>metadata API, root and terraform only"]
        N["time: 169.254.169.254 udp 123 on GCP,<br>169.254.169.123 udp 123 on AWS"]
        D["DHCP<br>the address lease"]
    end
    X["everything else: dropped<br>web, DNS, package mirrors, the heartbeat's probe"]
    style X fill:#fdd,stroke:#c00
~~~

Now the heartbeat. It is easy to picture it as a message sent to a control
plane, but in this lesson **it is not sent anywhere**. Every interval the agent
prints one JSON line, and systemd stores that line in the VM's own journal. A
local write cannot be blocked by an outbound firewall, so the heartbeat keeps
going with the internet off.

~~~mermaid
sequenceDiagram
    participant A as spe-monitoring-agent
    participant W as the wire
    participant J as systemd journal (on the VM)
    loop every SPE_HEARTBEAT_INTERVAL seconds
        A->>W: TCP handshake to 1.1.1.1:443 (no data, no DNS)
        alt internet on
            W-->>A: handshake completes
            A->>J: {"spe_id":..., "internet":"reachable"}
        else sealed
            Note over W: SYN dropped before it reaches the interface
            A->>J: {"spe_id":..., "internet":"blocked"}
        end
    end
~~~

What sealed mode changes is the **value** of one field. The agent checks the
wire itself with a bare handshake, and when that fails it writes `blocked`.
That is more trustworthy than reading what the toggle says, because a hand
edited firewall or a cloud outage shows up the same way.

Confirmed on 2026-09-11 on both clouds: with `spe-internet off`, and again after
rebooting while sealed, the journal kept receiving one line every 30 seconds
with `"internet":"blocked"`, and the boot-time identity step still read its two
keys through the metadata API, which is on the allowed list above. Zeek recorded
nothing for the blocked probes, because the packets never reached the interface
it watches.

One consequence for the future: a real off-VM exporter would itself be a new
outgoing connection and would need a line in
[spe-internet-allowlist.nft](files/internet-control/spe-internet-allowlist.nft),
by IP address, since names cannot be resolved while sealed.

Files: [spe-internet](files/internet-control/spe-internet),
[spe-internet-disabled.nft](files/internet-control/spe-internet-disabled.nft),
[spe-monitoring-agent.py](files/logging/heartbeat/spe-monitoring-agent.py).

## 3. Where the records live

Three streams, three places, all on the VM's own disk. Nothing leaves the VM.

~~~mermaid
flowchart LR
    subgraph producers
        P1["a human runs a program<br>logs in, types in a terminal"]
        P2["a packet crosses<br>the network interface"]
        P3["the agent prints<br>one line per interval"]
    end
    subgraph writers
        W1["auditd<br>as root"]
        W2["zeek<br>as spe-netaudit"]
        W3["journald<br>as root"]
    end
    subgraph disk["on the VM"]
        F1["/var/log/audit/audit.log<br>raw text, 10 MB x 5 files"]
        F2["/var/log/spe-audit/current/network.log<br>JSON lines, this hour<br>/var/log/spe-audit/YYYY-MM-DD/*.log.gz<br>hourly archives, kept 7 days"]
        F3["systemd journal<br>journalctl -u spe-monitoring-agent"]
    end
    P1 --> W1 --> F1
    P2 --> W2 --> F2
    P3 --> W3 --> F3
~~~

| stream | path on the VM | owner and mode | read with |
|---|---|---|---|
| operating system: logins, keystrokes, programs started | `/var/log/audit/audit.log` | `root`, `0600` | `sudo ausearch -k spe_cli -i --start recent`, `sudo aureport -l -i`, `sudo aureport --tty -i` |
| network: one line per connection | `/var/log/spe-audit/network.jsonl` (a link to `current/network.log`), archives under `/var/log/spe-audit/YYYY-MM-DD/` | `spe-netaudit`, `0750` directory | `sudo tail /var/log/spe-audit/network.jsonl \| jq .` |
| heartbeat: alive, and is the internet reachable | the systemd journal | `root` | `sudo journalctl -u spe-monitoring-agent -f` |

Only the operating-system stream and the network stream are audit evidence. The
heartbeat is the only one that already carries the SPE's name in every line;
the other two would get it from `/etc/spe/identity.env` at export time. How each
one is produced, rotated, and read is in the README of its folder under
[files/logging/](files/logging/), indexed by
[files/logging/AUDIT-LOG-GUIDE.md](files/logging/AUDIT-LOG-GUIDE.md).

## 4. Who may do what

Four identities matter. Two are humans, two are machinery.

~~~mermaid
flowchart TB
    subgraph humans
        T["terraform<br>the administrator<br>arrives by SSH with the baked-in key"]
        U["speuser<br>the researcher<br>arrives by RDP through Guacamole"]
    end
    subgraph machinery
        R["root<br>systemd, auditd, spe-identity,<br>the cloud guest agents"]
        Z["spe-netaudit<br>runs zeek, owns /var/log/spe-audit,<br>cannot log in at all"]
    end
    T -- "sudo, no password" --> R
    T -- "sudo spe-internet on/off" --> FW["outbound firewall"]
    T -- "sudo passwd speuser" --> U
    U --> D["XFCE desktop, JupyterLab, RStudio,<br>~/spe-data-lab"]
    R --> M["metadata API"]
    T --> M
    U -- "connection refused" --x M
    U -- "no sudo, not in sudoers" --x R
~~~

A line ending in a cross is a door that is closed: the researcher has no way
to become root, and a connection from the researcher to the metadata API is
refused at once by the firewall. Everything else the researcher does happens
inside the desktop and the home folder.

| | `terraform` (admin) | `speuser` (researcher) | `spe-netaudit` | `root` |
|---|---|---|---|---|
| how it gets in | SSH with the private half of `tf-packer`; the public half is baked into the image | RDP on 3389 via Guacamole, after the admin sets a password with `sudo passwd speuser`; created locked, so no reusable password exists anywhere | never; `nologin` shell | never directly; only through `sudo` from `terraform` |
| desktop | no password, so no RDP | yes, XFCE with the two launchers | no | no |
| `sudo` | yes, without a password | no | no | is root |
| seal or open the internet | yes, `sudo spe-internet off` / `on` | no; the command needs root | no | yes |
| affected by sealed mode | yes, like everyone | yes | yes | yes, except the metadata API and time |
| metadata API on `169.254.169.254:80` | allowed | refused at once | refused | allowed |
| read `/var/log/audit/audit.log` | with `sudo` | no | no | yes |
| read `/var/log/spe-audit` | with `sudo` | no | yes, owns it | yes |
| read the heartbeat journal | with `sudo` | no | no | yes |
| change or delete the logs | with `sudo`, and that is the known limit of a local design | no | zeek's own files only | yes |
| what gets audited | every program started, every keystroke in a terminal, every login, `sudo` included | the same | nothing; system account, `auid` unset | nothing by itself; root shells reached through `sudo` keep the admin's `auid` |
| runs | the heartbeat agent, as a normal unprivileged process | JupyterLab and RStudio, as itself | zeek, with only the two capabilities packet capture needs | everything else |

Two points that are easy to miss:

- **the researcher is audited but cannot see the audit.** Every command
  `speuser` types is recorded, and `speuser` cannot open either log file or the
  journal. The administrator can read everything and, being root through
  `sudo`, could also tamper with it. Protecting the logs from the admin is what
  an off-VM export is for.
- **`auid` is the login identity and it sticks.** When the admin runs
  `sudo bash`, the records say `uid=root` but still `auid=terraform`. That is
  how a root shell is traced back to a person.

Files: [setup.sh](scripts/image/setup.sh) creates the two human accounts,
[setup-auditing.sh](scripts/image/setup-auditing.sh) creates `spe-netaudit`,
[spe-metadata.nft](files/internet-control/spe-metadata.nft) decides who may use
the metadata API, [50-spe.rules](files/logging/auditd/50-spe.rules) and
[spe-tty-audit](files/logging/auditd/spe-tty-audit) decide what is recorded.

## Security and scope

- This is a learning environment. Both VMs have public addresses, narrowed to
  one source `/32` for SSH and RDP.
- Logs stay on the VM and die with its disk. A root administrator can alter
  them.
- Guacamole stores the researcher's RDP password in plaintext on the laptop.
- The shared SSH key is baked into the image for continuity between lessons; a
  production design injects access per deployment.
