---
type: decision
id: ADR-0007
title: Shared CLIs on PATH over per-agent plugins
description: Shared capabilities are exposed as CLI tools on PATH via the flake — the one common denominator across all agents — rather than per-agent plugin/MCP mechanisms.
status: accepted
date: 2026-07-26
tags: [tooling, agents, cli, mcp, portability]
timestamp: 2026-07-26
---

# ADR-0007 — Shared CLIs on PATH over per-agent plugins

## Context and problem statement

We want "one standard way to install skills and extensions" across Claude Code,
pi, and opencode. But there is **no universal plugin ABI** across them. Claude
Code uses MCP servers, `SKILL.md` skills, and hooks; opencode has its own config
plus MCP; pi deliberately ships four built-in tools and extends via TypeScript,
skills, or prompt templates — and notably does **not** do MCP. So MCP, the
obvious candidate, is not a common denominator.

## Decision

Split "skills/extensions" into two kinds and prefer the portable one:

1. **Shared CLI tools** (e.g. git-surgeon) go on **`PATH` via the flake**. Every
   agent has a bash tool, so every agent can invoke them with zero per-agent
   adapter. This is the primary mechanism.
2. **Agent-native capabilities** (ADR-as-a-"skill", prompt conventions, commit
   rules) are expressed as plain files + prompt snippets at the lowest common
   denominator, reaching for a given agent's native skill/MCP format only when a
   capability genuinely cannot be a CLI or a file.

The actual common denominator across all three agents is **the shell and the
filesystem**.

## Consequences

### Positive
- One mechanism works everywhere via bash; no N-times per-agent adapter tax.
- Tools are independently testable and usable by humans too.

### Negative / trade-offs
- Some agent-native niceties go unused.
- CLIs must be well-behaved for non-interactive/programmatic use (clean exit
  codes, machine-readable output).

## Alternatives considered
- **MCP everywhere** — pi doesn't support it; not a common denominator.
- **Per-agent adapters for each capability** — multiplies maintenance by the
  number of agents and drifts as each agent's plugin model changes.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- [ADR-0003 — Consume upstreams as pinned flake inputs](0003-consume-upstreams-as-flake-inputs.md)
- [Forward plan — Phase 3](../components/forward-plan-phases-1-5.md)
