# 5. Agent-written state lives in .context/, not docs/

- **Summary:** Agent-written project state (`project-context.md`, `RESUME.md`, milestone sentinels) lives in `.context/`, not `docs/` or `.claude/`.
- **Status:** Accepted
- **Date:** <fill on adoption>
- **Supersedes:** the *location* clauses of 0003 §4 and 0004 §1 (both mechanisms stand)
- **Superseded by:** —

## Context

`docs/` had accumulated three different kinds of files: documentation (ADRs,
architecture, design notes — human-authored, read-mostly), durable working state
(`project-context.md`, `RESUME.md` — robot-overwritten at every checkpoint, committed),
and ephemeral milestone-run sentinels (`MILESTONE_DONE`, `REPLAN.md` — per-run scratch,
never committed). The state files were in `docs/` for a historical reason, not a
taxonomic one: ADR 0003 first placed the resume pointer in `.claude/state/` and
discovered headless sessions are write-denied under all of `.claude/`; `docs/` was the
verified-writable fallback.

The location question is bounded by one hard constraint and one hygiene constraint:
agent-written state must be **outside `.claude/`** (the headless write guard), and the
steering layer should not claim a **visible** top-level directory of its own
(collision- and clutter-prone — many apps have their own `state/`).

Verified before deciding (live probe, CLI 2.1.204, empty scratch repo, headless
`acceptEdits`): a session **can** Write into a top-level dot-directory (`.context/probe.txt`
created) while the same session's `.claude/state/probe.txt` write was denied — the guard
is `.claude/`-specific, not dot-dir-general.

## Decision

We will keep agent-written project state in a top-level **`.context/`** directory:

- `.context/project-context.md` and `.context/RESUME.md` — durable, committed by
  `checkpoint.sh` (pathspec updated; `docs/decisions/` remains in the pathspec — ADRs
  are documentation *of record* and stay in `docs/`).
- `.context/MILESTONE_DONE` and `.context/REPLAN.md` — the milestone runner's
  ephemeral sentinels, gitignored.
- `.context/README.md` documents the directory's contract.

The resulting taxonomy: `docs/` = documentation only · `.context/` = agent-written
project state · `.claude/` = steering config (agent-write-guarded) · `.claude/state/` =
machine-local volatile, script-written, gitignored.

## Consequences

- This is the resume pointer's third home (`.claude/state/` → `docs/` → `.context/`);
  each move is annotated in the superseded ADR so the trail stays legible. The cost of
  the move was a ~15-file mechanical path sweep, all offline-test-covered.
- A committed hidden directory is less discoverable by casual browsing; discoverability
  is carried by the system itself (`SessionStart(compact)` injects `RESUME.md`; CLAUDE.md
  § Context & checkpoint protocol names the paths).
- The clean split holds from the start; nothing in `docs/` is robot-overwritten.
- The `.claude/`-guard fact is now double-verified (ADR 0003's live run; this ADR's
  targeted probe) — future relocations should re-run the probe rather than assume.
