---
type: decision
id: ADR-0003
title: Consume upstreams as pinned flake inputs (reference, never vendor)
description: The public repo references every upstream as a pinned Nix flake input and never copies their source, keeping attribution automatic and copyleft contained.
status: accepted
date: 2026-07-26
tags: [governance, nix, flake, licensing, attribution]
timestamp: 2026-07-26
---

# ADR-0003 — Consume upstreams as pinned flake inputs (reference, never vendor)

## Context and problem statement

`ragent` depends on others' work (jail.nix, nixpkgs, Zellij, Lima, …) and wants
to honor it. It also wants an "off-GitHub" hedge in case upstreams vanish. There
are two postures: **fork/vendor** the code into this repo, or **reference** it as
a pinned dependency. The choice has both ergonomic and licensing consequences —
sharpened by the fact that jail.nix is **GPL-3.0**.

## Decision

Reference every upstream as a **pinned Nix flake input**. The public repository
contains only URLs and content hashes (`flake.nix` / `flake.lock`) — never a copy
of upstream source. Downstream projects consume `ragent` itself the same way (as
a flake input they compose and override), not by forking it.

## Consequences

### Positive
- **Attribution is automatic and honest** — a URL + hash credits the source and
  redistributes nothing.
- **No redistribution obligations.** Because we never ship jail.nix's (GPL-3.0)
  or bubblewrap's (LGPL) code, copyleft attaches upstream, not here; ragent's own
  files stay Apache-2.0.
- **Reproducible** — `flake.lock` pins by content hash, so builds are stable even
  if an upstream force-pushes.
- Keeps the "shared brain" updatable — bumping an input is a one-line change, not
  a fork merge.

### Negative / trade-offs
- Builds depend on upstream availability — mitigated, deliberately, by
  [ADR-0010](0010-local-mirror-resilience.md) (local mirror + `nix flake archive`).
- Upstream changes must be pulled in intentionally (a lock bump), which is also a
  feature.

## Alternatives considered
- **Hard fork each upstream** — drifts from upstream, breaks updatability, and
  drags others' code under ragent's name. Rejected.
- **Vendor copies into the public repo** — triggers redistribution + copyleft
  entanglement (GPL/LGPL), the exact thing Apache-2.0 + referencing avoids.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- [ADR-0001 — Apache-2.0 license](0001-apache-2.0-license.md)
- [ADR-0010 — Local-mirror resilience](0010-local-mirror-resilience.md)
- `THIRD_PARTY.md`
