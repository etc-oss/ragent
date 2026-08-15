# Guide: async review with Forgejo

Run a task, get a **PR**, review it (from your phone), let the agent revise, and merge —
oversight on the go. Builds on [run a sandbox agent](sandbox-agent.md).

## Prerequisites

- The [sandbox-agent](sandbox-agent.md) prerequisites (Linux guest + a credential).
- A self-hosted **forge** and its transport env. For local dev, the your-config-repo
  config ships a `forgejo-local` harness:
  ```sh
  nix run <your-config-repo>#forgejo-local      # starts Forgejo on 127.0.0.1 + writes forge.env
  source ~/.config/ragent/forge.env             # RAGENT_ADAPTER + forge URL / user / token
  ```
  Remote is identical against a NixOS `services.forgejo` over **Tailscale** — a URL swap,
  no code change.

## Run a task → open a PR

```sh
ragent task orchestrate "$PWD" mytask "add a subtract() to calc.py with a test"
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
