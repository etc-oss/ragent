---
type: decision
id: ADR-0014
title: Provider API key via runtime env forwarding; no credential dir in the jail
description: The LLM API key is forwarded into the jail at runtime via jail.nix fwd-env and never enters the Nix store; no credential-bearing config dir is bound into the jail.
status: accepted
date: 2026-07-26
tags: [phase-1, secrets, security, jail, credentials]
timestamp: 2026-07-26
---

# ADR-0014 — Provider API key via runtime env forwarding; no credential dir in the jail

## Context and problem statement

The jailed agent needs a provider API key inside the jail, but **the Nix store is
world-readable**. A key placed in a derivation (an `env = { … }` value, a baked
config file) leaks to every user of the store. Two failure modes to avoid:
(1) build-time secrets in the store; (2) binding a credential-bearing config dir
(`~/.claude`, `~/.claude.json`, `~/.config/<agent>/auth.json`) read-write into the
jail — which quietly re-imports the very secret the zero-trust jail excludes.

## Decision

- Forward the API key with jail.nix's **`fwd-env`** / **`try-fwd-env`**
  combinator. Confirmed from source: `fwd-env NAME` sets the jailed env to the
  runtime value `"$NAME"` (resolved when the agent runs), so the secret **never
  enters the derivation or the store**. The caller exports it per run.
- **Do not bind a credential-bearing config dir** into the jail. If an agent
  insists on file-based auth, bind only a minimal, secret-free config and inject
  the key by env.
- Keep push/deploy credentials entirely outside the jail (human side,
  [ADR-0011](0011-git-worktree-review-boundary.md)); only the LLM API key crosses
  the boundary.

## Consequences

### Positive
- The key is never persisted in the store; the jail's secret surface is one
  explicit env var.
- Auth becomes a single stated decision, not an accidental mount.

### Negative / trade-offs
- The caller must export the key each session (by design; `try-fwd-env` tolerates
  it being unset so the confinement test still runs).
- Agents that only support config-file auth need per-agent handling (a minimal
  injected config), tracked when such an agent is added.

## Alternatives considered
- **`env` in the derivation** — leaks the key to the world-readable store. Rejected.
- **Bind the agent's credential dir rw** — re-imports the excluded secret. Rejected.
- **A full secrets manager (agenix/sops)** — over-engineered for Phase 1; revisit
  if multiple secrets appear.

## Phase 1 finding (opencode)

Inspecting the agents' actual bwrap bind lists shows jailed-agents' builders bind
credential-bearing paths **read-write** into the jail — in direct tension with
this ADR:

- **opencode** binds `~/.local/share/opencode` (rw), where it persists auth.
- **Claude Code** binds `~/.claude` (rw) and `~/.claude.json` (rw) — and
  `~/.claude.json` is literally where Claude Code stores its credentials, so this
  is the tension in its sharpest form.

**Unresolved** (no real auth wired yet): when wiring an agent's auth, either
env-forward the provider key and drop/override the credential-dir bind, or
consciously accept that the agent's credentials live in the real home path.
Decide deliberately at that point, per agent.

## Resolved in the first real run (2026-07-27)

Wiring a real agent surfaced two integration gaps, both fixed in `flake.nix`:

1. **jailed-agents does not forward the provider key.** Its `commonJailOptions`
   (network/time-zone/no-new-session) omits any `fwd-env`, so a jailed agent sees
   no key and reports "Not logged in" even with a valid key in the environment.
   Fix: extend each agent's `baseJailOptions` with
   `try-fwd-env "ANTHROPIC_API_KEY"` / `"OPENAI_API_KEY"`, using jailed-agents' own
   jail instance (`ja.internals.jail.combinators`) so the combinators match its
   jail.nix. The key is still runtime-forwarded — never in the store.
2. **Claude Code needs `CLAUDE_CODE_SIMPLE=1`** to authenticate *strictly* with
   `ANTHROPIC_API_KEY` (otherwise it prefers OAuth/keychain, which don't exist in
   the jail). Baked in via `makeJailedClaudeCode { env = { CLAUDE_CODE_SIMPLE = "1"; }; }`.

With both, a jailed Claude Code authenticates and completes a real task
confined to its clone — verified end to end (edit → review → test → merge).
The credential-dir bind (`~/.claude.json`) is still present but unused for auth
(the env key takes precedence); dropping that bind is still open.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- [ADR-0002 — jail.nix for confinement](0002-jail-nix-confinement.md)
- [ADR-0011 — Git-worktree review boundary](0011-git-worktree-review-boundary.md)
- [ADR-0013 — Build the jail on jailed-agents](0013-jailed-agents-opencode-first.md)
- `flake.nix` (the `try-fwd-env "ANTHROPIC_API_KEY"` in the confinement profile)
