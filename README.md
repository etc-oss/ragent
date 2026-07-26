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

> **Status: Phases 0–5 built and verified locally** (macOS host + a Lima Linux
> guest); **local-only, nothing published.** The confinement gate (8/8), cgroup
> caps, four confined agents (opencode, Claude Code, pi, crush), the two-side
> workspace with a git-clone review boundary, the shared tooling layer, and the
> project template are all verified in-guest, and `nix flake check` passes there.
> Not yet wired into CI; a real agent *edit* still needs your provider key. See
> the [forward plan](docs/knowledge/components/forward-plan-phases-1-5.md) for the
> honest, per-item caveats.

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
| **4** | Observability + more agents (opencode, Claude Code, pi, crush) | ✅ Core verified |
| **5** | Open-source hardening (CI prepared, CONTRIBUTING, audit, VM guide) | ✅ Core (pre-publish) |

See also: [CONTRIBUTING](CONTRIBUTING.md) · [CHANGELOG](CHANGELOG.md) ·
[running ragent on a VM instead of the host](docs/knowledge/components/running-on-a-vm.md).

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

## Try the workspace (Linux guest)

The jail and workspace run on Linux. The concrete VM config (Lima / cloud /
NixOS) lives in a personal config repo that consumes ragent — e.g.
**your-config-repo** — not in the framework (see
[running on a VM](docs/knowledge/components/running-on-a-vm.md)).

```sh
# 1) one-time: a Nix-enabled Linux guest (user namespaces + cgroup delegation).
#    Its config lives in your config repo, e.g. your-config-repo's lima/ragent.yaml:
limactl start --name=ragent /path/to/your-config-repo/lima/ragent.yaml
limactl shell ragent

# 2) inside the guest, on a git project (this repo works):
cd /path/to/ragent
nix develop .#workspace                       # zellij, nvim(+LSP), lazygit, git-surgeon, rg, fd, jq, agents
./tools/ragent-workspace.sh "$PWD" mytask     # or, checkout-free: nix run .#workspace -- "$PWD" mytask
```

Then sanity-check at the terminal (the interactive parts that can't be verified
headless):

- **HUMAN tab** — neovim opens on the project; open a `.nix`/`.py`/`.sh` file and
  confirm an LSP attaches (`gd` = go-to-def, `K` = hover). The lazygit pane shows
  the repo.
- **MACHINE tab** — a shell in the agent **clone** (`…-agent-mytask`). Export a
  provider key (e.g. `ANTHROPIC_API_KEY`), run `./.ragent/launch-agent.sh`, and
  watch the log pane fill. The agent can only touch the clone.
- **Review** — from the HUMAN side: `git fetch <clone> agent/mytask` then
  `git diff <default>..FETCH_HEAD`; `git merge FETCH_HEAD` to accept, or ignore to
  discard. Nothing lands without this.
- **Ergonomics** — confirm truecolor, clipboard copy/paste, and that Zellij's
  keybindings don't collide with your terminal (avoid nesting tmux). These are the
  [ADR-0005](docs/knowledge/decisions/0005-zellij-two-pane-layout.md) papercuts.
- **Sessions / a "frozen" TUI** — a frozen or garbled screen is almost always a
  bad `TERM` (e.g. `dumb`, which `limactl shell` can pass through). The launcher
  now forces `xterm-256color`, but use a truecolor terminal (iTerm2 / kitty /
  WezTerm). Manage sessions independently of a launch:
  ```sh
  nix run .#zellij -- list-sessions
  nix run .#zellij -- attach ragent-mytask          # re-attach after Ctrl+o d
  nix run .#zellij -- kill-session ragent-mytask     # or delete-all-sessions --yes
  ```
  Re-running `ragent-workspace.sh` on the same task now **attaches** to an
  existing session instead of erroring.

## Forking ragent into another project

Don't fork the repo, and **don't manage dependencies with a Makefile.** Adopt
ragent as a **pinned flake input** so you get reproducible dependencies and can
update with a one-line bump ([ADR-0019](docs/knowledge/decisions/0019-per-project-forking-and-dependencies.md)):

```sh
cd my-project                      # a git repo
nix flake init -t <ragent>#default # drops a small flake.nix consuming ragent
echo "use flake" > .envrc && direnv allow   # optional: auto-load the env
nix develop                        # zellij, nvim, lazygit, git-surgeon, agents
nix run .#workspace -- "$PWD" mytask
```

- **Dependencies live in `flake.lock`** (content-pinned, offline-capable via
  [ADR-0010](docs/knowledge/decisions/0010-local-mirror-resilience.md)), updated
  deliberately with `nix flake update` — *not* in a Makefile.
- **A Makefile is fine only as a thin task-runner** that delegates to nix
  (`make review` → `nix run .#workspace`); never as the dependency manager.
- **Want personal defaults** (a default agent, extra tools, an IDE nvim, a theme)?
  Consume a personal config repo like
  [your-config-repo](docs/knowledge/decisions/0018-split-your-config-repo.md)
  instead of ragent directly — it composes ragent and adds your opinions.

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
