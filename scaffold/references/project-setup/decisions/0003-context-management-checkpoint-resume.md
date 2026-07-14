# 3. Context management by checkpoint-resume, not compaction

- **Summary:** Durable state lives in files; checkpoint before clearing. Machinery of record is in the scaffold plugin — see plugin reference.
- **Status:** Accepted (machinery relocated)
- **Date:** <bootstrap fills>
- **Supersedes:** —
- **Superseded by:** —

## Decision

This project delegates the context checkpoint-resume **machinery** (the statusline
bridge, the context-nudge thresholds, the `checkpoint.sh` hook, and the milestone
runner) to the `scaffold` plugin. The rationale of record lives in the plugin's ADR
set (`scaffold/references/decisions/0003-*.md`), versioned with the plugin. This slot
is retained to preserve append-only numbering. The project-level convention it implies
— durable state in files, checkpoint before clearing — is stated in `CLAUDE.md`
§"Context & checkpoint protocol".
