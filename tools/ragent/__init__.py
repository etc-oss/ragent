"""ragent — the runtime package: the human-facing CLI, the async orchestrator, and the
pluggable review-transport adapters (ADR-0023 / 0020 / 0022).

Imported as a package with `tools/` on PYTHONPATH:

    python3 -m ragent.cli …                     # the CLI entry point (flake apps.default)
    from ragent.orchestrator import orchestrate
    from ragent.adapters import load

Standalone siblings stay flat in `tools/` (path-stable, no package deps):
`okf_render.py` (docs → HTML), `ragent-report.py` (per-task report), and the shell
launchers (`ragent-workspace.sh`, `ragent-confine.sh`, `ragent-serve.sh`, …).
"""
