"""Forgejo review-transport adapter (ADR-0020), stdlib-only (urllib — no requests/SDK,
matching okf_render's dependency-light ethos).

Runs HOST-SIDE, outside the jail; the token is runtime env, never in the repo/flake
(ADR-0011/0014). The same code drives a local dev Forgejo or a remote NixOS
`services.forgejo` on Tailscale — only RAGENT_FORGE_URL/TOKEN differ.

Env (from ~/.config/ragent/forge.env):
    RAGENT_FORGE_URL    e.g. http://127.0.0.1:3000  (or https://forge.tailnet)
    RAGENT_FORGE_USER   owner login (default ci)
    RAGENT_FORGE_TOKEN  API token (write:repository,write:issue,write:user)
    RAGENT_FORGE_REPO   owner/repo  (default <user>/<project-basename>)
"""

import json
import os
import subprocess
import time
import urllib.error
import urllib.request

from .base import ReviewAdapter, CODE, REVIEW, CONVERSATION

# Belt-and-suspenders marker so the 6b loop never re-feeds the orchestrator's own
# replies to the agent as if they were human review notes (matters when the bot and
# the reviewer are the same forge user, e.g. in a single-user test).
REPLY_MARKER = "\U0001f916 ragent"  # 🤖 ragent


class ForgejoAdapter(ReviewAdapter):
    def __init__(self, url, user, token, repo):
        self.url = url.rstrip("/")
        self.user = user
        self.token = token
        self.repo = repo
        self.api = self.url + "/api/v1"

    @classmethod
    def from_env(cls, repo=None):
        url = os.environ.get("RAGENT_FORGE_URL")
        token = os.environ.get("RAGENT_FORGE_TOKEN")
        if not url or not token:
            raise SystemExit("set RAGENT_FORGE_URL and RAGENT_FORGE_TOKEN (source forge.env)")
        user = os.environ.get("RAGENT_FORGE_USER", "ci")
        repo = repo or os.environ.get("RAGENT_FORGE_REPO")
        if not repo:
            raise SystemExit("set RAGENT_FORGE_REPO (owner/repo)")
        return cls(url, user, token, repo)

    # --- HTTP -----------------------------------------------------------------
    def _req(self, method, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            self.api + path, data=data, method=method,
            headers={"Authorization": "token " + self.token,
                     "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                raw = r.read()
                out = json.loads(raw) if raw else {}
                if isinstance(out, dict):
                    out.setdefault("_status", r.status)
                return out
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                out = json.loads(raw)
            except Exception:
                out = {"message": raw.decode("utf-8", "replace")}
            if isinstance(out, dict):
                out["_status"] = e.code
            return out

    # --- meta -----------------------------------------------------------------
    def ping(self) -> bool:
        r = self._req("GET", "/user")
        return isinstance(r, dict) and r.get("login") == self.user

    def capabilities(self) -> set:
        return {CODE, REVIEW, CONVERSATION}

    # --- code -----------------------------------------------------------------
    def init(self) -> None:
        r = self._req("GET", "/repos/" + self.repo)
        if isinstance(r, dict) and r.get("full_name"):
            return
        self._req("POST", "/user/repos",
                  {"name": self.repo.split("/", 1)[-1], "auto_init": False, "private": True})

    def push(self, clone, branch, base) -> None:
        host = self.url.split("://", 1)[-1]
        remote = "http://%s:%s@%s/%s.git" % (self.user, self.token, host, self.repo)
        # Base FIRST — a PR needs its base branch resolvable on the forge — then head.
        subprocess.run(["git", "-C", clone, "push", "-q", remote, base], check=True)
        subprocess.run(["git", "-C", clone, "push", "-qf", remote, branch], check=True)

    # --- review lifecycle -----------------------------------------------------
    def handover(self, branch, base, title, body):
        last = None
        # Right after a push Forgejo can briefly fail to resolve the branch
        # ("target couldn't be found"); retry, and reuse an already-open PR.
        for _ in range(4):
            r = self._req("POST", "/repos/%s/pulls" % self.repo,
                          {"head": branch, "base": base, "title": title, "body": body})
            if isinstance(r, dict) and r.get("number"):
                return r["number"]
            last = r
            opens = self._req("GET", "/repos/%s/pulls?state=open" % self.repo)
            if isinstance(opens, list):
                for p in opens:
                    if p.get("head", {}).get("ref") == branch:
                        return p["number"]
            time.sleep(2)
        raise RuntimeError("handover failed: %s" % str(last)[:200])

    def review_url(self, review) -> str:
        return "%s/%s/pulls/%s" % (self.url, self.repo, review)

    def status(self, review) -> str:
        revs = self._req("GET", "/repos/%s/pulls/%s/reviews" % (self.repo, review))
        states = [x.get("state") for x in revs] if isinstance(revs, list) else []
        if "APPROVED" in states:
            return "approved"
        if "REQUEST_CHANGES" in states:
            return "changes-requested"
        return "pending"

    def merge(self, review) -> None:
        r = self._req("POST", "/repos/%s/pulls/%s/merge" % (self.repo, review), {"Do": "merge"})
        if isinstance(r, dict) and r.get("_status", 200) >= 300:
            raise RuntimeError("merge failed: %s" % r.get("message"))

    # --- conversation ---------------------------------------------------------
    def examine(self, review) -> list:
        notes = []
        revs = self._req("GET", "/repos/%s/pulls/%s/reviews" % (self.repo, review))
        if isinstance(revs, list):
            for x in revs:
                body = (x.get("body") or "").strip()
                if body:
                    notes.append({"ts": x.get("submitted_at") or x.get("created_at") or "",
                                  "author": (x.get("user") or {}).get("login", "?"),
                                  "body": body, "kind": "review"})
        cs = self._req("GET", "/repos/%s/issues/%s/comments" % (self.repo, review))
        if isinstance(cs, list):
            for c in cs:
                body = (c.get("body") or "").strip()
                if body:
                    notes.append({"ts": c.get("created_at") or "",
                                  "author": (c.get("user") or {}).get("login", "?"),
                                  "body": body, "kind": "comment"})
        notes.sort(key=lambda n: n["ts"])
        return notes

    def reply(self, review, text) -> None:
        marked = text if text.startswith(REPLY_MARKER) else "%s: %s" % (REPLY_MARKER, text)
        self._req("POST", "/repos/%s/issues/%s/comments" % (self.repo, review), {"body": marked})
