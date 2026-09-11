#!/usr/bin/env python3
"""Print one JSON document per interval with everything the SPE recorded.

Every SPE_HEARTBEAT_INTERVAL seconds the agent prints one JSON object: who the
SPE is, whether the internet is reachable, every auditd event since the previous
document under "os", and every Zeek connection since the previous document under
"net". For now the document goes to stdout, which systemd stores in the journal.
Sending it to a collector outside the SPE is the next step.

Nothing about a particular SPE lives in this file. SPE_ID and
SPE_HEARTBEAT_INTERVAL arrive through the environment, written at boot by
spe-identity from the values Terraform attached to the instance.

The agent remembers where it stopped in its state directory, so a restart or a
reboot neither repeats nor skips a record:

  sequence          number of the last document printed
  audit.checkpoint  ausearch's own bookmark into /var/log/audit
  zeek.cursor       which live Zeek file, how far into it, and the newest
                    archive already read

Bookmarks move only after the document has been printed. Run with --once to
print a single document without moving any bookmark: that is how the image build
proves the agent works, and how to peek at a running SPE by hand.
"""

import argparse
import gzip
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path


MINIMUM_INTERVAL_SECONDS = 5
# Two anycast addresses, so one provider having a bad day does not read as a
# sealed SPE. Port 443 is what the SPE's own HTTPS traffic would use.
INTERNET_PROBES = (("1.1.1.1", 443), ("8.8.8.8", 443))
PROBE_TIMEOUT_SECONDS = 2

BOOT_ID_FILE = Path("/proc/sys/kernel/random/boot_id")
DEFAULT_STATE_DIRECTORY = Path("/var/lib/spe-monitoring-agent")

# auditd. ausearch reads the log files named in auditd.conf, follows their
# rotation, and keeps a bookmark (the checkpoint) so each event is seen once.
AUSEARCH = "ausearch"
CHECKPOINT_BROKEN_EXIT_CODES = (10, 11, 12)
STAMP = re.compile(r"msg=audit\((\d+\.\d+):(\d+)\)")
TOKEN = re.compile(r"""([A-Za-z0-9_-]+)=("[^"]*"|'[^']*'|\S+)""")
HEX = re.compile(r"[0-9A-F]+")
ARGUMENT = re.compile(r"a\d+")
COMMAND_KEY = "spe_cli"
SESSION_TYPES = {"USER_LOGIN", "USER_AUTH", "USER_START", "USER_END"}

# Zeek. The live file is rotated every hour into a dated, gzipped archive.
ZEEK_LIVE_LOG = Path("/var/log/spe-audit/current/network.log")
ZEEK_ARCHIVES = Path("/var/log/spe-audit")
ZEEK_ARCHIVE_PATTERN = "*/network.*.log.gz"
ROTATION_WAIT_LIMIT = 3
ZEEK_FIELDS = {
    "ts": "time",
    "id.orig_h": "src_ip",
    "id.orig_p": "src_port",
    "id.resp_h": "dst_ip",
    "id.resp_p": "dst_port",
    "proto": "proto",
    "duration": "duration",
    "orig_bytes": "bytes_out",
    "resp_bytes": "bytes_in",
    "conn_state": "state",
}
EMPTY_CURSOR = {"inode": None, "offset": 0, "archive_mtime": 0.0, "rotation_waits": 0}


def log(message: str) -> None:
    """Operational messages go to stderr, which systemd stores in the journal."""
    print(message, file=sys.stderr, flush=True)


def required_setting(name: str) -> str:
    """Return an environment value, or stop with a message systemd will show."""
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(
            f"{name} is not set. spe-identity writes it to /etc/spe/identity.env "
            "from the instance metadata Terraform attached."
        )
    return value


def probe_internet() -> str:
    """Report the wire: reachable if one handshake completes, blocked otherwise."""
    for host, port in INTERNET_PROBES:
        try:
            with socket.create_connection((host, port), timeout=PROBE_TIMEOUT_SECONDS):
                return "reachable"
        except OSError:
            continue
    return "blocked"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


# --- state -------------------------------------------------------------------


def read_json(path: Path, default):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, ValueError):
        return default


def write_atomic(path: Path, text: str) -> None:
    """Write through a temporary file so a crash never leaves a half-written state."""
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text)
    temporary.replace(path)


# --- os: auditd events -------------------------------------------------------


def field(fields: dict[str, str], key: str) -> str | None:
    """Return one auditd value as text: quotes removed, hex decoded, or None."""
    raw = fields.get(key)
    if raw is None:
        return None
    if raw[:1] in "\"'":
        return raw[1:-1]
    if len(raw) % 2 == 0 and HEX.fullmatch(raw):
        return bytes.fromhex(raw).decode("utf-8", errors="replace")
    return raw


