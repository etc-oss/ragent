# AGENTS.md — entrypoint for any coding agent

This is the context entrypoint every coding agent (Claude Code, pi, opencode,
crush, …) should read first. It is intentionally short and points at the
knowledge bundle instead of duplicating it. `CLAUDE.md` simply defers here.

## What ragent is

`ragent` is an open-source, forkable-per-project developer workspace that makes
AI-assisted coding efficient while preserving human oversight. Two sides share
one project directory:

- **HUMAN pane** — neovim + LSPs + lazygit, with an observability pane for the
  tool in use.
- **MACHINE pane** — coding agents working in a **safe sandbox** (`jail.nix` /
  bubblewrap) inside a Lima Linux VM, with a log/observability pane.

The machine side gets a read-write bind mount to the **project directory only**;
`$HOME`, SSH keys, and secrets are excluded; cgroup caps limit blast radius. The
sandbox is a safe haven, not a jail — an agent can act and ideate boldly precisely
because a mistake can't escape its clone. Shared CLI tools go on `PATH` via the flake
so every agent can call them through bash. Upstreams are consumed as **pinned flake
inputs**, never vendored.

Full rationale is in the knowledge bundle — start with
[the architecture overview](docs/knowledge/components/architecture-overview.md)
and [the forward plan](docs/knowledge/components/forward-plan-phases-1-5.md).

## Project status

**Phases 0–6 built and verified locally** (macOS host + a Lima Linux guest): the
confinement gate (probe 8/8, cgroup caps), the four sandboxed agents, the two-side
workspace + git-clone review boundary, the shared tooling layer, and the async review
loop (adapter + orchestrator + bounded, human-paced revise→merge loop). Claude Code
runs on an API key **or** a Pro/Max subscription (with a usage-limit wait layer). See
the [roadmap](docs/knowledge/components/roadmap.md) for what's next (6c: remote
Tailscale forge, notifications, more adapters, microvm.nix, opt-in OTel) and the
[CHANGELOG](CHANGELOG.md) for per-release detail.

The build is a vertical slice recorded as it goes: every non-trivial decision becomes
an ADR linked to the session that produced it — that trail *is* the design history.

## The knowledge bundle — read and maintain it

`docs/knowledge/` is an [OKF](https://github.com/GoogleCloudPlatform/knowledge-catalog)
bundle: Markdown files with YAML frontmatter, cross-linked with Markdown links.
Concept types (frontmatter `type`):

- **decision** — ADRs (MADR-style). The "why" behind every choice.
- **session** — verbatim chat/prompt records. Never paraphrased.
- **component** — architecture concepts and the forward plan.
- **convention** — the standards below.

Entry points: [knowledge bundle index](docs/knowledge/index.md),
[decisions index](docs/knowledge/decisions/index.md),
[configuration reference](docs/knowledge/components/configuration-reference.md) (every `RAGENT_*` variable).

## Working rules (conventions)

Read these before making changes; they are the contract for this repo:

1. [Knowledge format](docs/knowledge/conventions/knowledge-format.md) — OKF
   frontmatter schema, which fields are OKF-standard vs ragent extensions, and
   how to add a concept.
2. [ADR process](docs/knowledge/conventions/adr-process.md) — record every
   non-trivial decision as an ADR and link it back to the session that produced
   it. If you deviate from the suggested repo structure, justify it in an ADR.
3. [Verbatim sessions](docs/knowledge/conventions/verbatim-sessions.md) —
   session records are byte-faithful. Never "clean up" a transcript.

Additional standing rules:

- **Reference, don't redistribute.** Add upstreams as pinned flake inputs; do
  not copy their source into this repo. See `THIRD_PARTY.md` and ADR-0003.
  jail.nix is GPL-3.0 — vendoring it would change this repo's licensing story.
- **HTML is generated, never hand-edited.** `docs/html/` is produced from
  `docs/knowledge/` by `tools/okf_render.py`. Edit Markdown, then regenerate.
- **Model split:** plan/design with Opus, execute volume with Sonnet, delegate
  mechanical work to Haiku. See ADR-0009.

## Guardrails (do not cross without explicit human confirmation)

- Do **not** add a public git remote, push, or make the repository public.
- Do **not** run destructive git history rewrites on shared branches.
- Keep the private mirror/resilience layer **out** of the public repo
  (`.gitignore` already excludes `/mirror/`). See ADR-0010.

## How to regenerate the HTML view

```sh
python3 tools/okf_render.py        # renders docs/knowledge/ -> docs/html/
```
No third-party Python packages are required (standard library only).
