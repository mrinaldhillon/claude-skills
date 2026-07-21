#!/usr/bin/env bash
# SubagentStop hook — append-only breadcrumb trail of Agent-tool subagent completions.
#
# WHY: a recovery INDEX. When the main loop's context is later compacted, a subagent's
# tool-result text is dropped with it — but the subagent's full transcript persists on
# disk. Logging (timestamp, transcript_path, bounded snippet) keeps that work findable.
#
# LIMITS (honest scope — this is a breadcrumb, not magic):
#  - Fires ONLY for Agent-tool subagents in THIS session. It does NOT fire for
#    Workflow-internal agents (isolated run) — so it is NOT the fix for workflow token
#    burn; that fix is per-stage `opts.model` (discipline rule 10; orchestration skill).
#  - It does NOT automate compaction. The durable checkpoint is .context/RESUME.md,
#    committed by checkpoint.sh on PreCompact only (ADR 0003; the Stop trigger was
#    removed 2026-07-21 — see ADR 0003 Consequences). This only indexes
#    transcripts so they stay recoverable.
#  - Best-effort: any failure degrades to path-only, or a no-op. Never blocks the
#    session. SubagentStop delivers JSON on stdin with .transcript_path (no result text).
#
# Deliberately NOT `set -euo pipefail`: a checkpoint breadcrumb must never abort or
# return non-zero into the session. Errors are swallowed; the script always exits 0.

payload="$(cat 2>/dev/null || true)"

proj="$(printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}" | sed 's@/@-@g')"
memdir="$HOME/.claude/projects/$proj/memory"
log="$memdir/.subagent-trail.log"
[ -d "$memdir" ] || exit 0   # no project memory dir → nothing to checkpoint

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

# transcript_path from the payload (jq optional — degrade if absent).
transcript=""
if command -v jq >/dev/null 2>&1; then
  transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
fi

# Best-effort last-assistant-text snippet. Reads only the transcript tail (bounded
# memory) and degrades HARD to empty on any parse failure — path remains the anchor.
snippet=""
if [ -n "$transcript" ] && [ -f "$transcript" ] && command -v jq >/dev/null 2>&1; then
  snippet="$(tail -n 200 "$transcript" 2>/dev/null \
    | jq -rs 'map(select(.message.role? == "assistant"))
              | last
              | (.message.content[]? | select(.type? == "text") | .text)' 2>/dev/null \
    | tr '\n\t' '  ' \
    | sed 's/  */ /g' \
    | cut -c1-200 || true)"
fi

[ -n "$transcript" ] || transcript="(transcript_path absent in payload)"

printf '%s\t%s\t%s\n' "$ts" "$transcript" "$snippet" >> "$log" 2>/dev/null || true

# Bound the trail to its last 500 lines so it can't grow without limit.
if [ -f "$log" ]; then
  { tail -n 500 "$log" > "$log.tmp" 2>/dev/null && mv "$log.tmp" "$log" 2>/dev/null; } \
    || rm -f "$log.tmp" 2>/dev/null || true
fi

exit 0
