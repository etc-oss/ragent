# ragent

> AI coding agents that work boldly in a safe sandbox — with real human oversight.
> A forkable-per-project workspace.

ragent gives coding agents (Claude Code, opencode, pi, crush) a **safe sandbox** to
work in — a [`jail.nix`](https://git.sr.ht/~alexdavid/jail.nix)/bubblewrap space
inside a [Lima](https://github.com/lima-vm/lima) Linux VM where an agent can act and
ideate *boldly, precisely because it can't reach anything outside its task* — and
keeps a **human in the loop** two ways: a two-pane terminal workspace for hands-on
work, and an async review loop (the agent opens a PR, you review it when you're ready
— on any device — it revises, you merge). It's consumed as a **pinned flake input** — add your project's
tools and they run *in the sandbox* with the agent. Every decision is captured as an
ADR in an [OKF](https://github.com/GoogleCloudPlatform/knowledge-catalog) knowledge graph.

> **Status (2026-08): Phases 0–6 built and verified locally** (macOS host + a Lima
> Linux guest) — the confinement gate, four confined agents, the two-side workspace
> with a git-clone review boundary, the shared tooling layer, **and the async review
> loop** (a real sandboxed agent opens a real PR; a bounded, human-paced loop takes your
> review notes → revise → approve → merge). Claude Code can
> authenticate by API key **or** Pro/Max subscription. This is the **v0.1.0** first
> public release; every claim here is backed by a real run in the guest, and the
> honest edges are stated inline and in [`SECURITY.md`](SECURITY.md).

## What you get

- **A safe sandbox, by construction.** The agent works freely in a read-write bind to
  the *project directory only* — `$HOME`, SSH keys, the environment, and secrets sit
  outside it, and cgroup caps bound CPU/memory/PIDs. It can act boldly precisely
  because a mistake can't escape: verified by an **8/8 negative-control probe** (the
  agent *cannot* reach what isn't bound —
  [ADR-0002](docs/knowledge/decisions/0002-jail-nix-confinement.md),
  [ADR-0015](docs/knowledge/decisions/0015-cgroup-caps-systemd-run.md)).
- **A hard human gate.** The agent commits only in a disposable clone; nothing
  reaches your tree without you fetching + merging (or approving a PR) —
  [ADR-0011](docs/knowledge/decisions/0011-git-worktree-review-boundary.md),
  [ADR-0016](docs/knowledge/decisions/0016-agent-clone-not-worktree.md).
- **Two oversight modes.**
  - **Hands-on TUI** (`ragent task window`) — neovim + LSP + lazygit on your tree
    beside the confined agent in its clone, each with a log pane
    ([ADR-0005](docs/knowledge/decisions/0005-zellij-two-pane-layout.md)).
  - **Async review** (`ragent task orchestrate`) — the agent does a task → opens a
    **PR** on a self-hosted forge → a **bounded, human-paced loop** feeds your review
    notes back to the agent → you approve → it merges. Review when you're ready, any device
    ([ADR-0020](docs/knowledge/decisions/0020-review-transport-adapters.md),
    [ADR-0024](docs/knowledge/decisions/0024-human-paced-bounded-review-loop.md)).
- **A pluggable review transport.** The orchestrator is transport-agnostic — a
  9-verb adapter + a `capabilities` handshake — so Forgejo (today), GitLab, GitHub,
  or bare git-over-SSH slot in behind one interface; a forge-independent served HTML
  report is the universal fallback
  ([ADR-0022](docs/knowledge/decisions/0022-python-adapters-verb-superset-capabilities.md),
  [ADR-0021](docs/knowledge/decisions/0021-per-task-explanatory-report.md)).
- **Four agents, one interface.** opencode, Claude Code, pi, crush — all sandboxed
  identically, with shared CLIs (git-surgeon, ripgrep, fd, jq) on the in-sandbox PATH
  ([ADR-0007](docs/knowledge/decisions/0007-shared-clis-on-path.md)). Claude Code
  authenticates by API key **or** Pro/Max **subscription** (browser `setup-token`);
  on the subscription path there's no API fallback — it **waits out** a usage limit
  and resumes ([ADR-0025](docs/knowledge/decisions/0025-jailed-claude-subscription-auth.md),
  [ADR-0026](docs/knowledge/decisions/0026-subscription-usage-limit-wait.md)).
- **Forkable per project.** Consume ragent as a pinned flake input; your
  `projectTools` join the confined agent's PATH so it can build and test your project
  *itself, in-sandbox* (verified: a sandboxed agent runs `pytest` in-sandbox) —
  [ADR-0019](docs/knowledge/decisions/0019-per-project-forking-and-dependencies.md).
- **Its own memory.** Every non-trivial decision is an ADR linked to the verbatim
  session that produced it; `docs/knowledge/` is a cross-linked OKF graph.

## Guides

Task-focused how-tos in **[`docs/guides/`](docs/guides/)**:

- **[Run a sandbox agent](docs/guides/sandbox-agent.md)** — a confined agent on your project, no forge.
- **[Async review with Forgejo](docs/guides/async-review-forgejo.md)** — agent → PR → review → merge.
- **[Fork ragent into your project](#forking-ragent-into-another-project)** — consume it as a pinned flake input.
- **[Troubleshooting](docs/guides/troubleshooting.md)** — the common gotchas + fixes.
- **[Configuration reference](docs/knowledge/components/configuration-reference.md)** — every `RAGENT_*` variable in one table (defaults, scope, options).

> ragent uses OKF + ADRs for *its own* knowledge, but it **doesn't impose a docs
> format on you** — your project can use ADR-only, OKF, plain Markdown, Obsidian,
> anything ([ADR-0027](docs/knowledge/decisions/0027-knowledge-format-is-the-consumers-choice.md)).
> These guides are plain Markdown to model that.

## How it's airtight (and where the edges are)

The sandbox is a *safe haven* in the literal sense: the agent can experiment boldly
because it **cannot touch the host**. That single property is at once the pitch and
the security guarantee, and it has two **enforced** halves — see
[`SECURITY.md`](SECURITY.md) for the full model.

**Confinement (the sandbox).**
- The agent runs under bubblewrap with `--clearenv` and a bind list that is *only*
  the project directory (rw) — no `$HOME`, `~/.ssh`, keychain, or other path. The
  provider key/token is forwarded as a single env var at runtime and **never** enters
  the Nix store, the repo, or a bound file
  ([ADR-0014](docs/knowledge/decisions/0014-runtime-env-secret-forwarding.md)).
- cgroup caps (memory / CPU / PIDs, via a transient systemd scope) bound a runaway or
  fork-bomb.
- **Verified by negative control** — the discipline of proving the wall by what
  *doesn't* get through: an 8/8 probe asserts the agent cannot read outside its bind;
  subscription auth was proven by *unsetting* the API key and watching the sandbox fail,
  demonstrating the key cannot leak in.

**Oversight (the human gate).**
- The agent works in a throwaway clone and can only *commit* — it never pushes and
  never holds the forge token (that's the host-side orchestrator, **outside** the
  sandbox). Nothing lands without your merge/approve.
- Every autonomous loop is **bounded**: the async loop caps agent revisions (the
  load-bearing runaway guard), wall-clock, and cost, and escalates to *needs-human*
  rather than running away.

**The honest edges (we don't overstate "airtight"):**
- Bubblewrap is **namespace isolation, not a VM** — a kernel exploit could in
  principle escape. VM-per-agent (microvm.nix) is the roadmap's stronger boundary
  (prototype exists).
- The async loop is verified against a **local** forge (remote/Tailscale is a config
  swap, not yet exercised). Its mechanics + bounds are verified deterministically and
  the real-agent→PR at parity, but the *full real-agent revision cycle* is proven
  **transitively** (real agent + stubbed loop + the wired follow-path), not run as one
  unbroken pass.
- The subscription usage-limit **detector** is best-effort — a real weekly limit
  can't be triggered to verify, so the wait/retry *mechanics* and bound are tested,
  live detection is not ([ADR-0026](docs/knowledge/decisions/0026-subscription-usage-limit-wait.md)).
- `capabilities` graceful degradation is shipped but unexercised until a second,
  partial adapter exists.
- Single-user today; a SaaS forge adapter (github.com) would send review data
  off-box — a conscious, non-default relaxation.

> **A note on framing.** We call it a *sandbox* or *safe haven*, not a jail: the agent
> is a trusted collaborator given a protected space to work boldly, not a prisoner
> (that ethos is spelled out in [`AGENTS.md`](AGENTS.md)). The agent packages are
> named `jailed-*` after the upstream
> [jailed-agents](https://github.com/andersonjoseph/jailed-agents) library, and the
> sandbox is built on [`jail.nix`](https://git.sr.ht/~alexdavid/jail.nix) — we keep
> those upstream names, but the design intent is safety *in service of* the agent's
> freedom, not restriction of it.

## Architecture at a glance

```
macOS / Windows host
└─ Lima Linux VM (one long-lived guest, shared Nix store)
   ├─ Zellij workspace (hands-on)         ├─ Orchestrator (async, HOST-SIDE)
   │  ├─ HUMAN:   neovim + LSPs, lazygit  │  holds the forge token; the sandbox never does
   │  └─ MACHINE: sandbox → agent → CLIs  │  ├─ sets up the agent clone
   │             (rw bind: PROJECT ONLY)  │  ├─ runs the sandboxed agent (commits in clone)
   └───────────────────────────────────── │  └─ push + PR + read review notes → re-prompt
                                          Forge (Forgejo) ◄── review when ready (any device)
```

**Full technical architecture + file map:**
[architecture overview](docs/knowledge/components/architecture-overview.md) ·
[async review transport](docs/knowledge/components/forgejo-transport-design.md).

**Does confining the agent make it worse?** The honest accounting —
[orchestration & harness efficiency](docs/knowledge/components/orchestration-and-harness-efficiency.md):
the model and its tools are untouched; four named trade-offs, each with its mitigation.

**The review boundary — why a separate directory.** The agent never works in your project
folder; it works in a sibling **clone** — `<project>-agent-<task>`, on branch
`agent/<task>` — sandboxed to *that directory only*. Its edits can't reach your tree until
you `git fetch` + `merge` them across, so the separate directory **is** the human gate, and
a bad run is discarded by simply not merging. It's a full clone, **not a git worktree**, on
purpose: a worktree keeps its `.git` object store *outside* the directory (so in-sandbox git
would break), while a clone's `.git` is self-contained
([ADR-0016](docs/knowledge/decisions/0016-agent-clone-not-worktree.md)). The clone is
**reused** when you re-run the same task and is **not auto-deleted** — `rm -rf
<project>-agent-<task>` to reclaim the space when you're done.

## Quickstart (Linux guest)

The sandbox runs on Linux (bubblewrap needs namespaces); the VM config lives in
[your config repo](docs/knowledge/components/running-on-a-vm.md).

```sh
limactl shell ragent                             # a Nix-enabled Linux guest
cd /path/to/ragent && nix develop .#workspace    # tools + the four agents + the `ragent` CLI
export ANTHROPIC_API_KEY=...                     # or a subscription token (see the guide)
```

Then pick a use-case — the directory defaults to the current one, so there's no `$PWD` to type:

*Quickest — a confined interactive agent (a normal Claude Code session, just sandboxed to a clone):*
```sh
ragent shell
```

*Interactive with oversight — the two-pane TUI (you and the agent, side by side):*
```sh
ragent task window mytask
```

*Hands-off — the agent does the task and opens a PR you review and merge:*
```sh
ragent task orchestrate "add a subtract() to calc.py with a test"
```

**Then go deeper →** [run a sandbox agent](docs/guides/sandbox-agent.md) ·
[async review with Forgejo](docs/guides/async-review-forgejo.md) ·
[troubleshooting](docs/guides/troubleshooting.md).

## Commands

The directory defaults to the **current directory** (`-C DIR` to override); the task name
defaults to `work`. In the workspace devshell these are `ragent …`; anywhere else the same
commands are `nix run .#<app> -- …`.

| Command | What it does |
|---|---|
| `ragent shell [name]` | Quickest confined interactive agent session, in a clone of the current dir |
| `ragent shell --scratch` | …in a standing repo-less scratch sandbox (no project needed) |
| `ragent task window [name]` | Two-pane TUI — your tree beside the confined agent in its clone |
| `ragent task orchestrate [name] <prompt>` | Async — agent does the task → opens a PR → bounded review loop → merge |
| `ragent task review [clone]` | Serve a task's HTML report (the agent's explanation + the real diff) over HTTP |
| `ragent task list · attach <name> · kill <name>` | Session management |
| `nix run .#dev-forge` | Local Forgejo + `forge.env`, so `orchestrate` works out of the box ([ADR-0029](docs/knowledge/decisions/0029-local-dev-forge.md)) |

`-C DIR` overrides the project directory; `--sh` makes `shell` drop into a shell in the
clone instead of the agent. Rationale:
[ADR-0030](docs/knowledge/decisions/0030-cli-ergonomics-default-dir-shell.md).

## Forking ragent into another project

Don't fork the repo, and **don't manage dependencies with a Makefile.** Adopt ragent
as a **pinned flake input** — reproducible deps, a one-line bump
([ADR-0019](docs/knowledge/decisions/0019-per-project-forking-and-dependencies.md)):

```sh
cd my-project                      # a git repo
nix flake init -t github:etc-oss/ragent#default # a small flake.nix that consumes ragent
nix develop && nix run .#task-window -- mytask   # dir defaults to CWD
```

- **Your tools go in `projectTools`** (`ragent.lib.<system>.mkWorkspace { projectTools = […]; }`)
  and land on the confined agent's in-sandbox PATH — so it builds/tests your project
  *itself, in the sandbox*. Deps live in `flake.lock` (`nix flake update`), not a Makefile.
- **Personal defaults** (a default agent, extra tools, an IDE nvim, a theme, the dev
  forge)? Consume a personal config repo like
  [your-config-repo](docs/knowledge/decisions/0018-split-your-config-repo.md) that
  composes ragent and adds your opinions.

## Roadmap

| Phase | Focus | Status |
|---|---|---|
| **0** | Scaffold, governance, knowledge system, plan | ✅ Complete |
| **1** | The sandbox + confined agents (dogfood the sandbox) | ✅ Verified |
| **2** | Two-side Zellij workspace + git-clone review boundary | ✅ Verified |
| **3** | Shared CLIs on PATH + per-project template | ✅ Verified |
| **4** | Four agents (opencode, Claude Code, pi, crush) + observability | ✅ Verified |
| **5** | Open-source hardening (CI prepared, CONTRIBUTING, VM guide) | ✅ (pre-publish) |
| **6** | Async review: adapters + orchestrator + bounded human-paced loop; subscription auth | ✅ Verified (local forge) |
| **6c / beyond** | Remote Tailscale forge, notifications, more adapters, microvm.nix, opt-in OTel observability | Planned |

The living plan and guiding principles are in the
[roadmap](docs/knowledge/components/roadmap.md); the honest per-item caveats for
Phases 1–5 are in the [forward plan](docs/knowledge/components/forward-plan-phases-1-5.md).

## Knowledge bundle

`docs/knowledge/` is an OKF bundle (Markdown + YAML frontmatter, cross-linked into a
graph). Browse [`docs/knowledge/index.md`](docs/knowledge/index.md) or the
[decisions index](docs/knowledge/decisions/index.md); build the offline HTML + graph
view with `python3 tools/okf_render.py` (stdlib only; `docs/html/` is generated —
never hand-edit it). Coding agents should start at [`AGENTS.md`](AGENTS.md).

## Contributing & security

See [CONTRIBUTING](CONTRIBUTING.md), [CHANGELOG](CHANGELOG.md), and
[`SECURITY.md`](SECURITY.md) (the confinement model + how to report a vulnerability).

## Provenance — built by Claude, directed by a human

Every line of ragent's *own* code and documentation was authored by **Claude**
(Anthropic's Claude Code, on the Opus models), ideated and directed by its
maintainers, **Gourang Abani** and **Kunal Sharma**. That isn't a disclaimer — it's
the point: **ragent is an instance of
its own thesis** — an AI doing real engineering in a safe space, under human
direction, with a *complete, transparent record*. The receipts are in the repo: the
[verbatim session logs](docs/knowledge/sessions/) and the
[Architecture Decision Records](docs/knowledge/decisions/index.md) capture every
non-trivial choice, why it was made, and the run that verified it — read them as the
project's real changelog of *thinking*. (The referenced upstreams — `jail.nix`,
`jailed-agents`, `git-surgeon` — are third-party, under their own licenses; see
[`NOTICE`](NOTICE) and [`THIRD_PARTY.md`](THIRD_PARTY.md).)

## License & attribution

ragent's own code is [Apache-2.0](LICENSE)
([ADR-0001](docs/knowledge/decisions/0001-apache-2.0-license.md)), with a **CC0
public-domain fallback**: because much of ragent was AI-authored (see **Provenance**
above), any portion not eligible for copyright is dedicated to the public domain
([CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)); where copyright does
subsist, Apache-2.0 governs (details in [`NOTICE`](NOTICE)). It **references**
upstreams as pinned flake inputs and does **not** vendor their code — each keeps its
own license. In particular **`jail.nix` is GPL-3.0**: referencing it as a build input
(not distributing its source) is exactly what keeps this repo's Apache-2.0 umbrella
clean ([ADR-0003](docs/knowledge/decisions/0003-consume-upstreams-as-flake-inputs.md)).
Full, verified attribution is in [`NOTICE`](NOTICE) and
[`THIRD_PARTY.md`](THIRD_PARTY.md). Prior art studied and credited:
[jailed-agents](https://github.com/andersonjoseph/jailed-agents),
[sandnix](https://github.com/srid/sandnix), and the
[Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog).
