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
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # so `adapters` (and the report generator) resolve

from adapters import load, CODE, REVIEW, CONVERSATION, REPLY_MARKER  # noqa: E402

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


# --- 6b: the bounded review loop (ADR-0024) ----------------------------------
# The loop is HUMAN-PACED: the confined agent revises ONLY in response to a NEW
# human note (it has no forge access; the bot's own replies carry REPLY_MARKER and
# are filtered out). It cannot self-trigger — so `max_iterations` is the load-bearing
# runaway guard. Wall-clock is a *resource* cap (orchestrator lifetime, in HOURS),
# not a misbehavior signal; "cost" is cumulative AGENT runtime (never human idle).

def _sig(note):
    return (note["kind"], note["ts"], note["author"], note["body"])


def _review_config():
    def _i(k, d):
        return int(os.environ.get(k, d))

    def _f(k, d):
        return float(os.environ.get(k, d))

    return {
        "poll_interval": _f("RAGENT_POLL_INTERVAL", 20),
        "auto_merge": os.environ.get("RAGENT_AUTO_MERGE", "").lower() in ("1", "true", "yes"),
        "bounds": {
            "max_iterations": _i("RAGENT_MAX_ITERATIONS", 6),
            "max_agent_min": _f("RAGENT_MAX_AGENT_MIN", 30),
            "max_wall_hours": _f("RAGENT_MAX_WALL_HOURS", 24),
        },
    }


def _step(adapter, review, clone, branch, base, agent, processed, auto_merge, revise):
    """One poll-and-maybe-revise. Returns (status, action, agent_seconds_spent);
    action ∈ {'merged','approved','revised','waiting'}. Mutates `processed` (the set
    of note signatures already fed to the agent). Split out from the loop so the
    mechanics are unit-testable without threads or real sleeps."""
    st = adapter.status(review)
    if st == "approved":
        if auto_merge:
            adapter.merge(review)
            return (st, "merged", 0.0)
        return (st, "approved", 0.0)
    if st == "changes-requested":
        new = [n for n in adapter.examine(review)
               if _sig(n) not in processed and not n["body"].startswith(REPLY_MARKER)]
        if new:
            body = ("Address these review comments, then commit:\n\n"
                    + "\n\n".join("- " + n["body"] for n in new))
            t0 = time.monotonic()
            revise(clone, agent, body + _PROMPT_SUFFIX)
            spent = time.monotonic() - t0
            adapter.push(clone, branch, base)
            adapter.reply(review, "addressed the latest review notes; pushed an update.")
            for n in new:
                processed.add(_sig(n))
            return (st, "revised", spent)
    return (st, "waiting", 0.0)


def review_loop(adapter, review, clone, branch, base, agent, *,
                bounds, poll_interval, auto_merge, revise=None):
    """Bounded examine→revise→reply→merge loop, per task until resolved. A thin
    sleep+bounds wrapper around `_step`. State (`processed`) is in-memory: a crash
    re-feeds notes on restart — fine for a per-task process; persist to `.ragent/`
    if this ever outlives one task."""
    revise = revise or _run_agent
    processed = set()
    iterations = 0
    agent_seconds = 0.0
    start = time.monotonic()
    while True:
        st, action, spent = _step(adapter, review, clone, branch, base, agent,
                                  processed, auto_merge, revise)
        agent_seconds += spent
        if action == "merged":
            print("✓ approved → merged")
            return "merged"
        if action == "approved":
            print("✓ approved — merge when ready (autoMerge off)")
            return "approved"
        if action == "revised":
            iterations += 1
            print("↻ revision %d pushed; awaiting re-review" % iterations)
            # The load-bearing runaway guard (human-paced loop → count revisions).
            if iterations >= bounds["max_iterations"]:
                adapter.reply(review, "%s: needs-human — hit maxIterations=%d without approval."
                              % (REPLY_MARKER, bounds["max_iterations"]))
                print("⚠ needs-human: maxIterations")
                return "needs-human"
            # Cost = cumulative AGENT runtime (not human idle).
            if agent_seconds > bounds["max_agent_min"] * 60:
                adapter.reply(review, "%s: needs-human — cumulative agent runtime exceeded %g min."
                              % (REPLY_MARKER, bounds["max_agent_min"]))
                print("⚠ needs-human: agent runtime")
                return "needs-human"
            continue  # re-check status immediately after a revision
        # 'waiting': nothing new from the human. Wall-clock = orchestrator lifetime.
        if (time.monotonic() - start) > bounds["max_wall_hours"] * 3600:
            print("⏹ orchestrator lifetime cap (%gh) reached — stopping (the PR stays "
                  "open). A re-run restarts the task, not the poll (6c: persist loop state)."
                  % bounds["max_wall_hours"])
            return "timeout"
        time.sleep(poll_interval)


def orchestrate(project, task, prompt, agent=None, follow=True):
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

    if not follow:
        print("  (--no-follow: opened only; re-run without it to run the review loop)")
        return review
    if CONVERSATION not in caps:
        print("  (transport lacks 'conversation' — review via the served report; no loop)")
        return review

    # 6b: the bounded examine→revise→reply→merge loop, per task until resolved.
    cfg = _review_config()
    print("  following review — poll %ss, bounds %s (Ctrl-C to detach; the PR persists)"
          % (cfg["poll_interval"], cfg["bounds"]))
    return review_loop(adapter, review, clone, branch, base, agent,
                       bounds=cfg["bounds"], poll_interval=cfg["poll_interval"],
                       auto_merge=cfg["auto_merge"])


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) < 3:
        raise SystemExit("usage: orchestrator.py <project-dir> <task> <prompt>")
    orchestrate(argv[0], argv[1], argv[2])


if __name__ == "__main__":
    main()
