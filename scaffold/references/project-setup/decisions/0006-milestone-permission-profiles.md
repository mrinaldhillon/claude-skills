# 6. Milestone permission profiles

- **Summary:** Milestone runs pick a permission profile (strict / sandboxed auto / containment-gated bypass) scoped to risk. Machinery of record is in the scaffold plugin — see plugin reference.
- **Status:** Accepted (machinery relocated)
- **Date:** <fill on adoption>
- **Supersedes:** —
- **Superseded by:** —

## Decision

This project delegates the milestone permission-profile **machinery** (`strict` /
`auto` sandboxed / `bypass` containment-gated, and the runner's per-profile flag
construction and denial policy) to the `scaffold` plugin. The rationale of record
lives in the plugin's ADR set (`scaffold/references/decisions/0006-*.md`), versioned
with the plugin. This slot is retained to preserve append-only numbering. The
project-level convention it implies — pick the least-privileged profile that fits the
milestone, `strict` by default — is surfaced via the `milestone-workflow` skill and
the `/milestone` command's `permission_profile` config field.
