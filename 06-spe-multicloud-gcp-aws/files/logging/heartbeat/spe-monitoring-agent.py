#!/usr/bin/env python3
"""Print one JSON heartbeat per interval. systemd stores each line in the journal.

Nothing about a particular SPE lives in this file. SPE_ID and
SPE_HEARTBEAT_INTERVAL arrive through the environment, written at boot by
spe-identity from the values Terraform attached to the instance.

Each heartbeat also measures whether the internet is reachable, with a bare TCP
handshake to a stable public address: no request, no data, no DNS.
"""

import json
import os
import socket
import sys
import time
from datetime import datetime, timezone


MESSAGE = "SPE monitoring agent is alive"
MINIMUM_INTERVAL_SECONDS = 5
# Two anycast addresses, so one provider having a bad day does not read as a
# sealed SPE. Port 443 is what the SPE's own HTTPS traffic would use.
INTERNET_PROBES = (("1.1.1.1", 443), ("8.8.8.8", 443))
PROBE_TIMEOUT_SECONDS = 2


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


def create_heartbeat(spe_id: str) -> dict[str, str]:
    """Create one heartbeat using the current UTC time."""
    return {
        "spe_id": spe_id,
        "timestamp": datetime.now(timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z"),
        "message": MESSAGE,
        "internet": probe_internet(),
    }


def main() -> None:
    spe_id = required_setting("SPE_ID")
    interval_text = required_setting("SPE_HEARTBEAT_INTERVAL")
    try:
        interval = int(interval_text)
    except ValueError:
        sys.exit(f"SPE_HEARTBEAT_INTERVAL must be a whole number of seconds, not {interval_text!r}.")
    if interval < MINIMUM_INTERVAL_SECONDS:
        sys.exit(f"SPE_HEARTBEAT_INTERVAL must be at least {MINIMUM_INTERVAL_SECONDS}, not {interval}.")

    while True:
        print(json.dumps(create_heartbeat(spe_id), separators=(",", ":")), flush=True)
        time.sleep(interval)


if __name__ == "__main__":
    main()
