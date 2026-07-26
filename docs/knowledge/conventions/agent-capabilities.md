---
type: convention
id: CONV-agent-capabilities
title: Agent capabilities — CLIs on PATH, or files
description: How ragent gives coding agents shared capabilities — CLI tools on the in-jail PATH (primary), and plain files + prompt snippets at the lowest common denominator (for the rest).
tags: [agents, capabilities, cli, skills, convention]
timestamp: 2026-07-26
---

# Agent capabilities — CLIs on PATH, or files

There is no universal plugin ABI across Claude Code, opencode, and pi
([ADR-0007](../decisions/0007-shared-clis-on-path.md)). The one thing every agent
shares is **the shell and the filesystem**. So ragent gives agents capabilities
two ways, in this order of preference:

## 1. Shared CLIs on the in-jail PATH (primary)

Put a capability on `PATH` as a CLI and every agent invokes it via bash, with no
per-agent adapter. This is `sharedTools` in `flake.nix`, added to each agent's
jail via `extraPkgs` (and to the human workspace shell):

- **git-surgeon** ([ADR-0017](../decisions/0017-pin-git-surgeon.md)) — surgical,
  non-interactive git for agents.
- **git, ripgrep, fd, jq** — the common denominators.

To add a shared CLI: add it to `sharedTools` in `flake.nix`; it appears on every
agent's in-jail PATH automatically. If it is a niche tool, pin it as a flake input
(reference, don't vendor — [ADR-0003](../decisions/0003-consume-upstreams-as-flake-inputs.md))
and record an ADR when the choice is notable.

## 2. Capabilities as files + prompt snippets (for the rest)

Anything that can't be a CLI — conventions, an ADR "skill", commit rules — is
expressed as **plain files + prompt snippets at the lowest common denominator**,
not each agent's native skill/MCP format. Reach for a native format only when a
capability genuinely can't be a CLI or a file.

Examples that already live as files/prompts:
- **This knowledge bundle** — agents read [`AGENTS.md`](../../../AGENTS.md) → the
  OKF concepts. The [ADR process](adr-process.md) (writing decisions as OKF
  concepts) is itself a "skill" expressed as files + conventions, not a plugin.
- **Commit conventions** — a prompt snippet plus git-surgeon usage, not a plugin.

## Why this order

CLIs are portable across every agent and testable by humans; files/prompts are the
universal fallback. Native per-agent skill/MCP formats are thin wrappers of last
resort — they multiply maintenance by the number of agents and drift as each
agent's plugin model changes ([ADR-0007](../decisions/0007-shared-clis-on-path.md)).
