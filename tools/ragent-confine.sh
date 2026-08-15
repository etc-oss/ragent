#!/usr/bin/env bash
# ragent-confine.sh — launch a jailed agent with cgroup resource caps.
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
# Usage:  ragent-confine.sh <path-to-jailed-agent-bin> [args...]
#   e.g.  nix build .#jailed-opencode -o result-agent
#         ./tools/ragent-confine.sh ./result-agent/bin/* --help

set -euo pipefail

MEM="${RAGENT_MEM_MAX:-4G}"       # override via env
CPU="${RAGENT_CPU_QUOTA:-200%}"   # 200% = up to 2 cores
TASKS="${RAGENT_TASKS_MAX:-512}"  # PID cap (fork-bomb guard)

AGENT="${1:?usage: ragent-confine.sh <jailed-agent-bin> [args...]}"; shift || true
[ -x "$AGENT" ] || { echo "not executable: $AGENT" >&2; exit 1; }

# Pre-create dirs the jail bind-mounts read-write: bwrap aborts with "Can't find
# source path" if a bind source is missing. Agent state dirs must exist first.
# Set a space-separated list, e.g. for opencode:
#   RAGENT_PRECREATE_DIRS="$HOME/.config/opencode $HOME/.local/share/opencode $HOME/.local/state/opencode"
if [ -n "${RAGENT_PRECREATE_DIRS:-}" ]; then
  # shellcheck disable=SC2086
  mkdir -p $RAGENT_PRECREATE_DIRS
fi

# Load runtime secrets (provider key / Claude OAuth token) from the conventional 0600
# file if present, so they're in the environment for the jail's fwd-env to forward
# (ADR-0014) — no manual `export` each session. Secrets never enter the Nix store.
if [ -f "$HOME/.config/ragent/env" ]; then
  set -a; . "$HOME/.config/ragent/env"; set +a
fi

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
