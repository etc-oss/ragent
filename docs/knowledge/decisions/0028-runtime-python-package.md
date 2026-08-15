---
type: decision
id: ADR-0028
title: Promote the runtime Python into an importable `ragent` package
description: The CLI + orchestrator + adapters move into tools/ragent/ as an importable package with clean relative imports (retiring the sys.path shims); the flake app runs `python3 -m ragent.cli`. Standalone tools (okf_render.py, ragent-report.py, the shell launchers) stay flat. Grouping is by concern, not language.
status: accepted
date: 2026-08-15
tags: [tooling, python, packaging, refactor, structure]
timestamp: 2026-08-15
---

# ADR-0028 — Promote the runtime Python into an importable `ragent` package

## Context and problem statement

`tools/` grew a small tangle: `ragent_cli.py` imported `orchestrator.py` which imported
`adapters/`, all wired with `sys.path.insert(0, HERE)` shims, and `ragent-report.py`
carried a hyphen (so it can be *run* but never `import`ed). Flat is fine at ~11 files,
but the review-transport runtime is the part that will grow (more adapters, a future
`localModels` config), and the shims + hyphen-naming are friction for contributors.

## Decision

**Promote the runtime Python — the CLI, the orchestrator, and the adapters — into an
importable package `tools/ragent/`.** Everything else in `tools/` stays flat.

- **Package (`tools/ragent/`):** `cli.py`, `orchestrator.py`, `adapters/`
  (`base.py`, `forgejo.py`), `__init__.py`. Imports are **relative** — `from
  .orchestrator import orchestrate`, `from .adapters import load` — with no `sys.path`
  shims. The flake `apps.default` runs `python3 -m ragent.cli` with `tools/` on
  `PYTHONPATH`; tests import `from ragent.orchestrator import …`.
- **Flat (stay in `tools/`):** `okf_render.py` (the docs → HTML builder, referenced by
  a **stable path** across the README, CI, Makefile, and many ADRs — moving it would
  churn ~20 references); `ragent-report.py` (a leaf that only depends on `okf_render`,
  invoked by the generated `spawn-agent.sh` as a script); and the shell launchers
  (`ragent-workspace.sh`, `ragent-confine.sh`, `ragent-serve.sh`, `confinement-test.sh`,
  `mirror-example.sh`). `ragent-report.py` imports `okf_render` as a sibling (one small,
  justified path insert — the renderer is deliberately outside the package).

**Not language folders** (`shell/` + `python/`): language is the wrong axis — it splits
one *flow* across two dirs (e.g. `orchestrator.py` + `ragent-confine.sh` are one
"run the confined agent" story). Group by **concern**.

## Consequences

### Positive
- Clean, obvious imports; no `sys.path` shims; the package is the natural home for
  growth (GitLab/GitHub/SSH adapters, a `localModels` config).
- `python3 -m ragent.cli` is a conventional, discoverable entry point.

### Negative / trade-offs
- The flake app needs `PYTHONPATH=tools` + `-m` (a two-line change, done).
- `okf_render` sits *outside* the package (report imports it as a sibling) — a
  deliberate seam to keep the docs-build path stable, not an accident.

## Alternatives considered
- **Language folders (`shell/`/`python/`)** — rejected (splits one flow; wrong axis).
- **Move `okf_render` into the package too** — rejected for now: ~20 stable path
  references (README/CI/Makefile/ADRs) would churn for little gain; it's a standalone
  docs tool, not part of the review-transport runtime.
- **Leave it flat** — fine at this size, but the shims + hyphen-naming don't scale.

## Verification
The built flake app runs via `python3 -m ragent.cli`; all three Python suites
(`test_forgejo_adapter`, `test_review_loop`, `test_limit_wait`) pass importing
`from ragent…`; `nix flake check` green.

## Links
- [ADR-0023 — Unified ragent CLI](0023-unified-ragent-cli.md),
  [ADR-0022 — Python adapters + verb superset](0022-python-adapters-verb-superset-capabilities.md)
- [Architecture overview & file map](../components/architecture-overview.md), `tools/README.md`
