---
type: decision
id: ADR-0023
title: A unified `ragent` CLI (task subcommands) over flat per-app entry points
description: Collapse ragent's flat, separately-named apps (#workspace/#serve/#orchestrate/#zellij) into one human-facing `ragent` binary with subcommands under `task` (window/orchestrate/review/list/attach/kill); apps.default=ragent plus thin task-* aliases. The CLI is the human vocabulary and is deliberately distinct from the adapter verb superset (ADR-0022), which is the orchestrator's internal SPI.
status: accepted
date: 2026-07-27
tags: [cli, ux, orchestrator, zellij, phase-6, refactor]
timestamp: 2026-07-27
---

# ADR-0023 — A unified `ragent` CLI (task subcommands) over flat per-app entry points

## Context and problem statement

ragent's human-facing surface had grown into flat, separately-named flake apps:
`#workspace` (the TUI), `#serve` (task reports), `#orchestrate` (async review),
`#zellij` (session management), `#forgejo-local` (dev forge). Flat names don't
compose and don't communicate the shape of the tool: a person couldn't see that
these are all *things you do with a task*. Worse, `#zellij` leaked the
*implementation* (the session manager happens to be Zellij) as a top-level verb.
The Python rewrite (ADR-0022) also made a Python-hosted subcommand CLI natural —
the orchestrator is already Python.

## Decision

**Expose one human-facing binary, `ragent`, with subcommands grouped under `task`:**

| Command | Does | Was |
|---|---|---|
| `ragent task window <project> [name]` | launch/attach the two-side TUI workspace | `#workspace` |
| `ragent task orchestrate <project> <name> <prompt>` | async: confined agent → review (PR) | `#orchestrate` |
| `ragent task review [clone]` | serve the per-task HTML reports | `#serve` |
| `ragent task list` | list ragent sessions | `#zellij list-sessions` |
| `ragent task attach <name>` | attach to a session (resolves `ragent-<name>`) | `#zellij attach` |
| `ragent task kill <name>` | kill a session | `#zellij delete-session` |

- **Flake:** `apps.default = ragent`; thin `apps.task-window` / `task-orchestrate` /
  `task-review` aliases so `nix run .#task-<x> -- …` still works. The flat
  `workspace`/`serve`/`orchestrate` apps and the standalone `zellij` **package** are
  dropped (session ops fold into `task list|attach|kill`).
- **Naming:** `window` (a task's hands-on window), `orchestrate` (drive the async
  loop), `review` (serve for review); the session verbs are the `list`/`attach`/`kill`
  a user already knows, now *scoped under `task`* instead of a top-level `#zellij`.
  The session manager being Zellij is an implementation detail, no longer a verb.
- **Implementation:** stdlib `argparse` (no dependency), one closure carrying the TUI
  stack + the four agents + python3 + git; `orchestrate` calls into `orchestrator.py`.

**The CLI is a different vocabulary from the adapter superset — on purpose.** The
`ragent` CLI is what a **human** types; the 9 adapter verbs (ADR-0022:
ping/capabilities/init/push/handover/status/merge/examine/reply) are the
**orchestrator's internal SPI** for talking to a forge. One `ragent task orchestrate`
fans out to ~9 adapter verb calls. A human never types `handover` or `examine`; a
forge adapter never sees `window` or `review`. Two audiences, two vocabularies (the
coffee-machine's buttons vs. the machine's internal driver interface) — conflating
them would leak forge-think into the human surface and vice-versa.

## Consequences

### Positive
- A composable, discoverable surface: `ragent task <tab>` shows the whole shape.
- Session management folds in without a leaked tool name (`#zellij` is gone).
- Python-hosted, so subcommands share code with the orchestrator (ADR-0022).
- Room to grow: future groups (e.g. `ragent forge …`) slot in without new binaries.

### Negative / trade-offs
- `nix run .#workspace` muscle memory breaks — mitigated by the `task-window` alias
  and updated docs/README/template.
- Nested argparse subcommands are marginally more boilerplate than flat apps.

## Alternatives considered
- **Keep the flat apps** — rejected: doesn't compose or communicate the shape, and
  leaks `#zellij` as a top-level verb.
- **Verb-first, no `task` group** (`ragent window`, `ragent orchestrate`) — rejected:
  `task` names the noun everything here operates on and leaves room for other groups.
- **Multiple binaries** — rejected: one entry point is more discoverable and shares
  one closure.

## Links
- [ADR-0022 — Python adapters, verb superset + capabilities](0022-python-adapters-verb-superset-capabilities.md)
  (companion: the orchestrator's internal SPI, the *other* vocabulary)
- [ADR-0005 — Zellij two-side workspace](0005-zellij-two-pane-layout.md) (now driven
  via `ragent task window` / session ops)
- [ADR-0018 — your-config-repo split](0018-split-your-config-repo.md) (`forgejo-local`
  moves out; the CLI stays)
- [Roadmap](../components/roadmap.md), `tools/ragent_cli.py`, `tools/orchestrator.py`
