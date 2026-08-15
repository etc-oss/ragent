#!/usr/bin/env python3
"""Integration test for the Forgejo adapter — exercises all 9 verbs against an
ephemeral Forgejo, including the full review lifecycle a distinct reviewer drives.

    nix shell nixpkgs#forgejo nixpkgs#git -c python3 tests/test_forgejo_adapter.py
"""

import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)                                  # ephemeral_forge (sibling)
sys.path.insert(0, os.path.join(HERE, "..", "tools"))    # adapters package

from ragent.adapters.forgejo import ForgejoAdapter  # noqa: E402
from ragent.adapters.base import CODE, REVIEW, CONVERSATION  # noqa: E402
from ephemeral_forge import ephemeral_forge  # noqa: E402


def _git(clone, *args):
    subprocess.run(["git", "-C", clone, *args], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _make_repo():
    """A local repo with a 'master' base and an 'agent/x' branch to push."""
    tmp = tempfile.mkdtemp(prefix="ragent-clone-")
    clone = os.path.join(tmp, "demo")
    os.makedirs(clone)
    _git(clone, "init", "-q", "-b", "master")
    _git(clone, "config", "user.email", "ragent@test")
    _git(clone, "config", "user.name", "ragent")
    with open(os.path.join(clone, "README.md"), "w") as f:
        f.write("# demo\n")
    _git(clone, "add", "-A")
    _git(clone, "commit", "-q", "-m", "base")
    _git(clone, "checkout", "-q", "-b", "agent/x")
    with open(os.path.join(clone, "change.txt"), "w") as f:
        f.write("the agent's change\n")
    _git(clone, "add", "-A")
    _git(clone, "commit", "-q", "-m", "agent change")
    return clone


def _review_as_human(cfg, repo, pr, event, body):
    """The human on the phone submits a review (outside the adapter — the adapter
    only READS it, via status/examine)."""
    req = urllib.request.Request(
        "%s/api/v1/repos/%s/pulls/%d/reviews" % (cfg["url"], repo, pr),
        data=json.dumps({"event": event, "body": body}).encode(), method="POST",
        headers={"Authorization": "token " + cfg["reviewer_token"],
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def main():
    with ephemeral_forge() as cfg:
        repo = "%s/demo" % cfg["user"]
        bot = ForgejoAdapter(cfg["url"], cfg["user"], cfg["token"], repo)

        # meta
        assert bot.ping(), "ping should succeed with a valid token"
        assert bot.capabilities() == {CODE, REVIEW, CONVERSATION}, "forgejo = full caps"
        print("  ok: ping, capabilities")

        # code
        bot.init()
        assert bot._req("GET", "/repos/" + repo).get("full_name") == repo, "init created repo"
        clone = _make_repo()
        bot.push(clone, "agent/x", "master")
        print("  ok: init, push")

        # review lifecycle — open
        pr = bot.handover("agent/x", "master", "demo task", "what the agent changed and why")
        assert isinstance(pr, int), "handover returns a PR number"
        assert bot.status(pr) == "pending", "no reviews yet"
        # idempotent re-handover reuses the same PR (post-push retry path)
        assert bot.handover("agent/x", "master", "demo task", "body") == pr, "reuse open PR"
        print("  ok: handover (+ reuse), status=pending")

        # conversation — agent posts a reply, examine reads it back
        bot.reply(pr, "starting on this")
        assert any("starting on this" in n["body"] for n in bot.examine(pr)), "reply is visible"
        print("  ok: reply, examine (comment)")

        # human requests changes → status flips, examine surfaces the note
        _review_as_human(cfg, repo, pr, "REQUEST_CHANGES", "please add a test for change.txt")
        assert bot.status(pr) == "changes-requested", "status reflects REQUEST_CHANGES"
        notes = bot.examine(pr)
        assert any(n["kind"] == "review" and "add a test" in n["body"] for n in notes), \
            "examine surfaces the human's review note"
        print("  ok: status=changes-requested, examine (review note)")

        # human approves → status flips → bot merges
        # (Forgejo's review-event enum is APPROVED / REQUEST_CHANGES / COMMENT / PENDING)
        _review_as_human(cfg, repo, pr, "APPROVED", "lgtm")
        assert bot.status(pr) == "approved", "status reflects APPROVE"
        bot.merge(pr)
        assert bot._req("GET", "/repos/%s/pulls/%d" % (repo, pr)).get("merged") is True, "merged"
        print("  ok: status=approved, merge")

    print("PASS: all 9 adapter verbs + full review lifecycle")


if __name__ == "__main__":
    main()
