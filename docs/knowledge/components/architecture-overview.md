---
type: component
id: COMP-architecture-overview
title: Architecture overview & file map
description: The layered architecture of ragent as built through Phase 6 — host, Lima VM, the bubblewrap sandbox, the two-side workspace, the host-side orchestrator + review adapters, and the knowledge layer — plus a map of the repository's files.
tags: [architecture, overview, file-map, sandbox, orchestrator, adapters, zellij, lima, nix]
timestamp: 2026-08-15
---

# Architecture overview & file map

`ragent` runs coding agents in a **safe sandbox** with **human oversight**, consumed
per-project as a pinned flake input. This is the map; the
[decisions](../decisions/index.md) hold the "why". Everything below is **built and
verified locally** (Phases 0–6).

## Two halves

ragent is two cooperating halves that share one project directory:

1. **The interactive workspace** — a two-pane Zellij TUI. You edit on the HUMAN side
   (neovim + LSP + lazygit); a confined agent works in a disposable clone on the
   MACHINE side. You review the diff and merge. Entry: `ragent task window`.
2. **The async orchestrator** — host-side, *outside* the sandbox. It sets up the clone,
   runs the confined agent, then pushes and opens a **PR** on a forge and drives a
   bounded, human-paced review loop until you approve. Entry: `ragent task orchestrate`.

