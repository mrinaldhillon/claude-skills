# .context/ — agent-written project state

This directory is **working state, not documentation** (that's `docs/`). See ADR 0005.

| File | What | Committed? |
|---|---|---|
| `project-context.md` | Current goal/milestone, gate status, open questions — overwritten at every checkpoint | Yes (by `checkpoint.sh`, non-main branches only) |
| `RESUME.md` | The single next action for a fresh session; re-injected after compaction (`SessionStart` hook) | Yes (same) |
| `MILESTONE_DONE` | Milestone-runner completion sentinel — session writes it, `done_gate` verifies it | No (gitignored, per-run) |
| `REPLAN.md` | Milestone-runner escape valve — session writes it when the goal/decomposition is wrong | No (gitignored, per-run) |

Why a top-level dot-dir: `docs/` is documentation; `.claude/` is config and is **not
agent-writable in headless mode** (verified — ADR 0003/0005); `.claude/state/` is
machine-local volatile script-written state. Agent-written, repo-portable state needs
its own home, and a hidden dot-dir avoids colliding with downstream app layouts.
