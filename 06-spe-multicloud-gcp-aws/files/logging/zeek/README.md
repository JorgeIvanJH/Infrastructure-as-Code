Zeek is a free and open-source network analysis framework. it watches the packets going through a network interface and writes down what it sees, without touching the traffic.

the full pipeline, in simple words: packets arrive at the network interface, linux hands them to zeek through `AF_PACKET` and `libpcap`, zeek reassembles them into connections and recognises the protocols inside (DNS, HTTP, TLS, ...), turns what it sees into events (new connection, DNS query, HTTP request, ...), runs the policy scripts we loaded against those events, and hands structured records to its logging framework, whose ASCII writer stores them in files like `conn.log`, `dns.log`, `http.log`.

~~~mermaid
flowchart LR
    N["network interface<br>the one with the default route"]
    P["AF_PACKET + libpcap<br>packet capture"]
    Z["zeek<br>reassembles connections,<br>recognises protocols"]
    E["events<br>new connection, DNS query, HTTP request, ..."]
    L["local.zeek<br>keep only the connection log,<br>15 fields, JSON"]
    F["logging framework<br>ASCII writer"]
    C["/var/log/spe-audit/current/network.log<br>live, this hour"]
    A["/var/log/spe-audit/YYYY-MM-DD/<br>network.*.log.gz, kept 7 days"]
    N --> P --> Z --> E --> L --> F --> C
    C -- "every hour, ZeekControl" --> A
~~~

we run all this the official way, with ZeekControl (`zeekctl`), zeek's own operations tool, as one standalone node. that is where the three files come from:

- [node.cfg](node.cfg) says which node to run and which interface it watches.
- [local.zeek](local.zeek) is the site policy: what to do with the events.
- [zeekctl.cfg](zeekctl.cfg) says where the logs go, how often they rotate, and how long they are kept.

plus [networks.cfg](networks.cfg), which lists the networks that count as "local"; private address space is automatic so it lists nothing.

two things are ours because ZeekControl does not do them. first, a static `node.cfg` cannot know the interface name, which differs between GCP and AWS. [zeek-set-interface](zeek-set-interface) rewrites the `interface=` line at every start with the interface carrying the default route, so one image works on both clouds. second, ZeekControl expects to be started by hand and kept healthy by a cron job. [zeek.service](zeek.service) runs `zeekctl deploy` at boot and `zeekctl stop` at shutdown, and [zeek-cron.timer](zeek-cron.timer) runs `zeekctl cron` every five minutes, exactly what the docs ask for in crontab. both run as `spe-netaudit`, not root, with only the two capabilities packet capture needs.

~~~mermaid
flowchart TB
    B["boot"] --> U["zeek.service"]
    U -- "ExecStartPre, as root" --> I["zeek-set-interface<br>writes interface= into node.cfg"]
    I --> D["zeekctl deploy<br>as spe-netaudit"]
    CFG["node.cfg<br>zeekctl.cfg<br>networks.cfg<br>local.zeek"] -. "read by" .-> D
    D --> ZN["zeek node<br>captures and logs"]
    ZN --> C["/var/log/spe-audit/current/network.log"]
    T["zeek-cron.timer<br>every 5 minutes"] --> CR["zeekctl cron"]
    CR -- "restart if crashed" --> ZN
    CR -- "delete archives older than 7 days" --> AR["/var/log/spe-audit/YYYY-MM-DD/"]
    C -- "hourly rotation" --> AR
    S["shutdown"] --> ST["zeekctl stop<br>flush and archive"] --> AR
~~~

ZeekControl loads zeek's full default script set, so protocol recognition is on. we keep only the connection log anyway: the last block in `local.zeek` disables every other stream. the SPE audits who talked to whom, not what they said. delete that block to get `dns.log`, `ssl.log`, `http.log` and the rest back.

# where each file lands on the VM

| here | on the VM | what it is |
|---|---|---|
| `node.cfg` | `/opt/zeek/etc/node.cfg` | one `[zeek]` node, `type=standalone`. the `interface=` line is a placeholder rewritten at start |
| `zeekctl.cfg` | `/opt/zeek/etc/zeekctl.cfg` | stock file with our changes marked `SPE:`. logs archive into `/var/log/spe-audit`, rotate hourly, expire after 7 days. mail, `stats.log` and the prometheus port are off |
| `networks.cfg` | `/opt/zeek/etc/networks.cfg` | stock file, nothing listed |
| `local.zeek` | `/opt/zeek/share/zeek/site/local.zeek` | the policy. ignores cloud checksum offload, switches output to JSON, renames the connection log to `network`, keeps 15 fields, disables all other logs |
| `zeek-set-interface` | `/usr/local/sbin/zeek-set-interface` | finds the default-route interface and writes it into `node.cfg`. runs as root from the unit, before deploy |
| `zeek.service` | `/etc/systemd/system/zeek.service` | `zeekctl deploy` / `zeekctl stop`, sandboxed, as `spe-netaudit` |
| `zeek-cron.service`, `zeek-cron.timer` | `/etc/systemd/system/` | `zeekctl cron` every five minutes: restarts a crashed node, deletes expired archives |