Both are the same confinement + the same human gate, from two angles: hands-on vs.
review-on-the-go. Wondering whether wrapping the agent this way costs you anything? See
[Orchestration & harness efficiency](orchestration-and-harness-efficiency.md) — the
honest accounting of what confinement + orchestration trade away (and what they don't).

## The layered runtime

```
macOS / Windows host
└─ Lima Linux VM ....................... one long-lived guest, shared Nix store   [ADR-0004/0006]
   │
   ├─ Zellij workspace (KDL layout) .... the interactive TUI                       [ADR-0005]
   │  ├─ HUMAN pane:  neovim + LSPs, lazygit — edits the project tree directly
   │  └─ MACHINE pane: a shell in the agent CLONE (branch agent/<task>)            [ADR-0016]
   │     └─ jail.nix / bubblewrap ...... rw bind = the PROJECT DIR ONLY            [ADR-0002]
   │        └─ coding agent ............ opencode / Claude Code / pi / crush
   │           └─ shared CLIs on PATH .. git-surgeon, ripgrep, fd, jq             [ADR-0007]
   │
   └─ Orchestrator (host-side, OUTSIDE the sandbox) ...... holds the forge token   [ADR-0011/0014]
      ├─ sets up the clone + runs the confined agent (commits in the clone)
      ├─ push + open PR  ──►  Forge (Forgejo) ──► review from a phone
      └─ poll status → feed review notes back → agent revises → merge (bounded)    [ADR-0024]
```

**Load-bearing boundaries:** the agent's rw access is the project dir *only*
(`$HOME`, keys, secrets excluded; cgroup caps bound blast radius); the agent only
*commits* in its clone and never holds the forge token; nothing lands without a human
merge/approve. Full model in [`SECURITY.md`](../../../SECURITY.md).

## Components → files → decisions

| Component | Where | Decisions |
|---|---|---|
| **Sandbox** (bubblewrap via jail.nix; cgroup caps) | `flake.nix` (`mkAgents`, `agentBaseOptions`), `tools/ragent-confine.sh` | [ADR-0002](../decisions/0002-jail-nix-confinement.md), [ADR-0015](../decisions/0015-cgroup-caps-systemd-run.md) |
| **Agents** (4, jailed identically; API-key or subscription Claude) | `flake.nix` (`mkAgents`) | [ADR-0013](../decisions/0013-jailed-agents-opencode-first.md), [ADR-0025](../decisions/0025-jailed-claude-subscription-auth.md), [ADR-0026](../decisions/0026-subscription-usage-limit-wait.md) |
| **Workspace** (two-pane TUI + clone boundary) | `tools/ragent-workspace.sh`, `workspace/*.kdl` | [ADR-0005](../decisions/0005-zellij-two-pane-layout.md), [ADR-0016](../decisions/0016-agent-clone-not-worktree.md) |
| **CLI** (`ragent task …`) | `tools/ragent/cli.py`; flake `apps.default` | [ADR-0023](../decisions/0023-unified-ragent-cli.md) |
| **Orchestrator** (async loop, bounded) | `tools/ragent/orchestrator.py` | [ADR-0020](../decisions/0020-review-transport-adapters.md), [ADR-0024](../decisions/0024-human-paced-bounded-review-loop.md) |
| **Review adapters** (9-verb superset + capabilities) | `tools/ragent/adapters/` (`base.py`, `forgejo.py`) | [ADR-0022](../decisions/0022-python-adapters-verb-superset-capabilities.md) |
| **Served report** (EXPLAIN.md + diff → HTML) | `tools/ragent-report.py`, `tools/ragent-serve.sh` | [ADR-0021](../decisions/0021-per-task-explanatory-report.md) |
| **Shared tools** (CLIs on PATH) | `flake.nix` (`sharedTools`); `git-surgeon` input | [ADR-0007](../decisions/0007-shared-clis-on-path.md), [ADR-0017](../decisions/0017-pin-git-surgeon.md) |
| **Knowledge** (OKF bundle + ADRs + HTML) | `docs/knowledge/`, `tools/okf_render.py` | [ADR-0008](../decisions/0008-okf-adr-knowledge-capture.md), [ADR-0027](../decisions/0027-knowledge-format-is-the-consumers-choice.md) |
| **Consumption** (flake input; per-project) | `templates/default/`, `flake.nix` (`lib.mkWorkspace`) | [ADR-0003](../decisions/0003-consume-upstreams-as-flake-inputs.md), [ADR-0019](../decisions/0019-per-project-forking-and-dependencies.md) |

## File map

```
ragent/
├─ flake.nix                     # the core: agents, sandbox profile, mkWorkspace, apps (CLI + aliases)
├─ AGENTS.md / CLAUDE.md         # agent entrypoint (CLAUDE.md defers to AGENTS.md)
├─ README.md · SECURITY.md · CONTRIBUTING.md · CODE_OF_CONDUCT.md · CHANGELOG.md
├─ LICENSE · NOTICE · THIRD_PARTY.md   # Apache-2.0 + CC0 fallback; reference-don't-vendor attribution
│
├─ tools/                        # host-side utilities (stdlib Python + POSIX shell)
│  ├─ ragent/                    #   the runtime PACKAGE — import as `ragent` (python3 -m ragent.cli)
│  │  ├─ cli.py                  #     `ragent task <window|orchestrate|review|list|attach|kill>`
│  │  ├─ orchestrator.py         #     the async loop: setup → agent → push → PR → bounded review
│  │  └─ adapters/               #     review-transport SPI: base.py (ABC) + forgejo.py (urllib)
│  ├─ ragent-workspace.sh        #   launch/attach the two-pane TUI + set up the clone
│  ├─ ragent-confine.sh          #   run a jailed agent under cgroup caps (systemd scope)
│  ├─ ragent-report.py           #   per-task HTML report — standalone; imports okf_render
│  ├─ ragent-serve.sh            #   serve the reports over HTTP (localhost / Tailscale)
│  ├─ okf_render.py              #   knowledge bundle → offline HTML (stdlib only)
│  └─ confinement-test.sh · mirror-example.sh   # the 8/8 confinement probe · offline-mirror template
│
├─ tests/                        # run without the sandbox (ephemeral Forgejo + stubs)
│  ├─ ephemeral_forge.py         #   throwaway Forgejo fixture (unique port, handle teardown)
│  ├─ test_forgejo_adapter.py    #   the 9 verbs + full review lifecycle
│  ├─ test_review_loop.py        #   6b mechanics + bounds (deterministic)
│  └─ test_limit_wait.py         #   usage-limit detector + bounded wait
│
├─ workspace/                    # Zellij KDL layout (a @bash@/@paneBin@ template) + themes
├─ templates/default/            # the per-project scaffold (`nix flake init -t …`)
├─ docs/
│  ├─ guides/                    # plain-Markdown how-tos (sandbox-agent, forgejo, troubleshooting)
│  ├─ knowledge/                 # the OKF bundle — SOURCE OF TRUTH
│  │  ├─ decisions/              #   ADRs (the "why")
│  │  ├─ components/             #   this doc, the roadmap, the transport design, …
│  │  ├─ sessions/               #   verbatim session records (never paraphrased)
│  │  └─ conventions/            #   the working rules
│  └─ html/                      # GENERATED from docs/knowledge/ by okf_render.py — never hand-edit
└─ .github/workflows/ci.yml      # flake build + confinement gate + Python suites + docs-sync
```

The **dev-forge harness** and **VM/deploy config** are deliberately *not* here — they
live in a personal config repo that consumes ragent
([ADR-0018](../decisions/0018-split-your-config-repo.md)); ragent keeps only an
ephemeral-forge test fixture.

## `ragent` as umbrella vs. consumed input

This repo is the **umbrella framework**. Personal/per-project config consumes it as a
**pinned flake input** it composes and overrides (`ragent.lib.<system>.mkWorkspace`),
never a fork — [ADR-0003](../decisions/0003-consume-upstreams-as-flake-inputs.md),
[ADR-0019](../decisions/0019-per-project-forking-and-dependencies.md). The personal
layer (VM config, dev forge, themes, default agent) lives in a consuming repo
([ADR-0018](../decisions/0018-split-your-config-repo.md)).

## Status

Phases 0–6 are **built and verified locally** (macOS host + Lima guest): confinement
gate 8/8, four sandboxed agents, the two-side workspace + clone boundary, the shared
tooling layer, and the async review loop (adapters + orchestrator + bounded loop) with
API-key or subscription auth. Next is 6c and the [roadmap](roadmap.md)'s "beyond".
