#!/usr/bin/env python3
"""ragent — the unified, human-facing CLI. Everything a person does is a subcommand
under `task`; the adapter verbs (ADR-0022) are the orchestrator's internal SPI, not
exposed here.

    ragent task window <project> [name]                 # the hands-on TUI (launch/attach)
    ragent task orchestrate <project> <name> <prompt>   # async: agent → review (PR)
    ragent task review [clone]                          # serve the HTML task reports
    ragent task list                                    # list ragent sessions
    ragent task attach <name>                           # attach to a session
    ragent task kill <name>                             # kill a session

`window` and the session ops (`list`/`attach`/`kill`, folding the old #zellij app)
are the interactive side; `orchestrate`/`review` are the async oversight side.
"""

import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _sh(script, *args):
    return subprocess.run(["bash", os.path.join(HERE, script), *args]).returncode


def _session(name):
    # All ragent sessions are named ragent-<task>; accept either form.
    return name if name.startswith("ragent-") else "ragent-" + name


def cmd_window(a):
    sys.exit(_sh("ragent-workspace.sh", *([a.project] + ([a.name] if a.name else []))))


def cmd_orchestrate(a):
    sys.path.insert(0, HERE)
    from orchestrator import orchestrate
    orchestrate(a.project, a.name, a.prompt, follow=a.follow)


def cmd_review(a):
    sys.exit(_sh("ragent-serve.sh", *([a.clone] if a.clone else [])))


def cmd_list(a):
    subprocess.run(["zellij", "list-sessions"])


def cmd_attach(a):
    sys.exit(subprocess.run(["zellij", "attach", _session(a.name)]).returncode)


def cmd_kill(a):
    subprocess.run(["zellij", "delete-session", _session(a.name), "--force"])


def build_parser():
    p = argparse.ArgumentParser(
        prog="ragent", description="confined AI-coding agents with human oversight")
    groups = p.add_subparsers(dest="group", required=True)
    task = groups.add_parser("task", help="per-task operations").add_subparsers(
        dest="cmd", required=True)

    w = task.add_parser("window", help="launch/attach the two-side TUI workspace")
    w.add_argument("project")
    w.add_argument("name", nargs="?", help="task name (session ragent-<name>)")
    w.set_defaults(fn=cmd_window)

    o = task.add_parser("orchestrate", help="run an agent task and open a review (PR)")
    o.add_argument("project")
    o.add_argument("name")
    o.add_argument("prompt")
    o.add_argument("--no-follow", dest="follow", action="store_false",
                   help="open the review and stop (skip the 6b poll→revise→merge loop)")
    o.set_defaults(fn=cmd_orchestrate, follow=True)

    r = task.add_parser("review", help="serve the per-task HTML reports over HTTP")
    r.add_argument("clone", nargs="?")
    r.set_defaults(fn=cmd_review)

    ls = task.add_parser("list", help="list ragent workspace sessions")
    ls.set_defaults(fn=cmd_list)
    at = task.add_parser("attach", help="attach to a ragent session")
    at.add_argument("name")
    at.set_defaults(fn=cmd_attach)
    k = task.add_parser("kill", help="kill a ragent session")
    k.add_argument("name")
    k.set_defaults(fn=cmd_kill)
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    args.fn(args)


if __name__ == "__main__":
    main()
