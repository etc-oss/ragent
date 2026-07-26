---
type: index
id: INDEX-decisions
title: Decisions (ADRs)
description: Architecture Decision Records, MADR-style, each linked back to the session that produced it.
tags: [index, decisions, adr]
timestamp: 2026-07-26
---

# Decisions (ADRs)

MADR-style records per the [adr-process convention](../conventions/adr-process.md).
All were seeded from the [genesis conversation](../sessions/0001-genesis-architecture-conversation.md).

| ADR | Title | Status |
|---|---|---|
| [0001](0001-apache-2.0-license.md) | Use Apache-2.0 as the umbrella license | accepted |
| [0002](0002-jail-nix-confinement.md) | Use jail.nix (bubblewrap) for machine-side confinement | accepted |
| [0003](0003-consume-upstreams-as-flake-inputs.md) | Consume upstreams as pinned flake inputs (reference, never vendor) | accepted |
| [0004](0004-lima-vm-layer.md) | Use Lima as the Linux VM layer | accepted |
| [0005](0005-zellij-two-pane-layout.md) | Zellij two-side human/machine workspace layout | accepted |
| [0006](0006-one-long-lived-vm-per-project-devshells.md) | One long-lived VM with per-project devshells | accepted |
| [0007](0007-shared-clis-on-path.md) | Shared CLIs on PATH over per-agent plugins | accepted |
| [0008](0008-okf-adr-knowledge-capture.md) | OKF + ADR for knowledge capture | accepted |
| [0009](0009-opus-design-sonnet-execution.md) | Opus-for-design / Sonnet-for-execution model split | accepted |
| [0010](0010-local-mirror-resilience.md) | Local-mirror resilience, kept out of the public repo | accepted |
| [0011](0011-git-worktree-review-boundary.md) | Git-worktree review boundary for human oversight | proposed |
| [0012](0012-defer-global-config-split.md) | Defer splitting out a consumable global-config repo | accepted |
| [0013](0013-jailed-agents-opencode-first.md) | Build the jail on jailed-agents; prove confinement with a probe; opencode first | accepted |
| [0014](0014-runtime-env-secret-forwarding.md) | Provider API key via runtime env forwarding; no credential dir in the jail | accepted |
| [0015](0015-cgroup-caps-systemd-run.md) | cgroup resource caps via an external systemd-run scope | accepted |
