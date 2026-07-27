#!/usr/bin/env python3
"""ragent orchestrator (ADR-0020 / ADR-0022) — per-task, transport-agnostic.

HOST-SIDE: it drives a review ADAPTER (which holds the forge token, kept OUT of
the jail, ADR-0011/0014); the jailed agent only commits in its clone (ADR-0016).

6a scope (this module): set up the clone → run the confined agent → generate the
task report → adapter init/push/handover (a PR you can open on your phone). The
orchestrator branches on the adapter's `capabilities`, never on its identity, so a
partial transport degrades gracefully. The bounded comment→revise→merge loop is 6b.
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # so `adapters` (and the report generator) resolve

from adapters import load, CODE, REVIEW, CONVERSATION  # noqa: E402

# Appended to every task prompt so the agent leaves the artifacts review needs.
_PROMPT_SUFFIX = """

When finished: write a brief .ragent/EXPLAIN.md (2-3 sentences on what you changed
and why), then stage and commit all changes with a clear message."""


def _base_branch(project):
    r = subprocess.run(["git", "-C", project, "branch", "--show-current"],
                       capture_output=True, text=True)
    return r.stdout.strip() or "master"


def _run_agent(clone, agent, prompt):
    """Run the confined agent in its clone (spawn-agent.sh → ragent-confine.sh →
    the jailed agent). It commits in the clone and auto-generates the HTML report."""
    env = os.environ.copy()
    env["RAGENT_AGENT"] = agent
    proc = subprocess.run(["./.ragent/spawn-agent.sh", "-p", prompt,
                           "--dangerously-skip-permissions"],
                          cwd=clone, env=env, capture_output=True, text=True)
    for line in (proc.stdout + proc.stderr).splitlines()[-6:]:
        print("  agent:", line)


def _review_body(clone, task):
    explain = os.path.join(clone, ".ragent", "EXPLAIN.md")
    if os.path.isfile(explain) and os.path.getsize(explain) > 0:
        with open(explain) as f:
            body = f.read().rstrip()
    else:
        body = "_(no EXPLAIN.md was written)_"
    body += ("\n\n---\nFull explanation + rendered diff (served report):\n"
             "`ragent task review %s`  →  http://127.0.0.1:8099/%s.html\n"
             % (clone, task))
    return body


def orchestrate(project, task, prompt, agent=None):
    """Run one task through: setup → confined agent → publish review. Returns the
    review handle (or None for a review-less transport)."""
    project = os.path.abspath(project)
    agent = agent or os.environ.get("RAGENT_AGENT", "jailed-claude-code")
    branch = "agent/" + task
    clone = os.environ.get("RAGENT_CLONE_DIR") or (project.rstrip("/") + "-agent-" + task)
    base = _base_branch(project)

    user = os.environ.get("RAGENT_FORGE_USER", "ci")
    repo = os.environ.get("RAGENT_FORGE_REPO") or (user + "/" + os.path.basename(project))
    os.environ["RAGENT_FORGE_REPO"] = repo  # the report + adapter see the same repo
    adapter = load(repo=repo)

    print("▶ orchestrate: task '%s' on %s (%s) via %s → %s"
          % (task, project, base, os.environ.get("RAGENT_ADAPTER"), repo))

    # 0. Health/auth + capabilities up front — fail early, before doing any work.
    if not adapter.ping():
        raise SystemExit("adapter ping failed — forge unreachable or token invalid "
                         "(source ~/.config/ragent/forge.env)")
    caps = adapter.capabilities()

    # 1. Set up the agent clone + spawn helper (reuse the workspace boundary logic).
    env = os.environ.copy()
    env["RAGENT_SETUP_ONLY"] = "1"
    env["RAGENT_AGENT"] = agent
    subprocess.run(["bash", os.path.join(HERE, "ragent-workspace.sh"), project, task],
                   env=env, check=True, stdout=subprocess.DEVNULL)

    # 2. Run the confined agent (commits in the clone, writes EXPLAIN.md).
    print("▶ running %s (confined) …" % agent)
    _run_agent(clone, agent, prompt + _PROMPT_SUFFIX)

    # 3. Publish, gated on what the transport can do (ADR-0022 capabilities).
    if CODE not in caps:
        raise SystemExit("adapter cannot push code (capabilities lack 'code')")
    print("▶ publishing …")
    adapter.init()
    adapter.push(clone, branch, base)

    if REVIEW not in caps:
        # Degraded transport (e.g. a code-only git-over-SSH remote): no PR surface,
        # so fall back to the forge-independent served report (ADR-0021).
        print("ℹ this transport has no review UI (capabilities lack 'review'); "
              "review via the served report:  ragent task review %s" % clone)
        return None

    review = adapter.handover(branch, base, task, _review_body(clone, task))
    print("✓ review opened: %s" % adapter.review_url(review))
    print("  (6a: review it on your phone; the comment→revise→merge loop is 6b)")
    return review


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) < 3:
        raise SystemExit("usage: orchestrator.py <project-dir> <task> <prompt>")
    orchestrate(argv[0], argv[1], argv[2])


if __name__ == "__main__":
    main()
