#!/usr/bin/env python3
"""Nightly consolidation drain for the jarvis hindsight stack.

Auto-consolidation is disabled on the server (HINDSIGHT_API_ENABLE_AUTO_CONSOLIDATION=false),
so retains queue consolidation work as pending_consolidation. This script triggers
POST /v1/default/banks/{bank}/consolidate for every bank that has pending work and
waits until the queues drain.

Scheduled as a hermes cronjob (daily 03:00). Stdlib only.
"""

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "http://127.0.0.1:8888"
TOKEN_FILE = Path.home() / ".hindsight" / "coding-agent.json"
POLL_SECONDS = 30
# Worker pool is serialised (WORKER_MAX_SLOTS=1), so banks drain one task at a
# time. 90 minutes is generous for a full day of queued consolidation.
TOTAL_BUDGET_SECONDS = 90 * 60


def api(method: str, path: str, token: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(
        f"{BASE}{path}",
        method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        data=json.dumps(body).encode() if body is not None else None,
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def main() -> int:
    token = json.loads(TOKEN_FILE.read_text())["apiToken"]
    banks = [b["bank_id"] for b in api("GET", "/v1/default/banks", token).get("banks", [])]
    deadline = time.monotonic() + TOTAL_BUDGET_SECONDS

    pending: dict[str, int] = {}
    for bank in banks:
        enc = urllib.parse.quote(bank, safe="")
        stats = api("GET", f"/v1/default/banks/{enc}/stats", token)
        n = int(stats.get("pending_consolidation", 0))
        if n > 0:
            pending[bank] = n

    if not pending:
        # Silent on idle — the cron job delivers stdout verbatim, so an empty
        # day sends no message.
        return 0

    print(f"drain: triggering consolidation for {len(pending)} banks: "
          + ", ".join(f"{b}={n}" for b, n in sorted(pending.items())))

    triggered = []
    for bank in sorted(pending):
        enc = urllib.parse.quote(bank, safe="")
        try:
            api("POST", f"/v1/default/banks/{enc}/consolidate", token, {})
            triggered.append(bank)
            print(f"  triggered: {bank}")
        except urllib.error.HTTPError as exc:
            print(f"  FAILED to trigger {bank}: HTTP {exc.code} {exc.read().decode(errors='replace')[:200]}")

    # Poll until every triggered bank reports 0 pending (consolidation rounds
    # may re-queue; keep waiting until drained or budget exhausted).
    remaining = set(triggered)
    while remaining and time.monotonic() < deadline:
        time.sleep(POLL_SECONDS)
        for bank in sorted(remaining):
            enc = urllib.parse.quote(bank, safe="")
            stats = api("GET", f"/v1/default/banks/{enc}/stats", token)
            n = int(stats.get("pending_consolidation", 0))
            if n == 0:
                remaining.discard(bank)
                print(f"  drained: {bank}")
            else:
                print(f"  working: {bank} ({n} pending)")

    if remaining:
        print(f"drain: BUDGET EXHAUSTED, still pending: {sorted(remaining)}")
        return 1
    print("drain: complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
