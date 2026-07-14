# 5. Agent-written state lives in .context/, not docs/

- **Summary:** Agent-written project state (`project-context.md`, `RESUME.md`, milestone sentinels) lives in `.context/`, not `docs/` or `.claude/`. Machinery of record is in the scaffold plugin — see plugin reference.
- **Status:** Accepted (machinery relocated)
- **Date:** <fill on adoption>
- **Supersedes:** —
- **Superseded by:** —

## Decision

This project delegates the agent-state location **decision** (agent-written state in
`.context/`, documentation in `docs/`, machine-local volatile data in `.claude/state/`)
to the `scaffold` plugin. The rationale of record lives in the plugin at
[`../../decisions/0005-agent-state-in-context-dir.md`](../../decisions/0005-agent-state-in-context-dir.md),
versioned with the plugin. This slot is retained to preserve append-only numbering.
