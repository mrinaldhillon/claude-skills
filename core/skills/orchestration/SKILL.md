---
name: orchestration
description: >-
  Use at the start of any milestone build, large review, or migration that will
  spawn subagents — the tiered orchestrator-worker model: the strong model
  orchestrates and does the judgment work, tiered Haiku/Sonnet workers do the
  legwork, workers consult main, critics consult no one, and deterministic gates
  (tests, linters, type-checkers, schema/contract validators) outrank every LLM
  judge. Trigger from any task you'll parallelize across subagents. The full
  model behind the cost-aware-delegation skill. Validated against Anthropic's
  published multi-agent guidance (see Grounding).
---

# Orchestration (tiered orchestrator-worker)

The main loop is the orchestrator. Spawn cheaper-tier subagents (Haiku/Sonnet) for
the legwork; keep the judgment on the main loop. This is the full model behind the
`cost-aware-delegation` skill — read that first for the routing table; this skill
adds the fan-out, verification, and parallelism discipline around it.

## Model & effort tiering (tier = f(task stakes), not uniform)

Pick the model by the reasoning the task actually needs — decide it **before**
spawning, per subagent. Three tiers:

- **Haiku — pure-mechanical, high-read, low-reasoning:** web search, page fetch +
  extract (docs/API lookups, symbol/name checks), log/file scraping, status
  polling. A wrong answer here is cheap to catch.
- **Sonnet — moderate legwork / structural analysis (the usual subagent floor):**
  implementing from a near-pseudocode spec; transcribing known values (design
  tokens, config, fixtures — mechanical by definition, the values are given);
  DTO/model structs from a fixed schema; prose → structured-format translation
  where a validator is the gate; fixture authoring; per-module test scaffolding
  from a written spec; mechanical doc edits; **all git/GitHub ops** (commit, push,
  PR, CI-watch, merge-on-green); **absorbing verbose tool output** — build logs,
  CI run output, test dumps — and returning only the verdict.
