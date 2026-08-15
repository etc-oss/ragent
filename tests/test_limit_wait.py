#!/usr/bin/env python3
"""Rate-limit wait layer (ADR-0026) — detector precision + bounded wait/retry
mechanics, deterministic with a stub run_once (no LLM, no real sleeps). A real usage
limit can't be triggered on demand, so this proves the FAIL-SAFE classification and
the bound — not live detection.

    python3 tests/test_limit_wait.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))

from ragent import orchestrator as O  # noqa: E402


def test_detector():
    for s in ["You've hit your session limit · resets 3:45pm",
              "You've hit your weekly limit · resets Mon 12:00am",
              "spend limit reached (daily; resets 2026-08-09 00:00 UTC)",
              "Error: usage limit exceeded"]:
        assert O._detect_usage_limit(s), "should detect: %r" % s
    # FAIL-SAFE: a genuine error must NOT be mistaken for a limit (or it'd wait for days)
    for s in ["SyntaxError: invalid syntax", "fatal: network unreachable",
              "Killed (out of memory)", "OK", "", "the agent renamed a limit variable"]:
        assert not O._detect_usage_limit(s), "must NOT detect: %r" % s
    print("  ok: detector — matches limit phrases, ignores real errors")


def test_wait_retry_success():
    calls = {"n": 0}

    def run_once():
        calls["n"] += 1
        if calls["n"] <= 2:
            return 1, "You've hit your session limit · resets 3:45pm"
        return 0, "OK"

    idle = O._wait_out_limits(run_once, poll_sec=0, max_wait_hours=1)
    assert calls["n"] == 3, "retried until success (got %d runs)" % calls["n"]
    assert idle == 0.0, "poll_sec=0 → zero idle accrued"
    print("  ok: waits out a limit, then succeeds (3 runs)")


def test_wait_cap_needs_human():
    calls = {"n": 0}

    def run_once():
        calls["n"] += 1
        return 1, "spend limit reached"

    idle = O._wait_out_limits(run_once, poll_sec=0, max_wait_hours=0)  # cap trips at once
    assert calls["n"] == 1, "one attempt then cap (got %d)" % calls["n"]
    print("  ok: bounded — stops at the wait cap (needs-human), no infinite loop")


def test_real_error_not_retried():
    calls = {"n": 0}

    def run_once():
        calls["n"] += 1
        return 1, "fatal: could not read from remote"

    idle = O._wait_out_limits(run_once, poll_sec=0, max_wait_hours=99)
    assert calls["n"] == 1, "a real error surfaces without retry (got %d)" % calls["n"]
    assert idle == 0.0
    print("  ok: fail-safe — a real error is not mistaken for a limit")


def main():
    test_detector()
    test_wait_retry_success()
    test_wait_cap_needs_human()
    test_real_error_not_retried()
    print("PASS: rate-limit wait layer — detection + bounded wait/retry")


if __name__ == "__main__":
    main()