def number(fields: dict[str, str], key: str) -> int | None:
    raw = fields.get(key)
    try:
        return int(raw)
    except (TypeError, ValueError):
        return None


def parse_line(line: str) -> dict[str, str]:
    """Turn one raw auditd line into key=value pairs, ENRICHED names included.

    PAM events carry a second set of pairs inside msg='...'; those are merged in
    and win over the outer ones, since they describe the session itself.
    """
    fields: dict[str, str] = {}
    for key, value in TOKEN.findall(line.replace("\x1d", " ")):
        fields.setdefault(key, value)
        if value.startswith("'"):
            for inner_key, inner_value in TOKEN.findall(value[1:-1]):
                fields[inner_key] = inner_value
    return fields


def group_events(raw_output: str) -> list[dict[str, dict[str, str]]]:
    """Group raw lines by their msg=audit(time:serial) stamp, one dict per event."""
    events: dict[tuple[float, int], dict] = {}
    # Not splitlines(): it would also split on the 0x1D byte that separates the
    # ENRICHED names from the rest of the line.
    for line in raw_output.split("\n"):
        stamp = STAMP.search(line)
        if not stamp:
            continue
        key = (float(stamp.group(1)), int(stamp.group(2)))
        event = events.setdefault(key, {"time": key[0], "serial": key[1], "records": {}})
        fields = parse_line(line)
        record_type = fields.get("type")
        if record_type and record_type not in event["records"]:
            event["records"][record_type] = fields
    return list(events.values())


def shape_event(event: dict) -> dict | None:
    """Keep the essential fields of a command, session, or tty event; drop the rest."""
    records = event["records"]
    if "SYSCALL" in records and field(records["SYSCALL"], "key") == COMMAND_KEY:
        kind, source = "command", records["SYSCALL"]
    elif "TTY" in records:
        kind, source = "tty", records["TTY"]
    else:
        session_type = next((t for t in records if t in SESSION_TYPES), None)
        if session_type is None:
            return None
        kind, source = "session", records[session_type]

    shaped = {
        "time": event["time"],
        "serial": event["serial"],
        "kind": kind,
        "ses": number(source, "ses"),
        # ENRICHED names first; the numeric id only if the name is missing.
        "auid": field(source, "AUID") or source.get("auid"),
        "uid": field(source, "UID") or source.get("uid"),
        "pid": number(source, "pid"),
    }
    if kind == "command":
        execve = records.get("EXECVE", {})
        argument_keys = sorted((k for k in execve if ARGUMENT.fullmatch(k)), key=lambda k: int(k[1:]))
        shaped.update(
            exe=field(source, "exe"),
            args=[field(execve, k) for k in argument_keys],
            cwd=field(records.get("CWD", {}), "cwd"),
            success=field(source, "success") == "yes",
        )
    elif kind == "session":
        shaped.update(
            event=source.get("type"),
            acct=field(source, "acct"),
            exe=field(source, "exe"),
            terminal=field(source, "terminal"),
            addr=field(source, "addr"),
            res=field(source, "res"),
        )
    else:
        shaped.update(comm=field(source, "comm"), data=field(source, "data"))
    return shaped


def read_os_events(checkpoint: Path, next_checkpoint: Path, retry: bool = True) -> list[dict]:
    """Ask ausearch for every event after the bookmark; the new bookmark lands in next_checkpoint.

    The real checkpoint is copied first and only replaced by the caller once the
    document is out, so a crash in between repeats events rather than losing them.
    """
    command = [AUSEARCH, "--input-logs", "--raw", "--checkpoint", str(next_checkpoint)]
    if checkpoint.exists():
        shutil.copyfile(checkpoint, next_checkpoint)
    else:
        next_checkpoint.unlink(missing_ok=True)
        command += ["--start", "boot"]
    result = subprocess.run(command, capture_output=True, text=True, errors="replace")
    if result.returncode in CHECKPOINT_BROKEN_EXIT_CODES and retry:
        log(f"ausearch could not use its checkpoint (exit {result.returncode}); starting again from this boot")
        checkpoint.unlink(missing_ok=True)
        return read_os_events(checkpoint, next_checkpoint, retry=False)
    if result.returncode not in (0, 1):  # 1 means no new events
        raise RuntimeError(f"ausearch failed (exit {result.returncode}): {result.stderr.strip()}")
    return [shaped for shaped in map(shape_event, group_events(result.stdout)) if shaped]


# --- net: zeek connections ---------------------------------------------------


def shape_connection(line: str) -> dict:
    record = json.loads(line)
    return {new: record[old] for old, new in ZEEK_FIELDS.items() if old in record}


