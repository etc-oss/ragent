---
type: component
id: COMP-harness-efficiency
title: Orchestration & harness efficiency — does the sandbox make agents worse?
description: An honest evaluation of whether confining and orchestrating a coding agent (Claude Code, pi, opencode, crush) degrades it versus running it natively. The core — model, agentic loop, tools — is untouched; four deliberate trade-offs (no mid-task steering, bounded reach, native extensions, stateless re-prompting) are named with their mitigations, and the two paths (interactive TUI vs. async orchestrate) are matched to task shape.
tags: [orchestration, efficiency, harness, sandbox, claude-code, pi, trade-offs, agentConfig]
timestamp: 2026-08-15
---

# Orchestration & harness efficiency

A fair question before you trust ragent with real work: it wraps every agent in
**confinement** (bubblewrap), a **disposable clone**, a **non-interactive** invocation
(`claude -p … --dangerously-skip-permissions` and the equivalents), a small **prompt
suffix** (write `EXPLAIN.md`, commit), and a **bounded re-prompting loop**. Does all of
that make Claude Code / pi *worse* than running them natively in a terminal?

## Short answer: the core is untouched

The agent's **model, agentic loop, and tools are exactly what they'd be natively.**

- `-p` (headless) is **not a degraded mode** — it runs the full agentic loop (tool use,
  edits, reasoning) and prints the final result instead of holding an interactive
  session. Same model, same capabilities.
- `--dangerously-skip-permissions` *removes* friction (no permission prompts) — which is
  **safe precisely because the agent is confined**: its blast radius is the clone.
- **Bubblewrap adds ≈ zero runtime overhead** — it's Linux namespaces, not
  virtualization. The only compute knob is the cgroup cap ([ADR-0015](../decisions/0015-cgroup-caps-systemd-run.md)),
  and its defaults are generous (a mis-set cap could throttle, but that's tunable, not
  inherent).

So ragent does **not** make the agent "dumber." What it does is make four **deliberate
trade-offs** — each a conscious exchange for safety or boundedness, each with a
mitigation or an existing escape hatch.

## The four trade-offs

| # | Trade-off | Why it exists | Mitigation / escape |
|---|---|---|---|
| 1 | **No mid-task steering.** `-p` runs to completion, so the agent can't ask a clarifying question mid-task — it commits to an interpretation. | Orchestration *is* autonomy; a headless run has no human in the loop until the PR. | For ambiguous / exploratory work, use the **interactive TUI** (`ragent task window`) where you steer live. `orchestrate` is for well-scoped tasks. |
| 2 | **Bounded reach.** The agent sees the **project dir only** — not another repo, not `~/.config`, not arbitrary system paths. | This is the whole point of confinement ([ADR-0002](../decisions/0002-jail-nix-confinement.md)): the real tree, keys, and secrets stay outside. | `projectTools` adds the CLIs a task legitimately needs onto the sandbox PATH ([ADR-0019](../decisions/0019-per-project-forking-and-dependencies.md)). Genuinely cross-repo work is an intended non-goal of a single confined task. |
| 3 | **Native extensions aren't guaranteed.** MCP servers / skills that need out-of-sandbox processes or network may not work inside the sandbox. The guaranteed floor is **CLIs-on-PATH + `AGENTS.md`** ([ADR-0007](../decisions/0007-shared-clis-on-path.md)). | The portable core is the lowest common denominator across four agents, on purpose — so the orchestrator stays agent-agnostic. | **`agentConfig`** (roadmapped) opts each agent into its *native* strengths per project — Claude Code's skills/MCP, pi's conventions — layered on top of the floor. This is the real answer for power-users who feel the gap. See [roadmap](roadmap.md). |
| 4 | **Stateless re-prompting.** Each 6b revision is a fresh `-p` run that re-reads context, vs. a warm interactive session that retains it. | The loop is **stateless and bounded** by design ([ADR-0024](../decisions/0024-human-paced-bounded-review-loop.md)) — that's what makes it resumable and safe to cap. | Modern agents re-orient from a clone cheaply, and revisions are few (`max_iterations` default 6). The cost is real but small; the boundedness is worth it. |

## Two paths — match the tool to the task

ragent gives you **both** the interactive and the orchestrated path over the *same*
confinement and the *same* human gate. They're not competitors; they suit different work:

| | Interactive TUI (`ragent task window`) | Async orchestrate (`ragent task orchestrate`) |
|---|---|---|
| **Best for** | ambiguous, exploratory, high-touch work | well-scoped, self-contained tasks |
| **Steering** | live, mid-task | at the PR (review → revise → merge) |
| **Context** | warm session | fresh per revision |
| **Native features** | drive them by hand | limited to the floor (until `agentConfig`) |
| **Oversight** | you watch the pane | review asynchronously, when you're ready |

## Verdict

For its target — **well-scoped, autonomous tasks reviewed asynchronously** — orchestration is
efficient: the agent runs at full model capability with only a tiny prompt suffix and a
few bounded revisions of overhead. The trade-offs it makes are **interactivity, reach,
and native-extension strength** — all conscious, all with a mitigation (`projectTools`
now, `agentConfig` next) or an escape hatch (the interactive TUI for hands-on work).
Confining and orchestrating an agent costs you *specific, named things*; it does not cost
you the agent's intelligence.

## Links
- [Architecture overview & file map](architecture-overview.md) — the two halves this
  evaluates.
- [Roadmap](roadmap.md) — `agentConfig` (trade-off #3's real fix), local models.
- [ADR-0007 — Shared CLIs on PATH](../decisions/0007-shared-clis-on-path.md) (the floor),
  [ADR-0024 — Human-paced bounded loop](../decisions/0024-human-paced-bounded-review-loop.md) (trade-off #4),
  [ADR-0002 — jail.nix confinement](../decisions/0002-jail-nix-confinement.md) (trade-off #2).
