---
type: component
id: COMP-architecture-overview
title: Architecture overview
description: The layered architecture of ragent — host, VM, jail, the two Zellij panes, the tooling layer, and the knowledge layer — and how the seed decisions fit together.
tags: [architecture, overview, zellij, jail, lima, nix]
timestamp: 2026-07-26
---

# Architecture overview

`ragent` is an open-source, forkable-per-project developer workspace that makes
AI-assisted coding efficient while preserving human oversight. This is the map;
the [decisions](../decisions/index.md) hold the "why" and the
[forward plan](forward-plan-phases-1-5.md) holds the "when."

## The layering

```
macOS / Windows host
└─ Lima Linux VM ...................... one long-lived guest, shared Nix store   [ADR-0004, ADR-0006]
   └─ Zellij workspace (KDL layout) ... two sides, each with a log pane          [ADR-0005]
      ├─ HUMAN side
      │  ├─ neovim + LSPs, lazygit ..... edits the project directory directly
      │  └─ observability pane ......... the tool in use
      └─ MACHINE side
         ├─ jail.nix / bubblewrap ...... rw bind mount to the PROJECT DIR ONLY   [ADR-0002]
         │  └─ coding agent ............ Claude Code / pi / opencode
         │     └─ shared CLIs on PATH ... git-surgeon, etc. (via the flake)      [ADR-0007]
         └─ observability pane ......... log tail(s)
```

Both sides work on the **same** project directory. The machine's access is
confined to that directory; `$HOME`, SSH keys, and secrets are excluded, and
cgroup caps bound blast radius. Isolation is enforced by the jail; **oversight**
is enforced by a git boundary — the agent proposes on a branch/worktree and the
human reviews diffs before anything lands ([ADR-0011](../decisions/0011-git-worktree-review-boundary.md)).

## The layers, and the decisions behind them

| Layer | What it is | Decisions |
|---|---|---|
| **VM** | Lima Linux guest (bubblewrap needs Linux) | [ADR-0004](../decisions/0004-lima-vm-layer.md), [ADR-0006](../decisions/0006-one-long-lived-vm-per-project-devshells.md) |
| **Confinement** | jail.nix wrapping bubblewrap; scoped bind mount | [ADR-0002](../decisions/0002-jail-nix-confinement.md) |
| **Oversight** | git branch/worktree review; secrets stay human-side | [ADR-0011](../decisions/0011-git-worktree-review-boundary.md) |
| **Workspace** | Zellij two-side layout + log panes | [ADR-0005](../decisions/0005-zellij-two-pane-layout.md) |
| **Tooling** | shared CLIs on `PATH` via the flake; `ragent` consumed as a flake input | [ADR-0007](../decisions/0007-shared-clis-on-path.md), [ADR-0003](../decisions/0003-consume-upstreams-as-flake-inputs.md) |
| **Knowledge** | OKF bundle + ADRs + HTML view | [ADR-0008](../decisions/0008-okf-adr-knowledge-capture.md), [knowledge-system](knowledge-system.md) |
| **Governance** | Apache-2.0, reference-don't-vendor, local-mirror hedge | [ADR-0001](../decisions/0001-apache-2.0-license.md), [ADR-0003](../decisions/0003-consume-upstreams-as-flake-inputs.md), [ADR-0010](../decisions/0010-local-mirror-resilience.md) |

## `ragent` as umbrella vs. as consumed input

The name `ragent` appears in two roles in the genesis conversation: (1) this
repository — the umbrella workspace/harness — and (2) a "global config repo …
consumed as a pinned flake input, not forked." For now this repo takes role (1):
it is the umbrella project, and per-project forks consume it as a **pinned flake
input** they compose and override, consistent with
[ADR-0003](../decisions/0003-consume-upstreams-as-flake-inputs.md). The
**intended end-state is the split**: a separate `ragent-config` repo (the shared
brain) that many project-workspaces consume as an input — deferred until the
global-vs-workspace boundary is clear, per
[ADR-0012](../decisions/0012-defer-global-config-split.md).

## Structure, and deviations from the bootstrap prompt

The repository follows the suggested structure in
[SESSION-0002](../sessions/0002-phase0-bootstrap-prompt.md) closely. Notable,
deliberate choices:

- **`genesis-transcript.json` (not `.md`).** The conversation was supplied as the
  raw Claude.ai JSON export, which is the most byte-faithful source. It is kept
  verbatim in `sessions/`, with a faithful rendered
  [`0001` session](../sessions/0001-genesis-architecture-conversation.md)
  alongside. This is a fidelity *gain*, not a structural deviation.
- **`THIRD_PARTY.md` added** next to `NOTICE` — the prompt suggested
  "`NOTICE`/`THIRD_PARTY`"; both exist, with `THIRD_PARTY.md` holding the
  auditable table and verification notes.
- **Per-directory `index.md`** — uses OKF's reserved directory-listing filename.

None of these rise to needing a standalone "deviations" ADR; they are recorded
here per the convention that deviations are justified in writing.

## What is built vs. planned

Phase 0 (this repo) is **scaffold + governance + knowledge + plan**. The runtime
architecture above (VM, jail, Zellij, agents) is **planned** and implemented
incrementally from [Phase 1 onward](forward-plan-phases-1-5.md). Nothing in this
repo has been run as a live jail or workspace yet — see the forward plan for the
first "it works" milestone.
