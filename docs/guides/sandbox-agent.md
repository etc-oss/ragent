# Guide: run a sandbox agent

Run a coding agent **confined** to your project — it works in a disposable clone, you
review the diff and merge. No forge, no async loop. The simplest use-case.

The project directory **defaults to the current directory** (pass `-C DIR` to override),
and the task name defaults to `work` — so most commands take no arguments.

## Prerequisites

- A Nix-enabled **Linux guest** (the sandbox/bubblewrap needs Linux namespaces) — see
  [running on a VM](../knowledge/components/running-on-a-vm.md). You can dogfood on the
  ragent repo itself.
- The workspace on your PATH:
  ```sh
  cd /path/to/your/project        # a git repo
  nix develop .#workspace          # (or just `nix develop` in a project that consumes ragent)
  ```
- A credential, **guest-only, never in the repo** — pick one:
  ```sh
  export ANTHROPIC_API_KEY=...                              # API key
  ```
  ```sh
  claude setup-token                                        # once, in a browser, OUTSIDE the sandbox
  export CLAUDE_CODE_OAUTH_TOKEN=...                        # then a Pro/Max subscription
  export RAGENT_AGENT=jailed-claude-code-subscription
  ```
  **Tip:** put those `export …` lines in **`~/.config/ragent/env`** (`chmod 600`) — ragent
  auto-loads that file before every confined run, so the token/key is forwarded into the
  sandbox without re-exporting each session (it never enters the Nix store; ADR-0014).

  **Interactive vs. headless (subscription).** The `CLAUDE_CODE_OAUTH_TOKEN` authenticates
  **headless** runs (`-p` / `ragent task orchestrate`) but **not interactive** ones
  (`ragent shell`, `ragent task window`) — Claude Code only honors that env token for
  CI/scripts and wants a **stored login** for a REPL. Do a **one-time `/login`** inside the
  first `ragent shell` (Browser Login → open the URL on your host → paste the code): the
  sandbox binds `~/.claude`, so the credential **persists** and every later interactive
  session is authenticated with no prompt. (An `ANTHROPIC_API_KEY` also skips the prompt, but
  that's Console/API billing, not a Pro/Max subscription.)
- Pick any agent with `RAGENT_AGENT`: `jailed-opencode` (default), `jailed-claude-code`,
  `jailed-claude-code-subscription`, `jailed-pi`, `jailed-crush`.

## Run an agent — three ways

### 1. Quickest — a confined interactive agent

Drops you straight into an interactive agent session (a normal Claude Code REPL, just
sandboxed to a clone of the current directory). This is the closest thing to a plain
`claude` session, with the confinement + review boundary added.

```sh
ragent shell
```

No project handy? Use a standing, repo-less **scratch** sandbox instead:

```sh
ragent shell --scratch
```

### 2. Interactive with oversight — the two-pane TUI

A Zellij workspace: **HUMAN** pane (neovim + LSP + lazygit on your tree) beside the
**MACHINE** pane (a shell in the agent's clone). You watch and steer; you review and merge.

```sh
ragent task window mytask
```

Then, in the MACHINE pane, launch the agent — **interactively** (omit `-p`) or one-shot:

```sh
./.ragent/spawn-agent.sh                                     # interactive REPL, confined
```
```sh
./.ragent/spawn-agent.sh -p "add a subtract() to calc.py" --dangerously-skip-permissions
```

### 3. Hands-off — one-shot, no TUI

Just run the task and stop; review the result afterwards. (For the full async **PR** loop
instead, see [async review](async-review-forgejo.md).)

```sh
ragent task orchestrate mytask "add a subtract() to calc.py with a test" --no-follow
```

## Review and merge — nothing lands without this

The agent commits on `agent/<name>` inside the clone (the sibling directory
`<project>-agent-<name>`). From your main tree, pull it back and decide:

```sh
git fetch "$PWD-agent-mytask" agent/mytask
```
```sh
git diff  <base>..FETCH_HEAD            # exactly what the agent proposes
```
```sh
git merge FETCH_HEAD                    # accept — or do nothing to discard (nothing lands)
```

The clone **persists** and is **reused** if you re-run `mytask`; it is not auto-deleted:

```sh
rm -rf "$PWD-agent-mytask"              # reclaim the space when you're done
```

Prefer a rendered view? A self-contained HTML report (the agent's `.ragent/EXPLAIN.md` +
the real diff) is generated after each run:

```sh
ragent task review "$PWD-agent-mytask"  # → http://127.0.0.1:8099/  (any device)
```

## What the sandbox guarantees

The agent gets a read-write bind to the **project clone only** — no `$HOME`, SSH keys, or
secrets; cgroup caps bound CPU/memory/PIDs. It can act boldly *because a mistake can't
escape* (full model in [SECURITY.md](../../SECURITY.md)).

Snag? → **[Troubleshooting](troubleshooting.md)**.
