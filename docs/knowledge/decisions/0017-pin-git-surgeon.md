---
type: decision
id: ADR-0017
title: Pin raine/git-surgeon as the shared agent git CLI
description: Adopt raine/git-surgeon (git primitives for autonomous coding agents) onto the agents' in-jail PATH, pinned at v0.1.17 and built with buildRustPackage/cargoLock.
status: accepted
date: 2026-07-26
tags: [phase-3, tooling, git-surgeon, cli, packaging]
timestamp: 2026-07-26
---

# ADR-0017 — Pin raine/git-surgeon as the shared agent git CLI

## Context and problem statement

The tooling layer ([ADR-0007](0007-shared-clis-on-path.md)) puts shared CLIs on
every agent's in-jail PATH so agents invoke them through bash. But "git-surgeon"
is **at least four different projects** (the genesis conversation flagged the
collision). We must pin exactly one, and say why.

## Decision

Adopt **`raine/git-surgeon`** — "git primitives for autonomous coding agents"
(Rust, MIT). It gives agents surgical, non-interactive git control — stage /
unstage / discard hunks, commit hunks with line-range precision, split or fold
commits — which is exactly what an agent needs and a strong complement to the
clone-and-commit flow ([ADR-0016](0016-agent-clone-not-worktree.md)): the agent
makes precise commits in its clone that the human then reviews.

Explicitly **not** `hyperb1iss/git-surgeon` (history truncation, file purging,
author rewriting; GPL-2.0) — a different, destructive tool, wrong for this role.

**Packaging:** pin the **v0.1.17** release as a `flake = false` source input and
build with `rustPlatform.buildRustPackage` + `cargoLock.lockFile`. raine's own
flake postdates that tag and builds via a sandbox-hostile `cargo build --locked`;
`buildRustPackage` vendors dependencies from `Cargo.lock` (which has **no git
deps**, so no `outputHashes` are needed) for a pure, reproducible build. This
still **references, not vendors** ([ADR-0003](0003-consume-upstreams-as-flake-inputs.md)):
the repo carries only a URL + content hash.

## Consequences

### Positive
- Agents get precise, scriptable git control via bash — no per-agent adapter.
- Reproducible, sandbox-safe build; MIT; complements ADR-0016.

### Negative / trade-offs
- We package it ourselves (its tagged release has no usable flake); a version
  bump means re-pinning the source and refreshing the `Cargo.lock` reference.
- git-surgeon shells out to `git`, so `git` must also be on the in-jail PATH —
  it is, in `sharedTools`.

## Alternatives considered
- **hyperb1iss/git-surgeon** — a different (destructive) tool, GPL-2.0. Rejected
  for this role.
- **Consume raine's flake directly** — not sandbox-pure, and the tag lacks the
  flake. Rejected in favor of `buildRustPackage`.

## Links
- [ADR-0007 — Shared CLIs on PATH over per-agent plugins](0007-shared-clis-on-path.md)
- [ADR-0016 — Agent works in a self-contained clone](0016-agent-clone-not-worktree.md)
- [ADR-0003 — Consume upstreams as pinned flake inputs](0003-consume-upstreams-as-flake-inputs.md)
- git-surgeon: <https://github.com/raine/git-surgeon>
