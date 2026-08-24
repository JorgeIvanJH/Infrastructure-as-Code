#!/usr/bin/env python3

import json
import os
import time
from datetime import datetime, timezone


DEFAULT_SPE_ID = "spe-demo-001"
HEARTBEAT_INTERVAL_SECONDS = 30
MESSAGE = "SPE monitoring agent is alive"


def create_heartbeat() -> dict[str, str]:
    """Create one heartbeat using the current UTC time."""
    return {
        "spe_id": os.getenv("SPE_ID", DEFAULT_SPE_ID),
        "timestamp": datetime.now(timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z"),
        "message": MESSAGE,
    }


def main() -> None:
    while True:
        print(json.dumps(create_heartbeat(), separators=(",", ":")), flush=True)
        time.sleep(HEARTBEAT_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
