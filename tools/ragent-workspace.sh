#!/usr/bin/env bash
# ragent-workspace.sh — launch the two-side Zellij workspace (ADR-0005) with the
# git-clone review boundary (ADR-0011 + ADR-0016).
#
# Run INSIDE the Lima guest, from the workspace devshell so the Zellij panes
# inherit a PATH with nvim / lazygit / the jailed agents on it:
#     nix develop .#workspace
#     ./tools/ragent-workspace.sh <project-dir> [task]
#
# HUMAN tab = neovim + lazygit on the main tree. MACHINE tab = a shell in a
# self-contained agent CLONE (branch agent/<task>) where the jailed agent runs
# confined, plus a tail of its log. The human reviews the agent's commits by
# fetching the clone's branch back into the main tree — nothing lands without that.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The layout is set by the devshell/app to the flake-GENERATED (PATH-substituted)
# store layout. The raw workspace/ragent-workspace.kdl is a @bash@/@paneBin@
# TEMPLATE and must not be used un-substituted. RAGENT_LAYOUT is REQUIRED to launch
# the TUI, but not to do clone/boundary setup (RAGENT_SETUP_ONLY) — so it is checked
# just before the Zellij launch, below, not here.
LAYOUT="${RAGENT_LAYOUT:-}"
RAGENT_RUN="${RAGENT_RUN_BIN:-$REPO/tools/ragent-confine.sh}"
# Host-side task-report generator (agent's explanation + diff → served HTML).
RAGENT_REPORT="${RAGENT_REPORT_BIN:-$REPO/tools/ragent-report.py}"
# Neon/pastel theming (Tokyo Night, greens neutralized): Zellij via --config,
# lazygit via LG_CONFIG_FILE, neovim via the flake. Overridable per config repo.
ZJ_CONFIG="${RAGENT_ZELLIJ_CONFIG:-$REPO/workspace/zellij-config.kdl}"
export LG_CONFIG_FILE="${RAGENT_LAZYGIT_CONFIG:-$REPO/workspace/lazygit-theme.yml}"

MAIN="$(cd "${1:?usage: ragent-workspace.sh <project-dir> [task]}" && pwd)"
TASK="${2:-task}"
BRANCH="agent/$TASK"
CLONE="${RAGENT_CLONE_DIR:-${MAIN%/}-agent-$TASK}"

git -C "$MAIN" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "$MAIN is not a git repo" >&2; exit 1; }
BASE="$(git -C "$MAIN" branch --show-current 2>/dev/null || echo HEAD)"

# 1) Agent clone — a self-contained .git INSIDE the jail bind (ADR-0016), so the
#    agent's git works confined. --local hardlinks objects (cheap).
if [ -d "$CLONE/.git" ]; then
  echo "reusing agent clone: $CLONE"
  git -C "$CLONE" checkout -q "$BRANCH" 2>/dev/null || git -C "$CLONE" checkout -q -b "$BRANCH"
else
  echo "cloning $MAIN -> $CLONE (branch $BRANCH)"
  git clone --local --quiet "$MAIN" "$CLONE"
  git -C "$CLONE" checkout -q -b "$BRANCH"
fi

# 2) Per-workspace metadata in the clone: log + a launch helper + a README.
mkdir -p "$CLONE/.ragent"
# Keep workspace metadata out of the agent's commits/diffs (local to the clone).
grep -qxF ".ragent/" "$CLONE/.git/info/exclude" 2>/dev/null || echo ".ragent/" >> "$CLONE/.git/info/exclude"
LOG="$CLONE/.ragent/agent.log"; : > "$LOG"

cat > "$CLONE/.ragent/spawn-agent.sh" <<EOF
#!/usr/bin/env bash
# Launch the confined agent in this clone (cgroup-capped + logged). Set your key
# first, e.g.  export ANTHROPIC_API_KEY=...   (ADR-0014 covers the credential bind).
set -euo pipefail
AGENT="\${RAGENT_AGENT:-jailed-opencode}"
BIN="\$(command -v "\$AGENT")" || { echo "agent \$AGENT not on PATH — enter 'nix develop .#workspace'"; exit 1; }
case "\$AGENT" in
  *opencode*) export RAGENT_PRECREATE_DIRS="\$HOME/.config/opencode \$HOME/.local/share/opencode \$HOME/.local/state/opencode" ;;
  *claude*)   mkdir -p "\$HOME/.claude"; [ -f "\$HOME/.claude.json" ] || echo "{}" > "\$HOME/.claude.json"; export RAGENT_PRECREATE_DIRS="\$HOME/.claude" ;;
  *pi*)       export RAGENT_PRECREATE_DIRS="\$HOME/.pi" ;;
  *crush*)    export RAGENT_PRECREATE_DIRS="\$HOME/.config/crush \$HOME/.local/share/crush" ;;
