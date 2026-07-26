#!/usr/bin/env bash
# confinement-test.sh — Phase 1 exit gate: prove the jail actually confines.
#
# Runs INSIDE the Lima Linux guest (bubblewrap is Linux-only). It builds the
# jail.nix confinement probe (`.#jailed-probe`, a jailed shell carrying the exact
# agent profile) and asserts:
#   POSITIVE control — the project directory (cwd) IS writable.
#   NEGATIVE controls — $HOME, a decoy secret, SSH keys, and paths OUTSIDE the
#                       project dir are NOT reachable.
#
# Exit 0 only if the positive control passes AND every negative control holds
# (i.e. the jail blocked access). See ADR-0002 / ADR-0013.

set -uo pipefail

if [ "$(uname -s)" != "Linux" ]; then
  echo "This test must run inside the Linux guest (bubblewrap needs Linux)." >&2
  echo "Start the VM and shell in:  limactl start lima/ragent.yaml && limactl shell ragent" >&2
  exit 2
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NIXFLAGS=(--extra-experimental-features 'nix-command flakes')

echo "==> Building the confinement probe (.#jailed-probe)"
nix build "${NIXFLAGS[@]}" "$REPO#jailed-probe" -o "$REPO/result-jail-probe" || {
  echo "build failed — is Nix installed with flakes, and user namespaces enabled?" >&2; exit 1; }
PROBE="$REPO/result-jail-probe/bin/ragent-jail-probe"
[ -x "$PROBE" ] || { echo "probe binary not found at $PROBE" >&2; exit 1; }

# A scratch "project" the jail is allowed to touch (mount-cwd = this dir).
PROJECT="$(mktemp -d)"
# Decoys the jail must NOT be able to reach.
DECOY_HOME="$HOME/ragent-decoy-secret.txt"
DECOY_OUT="$(mktemp)"
echo "TOP-SECRET (home)"    > "$DECOY_HOME"
echo "TOP-SECRET (outside)" > "$DECOY_OUT"
cleanup() { rm -f "$DECOY_HOME" "$DECOY_OUT"; rm -rf "$PROJECT"; }
trap cleanup EXIT

pass=0; fail=0
# check <expect: allow|deny> <description> <command...>
check() {
  local expect="$1" desc="$2"; shift 2
  ( cd "$PROJECT" && "$PROBE" -c "$*" ) >/dev/null 2>&1
  local rc=$?
  if { [ "$expect" = allow ] && [ $rc -eq 0 ]; } || { [ "$expect" = deny ] && [ $rc -ne 0 ]; }; then
    echo "  PASS  [$expect] $desc"; pass=$((pass+1))
  else
    echo "  FAIL  [$expect] $desc  (rc=$rc)"; fail=$((fail+1))
  fi
}

echo "==> Positive control (the project dir must be usable)"
check allow "write a file in the project dir (cwd)"        'touch ./agent-wrote-this && test -f ./agent-wrote-this'

echo "==> Negative controls (everything else must be denied)"
check deny  "read a decoy secret in \$HOME"                 "cat '$DECOY_HOME'"
check deny  "write into \$HOME"                             "touch '$HOME/ragent-escape'"
check deny  "read a file OUTSIDE the project dir"           "cat '$DECOY_OUT'"
check deny  "list \$HOME/.ssh"                              "ls -la '$HOME/.ssh'"
check deny  "read /etc/shadow"                              'cat /etc/shadow'

echo
echo "==> Result: $pass passed, $fail failed"
if [ $fail -eq 0 ]; then
  echo "CONFINEMENT VERIFIED — the jail confined the process to the project dir."
  exit 0
else
  echo "CONFINEMENT FAILED — a control did not hold. Do NOT trust this jail." >&2
  exit 1
fi
