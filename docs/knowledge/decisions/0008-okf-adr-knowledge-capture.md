---
type: decision
id: ADR-0008
title: OKF + ADR for knowledge capture
description: Knowledge is captured as an OKF bundle of Markdown+frontmatter concepts; ADRs are decision-type concepts with MADR bodies; sessions are verbatim.
status: accepted
date: 2026-07-26
tags: [knowledge, okf, adr, madr, documentation]
timestamp: 2026-07-26
---

# ADR-0008 — OKF + ADR for knowledge capture

## Context and problem statement

We want to capture prompts, decisions, and the project's evolutionary story in a
form any tool, model, or harness can load — and we want decision discipline.
"ADRs vs OKF" looks like a choice but is not: they are different layers. An ADR
is a *content genre* (context, decision, consequences). OKF (Google's **Open
Knowledge Format**) is a *packaging/interchange format*: a directory of Markdown
files with YAML frontmatter, cross-linked into a graph.

## Decision

Make `docs/knowledge/` an **OKF v0.1 bundle** and write **ADRs as OKF
`decision` concepts** with MADR-style bodies. Capture the raw chats as verbatim
`session` concepts, architecture as `component` concepts, and standards as
`convention` concepts, all cross-linked with Markdown links. Distill sessions
into decisions and link them; the session → decision graph *is* the evolutionary
story.

## Consequences

### Positive
- Portable: plain Markdown + YAML + links. "If you can `cat` a file, you can read
  it." Loads into any harness (reinforces `AGENTS.md`, not competes with it).
- The link graph captures intent and evolution, not just end-state docs.
- Apache-2.0 spec; low lock-in.

### Negative / trade-offs
- OKF is **v0.1 and will move** (v0.2 already renames some provenance fields).
  Mitigation: don't over-engineer tooling around it — it bottoms out in Markdown,
  so churn costs little. See [knowledge-format convention](../conventions/knowledge-format.md).
- Requires ongoing discipline to keep concepts linked and current.

## Alternatives considered
- **ADRs alone (loose Markdown)** — good genre, no interchange packaging or graph.
- **A wiki/database/knowledge tool** — not portable, and over-engineered for a
  v0.1 spec and a young project.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- [Knowledge-format convention](../conventions/knowledge-format.md)
- [ADR-process convention](../conventions/adr-process.md)
- [Knowledge-system component](../components/knowledge-system.md)
- OKF: <https://github.com/GoogleCloudPlatform/knowledge-catalog>
