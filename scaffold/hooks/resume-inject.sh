#!/usr/bin/env bash
# Re-inject the curated resume file into the window after a context reset.
#
# Wired on SessionStart(compact|clear): fires after an autocompact replaces the
# conversation with a lossy summary, or after a deliberate /clear. Claude WRITES
# .context/RESUME.md before the reset; this reads it BACK from disk afterward —
# closing the checkpoint->resume loop so a reset session resumes from the
# curated substrate, not just the auto-summary.
#
# Reads from DISK, never from git — and that independence is now load-bearing,
# not incidental. checkpoint.sh commits this file only when the project TRACKS
# it: a project may legitimately gitignore it, since per-checkout state never
# converges between branches and tracking it manufactures a rebase conflict on
# every branch that outlives one session. When it is ignored, checkpoint.sh
# skips it and nothing commits it — this hook is unaffected either way. The
# /clear path never had a commit to rely on regardless, because /clear fires no
# PreCompact at all (ADR 0007).
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
# Authority is assigned by KIND, not by recency, and the distinction is real:
# on /clear there is no summary at all, so this file is the only carrier; on an
# autocompact the summary exists and was generated just now, while this file is
# only as fresh as the last time Claude wrote it. Claiming blanket authority
# over "any auto-generated summary" is therefore right on one trigger and wrong
# on the other. One sentence that holds on both beats branching on the trigger.
printf '%s\n\n' 'The context was just reset (autocompact or /clear). This file is the curated resume state the prior session persisted. For the next action and durable pointers, it wins. After an autocompact the auto-summary may hold fresher mid-task detail than this file — weigh the written timestamp above, and re-verify against the repo where the two disagree.'
cat "$resume" || true
