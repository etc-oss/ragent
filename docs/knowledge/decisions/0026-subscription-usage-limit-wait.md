---
type: decision
id: ADR-0026
title: Wait out a subscription usage limit instead of falling back to the API
description: On the autonomous path, when the Claude subscription agent hits a usage limit, the orchestrator WAITS and retries — never falls back to the API key. Detection is fail-safe (positive high-precision match only; real errors surface), the wait is bounded (a misread can't hang for days → needs-human), and idle wait time is excluded from the 6b cost bound. Live weekly-limit detection is structurally unverifiable, so the tests prove the mechanics + bound, not live detection.
status: accepted
date: 2026-08-15
tags: [auth, subscription, rate-limit, orchestrator, autonomy, safety, claude-code]
timestamp: 2026-08-15
---

# ADR-0026 — Wait out a subscription usage limit instead of falling back to the API

## Context and problem statement

[ADR-0025](0025-jailed-claude-subscription-auth.md) lets the jailed agent run on a
Claude **subscription**, which has session (5-hour) and weekly usage limits. The
API-key agent was positioned as the fallback when the subscription runs dry — but
the intent is **subscription-first with no API fallback**: on a limit, *wait for the
reset and resume*, not silently switch to (and bill) the API. That needs the
autonomous path to **recognise** a usage limit, wait, and retry — a genuinely new,
and genuinely risky, behavior (mis-classifying a real error as a limit would hang a
run for days while masking the bug).

## Decision

**On the autonomous path (`orchestrator._run_agent`, used by `orchestrate` and the 6b
`revise`), wait out a subscription usage limit and retry — never fall back to the
API.** The interactive TUI path (`spawn-agent.sh`) is left to the human, who is
present.

Four properties make it safe (the advisor's framing, applied):

1. **Fail-safe detection.** A run counts as rate-limited **only** on a positive,
   high-precision match to a known limit phrase (`_detect_usage_limit`); *anything
   else* — a bad prompt, network failure, a cgroup OOM, a crash — is a real failure
   that surfaces to the human. The dangerous bug is a false positive (wait for days,
   masking a bug); the safe failure is the reverse.
2. **Bounded wait.** The retry loop is capped by `max_wait_hours` (default 6h, which
   covers the 5-hour session limit). Past the cap it **stops with a needs-human
   message** — so even a *misread* error can't hang forever; it surfaces.
3. **Idle ≠ cost.** `_run_agent` returns the seconds it spent waiting; the 6b loop
   **subtracts** that from the agent-runtime it bounds. A limit wait is idle time,
   like human-review latency — the same "idle ≠ misbehavior" reframing as
   [ADR-0024](0024-human-paced-bounded-review-loop.md)'s wall-clock. (Without this,
   a blocking `_run_agent` inside `_step` would also silently defeat 6b's own caps.)
4. **Loud + testable.** Every pause logs "PAUSED … not falling back to the API" plus
   any parsed reset hint, so a long pause never reads as a hang. `_wait_out_limits`
   is split from the agent subprocess so the mechanics are unit-tested with a stub.

Config (env): `RAGENT_LIMIT_POLL_SEC` (900), `RAGENT_LIMIT_MAX_WAIT_HOURS` (6),
`RAGENT_LIMIT_PATTERNS` (override the matchers). **your-config-repo** sets
`jailed-claude-code-subscription` as its default agent.

## Verification — and the corner it can't reach (honest)

Verified against the **real binary** (claude-code 2.1.220): the literal strings
`"hit your session/weekly limit"` are **composed at runtime** (0 hits in the bundle);
only `spend limit reached` and the structured `rate_limit`/`billing_error`/`api_retry`
tokens are literal. A **real weekly limit cannot be triggered on demand**, so live
usage-limit *detection* ships **unverified against reality** — the one place this
project's "verify by behavior" rule structurally cannot reach. What the tests
(`tests/test_limit_wait.py`) prove deterministically:
- the detector matches the known limit phrases **and ignores real errors** (fail-safe);
- the loop waits out a limit then succeeds; stops at the cap (needs-human); and does
  **not** retry a genuine error.

Re-verify the matchers on a Claude Code bump, and if you ever hit a real limit, check
the logs classified it correctly.

## Consequences

### Positive
- Subscription-first with no surprise API billing; short (session) limits are waited
  out automatically; long (weekly) limits surface with clear guidance.
- Bounded, so a detection miss can't hang a run; 6b's own bounds stay intact.

### Negative / trade-offs
- Detection is best-effort and version-sensitive (see above).
- A limit hit **mid-task** leaves partial edits in the clone; the retry re-runs `-p`
  on top (tolerable for one-shot `-p`, and logged).
- A long blocking wait is **not durable** — a VM sleep/restart kills it (the same
  durability gap as the 6c "persist loop state" item). Hence the conservative default
  cap + needs-human; to truly wait out a *weekly* reset, raise
  `RAGENT_LIMIT_MAX_WAIT_HOURS`, but a resumable version is 6c.

## Alternatives considered
- **Fall back to the API key** — rejected: the explicit intent is to stay on the
  subscription; silent API billing is a surprise-cost footgun.
- **Retry any non-zero exit with backoff** — rejected: retries genuine errors
  (violates fail-safe); masks real bugs behind days of waiting.
- **Parse the reset timestamp and sleep exactly until then** — the messages are
  local-time, no date/zone, and version-sensitive; a bounded poll + logged hint is
  more robust than trusting a fragile parse.

## Links
- [ADR-0025 — Jailed Claude Code subscription auth](0025-jailed-claude-subscription-auth.md)
  (this makes it usable without an API fallback)
- [ADR-0024 — Human-paced bounded review loop](0024-human-paced-bounded-review-loop.md)
  (the idle-≠-cost reframing, applied here)
- `tools/ragent/orchestrator.py` (`_detect_usage_limit`, `_wait_out_limits`),
  `tests/test_limit_wait.py`, [Roadmap](../components/roadmap.md) (6c durability)
