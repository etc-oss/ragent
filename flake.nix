{
  description = "ragent — a forkable AI-coding workspace: confined agents (jail.nix) with human oversight, on Zellij + Lima.";

  # ---------------------------------------------------------------------------
  # The docs devshell runs anywhere (incl. the macOS host). The jail and the
  # Zellij workspace are Linux only (bubblewrap needs Linux namespaces), so all
  # jail/workspace outputs are guarded to Linux systems and run inside a Lima
  # guest (see lima/ragent.yaml). See docs/knowledge/components/forward-plan and
  # ADRs 0013–0016.
  #
  # Reference, don't vendor (ADR-0003): upstreams are pinned inputs; their source
  # is never copied into this repo. jail.nix is GPL-3.0 — referencing it keeps
  # this repo's Apache-2.0 umbrella clean.
  #
  # Local-resilience path (ADR-0010): nix flake archive + a private mirror +
  # --override-input failover. Keep the mirror OUT of this repo; see
  # tools/mirror-example.sh.
  # ---------------------------------------------------------------------------

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Machine-side confinement. GPL-3.0; referenced, not vendored.
    jail-nix.url = "sourcehut:~alexdavid/jail.nix";

    # Jails for LLM agents built on jail.nix (makeJailedOpencode / …ClaudeCode / …Pi).
    jailed-agents.url = "github:andersonjoseph/jailed-agents";
  };

  outputs = { self, nixpkgs, flake-utils, jail-nix, jailed-agents, ... }:
    let inherit (nixpkgs) lib; in
    # Enumerate systems explicitly: nixpkgs 26.11 dropped x86_64-darwin.
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          # Claude Code is distributed unfree; needed only for jailed-claude-code.
          config.allowUnfree = true;
        };
        # Decide Linux-ness from the system STRING. Do NOT force `pkgs` for this —
        # merging the outputs attrset would then import nixpkgs for every system
        # (incl. dropped x86_64-darwin) just to branch, which errors at eval time.
        isLinux = lib.hasSuffix "-linux" system;

        # Phase 0 docs devshell — usable on macOS and Linux. Stdlib Python only.
        docsShell = pkgs.mkShell {
          packages = [ pkgs.python3 pkgs.git ];
          shellHook = ''
            echo "ragent docs devshell."
            echo "  Render docs:  python3 tools/okf_render.py   (-> docs/html/)"
            echo "  Jail/workspace: Linux only — run inside the Lima guest (lima/ragent.yaml)."
          '';
        };

        # ---- Phase 1: the jail (Linux only) ----
        jail = jail-nix.lib.init pkgs;
        ja = jailed-agents.lib.${system};

        # The confinement contract, stated once. Bubblewrap exposes the bare
        # minimum by default, so $HOME, SSH keys, and every other secret are
        # DENIED unless explicitly bound — and we bind nothing but the cwd.
        confinementProfile = with jail.combinators; [
          network                              # egress for the LLM API
          time-zone
          no-new-session
          mount-cwd                            # the PROJECT DIRECTORY (cwd) rw — and nothing else
          (try-fwd-env "ANTHROPIC_API_KEY")    # runtime-forwarded key; never enters the Nix store (ADR-0014)
          (add-pkg-deps (with pkgs; [ bashInteractive coreutils ]))
        ];

        # A jailed shell carrying exactly the agent confinement profile — the
        # security proof that tools/confinement-test.sh drives (ADR-0013).
        jailed-probe = jail "ragent-jail-probe" pkgs.bashInteractive confinementProfile;
        jailed-opencode = ja.makeJailedOpencode { };
        jailed-claude-code = ja.makeJailedClaudeCode { };

        # ---- Phase 2: the Zellij workspace (Linux only) ----
        # Tools for the two-side workspace. Launch the workspace from THIS shell
        # (or via `nix develop .#workspace`) so the Zellij panes inherit a PATH
        # with nvim/lazygit/the agents on it. neovim here is plain — no LSPs are
        # configured yet (that is a later refinement, not claimed as done).
        workspaceShell = pkgs.mkShell {
          packages = [
            pkgs.zellij
            pkgs.neovim
            pkgs.lazygit
            pkgs.git
            jailed-opencode
            jailed-claude-code
          ];
          shellHook = ''
            echo "ragent workspace devshell (Phase 2)."
            echo "  Launch:  ./tools/ragent-workspace.sh <project-dir> [task]"
            echo "  Tools:   zellij, nvim (plain), lazygit, git"
            echo "  Agents:  jailed-opencode, jailed-claude-code (run via tools/ragent-run.sh)"
          '';
        };
      in
      {
        devShells.default = docsShell;
      }
      // lib.optionalAttrs isLinux {
        packages = { inherit jailed-probe jailed-opencode jailed-claude-code; };
        devShells = { default = docsShell; workspace = workspaceShell; };
      }
    );
}
