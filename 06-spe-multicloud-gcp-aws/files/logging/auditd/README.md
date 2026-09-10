auditd is the linux native auditing framework. it has two halves: the kernel decides what to record, and the auditd daemon writes it down.

the kernel generates an event whenever one of three things happens:

- a rule we loaded matches. our rules live in [50-spe.rules](50-spe.rules) and record every program a human starts (`execve`), for 64-bit and 32-bit binaries. the `50` prefix is the upstream slot for "server specific rules"; `augenrules` only picks up files ending in `.rules` and merges them in numeric order into `/etc/audit/audit.rules`.
- a program like `sshd`, `sudo`, or `xrdp` opens or closes a session through PAM. these login, logout, and credential events (`USER_LOGIN`, `USER_START`, `USER_END`, `CRED_ACQ`, ...) are hard-wired: they are always sent when auditing is on, so no rule is needed for them.
- a terminal session has TTY auditing switched on. [spe-tty-audit](spe-tty-audit) does that for every session PAM opens, including root shells reached through `sudo`, so what users type or paste into a terminal is recorded, shell built-ins like `cd` included. `log_passwd` is left out, so anything typed while echo is off (password prompts) is not captured.

then these events are sent to auditd, the writer, which stores them in a physical file, `/var/log/audit/audit.log`, in a raw text format we can parse (more on that below). how that file behaves is configured in [auditd.conf](auditd.conf), a copy of the stock ubuntu 24.04 file where we changed three keys: rotate at 10 MB (`max_log_file`), keep 5 files (`num_logs`), and rotate instead of stopping when the limit is reached (`max_log_file_action = ROTATE`). everything else, including `log_format = ENRICHED` and `log_group = root`, is the distribution default.

~~~mermaid
flowchart LR
    subgraph triggers["what makes the kernel record something"]
        R["50-spe.rules<br>a human runs a program (execve)"]
        P["PAM session events<br>login, logout, sudo, cron<br>always on, no rule needed"]
        T["spe-tty-audit<br>keystrokes in a terminal"]
    end
    K["kernel audit subsystem<br>decides what to record"]
    A["auditd daemon<br>writes it down"]
    C["auditd.conf<br>10 MB x 5 files, ROTATE, ENRICHED"]
    L["/var/log/audit/audit.log<br>raw text, several lines per event<br>0600 root:root"]
    S["ausearch / aureport<br>group the lines, decode the hex"]
    R --> K
    P --> K
    T --> K
    K -- "netlink socket" --> A
    C -. "configures" .-> A
    A --> L
    L --> S
~~~

# where each file lands on the VM

| here | on the VM | installed by |
|---|---|---|
| `50-spe.rules` | `/etc/audit/rules.d/50-spe.rules` | [setup-auditing.sh](../../../scripts/setup-auditing.sh) |
| `spe-tty-audit` | `/etc/pam.d/spe-tty-audit`, included from `/etc/pam.d/common-session` | same |
| `auditd.conf` | `/etc/audit/auditd.conf` | same |

the file names are the same here and on the VM on purpose, so a `grep` in either place finds the other.

# most relevant raw auditd outputs

one action produces several lines. they all share the same `msg=audit(time:serial)` stamp, and that stamp is what groups them into one event. `time` is unix seconds with milliseconds, `serial` restarts at every boot.

~~~mermaid
flowchart TB
    E["speuser types<br>python3 --version"]
    E --> S1["type=SYSCALL<br>who, which syscall, key=spe_cli"]
    E --> S2["type=EXECVE<br>a0=python3 a1=--version"]
    E --> S3["type=CWD<br>where it ran"]
    E --> S4["type=PATH<br>which binary"]
    E --> S5["type=PROCTITLE<br>command line, hex"]
    S1 --> G["one event<br>msg=audit(1787762101.420:966)"]
    S2 --> G
    S3 --> G
    S4 --> G
    S5 --> G
~~~

this is what `python3 --version` typed by `speuser` looks like, trimmed for width:

~~~text
type=SYSCALL   msg=audit(1787762101.420:966): arch=c000003e syscall=59 success=yes exit=0 ppid=4300 pid=4321 auid=1001 uid=1001 tty=pts0 ses=3 comm="python3" exe="/usr/bin/python3.12" key="spe_cli"  ARCH=x86_64 SYSCALL=execve AUID="speuser" UID="speuser"
type=EXECVE    msg=audit(1787762101.420:966): argc=2 a0="python3" a1="--version"
type=CWD       msg=audit(1787762101.420:966): cwd="/home/speuser/spe-data-lab"
type=PATH      msg=audit(1787762101.420:966): item=0 name="/usr/bin/python3" mode=0100755 ouid=0 ogid=0
type=PROCTITLE msg=audit(1787762101.420:966): proctitle=707974686F6E33002D2D76657273696F6E
~~~

the fields we care about:

- `type`: which kind of line this is. `SYSCALL` carries who and what, `EXECVE` the arguments, `CWD` the directory, `PATH` the binary, `PROCTITLE` the command line hex-encoded.
- `auid` / `AUID`: the login identity. it survives `sudo`, so a root shell still says which human logged in.
- `uid` / `UID`: the account the process is running as right now.
- `ses`: the login session number, handy to group everything one person did in one session.
- `pid` / `ppid`: the process and its parent.
- `exe`, `comm`: the binary path and its short name.
- `key`: the tag from our rule, `spe_cli`, which is what `ausearch -k spe_cli` filters on.
- `a0`, `a1`, ...: the arguments, one field each. there is no array.
- the uppercase fields at the end (`AUID="speuser"`, `SYSCALL=execve`) are the `ENRICHED` translations of the numeric ones. they sit after a `0x1D` control character on the same line.

a login looks different because it comes from PAM, not from a rule. one line, and the interesting part is inside `msg='...'`:

~~~text
type=USER_START msg=audit(1787762050.101:940): pid=4210 uid=0 auid=1001 ses=3 msg='op=PAM:session_open acct="speuser" exe="/usr/sbin/sshd" hostname=203.0.113.10 addr=203.0.113.10 terminal=ssh res=success'  UID="root" AUID="speuser"
~~~

here `acct` is who logged in, `exe` and `terminal` say through what (`sshd` over `ssh`, `cron` for a scheduled job, `xrdp-sesman` for the desktop), and `res` whether it worked.

and keystrokes are `TTY` lines with the typed bytes hex-encoded in `data`:

~~~text
type=TTY msg=audit(1787762110.330:951): tty pid=4321 uid=1001 auid=1001 ses=3 major=136 minor=0 comm="bash" data=6364207E2F7370652D646174612D6C61620A
~~~

# reading it

don't parse the file by hand. `ausearch` groups the lines of an event and, with `-i`, decodes the hex and resolves the numbers into names:

~~~bash
sudo ausearch -k spe_cli -i --start recent     # commands humans ran
sudo aureport -l -i --start recent             # logins
sudo aureport --tty -i --start recent          # what was typed
~~~

the file is `0600 root:root`, so all of this needs `sudo`.