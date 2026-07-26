{
  description = "ragent — a forkable AI-coding workspace: confined agents (jail.nix) with human oversight, on Zellij + Lima.";

  # ---------------------------------------------------------------------------
  # The docs devshell runs anywhere (incl. the macOS host). The jail and the
  # Zellij workspace are Linux only (bubblewrap needs Linux namespaces), so all
  # jail/workspace outputs are guarded to Linux systems and run inside a Lima
  # guest (see lima/ragent.yaml). See docs/knowledge/components/forward-plan and
  # ADRs 0013–0017.
  #
  # Reference, don't vendor (ADR-0003): upstreams are pinned inputs; their source
  # is never copied into this repo. jail.nix is GPL-3.0 — referencing it keeps
  # this repo's Apache-2.0 umbrella clean.
  # ---------------------------------------------------------------------------

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Machine-side confinement. GPL-3.0; referenced, not vendored.
    jail-nix.url = "sourcehut:~alexdavid/jail.nix";

    # Jails for LLM agents built on jail.nix (makeJailedOpencode / …ClaudeCode / …Pi).
    jailed-agents.url = "github:andersonjoseph/jailed-agents";

    # Shared CLI: raine/git-surgeon — "git primitives for autonomous coding agents"
    # (ADR-0017). Pinned to the v0.1.17 release, which predates its own flake, so
    # we take the source (flake=false) and buildRustPackage it (pure/sandbox-safe).
    git-surgeon-src = {
      url = "github:raine/git-surgeon/v0.1.17";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, jail-nix, jailed-agents, git-surgeon-src, ... }:
    let inherit (nixpkgs) lib; in
    # Enumerate systems explicitly: nixpkgs 26.11 dropped x86_64-darwin.
    (flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true; # Claude Code is unfree (jailed-claude-code only).
        };
        # Decide Linux-ness from the system STRING — do NOT force `pkgs` here, or
        # merging outputs would import nixpkgs for every system (incl. dropped
        # x86_64-darwin) just to branch, which errors at eval time.
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

        # ---- Phase 3: shared CLI tools (Linux) ----
        # raine/git-surgeon, built from the pinned source. Cargo.lock has no git
        # deps, so cargoLock.lockFile alone vendors everything (no outputHashes).
        git-surgeon = pkgs.rustPlatform.buildRustPackage {
          pname = "git-surgeon";
          version = "0.1.17";
          src = git-surgeon-src;
          cargoLock.lockFile = git-surgeon-src + "/Cargo.lock";
        };

        # The shared-tools layer (ADR-0007): put these on every agent's in-jail
        # PATH so agents invoke them through bash with no per-agent adapter.
        # git-surgeon shells out to git, so git is included.
        sharedTools = [ git-surgeon pkgs.git pkgs.ripgrep pkgs.fd pkgs.jq ];

        # ---- Phase 1: the jail (Linux) ----
        jail = jail-nix.lib.init pkgs;
        ja = jailed-agents.lib.${system};

        # The confinement contract. Bubblewrap exposes the bare minimum by default,
        # so $HOME, SSH keys, and every other secret are DENIED unless bound — and
        # we bind nothing but the cwd. The probe also carries sharedTools so the
        # confinement test exercises the same profile the agents use.
        confinementProfile = with jail.combinators; [
          network                                        # egress for the LLM API
          time-zone
          no-new-session
          mount-cwd                                      # the PROJECT DIRECTORY (cwd) rw — nothing else
          (try-fwd-env "ANTHROPIC_API_KEY")              # runtime-forwarded key; never in the store (ADR-0014)
          (add-pkg-deps ([ pkgs.bashInteractive pkgs.coreutils ] ++ sharedTools))
        ];
        jailed-probe = jail "ragent-jail-probe" pkgs.bashInteractive confinementProfile;

        # Agents get the shared tools on their in-jail PATH via extraPkgs. All four
        # are jailed identically (same confinement + sharedTools), so they invoke
        # the tooling layer uniformly through bash.
        jailed-opencode = ja.makeJailedOpencode { extraPkgs = sharedTools; };
        jailed-claude-code = ja.makeJailedClaudeCode { extraPkgs = sharedTools; };
        jailed-pi = ja.makeJailedPi { extraPkgs = sharedTools; };
        jailed-crush = ja.makeJailedCrush { extraPkgs = sharedTools; };
        allAgents = [ jailed-opencode jailed-claude-code jailed-pi jailed-crush ];

        # ---- Phase 2: the Zellij workspace (Linux) ----
        # neovim configured with LSP support (nvim-lspconfig) for the languages a
        # ragent repo actually uses: Nix (nixd), Python (basedpyright), Bash (bashls).
        lspServers = [ pkgs.nixd pkgs.basedpyright pkgs.bash-language-server ];
        ragentNvim = pkgs.neovim.override {
          configure = {
            packages.ragent.start = [ pkgs.vimPlugins.nvim-lspconfig ];
            customRC = ''
              set number
              set termguicolors
              lua << LUAEOF
              -- nvim 0.11+ LSP API; nvim-lspconfig supplies the server defs on
              -- the runtimepath (its lsp/*.lua), so no deprecated framework call.
              vim.lsp.enable({ 'nixd', 'basedpyright', 'bashls' })
              vim.api.nvim_create_autocmd('LspAttach', { callback = function(ev)
                local b = ev.buf
                vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = b })
                vim.keymap.set('n', 'K',  vim.lsp.buf.hover,      { buffer = b })
                vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, { buffer = b })
              end })
              LUAEOF
            '';
          };
        };
        # Shared between the workspace devshell and the packaged launcher app.
        workspaceTools = [ pkgs.zellij ragentNvim pkgs.lazygit pkgs.git ] ++ lspServers ++ sharedTools;
        workspaceShell = pkgs.mkShell {
          packages = workspaceTools ++ allAgents;
          shellHook = ''
            echo "ragent workspace devshell (Phase 2–3)."
            echo "  Launch:  ./tools/ragent-workspace.sh <project-dir> [task]"
            echo "  Tools:   zellij, nvim (+LSP: nixd/basedpyright/bashls), lazygit, git, git-surgeon, rg, fd, jq"
            echo "  Agents:  jailed-opencode, jailed-claude-code (run via tools/ragent-run.sh)"
          '';
        };

        # A packaged, checkout-free launcher: `nix run .#workspace -- <project>`.
        # Bundles the layout + ragent-run.sh as store paths and the workspace tools
        # as runtime inputs, so downstream projects launch without cloning ragent.
        workspaceApp = pkgs.writeShellApplication {
          name = "ragent-workspace";
          runtimeInputs = workspaceTools ++ allAgents;
          text = ''
            export RAGENT_LAYOUT=${./workspace/ragent-workspace.kdl}
            export RAGENT_RUN_BIN=${./tools/ragent-run.sh}
            exec ${./tools/ragent-workspace.sh} "$@"
          '';
        };
      in
      {
        devShells.default = docsShell;
      }
      // lib.optionalAttrs isLinux {
        packages = {
          inherit jailed-probe jailed-opencode jailed-claude-code jailed-pi jailed-crush git-surgeon;
          # Zellij itself, unconfined, for session management (attach/detach/list/
          # kill) independent of a workspace launch: `nix run .#zellij -- <args>`.
          zellij = pkgs.zellij;
        };
        devShells = { default = docsShell; workspace = workspaceShell; };
        apps.workspace = {
          type = "app";
          program = "${workspaceApp}/bin/ragent-workspace";
          meta.description = "Launch the ragent two-side human/machine workspace on a project.";
        };
        # `nix flake check` builds these (the jail + the shared CLI). The
        # confinement negative-control RUNTIME test and docs-sync run in CI
        # (.github/workflows/ci.yml) — bubblewrap needs runtime namespaces a nix
        # build sandbox can't guarantee.
        checks = { inherit jailed-probe git-surgeon; };
      }
    ))
    // {
      # A per-project template that consumes ragent as a pinned flake input
      # (ADR-0003 / ADR-0007). Scaffold with:  nix flake init -t <ragent>#default
      templates.default = {
        path = ./templates/default;
        description = "A per-project ragent workspace that consumes ragent as a flake input.";
      };
    };
}
