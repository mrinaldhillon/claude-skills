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

## Verification

Measured 2026-07-22 against Claude Code 2.1.217 — treat each as a refutable
hypothesis and re-probe on version bumps.

1. **A plugin cannot set `statusLine`.** Its own `settings.json` supports only the
   `agent` and `subagentStatusLine` keys (plugins-reference, plugin-structure table);
   `${CLAUDE_PLUGIN_ROOT}` does not expand in a user's own `settings.json` either.
   This is what forces the split — it is not a stylistic choice.
2. **No hook payload carries main-session context-window data.** The full hooks
   reference documents no `context_window`/`used_percentage`/`exceeds_200k_tokens`
   field on any event: `Stop` carries `stop_hook_active`/`last_assistant_message`/
   `background_tasks`/`session_crons`, `SessionEnd` carries `reason`, `PreCompact`
   carries `trigger`/`custom_instructions`, `PostCompact` carries `trigger`/
   `compact_summary`. In the 2.1.217 binary, `context_window_size`/`current_usage`/
   `used_percentage`/`remaining_percentage` appear in exactly one place — the
   `tengu_status_line_result` payload constructor — with no hook code path. And a
   headless `claude -p --output-format json` terminal result carries raw `usage`
   token counts but no `context_window_size`: the numerator without the denominator.
   *(Narrow exception, no help here: `PostToolUse` on a completed `Agent` call
   carries `tool_response.totalTokens`/`usage` — that is subagent cost, not this
   session's context.)*
   **Consequence: the statusline bridge is the only live source, so this split is
   the only shape available — not merely the preferred one.** Rejected alternatives:
   deriving a percentage from `transcript_path` (`message.usage` gives the three
   numerator terms, but the context limit is published only on the statusline
   payload — a hardcoded 200k/1M guess is wrong in both directions), and
   `PreCompact(auto)` (a real bridge-free signal, but it fires *after* the window
   filled, which is the failure this design exists to pre-empt).
3. **Plugin `hooks.json` supports `UserPromptSubmit` and `PostToolUse`** identically
   to project hooks; `UserPromptSubmit` stdout on exit 0 becomes context, while
   `PostToolUse` requires `hookSpecificOutput.additionalContext` — hence dual mode.

Sources: code.claude.com/docs/en/{plugins-reference,statusline,hooks}; `strings` on
the 2.1.217 binary; a live headless `--output-format json` run.

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
- **The consumer's statusline copy MUST be refreshed in the same change** — it is a
  numbered step in the migration checklist, not advice. An old bridge (no
  `session_id`) leaves the guard inert, and only `PostToolUse` has a fallback: it
  refuses a bridge older than `STALE_S`. `UserPromptSubmit` has no staleness
  backstop *by design* — the bridge refreshes only while an interactive statusline
  renders, so any short bound would swallow legitimate nudges after an idle
  stretch — so on that path a stale or foreign bridge nudges on every prompt. The
  failure is silent: nothing errors, the notice is simply wrong. Refresh, don't
  rely on the degraded path.
- `.claude/state/` gains `hook-surface-log.jsonl`, created on the first event in
  **any** scaffold-enabled repo — bridge or no bridge, since the logger deliberately
  precedes every guard. The setup guide's §5 `.gitignore` line therefore stops being
  optional for repos that adopt `scaffold` without the statusline; §2 now says so.
