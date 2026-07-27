---
type: decision
id: ADR-0021
title: Per-task explanatory HTML report, served for universal oversight
description: Alongside every agent task, ragent renders the agent's own explanation plus the real diff to a self-contained HTML report and serves it — a forge-independent oversight channel reviewable from any device.
status: accepted
date: 2026-07-27
tags: [oversight, review, html, report, okf, serve, security]
timestamp: 2026-07-27
---

# ADR-0021 — Per-task explanatory HTML report, served for universal oversight

## Context and problem statement

Human oversight should be **universal and optimal** — reviewable from any device,
without requiring a forge to be stood up. A raw diff shows *what* changed but not
*why*; the reasoning is the point of oversight. The project already renders
Markdown to self-contained offline HTML (`tools/okf_render.py`), and the agent
already works in a git clone (ADR-0016) — so the pieces to render a per-task
explanation + diff exist.

## Decision

**Alongside every agent task, generate a self-contained HTML report — the agent's
own explanation plus the real diff — and serve it.** This is a first-class oversight
channel that **complements the forge** ([ADR-0020](0020-review-transport-adapters.md))
and works with no forge at all.

- **The explanation is the agent's *deliberate* output:** the agent writes
  `.ragent/EXPLAIN.md` in its clone (asked for in the template `AGENTS.md`); the
  report combines that with `git diff base..agent/<task>`. If `EXPLAIN.md` is
  absent, it falls back to a stripped tail of the agent log.
- **Reuse the renderer, not a parallel one:** `tools/ragent-report.py` imports
  `okf_render`'s Markdown renderer + CSS (the whole `tools/` dir is one store path
  so the import resolves), and renders the diff with its own neon add/del colouring.
- **Host-side + automatic:** report generation runs *outside* the jail (same side as
  a forge push), invoked by the clone's `spawn-agent.sh` after the agent finishes.
- **Serve = a security seam:** `nix run .#task-review -- <dir>` binds `127.0.0.1` by
  default (python `http.server` is unauthenticated); a private **Tailscale** address
  is opt-in (`RAGENT_SERVE_HOST`). This is **weaker than the forge's token-gated
  review** and is documented as such — never bind a public port.

## Consequences

### Positive
- Oversight from any device with no forge — the lightest path to "review on the go".
- Reasoning + change reviewed together; ties the AGENTS.md "explain yourself"
  convention to a concrete artifact.
- One substrate: the same report is what a forge `report` verb (ADR-0020) can post.

### Negative / trade-offs
- `http.server` is unauthenticated → localhost/Tailscale only (stated, bounded).
- Quality depends on the agent writing a good `EXPLAIN.md` (fallback is a raw log).
- Another host-side tool to maintain (small; reuses the renderer).

## Alternatives considered
- **Diff-only (no explanation)** — loses the *why*, the whole point.
- **Scrape the agent log for reasoning** — noisy, ANSI-laden, accumulates across
  iterations; a deliberate `EXPLAIN.md` is faithful.
- **Only the forge** — heavier, and unavailable without standing one up; the served
  report is universal.

## Links
- [ADR-0020 — Review transport adapters](0020-review-transport-adapters.md) (this complements it)
- [ADR-0016 — Agent works in a clone](0016-agent-clone-not-worktree.md),
  [ADR-0008 — OKF + ADR knowledge capture](0008-okf-adr-knowledge-capture.md)
- [Roadmap](../components/roadmap.md), [async review transport](../components/forgejo-transport-design.md)
- `tools/ragent-report.py`, `tools/ragent-serve.sh`
