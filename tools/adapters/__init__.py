"""Review-transport adapters (ADR-0020).

`load()` builds the adapter named by RAGENT_ADAPTER from the RAGENT_FORGE_* env
(written by the dev forge harness or a remote NixOS Forgejo — same code, only the
URL/token differ). The orchestrator imports the ABC, never a concrete forge.
"""

import os

from .base import ReviewAdapter, CODE, REVIEW, CONVERSATION  # noqa: F401


def load(name=None, **cfg) -> ReviewAdapter:
    name = name or os.environ.get("RAGENT_ADAPTER")
    if not name:
        raise SystemExit("set RAGENT_ADAPTER (source ~/.config/ragent/forge.env)")
    if name == "forgejo":
        from .forgejo import ForgejoAdapter
        return ForgejoAdapter.from_env(**cfg)
    raise SystemExit(
        f"unknown adapter '{name}' (have: forgejo). GitLab/GitHub/ssh are on the roadmap."
    )