- **Strong model (the session model) — correctness-critical judgment:**
  architecture and module boundaries; anything touching a core invariant
  (correctness, data integrity, determinism, security/privacy); the exact logic
  of correctness-critical code; schema decisions; selecting or hand-computing a
  golden fixture; **all verification of delegated work**; code review; milestone
  implementation. Write the low-volume/high-criticality piece yourself (e.g. a
  determinism suite's input fixture).

`core`'s own shipped agents sit on this table: `search`, `doc-sync`, and
`config-auditor` are pinned `model: sonnet` (locator and audit legwork);
`code-reviewer` is `model: inherit` (correctness judgment — it rides the
session's strongest model). A project's own agents slot in the same way: pin the
mechanical / high-read ones to the floor, leave the judgment ones on `inherit`.

**Quality is paramount — the cost rule and the quality rule resolve via stakes.**
"Don't waste tokens on mechanical work" applies *only* when the task is genuinely
low-reasoning/high-read AND a wrong answer is cheap. When correctness or output
quality is at stake, tier **up**, not down — in doubt on a quality-critical task,
go up. A too-cheap model that rubber-stamps a verification or botches a coupled
edit is a false economy. Never cost-cut the judgment, verification, or gate paths.

Write specs so subagents **translate, not design**: exact types + pseudocode +
**hand-computed expected test values** as the correctness anchor.

## Workflow fan-out: tier every stage, guard the budget, checkpoint before loss

The Workflow tool's `agent()` calls **inherit the session's strong model unless you
set `opts.model` per stage**. A fan-out that lets mechanical stages inherit it
burns the budget in minutes (a real un-tiered deep-research run spent ~1.95M tokens
across 108 agents and produced no report). Rules:

- **Set `opts.model` on EVERY stage** — search/fetch/extract → `haiku`;
  verify/moderate analysis → `sonnet`; synthesis / final judgment → the strong model.
- **Guard the budget** — scale fleet size and per-task depth to
  `budget.remaining()`; stop fanning out before the cap.
- **Cap fan-out concurrency; never truncate silently** — keep concurrent agents to
  a small width (~5) per workflow or Agent-tool fan-out; fan a larger work-list
  that width and process it N-at-a-time, never wider. `log()` what you dropped.
- **Checkpoint distilled output to a durable file as an explicit step, not a
  hook.** `SubagentStop` does not fire for Workflow-internal agents, and even for
  Agent-tool subagents the payload carries no result text. Checkpoint per landed
  unit, not all at the end; synthesize even if partial. The **orchestrator** does
  the Write — worker file-Writes are best-effort (a real 18-agent fleet: 6 wrote
  to their CWD, 12 wrote nowhere; the payloads survived only in the run journal).
  Carry results in structured returns and treat the run journal as the recovery
  record (`journal.jsonl` in the workflow run's transcript dir —
  `subagents/workflows/wf_*/` under the session's project dir).
- **Journal the fan-out plan before a large launch, not just its output.** Before
  an Agent-tool fan-out past the concurrency width or any multi-wave run, write the
  task list, per-agent assignment, and per-unit done/not-done state to a durable
  scratch file — so an accidental cancel resumes from the journal instead of
  re-running the whole fan-out. This persists the *plan* of the fan-out; the bullet
  above persists its *output*.

## Context hygiene — checkpoint, clear, resume (don't let autocompact decide)

A long orchestration session accretes context that is re-sent on every API call. The
cost that bites is **not dollars** — re-sent history is cache-read, the cheap tier — but
**context rot** (reasoning degrades as the window fills; see Grounding), **window
pressure** (nearing the limit forces a compaction), and **latency** (a bigger window is
a slower call). Spend the *right* context per prompt; don't let it grow unbounded because
it "still fits."

When the window fills, Claude Code **auto-compacts**: it replaces history with a
generated summary, on its own schedule, lossily. Don't let that be your
context-management strategy. The discipline is to **checkpoint durable state to files,
`/clear`, and resume from those files** at a boundary *you* choose (a gate or milestone
close) — so the resume reads from your curated substrate, not an auto-summary you never
reviewed. This is the session-level twin of *checkpoint before loss* above: that rule
saves a worker's output; this one saves the orchestrator's own working context.

Three delivery tiers, by session mode:

- **Proactive nudge (interactive).** A threshold nudge — watch at ~55%, land by ~65% —
  that tells the model to write the resume file and stop for a clean `/clear`. It needs a
  **status-line → file → hook bridge**: no hook event receives context-window usage on
  its stdin, so the status line (the only surface that sees usage) must persist it to a
  state file for a hook to read and act on. Opt-in per-repo machinery, not a core
  primitive.
- **Reactive backstop.** Two hooks bracket a compaction you couldn't prevent:
  `PreCompact` commits durable state before the summary lands (it can't steer the summary
  or run `/clear` — verified), and a `SessionStart(compact|clear)` hook re-injects that
  saved resume file into the fresh window afterward. Together they make an unplanned
  autocompact — or a deliberate `/clear` — resume from your curated substrate, not just
  the auto-summary. Bridge-free (needs no context-window data), unlike the proactive
  nudge.
- **Fresh-session milestone runner (long / unattended).** Run each milestone phase as a
  fresh `claude -p` session so context never accretes across phases; cap per-phase
  compaction with `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`.

Keep the **principle** here; bind the **machinery** in a project. The concrete thresholds,
the state-file path, the resume-file layout, the nudge hook, and the runner are a repo's
opt-in `.context/` substrate (e.g. the `scaffold` plugin's milestone substrate) — `core`
can't ship them because they need a project's own `statusLine` and `settings.json`. Same
split as *Extending this skill*: principle and guards here, concrete bindings in the
companion/substrate.

## Who consults whom — workers vs critics

The **main loop may call `advisor`** (on Fable sessions: the `advisor-plus`
agent — the built-in tool is unsupported there; `cost-aware-delegation` › Verify
with the advisor). Subagents fall into two classes, and neither calls `advisor`:

- **Workers** (fan-out implementers): on a genuine design fork they `SendMessage`
  `main` — never `advisor`. Each consult must carry enough context (the decision,
  options, what was tried), since main doesn't see their transcript. Scope:
  implementation direction; main centralizes design.
- **Critics & locators** (reviewers, auditors, search/locator agents): **terminal —
  they consult no one.** Uncertainty is an *output*: a labeled finding (severity +
  confidence + basis) for main to adjudicate. Put the no-consult line in each
  agent **body** because `advisor` is not gated by `tools:` frontmatter. A critic
  that *needs* to consult is a prompt-construction bug — pack the critic's prompt
  completely instead.

## Verification = independent critics + deterministic gates

Verification is never orchestrator-as-sole-judge. Use **independent reviewer agents
with fresh context**. The strongest check is a **deterministic gate** — your repo's
test suite, a determinism/reproducibility check (same input → byte-equal output),
linters run in strict mode, formatters run as a check, type-checkers, and any
schema/contract/catalog validator. Gates outrank every LLM judge; an auditor that
**independently re-derives** a golden from raw inputs substantiates "hand-computed".
Main backstops its own design with the advisor (`advisor-plus` on Fable).

## Verification economics — size the verify fleet to the stakes

- **Don't re-verify what the finder already proved.** If the finding agent
  *executed* the failing case — ran the test, reproduced the crash — its evidence
  stands. Re-verify when the evidence is reasoning rather than execution, or the
  claim drives a priority decision.
- **Cap adversarial-verify fleets at the criticals** — findings whose being-wrong
  violates a core invariant or corrupts persistent state. Minors ride with the
  single reviewer.
- **Surface fleet size before big launches** — state the agent count and a rough
  token estimate before a large verification pass; a silent 500k-token fleet is an
  unreviewed spend decision.
- **Scope each critic to the surface it audits** — the docs critic runs only when
  the diff touches a docs surface, the config auditor only on steering-layer
  (`.claude/`) diffs; the heaviest per-call agent gets the tightest gate. Critics
  run **once per PR on the full branch diff** — after all the PR's tasks, before
  the PR opens — never per commit and never as an iterative re-review loop:
  fragmentary diffs produce fragmentary findings, and loops burn tokens
  re-adjudicating settled points.

## Parallelism, isolation, and merge discipline

- **Gate fan-out on independent-vs-coupled BEFORE spawning.** Parallelize
  *investigation* freely (search, review, per-file analysis, independent critics).
  For *coupled implementation* — multiple files that must agree on shared decisions
  (types, naming, edge cases) — keep writes **single-threaded: one writer**, with
  other agents adding intelligence *around* it. Parallel writers make conflicting
  implicit choices that degrade coherence. This is a *coherence* argument, distinct
  from `dispatching-parallel-agents`' "don't parallelize agents that would edit the
  same files" — coupled writers corrupt the design even when they never touch the
  same file.
- File-mutating parallel subagents run in **isolated git worktrees**
  (`isolation: worktree`). **Caveat:** a worktree branches from the **default
  branch, not the parent's HEAD** — workers see neither your uncommitted work nor
  each other's. Commit first; single-thread coupled writes.
- Subagents report a **verdict only** (no log dumps); verbose build/CI output stays
  out of the main context.
- **No independent merges.** Main reviews the full diff and runs the gates before
  merging each branch. The synchronous-merge bottleneck (main waits on the slowest
  subagent) is accepted for simplicity.

## Prompt craft is not here — use `superpowers:dispatching-parallel-agents`

How to *write* the dispatch — pack the full context because the agent starts blind
and never inherits your history, give it scope + goal + constraints + expected output
format, then review and integrate what comes back — is
`superpowers:dispatching-parallel-agents`. It says it well; this skill does not
restate it.

What that skill has no notion of, and this one exists for: **model tiering**
(`opts.model` per stage, the Haiku/Sonnet/strong table above), the **budget** guard,
**checkpointing before loss**, **worktree branch-point semantics**, and the
**workers-vs-critics consult rule**. Read both: that one for the prompt, this one for
which model runs it and what it costs.

One Claude-Code specific it doesn't carry: "starts blind" is not absolute — a
**custom subagent still loads CLAUDE.md + memory**; it is your *task-specific*
constraints that must be restated. The sole parent→child channel remains the prompt
string, and only the child's final message returns (see Grounding).

## Gotchas

- **Worktree isolation can switch the MAIN checkout** onto a subagent branch —
  always `git branch --show-current` before merging or cherry-picking.
- **Never switch branches in the shared tree while a read-agent is running** —
  its later re-reads silently return the *new* branch's content. Hold branch
  switches until spawned readers return; `isolation: worktree` helps only when
  the reader targets default-branch state (a worktree branches from the default
  branch, not your HEAD — see above).
- **Before calling a subagent wrong about repo state, check whether HEAD moved.**
  A finding produced pre-commit can be honestly stale rather than hallucinated —
  `git log` for commits newer than the phase that produced the claim, and
  reconcile each phase against the HEAD it ran at.
- **Run the full gate list before the PR**, not just the fast test subset — the
  format *check* and strict lint catch what a dev-loop test run never flags; it's
  the discriminator between a green PR and a red round-trip.
- Delegate the mechanical `gh` flow (push/PR/CI-watch/merge-on-green) to a Sonnet
  subagent; keep the **merge decision** on the main loop (see `git-workflow`).

## Extending this skill (bind, don't fork)

Portable, project-neutral discipline. To specialize it for a repo, **add a companion — never
copy this into a project `orchestration` skill.** Plugin skills are namespaced
(`core:orchestration`) and can't be shadowed by a project skill: a same-named copy *coexists*
ambiguously and drifts behind core (there is no skill inheritance).

- **Companion** `orchestration-<yourrepo>` (a distinct name) fills this skill's generic slots
  with the repo's concrete bindings — the **deterministic-gate roster** (that repo's tests /
  linters / validators), the **agent→tier map** (which of its agents run Haiku / Sonnet /
  strong), and **task→model tier examples**. Name it in the repo's `CLAUDE.md` so it co-fires
  with this skill.
- **Guards stay here.** Per-stage `opts.model`, the fan-out cap, and "judgment / verification /
  gates stay on the strong model" are budget-critical — keep them here and mirror the caps into
  `CLAUDE.md`. A companion carries only *lose-able* reference; if it fails to co-fire you lose
  examples, never a guard.

## Grounding (primary sources)

- **Orchestrator-worker fits complex tasks whose subtasks can't be predicted up
  front** — not a default for all decomposable work; it trades latency + cost for
  performance. (anthropic.com/research/building-effective-agents)
- **Multi-agent uses ~15× the tokens of single-agent chat** — justified only when
  task value is high. (anthropic.com/engineering/multi-agent-research-system)
- **Context is finite, with diminishing returns (context rot)** — spend the
  *right* context per prompt.
  (anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- **Subagents run in isolated context** — only the final message returns; the sole
  parent→child channel is the prompt string. (code.claude.com/docs/en/sub-agents)
- **Model tiering is first-class & per-subagent** (`model` frontmatter).
  (code.claude.com/docs/en/sub-agents)
- **Worker file-Writes are best-effort; the run journal is the record** — a
  2026-07-13 18-agent fleet: 6 checkpoint Writes landed in the wrong dir, 12
  nowhere; every payload was recovered from the run's `journal.jsonl`
  (recorded in the maintainer's audit memory; journal path/schema re-verified on
  disk 2026-07-16).
- **Verification uses independent critics**, not orchestrator-as-judge.
  (anthropic.com/research/building-effective-agents — Writer/Reviewer)
- **Single-thread coupled writes.** (cognition.com/blog/dont-build-multi-agents)
- **Workflow-tool mechanics are documented tool parameters** — `opts.model` per
  stage, the `budget` object, `isolation: 'worktree'`. (Claude Code Workflow tool
  interface.)
- **No hook event receives context-window usage on stdin** (verified v2.1.212) — the
  status line is the only surface carrying context-usage data, so a proactive threshold
  nudge must bridge status-line → state file → hook. `PreCompact` stdin carries only
  `trigger` + `custom_instructions` and cannot steer the compaction summary; the
  documented re-inject-after-compaction channel is a `SessionStart(compact)` hook.
  (code.claude.com/docs/en/hooks)

Re-validate with a `claude-code-guide` lookup if the docs evolve.
