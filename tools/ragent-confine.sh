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

# --- network egress allowlist (ADR-0031) -------------------------------------
# Default-DENY outbound; allow ONLY the LLM API host(s) (+ localhost + the DNS
# resolver), enforced by a kernel BPF IP filter on a SYSTEM scope — because `--user`
# scopes do NOT enforce IP filtering (verified on systemd 255). So a prompt-injected
# or malicious agent cannot exfiltrate the clone or fetch arbitrary packages. Needs
# passwordless sudo + setpriv (to drop the scope back to the caller's uid). Knobs:
#   RAGENT_EGRESS_ALLOW="host1 host2"   hosts to allow (default: api.anthropic.com)
#   RAGENT_EGRESS_OPEN=1                disable filtering (old open-network behaviour)
USERHOME="$HOME"
_egress_args() {                                   # NUL-separated systemd-run -p args
  printf '%s\0' -p 'IPAddressDeny=any' -p 'IPAddressAllow=127.0.0.0/8' -p 'IPAddressAllow=::1/128'
  local h ip
  for h in ${RAGENT_EGRESS_ALLOW:-api.anthropic.com} \
           $(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null); do
    for ip in $(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u); do
      printf '%s\0' -p "IPAddressAllow=$ip"
    done
  done
}

if command -v systemd-run >/dev/null 2>&1 && [ -z "${RAGENT_EGRESS_OPEN:-}" ] \
   && command -v setpriv >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  # Filtered: a SYSTEM scope carrying the cgroup caps AND the egress allowlist,
  # dropped back to the caller (setpriv) so the agent never runs as root. The token
  # rides the inherited env (sudo -E); HOME is re-pinned for the ~/.claude bind.
  mapfile -d '' _EG < <(_egress_args)
  echo "confined + capped + egress-allowlisted [${RAGENT_EGRESS_ALLOW:-api.anthropic.com}]" >&2
  exec sudo -En systemd-run --scope --quiet \
    -p MemoryMax="$MEM" -p CPUQuota="$CPU" -p TasksMax="$TASKS" \
    "${_EG[@]}" \
    -- setpriv --reuid="$(id -u)" --regid="$(id -g)" --clear-groups \
    -- env "HOME=$USERHOME" "$AGENT" "$@"
elif command -v systemd-run >/dev/null 2>&1; then
  # No egress filter available (no sudo/setpriv, or RAGENT_EGRESS_OPEN=1): cgroup caps
  # via a --user scope, but the network is OPEN. See SECURITY.md.
  [ -n "${RAGENT_EGRESS_OPEN:-}" ] \
    || echo "warning: network egress is UNRESTRICTED (need passwordless sudo + setpriv to allowlist; set RAGENT_EGRESS_OPEN=1 to silence)" >&2
  exec systemd-run --user --scope --quiet \
    -p MemoryMax="$MEM" -p CPUQuota="$CPU" -p TasksMax="$TASKS" \
    -- "$AGENT" "$@"
else
  echo "warning: systemd-run not found; running WITHOUT cgroup caps or egress limits" >&2
  exec "$AGENT" "$@"
fi
