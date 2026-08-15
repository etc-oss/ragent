---
type: decision
id: ADR-0024
title: The 6b review loop is human-paced; max_iterations is the runaway guard
description: The bounded examine→revise→reply→merge loop revises only in response to a NEW human note (the confined agent can't self-trigger), so max_iterations — not wall-clock — is the load-bearing runaway guard. Wall-clock becomes a resource cap in hours; "cost" is cumulative agent runtime; a tripped bound posts a needs-human reply. The loop splits into a testable _step + a sleep/bounds wrapper.
status: accepted
date: 2026-07-27
tags: [phase-6, review, loop, bounds, orchestrator, safety, autonomy]
timestamp: 2026-07-27
---

# ADR-0024 — The 6b review loop is human-paced; `max_iterations` is the runaway guard

## Context and problem statement

Phase 6b is the bounded loop that closes the async-review circle: poll the review,
feed the human's review notes to the confined agent, push its revision, repeat until
resolved. [ADR-0020](0020-review-transport-adapters.md) named four bounds
generically — `maxIterations`, `maxCostUSD`, `wallClockMin`, and a "needs-human"
escape — as a flat set. Implementing it surfaced that **not all four bounds mean the
same thing**, and that a naive wall-clock bound is actively wrong for this loop.

## Decision

**The loop is *human-paced*, and the bounds are designed around that fact.**

**Human-paced (the load-bearing property).** The confined agent revises **only in
response to a NEW human review note**. It has no forge access (ADR-0016); the
orchestrator's own replies are prefixed with a shared `REPLY_MARKER` and filtered
out; `push`/`reply` create nothing that `examine` returns as a new note. So the loop
**cannot self-trigger** — between human notes it just polls and waits. This changes
what each bound is *for*:

- **`max_iterations` (agent revision count) — the load-bearing runaway guard.**
  Because the agent can't self-trigger, the only way it runs "away" is a human (or a
  loop bug) feeding it endlessly. Cap the number of revisions; on trip, stop. This is
  the bound that is **enforced and tested**.
- **Wall-clock — a *resource* cap, in HOURS, not a misbehavior signal.** "Review on
  the go" means human latency is *hours* (asleep, in a meeting). A minutes-scale
  wall-clock (ADR-0020 said 60 min) would fire on a **perfectly healthy PR the human
  simply hasn't looked at yet** and cry "needs-human." So wall-clock is reframed as
  "the orchestrator has lived long enough, **stop cleanly** (the PR stays open)" —
  defaulted to 24h, and it does **not** post needs-human (nothing is wrong). A re-run
  **restarts the task** (re-executes the original prompt on the reused clone with a
  fresh `processed` set), it does not resume the poll — persisting loop state to
  `.ragent/` to make it truly resumable is a 6c item.
- **"Cost" = cumulative *agent* runtime.** We can't get token counts from the jailed
  agent, but we can time each revise call and cap the **sum** — which, unlike
  wall-clock-since-open, never counts human idle. A real, measurable cost proxy.
- **needs-human escape = a prominent `reply`.** On a real runaway (max_iterations or
  agent-runtime), post a `REPLY_MARKER`-tagged "needs-human" comment and stop. No new
  adapter verb — a proper forge **label** is 6c polish; `reply` works for every
  conversation-capable transport today.

**New-notes tracking.** A `processed` set of note **signatures** (kind, ts, author,
body), not a single timestamp watermark — Forgejo timestamps are second-granular, so
a watermark could silently skip a note posted in the same second as one just handled.
State is **in-memory** (per-task process): a crash re-feeds notes on restart, which is
acceptable now; persist to the clone's `.ragent/` if the loop ever outlives one task.

**Testability — split `_step` from `review_loop`.** `_step` does one
poll-and-maybe-revise and returns `(status, action, agent_seconds)`; `review_loop` is
the thin `sleep`+bounds wrapper around it. A same-process test drives `_step`
directly — interleaving the reviewer's REQUEST_CHANGES / APPROVED via the API — with a
**stub `revise`** (a deterministic file edit), so the *new* logic is verified with **no
LLM, no threads, no real sleeps**. The real jailed agent's ability to revise was
already proven by the 6a parity run; a real-agent loop iteration is confidence, not
new coverage.

**Wiring.** The loop runs only if the adapter's `capabilities` include `conversation`
(else the served report is the review channel). `ragent task orchestrate` **follows
by default**; `--no-follow` keeps the 6a open-and-stop path. Knobs come from env
(`RAGENT_POLL_INTERVAL` / `RAGENT_MAX_ITERATIONS` / `RAGENT_MAX_AGENT_MIN` /
`RAGENT_MAX_WALL_HOURS` / `RAGENT_AUTO_MERGE`; defaults 20s / 6 / 30min / 24h / false).

## Consequences

### Positive
- The bound that matters (revision count) is enforced and **tested**; runaway is
  genuinely capped without falsely tripping on slow human review.
- The loop mechanics are deterministically unit-testable (`_step` + stub revise).
- No new adapter verb; the 9-verb interface (ADR-0022) stays stable.

### Negative / trade-offs
- Wall-clock and agent-runtime caps are coarse (no token accounting); acceptable, and
  the human gate + `max_iterations` are the real safety.
- In-memory loop state → a crash re-feeds notes (bounded re-work; noted for later).
- A single-shared-user test needs the `REPLY_MARKER` to distinguish bot from human;
  in real multi-user use the author differs too.

## Alternatives considered
- **Flat four-bounds, wall-clock in minutes** (ADR-0020's first cut) — rejected: fires
  needs-human on a healthy, not-yet-reviewed PR; misreads human latency as a fault.
- **Timestamp watermark for new notes** — rejected: second-granular timestamps can
  skip a same-second note; a signature set is exact.
- **A blocking loop tested with threads + real sleeps** — rejected: flaky and slow;
  the `_step` split makes it deterministic.
- **A new `label` verb for needs-human** — deferred to 6c; `reply` suffices now.

## Links
- [ADR-0020 — Review transport adapters](0020-review-transport-adapters.md) (refines
  its bounds set + semantics)
- [ADR-0022 — Python adapters + verb superset](0022-python-adapters-verb-superset-capabilities.md)
  (`examine`/`reply`/`status`/`merge` + `capabilities`; the shared `REPLY_MARKER`)
- [ADR-0023 — Unified ragent CLI](0023-unified-ragent-cli.md) (`ragent task orchestrate`)
- [async review transport](../components/forgejo-transport-design.md),
  [Roadmap](../components/roadmap.md)
- `tools/ragent/orchestrator.py` (`_step` / `review_loop`), `tests/test_review_loop.py`
