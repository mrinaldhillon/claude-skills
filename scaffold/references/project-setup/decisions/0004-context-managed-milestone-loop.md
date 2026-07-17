# 4. Context-managed milestone loop

- **Summary:** Long milestones run as session-chosen chunks behind deterministic gates, checkpointing between chunks. Machinery of record is in the scaffold plugin — see plugin reference.
- **Status:** Accepted (machinery relocated)
- **Date:** <fill on adoption>
- **Supersedes:** —
- **Superseded by:** —

## Decision

This project delegates the context-managed milestone loop **machinery** (the
`milestone-runner.sh` outer loop, deterministic iteration/done gates, cost and
flag-drift hardening, and the watchdog/lock) to the `scaffold` plugin. The rationale
of record lives in the plugin's ADR set (`scaffold/references/decisions/0004-*.md`),
versioned with the plugin. This slot is retained to preserve append-only numbering.
The project-level convention it implies — long milestones run as dynamic,
session-chosen chunks behind deterministic gates, not a fixed phase list — is
surfaced via the `milestone-workflow` skill and the `/goal`/`/milestone` commands.
