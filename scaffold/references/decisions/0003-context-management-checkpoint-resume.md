# 3. Context management by checkpoint-resume, not compaction

- **Status:** Accepted
- **Date:** 2026-07-08
- **Supersedes:** —
- **Superseded by:** [0004](0004-context-managed-milestone-loop.md) — runner-mechanism
  clause of §5 only; [0005](0005-agent-state-in-context-dir.md) — location clauses
  (§4 resume pointer, Consequences `docs/` placement) only;
  [0007](0007-remove-stop-checkpoint-trigger.md) — checkpoint-trigger clause of §3 and
  the Stop/`/clear` Consequences bullets only;
  [0008](0008-graduate-context-nudge-into-plugin.md) — the project-local placement of
  §2 only; the rest of this ADR remains in force

## Context

Long sessions and milestone builds outrun the context window. Claude Code's built-in
remedy is auto-compaction — a lossy summary of the conversation near ~83% usage. Summaries
drop load-bearing detail (the exact next step, gate status, which file was mid-edit), and
the timing is not ours to choose. We want durable state to survive a cleared or compacted
session with no loss, and long milestones to run hands-off.

Constraints, verified against Claude Code 2.1.204 and current docs:
- Hook payloads carry **no** token counts; the **status line** is the only place live
  context usage (`context_window.used_percentage`) is exposed.
- A hook cannot run `/compact` or `/clear`, and cannot trigger compaction; it may only run
  scripts and inject text (`UserPromptSubmit` stdout is added to context).
- There is **no** auto-compaction *percentage* override env var (an earlier draft of this
  work assumed `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`; it does not exist). The only knobs are
  `autoCompactEnabled` and `DISABLE_AUTO_COMPACT=1`.
  *(Corrected by ADR 0004: `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` and
  `CLAUDE_CODE_AUTO_COMPACT_WINDOW` are documented and present in the CLI 2.1.204
  binary — this bullet's verification was wrong for the version it cited.)*
- Compaction summarizes only conversation history; files re-read at startup (CLAUDE.md,
  memory, docs) survive it intact — so durable state belongs in files.

## Decision

Durable state lives in **files**; the session is disposable. The mechanism:

1. **Status-line bridge** (`.claude/statusline.sh`) publishes usage to
   `.claude/state/context-usage.json` — the only way a hook can observe it.
2. **Context-nudge hook** (`.claude/hooks/context-nudge.sh`, `UserPromptSubmit`) injects a
   checkpoint nudge at 55% (watch) and 65% (land), both below the default auto-compact
   trigger, so the agent checkpoints and the user clears before a summary ever fires.
   *(Placement evolved by ADR 0008, 2026-07-22: the hook ships in the scaffold plugin's
   `hooks.json`, dual-mode per ADR 0004, with a session-identity guard; the statusline
   bridge stays project-local. The thresholds and mechanism stand.)*
3. **Checkpoint script** (`.claude/hooks/checkpoint.sh`, on `PreCompact` and `Stop`) commits
   the durable files — `docs/project-context.md`, `docs/decisions/`, `docs/RESUME.md`
   — but **only on non-main branches** (ADR 0002: PR-into-`main` is by discipline), committing
   by pathspec so unrelated staged files are never swept in, and only over paths with a
   staged change (an empty `docs/decisions/` must not abort the commit).
   *(Superseded by ADR 0007, 2026-07-21: the `Stop` trigger is removed — it fired after
   every turn and landed a commit per turn, interleaving automation commits with
   in-flight work. `PreCompact`, the milestone runner's direct calls, and a deliberate
   land-step commit are the triggers of record.)*
4. **Resume pointer** is the in-repo, committed `docs/RESUME.md` — one canonical location,
   superseding both the earlier per-user memory-dir `resume.md` and an initial `.claude/state/`
   placement (see Consequences). `SessionStart(compact)` re-injects it after any compaction
   that does fire. *(Location evolved by ADR 0005: agent-written state now lives in
   `.context/` — docs/ is documentation only.)*
5. **Milestone runner** (`scripts/milestone-runner.sh`) runs each phase as a fresh `claude -p`
   session that resumes from those files — clear-and-resume, not compact; it refuses to run on
   `main`/detached HEAD. *(Mechanism evolved by ADR 0004: dynamic chunks behind deterministic
   gates replace the text phases-file; the clear-and-resume decision stands.)*

Auto-compaction stays enabled as a backstop: if a nudge is missed, `PreCompact` still
checkpoints before the summary and `SessionStart` restores the pointer after.

## Consequences

- Working state survives `/clear`, an unexpected compaction, and a machine change, because it
  is committed to the branch. *(Qualified by ADR 0007: `/clear` fires no `PreCompact`, so on
  that path "committed" holds only once the land step's deliberate commit runs; on-disk
  survival is unaffected either way.)*
- The system pays off on long milestones; on short chats the always-loaded overhead (the
  CLAUDE.md protocol section, the per-prompt hook) is pure cost. Measuring the delta with
  `/usage` is a documented follow-up, not part of this change.
- Checkpoints never land on `main`; a milestone must run on a branch.
- ~~The `Stop` checkpoint fires at every turn end~~ *(removed by ADR 0007, 2026-07-21)*: the per-turn
  trigger's "no-op unless a durable file changed" guard was not enough — any turn that
  touched a durable file landed an automation commit mid-flight. Checkpoint commits now
  land only at `PreCompact` and at the runner's iteration boundaries. Trade-off: durable
  edits sit uncommitted on disk between those points, so a `docs/project-context.md`
  change meant to ship together with code should be staged and committed deliberately
  rather than left for the hook.
- `jq` is now a soft dependency (already used by `validate-config`); the status line and nudge
  degrade to a no-op without it.
- **The resume pointer lives in `docs/`, not `.claude/state/`, because `.claude/` is not
  agent-writable in headless mode.** A live end-to-end run of the milestone runner revealed
  that Claude Code guards the `.claude/` tree: the Write/Edit tools are *denied* there under
  `--permission-mode acceptEdits` in a `claude -p` session, even though the same headless
  session wrote `docs/` files fine (verified from the resulting checkpoint commits). An initial
  `.claude/state/RESUME.md` placement was therefore unwritable by exactly the hands-off phase
  it exists to serve; moving it to `docs/RESUME.md` also reflects the correct split — `.claude/`
  is agent *config*, the resume pointer is project *state*.
- **Corollary (known, not addressed here):** because a headless phase cannot edit `.claude/`,
  the runner cannot hands-off *build* a project whose product IS `.claude/` content — such as
  this template itself. It targets downstream projects whose code lives in `src/`; building the
  steering layer stays an interactive task.
