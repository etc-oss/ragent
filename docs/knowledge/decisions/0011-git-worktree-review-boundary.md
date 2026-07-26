---
type: decision
id: ADR-0011
title: Git-worktree review boundary for human oversight
description: The agent proposes changes on a dedicated branch/worktree that the human reviews before landing; push/deploy secrets stay on the human side.
status: proposed
date: 2026-07-26
tags: [oversight, git, worktree, secrets, review]
timestamp: 2026-07-26
---

# ADR-0011 — Git-worktree review boundary for human oversight

## Context and problem statement

The scoped bind mount ([ADR-0002](0002-jail-nix-confinement.md)) shares the
project directory with the jailed agent — but a shared directory is *isolation*,
not *oversight*. The whole point of the workspace is human review of machine
work. We need a boundary where a human sees and approves diffs before they land,
and where deploy/push credentials never enter the jail.

## Decision (proposed)

Give human review a **git boundary**, not just a filesystem one:

- The agent operates on an `agent/<task>` branch or a dedicated **git
  worktree**.
- The human pane (lazygit/neovim) reviews diffs on the main tree before anything
  is merged.
- **Secrets split by side:** push/deploy credentials live on the *human* side;
  the machine may only *propose* commits. The LLM API key is bound explicitly
  into the jail; git push credentials never enter it.

Status is **proposed** — to be validated when Phases 1–2 build the real loop.
pi's "Gondolin" pattern (auth on host, agent tools in a micro-VM) is an
inverted precedent worth studying during validation.

## Consequences

### Positive
- Real oversight: nothing lands without a human-reviewed diff.
- Clean secret boundary: a compromised/confused agent cannot push or deploy.

### Negative / trade-offs
- Branch/worktree orchestration adds moving parts to the loop.
- Agents must be reliably steered to operate on their own branch/worktree.

## Alternatives considered
- **Shared directory only** — simplest, but provides no review gate. Rejected as
  the oversight mechanism.
- **A full fork/clone per task** — heavier than a worktree for the same benefit.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- [ADR-0002 — jail.nix for confinement](0002-jail-nix-confinement.md)
- [ADR-0005 — Zellij two-side layout](0005-zellij-two-pane-layout.md)
- [Forward plan — Phases 1–2](../components/forward-plan-phases-1-5.md)
