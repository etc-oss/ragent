"""Review-transport adapter contract (ADR-0020).

The orchestrator is transport-agnostic: it programs against this ABC and never
names a concrete forge. Each backend (Forgejo, GitLab, GitHub, git-over-SSH) is a
`ReviewAdapter` subclass. The verb set is the superset from ADR-0020, grouped:

    meta          ping, capabilities
    code          init, push
    review        handover, status, merge
    conversation  examine, reply

`capabilities()` lets a partial transport (e.g. bare git-over-SSH = {CODE}) be
driven safely: the orchestrator branches on capability, never on adapter identity,
and degrades gracefully (falls back to the served-HTML review for conversation).
"""

from abc import ABC, abstractmethod

# Capability groups.
CODE = "code"
REVIEW = "review"
CONVERSATION = "conversation"


class ReviewAdapter(ABC):
    # --- meta -----------------------------------------------------------------
    @abstractmethod
    def ping(self) -> bool:
        """Is the transport reachable and the token valid? (run once, up front)"""

    @abstractmethod
    def capabilities(self) -> set:
        """Subset of {CODE, REVIEW, CONVERSATION} this adapter supports."""

    # --- code -----------------------------------------------------------------
    @abstractmethod
    def init(self) -> None:
        """Ensure the project's remote repo exists (create if missing)."""

    @abstractmethod
    def push(self, clone: str, branch: str, base: str) -> None:
        """Push the base branch first, then the agent branch, to the transport."""

    # --- review lifecycle -----------------------------------------------------
    @abstractmethod
    def handover(self, branch: str, base: str, title: str, body: str):
        """Open (or reuse) the review unit. Returns a review handle (id/number)."""

    @abstractmethod
    def status(self, review) -> str:
        """One of: 'pending' | 'changes-requested' | 'approved'."""

    @abstractmethod
    def merge(self, review) -> None:
        """Land the change (only when approved / autoMerge)."""

    # --- conversation ---------------------------------------------------------
    @abstractmethod
    def examine(self, review) -> list:
        """Read the human's review notes. Returns a list of note dicts, oldest
        first, each {ts, author, body, kind} (kind: 'review' | 'comment'). The
        orchestrator filters to notes newer than what the agent has seen."""

    @abstractmethod
    def reply(self, review, text: str) -> None:
        """Post the agent's response back into the review thread."""

    # --- helpers (not abstract) ----------------------------------------------
    def review_url(self, review) -> str:
        """Human-facing URL for a review handle. Override if the adapter knows it."""
        return str(review)
