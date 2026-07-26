---
type: decision
id: ADR-0004
title: Use Lima as the Linux VM layer
description: The flake and jail run inside a Lima Linux guest, because bubblewrap is Linux-only and the primary host is macOS.
status: accepted
date: 2026-07-26
tags: [lima, vm, macos, linux, portability]
timestamp: 2026-07-26
---

# ADR-0004 — Use Lima as the Linux VM layer

## Context and problem statement

[jail.nix/bubblewrap](0002-jail-nix-confinement.md) requires Linux namespaces, so
it cannot run natively on macOS. The primary development host is macOS. We need a
Linux environment that feels native and can host the Nix store and the jail.

## Decision

Run the flake and the jail inside a **Lima** (`lima-vm/lima`) Linux guest. The
layering is `macOS → Lima → jail.nix/bubblewrap → agent`. Neovim and the agents
run *inside the guest* (not editing host files over a virtiofs/sshfs mount, which
gets sluggish on large repos).

## Consequences

### Positive
- A real Linux kernel with namespaces, so bubblewrap works unchanged.
- Apache-2.0 licensed; integrates cleanly with a shared Nix store
  ([ADR-0006](0006-one-long-lived-vm-per-project-devshells.md)).
- Same jail works on Windows via WSL2 (also Linux).

### Negative / trade-offs
- **Not native macOS.** The honest portability claim is "any Linux, or
  mac/Windows via a Linux VM," not "runs natively everywhere."
- Nesting (`macOS terminal → SSH → Lima → Zellij`) introduces ergonomic
  papercuts — clipboard passthrough, truecolor, keybinding collisions — that
  Phase 2 must budget for. See [ADR-0005](0005-zellij-two-pane-layout.md).
- A VM is a moving part with its own lifecycle to manage.

## Alternatives considered
- **Native macOS confinement** — impossible for bubblewrap; `sandbox-exec`
  (via sandnix) is a weaker, separate model kept only as a fallback.
- **Docker Desktop** — heavier, a different isolation model, and still a Linux VM
  under the hood on macOS.
- **microvm.nix** — interesting for stronger isolation later; more than the
  vertical slice needs now.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- [ADR-0002 — jail.nix for confinement](0002-jail-nix-confinement.md)
- [ADR-0006 — One long-lived VM, per-project devshells](0006-one-long-lived-vm-per-project-devshells.md)
