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
# Honor store-path overrides when run as a packaged app (`nix run .#workspace`);
# fall back to repo-relative paths when run from a checkout.
LAYOUT="${RAGENT_LAYOUT:-$REPO/workspace/ragent-workspace.kdl}"
RAGENT_RUN="${RAGENT_RUN_BIN:-$REPO/tools/ragent-run.sh}"

MAIN="$(cd "${1:?usage: ragent-workspace.sh <project-dir> [task]}" && pwd)"
TASK="${2:-task}"
BRANCH="agent/$TASK"
CLONE="${RAGENT_CLONE_DIR:-${MAIN%/}-agent-$TASK}"

command -v zellij >/dev/null || { echo "zellij not on PATH — run inside 'nix develop .#workspace'" >&2; exit 1; }
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

cat > "$CLONE/.ragent/launch-agent.sh" <<EOF
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
echo "launching \$AGENT (confined + capped) — logging to $LOG"
"$RAGENT_RUN" "\$BIN" "\$@" 2>&1 | tee -a "$LOG"
EOF
chmod +x "$CLONE/.ragent/launch-agent.sh"

cat > "$CLONE/.ragent/README" <<EOF
AGENT clone — branch $BRANCH — confined via jail.nix (ADR-0016).

Launch the agent here (confined + cgroup-capped; logs to .ragent/agent.log):
    ./.ragent/launch-agent.sh                              # opencode (default)
    RAGENT_AGENT=jailed-claude-code ./.ragent/launch-agent.sh

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

# Testability hook: set RAGENT_NO_LAUNCH=1 to do the clone/boundary setup without
# starting the TUI (used by the boundary test; a TUI can't be driven headlessly).
if [ -n "${RAGENT_NO_LAUNCH:-}" ]; then
  echo "(RAGENT_NO_LAUNCH set — clone + workspace metadata ready; skipping Zellij)"
  exit 0
fi

echo "launching Zellij workspace…"
# --new-session-with-layout starts a NEW session with this layout. (Plain
# --layout with --session would instead add tabs to an EXISTING session.)
exec zellij --session "ragent-$TASK" --new-session-with-layout "$LAYOUT"
