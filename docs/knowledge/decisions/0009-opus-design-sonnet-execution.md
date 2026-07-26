---
type: decision
id: ADR-0009
title: Opus-for-design / Sonnet-for-execution model split
description: Plan and design with Opus, execute build volume with Sonnet, delegate mechanical work to Haiku — while treating context hygiene as more decisive than model choice.
status: accepted
date: 2026-07-26
tags: [models, claude, workflow, opus, sonnet, haiku]
timestamp: 2026-07-26
---

# ADR-0009 — Opus-for-design / Sonnet-for-execution model split

## Context and problem statement

The build spans hard, ambiguous design work (Nix/bubblewrap sandbox, cross-agent
abstraction, licensing judgment) and a large volume of mechanical construction
(flake, KDL, configs, refactors). Using one model for everything is either
needlessly expensive or needlessly weak.

## Decision

Mix Claude models by task:

- **Opus 4.8** — planning and design: the sandbox design, cross-agent
  abstraction, licensing calls, gnarly debugging. (This Phase 0 bootstrap.)
- **Sonnet 5** — the coding workhorse for build volume: flake, KDL layout,
  configs, iteration. Most hours live here.
- **Haiku 4.5** — cheap mechanical work: formatting, boilerplate, log parsing.

## Consequences

### Positive
- Right capability at the right cost/latency for each task.
- A natural, recursive milestone: Claude Code runs on the host early, then
  dogfoods the jail by running *inside it* once it exists.

### Negative / trade-offs
- Requires discipline to switch models at the right boundaries.
- **Context hygiene beats model choice** for a config-heavy project: a tight
  `AGENTS.md` + a well-linked OKF bundle lifts any of these models more than
  swapping between them — which is why [ADR-0008](0008-okf-adr-knowledge-capture.md)
  is the same investment as this one.

## Alternatives considered
- **Single model throughout** — simpler but pays Opus prices for boilerplate or
  accepts weaker planning.
- **The Mythos tier (Fable 5, …)** — gated and adds nothing for infra/config
  work; out of scope.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- [ADR-0008 — OKF + ADR for knowledge capture](0008-okf-adr-knowledge-capture.md)
