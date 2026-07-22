# 8. Graduate the context-nudge hook into the plugin

- **Status:** Accepted
- **Date:** 2026-07-22
- **Supersedes:** [0003](0003-context-management-checkpoint-resume.md) — the
  project-local *placement* of Decision §2 only (the thresholds and nudge mechanism
  stand); also retires the scaffold README's standing "`context-nudge` is
  intentionally not here" rationale (recorded there, never in an ADR)
- **Superseded by:** —

## Context

ADR 0003 placed `context-nudge.sh` project-local, paired with `statusline.sh`, both
hand-copied from `references/project-setup/`. The README's rationale: a plugin cannot
set the `statusLine` settings key, so "shipping the hook alone would be a
permanently-dead artifact."

Two things changed:

1. **The dead-artifact premise was wrong in emphasis.** Without the bridge file the
   hook exits in ~1 ms (`[ -f "$state_file" ] || exit 0`) — a cheap no-op, not a dead
   artifact. The real cost sat on the other side: the hook is the *complex, evolving*
   half of the pair (threshold rounding, GNU/BSD `stat` divergence, PostToolUse JSON
   injection, cooldown state), and hand copies of it rot.
2. **The rot was observed, not hypothesized.** A consuming repo hit a cross-session
   nudge leak — a bridge file written by one session's statusline nudged a *different*
   session sharing the same checkout (another window, headless `-p`, an IDE panel).
   The mtime staleness guard cannot catch this: the percentage stays fresh while
   belonging to someone else. The fix (a session-identity handshake) had to be
   authored downstream and back-ported here — exactly the drift the plugin layer
   exists to prevent.

Verified against current docs (2026-07-22): a plugin's own `settings.json` supports
only `agent` and `subagentStatusLine`; there is no mechanism for a plugin to set the
main `statusLine`, and `${CLAUDE_PLUGIN_ROOT}` does not expand in a user's own
`settings.json`. Plugin `hooks.json` supports `UserPromptSubmit` and `PostToolUse`
identically to project hooks (code.claude.com/docs/en/plugins-reference, /statusline,
/hooks).

## Decision

1. **The hook ships in the plugin.** `scaffold/hooks/context-nudge.sh`, wired in
   `hooks.json` on both events — `UserPromptSubmit` (plain-stdout injection) and
   `PostToolUse` matcher `*` (`hookSpecificOutput.additionalContext`, per ADR 0004 §4).
   The `references/project-setup/` copy is deleted; single source of truth.
2. **The bridge stays project-local.** `statusline.sh` remains a documented reference
   copy wired by the consumer's own `statusLine` settings key — the one thing a plugin
   structurally cannot provide. Copying one thin, stable file is the entire remaining
   setup step; the evolving half now updates by version bump.
3. **Session-identity guard.** The statusline stamps `session_id` into the bridge;
   the hook compares it against the hook payload's `session_id` on BOTH events and
   stays silent on mismatch. A missing id on either side degrades to prior behavior
   (the PostToolUse mtime staleness guard still covers pre-session-id bridges).
4. **Surface log.** Before its jq guard (an embedded host may lack a Homebrew PATH),
   the hook appends one deduplicated line per unique (`__CFBundleIdentifier`,
   `CLAUDE_CODE_EXECPATH`) pair to `.claude/state/hook-surface-log.jsonl` — making
   "do plugin hooks fire on host X" passively observable. Best-effort; never fails
   or slows the hook.

## Consequences

- **Consumers must delete their project-side copy and wiring in the same change that
  adopts the new plugin version.** Claude Code *merges* plugin and project hooks: any
  overlap double-fires the nudge on every tool call, and a threshold crossing injects
  twice. The setup guide's complement rule now lists `context-nudge` among the
  never-wire-in-project hooks.
- Repos without the statusline bridge pay a ~1 ms no-op per prompt/tool event.
- The consumer's statusline copy should be refreshed to the session-id-stamping
  version; an old bridge (no `session_id`) keeps working via the degraded path but
  stays exposed to the cross-session leak the guard exists to close.
- `.claude/state/` gains `hook-surface-log.jsonl` (already gitignored per the setup
  guide's §5 convention).
