---
type: decision
id: ADR-0010
title: Local-mirror resilience, kept out of the public repo
description: Guarantee offline rebuildability with flake.lock pins, nix flake archive, and a private upstream mirror with override failover — deliberately kept separate from the public repo.
status: accepted
date: 2026-07-26
tags: [resilience, offline, nix, mirror, supply-chain]
timestamp: 2026-07-26
---

# ADR-0010 — Local-mirror resilience, kept out of the public repo

## Context and problem statement

The project references upstreams it does not control
([ADR-0003](0003-consume-upstreams-as-flake-inputs.md)). The owner wants a hedge
for the unlikely case that an upstream disappears from GitHub/sourcehut, so the
project still builds fully offline — without vendoring others' code into the
public repo.

## Decision

Layer three levels of resilience, and keep the mirror layer **separate from the
public repository**:

1. **`flake.lock`** already pins every input by content hash — reproducible even
   if an upstream force-pushes.
2. **`nix flake archive`** pulls all inputs into the local store; `nix copy` (to
   a directory or a Cachix / self-hosted cache) persists *built* closures for
   fully-offline rebuilds.
3. **A private git mirror** of each upstream plus a small "mirrors" flake or
   `--override-input` mapping: the public repo points at real upstreams, but the
   owner can fail over to local copies.

The mirror/override layer lives outside the public repo (`.gitignore` excludes
`/mirror/`); `tools/mirror-example.sh` is a publishable template of the commands.

## Consequences

### Positive
- Fully offline rebuildable; survives upstream disappearance.
- Separation avoids redistributing others' code under ragent's name and the
  license entanglement that would bring.

### Negative / trade-offs
- The mirror is personal infrastructure to maintain and refresh.
- Because it is out of the public repo, forkers must set up their own hedge if
  they want the same guarantee (documented, not automatic).

## Alternatives considered
- **Vendor everything into the public repo** — offline-safe but triggers
  redistribution + copyleft entanglement. Rejected (see ADR-0003).
- **Trust upstream availability** — simplest, but is exactly the risk being
  hedged.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- [ADR-0003 — Consume upstreams as pinned flake inputs](0003-consume-upstreams-as-flake-inputs.md)
- `tools/mirror-example.sh`, `.gitignore`
