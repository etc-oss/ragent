#!/usr/bin/env bash
# ragent-serve.sh — serve a project's task reports over HTTP for review on any
# device. HOST-SIDE (outside the jail). Complements the forge: no forge needed,
# just the agent's explanation + diff rendered to HTML (tools/ragent-report.py).
#
# SECURITY: python's http.server is UNAUTHENTICATED and serves your code/diffs in
# the clear — weaker than the forge's token-gated review (roadmap principle #1).
# So it binds 127.0.0.1 by DEFAULT. Reach it from a phone via the Tailscale mesh
# by setting RAGENT_SERVE_HOST to your tailnet IP (opt-in), or an SSH tunnel to
# localhost. Never bind 0.0.0.0 on an untrusted network.
#
# Usage:  ragent-serve.sh <clone-or-project-dir> [port]
#   RAGENT_SERVE_HOST=100.x.y.z ragent-serve.sh <dir>   # Tailscale opt-in

set -euo pipefail

DIR="${1:?usage: ragent-serve.sh <clone-or-project-dir> [port]}"
PORT="${2:-8099}"
HOST="${RAGENT_SERVE_HOST:-127.0.0.1}"
ROOT="$DIR/.ragent/reports/html"

[ -d "$ROOT" ] || { echo "no reports yet at $ROOT — run a task first" >&2; exit 1; }

case "$HOST" in
  127.0.0.1|localhost) note="localhost only (tunnel or set RAGENT_SERVE_HOST=<tailnet-ip> for phone access)";;
  *) note="EXPOSED on $HOST — ensure this is a private Tailscale/VPN address, not public";;
esac
echo "serving task reports:  http://$HOST:$PORT/   ($note)"
echo "  (Ctrl-C to stop)"
exec python3 -m http.server "$PORT" --bind "$HOST" --directory "$ROOT"
