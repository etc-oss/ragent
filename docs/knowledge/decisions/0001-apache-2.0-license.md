---
type: decision
id: ADR-0001
title: Use Apache-2.0 as the umbrella license
description: ragent's own code is licensed Apache-2.0 for its explicit patent grant and NOTICE attribution mechanism.
status: accepted
date: 2026-07-26
tags: [license, governance, apache-2.0]
timestamp: 2026-07-26
---

# ADR-0001 — Use Apache-2.0 as the umbrella license

## Context and problem statement

`ragent` needs a permissive umbrella license for its own files. The project
cares a lot about crediting upstreams generously, and at least one core
dependency ([jail.nix](0002-jail-nix-confinement.md)) is copyleft (GPL-3.0). The
two sane candidates are MIT (minimal) and Apache-2.0.

## Decision

License ragent's own code under **Apache-2.0**.

## Consequences

### Positive
- **Explicit patent grant** — MIT has none; Apache-2.0's matters for a tool that
  wraps sandboxing/VM tech.
- **A built-in `NOTICE` mechanism** designed for exactly the kind of upstream
  attribution this project does (`NOTICE`, `THIRD_PARTY.md`).
- **One-way GPLv3 compatibility** — Apache-2.0 code may be incorporated into
  GPLv3 works, so nothing here conflicts with copyleft upstreams we reference.

### Negative / trade-offs
- More verbose than MIT; contributors must keep `NOTICE` current.
- Apache-2.0 is *not* compatible with GPLv2-only projects, should we ever want
  to vendor one (we do not — see [ADR-0003](0003-consume-upstreams-as-flake-inputs.md)).

## Alternatives considered
- **MIT** — simplest, but no patent grant and no NOTICE convention; weaker fit
  for a project whose whole ethos is careful attribution.
- **A copyleft license (GPL)** — wrong shape: ragent is a permissive umbrella
  that *references* upstreams; it is not itself trying to enforce copyleft.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- [ADR-0003 — Consume upstreams as pinned flake inputs](0003-consume-upstreams-as-flake-inputs.md)
- `LICENSE`, `NOTICE`, `THIRD_PARTY.md`

*Not legal advice — this records the project's reasoning, not a lawyer's opinion.*
