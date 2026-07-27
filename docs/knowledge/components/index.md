---
type: index
id: INDEX-components
title: Components
description: Architecture concepts and the forward plan.
tags: [index, components, architecture]
timestamp: 2026-07-26
---

# Components

Architecture concepts and planning.

- [COMP-roadmap — Roadmap & future guidelines](roadmap.md)
  — the long view: current state, Phase 6, future direction, guiding principles.

- [COMP-architecture-overview — Architecture overview](architecture-overview.md)
  — the layered map (host → VM → jail → panes) and how the ADRs fit together.
- [COMP-forward-plan — Forward plan (Phases 1–5)](forward-plan-phases-1-5.md)
  — the phased roadmap with tasks, exit criteria, and risks.
- [COMP-knowledge-system — Knowledge system (OKF + HTML)](knowledge-system.md)
  — how the bundle is authored and rendered.
- [COMP-draft-flake-vision — Draft flake (original vision, preserved)](draft-flake-vision.md)
  — the verbatim pre-Phase-0 flake the starter builds toward.
- [COMP-running-on-a-vm — Running ragent on a VM instead of the host](running-on-a-vm.md)
  — how to drop the Lima layer and run host-independently (cloud / NixOS VM).
- [COMP-phase6-remote-async-review — Phase 6 (proposed): remote access & async web review](phase6-remote-and-async-review.md)
  — evaluation of Zellij remote sessions + a server-backed diff-review surface.
- [COMP-forgejo-transport — Forgejo-as-transport for async agent review (design)](forgejo-transport-design.md)
  — concrete Phase 6a design: shared guest forge, outside-jail push, bounded comment loop.
