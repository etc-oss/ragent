# Thin task-runner — ergonomic aliases that DELEGATE to nix. It is NOT a
# dependency manager: dependencies are pinned in flake.lock and declared as
# `projectTools` in flake.nix (see ADR-0019). Deleting this Makefile changes
# nothing about what's installed — it only saves you some typing.

.PHONY: shell workspace agent review test help

help:            ## Show these targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t—/'

shell:           ## Enter the workspace devshell (tools on PATH)
	nix develop

workspace:       ## Launch the two-side HUMAN/MACHINE workspace on this project
	nix run .#task-window -- $(or $(task),work)

review:          ## Show the current agent branch's proposed diff (agent/<task>)
	@git -C "$$PWD-agent-$(or $(task),work)" log --oneline -1 2>/dev/null \
	  && git fetch -q "$$PWD-agent-$(or $(task),work)" "agent/$(or $(task),work)" \
	  && git --no-pager diff "$$(git branch --show-current)"..FETCH_HEAD \
	  || echo "no agent clone yet — run 'make workspace task=<name>' first"

test:            ## Run this project's tests (uses projectTools from the devshell)
	nix develop --command sh -c 'pytest -q || true'
