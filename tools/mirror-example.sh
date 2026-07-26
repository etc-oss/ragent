#!/usr/bin/env bash
# mirror-example.sh — PUBLISHABLE TEMPLATE for ragent's local-resilience strategy.
#
# This is a template, not the real thing. It documents the commands behind
# ADR-0010 (docs/knowledge/decisions/0010-local-mirror-resilience.md): guarantee
# that ragent still builds fully offline even if an upstream disappears from
# GitHub/sourcehut — WITHOUT vendoring anyone's code into the public repo.
#
# The actual private mirror lives OUTSIDE this repository. `.gitignore` excludes
# /mirror/ so it can never be committed by accident. Copy this file, point the
# paths at your own storage, and run it from outside version control.
#
# Layer 1 — flake.lock already pins every input by content hash (reproducible
#           even if an upstream force-pushes). Nothing to do; keep it committed.
# Layer 2 — nix flake archive + nix copy: persist inputs and built closures.
# Layer 3 — a private git mirror + --override-input failover.

set -euo pipefail

# Where your personal, out-of-repo mirror/cache lives (NOT under this repo):
MIRROR_ROOT="${RAGENT_MIRROR_ROOT:-$HOME/.ragent-mirror}"
CACHE_DIR="$MIRROR_ROOT/nix-cache"        # a plain binary cache (file://)
SRC_MIRROR="$MIRROR_ROOT/src"             # bare git mirrors of upstreams
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$CACHE_DIR" "$SRC_MIRROR"

echo "==> Layer 2a: pull all flake inputs into the local Nix store"
# Reads flake.lock; fetches every pinned input by hash.
nix flake archive "$REPO_ROOT"

echo "==> Layer 2b: persist built closures to an offline binary cache"
# Build what you want available offline (extend once Phase 1 adds jail outputs):
#   nix copy --to "file://$CACHE_DIR" "$REPO_ROOT#devShells.$(nix eval --raw --impure --expr builtins.currentSystem).default"
echo "    (extend this once buildable outputs exist; devShell + jail closures)"

echo "==> Layer 3: keep bare git mirrors of each upstream"
# Example upstreams (keep in sync with flake.nix / THIRD_PARTY.md):
mirror_repo() { # <name> <url>
  local name="$1" url="$2" dst="$SRC_MIRROR/$1.git"
  if [ -d "$dst" ]; then git -C "$dst" remote update --prune
  else git clone --mirror "$url" "$dst"; fi
}
# mirror_repo jail-nix     https://git.sr.ht/~alexdavid/jail.nix
# mirror_repo nixpkgs      https://github.com/NixOS/nixpkgs
# mirror_repo flake-utils  https://github.com/numtide/flake-utils

cat <<EOF

==> Failover (when an upstream is unreachable):
    Point the flake at your local mirror instead of the network, e.g.

      nix develop "$REPO_ROOT" \\
        --override-input jail-nix "git+file://$SRC_MIRROR/jail-nix.git" \\
        --option substituters "file://$CACHE_DIR"

    The PUBLIC flake.nix still references real upstreams; the override is local
    and personal. Do not commit the mirror or the overrides into this repo.
EOF
