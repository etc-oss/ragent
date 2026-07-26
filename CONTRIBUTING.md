# Contributing to ragent

ragent is an open-source, forkable AI-coding workspace: confined agents (jail.nix)
with human oversight, on Zellij + Lima. Contributions are welcome.

## Ground rules (from the knowledge bundle)

- **Read [AGENTS.md](AGENTS.md) first** — it points at the knowledge bundle and
  the conventions below.
- **Record decisions as ADRs** ([ADR process](docs/knowledge/conventions/adr-process.md))
  and link each to the session that produced it. Justify structure deviations in
  an ADR.
- **Reference, don't vendor** upstreams — pinned flake inputs, never copied
  ([ADR-0003](docs/knowledge/decisions/0003-consume-upstreams-as-flake-inputs.md)).
  jail.nix is GPL-3.0; do not copy it in.
- **Sessions are verbatim** — never paraphrase a captured chat/prompt
  ([verbatim-sessions](docs/knowledge/conventions/verbatim-sessions.md)).
- **`docs/html/` is generated** — edit `docs/knowledge/`, then run
  `python3 tools/okf_render.py`. Never hand-edit the HTML.

## Dev setup

- Docs + tooling on any host (incl. macOS): `nix develop` gives Python + git.
  Render the knowledge view with `python3 tools/okf_render.py`.
- The jail and workspace need **Linux** (bubblewrap): use the Lima guest
  (`lima/ragent.yaml`) — see the README's "Try the workspace".

## Before you open a PR

- `nix flake check` passes (it verifies `docs/html/` is in sync and builds the
  key Linux derivations).
- If you changed `docs/knowledge/`, regenerate `docs/html/` and commit both.
- If you changed the jail/workspace, run the in-guest checks:
  `tools/confinement-test.sh` (must stay green) and a workspace launch.
- Adding an upstream? Add it to `THIRD_PARTY.md` with its **verified** license,
  and pin it as a flake input (or a `flake=false` source), never vendored.

## Where things live

| Area | Path |
|---|---|
| Cross-harness entrypoint | `AGENTS.md`, `CLAUDE.md` |
| Architecture + forward plan | `docs/knowledge/components/` |
| Decisions (ADRs) | `docs/knowledge/decisions/` |
| Conventions | `docs/knowledge/conventions/` |
| Flake / jail / tools / workspace | `flake.nix`, `tools/`, `workspace/`, `lima/` |
| Generated HTML view | `docs/html/` (never hand-edit) |
