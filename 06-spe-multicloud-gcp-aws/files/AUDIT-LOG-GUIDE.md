# How to read the SPE audit logs

This guide explains how to connect the audit records with the people, commands,
applications, and network connections inside the SPE.

The two files to inspect are:

```text
/var/log/spe-audit/os.jsonl       Linux login and command-line events
/var/log/spe-audit/network.jsonl  Zeek network connection summaries
```

Each line is one complete JSON object. Use the `terraform` administrator and
`sudo` to read them. The `speuser` researcher cannot change them.

```bash
sudo tail -n 10 /var/log/spe-audit/os.jsonl | jq .
sudo tail -n 10 /var/log/spe-audit/network.jsonl | jq .
```

## Think of the logs as two witnesses

The operating-system log knows about users, sessions, terminal input, and
programs. The network log knows about connections, addresses, ports, and byte
counts.

They observe the same SPE from different places. They do not share a common
event ID. I can put their observations next to each other by time, but this
proof of concept cannot prove that one particular process created one
particular network connection.

## Important operating-system fields

Laurel gives every Linux Audit event an `ID` similar to:

```text
1787762101.420:966
```

- `1787762101.420` is the event time as Unix time.
- `966` is Linux Audit's serial number for the event.
- The whole `ID` identifies one audit event. It is not a login session ID.

An event normally has a section named after its type, such as `USER_START`,
`TTY`, or `EXECVE`. Common fields inside that section are:

- `uid` or `UID`: the account under which the process is currently running.
- `auid` or `AUID`: the audit login identity. It normally stays with the
  activity even after `sudo` changes the effective user.
- `ses`: the audit session number. This is useful for grouping activity from
  one login session.
- `pid`: the process ID.
- `ppid`: the parent process ID.
- `comm`: the short process name.
- `exe`: the executable path reported for the audited operation.
- `acct`: the account involved in a PAM login or credential operation.
- `terminal`: where the session came from, such as `ssh`, a pseudo-terminal,
  `cron`, or the graphical login service.
- `res`: whether the operation succeeded or failed.

Laurel may also add an uppercase `PID` object. It enriches the numeric process
ID with details such as `START_TIME`, `comm`, `exe`, and `ppid`. The numeric
`pid` is the value in the original event; the `PID` object helps explain which
process that number represented.

The process ID can eventually be reused by Linux. When comparing old events,
use `PID.START_TIME` with the PID instead of relying on the PID alone.

## Reading login and logout activity

Useful event types include:

- `USER_AUTH`: an authentication attempt.
- `USER_LOGIN`: a login recorded by a login program.
- `USER_START`: a PAM session was opened.
- `USER_END`: a PAM session was closed.
- `USER_LOGOUT`: a logout recorded by a login program.
- `CRED_ACQ` or `CRED_REFR`: credentials were acquired or refreshed.
- `CRED_DISP`: credentials were discarded when they were no longer needed.

Different login programs do not always produce every event type. Do not expect
one `USER_LOGIN` and one `USER_LOGOUT` for every session. Match the account,
`ses`, executable, terminal, process IDs, and nearby timestamps.

Show the session-related events with:

```bash
sudo jq -c '
  select(
    .USER_AUTH or .USER_LOGIN or .USER_START or .USER_END or .USER_LOGOUT or
    .CRED_ACQ or .CRED_REFR or .CRED_DISP
  )
' /var/log/spe-audit/os.jsonl
```

### Interpreting the cron example

The example containing these values is not a person logging in as root:

```text
acct="root"
exe="/usr/sbin/cron"
terminal=cron
uid=0
auid=0
res=success
```

It is an automatic root cron session:

1. `CRED_REFR` says cron set or refreshed the credentials used by its job.
2. PID `2292` is a child shell. Laurel identifies it as `sh`, executing
   `/usr/bin/dash`, with parent PID `2291`.
3. `CRED_DISP` says cron discarded the credentials when the work ended.
4. `USER_END` says PAM closed the cron session.
5. PID `2291` is `cron`, and its parent PID `945` is the long-running cron
   service.

The three timestamps are only a few milliseconds apart, and the process
relationships agree. `terminal=cron` and `exe=/usr/sbin/cron` are the clearest
clues that this is scheduled system work rather than an interactive root
login. Background services can create login-style PAM events, so always check
the terminal and executable before deciding that a human was involved.

## Reading terminal commands and program execution

There are two complementary records.

### `TTY`: what the person typed

`pam_tty_audit` records interactive terminal input in `TTY.data`. This is how
the audit captures shell built-ins such as:

```bash
cd ~/spe-data-lab
```

`cd` changes the state of the existing shell; it does not start another
program. Therefore, I expect a `TTY` record but no separate `EXECVE` record for
`cd`.

```bash
sudo jq -c 'select(.TTY) | {
  ID,
  AUID: .TTY.AUID,
  UID: .TTY.UID,
  session: .TTY.ses,
  pid: .TTY.pid,
  input: .TTY.data
}' /var/log/spe-audit/os.jsonl
```

Terminal input may include corrections, control characters, or several short
pieces rather than one perfectly formatted command. It records input, not the
terminal output or a replayable desktop session.

