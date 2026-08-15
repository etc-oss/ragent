---
type: decision
id: ADR-0027
title: The knowledge/docs format is the consumer's choice — ragent doesn't impose OKF+ADR
description: ragent uses OKF + ADRs for its OWN repository, but a project that consumes ragent is free to document and record decisions in any format (ADR-only, OKF, plain Markdown, Obsidian, Logseq, or none). ragent's tooling (okf_render) and conventions are internal; nothing in the consumed surface requires OKF. User-facing guides live in docs/guides/ as plain Markdown to model this.
status: accepted
date: 2026-08-15
tags: [decoupling, docs, okf, adr, conventions, consumer, template]
timestamp: 2026-08-15
---

# ADR-0027 — The knowledge/docs format is the consumer's choice

## Context and problem statement

ragent records its own decisions as **ADRs** in an **OKF** knowledge bundle
([ADR-0008](0008-okf-adr-knowledge-capture.md)) rendered by `tools/okf_render.py`.
That is a strong, opinionated convention — good for *this* repo. But a project that
**consumes** ragent (as a pinned flake input, [ADR-0019](0019-per-project-forking-and-dependencies.md))
should not feel forced to adopt OKF or the ADR process for *its* documentation. The
template links ragent's ADRs as *rationale*, which can read as a mandate; it isn't
one, and that should be explicit.

## Decision

**ragent's knowledge conventions (OKF + ADR + `okf_render`) apply to ragent's own
repository only. A consuming project may use any format it likes** — ADR-only, OKF,
plain Markdown, a wiki, Obsidian/Logseq, or nothing at all. Concretely:

- **No consumed surface requires OKF.** `mkWorkspace`, the CLI, the orchestrator, and
  the adapters don't read or produce OKF; `okf_render` is an *internal* tool for
  ragent's own `docs/knowledge/`. A consumer never has to run it.
- **The agent-facing convention stays format-agnostic.** The template `AGENTS.md`
  asks an agent to leave a short `.ragent/EXPLAIN.md` — that's plain Markdown prose,
  not OKF, and it feeds the served report ([ADR-0021](0021-per-task-explanatory-report.md))
  regardless of how the project records its own decisions.
- **ragent's own user-facing guides are plain Markdown** (`docs/guides/`), separate
  from the OKF bundle — modelling that how-tos don't need OKF either.
- **The template says so.** Its `README`/`AGENTS.md` note that recording decisions is
  encouraged but the *format is yours*; ragent's ADR links are "here's why we chose
  X," not "you must document like this."

## Consequences

### Positive
- Lower adoption friction: teams keep their existing docs habits.
- Honest separation: ragent stays opinionated for itself without colonising consumers.
- The OKF bundle remains ragent's internal source of truth, undiluted.

### Negative / trade-offs
- Two doc "modes" in this repo (the OKF `docs/knowledge/` bundle + plain-Markdown
  `docs/guides/`); intentional, and each is signposted.
- Consumers who *want* an OKF-style bundle get no scaffolding for it here (they can
  still copy `okf_render.py` — it's Apache-2.0 and dependency-light — but it isn't a
  supported product surface).

## Alternatives considered
- **Impose OKF+ADR on consumers** — rejected: needless friction; not our place.
- **Make ragent's own knowledge format pluggable** — rejected as premature: ragent
  benefits from one opinionated internal convention; this ADR is about the *consumer*
  boundary, not ragent's internals.

## Links
- [ADR-0008 — OKF + ADR for knowledge capture](0008-okf-adr-knowledge-capture.md) (ragent's own choice)
- [ADR-0019 — Per-project forking & dependencies](0019-per-project-forking-and-dependencies.md)
- [ADR-0021 — Per-task explanatory report](0021-per-task-explanatory-report.md) (the format-agnostic EXPLAIN.md)
- `docs/guides/` (plain-Markdown how-tos), `templates/default/`
