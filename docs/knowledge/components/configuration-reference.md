---
type: component
id: COMP-configuration-reference
title: Configuration reference — every RAGENT_* variable in one place
description: The central, tabulated list of all RAGENT_* environment variables (plus the provider/auth vars) with their defaults, the entrypoint each applies to, and their options. Everything ragent reads from the environment, in one table.
tags: [reference, configuration, env-vars, egress, secrets]
timestamp: 2026-08-16
---

# Configuration reference

Every knob ragent reads from the environment, in one place. All configuration is
**environment variables** — there is no config file to edit. Precedence is simply:
**an exported variable wins; otherwise the default below applies.**

**Where to set them**

- **Per run:** `export RAGENT_… ` in the shell before `ragent …`, or inline
  (`RAGENT_AGENT=jailed-claude-code-subscription ragent task orchestrate …`).
- **Secrets** (provider keys, forge token) go in a `0600` file that the confine
  chokepoint auto-loads — never on the command line, never committed, never in the
  Nix store (ADR-0014):
  - `~/.config/ragent/env` — the agent's provider key / OAuth token (loaded *inside* the guest, forwarded into the jail).
  - `~/.config/ragent/forge.env` — the review-transport (forge) URL/user/token (host-side; **never** enters the jail).

The **"Applies to"** column names the entrypoint that reads the variable:
`confine` (the jail launcher) · `orchestrate` (the async review loop) ·
`workspace` (the TUI / `ragent shell` / `ragent task window`) · `adapter` (the
review transport) · `dev-forge` (the local forge fixture).

---

## Agent & review transport

