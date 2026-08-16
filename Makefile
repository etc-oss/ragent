# ragent — a thin dev task-runner that DELEGATES to nix. It is NOT a dependency
# manager: dependencies are `projectTools` in flake.nix (ADR-0019). Deleting this
# changes nothing about what's installed — it only saves you some typing.

.PHONY: help shell workspace clean test docs

help:       ## Show these targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t— /'

shell:      ## Workspace devshell — the ragent CLI + the jailed agents on PATH
	nix develop .#workspace

workspace:  ## Launch the two-side HUMAN/MACHINE workspace (task=<name>, default: work)
	nix run .#task-window -- $(or $(task),work)

clean:      ## GC agent clones via `ragent task clean`  (args="--dry-run" | "--all")
	nix run . -- task clean $(args)

test:       ## Run the Python test suites (forgejo fixture provided for the adapter test)
	nix shell nixpkgs#forgejo nixpkgs#git nixpkgs#python3 --command \
	  bash -c 'for t in tests/test_*.py; do echo "== $$t"; python3 "$$t"; done'

docs:       ## Render the OKF knowledge bundle → docs/html/
	nix develop --command python3 tools/okf_render.py
