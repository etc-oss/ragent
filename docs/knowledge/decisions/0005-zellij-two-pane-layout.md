---
type: decision
id: ADR-0005
title: Zellij two-side human/machine workspace layout
description: The TUI is a Zellij KDL layout with a HUMAN side and a MACHINE side, each with a main pane and an observability/log pane.
status: accepted
date: 2026-07-26
tags: [zellij, tui, workspace, layout, observability]
timestamp: 2026-07-26
---

# ADR-0005 — Zellij two-side human/machine workspace layout

## Context and problem statement

The workspace needs two clearly separated sides working on the same project — a
**HUMAN** side (neovim + LSPs + lazygit) and a **MACHINE** side (confined coding
agents) — each with its own observability pane (the tool in use for the human;
logs for the machine). We need a terminal workspace that expresses this cleanly.

## Decision

Define the workspace as a **Zellij** KDL layout: two sides (tabs/panes), each
with a main pane plus a log/observability pane. Zellij's KDL layouts handle this
two-tab, main-plus-log structure directly.

## Consequences

### Positive
- KDL layouts express the structure trivially; low effort for the core shell.
- Zellij is MIT-licensed and WASM-plugin extensible if richer observability is
  ever justified.

### Negative / trade-offs
- Running Zellij inside an SSH'd [Lima](0004-lima-vm-layer.md) session fights on
  clipboard passthrough, truecolor, and keybinding collisions — worse if tmux is
  anywhere in the stack. Decide the nesting deliberately; run neovim in-guest.
- Unified observability is aspirational: the agents emit heterogeneous logs, so
  the "log pane" starts as `tail -f` + `jq`/`fx`, not a normalizer.

## Alternatives considered
- **tmux** — capable but more prone to keybinding collisions in this nested
  setup; Zellij's layouts are a better fit for a declarative workspace.
- **Raw terminal splits / a bespoke TUI** — more work, less portable.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- [ADR-0004 — Lima as the VM layer](0004-lima-vm-layer.md)
- [ADR-0011 — Git-worktree review boundary](0011-git-worktree-review-boundary.md)
- [Forward plan — Phase 2](../components/forward-plan-phases-1-5.md)
