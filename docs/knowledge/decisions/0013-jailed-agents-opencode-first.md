---
type: decision
id: ADR-0013
title: Build the jail on jailed-agents; prove confinement with a probe; opencode first
description: Consume jailed-agents as a pinned input, prove confinement with a jail.nix shell probe (not the agent), and lead with opencode; keep makeJailedClaudeCode as a verified dogfood target.
status: accepted
date: 2026-07-26
tags: [phase-1, jail, jailed-agents, opencode, claude-code]
timestamp: 2026-07-26
---

# ADR-0013 — Build the jail on jailed-agents; prove confinement with a probe; opencode first

## Context and problem statement

Phase 1 needs one coding agent running confined. `jailed-agents` already exports
`makeJailedOpencode`, `makeJailedClaudeCode`, `makeJailedPi`, … on top of jail.nix,
so building a jail from scratch would duplicate it. Two traps: (1) the Phase 1
exit gate is the **confinement negative-control test**, not which agent runs — so
the security proof should not depend on agent packaging; (2) Claude Code is the
**riskiest** of the agents to package (npm/bun2nix build, unfree, auth), so
leading with it risks stalling Phase 1 on packaging before confinement is proven.

## Decision

- **Consume `jailed-agents` as a pinned flake input** (it transitively pins
  jail.nix; we also pin jail.nix directly for the probe).
- **Prove confinement with a jail.nix probe:** `jailed-probe`, a jailed shell
  carrying the exact agent confinement profile (`mount-cwd`, `network`,
  zero-trust default). `tools/confinement-test.sh` drives it, so the security
  gate is independent of agent packaging.
- **Lead with opencode** (`makeJailedOpencode`) as the first real agent — it is
  jailed-agents' best-documented example and the lowest-friction path to the gate.
- **Keep `jailed-claude-code` as an explicit dogfood target** (Claude Code in its
  own jail — the recursive "it works" milestone), verified to build in-guest
  before it is relied on.

## Consequences

### Positive
- Reuses a maintained implementation; less to own.
- The confinement proof is decoupled from npm/bun packaging friction.
- Dogfooding remains the milestone we arrive at, not a blocker we lead with.

### Negative / trade-offs
- jailed-agents lacks cgroup caps ([ADR-0015](0015-cgroup-caps-systemd-run.md))
  and a secret pattern ([ADR-0014](0014-runtime-env-secret-forwarding.md)); we add both.
- The agent derivations use IFD (bun2nix), so they **build in the guest**, not by
  eval on macOS — verified: `jailed-probe` cross-evaluates on darwin; the agents
  do not.

## Alternatives considered
- **Build the jail from scratch on jail.nix** — more control, more work, and
  re-derives jailed-agents.
- **Lead with Claude Code** — risks burning Phase 1 on packaging before any
  confinement is demonstrated.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- [ADR-0002 — jail.nix for confinement](0002-jail-nix-confinement.md)
- [ADR-0014 — Runtime env secret forwarding](0014-runtime-env-secret-forwarding.md)
- [ADR-0015 — cgroup caps via systemd-run](0015-cgroup-caps-systemd-run.md)
- [Forward plan — Phase 1](../components/forward-plan-phases-1-5.md)
- `flake.nix`, `tools/confinement-test.sh`
