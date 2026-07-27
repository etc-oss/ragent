#!/usr/bin/env bash
# ragent-orchestrate.sh — per-task orchestrator (ADR-0020). Transport-agnostic:
# it drives a review ADAPTER (forgejo | gitlab | github | ssh). HOST-SIDE — the
# adapter holds the forge token (kept out of the jail, ADR-0011/0014); the agent
# only commits in its clone (ADR-0016).
#
# 6a scope: setup clone -> run the confined agent -> generate the task report ->
# adapter ensure/push/open-review (a PR you can open on your phone). The
# poll/comment/merge loop is 6b.
#
#   source ~/.config/ragent/forge.env
#   ragent-orchestrate.sh <project-dir> <task-name> "<prompt for the agent>"

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$(cd "${1:?usage: ragent-orchestrate.sh <project-dir> <task> <prompt>}" && pwd)"
TASK="${2:?task name (becomes branch agent/<task>)}"
PROMPT="${3:?the instruction for the agent}"

AGENT="${RAGENT_AGENT:-jailed-claude-code}"
ADAPTER="${RAGENT_ADAPTER:?set RAGENT_ADAPTER (source ~/.config/ragent/forge.env)}"
ADAPTER_BIN="${RAGENT_ADAPTER_BIN:-$REPO/tools/adapters/$ADAPTER.sh}"
[ -x "$ADAPTER_BIN" ] || { echo "no adapter: $ADAPTER_BIN" >&2; exit 1; }

BRANCH="agent/$TASK"
CLONE="${RAGENT_CLONE_DIR:-${PROJECT%/}-agent-$TASK}"
BASE="$(git -C "$PROJECT" branch --show-current 2>/dev/null || echo master)"
export RAGENT_FORGE_REPO="${RAGENT_FORGE_REPO:-${RAGENT_FORGE_USER:-ci}/$(basename "$PROJECT")}"

echo "▶ orchestrate: task '$TASK' on $PROJECT ($BASE) via $ADAPTER → $RAGENT_FORGE_REPO"

# 1. Set up the agent clone + launch helper (reuse the workspace boundary logic).
RAGENT_NO_LAUNCH=1 RAGENT_AGENT="$AGENT" bash "$REPO/tools/ragent-workspace.sh" "$PROJECT" "$TASK" >/dev/null

# 2. Run the confined agent. It commits in the clone, writes .ragent/EXPLAIN.md,
#    and launch-agent.sh auto-generates the HTML report (ADR-0021).
FULL_PROMPT="$PROMPT

When finished: write a brief .ragent/EXPLAIN.md (2-3 sentences on what you changed
and why), then stage and commit all changes with a clear message."
echo "▶ running $AGENT (confined) …"
( cd "$CLONE" && RAGENT_AGENT="$AGENT" ./.ragent/launch-agent.sh -p "$FULL_PROMPT" --dangerously-skip-permissions ) \
  2>&1 | sed 's/^/  agent: /' | tail -6

# 3. Push the branch and open the review via the adapter (outside the jail).
echo "▶ publishing review …"
"$ADAPTER_BIN" ensure
"$ADAPTER_BIN" push "$CLONE" "$BRANCH" "$BASE"

BODY="$(mktemp)"
{ if [ -s "$CLONE/.ragent/EXPLAIN.md" ]; then cat "$CLONE/.ragent/EXPLAIN.md"; else echo "_(no EXPLAIN.md was written)_"; fi
  echo; echo "---"
  echo "Full explanation + rendered diff (served report):"
  echo "\`nix run .#serve -- $CLONE\`  →  http://127.0.0.1:8099/$TASK.html"
} > "$BODY"

REVIEW_URL="$("$ADAPTER_BIN" open-review "$BRANCH" "$BASE" "$TASK" "$BODY")"
rm -f "$BODY"
echo "✓ review opened: $REVIEW_URL"
echo "  (6a: review it on your phone; the comment→revise→merge loop is 6b)"