| Variable | Default | Applies to | What it does / options |
|---|---|---|---|
| `RAGENT_AGENT` | `jailed-opencode` (workspace/shell) · `jailed-claude-code` (orchestrate) | confine · workspace · orchestrate | Which jailed agent to launch. Options: `jailed-claude-code`, `jailed-claude-code-subscription` (Pro/Max token), `jailed-opencode`, `jailed-pi`, `jailed-crush`. ⚠️ **the default differs by entrypoint** — see [note below](#a-note-on-ragent_agents-two-defaults). |
| `RAGENT_ADAPTER` | *(unset — required for orchestrate)* | orchestrate · adapter | The review-transport adapter. Currently `forgejo`. Orchestrate fails fast if unset. |
| `RAGENT_FORGE_URL` | *(from `forge.env`)* | adapter | Base URL of the forge (e.g. `http://127.0.0.1:3000`). |
| `RAGENT_FORGE_USER` | `ci` | adapter | Forge account the adapter authenticates as. |
| `RAGENT_FORGE_TOKEN` | *(secret, from `forge.env`)* | adapter | Forge API token. Keep in `forge.env`, never inline. |
| `RAGENT_FORGE_REPO` | *(unset)* | orchestrate · adapter | Target repo as `owner/repo`. |
| `RAGENT_FORGE_ENV` | `~/.config/ragent/forge.env` | adapter | Path to the host-side forge secrets file. |

## Orchestration loop

| Variable | Default | Applies to | What it does / options |
|---|---|---|---|
| `RAGENT_POLL_INTERVAL` | `20` | orchestrate | Seconds between review polls. |
| `RAGENT_MAX_ITERATIONS` | `6` | orchestrate | Max agent↔review rounds before giving up. |
| `RAGENT_MAX_AGENT_MIN` | `30` | orchestrate | Per-iteration agent wall-clock cap, in minutes. |
| `RAGENT_MAX_WALL_HOURS` | `24` | orchestrate | Total wall-clock cap for the whole orchestration, in hours. |
| `RAGENT_AUTO_MERGE` | *(off)* | orchestrate | Auto-merge on approval. Truthy: `1` / `true` / `yes`. Default leaves the merge to a human. |

## Session-limit backoff

Handles the provider's ~5h usage window: when a limit is detected, wait and resume
rather than fail.

| Variable | Default | Applies to | What it does / options |
|---|---|---|---|
| `RAGENT_LIMIT_MAX_WAIT_HOURS` | `6` | orchestrate | Max time to wait out a usage limit (covers the 5h window). |
| `RAGENT_LIMIT_POLL_SEC` | `900` | orchestrate | Poll cadence (seconds) while waiting out a limit. |
| `RAGENT_LIMIT_PATTERNS` | *(empty)* | orchestrate | Extra regexes (space/newline-separated) that also signal a usage limit in agent output. |

## Sandbox — resource caps (ADR-0015)

Transient systemd-scope cgroup caps applied by `ragent-confine.sh`.

| Variable | Default | Applies to | What it does / options |
|---|---|---|---|
| `RAGENT_MEM_MAX` | `4G` | confine | Memory cap (`MemoryMax`). |
| `RAGENT_CPU_QUOTA` | `200%` | confine | CPU quota (`200%` = up to 2 cores). |
| `RAGENT_TASKS_MAX` | `512` | confine | PID cap (fork-bomb guard). |
| `RAGENT_PRECREATE_DIRS` | *(empty)* | confine | Space-separated dirs to `mkdir -p` before the jail bind-mounts them (bwrap aborts if a bind source is missing — e.g. opencode's state dirs). |

## Sandbox — network egress (ADR-0031)

Default-**deny** outbound; allow only the LLM API host(s) via a kernel BPF IP filter.

| Variable | Default | Applies to | What it does / options |
|---|---|---|---|
| `RAGENT_EGRESS_ALLOW` | `api.anthropic.com` | confine | Space-separated hostnames to allow out (resolved to IPs at launch; localhost + the DNS resolver are always allowed). Add e.g. telemetry hosts here, or the target domains for a `web` profile. |
| `RAGENT_EGRESS_OPEN` | *(unset)* | confine | Set to `1` to disable filtering entirely (the old open-network behaviour). Escape hatch — prefer widening `RAGENT_EGRESS_ALLOW`. |

> Egress filtering needs passwordless `sudo` + `setpriv` in the guest; without them
> confine falls back to a `--user` scope and prints a warning (filtering is **not**
> enforced on `--user` scopes). See [ADR-0031](../decisions/0031-network-egress-allowlist.md).

## Paths & clones

| Variable | Default | Applies to | What it does / options |
|---|---|---|---|
| `RAGENT_CLONE_DIR` | `<main>-agent-<task>` | workspace · orchestrate | Where the agent's working clone is created. |
| `RAGENT_SCRATCH_DIR` | `~/.local/share/ragent/scratch` | workspace (`shell`) | Base dir for `ragent shell` scratch worktrees. |
| `RAGENT_MIRROR_ROOT` | `~/.ragent-mirror` | confine | Root for the offline package/git mirror. |
| `RAGENT_RUN_BIN` | `tools/ragent-confine.sh` | workspace · orchestrate | Override the confine launcher path. |
| `RAGENT_REPORT_BIN` | `tools/ragent-report.py` | workspace | Override the task-report generator path. |

## Dev-forge (local forge fixture)

The throwaway Forgejo used for local end-to-end runs (`ragent dev-forge`).

| Variable | Default | Applies to | What it does / options |
|---|---|---|---|
| `RAGENT_DEV_FORGE_PORT` | `3000` | dev-forge | HTTP port. |
| `RAGENT_DEV_FORGE_USER` | `ragent` | dev-forge | Seed account name. |
| `RAGENT_DEV_FORGE_DIR` | `~/.local/share/ragent/dev-forge` | dev-forge | State directory (sqlite + repos). |

## Workspace / TUI

| Variable | Default | Applies to | What it does / options |
|---|---|---|---|
| `RAGENT_LAYOUT` | *(flake default)* | workspace | Zellij layout name. |
| `RAGENT_ZELLIJ_CONFIG` | `workspace/zellij-config.kdl` | workspace | Zellij config path. |
| `RAGENT_LAZYGIT_CONFIG` | `workspace/lazygit-theme.yml` | workspace | lazygit theme path. |
| `RAGENT_SERVE_HOST` | `127.0.0.1` | workspace | Bind host for the local task-report server. |

## Flags

| Variable | Default | Applies to | What it does / options |
|---|---|---|---|
| `RAGENT_SETUP_ONLY` | *(unset)* | workspace | Set to `1` to provision the clone/workspace and exit **without** launching the agent. |
| `RAGENT_FRESH` | *(unset)* | workspace | Set to force a fresh clone even if one exists. |

---

## Provider / agent authentication (not `RAGENT_*`, but required)

These are read by the underlying coding agent, forwarded into the jail from
`~/.config/ragent/env`. See the [sandbox-agent guide](../../guides/sandbox-agent.md)
for the interactive-vs-headless auth details.

| Variable | Applies to | What it does / options |
|---|---|---|
| `ANTHROPIC_API_KEY` | `jailed-claude-code` | Console/API key — **API billing**. Skips the interactive login prompt. |
| `CLAUDE_CODE_OAUTH_TOKEN` | `jailed-claude-code-subscription` | Pro/Max subscription token (`claude setup-token`). Authenticates **headless (`-p`) only**; interactive needs a stored `/login` in the bound `~/.claude`. |
| `CLAUDE_CODE_SIMPLE` | claude-code | `1` ≡ `--bare`; ignores the OAuth token (the non-subscription `jailed-claude-code` path). |
| `OPENAI_API_KEY` | `jailed-opencode` & others | Provider key for OpenAI-backed agents. |

**Recommended for tight egress — _not set by ragent by default_.** With the egress
allowlist on (`api.anthropic.com` only), Claude Code's telemetry/error endpoints are
blocked and it can stall at startup. Set these in `~/.config/ragent/env` to silence
them instead of widening the allowlist:

| Variable | Value | Effect |
|---|---|---|
| `DISABLE_TELEMETRY` | `1` | No Statsig telemetry (a blocked endpoint otherwise). |
| `DISABLE_ERROR_REPORTING` | `1` | No Sentry error reporting. |
| `DISABLE_AUTOUPDATER` | `1` | No background update check. |

---

## Set by ragent — not knobs

These are **exported by ragent for its own child processes**; the agent/report
scripts read them, but you don't set them. Listed so they're not mistaken for
options. The overridable form of the last two is `RAGENT_RUN_BIN` / `RAGENT_REPORT_BIN`
(above).

| Variable | Set by | Holds |
|---|---|---|
| `RAGENT_MAIN` | workspace | Path to the main (source) worktree. |
| `RAGENT_CLONE` | workspace | Path to the agent's working clone. |
| `RAGENT_LOG` | workspace | Path to the agent log (`<clone>/.ragent/agent.log`). |
| `RAGENT_RUN` | workspace | Resolved confine-launcher path. |
| `RAGENT_REPORT` | workspace | Resolved report-generator path. |

---

## A note on `RAGENT_AGENT`'s two defaults

`RAGENT_AGENT` genuinely defaults differently depending on the entrypoint:
`jailed-opencode` for the interactive workspace / `ragent shell`
(`tools/ragent-workspace.sh`), but `jailed-claude-code` for `ragent task orchestrate`
(`tools/ragent/orchestrator.py`). This is a historical divergence, not a designed
one — set `RAGENT_AGENT` explicitly if you care which agent runs. Reconciling the two
defaults is tracked in the backlog, not fixed here.

## Links

- [ADR-0014 — Secrets never in the Nix store](../decisions/0014-runtime-env-secret-forwarding.md)
- [ADR-0015 — cgroup resource caps](../decisions/0015-cgroup-caps-systemd-run.md)
- [ADR-0031 — Network egress allowlist](../decisions/0031-network-egress-allowlist.md)
- [Guide — running a sandboxed agent](../../guides/sandbox-agent.md)
