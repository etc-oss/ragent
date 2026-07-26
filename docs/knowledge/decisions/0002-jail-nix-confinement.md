---
type: decision
id: ADR-0002
title: Use jail.nix (bubblewrap) for machine-side confinement
description: The machine pane runs confined via Alex David's jail.nix, a Nix-native bubblewrap wrapper, not via plain Nix.
status: accepted
date: 2026-07-26
tags: [confinement, security, jail-nix, bubblewrap, nix]
timestamp: 2026-07-26
---

# ADR-0002 — Use jail.nix (bubblewrap) for machine-side confinement

## Context and problem statement

The machine pane runs coding agents that can execute arbitrary code. It must be
confined so a runaway or malicious agent cannot touch `$HOME`, SSH keys, or
secrets. A common misconception is that Nix already provides this: it does not.
Plain Nix gives a reproducible *toolchain*, not runtime *confinement* — `nix
develop` does nothing to stop a process from reading your home directory.

## Decision

Confine the machine side with **jail.nix** (`sourcehut:~alexdavid/jail.nix`),
Alex David's Nix-native wrapper around **bubblewrap**. It exposes only the bare
minimum by default and grants capabilities through explicit combinators
(`network`, `mount-cwd`, `readwrite`, `add-pkg-deps`, …). The scoped bind mount
gives the jail read-write access to the **project directory only**; everything
else is excluded. Add cgroup resource caps to bound blast radius.

## Consequences

### Positive
- Real, process-level isolation via Linux namespaces + bubblewrap — the correct
  kind of tool, not Nix miscast as a sandbox.
- Large prior art to build on: `jailed-agents` already jails opencode/pi/crush
  with jail.nix and ships a `makeJailedAgent` builder.
- Capabilities are explicit and auditable in the flake.

### Negative / trade-offs
- **Linux-only.** bubblewrap needs Linux namespaces, so this must run inside a
  Linux guest on macOS — hence [Lima](0004-lima-vm-layer.md). No native-macOS
  path for bwrap.
- jail.nix is **GPL-3.0**; we keep our Apache umbrella clean only by referencing,
  never vendoring it — see [ADR-0003](0003-consume-upstreams-as-flake-inputs.md).
- bubblewrap needs unprivileged user namespaces enabled in the guest.
- A shared bind mount is isolation, not *oversight* — that gap is addressed by
  [ADR-0011](0011-git-worktree-review-boundary.md).

## Alternatives considered
- **Plain `nix develop`** — reproducible toolchain, zero confinement. Rejected.
- **sandnix (landrun/Landlock, `sandbox-exec`)** — weaker model but native on
  macOS; kept as a documented fallback, not the primary mechanism.
- **Full VM / container per agent** — heavier; the VM already exists for Lima,
  and bwrap is lighter-weight inside it.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- [ADR-0003 — Consume upstreams as pinned flake inputs](0003-consume-upstreams-as-flake-inputs.md)
- [ADR-0004 — Lima as the VM layer](0004-lima-vm-layer.md)
- [ADR-0011 — Git-worktree review boundary](0011-git-worktree-review-boundary.md)
- Prior art: <https://github.com/andersonjoseph/jailed-agents>
