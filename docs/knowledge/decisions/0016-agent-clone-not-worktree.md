---
type: decision
id: ADR-0016
title: Agent works in a self-contained clone, not a git worktree
description: The machine side operates in a full git clone (its own .git inside the jail bind); a worktree's object store lies outside the cwd bind and breaks in-jail git.
status: accepted
date: 2026-07-26
tags: [phase-2, git, jail, worktree, clone, oversight]
timestamp: 2026-07-26
---

# ADR-0016 — Agent works in a self-contained clone, not a git worktree

## Context and problem statement

[ADR-0011](0011-git-worktree-review-boundary.md) proposed the agent operate on an
`agent/<task>` branch or a **git worktree**, with the human reviewing diffs. But
the jail binds only the cwd ([mount-cwd](0002-jail-nix-confinement.md)). A
worktree's `.git` is a *file* pointing at `<main>/.git/worktrees/<name>`, and its
object store lives in `<main>/.git` — both **outside** the worktree directory. So
a jailed agent running git from a worktree cannot reach the object store.

Verified in the guest: a jailed shell (`mount-cwd` + git) run from a worktree
fails with `fatal: not a git repository: (null)`; run from a self-contained clone
it succeeds — `git status` works and the agent can `git commit` on its branch.

## Decision

The machine side operates in a **self-contained git clone** of the project (its
own complete `.git` inside the cwd bind), on an `agent/<task>` branch — not a
worktree. The jail's `mount-cwd` binds the clone directory, so all git (status,
add, commit, and git-surgeon in Phase 3) works entirely inside the jail. This
**refines the mechanism of ADR-0011**; the oversight intent is unchanged.

Human review: from the main tree, `git fetch <clone> agent/<task>` and review the
diff, then accept (merge) or discard. The clone's `origin` is the local main repo
(not a network remote); push/deploy credentials stay human-side (ADR-0011).

## Consequences

### Positive
- In-jail git works, so the agent can genuinely *propose commits* on its branch
  (realizes ADR-0011) and use in-jail git tooling later (Phase 3).
- Full filesystem confinement is preserved — only the clone dir is bound.

### Negative / trade-offs
- The clone duplicates the working tree. Mitigate with `git clone --local`
  (hardlinks objects) for cheap local clones.
- A sync-back step (fetch/merge from the clone) is required for the human to land
  changes — which is exactly the review gate.
- Two checkouts to keep straight: the main tree and the agent clone.

## Alternatives considered
- **git worktree** — breaks in-jail git (object store outside the bind). Rejected
  as the jail-side mechanism.
- **Also bind the main `.git` into the jail** — would expose the whole repo and
  widen the bind beyond cwd, against the scoped-mount principle.
- **Agent edits only; all git human-side** — simplest, but forfeits "agent
  proposes commits" and in-jail tooling.

## Links
- [ADR-0011 — Git-worktree review boundary](0011-git-worktree-review-boundary.md) (mechanism refined by this)
- [ADR-0002 — jail.nix for confinement](0002-jail-nix-confinement.md)
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- [Forward plan — Phase 2](../components/forward-plan-phases-1-5.md)
