#!/usr/bin/env bash
# forgejo-local.sh — a LOCAL Forgejo for development (a test scaffold, not the
# deliverable; the real hosting is the NixOS `services.forgejo` on Tailscale in a
# config repo like your-config-repo). Local and remote differ ONLY in config/URL —
# the adapter code is identical (ADR-0020).
#
# Starts Forgejo on 127.0.0.1, creates an admin + a fresh API token, and writes the
# transport env to ~/.config/ragent/forge.env (0600) for the orchestrator to source.
#
#   nix run .#forgejo-local            # starts it in the foreground (Ctrl-C to stop)
#   source ~/.config/ragent/forge.env  # in another shell, before orchestrating

set -euo pipefail

W="${RAGENT_FORGE_WORK:-$HOME/.local/share/ragent-forge}"
PORT="${RAGENT_FORGE_PORT:-3000}"
USER_NAME="${RAGENT_FORGE_USER:-ci}"
URL="http://127.0.0.1:$PORT"
ENVF="$HOME/.config/ragent/forge.env"
BIN="$(command -v forgejo)"

mkdir -p "$W/custom/conf" "$W/repos" "$W/data" "$(dirname "$ENVF")"
if [ ! -f "$W/custom/conf/app.ini" ]; then
  cat > "$W/custom/conf/app.ini" <<INI
APP_NAME = ragent-forge
[server]
HTTP_ADDR = 127.0.0.1
HTTP_PORT = $PORT
ROOT_URL = $URL/
DISABLE_SSH = true
[database]
DB_TYPE = sqlite3
PATH = $W/data/forgejo.db
[repository]
ROOT = $W/repos
[security]
INSTALL_LOCK = true
SECRET_KEY = ragent-local-dev-secret-change-for-remote
[service]
DISABLE_REGISTRATION = true
[log]
LEVEL = Error
INI
fi

run() { "$BIN" --work-path "$W" --config "$W/custom/conf/app.ini" "$@"; }

run migrate >/dev/null
# Create admin (idempotent — ignore "already exists").
run admin user create --username "$USER_NAME" --password 'ragent-DevPass1' \
  --email "$USER_NAME@example.com" --admin --must-change-password=false >/dev/null 2>&1 || true
# A fresh token each start (issue write is needed — a PR is an "issue" in the API).
TOKEN="$(run admin user generate-access-token --username "$USER_NAME" \
  --scopes 'write:repository,write:issue,write:user' --token-name "ragent-$(date +%s)" \
  --raw 2>/dev/null | tr -d '[:space:]')"

umask 077
{ echo "export RAGENT_ADAPTER=forgejo"
  echo "export RAGENT_FORGE_URL=$URL"
  echo "export RAGENT_FORGE_USER=$USER_NAME"
  echo "export RAGENT_FORGE_TOKEN=$TOKEN"
} > "$ENVF"

echo "Forgejo (local): $URL"
echo "  transport env → $ENVF   (source it before: nix run .#orchestrate -- <project> <task> <prompt>)"
echo "  token minted (write:repository,issue,user). Ctrl-C to stop."
# exec the binary directly (not the `run` function — exec can't run a shell function).
exec "$BIN" --work-path "$W" --config "$W/custom/conf/app.ini" web
