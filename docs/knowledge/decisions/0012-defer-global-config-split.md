---
type: decision
id: ADR-0012
title: Defer splitting out a consumable global-config repo
description: Keep ragent as a single umbrella repo now; extract a separately-consumable global-config input (ragent-config) in a later phase, once the global-vs-workspace boundary is clear.
status: accepted
date: 2026-07-26
tags: [repo-structure, packaging, flake, global-config, deferred]
timestamp: 2026-07-26
---

# ADR-0012 — Defer splitting out a consumable global-config repo

## Context and problem statement

In the genesis conversation, "ragent" is used in two senses: (1) the umbrella
workspace/harness you fork per project, and (2) a "global config repo … consumed
as a pinned flake input, not forked" — the *shared brain* (conventions, agent
skills, ADR setup, shared CLI pins) meant to be identical across all projects.
Those imply different layouts: **one** repo, or **two** (a thin per-project
workspace plus a shared-config input that many workspaces consume). If every
project instead *forks* one big repo, the forks drift and the shared config
stops being centrally updatable — the opposite of the "shared brain" goal.

## Decision

Keep ragent as a **single umbrella repo for now** (Phase 0 onward), but treat the
**split as the intended end-state**. Later — once Phases 1–3 reveal which pieces
are truly *global* versus *workspace-specific* — extract the global-config
portion into its own repo (working name `ragent-config`) that per-project
workspaces consume as a **pinned flake input** and override, with a
`nix flake init` template for scaffolding. Do **not** perform the split now: the
boundary is not yet known, and splitting prematurely would guess it wrong.

This refines [ADR-0003](0003-consume-upstreams-as-flake-inputs.md): downstream
projects consume ragent as a pinned input either way; this ADR only decides *what
the consumable unit is* — the whole repo now, a carved-out config repo later.

## Consequences

### Positive
- No premature guess at the global/workspace boundary; the split becomes
  evidence-based.
- Preserves "the shared brain stays updatable" as the end-state: updating
  `ragent-config` once lets every project bump its pin, with no fork drift.
- Costs nothing today — the Phase 0 scaffold is identical either way.

### Negative / trade-offs
- The updatable-shared-config benefit is not realized until the split lands;
  until then, reuse across projects is manual.
- A future migration (moving files into `ragent-config`, rewiring inputs) is
  owed, and must preserve git history and attribution.

## Alternatives considered
- **Commit to a single repo permanently** — simplest, but forks drift and the
  shared config is not centrally updatable.
- **Split now** — would guess the global-vs-workspace boundary before Phases 1–3
  make it clear; likely wrong and disruptive to redo.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md) — where both framings appear.
- [ADR-0003 — Consume upstreams as pinned flake inputs](0003-consume-upstreams-as-flake-inputs.md)
- [Architecture overview](../components/architecture-overview.md)
- [Forward plan — Phase 3](../components/forward-plan-phases-1-5.md)

*Decided during the Phase 0 checkpoint review with the owner (post-genesis).*
