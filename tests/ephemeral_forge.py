"""Ephemeral Forgejo for adapter tests — a throwaway instance, spun up and torn
down per run, with every harness flake this project already fought baked out:

  * unique free port (never the hardcoded 3000 that a stale instance can hold)
  * migrate BEFORE admin-create; INSTALL_LOCK + DISABLE_SSH in app.ini
  * readiness poll on /api/v1/version (not a fixed sleep)
  * teardown via the process HANDLE + a fresh temp dir (never `pkill -f forgejo`,
    which once matched — and killed — its own shell)

Yields two admin users so the full review lifecycle is exercisable with a reviewer
distinct from the PR author (a user can't approve their own PR):
    bot      — the orchestrator's token owner (opens/merges PRs)
    reviewer — stands in for the human on the phone (submits reviews)

Needs `forgejo` on PATH:  nix shell nixpkgs#forgejo nixpkgs#git -c python3 ...
"""

import contextlib
import os
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.request


def _free_port():
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]
    finally:
        s.close()


def _wait_http(url, timeout=90):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2) as r:
                if r.status < 500:
                    return True
        except Exception:
            time.sleep(0.5)
    return False


@contextlib.contextmanager
def ephemeral_forge(bot="ci", reviewer="human"):
    binp = shutil.which("forgejo") or shutil.which("gitea")
    if not binp:
        raise RuntimeError("forgejo not on PATH — run inside `nix shell nixpkgs#forgejo`")

    work = tempfile.mkdtemp(prefix="ragent-forge-")
    port = _free_port()
    url = "http://127.0.0.1:%d" % port
    conf = os.path.join(work, "custom", "conf")
    for d in (conf, os.path.join(work, "repos"), os.path.join(work, "data")):
        os.makedirs(d, exist_ok=True)
    ini = os.path.join(conf, "app.ini")
    with open(ini, "w") as f:
        f.write(
            "APP_NAME = ragent-test-forge\n"
            "RUN_MODE = prod\n"
            "[server]\n"
            "HTTP_ADDR = 127.0.0.1\n"
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
            "SECRET_KEY = ragent-ephemeral-test-secret\n"
            "[service]\n"
            "DISABLE_REGISTRATION = true\n"
            "[log]\n"
            "LEVEL = Error\n"
            "MODE = console\n" % (port, url, work, work)
        )

    def cli(*args):
        return subprocess.run([binp, "--work-path", work, "--config", ini, *args],
                              capture_output=True, text=True)

    def mkuser(name):
        cli("admin", "user", "create", "--username", name, "--password", "ragent-DevPass1",
            "--email", "%s@example.com" % name, "--admin", "--must-change-password=false")
        r = cli("admin", "user", "generate-access-token", "--username", name,
                "--scopes", "write:repository,write:issue,write:user",
                "--token-name", "ragent-%d" % int(time.time() * 1000), "--raw")
        return r.stdout.strip()

    cli("migrate")  # migrate BEFORE creating users
    bot_token = mkuser(bot)
    reviewer_token = mkuser(reviewer)

    proc = subprocess.Popen([binp, "--work-path", work, "--config", ini, "web"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        if not _wait_http(url + "/api/v1/version"):
            raise RuntimeError("ephemeral forgejo did not become ready on " + url)
        yield {
            "url": url,
            "user": bot, "token": bot_token,
            "reviewer": reviewer, "reviewer_token": reviewer_token,
        }
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
        shutil.rmtree(work, ignore_errors=True)