esac
# Headless (-p/--print) runs are tee'd to the log. An INTERACTIVE run (no prompt) must
# keep the real TTY: piping stdout through tee makes the agent see a non-tty stdout and
# fall back to --print, which then errors ("Input must be provided..."). So only tee
# when headless; run interactive attached to the terminal.
_headless=
for _a in "\$@"; do case "\$_a" in -p|--print) _headless=1 ;; esac; done
if [ -n "\$_headless" ]; then
  echo "launching \$AGENT (confined + capped, headless) — logging to $LOG"
  "$RAGENT_RUN" "\$BIN" "\$@" 2>&1 | tee -a "$LOG"
else
  echo "launching \$AGENT (confined + capped, interactive) — live TTY (not logged)"
  "$RAGENT_RUN" "\$BIN" "\$@"
fi

# After the agent finishes, generate the task report HOST-SIDE (outside the jail):
# the agent's own .ragent/EXPLAIN.md + the real diff → self-contained HTML.
if command -v python3 >/dev/null 2>&1; then
  python3 "$RAGENT_REPORT" "$CLONE" "$TASK" "$BASE" >/dev/null 2>&1 \
    && echo "task report → $CLONE/.ragent/reports/html/$TASK.html   (serve: nix run .#task-review -- $CLONE)"
fi
EOF
chmod +x "$CLONE/.ragent/spawn-agent.sh"

cat > "$CLONE/.ragent/README" <<EOF
AGENT clone — branch $BRANCH — confined via jail.nix (ADR-0016).

Launch the agent here (confined + cgroup-capped; logs to .ragent/agent.log):
    ./.ragent/spawn-agent.sh                              # opencode (default)
    RAGENT_AGENT=jailed-claude-code ./.ragent/spawn-agent.sh

A task report (the agent's .ragent/EXPLAIN.md + the diff, as HTML) is generated
automatically after each run. Review it from any device:
    nix run .#task-review -- "$CLONE"     # then open http://127.0.0.1:8099/

Human review (from the main tree, OUTSIDE the jail):
    git -C "$MAIN" fetch "$CLONE" "$BRANCH"
    git -C "$MAIN" log  --oneline "$BASE"..FETCH_HEAD      # what the agent proposes
    git -C "$MAIN" diff             "$BASE"..FETCH_HEAD
    # accept:  git -C "$MAIN" merge FETCH_HEAD
    # discard: do nothing (the clone is disposable)
EOF

# 3) Export what the KDL layout reads, then launch Zellij.
export RAGENT_MAIN="$MAIN" RAGENT_CLONE="$CLONE" RAGENT_LOG="$LOG"
echo "human tree : $MAIN ($BASE)"
echo "agent clone: $CLONE ($BRANCH)"

# Testability hook: set RAGENT_SETUP_ONLY=1 to do the clone/boundary setup without
# starting the TUI (used by the boundary test; a TUI can't be driven headlessly).
if [ -n "${RAGENT_SETUP_ONLY:-}" ]; then
  echo "(RAGENT_SETUP_ONLY set — clone + workspace metadata ready; skipping Zellij)"
  exit 0
fi

# The TUI needs zellij on PATH (the setup-only path above does not — the
# orchestrator reuses this script only for clone/boundary setup).
command -v zellij >/dev/null || { echo "zellij not on PATH — run inside 'nix develop .#workspace'" >&2; exit 1; }

# A layout is required to launch the TUI (but not for the setup-only path above).
: "${LAYOUT:?run via 'nix develop .#workspace' or 'nix run .#task-window' (RAGENT_LAYOUT unset)}"

# Zellij cannot render on a dumb/unset terminal (a common cause of an apparently
# frozen TUI, e.g. under `limactl shell` which may pass TERM=dumb). Force a sane one.
case "${TERM:-}" in "" | dumb) export TERM=xterm-256color ;; esac

SESSION="ragent-$TASK"
# Session hygiene: RAGENT_FRESH=1 discards any existing session of this name first,
# so you can never get stuck re-attaching to a broken/stale one.
if [ -n "${RAGENT_FRESH:-}" ]; then
  zellij delete-session "$SESSION" --force >/dev/null 2>&1 || true
fi
# Otherwise, if the session exists (e.g. you detached with Ctrl+o d), ATTACH to it
# rather than recreating it. If a session ever looks broken (panes showing an exit
# prompt), recreate it:  RAGENT_FRESH=1 ...   or  zellij kill-all-sessions --yes.
if zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' \
     | grep -qE "(^|[[:space:]])${SESSION}([[:space:]]|\$)"; then
  echo "session '$SESSION' exists — attaching (detach Ctrl+o d; recreate with RAGENT_FRESH=1)…"
  exec zellij --config "$ZJ_CONFIG" attach "$SESSION"
fi
echo "launching Zellij workspace '$SESSION' (detach with Ctrl+o d; quit with Ctrl+q)…"
# --new-session-with-layout starts a NEW session with this layout. (Plain
# --layout with --session would instead add tabs to an EXISTING session.)
exec zellij --config "$ZJ_CONFIG" --session "$SESSION" --new-session-with-layout "$LAYOUT"