### `EXECVE`: which external program Linux started

`EXECVE.ARGV` contains the executable arguments supplied to Linux. For:

```bash
python3 --version
```

I expect an argument array similar to:

```json
["python3", "--version"]
```

```bash
sudo jq -c 'select(.EXECVE) | {
  ID,
  AUID: .SYSCALL.AUID,
  UID: .SYSCALL.UID,
  session: .SYSCALL.ses,
  pid: .SYSCALL.pid,
  executable: .SYSCALL.exe,
  arguments: .EXECVE.ARGV
}' /var/log/spe-audit/os.jsonl
```

Use the nearby time, audit session, audit user, PID, and parent PID to match a
`TTY` command with its `EXECVE` event. The text the person typed and the final
argument array may differ because the shell expands variables, wildcards, and
quoted text before starting the program.

For example, the desktop launchers in this exercise can produce process trails
like these:

```text
SPE JupyterLab launcher
  /usr/local/bin/spe-jupyter
  /opt/spe-python/bin/jupyter lab
  Python and browser child processes

SPE RStudio Data Lab launcher
  rstudio --disable-gpu .../spe-data-lab.Rproj
  RStudio helper and R child processes
```

One click can start several processes. Group close timestamps and follow parent
process IDs before treating them as separate user actions.

## Reading network connections

Each line in `network.jsonl` summarizes one connection. Important fields are:

- `ts`: connection start time as Unix time.
- `uid`: Zeek's unique connection ID. This is not a Linux user ID.
- `id.orig_h` and `id.orig_p`: address and port of the connection initiator.
- `id.resp_h` and `id.resp_p`: address and port of the responder.
- `proto`: usually `tcp`, `udp`, or `icmp`.
- `duration`: observed connection lifetime in seconds.
- `conn_state`: Zeek's summary of how the connection ended.
- `orig_bytes` and `resp_bytes`: payload bytes sent by each side.
- `orig_pkts` and `resp_pkts`: packets observed from each side.
- `orig_ip_bytes` and `resp_ip_bytes`: IP-level bytes, including headers.

For a normal outbound HTTPS request from the SPE, `id.orig_h` is normally the
SPE's private address, `id.resp_h` is the remote address, and `id.resp_p` is
`443`.

Common connection states in this lesson are:

- `SF`: a TCP connection was established and closed normally.
- `S0`: a connection attempt was sent, but no reply was observed.
- `REJ`: the destination rejected the attempt.
- `RSTO`: the originator reset the connection.
- `RSTR`: the responder reset the connection.
- `OTH`: Zeek observed a connection that did not fit a usual TCP sequence.

A zero byte count is not automatically an error. It can represent a rejected
attempt, an incomplete observation, or a connection that did not transfer
application payload.

Create a readable network timeline with:

```bash
sudo jq -r '[
  (.ts | strftime("%Y-%m-%dT%H:%M:%SZ")),
  .uid,
  ([.["id.orig_h"], .["id.orig_p"]] | map(tostring) | join(":")),
  ([.["id.resp_h"], .["id.resp_p"]] | map(tostring) | join(":")),
  .proto,
  .conn_state,
  .orig_bytes,
  .resp_bytes
] | @tsv' /var/log/spe-audit/network.jsonl
```

Zeek normally writes the final summary after a connection closes or expires.
A connection may therefore appear a little after its related command.

## A simple matching exercise

Use a distinctive command and a short time window:

```bash
date -u +%Y-%m-%dT%H:%M:%SZ
/usr/bin/printf 'audit-lab-001\n'
python3 --version
curl --head --connect-timeout 5 https://example.com
date -u +%Y-%m-%dT%H:%M:%SZ
```

Then inspect the logs as the administrator:

```bash
sudo jq -c 'select(.TTY)' /var/log/spe-audit/os.jsonl | tail -n 10
sudo jq -c 'select(.EXECVE)' /var/log/spe-audit/os.jsonl | tail -n 20
sudo tail -n 20 /var/log/spe-audit/network.jsonl | jq .
```

I should be able to build the following explanation:

1. The login records identify the researcher and audit session.
2. `TTY.data` shows the commands typed in that terminal.
3. `EXECVE.ARGV` shows `/usr/bin/printf`, `python3`, `curl`, and their
   arguments. The shell built-in `cd`, if used, appears only in the TTY input.
4. A nearby network record shows an outbound connection to port `443`.
5. The logout records close the researcher's session.

This is a strong timeline, but the final step remains a time-based inference.
This Zeek configuration does not record the Linux PID, process name, or user
that owns a connection. It also records IP addresses rather than DNS names and
does not inspect encrypted HTTPS contents.

## Password and security warning

The configuration deliberately does not enable `log_passwd`, so input entered
while the terminal has echo disabled is not intentionally recorded. Some
nested or unusual password prompts may still behave differently. Do not type
real secrets in this learning environment.

These logs are protected from the normal researcher, but a root administrator
can change or delete them. Deleting the VM disk also deletes the evidence. A
production SPE would send audit records to protected storage outside the VM.
