#!/usr/bin/env python3
"""ragent dev-forge — a first-class LOCAL Forgejo so the async review loop runs out of
the box (ADR-0029).

Deliberately **not** docker-compose: the Lima guest has no Docker daemon, and nixpkgs
already ships `forgejo` — the same substrate `tests/ephemeral_forge.py` proves. This is
the human-facing sibling of that throwaway test fixture: persistent data, one admin user,
and it writes the `forge.env` the adapter reads.

    nix run .#dev-forge                 # Forgejo on http://127.0.0.1:3000 + writes forge.env
    source ~/.config/ragent/forge.env   # in ANOTHER shell (this one stays foreground)
    ragent task orchestrate "$PWD" demo "add a subtract() to calc.py with a test"

Runs `forgejo web` in the FOREGROUND (Ctrl-C to stop) — so there is no lingering daemon to
leveldb-lock the data dir on the next run (the flake `ephemeral_forge` was written to dodge).

Env knobs:
    RAGENT_DEV_FORGE_PORT   default 3000
    RAGENT_DEV_FORGE_DIR    data dir, default ~/.local/share/ragent/dev-forge
    RAGENT_DEV_FORGE_USER   admin login, default ragent
    RAGENT_FORGE_ENV        forge.env path, default ~/.config/ragent/forge.env

Hard-won bits carried over from ephemeral_forge.py: migrate BEFORE admin-create;
INSTALL_LOCK + DISABLE_SSH; sqlite; a token minted via the admin CLI (no web server needed).
"""

import os
import shutil
import socket
import subprocess
import sys
import time


def _port_in_use(port):
    s = socket.socket()
    try:
        return s.connect_ex(("127.0.0.1", port)) == 0
    finally:
        s.close()


def main():
    binp = shutil.which("forgejo") or shutil.which("gitea")
    if not binp:
        raise SystemExit("forgejo not on PATH (the .#dev-forge app is supposed to provide it)")

    port = int(os.environ.get("RAGENT_DEV_FORGE_PORT", "3000"))
    work = os.path.expanduser(os.environ.get("RAGENT_DEV_FORGE_DIR", "~/.local/share/ragent/dev-forge"))
    user = os.environ.get("RAGENT_DEV_FORGE_USER", "ragent")
    env_path = os.path.expanduser(os.environ.get("RAGENT_FORGE_ENV", "~/.config/ragent/forge.env"))
    url = "http://127.0.0.1:%d" % port

    if _port_in_use(port):
        raise SystemExit(
            "port %d is already in use — dev forge already running?\n"
            "  stop it (Ctrl-C in its terminal), or set RAGENT_DEV_FORGE_PORT to a free port." % port)

    conf = os.path.join(work, "custom", "conf")
    for d in (conf, os.path.join(work, "repos"), os.path.join(work, "data")):
        os.makedirs(d, exist_ok=True)
    ini = os.path.join(conf, "app.ini")
    with open(ini, "w") as f:
        f.write(
            "APP_NAME = ragent-dev-forge\n"
            "RUN_MODE = prod\n"
            "[server]\n"
            "HTTP_ADDR = 127.0.0.1\n"        # localhost only — never a public port (ADR-0020)
            "HTTP_PORT = %d\n"
            "ROOT_URL = %s/\n"
            "DISABLE_SSH = true\n"
            "[database]\n"
            "DB_TYPE = sqlite3\n"
            "PATH = %s/data/forgejo.db\n"
            "[repository]\n"
            "ROOT = %s/repos\n"
            "[security]\n"
            "INSTALL_LOCK = true\n"
            "SECRET_KEY = ragent-dev-forge-local-secret\n"
            "[service]\n"
            "DISABLE_REGISTRATION = true\n"
            "[log]\n"
            "LEVEL = Info\n"
            "MODE = console\n" % (port, url, work, work))

    def cli(*args):
        return subprocess.run([binp, "--work-path", work, "--config", ini, *args],
                              capture_output=True, text=True)

    cli("migrate")  # migrate BEFORE creating the user; idempotent across runs
    # Create the admin user if absent; harmless "already exists" on later runs is ignored.
    cli("admin", "user", "create", "--username", user, "--password", "ragent-DevPass1",
        "--email", "%s@dev.forge" % user, "--admin", "--must-change-password=false")
    # Always mint a FRESH token (unique name) and write it — so forge.env is always valid.
    r = cli("admin", "user", "generate-access-token", "--username", user,
            "--scopes", "write:repository,write:issue,write:user",
            "--token-name", "ragent-dev-%d" % int(time.time()), "--raw")
    token = r.stdout.strip()
    if not token:
        raise SystemExit("failed to mint an access token:\n" + (r.stderr or r.stdout))

    os.makedirs(os.path.dirname(env_path) or ".", exist_ok=True)
    fd = os.open(env_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(
            "# written by `ragent dev-forge` (ADR-0029) — source me, then `ragent task orchestrate`\n"
            "export RAGENT_ADAPTER=forgejo\n"
            "export RAGENT_FORGE_URL=%s\n"
            "export RAGENT_FORGE_USER=%s\n"
            "export RAGENT_FORGE_TOKEN=%s\n" % (url, user, token))

    print("ragent dev-forge  →  %s   (admin user: %s)" % (url, user))
    print("wrote %s  (0600)" % env_path)
    print("next, in ANOTHER shell:")
    print("  source %s && ragent task orchestrate \"$PWD\" demo \"<your prompt>\"" % env_path)
    print("Ctrl-C here to stop the forge.\n")
    sys.stdout.flush()
    # Foreground: REPLACE this process with the web server so Ctrl-C stops it cleanly and
    # no daemon lingers to lock the data dir on the next run.
    os.execvp(binp, [binp, "--work-path", work, "--config", ini, "web"])


if __name__ == "__main__":
    main()
