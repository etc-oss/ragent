#!/usr/bin/env python3
"""ragent — the unified, human-facing CLI (ADR-0023, ergonomics refined by ADR-0030).

    ragent task window [name] [-C DIR]                  # the hands-on two-pane TUI
    ragent task orchestrate [name] <prompt> [-C DIR]    # async: agent → review (PR)
    ragent task review [clone]                          # serve the HTML task reports
    ragent task list | attach <name> | kill <name>      # session ops
    ragent shell [name] [-C DIR] [--scratch] [--sh]     # quick confined interactive session

The **project directory defaults to the current directory** (override with `-C/--dir`) —
no more explicit "$PWD". The **task name defaults to `work`** (`shell` for `ragent shell`).
Every path stays confined to a clone with the human-review gate (ADR-0016).
"""

import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_TOOLS = os.path.dirname(HERE)  # the shell launchers live in tools/, the package's parent


def _sh(script, *args, env=None):
    return subprocess.run(["bash", os.path.join(_TOOLS, script), *args], env=env).returncode


def _dir(a):
    # The project directory: -C/--dir if given, else the current directory (no more "$PWD").
    return os.path.abspath(a.dir) if getattr(a, "dir", None) else os.getcwd()


def _session(name):
    # All ragent sessions are named ragent-<task>; accept either form.
    return name if name.startswith("ragent-") else "ragent-" + name


def _clone_path(project, name):
    return os.environ.get("RAGENT_CLONE_DIR") or (project.rstrip("/") + "-agent-" + name)


def cmd_window(a):
    sys.exit(_sh("ragent-workspace.sh", _dir(a), a.name))


def cmd_orchestrate(a):
    from .orchestrator import orchestrate
    orchestrate(_dir(a), a.name, a.prompt, follow=a.follow)


def cmd_review(a):
    sys.exit(_sh("ragent-serve.sh", *([a.clone] if a.clone else [])))


def _scratch_dir():
    # A standing, repo-less sandbox: a git repo under XDG data, created on first use.
    d = os.path.expanduser(os.environ.get("RAGENT_SCRATCH_DIR", "~/.local/share/ragent/scratch"))
    if not os.path.isdir(os.path.join(d, ".git")):
        os.makedirs(d, exist_ok=True)
        ident = {"GIT_AUTHOR_NAME": "ragent", "GIT_AUTHOR_EMAIL": "ragent@localhost",
                 "GIT_COMMITTER_NAME": "ragent", "GIT_COMMITTER_EMAIL": "ragent@localhost"}
        subprocess.run(["git", "-C", d, "init", "-q"], check=True)
        subprocess.run(["git", "-C", d, "commit", "-q", "--allow-empty", "-m", "ragent scratch"],
                       check=True, env={**os.environ, **ident})
    return d


def cmd_shell(a):
    # Quick confined interactive session: reuse the workspace clone/boundary setup (no TUI),
    # then drop straight into the confined agent (or a shell with --sh).
    project = _scratch_dir() if a.scratch else _dir(a)
    rc = _sh("ragent-workspace.sh", project, a.name, env={**os.environ, "RAGENT_SETUP_ONLY": "1"})
    if rc != 0:
        sys.exit(rc)
    clone = _clone_path(project, a.name)
    if os.environ.get("RAGENT_SETUP_ONLY"):  # caller wants setup only (also the headless test seam)
        print("clone ready: %s" % clone)
        return
    os.chdir(clone)
    if a.agent:
        # Straight into the confined agent, INTERACTIVE (no -p); RAGENT_AGENT picks which one.
        os.execvp("bash", ["bash", os.path.join(clone, ".ragent", "spawn-agent.sh")])
    else:
        print("confined clone ready: %s" % clone)
        print("  launch the agent :  ./.ragent/spawn-agent.sh          (interactive, confined)")
        print("  review (main tree): git -C %s fetch %s agent/%s" % (project, clone, a.name))
        shell = os.environ.get("SHELL", "bash")
        os.execvp(shell, [shell])


def cmd_list(a):
    subprocess.run(["zellij", "list-sessions"])


def cmd_attach(a):
    sys.exit(subprocess.run(["zellij", "attach", _session(a.name)]).returncode)


def cmd_kill(a):
    subprocess.run(["zellij", "delete-session", _session(a.name), "--force"])


def _add_dir(p):
    p.add_argument("-C", "--dir", default=None,
                   help="project directory (default: the current directory)")


def build_parser():
    p = argparse.ArgumentParser(
        prog="ragent", description="AI coding agents that work boldly in a safe sandbox — with human oversight")
    groups = p.add_subparsers(dest="group", required=True)
    task = groups.add_parser("task", help="per-task operations").add_subparsers(
        dest="cmd", required=True)

    w = task.add_parser("window", help="launch/attach the two-side TUI workspace")
    w.add_argument("name", nargs="?", default="work", help="task name (default: work)")
    _add_dir(w)
    w.set_defaults(fn=cmd_window)

    o = task.add_parser("orchestrate", help="run an agent task and open a review (PR)")
    o.add_argument("name", nargs="?", default="work", help="task name (default: work)")
    o.add_argument("prompt", help="the task prompt for the agent")
    o.add_argument("--no-follow", dest="follow", action="store_false",
                   help="open the review and stop (skip the 6b poll→revise→merge loop)")
    _add_dir(o)
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

    sh = groups.add_parser(
        "shell", help="quick confined interactive session in a clone (of the current dir, or --scratch)")
    sh.add_argument("name", nargs="?", default="shell", help="clone/task name (default: shell)")
    _add_dir(sh)
    sh.add_argument("--scratch", action="store_true",
                    help="use a standing repo-less scratch sandbox instead of the current directory")
    sh.add_argument("--sh", dest="agent", action="store_false", default=True,
                    help="drop into a shell in the clone instead of launching the agent")
    sh.set_defaults(fn=cmd_shell)

    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    args.fn(args)


if __name__ == "__main__":
    main()
