#!/usr/bin/env bash
# confinement-test.sh — Phase 1 exit gate: prove the jail actually confines.
#
# Runs INSIDE the Lima Linux guest (bubblewrap is Linux-only). It builds the
# jail.nix confinement probe (`.#jailed-probe`, a jailed shell carrying the exact
# agent profile) and asserts, with the probe's cwd set to a scratch project dir:
#
#   POSITIVE  — the project directory (cwd) is real and writable.
#   READS     — real secret FILES (a $HOME secret, an SSH key, an out-of-project
#               file, /etc/shadow) are unreadable.
#   WRITES    — only the project dir is a real writable path. Everywhere else the
#               jail sees an EPHEMERAL tmpfs ($HOME, /etc, /), so a write there
#               "succeeds" but must NOT reach the real filesystem. We therefore
#               assert by EFFECT: after the jail writes, the real path stays absent.
#
# The jail gives a fresh empty $HOME, so the danger is never "can it list a dir"
# (an empty tmpfs lists fine) but "can it read a real secret" or "can a write
# escape to the real fs" — which is what these controls check. Exit 0 only if
# every control holds. See ADR-0002 / ADR-0013.

set -uo pipefail

if [ "$(uname -s)" != "Linux" ]; then
  echo "This test must run inside the Linux guest (bubblewrap needs Linux)." >&2
  echo "  limactl start --name=ragent lima/ragent.yaml && limactl shell ragent" >&2
  exit 2
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Building the confinement probe (.#jailed-probe)"
PROBE_OUT="$(nix build --no-link --print-out-paths "$REPO#jailed-probe" 2>/dev/null)" || {
  echo "build failed — is Nix installed with flakes, and user namespaces enabled?" >&2; exit 1; }
PROBE="$PROBE_OUT/bin/ragent-jail-probe"
[ -x "$PROBE" ] || { echo "probe binary not found at $PROBE" >&2; exit 1; }

PROJECT="$(mktemp -d)"                                   # the jail's cwd (allowed)
OUTSIDE="$(mktemp -d)"; echo "OUTSIDE-SECRET" > "$OUTSIDE/secret.txt"  # real, out-of-project
HOME_DECOY="$HOME/.ragent-home-decoy.$$"; echo "HOME-SECRET" > "$HOME_DECOY"
SSH_DECOY_DIR="$HOME/.ssh"; SSH_DECOY="$SSH_DECOY_DIR/ragent_probe_id.$$"
mkdir -p "$SSH_DECOY_DIR"; echo "FAKE-PRIVATE-KEY" > "$SSH_DECOY"
cleanup() {
  rm -f "$HOME_DECOY" "$SSH_DECOY" "$HOME/ragent-should-not-persist" \
        "$OUTSIDE/escape" /etc/ragent-escape-probe 2>/dev/null
  rmdir "$SSH_DECOY_DIR" 2>/dev/null; rm -rf "$OUTSIDE" "$PROJECT"
}
trap cleanup EXIT

pass=0; fail=0
jailrun() { ( cd "$PROJECT" && "$PROBE" -c "$*" ); }   # run inside the jail, cwd = project

# read_denied <desc> <command...>   — the jail command must fail (secret unreachable)
read_denied() {
  local desc="$1"; shift
  if jailrun "$*" >/dev/null 2>&1; then echo "  FAIL  [read]  $desc (was readable)"; fail=$((fail+1))
  else echo "  PASS  [read]  $desc"; pass=$((pass+1)); fi
}
# write_isolated <desc> <real-path>  — the jail writes it; the REAL path must stay absent
write_isolated() {
  local desc="$1" real="$2"
  jailrun "touch '$real'" >/dev/null 2>&1
  if [ -e "$real" ]; then echo "  FAIL  [write] $desc (leaked to real fs: $real)"; fail=$((fail+1)); rm -f "$real"
  else echo "  PASS  [write] $desc"; pass=$((pass+1)); fi
}

echo "==> Positive control"
if jailrun 'touch ./agent-wrote-this' && [ -f "$PROJECT/agent-wrote-this" ]; then
  echo "  PASS  [allow] project dir (cwd) is real and writable"; pass=$((pass+1))
else
  echo "  FAIL  [allow] could not write the project dir (cwd)"; fail=$((fail+1))
fi

echo "==> Reads that must be denied (real secrets)"
read_denied "a secret file in the real \$HOME"   "cat '$HOME_DECOY'"
read_denied "a planted SSH private key"          "cat '$SSH_DECOY'"
read_denied "a file OUTSIDE the project dir"     "cat '$OUTSIDE/secret.txt'"
read_denied "/etc/shadow"                        'cat /etc/shadow'

echo "==> Writes that must not escape to the real filesystem"
write_isolated "write to \$HOME stays ephemeral"        "$HOME/ragent-should-not-persist"
write_isolated "write to an out-of-project path"        "$OUTSIDE/escape"
write_isolated "write to /etc stays ephemeral"          "/etc/ragent-escape-probe"

echo
echo "==> Result: $pass passed, $fail failed"
if [ $fail -eq 0 ]; then
  echo "CONFINEMENT VERIFIED — the jail confined the process to the project dir."
  exit 0
else
  echo "CONFINEMENT FAILED — a control did not hold. Do NOT trust this jail." >&2
  exit 1
fi
