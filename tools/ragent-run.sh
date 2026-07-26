#!/usr/bin/env bash
# ragent-run.sh — launch a jailed agent with cgroup resource caps.
#
# jail.nix confines the filesystem/namespaces but does NOT impose cgroup resource
# LIMITS (it only isolates the cgroup namespace). So we add CPU/memory/PID caps
# here with a transient systemd scope — cheap fork-bomb / runaway insurance
# (ADR-0015). Runs INSIDE the Lima Linux guest.
#
# The provider API key is taken from the caller's environment and forwarded into
# the jail at runtime by the jail's `fwd-env` combinator; it never enters the Nix
# store or this script's arguments (ADR-0014). Export it before running, e.g.:
#   export ANTHROPIC_API_KEY=...    # for jailed-claude-code
#
# Usage:  ragent-run.sh <path-to-jailed-agent-bin> [args...]
#   e.g.  nix build .#jailed-opencode -o result-agent
#         ./tools/ragent-run.sh ./result-agent/bin/* --help

set -euo pipefail

MEM="${RAGENT_MEM_MAX:-4G}"       # override via env
CPU="${RAGENT_CPU_QUOTA:-200%}"   # 200% = up to 2 cores
TASKS="${RAGENT_TASKS_MAX:-512}"  # PID cap (fork-bomb guard)

AGENT="${1:?usage: ragent-run.sh <jailed-agent-bin> [args...]}"; shift || true
[ -x "$AGENT" ] || { echo "not executable: $AGENT" >&2; exit 1; }

if command -v systemd-run >/dev/null 2>&1; then
  # NOTE (ADR-0015): --user scopes only enforce CPU/memory if the controllers are
  # delegated to the user session (a `Delegate=cpu memory pids` drop-in, or run as
  # root). Verify with `systemd-cgls` / by forcing an over-limit process before
  # trusting the caps. If delegation is missing, this still runs — just uncapped.
  exec systemd-run --user --scope --quiet \
    -p MemoryMax="$MEM" -p CPUQuota="$CPU" -p TasksMax="$TASKS" \
    -- "$AGENT" "$@"
else
  echo "warning: systemd-run not found; running WITHOUT cgroup caps" >&2
  exec "$AGENT" "$@"
fi
