---
type: decision
id: ADR-0030
title: CLI ergonomics — the directory defaults to CWD, the name is optional, and a `ragent shell`
description: Drop the mandatory "$PWD" first positional (the project dir now defaults to the current directory, overridable with -C/--dir), make the task name optional (default `work`), and add a low-ceremony top-level `ragent shell` that drops straight into a confined interactive agent session in a clone of the current dir (or a --scratch sandbox). Refines ADR-0023.
status: accepted
date: 2026-08-16
tags: [cli, ergonomics, dx, shell, refactor]
timestamp: 2026-08-16
---

# ADR-0030 — CLI ergonomics: default directory, optional name, `ragent shell`

## Context and problem statement

[ADR-0023](0023-unified-ragent-cli.md) gave one CLI, but shaped it around the
*orchestrator* (which passes absolute paths programmatically). So the **human** had to
type the project directory as a required first positional:

```
ragent task window "$PWD" mytask
ragent task orchestrate "$PWD" mytask "add a subtract()"
```

`"$PWD"` is pure ceremony — it's almost always the current directory, yet it's mandatory.
That the template `Makefile` had to wrap it (`nix run .#task-window -- "$$PWD" …`) is the
tell: if the ergonomic path needs a wrapper to be bearable, the CLI is wrong. There was
also no low-ceremony way to *just* get a confined interactive session.

## Decision

**1. The project directory defaults to the current directory; override with `-C/--dir`**
(git's convention). No more `"$PWD"`.

**2. The task name is optional**, defaulting to `work` (`shell` for `ragent shell`). The
name stays the primary positional where it's the primary thing (`window`, `shell`); for
`orchestrate` the prompt is primary, so `orchestrate [name] <prompt>` — argparse resolves
one positional to the required `prompt` (verified).

**3. A new top-level `ragent shell [name] [-C DIR] [--scratch] [--sh]`** — the
low-ceremony entry: set up a clone (of the current dir, or a repo-less `--scratch`
sandbox) and drop **straight into the confined interactive agent** (no `-p`). `--sh` drops
into a shell positioned in the clone instead (from which you launch the agent yourself).

```
ragent task window mytask                 # dir = CWD
ragent task orchestrate "add a subtract() + test"
ragent shell                              # confined interactive agent in a clone of CWD, now
ragent shell --scratch                    # …in a standing repo-less sandbox
ragent task window mytask -C ~/other      # explicit dir only when you mean it
```

**No new isolation path.** `shell` reuses the *existing* clone + bubblewrap + cgroup
machinery (`ragent-workspace.sh` setup + the generated `spawn-agent.sh`); the change is
better **defaults** and a shorter **entry point**, not a second sandbox model. The
confinement is the agent's (bubblewrap binds the clone as cwd); `--sh` gives a normal
shell *positioned* in the disposable clone — the review boundary, not OS confinement.

This **refines ADR-0023**; the internal `orchestrate(project, task, prompt)` signature is
unchanged — the CLI just resolves `project` from `-C`-or-CWD.

## Consequences

### Positive
- The common case loses the boilerplate: `ragent task window mytask`, `ragent shell`.
- `ragent shell` collapses the old three-step "setup-only + cd + spawn" dance into one word.
- `--scratch` gives a confined Claude Code to poke at *without a repo at all*.
- The Makefile is no longer needed to make the CLI bearable (it stays as pure sugar).

### Negative / trade-offs
- **Breaking change** (positional reorder). Acceptable at **v0.1.0, pre-publish,
  single-user** — the ideal moment; the Makefile, guides, and template were updated.
- Ephemeral `shell`/scratch clones accrue — they pair with the queued `ragent task clean`.

## Alternatives considered
- **Name as `-n/--name` flag everywhere** — rejected: a positional name is more natural for
  the commands whose primary arg *is* the name (`window`, `shell`).
- **Keep `"$PWD"`** — rejected: needless ceremony; the shell already knows the directory.
- **A bubblewrap-confined `--sh` shell** — deferred: needs a `jailed-bash` binary; for now
  `--sh` is a normal shell in the clone, and the *agent* you launch from it is confined.

## Verification
In the Lima guest: argparse resolves `orchestrate [name] <prompt>` correctly (1 arg →
prompt, name=`work`; 2 args → name, prompt); `-C` overrides the dir; and real clone setup
through the flake apps (`.#task-window`, `.#shell`, `.#shell --scratch`) creates the
expected clones (setup-only path, no TUI). Per roadmap principle #7 (verify by behavior).

## Links
- [ADR-0023 — Unified ragent CLI](0023-unified-ragent-cli.md) (this refines its shape)
- [ADR-0016 — Agent works in a clone](0016-agent-clone-not-worktree.md) (the boundary `shell` reuses)
- [guide: run a sandbox agent](../../guides/sandbox-agent.md), `tools/ragent/cli.py`
