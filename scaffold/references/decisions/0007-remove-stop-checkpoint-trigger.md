# 7. Remove the checkpoint hook's per-turn Stop trigger

- **Status:** Accepted
- **Date:** 2026-07-21
- **Supersedes:** [0003](0003-context-management-checkpoint-resume.md) — checkpoint-trigger
  clause of Decision §3 and the Stop/`/clear` Consequences bullets only;
  [0004](0004-context-managed-milestone-loop.md) — the "belt-and-suspenders" correction
  clause (b) of Consequences only
- **Superseded by:** —

## Context

`checkpoint.sh` was wired to both `Stop` and `PreCompact` (ADR 0003 §3). `Stop` fires
after every turn, so any turn that touched a durable file landed a `chore(checkpoint)`
commit mid-flight — automation commits interleaved with in-flight work, files yanked
out from under an edit in progress (observed live in handled-next). A 900s cooldown
(unreleased 0.5.4) only thinned the noise; commits still landed mid-session.

The trigger's protective value was thin: the durable files live in the working tree,
so they survive `/clear` and compaction on disk regardless of any commit —
`resume-inject.sh` reads `RESUME.md` back from disk, not from git history. The commit
matters only for machine-change survival and branch history.

## Decision

Drop the `Stop` entry from `scaffold/hooks/hooks.json`. Triggers of record:

1. **`PreCompact`** — the context-loss guard; commits before an autocompact summary.
2. **`milestone-runner.sh`'s direct `checkpoint.sh` calls** at each iteration boundary
   and at done — the primary (and only) trigger inside a headless loop.
3. **A deliberate commit at interactive land time** — `/clear` fires no `PreCompact`,
   so the ~65% land step now includes committing the durable files before `/clear`
   (never on `main`; ADR 0002).

Scaffold bumps to 0.6.0 (plugin updates are version-gated).

## Consequences

- No automation commit ever lands mid-turn; checkpoint commits appear only at
  compaction, runner boundaries, or deliberate invocation.
- ADR 0003's unqualified "working state survives `/clear` … because it is committed to
  the branch" now holds on the `/clear` path only via the land-step commit; on-disk
  survival is unaffected.
- On a partial add or failed commit, staged durable files can linger until the next
  trigger — interactively that can be far off; the deliberate land commit is the
  reliable path.
