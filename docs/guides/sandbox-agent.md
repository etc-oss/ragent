# Guide: run a sandbox agent

Run a coding agent **confined** to a project directory — no forge, no async loop. The
agent works in a disposable clone; you review the diff and merge. The simplest use-case.

## Prerequisites

- A Nix-enabled **Linux guest** (the sandbox/bubblewrap needs Linux namespaces) — see
  [running on a VM](../knowledge/components/running-on-a-vm.md). You can dogfood on the
  ragent repo itself.
- A credential, **guest-only, never in the repo**:
  - **API key:** `export ANTHROPIC_API_KEY=...`
  - **or a Claude Pro/Max subscription:** run `claude setup-token` once (in a browser,
    *outside* the sandbox), then `export CLAUDE_CODE_OAUTH_TOKEN=...` and select
    `RAGENT_AGENT=jailed-claude-code-subscription`.

Pick any agent with `RAGENT_AGENT`: `jailed-opencode` (default), `jailed-claude-code`,
`jailed-claude-code-subscription`, `jailed-pi`, `jailed-crush`.

## Option A — the two-pane TUI (interactive)

```sh
cd /path/to/your/project          # a git repo
nix develop .#workspace           # (or just `nix develop` in a project that consumes ragent)
ragent task window "$PWD" mytask
```

- **HUMAN** pane: neovim + LSP + lazygit on your tree.
- **MACHINE** pane: a shell in the agent **clone** (`…-agent-mytask`). Run the agent:
  ```sh
  ./.ragent/spawn-agent.sh -p "add a subtract() to calc.py" --dangerously-skip-permissions
  ```
- **Review** from the HUMAN side, then merge — nothing lands without this:
  ```sh
  git fetch "$PWD-agent-mytask" agent/mytask
  git diff  <base>..FETCH_HEAD     # what the agent proposes
  git merge FETCH_HEAD             # accept — or do nothing to discard (the clone is disposable)
  ```

Session ops: `ragent task list | attach mytask | kill mytask`.

## Option B — one-shot, no TUI

```sh
RAGENT_SETUP_ONLY=1 ragent task window "$PWD" mytask       # create the clone + spawn helper only
cd "$PWD-agent-mytask"
RAGENT_AGENT=jailed-claude-code ./.ragent/spawn-agent.sh -p "…" --dangerously-skip-permissions
```

A self-contained HTML report (the agent's `.ragent/EXPLAIN.md` + the diff) is generated
after each run — serve it from any device with `ragent task review "$PWD-agent-mytask"`.

## What the sandbox guarantees

The agent gets a read-write bind to the **project directory only** — no `$HOME`, SSH
keys, or secrets; cgroup caps bound CPU/memory/PIDs. It can act boldly *because a
mistake can't escape* (full model in [SECURITY.md](../../SECURITY.md)).

Snag? → **[Troubleshooting](troubleshooting.md)**.
