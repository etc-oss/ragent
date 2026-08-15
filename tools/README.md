# tools/

Host-side utilities for ragent — **stdlib Python + POSIX shell**, no third-party
packages. Split by *role*: Python for logic (CLI, orchestrator, adapters, renderers),
shell for process/launch plumbing.

## CLI + orchestration (Python)

- **`ragent_cli.py`** — the unified CLI: `ragent task <window|orchestrate|review|list|
  attach|kill>` (flake `apps.default`). [ADR-0023]
- **`orchestrator.py`** — the async loop: set up the clone → run the confined agent →
  push → open a PR → poll the review → feed notes back → merge, all bounded. Also the
  subscription usage-limit wait layer. [ADR-0020/0024/0026]
- **`adapters/`** — the review-transport SPI. `base.py` = the `ReviewAdapter` ABC (the
  9-verb contract + `capabilities`); `forgejo.py` implements it over stdlib `urllib`.
  [ADR-0022]

## Sandbox + workspace (shell)

- **`ragent-workspace.sh`** — launch/attach the two-pane Zellij TUI and set up the agent
  clone (branch `agent/<task>`) + the generated `spawn-agent.sh`. `RAGENT_SETUP_ONLY=1`
  does clone-only setup (used by the orchestrator). [ADR-0005/0016]
- **`ragent-confine.sh`** — run a jailed agent binary under cgroup caps (a transient
  `systemd-run --user` scope). [ADR-0015]
- **`confinement-test.sh`** — the negative-control probe (the 8/8 gate; runs in CI):
  proves the wall by what *doesn't* get through.

## Reports + docs (Python + shell)

- **`ragent-report.py`** — render a task's `.ragent/EXPLAIN.md` + the real diff to a
  self-contained HTML report (imports `okf_render` as a sibling). [ADR-0021]
- **`ragent-serve.sh`** — serve the reports over HTTP (`127.0.0.1` default; Tailscale
  opt-in via `RAGENT_SERVE_HOST`).
- **`okf_render.py`** — the OKF knowledge bundle → offline HTML view + graph visualizer.
  Stdlib only; `docs/html/` is generated — never hand-edit it.

## Resilience

- **`mirror-example.sh`** — a publishable template for the offline/local-mirror hedge
  ([ADR-0010]); the actual mirror stays out of the repo (`.gitignore` excludes `/mirror/`).

> **Layout note (for contributors).** These are flat by design at this size (~11 files).
> If the layer grows, the plan is to promote the Python into an importable `ragent`
> package (retiring the `sys.path` shims and the hyphenated script names) and group by
> *concern* — **not** by language. See the [architecture overview](../docs/knowledge/components/architecture-overview.md).
