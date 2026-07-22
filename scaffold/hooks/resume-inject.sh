#!/usr/bin/env bash
# Re-inject the curated resume file into the window after a context reset.
#
# Wired on SessionStart(compact|clear): fires after an autocompact replaces the
# conversation with a lossy summary, or after a deliberate /clear. Claude WRITES
# .context/RESUME.md before the reset (checkpoint.sh commits it at PreCompact;
# the /clear path relies on the land-step commit — ADR 0007); this reads it BACK
# from disk afterward — closing the checkpoint->resume loop so a reset session
# resumes from the curated substrate, not just the auto-summary.
#
# Bridge-free: needs no context-window data, so unlike context-nudge (which
# reads the project-local statusline bridge) it has nothing project-local at all.
#
# Output contract: for a SessionStart hook, stdout on exit 0 is added to
# Claude's context (Claude Code hooks reference — as for UserPromptSubmit).
# Plain stdout, no JSON envelope, no escaping. Silent no-op (exit 0) when there
# is nothing to resume from, so a fresh project is never disturbed.
set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

# Literal path, matching checkpoint.sh's writer: keep reader and writer on the
# same path so an override on one can never silently orphan the other.
resume=".context/RESUME.md"
[ -f "$resume" ] || exit 0

# Freshness cue so the model can weigh staleness. GNU stat (-c) resolves first;
# only BSD/macOS falls through to -f (where -f means format, not filesystem).
mtime="$(stat -c '%y' "$resume" 2>/dev/null || stat -f '%Sm' "$resume" 2>/dev/null || echo unknown)"

printf '## Resuming from checkpoint: %s (written %s)\n\n' "$resume" "$mtime"
printf '%s\n\n' 'The context was just reset (autocompact or /clear). This file is the curated resume state the prior session persisted — treat it as authoritative over any auto-generated summary. If it reads stale, re-verify against the repo before acting.'
cat "$resume" || true
