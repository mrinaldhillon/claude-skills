# 4. Context-managed milestone loop: dynamic chunks behind deterministic gates

- **Status:** Accepted
- **Date:** 2026-07-08
- **Supersedes:** the runner *mechanism* in 0003 §5 (the checkpoint-resume decision itself stands)
- **Superseded by:** [0005](0005-agent-state-in-context-dir.md) — sentinel/checkpoint
  path locations (§1) only; [0006](0006-milestone-permission-profiles.md) extends the
  loop with permission profiles (strict default unchanged); the rest of this ADR
  remains in force

## Context

ADR 0003 settled checkpoint-resume over compaction and shipped a minimal milestone
runner: a text phases-file, one fresh `claude -p` session per phase, no verification, no
resume. Two efforts to grow it forced this decision:

1. **A 790-line manifest-driven driver design** (7 files: per-phase model/tools/turn-caps,
   budget summing, retry-once, progress registry) was adversarially stress-tested before
   building: 5 independent investigations ground-truthed its claims against the installed
   CLI (2.1.204), the docs, and this repo. Verdict: the *architecture* held; the *code
   layer* had nine confirmed bugs (vacuous tests, a `DRY_RUN` that poisoned progress,
   budget accounting that recorded $0 for failed attempts) and one inverted premise — a
   disallowed tool does **not** hang a headless session; it is **denied silently in
   seconds**, `is_error:false`, exit 0, recorded only in a `permission_denials` array the
   design never read. The full design is parked with the bug list at
   `docs/meta/milestone-driver-plan.md`; roadmap §0 carries the resurrection criterion.
2. **The requirement was restated as a loop**: run a long milestone; at a context-usage
   threshold, checkpoint at a safe logical point; clear (preferred) or compact; resume;
   iterate to completion. Verified constraints that shape any solution: the model cannot
   run `/clear` or `/compact` on itself (commands are user-initiated; hooks may only
   inject guidance); `Stop` hooks **do** fire in `-p` mode (0003-era comments said
   otherwise); and — correcting 0003:21 — auto-compaction **is** tunable: both
   `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` and `CLAUDE_CODE_AUTO_COMPACT_WINDOW` are documented
   and present in the installed 2.1.204 binary (verified by string search; the earlier
   "no override env var exists" verification was wrong for the very version it cited).

## Decision

We will run long milestones as **four cooperating layers over the ADR 0003 checkpoint
files**, and we keep **clear over compact** as the primary boundary — a fresh session
resuming from deliberate, auditable files beats a lossy, unaudited summary whose drift
compounds across iterations.

1. **Outer loop (clear as a process boundary).** `scripts/milestone-runner.sh`, evolved
   in place, reads a JSON config (`milestone`, `goal`, `model`, `allowed_tools`,
   `max_budget_usd_per_iteration`, `max_iterations`, `iteration_gate`, `done_gate`) and
   respawns fresh `claude -p` sessions — one **coherent chunk chosen by the session** per
   iteration, not a pre-decomposed phase list. Deterministic shell gates decide progress:
   `iteration_gate` (tree-health invariant) after every chunk, `done_gate` when the
   session writes `docs/MILESTONE_DONE`. A completion claim whose gate fails stops the
   run (false-done). **No retry** — a failed gate means the checkpoint no longer
   describes reality; stop and let a human triage. A session that discovers the goal is
   wrong writes `docs/REPLAN.md` and the runner exits distinctly rather than completing
   a run shaped like an obsolete plan. *(Sentinel and checkpoint paths moved from
   `docs/` to `.context/` by ADR 0005.)*
2. **Hardening from the stress-test findings.** `permission_denials` in the response
   JSON fails the iteration (silent denials are the worst unattended failure mode);
   cost is parsed on success *and* failure paths but only ever *reported* — the CLI's
   own `--max-budget-usd` per iteration is the cap (no homegrown budget accounting);
   a zero-cost flag probe at every start catches CLI drift (a `--help` grep
   false-negatives on hidden-but-working flags); an atomic `mkdir` lock serializes runs;
   a pure-bash watchdog bounds a stalled session (stock macOS has neither `timeout` nor
   `gtimeout`); and the runner + config sha256s are pinned per run — a session that
   edits its own verifier or contract aborts the run (trust boundary).
3. **In-session tiering (context sharding).** The spawned session runs the strong model
   — it *is* the orchestrator — and its prompt binds the `orchestration` skill: legwork
   goes to tiered subagents (`search` to locate, Sonnet workers from precise specs);
   judgment and verification stay in-session; only distilled results enter its context,
   so chunks stay large without nearing the window.
4. **Usage-triggered checkpointing at a safe logical point.** The `context-nudge` hook
   is dual-mode: the `UserPromptSubmit` path is unchanged, and a new `PostToolUse` path
   injects the same nudge **mid-turn** via `hookSpecificOutput.additionalContext` (plain
   stdout is debug-log-only for that event), with a 300s in-band cooldown and a 120s
   bridge-staleness guard so a leftover interactive percentage never nudges a headless
   session (the statusline — the only live usage source — does not render under `-p`).
5. **Tuned compaction as the backstop, not the boundary.** The runner exports
   `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` (default 70) to spawned sessions: if a chunk
   overruns anyway, compaction fires *above* the nudge thresholds and therefore over a
   fresh checkpoint, with `PreCompact` committing and `SessionStart(compact)` re-injecting
   `docs/RESUME.md` (both already wired). The summary's lossiness is tolerable precisely
   because the files, not the summary, carry the truth.

## Consequences

- **Corrections to ADR 0003 (recorded here, annotated there):** (a) 0003:21 — the
  auto-compact override env vars exist on 2.1.204; (b) `Stop` hooks fire in `-p` mode,
  so the runner's explicit `checkpoint.sh` call is belt-and-suspenders, not a workaround.
- **The honest operating envelope:** mechanical, well-specified milestones with intrinsic
  gates (build/test, not existence probes), on a branch, a human auditing the diff after.
  The loop's promise is *stops early and safely, resumes cheaply* — never *finishes
  discovery-heavy work*. The REPLAN valve is the escape hatch, not a replanner.
- **Residual trust-boundary risk:** the session and its gates share one writable
  worktree. The sha pin protects the runner and config; it cannot stop a session from
  gaming a weak gate's *target* (e.g. touching a file an existence probe checks). The
  mitigation is gate quality — prefer gates a goal-seeking model cannot satisfy without
  doing the work.
- **Restart safety is structural:** state lives in the checkpoint files; a rerun resumes
  iterating with no phase registry to corrupt. An already-done milestone re-verifies its
  `done_gate` and exits idempotently.
- If exact usage-percentage triggering *inside* headless sessions ever becomes a hard
  requirement, the supported escalation is an Agent-SDK driver (per-turn `usage` is a
  stable API field there); parsing the session transcript JSONL is explicitly unstable
  and rejected.
- The parked 7-file driver returns only on the roadmap §0 criterion: a downstream
  project running 10+ phase unattended milestones and demonstrably outgrowing this
  single-file loop.
