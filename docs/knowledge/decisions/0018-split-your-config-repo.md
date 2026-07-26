---
type: decision
id: ADR-0018
title: Split personal config into your-config-repo (realizes ADR-0012)
description: Execute ADR-0012's split — extract the personal config layer into a separate repo, your-config-repo, that consumes ragent as a pinned input; the VM/deployment specifics move there first.
status: accepted
date: 2026-07-26
tags: [repo-structure, split, your-config-repo, vm, config]
timestamp: 2026-07-26
---

# ADR-0018 — Split personal config into your-config-repo (realizes ADR-0012)

## Context and problem statement

[ADR-0012](0012-defer-global-config-split.md) kept ragent a single umbrella repo
but treated a split of the personal/global config into its own consumable repo as
the end-state, deferred until the boundary was clear. With Phases 0–5 built, the
owner chose to execute the split now and named the config repo **your-config-repo**
(not the placeholder "ragent-config").

## Decision

Create **your-config-repo** (at `~/Developer/randomness/your-config-repo`) as the
personal config repo. It **consumes ragent as a pinned flake input** (never forks
it) and holds the personal/environment layer. The first things moved out of the
ragent framework are the **VM / deployment specifics**:

- `lima/ragent.yaml` — the local Lima guest.
- `deploy/{cloud-init.yaml,provision.sh}` — a dedicated Linux VM (Option A).
- `nixos/ragent-box.nix` + `nixosConfigurations.your-config-repo` — the declarative
  box (Option B).

ragent keeps the shareable framework: the jail, the workspace mechanism, the
agents, the shared-tools layer, the knowledge system, and the Catppuccin theme as
a default. your-config-repo composes ragent's `workspace` devshell/app and adds
personal specifics (the VM config now; agent choices / extra tools / theme
overrides later).

## Consequences

### Positive
- Realizes ADR-0012's "shared brain as a consumable input": ragent stays generic
  and forkable; your-config-repo is the personal layer.
- Personal VM/deploy config no longer lives in the framework.
- Verified: your-config-repo composes ragent's `workspace` devshell (`nix eval` →
  `nix-shell`).

### Negative / trade-offs
- ragent alone no longer ships a runnable VM config; running it needs a config
  repo (your-config-repo) or your own Linux VM. ragent's docs point to
  [running on a VM](../components/running-on-a-vm.md).
- `ragent.url` in your-config-repo is a local `path:` until ragent is published;
  two repos to keep in sync.

## Alternatives considered
- **Keep everything in ragent** (ADR-0012's "now" state) — rejected: the owner
  wants the personal layer separate.
- **ragent depends on your-config-repo** (inverted) — rejected: the framework must
  not depend on personal config; your-config-repo consumes ragent.

## Links
- [ADR-0012 — Defer splitting out a consumable global-config repo](0012-defer-global-config-split.md) (realized by this)
- [ADR-0003 — Consume upstreams as pinned flake inputs](0003-consume-upstreams-as-flake-inputs.md)
- [Running ragent on a VM](../components/running-on-a-vm.md)
