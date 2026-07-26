---
type: convention
id: CONV-adr-process
title: ADR process (MADR-style decisions)
description: How architecture decisions are recorded as OKF decision concepts using a lightweight MADR-style body.
tags: [adr, madr, decision, convention]
timestamp: 2026-07-26
sources:
  - https://adr.github.io/madr/
---

# ADR process (MADR-style decisions)

Every non-trivial decision is recorded as a `type: decision` concept in
`decisions/`. An ADR is a *content genre* (context → decision → consequences);
OKF is the *packaging*. We write ADRs **as** OKF concepts so any harness can
walk them. See [ADR-0008](../decisions/0008-okf-adr-knowledge-capture.md) for
why the two compose rather than compete.

## When to write one

- A choice with lasting consequences (a dependency, a boundary, a format).
- Any deviation from the suggested repository structure in the bootstrap prompt
  (the prompt explicitly asks that deviations be justified in an ADR).
- Superseding an earlier decision — write a new ADR; do not silently edit the
  old one.

## Body template (MADR, trimmed)

```markdown
## Context and problem statement
What forces are at play? What are we deciding and why now?

## Decision
The choice, stated plainly.

## Consequences
### Positive
- ...
### Negative / trade-offs
- ... (be honest — every real decision has these)

## Alternatives considered
- Option — why not.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- Related ADRs.
```

Keep it short. MADR is short by design. The depth belongs in the reasoning, not
the word count.

## Rules

1. **Frontmatter** per [knowledge-format](knowledge-format.md): `type: decision`,
   an `id` like `ADR-0007`, a `status`, a `date`, `title`, `description`, `tags`.
2. **Status lifecycle:** `proposed` → `accepted` → (later) `superseded` /
   `deprecated`. Use `supersedes` / `superseded-by` to link lineage.
3. **Link back to the session** that produced the decision. That link graph is
   the project's evolutionary story.
4. **Number monotonically** (`0001`, `0002`, …). Never renumber.
5. Record the **negative** consequences too. An ADR with only upsides is a
   marketing page, not a decision record.
