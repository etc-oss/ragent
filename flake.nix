{
  description = "ragent — a forkable AI-coding workspace: confined agents (jail.nix) with human oversight, on Zellij + Lima.";

  # ---------------------------------------------------------------------------
  # The docs devshell runs anywhere (incl. the macOS host). The jail and the
  # Zellij workspace are Linux only (bubblewrap needs Linux namespaces), so all
  # jail/workspace outputs are guarded to Linux systems and run inside a Linux
  # guest. The concrete VM config (Lima / cloud / NixOS) lives in a personal
  # config repo that consumes ragent — e.g. your-config-repo — see
  # docs/knowledge/components/running-on-a-vm.md. See also the forward plan and
  # ADRs 0012–0017.
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
            echo "  Jail/workspace: Linux only — run in a Linux guest (VM config in your config repo, e.g. your-config-repo)."
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
        #
        # jailed-agents' commonJailOptions (network/time-zone/no-new-session) does
        # NOT forward the provider API key, so an agent authenticates as "Not logged
        # in" even with a valid key in the environment. Extend the base options with
        # a runtime `fwd-env` of the provider keys (ADR-0014) — using jailed-agents'
        # OWN jail instance (ja.internals.jail) so the combinators match its jail.nix.
        # try-fwd-env tolerates a key being unset (agents that don't need it).
        jaCombinators = ja.internals.jail.combinators;
        agentBaseOptions = ja.commonJailOptions
          ++ map jaCombinators.try-fwd-env [ "ANTHROPIC_API_KEY" "OPENAI_API_KEY" ];

        # Build the four jailed agents with a given tool set on their in-jail PATH.
        # `projectTools` (from mkWorkspace, per project) joins sharedTools so a
        # confined agent gets the project's runtime/test tools (e.g. python+pytest)
        # and can self-verify — the limitation the first real loop surfaced.
        # CLAUDE_CODE_SIMPLE=1 makes Claude Code auth strictly via ANTHROPIC_API_KEY
        # (forwarded above); without it a jailed run reports "Not logged in".
        mkAgents = projectTools:
          let tools = sharedTools ++ projectTools; in rec {
            jailed-opencode = ja.makeJailedOpencode { extraPkgs = tools; baseJailOptions = agentBaseOptions; };
            jailed-claude-code = ja.makeJailedClaudeCode { extraPkgs = tools; env = { CLAUDE_CODE_SIMPLE = "1"; }; baseJailOptions = agentBaseOptions; };
            jailed-pi = ja.makeJailedPi { extraPkgs = tools; baseJailOptions = agentBaseOptions; };
            jailed-crush = ja.makeJailedCrush { extraPkgs = tools; baseJailOptions = agentBaseOptions; };
            list = [ jailed-opencode jailed-claude-code jailed-pi jailed-crush ];
          };

        # ---- Phase 2: the Zellij workspace (Linux) ----
        # neovim configured with LSP support (nvim-lspconfig) for the languages a
        # ragent repo actually uses: Nix (nixd), Python (basedpyright), Bash (bashls).
        lspServers = [ pkgs.nixd pkgs.basedpyright pkgs.bash-language-server ];
        ragentNvim = pkgs.neovim.override {
          configure = {
            packages.ragent.start = [ pkgs.vimPlugins.nvim-lspconfig pkgs.vimPlugins.tokyonight-nvim ];
            customRC = ''
              set number
              set termguicolors
              lua << LUAEOF
              -- Tokyo Night (neon/pastel, VS-Code-adjacent) with greens neutralized
              -- to neon cyan/teal — no explicit greens in the palette.
              require('tokyonight').setup({
                style = 'moon',           -- brighter, more neon than storm
                on_colors = function(c)
                  -- neutralize greens to bright neon cyan (no explicit greens)
                  c.green = '#86e1fc'; c.green1 = '#86e1fc'; c.green2 = '#89ddff'
                  c.teal = '#86e1fc'
                end,
                on_highlights = function(hl, c)
                  -- push accents brighter/neon
                  hl['@function'] = { fg = '#82aaff' }
                  hl['@keyword']  = { fg = '#c099ff' }
                end,
              })
              vim.cmd.colorscheme('tokyonight-moon')

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
        # The whole tools/ dir as one store path so ragent-report.py can import its
        # sibling okf_render.py at runtime (host-side task-report rendering).
        toolsDir = ./tools;

        # mkWorkspace: the parameterized workspace (ADR-0019). `projectTools` join
        # the agents' in-jail PATH, the Zellij pane PATH, and the devshell — so a
        # downstream project puts its runtime/test tools (e.g. python+pytest) where
        # the confined agent can use them. Ragent's own outputs are `mkWorkspace {}`
        # (behavior-preserving). Consumers call `ragent.lib.<system>.mkWorkspace`.
        mkWorkspace = { projectTools ? [ ], defaultAgent ? "jailed-opencode" }:
          let
            agents = mkAgents projectTools;
            tools = sharedTools ++ projectTools;
            # python3 is for the host-side task-report generator (tools/ragent-report.py),
            # which runs after each agent task in the agent pane — not for the jail.
            wsTools = [ pkgs.zellij ragentNvim pkgs.lazygit pkgs.git pkgs.btop pkgs.python3 ] ++ lspServers ++ tools;
            # Tools the Zellij panes invoke at runtime, baked into the layout as an
            # explicit PATH so panes work from ANY launch context.
            paneBin = pkgs.lib.makeBinPath (
              [ pkgs.bashInteractive pkgs.coreutils pkgs.git pkgs.lazygit pkgs.btop pkgs.python3 ragentNvim ]
              ++ lspServers ++ tools ++ agents.list);
            layout = pkgs.writeText "ragent-workspace.kdl" (builtins.replaceStrings
              [ "@bash@" "@paneBin@" ]
              [ "${pkgs.bashInteractive}/bin/bash" paneBin ]
              (builtins.readFile ./workspace/ragent-workspace.kdl));
            # The unified human-facing CLI (ADR-0023): `ragent task <window|orchestrate|
            # review|list|attach|kill>`. One closure carries everything the subcommands
            # need — the TUI stack, the four agents, python3, git, bash. The adapter
            # uses stdlib urllib (ADR-0022), so no curl/jq. ''${VAR:-default} keeps a
            # consumer's RAGENT_* overrides (e.g. your-config-repo's theme / agent).
            cliApp = pkgs.writeShellApplication {
              name = "ragent";
              runtimeInputs = wsTools ++ agents.list ++ [ pkgs.bashInteractive pkgs.coreutils ];
              text = ''
                export RAGENT_LAYOUT="''${RAGENT_LAYOUT:-${layout}}"
                export RAGENT_RUN_BIN="''${RAGENT_RUN_BIN:-${toolsDir}/ragent-confine.sh}"
                export RAGENT_REPORT_BIN="''${RAGENT_REPORT_BIN:-${toolsDir}/ragent-report.py}"
                export RAGENT_ZELLIJ_CONFIG="''${RAGENT_ZELLIJ_CONFIG:-${./workspace/zellij-config.kdl}}"
                export RAGENT_LAZYGIT_CONFIG="''${RAGENT_LAZYGIT_CONFIG:-${./workspace/lazygit-theme.yml}}"
                export RAGENT_AGENT="''${RAGENT_AGENT:-${defaultAgent}}"
                exec python3 ${toolsDir}/ragent_cli.py "$@"
              '';
            };
            devShell = pkgs.mkShell {
              packages = wsTools ++ agents.list ++ [ cliApp ];
              shellHook = ''
                export RAGENT_LAYOUT="''${RAGENT_LAYOUT:-${layout}}"
                export RAGENT_AGENT="''${RAGENT_AGENT:-${defaultAgent}}"
                export RAGENT_REPORT_BIN="''${RAGENT_REPORT_BIN:-${toolsDir}/ragent-report.py}"
                echo "ragent workspace devshell."
                echo "  Launch:  ragent task window <project-dir> [task]   (or: nix run . -- task window <project-dir>)"
                echo "  Tools:   zellij, nvim(+LSP), lazygit, git, git-surgeon, rg, fd, jq, btop${
                  pkgs.lib.optionalString (projectTools != [ ]) " + project tools"}"
              '';
            };
          in {
            inherit devShell agents layout;
            tools = wsTools;
            cli = cliApp;
          };
        defaultWs = mkWorkspace { };
        # A thin flat alias for a `ragent task <sub>` subcommand: `nix run .#task-<sub>`.
        mkTaskAlias = sub: desc: {
          type = "app";
          program = "${pkgs.writeShellApplication {
            name = "ragent-task-${sub}";
            text = ''exec ${defaultWs.cli}/bin/ragent task ${sub} "$@"'';
          }}/bin/ragent-task-${sub}";
          meta.description = desc;
        };
      in
      {
        devShells.default = docsShell;
      }
      // lib.optionalAttrs isLinux {
        packages = {
          inherit jailed-probe git-surgeon;
          inherit (defaultWs.agents) jailed-opencode jailed-claude-code jailed-pi jailed-crush;
        };
        devShells = { default = docsShell; workspace = defaultWs.devShell; };

        # The unified CLI is the default app (ADR-0023). Session management
        # (list/attach/kill — the old #zellij app) is folded into `ragent task …`.
        apps.default = {
          type = "app";
          program = "${defaultWs.cli}/bin/ragent";
          meta.description = "ragent — confined agents with human oversight (task window/orchestrate/review/list/attach/kill).";
        };
        # Thin aliases so `nix run .#task-<x> -- …` works without the `task` prefix.
        apps.task-window = mkTaskAlias "window" "Launch/attach the two-side human/machine TUI workspace on a project.";
        apps.task-orchestrate = mkTaskAlias "orchestrate" "Run an agent task and open a review (PR) via the configured forge adapter.";
        apps.task-review = mkTaskAlias "review" "Serve a project's per-task HTML reports over HTTP (localhost by default).";
        # Dev-time forge (moves to your-config-repo in G2/ADR-0018 — VM/deploy config).
        apps.forgejo-local = {
          type = "app";
          program = "${pkgs.writeShellApplication {
            name = "ragent-forgejo-local";
            runtimeInputs = [ pkgs.forgejo pkgs.git pkgs.curl ];
            text = ''exec ${toolsDir}/forgejo-local.sh "$@"'';
          }}/bin/ragent-forgejo-local";
          meta.description = "Start a local dev Forgejo (127.0.0.1) + write the transport env.";
        };
        # `nix flake check` builds these (the jail + the shared CLI). The
        # confinement negative-control RUNTIME test and docs-sync run in CI
        # (.github/workflows/ci.yml) — bubblewrap needs runtime namespaces a nix
        # build sandbox can't guarantee.
        checks = { inherit jailed-probe git-surgeon; };
        # The parameterized workspace, so a project can add its own in-jail tools
        # (ADR-0019):  ragent.lib.<system>.mkWorkspace { projectTools = [ … ]; }
        lib = { inherit mkWorkspace sharedTools; };
      }
    ))
    // {
      # A per-project template that consumes ragent as a pinned flake input
      # (ADR-0003 / ADR-0007). Scaffold with:  nix flake init -t <ragent>#default
      templates.default = {
        path = ./templates/default;
        description = "A per-project ragent workspace that consumes ragent as a flake input.";
      };

      # VM/deployment specifics (Lima config, cloud provisioning, and the
      # declarative NixOS box) live in a personal config repo that consumes ragent
      # — e.g. your-config-repo — not in the framework. See ADR-0012 and
      # docs/knowledge/components/running-on-a-vm.md.
    };
}
