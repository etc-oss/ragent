#!/usr/bin/env bash
# Forgejo review-transport adapter (ADR-0020). Implements the transport verbs the
# orchestrator calls, against the Forgejo/Gitea API. Runs HOST-SIDE (outside the
# jail); the token is runtime env, never in the repo/flake.
#
# Env (from ~/.config/ragent/forge.env, written by forgejo-local.sh, or your
# remote NixOS Forgejo on Tailscale — SAME code, only the URL/token differ):
#   RAGENT_FORGE_URL    e.g. http://127.0.0.1:3000  (or https://forge.tailnet)
#   RAGENT_FORGE_USER   owner login (default ci)
#   RAGENT_FORGE_TOKEN  API token (write:repository,write:issue)
#   RAGENT_FORGE_REPO   owner/repo  (default <user>/<project-basename>)
#
# Usage:  forgejo.sh <verb> [args]
#   ensure
#   push        <clone-dir> <branch> <base>
#   open-review <branch> <base> <title> <body-file>   -> prints the review URL
#   status      <pr>                                   -> pending|changes-requested|approved
#   report      <pr> <text-file>
#   merge       <pr>

set -euo pipefail

: "${RAGENT_FORGE_URL:?set RAGENT_FORGE_URL (source ~/.config/ragent/forge.env)}"
: "${RAGENT_FORGE_TOKEN:?set RAGENT_FORGE_TOKEN}"
U="${RAGENT_FORGE_USER:-ci}"
REPO="${RAGENT_FORGE_REPO:?set RAGENT_FORGE_REPO (owner/repo)}"
API="$RAGENT_FORGE_URL/api/v1"

api() { curl -s -H "Authorization: token $RAGENT_FORGE_TOKEN" -H "Content-Type: application/json" "$@"; }

verb="${1:?usage: forgejo.sh <verb> [args]}"; shift || true
case "$verb" in
  ensure)
    # Create the repo if it doesn't exist (idempotent).
    if ! api "$API/repos/$REPO" | grep -q '"full_name"'; then
      api -X POST -d "$(jq -n --arg n "${REPO#*/}" '{name:$n,auto_init:false,private:true}')" \
        "$API/user/repos" >/dev/null
    fi
    ;;

  push) # <clone-dir> <branch> <base>
    clone="$1"; branch="$2"; base="$3"
    # token-in-URL push; base FIRST (a PR needs its base branch on the forge), then head.
    remote="http://$U:$RAGENT_FORGE_TOKEN@${RAGENT_FORGE_URL#http://}/$REPO.git"
    git -C "$clone" push -q "$remote" "$base"
    git -C "$clone" push -qf "$remote" "$branch"
    ;;

  open-review) # <branch> <base> <title> <body-file>
    branch="$1"; base="$2"; title="$3"; bodyfile="${4:-/dev/null}"
    payload="$(jq -cn --arg h "$branch" --arg b "$base" --arg t "$title" \
                 --rawfile body "$bodyfile" '{head:$h,base:$b,title:$t,body:$body}')"
    num=""; resp=""
    # Retry: right after a push Forgejo may briefly not resolve the branch
    # ("target couldn't be found"); and a re-run finds the already-open PR.
    for attempt in 1 2 3 4; do
      resp="$(api -X POST -d "$payload" "$API/repos/$REPO/pulls")"
      num="$(printf '%s' "$resp" | jq -r 'if type=="object" then (.number // empty) else empty end' 2>/dev/null)"
      [ -n "$num" ] && break
      # already open for this head → reuse it (guard: an error is an object, not array)
      num="$(api "$API/repos/$REPO/pulls?state=open" \
             | jq -r --arg h "$branch" 'if type=="array" then (.[] | select(.head.ref==$h) | .number) else empty end' 2>/dev/null | head -1)"
      [ -n "$num" ] && break
      sleep 2
    done
    [ -n "$num" ] && echo "$RAGENT_FORGE_URL/$REPO/pulls/$num" || { echo "open-review failed: $(printf '%s' "$resp" | head -c 200)" >&2; exit 1; }
    ;;

  status) # <pr>  -> pending | changes-requested | approved
    pr="$1"
    revs="$(api "$API/repos/$REPO/pulls/$pr/reviews")"
    if printf '%s' "$revs" | jq -e 'any(.[]; .state=="APPROVED")' >/dev/null 2>&1; then echo approved
    elif printf '%s' "$revs" | jq -e 'any(.[]; .state=="REQUEST_CHANGES")' >/dev/null 2>&1; then echo changes-requested
    else echo pending; fi
    ;;

  comments) # <pr>  -> unresolved review comments (text), for the 6b loop
    pr="$1"
    api "$API/repos/$REPO/pulls/$pr/reviews" \
      | jq -r '.[] | select(.state=="REQUEST_CHANGES" or .body!="") | .body' 2>/dev/null
    ;;

  report) # <pr> <text-file> — post the agent's reply into the thread
    pr="$1"; textfile="${2:-/dev/null}"
    api -X POST -d "$(jq -n --rawfile b "$textfile" '{body:$b}')" \
      "$API/repos/$REPO/issues/$pr/comments" >/dev/null
    ;;

  merge) # <pr>
    pr="$1"
    api -X POST -d '{"Do":"merge"}' "$API/repos/$REPO/pulls/$pr/merge" >/dev/null
    ;;

  *) echo "unknown verb: $verb" >&2; exit 2 ;;
esac