all installed by [setup-auditing.sh](../../../scripts/setup-auditing.sh). ZeekControl's run-time data lives in `/opt/zeek/spool`, owned by `spe-netaudit`. the live log is `/var/log/spe-audit/current/network.log` (`current` is a symlink ZeekControl keeps into the spool), and every hour it is moved, gzipped, to `/var/log/spe-audit/YYYY-MM-DD/network.HH:MM:SS-HH:MM:SS.log.gz`. the `network.jsonl` symlink points at the live file. reading any of it needs `sudo`.

# most relevant raw Zeek outputs

one line per connection, written when the connection closes or zeek gives up waiting for it, not when it starts. so a long SSH session shows up at the end, with `ts` pointing back at the beginning. this is an HTTPS request to `example.com` from the SPE:

~~~json
{"ts":1787754601.25,"uid":"CmXk4d3JZa8rPvLYd","id.orig_h":"10.60.1.2","id.orig_p":43210,"id.resp_h":"93.184.216.34","id.resp_p":443,"proto":"tcp","duration":0.12,"orig_bytes":80,"resp_bytes":300,"conn_state":"SF","orig_pkts":6,"resp_pkts":5,"orig_ip_bytes":400,"resp_ip_bytes":560}
~~~

the fields we care about:

- `ts`: time of the first packet, unix seconds as a float.
- `uid`: zeek's id for this connection. it is a string, and it is *not* a linux user id. if the protocol logs are switched on, the same `uid` appears in `dns.log`, `http.log`, and so on, which is how you link them.
- `id.orig_h`, `id.orig_p`: who started the connection (originator), address and port. for anything the SPE reached out to, this is the VM's private address.
- `id.resp_h`, `id.resp_p`: who answered (responder). `443` here means HTTPS.
- `proto`: `tcp`, `udp`, or `icmp`.
- `duration`: seconds from first to last useful packet.
- `orig_bytes`, `resp_bytes`: payload bytes each side sent. for TCP these come from sequence numbers, so they can be slightly off on very large transfers.
- `conn_state`: how the connection ended, see below.
- `orig_pkts`, `resp_pkts`, `orig_ip_bytes`, `resp_ip_bytes`: packet counts and bytes as seen on the wire, headers included.

the field names have dots in them, so in `jq` they need quoting: `.["id.resp_h"]`.

`conn_state` in plain words:

| value | meaning |
|---|---|
| `SF` | normal: established and closed properly |
| `S0` | attempt seen, nobody answered. typical for internet-off mode, where outbound packets are dropped |
| `REJ` | attempt rejected by the other side |
| `S1` | established, never saw it close (zeek was still watching when it stopped) |
| `S2`, `S3` | established, one side tried to close, the other never replied |
| `RSTO`, `RSTR` | established, then aborted with a reset by the originator (`RSTO`) or the responder (`RSTR`) |
| `RSTOS0`, `RSTRH`, `SH`, `SHR` | half-open oddities: a SYN followed by a reset or a FIN without the handshake ever completing |
| `OTH` | zeek joined midstream, never saw the start |

a zero in the byte counts is not an error by itself, it is what a rejected or unanswered attempt looks like.

one line you will always see: the heartbeat agent checks the internet every interval with a TCP handshake to `1.1.1.1:443` (then `8.8.8.8:443` if that fails), so expect one such connection per heartbeat, `SF` with the internet on and `S0` with it off. that is the SPE checking on itself, not a researcher.

# reading it

~~~bash
sudo -u spe-netaudit /opt/zeek/bin/zeekctl status              # is the node running
sudo journalctl -u zeek -n 5                                    # which interface was picked
sudo tail -n 5 /var/log/spe-audit/network.jsonl | jq .          # live log, this hour
sudo ls /var/log/spe-audit                                      # current/ plus one dir per day
sudo zcat /var/log/spe-audit/*/network.*.log.gz | jq -r '[(.ts|todate), .["id.resp_h"], .["id.resp_p"], .conn_state] | @tsv'
~~~

zeek only knows addresses and ports. it does not know which process or which user made the connection, and it logs IPs, not hostnames. matching a connection to a command is done by time against the auditd log, which is what [AUDIT-LOG-GUIDE.md](../AUDIT-LOG-GUIDE.md) walks through. how the whole thing is wired, rotated, and what an exporter must handle is in [TELEMETRY-PIPELINE-GUIDE.md](../TELEMETRY-PIPELINE-GUIDE.md).
