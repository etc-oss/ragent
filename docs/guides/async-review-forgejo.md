# Guide: async review with Forgejo

Run a task, get a **PR**, review it when you're ready (on any device), let the agent
revise, and merge — **async oversight**: the code waits for you. Builds on
[run a sandbox agent](sandbox-agent.md).

## Prerequisites

- The [sandbox-agent](sandbox-agent.md) prerequisites (Linux guest + a credential).
- A **forge** and its transport env. **Out of the box**, ragent ships a local dev forge
  ([ADR-0029](../knowledge/decisions/0029-local-dev-forge.md)):
  ```sh
  nix run .#dev-forge                           # Forgejo on 127.0.0.1 + writes forge.env (foreground; Ctrl-C to stop)
  source ~/.config/ragent/forge.env             # in ANOTHER shell — RAGENT_ADAPTER + forge URL / user / token
  ```
  Nix, **not** docker-compose (the guest has no Docker daemon; nixpkgs already ships
  forgejo). For a persistent/**remote** forge, run a NixOS `services.forgejo` over
  **Tailscale** (deployment config lives in your-config-repo) — the client side is
  identical, just a `RAGENT_FORGE_URL` swap.

## Run a task → open a PR

```sh
ragent task orchestrate mytask "add a subtract() to calc.py with a test"
```

The confined agent does the work and commits in its clone; then **host-side (outside
the sandbox)** ragent pushes the branch and opens a PR whose body is the agent's own
explanation + a link to the served report. The sandboxed agent never holds the forge
token.

## The review loop

`orchestrate` **follows** the review by default:

1. Review the PR — diff, line comments, approve — in Forgejo, on any device.
2. **Request changes** → ragent feeds your notes to the confined agent → it revises →
   pushes an update → replies in the thread.
3. **Approve** → it merges (if `autoMerge`), else it stops and you merge.

Bounds keep it safe: `max_iterations` is the load-bearing runaway guard; wall-clock is
a resource cap; "cost" is cumulative agent runtime; a tripped bound posts a
**needs-human** reply and stops. Knobs (env):

| Env | Meaning | Default |
|---|---|---|
| `RAGENT_POLL_INTERVAL` | seconds between review polls | 20 |
| `RAGENT_MAX_ITERATIONS` | max agent revisions before needs-human | 6 |
| `RAGENT_AUTO_MERGE` | merge on approve vs. wait for you | off |
| `RAGENT_LIMIT_MAX_WAIT_HOURS` | how long to wait out a subscription usage limit | 6 |

Use `--no-follow` to just open the PR and stop.

## Forge-independent fallback

No forge, or a `code`-only transport? Every task still renders a self-contained HTML
report (the agent's `EXPLAIN.md` + the real diff):

```sh
ragent task review "$PWD-agent-mytask"    # → http://127.0.0.1:8099/
```

## Choosing a transport

Forgejo is the default adapter; the orchestrator is transport-agnostic (a 9-verb
adapter + a `capabilities` handshake), so GitLab / GitHub / bare git-over-SSH follow
the same interface —
[ADR-0020](../knowledge/decisions/0020-review-transport-adapters.md),
[ADR-0022](../knowledge/decisions/0022-python-adapters-verb-superset-capabilities.md).

Snag? → **[Troubleshooting](troubleshooting.md)**.
