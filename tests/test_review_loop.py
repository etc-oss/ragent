#!/usr/bin/env python3
"""6b review-loop test — the loop MECHANICS (poll→examine→revise→reply→merge) and its
BOUNDS, driven deterministically through _step()/review_loop() with a STUB revise fn
(no LLM, no threads, no real sleeps). The 6a parity run already proved the real jailed
agent revises for real; here we prove the loop orchestrates it correctly and that the
load-bearing runaway guard (max_iterations) actually stops an unresolving review.

    nix shell nixpkgs#forgejo nixpkgs#git -c python3 tests/test_review_loop.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)                                  # ephemeral_forge, test_forgejo_adapter
sys.path.insert(0, os.path.join(HERE, "..", "tools"))    # adapters, orchestrator

import orchestrator  # noqa: E402
from adapters.forgejo import ForgejoAdapter  # noqa: E402
from ephemeral_forge import ephemeral_forge  # noqa: E402
from test_forgejo_adapter import _make_repo, _review_as_human, _git  # noqa: E402


def _open_pr(cfg, name):
    repo = "%s/%s" % (cfg["user"], name)
    bot = ForgejoAdapter(cfg["url"], cfg["user"], cfg["token"], repo)
    bot.init()
    clone = _make_repo()
    bot.push(clone, "agent/x", "master")
    pr = bot.handover("agent/x", "master", "loop task", "body")
    return bot, clone, pr, repo


def _merged(bot, repo, pr):
    return bot._req("GET", "/repos/%s/pulls/%d" % (repo, pr)).get("merged")


def test_mechanics(cfg):
    bot, clone, pr, repo = _open_pr(cfg, "loopa")
    calls = []

    def stub_revise(clone_, agent_, prompt_):
        calls.append(prompt_)                              # a deterministic "fix"
        with open(os.path.join(clone_, "change.txt"), "a") as f:
            f.write("addressed\n")
        _git(clone_, "commit", "-aqm", "address review")

    step = lambda: orchestrator._step(bot, pr, clone, "agent/x", "master",
                                      "stub", processed, True, stub_revise)
    processed = set()

    # pending → no human note yet → waiting (no revision)
    assert step()[1] == "waiting"
    assert calls == []

    # human requests changes → the agent revises exactly once
    _review_as_human(cfg, repo, pr, "REQUEST_CHANGES", "please add a docstring")
    assert step()[1] == "revised"
    assert len(calls) == 1 and len(processed) == 1

    # step again with no NEW human note: the old note is processed and the bot's own
    # reply carries REPLY_MARKER → nothing new → waiting (old notes are NOT re-fed)
    assert step()[1] == "waiting"
    assert len(calls) == 1, "old notes must not be re-fed to the agent"

    # human approves → merged (auto_merge=True)
    _review_as_human(cfg, repo, pr, "APPROVED", "lgtm")
    assert step()[1] == "merged"
    assert _merged(bot, repo, pr) is True
    print("  ok: mechanics — one revision, old notes not re-fed, approved→merged")


def test_bounds(cfg):
    bot, clone, pr, repo = _open_pr(cfg, "loopb")
    n = {"i": 0}

    # A reviewer that NEVER approves: after each "fix" the stub posts a fresh
    # REQUEST_CHANGES as the human, so new notes keep arriving — the loop must stop
    # itself at max_iterations (the human-paced loop's load-bearing runaway guard).
    def stub_revise_then_nag(clone_, agent_, prompt_):
        with open(os.path.join(clone_, "change.txt"), "a") as f:
            f.write("try\n")
        _git(clone_, "commit", "-aqm", "attempt")
        n["i"] += 1
        _review_as_human(cfg, repo, pr, "REQUEST_CHANGES", "still not right #%d" % n["i"])

    _review_as_human(cfg, repo, pr, "REQUEST_CHANGES", "start")
    outcome = orchestrator.review_loop(
        bot, pr, clone, "agent/x", "master", "stub",
        bounds={"max_iterations": 2, "max_agent_min": 999, "max_wall_hours": 999},
        poll_interval=0, auto_merge=True, revise=stub_revise_then_nag)

    assert outcome == "needs-human", outcome
    assert n["i"] == 2, "stopped at exactly max_iterations=2 revisions (got %d)" % n["i"]
    assert any("needs-human" in x["body"] for x in bot.examine(pr)), "needs-human reply posted"
    assert _merged(bot, repo, pr) in (False, None), "must NOT merge an unresolved review"
    print("  ok: bounds — stopped at maxIterations=2 with a needs-human reply, unmerged")


def main():
    with ephemeral_forge() as cfg:
        test_mechanics(cfg)
        test_bounds(cfg)
    print("PASS: 6b review loop — mechanics + bounds")


if __name__ == "__main__":
    main()
