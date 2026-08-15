# <your project>

Scaffolded from the [ragent](https://github.com/etc-oss/ragent) per-project
template. ragent is an open-source, forkable AI-coding workspace: agents that work
boldly in a safe sandbox (jail.nix), with human oversight, on Zellij + Lima.

## One-time setup

1. Point `inputs.ragent.url` in `flake.nix` at your ragent repo/fork. Until it is
   published, use a local checkout:
   ```
   ragent.url = "git+file:///absolute/path/to/ragent";
   ```
2. Run inside a Linux guest (bubblewrap needs Linux) — e.g. a Lima VM whose config
   lives in a config repo like your-config-repo. `nix flake lock` to pin.

## This project's tools (so the agent can build/test it)

Edit `projectTools` in `flake.nix` to add your stack (the template ships Python +
pytest as an example). Those tools go on the **confined agent's in-sandbox PATH**, so
the agent can run your build/tests *itself*, inside the sandbox — not just the human
side. Dependencies are pinned by `flake.lock`; you update them with
`nix flake update`. This is the dependency mechanism — **not** the Makefile.

## Use

```sh
nix develop                 # workspace tools + jailed agents + your projectTools
nix run .#task-window -- .    # launch the two-side workspace on this project
```

There's also a thin **`Makefile`** — `make workspace`, `make review`, `make test` —
purely ergonomic aliases that delegate to `nix`. It is **not** a dependency
manager (see [ADR-0019](https://github.com/etc-oss/ragent/blob/main/docs/knowledge/decisions/0019-per-project-forking-and-dependencies.md));
deleting it changes nothing about what's installed.

The MACHINE side runs a coding agent confined to a **clone** of this project
(the agent can only touch the clone + its own config; ADR-0016). You review its
proposed commits from the HUMAN side and merge what you accept — nothing lands
without that gate.

## Reviewing on any device

After each task, ragent renders the agent's own explanation (`.ragent/EXPLAIN.md`)
plus the real diff into a **self-contained HTML report** and can serve it — review
from your phone/laptop without the TUI:

```sh
nix run .#task-review -- <clone-dir>          # http://127.0.0.1:8099/  (localhost by default)
RAGENT_SERVE_HOST=<tailnet-ip> nix run .#task-review -- <clone-dir>   # reach it over Tailscale
```

It's convenient but unauthenticated — keep it on localhost or a private Tailscale
address (ADR-0021).

## Your project's docs & decisions

Record them however you like — ADRs, a wiki, plain Markdown, Obsidian, or nothing at
all. ragent uses OKF + ADRs for *its own* repo but doesn't impose a format on you
([ADR-0027](https://github.com/etc-oss/ragent/blob/main/docs/knowledge/decisions/0027-knowledge-format-is-the-consumers-choice.md)).