def read_net_connections(cursor: dict) -> tuple[list[dict], dict]:
    """Return the new Zeek lines and the moved cursor. Writes nothing.

    The live file is read from the saved offset, whole lines only. When it has
    been rotated (new inode, or shorter than the offset), the rest of the old
    file is read from the gzipped archive Zeek moved it to, then the new live
    file starts at zero. The archive can take a few seconds to appear, so the
    agent waits a few intervals for it before giving up on that tail.
    """
    cursor = {**EMPTY_CURSOR, **cursor}
    moved = dict(cursor)
    lines: list[str] = []
    try:
        live = ZEEK_LIVE_LOG.stat()
        live_inode, live_size = live.st_ino, live.st_size
    except FileNotFoundError:
        live_inode, live_size = None, 0

    first_run = cursor["inode"] is None
    rotated = not first_run and (live_inode != cursor["inode"] or live_size < cursor["offset"])
    if first_run or rotated:
        archives = [p for p in ZEEK_ARCHIVES.glob(ZEEK_ARCHIVE_PATTERN) if p.stat().st_mtime > cursor["archive_mtime"]]
        archives.sort(key=lambda p: p.stat().st_mtime)
        if rotated and not archives and cursor["rotation_waits"] < ROTATION_WAIT_LIMIT:
            moved["rotation_waits"] += 1
            return [], moved
        if rotated and not archives:
            log(f"zeek archive of the rotated live file never appeared; {cursor['offset']} bytes were read from it")
        offset = cursor["offset"] if rotated else 0
        for archive in archives:
            with gzip.open(archive, "rb") as handle:
                lines += handle.read()[offset:].decode("utf-8", errors="replace").split("\n")
            offset = 0
            moved["archive_mtime"] = archive.stat().st_mtime
        moved["offset"] = 0
        moved["rotation_waits"] = 0

    moved["inode"] = live_inode
    if live_inode is not None:
        with ZEEK_LIVE_LOG.open("rb") as handle:
            handle.seek(moved["offset"])
            chunk = handle.read()
        complete = chunk.rfind(b"\n") + 1
        lines += chunk[:complete].decode("utf-8", errors="replace").split("\n")
        moved["offset"] += complete
    return [shape_connection(line) for line in lines if line.strip()], moved


# --- the document ------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--once", action="store_true", help="print one document and exit without moving any bookmark")
    once = parser.parse_args().once

    spe_id = required_setting("SPE_ID")
    interval_text = required_setting("SPE_HEARTBEAT_INTERVAL")
    try:
        interval = int(interval_text)
    except ValueError:
        sys.exit(f"SPE_HEARTBEAT_INTERVAL must be a whole number of seconds, not {interval_text!r}.")
    if interval < MINIMUM_INTERVAL_SECONDS:
        sys.exit(f"SPE_HEARTBEAT_INTERVAL must be at least {MINIMUM_INTERVAL_SECONDS}, not {interval}.")

    # --once must not touch the real state, so its new bookmark goes to a scratch
    # directory, and so does everything else when no state exists yet.
    scratch = Path(tempfile.mkdtemp(prefix="spe-monitoring-agent.")) if once else None
    state_directory = Path(os.environ.get("STATE_DIRECTORY", DEFAULT_STATE_DIRECTORY))
    if not state_directory.is_dir():
        if not once:
            sys.exit(f"{state_directory} does not exist. The unit's StateDirectory= creates it.")
        state_directory = scratch
    sequence_file = state_directory / "sequence"
    checkpoint = state_directory / "audit.checkpoint"
    cursor_file = state_directory / "zeek.cursor"
    next_checkpoint = (scratch or state_directory) / "audit.checkpoint.next"

    boot_id = BOOT_ID_FILE.read_text().strip()
    sequence = read_json(sequence_file, 0)
    cursor = read_json(cursor_file, EMPTY_CURSOR)

    while True:
        os_events = read_os_events(checkpoint, next_checkpoint)
        net_connections, cursor = read_net_connections(cursor)
        sequence += 1
        document = {
            "spe_id": spe_id,
            "boot_id": boot_id,
            "sequence": sequence,
            "timestamp": utc_now(),
            "internet": probe_internet(),
            "os": os_events,
            "net": net_connections,
        }
        print(json.dumps(document, separators=(",", ":")), flush=True)
        if once:
            shutil.rmtree(scratch, ignore_errors=True)
            return
        # The document is out: move the bookmarks.
        if next_checkpoint.exists():
            next_checkpoint.replace(checkpoint)
        write_atomic(cursor_file, json.dumps(cursor))
        write_atomic(sequence_file, json.dumps(sequence))
        time.sleep(interval)


if __name__ == "__main__":
    main()
