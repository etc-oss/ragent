---
type: decision
id: ADR-0006
title: One long-lived VM with per-project devshells
description: Share a single long-lived Lima VM and Nix store across projects, with per-project devshells and a binary cache, rather than a VM per project.
status: accepted
date: 2026-07-26
tags: [vm, nix, devshell, performance, cold-start]
timestamp: 2026-07-26
---

# ADR-0006 — One long-lived VM with per-project devshells

## Context and problem statement

The workspace is "forkable per project." Naively that suggests a VM per project,
but that would rebuild the jail closure on every fork and make cold-start slow —
and open-source adoption hinges on cold-start reliability.

## Decision

Run **one long-lived Lima VM** that shares a single Nix store, with **per-project
devshells** on top. Add a binary cache (e.g. Cachix) so the jail closure isn't
rebuilt for every fork.

## Consequences

### Positive
- Shared Nix store + binary cache → fast project forks, no closure rebuild.
- One environment to maintain and reason about.

### Negative / trade-offs
- Projects share VM-level state, so per-project isolation must come from the
  scoped jail bind mount ([ADR-0002](0002-jail-nix-confinement.md)), not from
  separate VMs.
- The single VM's lifecycle (updates, disk, drift) is a maintenance surface.

## Alternatives considered
- **VM per project** — cleanest isolation but slow, heavy, and redundant given
  the jail already scopes filesystem access per project.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- [ADR-0004 — Lima as the VM layer](0004-lima-vm-layer.md)
- [ADR-0002 — jail.nix for confinement](0002-jail-nix-confinement.md)
