an SPE can be open or sealed. these files are the switch, the rules it applies, and the piece that remembers the position across reboots.

`spe-internet` is the admin command. `sudo spe-internet off` loads an nftables table, `spe_egress`, that drops every new outbound connection except what the VM needs to stay healthy; `sudo spe-internet on` deletes the table again; `status` shows the effective and saved modes. the chosen mode is saved in `/var/lib/spe-internet/mode` and replayed at boot, so a sealed SPE stays sealed. only the admin over SSH can run it; the researcher on the desktop cannot.

a second, smaller table, `spe_metadata`, is loaded in both modes. it decides who may talk to the instance metadata endpoint `169.254.169.254`, the address that hands out this VM's identity and, if a cloud role is attached, its credentials: `root` (the boot-time identity step and the cloud agents), `terraform` (the admin) and `_chrony` (time sync). everyone else is refused.

~~~mermaid
flowchart LR
    A["sudo spe-internet off"] --> L["load spe_egress<br>from disabled.nft + allowlist.nft"]
    B["sudo spe-internet on"] --> D["delete spe_egress"]
    L --> S["save mode to<br>/var/lib/spe-internet/mode"]
    D --> S
    A --> M["load spe_metadata<br>from metadata.nft"]
    B --> M
    R["boot: spe-internet-restore.service"] --> RS["spe-internet restore<br>replays the saved mode"]
    RS --> A
    RS --> B
~~~

# where each file lands on the VM

| here | on the VM | what it is |
|---|---|---|
| `spe-internet` | `/usr/local/sbin/spe-internet` | the command: `on`, `off`, `status`, and `restore` for the boot unit. loads rules as one atomic batch, checked first, so a bad edit cannot remove the active protection |
| `spe-internet-disabled.nft` | `/etc/spe-internet/disabled.nft` | the sealed mode. output chain with `policy drop`; lets through loopback, replies to already open connections (the admin's SSH and RDP), the metadata endpoint, AWS time sync, DHCP, and whatever the allowlist adds |
| `spe-internet-allowlist.nft` | `/etc/spe-internet/allowlist.nft` | control-layer exceptions to the sealed mode, one exact address and port each. empty in this lesson; a future log collector goes here |
| `spe-metadata.nft` | `/etc/spe-internet/metadata.nft` | who may reach `169.254.169.254`: `root`, `terraform`, `_chrony`. loaded in both modes |
| `spe-internet-restore.service` | `/etc/systemd/system/spe-internet-restore.service` | oneshot at boot, runs `spe-internet restore` so the saved mode is applied before anyone logs in |

all installed by [setup-internet-control.sh](../../scripts/image/setup-internet-control.sh), which also proves the design at build time: a new HTTPS request must fail with the internet off and succeed with it on, and the metadata endpoint must answer `root` and `terraform` but refuse `speuser`.

# what the sealed mode still allows, and why

| allowed | why |
|---|---|
| loopback | local programs talk to each other, jupyter and rstudio included |
| established, related | the admin's own SSH and RDP sessions keep working; only *new* outbound connections are blocked |
| `169.254.169.254` | the metadata endpoint is the hypervisor, not the internet; the identity step and the cloud agents need it |
| `169.254.169.123` udp 123 | AWS serves time from this second link-local address; accurate clocks keep the audit timestamps trustworthy |
| DHCP | the address lease must renew after a reboot in sealed mode |
| `allowlist.nft` | nothing today. when a log collector exists, its exact address and port go here, and `sudo spe-internet off` must be run again to load it |

DNS is not in the list, on purpose: in sealed mode nothing can resolve a name, so an exception in the allowlist must be an IP address.

# reading it

~~~bash
sudo spe-internet status                              # effective mode, saved mode, metadata policy
sudo nft list table inet spe_egress                   # the sealed rules with packet counters, or an error if open
sudo nft list table inet spe_metadata                 # who reached or was refused the metadata endpoint
curl --head --connect-timeout 5 https://example.com   # the practical test
~~~

the heartbeat reports the same thing independently, with a real TCP handshake every interval, so the collector learns whether an SPE is sealed without asking it; see [logging/heartbeat](../logging/heartbeat/README.md).
