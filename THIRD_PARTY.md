# Third-party attributions

`ragent` is an umbrella project that **references** upstream work — as pinned Nix
flake inputs, as packages built from Nixpkgs, or (for the VM host) as a tool the
user installs. It does not vendor, copy, or redistribute upstream source code:
the public repository contains only URLs and content hashes (`flake.nix` /
`flake.lock`). Anyone who builds the flake fetches each upstream directly from
its own source, under its own license. The `Consumed as` column below states the
mechanism per upstream so the credit is precise.

This posture is a deliberate decision, recorded in
[ADR-0003: Consume upstreams as pinned flake inputs](docs/knowledge/decisions/0003-consume-upstreams-as-flake-inputs.md)
and [ADR-0010: Local-mirror resilience](docs/knowledge/decisions/0010-local-mirror-resilience.md).

## Why this matters for licensing

The most important upstream, **jail.nix, is GPL-3.0**. Copyleft licenses like
GPL-3.0 and LGPL-2.0/2.1 attach obligations when you **distribute** their code
or a derivative of it. `ragent` never distributes their code — it distributes a
URL and a hash. The combined system is only ever assembled locally on a user's
machine by `nix build`, which is permitted use. Therefore:

- `ragent`'s own files (this repo) stay under **Apache-2.0**.
- Each upstream stays under its own license, upstream.
- **Do not vendor a GPL/LGPL upstream into this repository.** Doing so would
  pull its copyleft obligations onto the copied files and break the clean
  separation above. If a future phase genuinely needs to vendor code, record a
  new ADR and confine the vendored copy under its original license.

## Attribution table

Licenses below were verified on 2026-07-26 (SPDX identifiers from the GitHub
Licenses API, from each project's `LICENSE`/`COPYING` file, or from in-source
`SPDX-License-Identifier` headers). Where a project declares no machine-readable
SPDX id, the basis is noted.

| Upstream | Role in ragent | Consumed as | License | Verified via | Source |
|---|---|---|---|---|---|
| **jail.nix** (Alex David) | Machine-side confinement: Nix-native bubblewrap wrapper | pinned flake input | `GPL-3.0` | `LICENSE` file (GPLv3 text) | https://git.sr.ht/~alexdavid/jail.nix |
| **Nixpkgs** | Package set / toolchains | pinned flake input | `MIT` | GitHub Licenses API | https://github.com/NixOS/nixpkgs |
| **flake-utils** (Numtide) | Flake system helper | pinned flake input | `MIT` | GitHub Licenses API | https://github.com/numtide/flake-utils |
| **git-surgeon** (raine) | Shared agent git CLI (ADR-0017) | pinned source input (`flake=false`), built via `buildRustPackage` | `MIT` | GitHub Licenses API | https://github.com/raine/git-surgeon |
| **Bubblewrap** | Unprivileged sandbox that jail.nix drives | Nixpkgs package (via jail.nix) | `LGPL-2.0-or-later` | `SPDX-License-Identifier` in `bubblewrap.c` | https://github.com/containers/bubblewrap |
| **Zellij** | Terminal workspace / two-side layout | Nixpkgs package (Phase 2) | `MIT` | GitHub Licenses API | https://github.com/zellij-org/zellij |
| **Neovim** | Human-side editor | Nixpkgs package (Phase 2) | `Apache-2.0` AND `Vim` | `LICENSE.txt` (dual) | https://github.com/neovim/neovim |
| **Lima** | Linux VM host (the flake runs inside a Lima guest) | external tool, user-installed | `Apache-2.0` | GitHub Licenses API | https://github.com/lima-vm/lima |
| **Open Knowledge Format** (in `knowledge-catalog`, Google LLC) | Knowledge-capture format (`docs/knowledge/`) | format followed (not code) | `Apache-2.0` | GitHub Licenses API | https://github.com/GoogleCloudPlatform/knowledge-catalog |

## Studied as prior art (not dependencies)

Referenced for design; their code is not consumed by this repository.

| Project | Why it was studied | License | Source |
|---|---|---|---|
| **jailed-agents** (Anderson Joseph) | Already jails opencode/pi/crush via jail.nix; a large fraction of the "machine pane" | `MIT` | https://github.com/andersonjoseph/jailed-agents |
| **sandnix** (srid) | Alternative confinement (landrun/Landlock on Linux, `sandbox-exec` on macOS) | `GPL-3.0` | https://github.com/srid/sandnix |

## CLI tool identity (name collision — resolved)

"git-surgeon" is at least four different projects. **raine/git-surgeon is the one
adopted** (ADR-0017), pinned at v0.1.17; it is in the attribution table above. The
other well-known candidate is recorded here to document the collision that was
resolved:

| Project | Description | License | Source |
|---|---|---|---|
| **git-surgeon** (raine) | "Git primitives for autonomous coding agents" | `MIT` | https://github.com/raine/git-surgeon |
| **git-surgeon** (hyperb1iss) | History truncation, file purging, author rewriting atop git-filter-repo | `GPL-2.0` | https://github.com/hyperb1iss/git-surgeon |

> Note: a GPL-2.0 CLI invoked as a separate process over `PATH` is used, not
> linked or vendored, so it does not affect this repo's license — but pinning
> the wrong project entirely is the more likely mistake. Confirm identity first.

## Agents added in later phases

Coding agents (Claude Code, pi, opencode, crush) are integrated in Phase 1+.
Each is added as a pinned input at that time and credited here with its verified
license then, rather than pre-listed now.

## How to re-verify

```sh
# SPDX id for a GitHub-hosted upstream:
curl -s https://api.github.com/repos/<owner>/<repo> | jq -r '.license.spdx_id'
# In-source authority (most reliable for C projects):
curl -s https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<file> | grep SPDX
```
