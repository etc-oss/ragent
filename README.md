# ragent

An open-source, forkable-per-project developer workspace that makes AI-assisted
coding **efficient** while preserving **human oversight**.

Two sides share one project directory inside a terminal workspace:

- **HUMAN** — neovim + LSPs + lazygit, with an observability pane for the tool in
  use.
- **MACHINE** — coding agents (Claude Code, pi, opencode) running **confined**
  via [`jail.nix`](https://git.sr.ht/~alexdavid/jail.nix) (bubblewrap) inside a
  [Lima](https://github.com/lima-vm/lima) Linux VM, with a log pane.

The machine side gets a read-write bind mount to the **project directory only** —
`$HOME`, SSH keys, and secrets are excluded, and cgroup caps bound blast radius.
Shared CLI tools go on `PATH` via the flake so every agent can call them through
bash. Upstreams are consumed as **pinned flake inputs**, never vendored.

> **Status: Phase 0 (scaffold + governance + knowledge + plan) — complete.**
> This is an early, local-only scaffold. The runtime (VM, jail, Zellij, agents)
> is planned and built incrementally from Phase 1. Nothing here has been run as a
> live jail yet. See the roadmap below.

## Why this exists

The full rationale is captured in the project's own knowledge bundle, starting
with the verbatim [genesis conversation](docs/knowledge/sessions/0001-genesis-architecture-conversation.md)
and distilled into [Architecture Decision Records](docs/knowledge/decisions/index.md).
In short: a jail gives real confinement (plain Nix does not); a git
branch/worktree gives real oversight (a shared directory does not); and the one
tooling mechanism common to every agent is the shell + filesystem, so shared
capabilities are CLIs on `PATH`, not per-agent plugins.

## Architecture at a glance

```
macOS / Windows host
└─ Lima Linux VM (one long-lived guest, shared Nix store)
   └─ Zellij workspace (two sides, each with a log pane)
      ├─ HUMAN:   neovim + LSPs, lazygit
      └─ MACHINE: jail.nix/bubblewrap → agent → shared CLIs on PATH
                  (rw bind mount: PROJECT DIR ONLY)
```

See the [architecture overview](docs/knowledge/components/architecture-overview.md)
for the layer-by-layer map and the decisions behind each layer.

## Roadmap

Detailed plan (tasks, exit criteria, risks) in the
[forward plan](docs/knowledge/components/forward-plan-phases-1-5.md).

| Phase | Focus | Status |
|---|---|---|
| **0** | Scaffold, governance, knowledge system, plan | ✅ Complete |
| **1** | The jail, one agent (confined loop; dogfood the jail) | ✅ Core verified |
| **2** | The Zellij workspace (two sides + review boundary) | 🚧 In progress |
| **3** | The tooling layer (shared CLIs on PATH; project template) | ✅ Core verified |
| **4** | Observability + the 2nd/3rd agent | ⬜ Planned |
| **5** | Open-source hardening (CI, example, audit, release) | ⬜ Planned |

## Knowledge bundle

`docs/knowledge/` is an [OKF](https://github.com/GoogleCloudPlatform/knowledge-catalog)
bundle — Markdown + YAML frontmatter, cross-linked into a graph.

- Browse the source: [`docs/knowledge/index.md`](docs/knowledge/index.md)
- Generated offline HTML view + graph visualizer: `docs/html/` (build it with
  `python3 tools/okf_render.py`; open `docs/html/index.html`)

Coding agents should start at [`AGENTS.md`](AGENTS.md).

## Building the docs view

```sh
python3 tools/okf_render.py     # renders docs/knowledge/ -> docs/html/
```

No third-party Python packages required (standard library only). The HTML is
generated and must never be hand-edited.

## License & attribution

ragent's own code is licensed under [Apache-2.0](LICENSE)
([ADR-0001](docs/knowledge/decisions/0001-apache-2.0-license.md)). It
**references** upstreams as pinned flake inputs and does not vendor their code;
each remains under its own license. See [`NOTICE`](NOTICE) and
[`THIRD_PARTY.md`](THIRD_PARTY.md) for full, verified attribution — including
that `jail.nix` is GPL-3.0 and why referencing (not vendoring) keeps this repo's
Apache-2.0 umbrella clean.

Prior art studied and credited: [jailed-agents](https://github.com/andersonjoseph/jailed-agents),
[sandnix](https://github.com/srid/sandnix), and the
[Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog).
