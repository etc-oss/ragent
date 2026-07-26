{
  description = "ragent — a forkable AI-coding workspace: confined agents (jail.nix) with human oversight, on Zellij + Lima.";

  # ---------------------------------------------------------------------------
  # Phase 0 starter flake.
  #
  # This is deliberately small and *resolvable*: it pins the real upstreams and
  # provides a docs devshell that runs on the macOS/Linux host. The full runtime
  # (the jail, the Zellij workspace, the agents, the shared CLIs) is built
  # incrementally from Phase 1 onward — see
  # docs/knowledge/components/forward-plan-phases-1-5.md. The original, larger
  # "vision" flake is preserved verbatim at
  # docs/knowledge/components/draft-flake-vision.md.
  #
  # Reference, don't vendor (ADR-0003): upstreams are pinned inputs; their source
  # is never copied into this repo. jail.nix is GPL-3.0 — referencing it keeps
  # this repo's Apache-2.0 umbrella clean.
  #
  # Local-resilience path (ADR-0010), so this builds offline if upstreams vanish:
  #   nix flake archive                 # pull all inputs into the local store
  #   nix copy --to file:///path/cache ...   # persist built closures
  #   nix flake lock --override-input jail-nix path:/path/to/mirror/jail.nix
  # Keep the private mirror OUT of this repo (.gitignore excludes /mirror/); see
  # tools/mirror-example.sh for a publishable template.
  # ---------------------------------------------------------------------------

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Machine-side confinement (wired in Phase 1). GPL-3.0; referenced, not vendored.
    jail-nix.url = "sourcehut:~alexdavid/jail.nix";

    # Prior art — jails opencode/pi/crush via jail.nix. Enable when a real agent
    # is pinned in Phase 1.
    # jailed-agents.url = "github:andersonjoseph/jailed-agents";
  };

  outputs = { self, nixpkgs, flake-utils, jail-nix, ... }:
    # eachDefaultSystem includes aarch64-darwin, so the docs tooling is usable on
    # the macOS host. The jail itself is Linux-only (bubblewrap needs Linux
    # namespaces) and is added under a Linux guard in Phase 1.
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        # Phase 0 devshell: everything needed to author and render the knowledge
        # bundle. Python is standard-library only — no third-party packages.
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.python3   # tools/okf_render.py (stdlib only)
            pkgs.git
          ];

          shellHook = ''
            echo "ragent devshell — Phase 0 (scaffold + knowledge)."
            echo "  Render docs:  python3 tools/okf_render.py   (-> docs/html/)"
            echo "  Knowledge:    docs/knowledge/   Entry: AGENTS.md"
            echo "  Next:         Phase 1 wires jail.nix (Linux/Lima). See the forward plan."
          '';
        };

        # Phase 1 will add, under a Linux guard, something like:
        #   packages.jailed-agent =
        #     let jail = jail-nix.lib.init pkgs; in
        #     jail "jailed-agent" <agent> (with jail.combinators; [
        #       network mount-cwd
        #       (readwrite (noescape "$PWD"))   # PROJECT DIR ONLY; $HOME excluded
        #     ]);
        # It is intentionally omitted here so this flake stays resolvable on macOS.
      });
}
