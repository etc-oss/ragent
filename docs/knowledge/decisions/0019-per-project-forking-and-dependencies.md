---
type: decision
id: ADR-0019
title: Per-project forking and dependency model (flake template + pinned input, not Makefiles)
description: A project adopts ragent via a per-project flake that consumes ragent as a pinned input; dependencies are pinned in flake.lock, not a Makefile. A Makefile is fine only as a thin task-runner delegating to nix.
status: accepted
date: 2026-07-26
tags: [forking, dependencies, flake, template, direnv, makefile]
timestamp: 2026-07-26
---

# ADR-0019 — Per-project forking and dependency model

## Context and problem statement

Each project should be able to "fork" the ragent workspace and manage its own
dependencies. Two questions arise: (1) how does a project adopt ragent, and
(2) should each project carry a `Makefile` for dependencies, or is there a better
mechanism?

## Decision

**Adopt ragent via a per-project flake that consumes ragent as a pinned input —
do not fork ragent, and do not manage dependencies with a Makefile.**

1. **Scaffold** a project workspace from the template (ADR-0007 / the `templates/`
   dir): `nix flake init -t <ragent>#default`. That drops a small `flake.nix` with
   `inputs.ragent.url = …` and a `devShell`/`workspace` app composed from ragent.
2. **Dependencies are pinned in `flake.lock`**, by content hash — reproducible,
   offline-capable (ADR-0010), and updated deliberately with `nix flake update`.
   This is the dependency manager. A `Makefile` is **not**.
3. **Auto-load** the environment with `direnv` (`echo "use flake" > .envrc`) or
   `nix develop` — tools appear on entering the directory.
4. **Personal/global config** (agent choice, extra tools, theme) lives in a config
   repo like `your-config-repo` that also consumes ragent as an input
   ([ADR-0018](0018-split-your-config-repo.md)); a project can consume that instead
   of ragent directly to inherit personal defaults.

**A per-project `Makefile` is acceptable only as a thin task-runner** — human-
friendly aliases that *delegate to nix* (e.g. `make review` → `nix run .#workspace`,
`make agent` → `.ragent/launch-agent.sh`). It must never be the dependency
mechanism (no `apt install`, no `go get`, no version pinning in `make`); that is
`flake.lock`'s job.

## Implemented (2026-07-27)

ragent exposes `lib.<system>.mkWorkspace { projectTools ? [ ], defaultAgent ? … }`.
A project's `flake.nix` (from `templates/default`) sets `projectTools` to its own
stack — e.g. `[ (pkgs.python3.withPackages (ps: [ ps.pytest ])) ]`. Those tools
join `sharedTools` on the **confined agent's in-jail PATH** (and the pane PATH and
devshell), so the agent can build and test the project *itself, inside the jail*.
Verified end to end: a jailed Claude Code with `projectTools = [python+pytest]` ran
`pytest -q` inside its jail and reported "2 passed" — closing the limitation the
first real loop surfaced (the jail previously had no project runtime). The
`templates/default/Makefile` is the thin task-runner (`make workspace|review|test`,
each delegating to `nix`), explicitly not the dependency manager.

## Consequences

### Positive
- One reproducible dependency mechanism (`flake.lock`), consistent with
  reference-don't-vendor (ADR-0003) and offline resilience (ADR-0010).
- Projects update ragent by bumping one pinned input — no fork drift.
- `direnv`/`nix develop` gives zero-friction, per-project environments.
- A task-runner Makefile stays optional and ergonomic, not load-bearing.

### Negative / trade-offs
- Requires Nix + flakes on the machine (already required for the jail/workspace).
- Contributors used to `make install` must learn the flake/direnv flow (a short
  README section covers it).

## Alternatives considered
- **A Makefile per project for dependencies** — non-reproducible (relies on
  ambient/system package managers), no content pinning, drifts across machines.
  Rejected as the dependency mechanism; allowed only as a nix-delegating task runner.
- **Fork ragent per project** — drifts from upstream, breaks updatability
  (ADR-0003). Rejected.
- **A monorepo of all projects** — couples unrelated projects; a per-project flake
  consuming a shared input is looser and more portable.

## Links
- [ADR-0003 — Consume upstreams as pinned flake inputs](0003-consume-upstreams-as-flake-inputs.md)
- [ADR-0007 — Shared CLIs on PATH](0007-shared-clis-on-path.md)
- [ADR-0010 — Local-mirror resilience](0010-local-mirror-resilience.md)
- [ADR-0018 — Split personal config into your-config-repo](0018-split-your-config-repo.md)
- `templates/default/`
