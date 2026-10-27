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
from datetime import datetime, timedelta, timezone
from pathlib import Path

BASE = "http://127.0.0.1:8888"
TOKEN_FILE = Path.home() / ".hindsight" / "coding-agent.json"
POLL_SECONDS = 30
# Self-terminate at 50min: the hermes cron harness kills scripts at 3600s, and a
# kill swallows stdout — an early, reported exit beats a silent strangling.
TOTAL_BUDGET_SECONDS = 50 * 60
# A bank whose pending_consolidation count does not move for this many polls is
# not "slow", it is stalled: a live op updates progress (and the count drains).
STALL_POLLS = 10  # 10 * 30s
# Processing ops whose updated_at is older than this are zombies: a claimed task
# whose worker died. The poller never reclaims other workers' tasks by design.
STALE_MINUTES = 15


def api(method: str, path: str, token: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(
        f"{BASE}{path}",
        method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        data=json.dumps(body).encode() if body is not None else None,
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def stale_processing_ops(token: str, bank: str) -> list[str]:
    """Report 'processing' ops in `bank` whose updated_at stopped advancing."""
    enc = urllib.parse.quote(bank, safe="")
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=STALE_MINUTES)
    out = []
    try:
        ops = api("GET", f"/v1/default/banks/{enc}/operations?status=processing&limit=100", token)
    except urllib.error.HTTPError as exc:
        return [f"  {bank}: could not list operations: HTTP {exc.code}"]
    for op in ops.get("operations", []):
        updated = op.get("updated_at")
        if not updated:
            continue
        try:
            ts = datetime.fromisoformat(updated)
        except ValueError:
            continue
        if ts < cutoff:
            age_h = (datetime.now(timezone.utc) - ts).total_seconds() / 3600
            stage = (op.get("progress") or {}).get("stage", "?")
            out.append(
                f"  {bank}: zombie op {op['operation_id']} type={op.get('operation_type')} "
                f"stage={stage} stuck {age_h:.1f}h at updated_at={updated} — release with: "
                f"curl -X DELETE -H \"Authorization: Bearer <token>\" "
                f"'{BASE}/v1/default/banks/{enc}/operations/{op['operation_id']}'"
            )
    return out


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
    # may re-queue; keep waiting until drained or budget exhausted). Abort early
    # if a bank stops making progress — that is a stalled/zombie claim, not a
    # slow LLM, and waiting longer only burns the budget (see 2026-10-25: three
    # nightly timeouts behind one zombie op frozen at 8/13 memories).
    remaining = set(triggered)
    last_counts: dict[str, int] = {}
    stall_polls: dict[str, int] = {}
    while remaining and time.monotonic() < deadline:
        time.sleep(POLL_SECONDS)
        for bank in sorted(remaining):
            enc = urllib.parse.quote(bank, safe="")
            stats = api("GET", f"/v1/default/banks/{enc}/stats", token)
            n = int(stats.get("pending_consolidation", 0))
            if n == 0:
                remaining.discard(bank)
                print(f"  drained: {bank}")
                continue
            if last_counts.get(bank) == n:
                stall_polls[bank] = stall_polls.get(bank, 0) + 1
            else:
                stall_polls[bank] = 0
            last_counts[bank] = n
            print(f"  working: {bank} ({n} pending)")
            if stall_polls[bank] >= STALL_POLLS:
                print(f"drain: STALLED — {bank} unchanged at {n} for "
                      f"{stall_polls[bank] * POLL_SECONDS // 60} min")
                for line in stale_processing_ops(token, bank):
                    print(line)
                return 2

    if remaining:
        print(f"drain: BUDGET EXHAUSTED, still pending: {sorted(remaining)}")
        for bank in sorted(remaining):
            for line in stale_processing_ops(token, bank):
                print(line)
        return 1
    print("drain: complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
