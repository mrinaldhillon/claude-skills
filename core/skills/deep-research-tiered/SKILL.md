---
name: deep-research-tiered
description: >-
  Use to run a deep, multi-source research report efficiently — the tiered,
  budget-guarded, checkpointed version of a fan-out research workflow. Trigger
  whenever you would reach for the bundled `deep-research` harness, or any time you
  fan out web search → fetch → verify → synthesize across many subagents. Encodes
  the fix for this repo's ~1.95M-token burn: per-stage model pins, a budget guard,
  per-phase checkpoint-to-memory, and synthesis that runs even when partial.
---

# Deep research, tiered and budget-safe

This is the **corrected** way to run fan-out research. It exists because the bundled
`deep-research` workflow, run once with no per-stage model pins, **spent ~1.95M
tokens across 108 subagents and hit the session cap twice — producing no report**.
Every rule below is the direct countermeasure to a failure that actually happened.
(Provenance: recorded in the claude-code-starter template repo at
`docs/meta/orchestration-research.md` §7 and its discipline Rule 10 — this skill
installs user-level, so from any other project treat that path as provenance, not
a resolvable link; the key facts are inlined here.)

Use it for: a deep, multi-source, fact-checked report where breadth (many independent
search angles + adversarial verification) earns the multi-agent token premium. Do
**not** reach for it for a single-source lookup or a question one good search answers —
multi-agent costs ~15× single-agent chat (research §1); spend that only on high-value,
unpredictable-decomposition tasks.

## The five rules (each fixes a failure from the burned run)

### 1. Pin `opts.model` on EVERY stage — never inherit the session default
The burn's root cause: the workflow's default model was Opus-1M and the `agent()` calls
set no `model:`, so Scope, all Search agents, and ~18 Fetch/extract agents inherited
Opus-1M and poured full web pages into a 1M context. Tier by stakes (Rule 10):

| Stage | Work | Model |
|---|---|---|
| Scope | decompose the question into search angles | `haiku` |
| Search | run each angle's web search | `haiku` |
| Fetch / extract | pull pages, extract falsifiable claims | `haiku` |
| Verify | adversarial multi-vote grading of each claim | `sonnet` |
| Synthesize | merge, rank by confidence, write the cited report | `opus` |

Pure read/extract is Haiku; structured judgment (verify) is Sonnet; the final synthesis
— the one correctness-critical, low-volume step — is Opus. **An unset stage silently
runs on the strong default; that is the bug this skill exists to prevent.**

> **"Verify" here means research-claim grading** — does a fetched source support the
> claim? That is Sonnet-tier per the `orchestration` skill's fan-out tiering. It is a
> *different task* from CLAUDE.md's **code-correctness verification** (the correctness
> gate, code review), which stays **Opus**. Don't conflate the two senses.

### 2. Guard the budget; cap fan-out; never truncate silently
The Workflow tool exposes a `budget` object (`budget.total` / `spent()` /
`remaining()`). Scale fleet size and per-task depth to what remains, and stop fanning
out before the cap — a fan-out that runs to the cap leaves the verifier abstaining and
synthesis unreached. `log()` whatever you drop so truncation is visible, not silent.

### 3. Checkpoint each phase to durable memory BEFORE synthesis
The run was killed *during* Synthesize, the last and only unpersisted phase, so it
produced nothing despite 25 graded claims (14 confirmed) held only in the run's volatile
state and never checkpointed. **Write the distilled
payload (verified claims + sources + confidence) to a memory file as an explicit step
after Verify, before Synthesize.** `SubagentStop` does **not** fire for
Workflow-internal agents, so this cannot be a hook — it is a step in the script (or the
orchestrator's job). Checkpoint per landed unit, not at the end.

**The orchestrator does the Write — never trust worker Writes as the checkpoint
mechanism.** Worker file-Writes are best-effort: in a real 18-agent fleet told to Write
checkpoints to an absolute path, 6 wrote to their CWD (polluting the repo) and 12 wrote
nowhere. Carry the payload in each stage's **structured return** (`schema`) and have the
orchestrator persist the returned object. If a run dies anyway, every agent's actual
return survives in the run journal — `journal.jsonl` in the workflow run's transcript
dir (`subagents/workflows/wf_*/` under the session's project dir) — recover with
`jq 'select(.type=="result") | .result'` instead of re-running the fleet.

### 4. Synthesis must run even if partial
If the budget is nearly spent or verification is incomplete, **still synthesize what
exists** and label it partial. A partial cited report beats a dead run with the
findings stranded in `/tmp`. Read the checkpoint from rule 3 and write the report from
it; the run's whole loss was a synthesis that never started.

### 5. Single-writer for the report
The final report is a coupled artifact — one writer (the synthesis stage) composes it;
do not fan out parallel report-section writers, which make conflicting implicit choices
that degrade coherence (research §2). Parallelize *investigation* (search, fetch,
verify) freely; serialize the *write*.

## Workflow agents start blind — specify everything upfront
Workflow-internal `agent()` stages are isolated: no inherited history, **and no
back-channel to consult the main loop mid-run** (unlike addressable Agent-tool
subagents, which can `SendMessage` main — the `orchestration` skill's *Who consults whom*
rule applies to those *worker* subagents, not to workflow stages). Pack everything each
stage needs into its prompt — the search angle, the schema, the exact extraction /
output format. A stage that needs a decision it wasn't given will **guess, not ask**.
So the cheapest and safest run is one where no stage ever *needs* to consult: settle the
decomposition, the claim format, and the verdict rubric upfront, and routing-to-main
never enters the picture.

## Honesty rules for the report (carry into synthesis)
- **Every claim carries provenance** — its verify vote, its source, and a confidence
  tag. Label killed/abstained claims as such; an abstention (verifier hit the cap) is
  **unverified, not false**.
- **Zero invented metrics.** A number with no surviving source is dropped, not
  laundered. The burned run hallucinated a benchmark figure and a source ID — both were
  caught only on re-verify. If a figure can't be traced to a fetched source, cut it.
- **Re-verify the load-bearing abstentions** with a small, targeted second pass (the
  "Track A" pattern: a few Sonnet graders on just the high-signal unverified claims)
  rather than re-running the whole fan-out.
- **Tool-existence claims need execution, not search.** A web fleet can validate a
  *name* and still miss that the command doesn't exist (a real fleet confirmed a
  skill's name while the `xcrun` subcommand it hung on didn't exist at all — only
  running the binary caught it). For claims about installed tools, CLIs, or local
  APIs, give at least one verifier Bash and have it run the thing (`--version`,
  `--help`). And read the votes: discard degenerate verdicts (a one-word rationale
  like "test"); no single uncorroborated vote is load-bearing.

## Reference workflow snippet (the per-stage pins made concrete)
A schematic of the corrected harness — pins on every stage, a budget guard, a
checkpoint before synthesis, and a synthesis that always runs:

This is a **Workflow-tool script**: `export const meta` + top-level `await`/`return` is
the shape the tool runs (it wraps the body in an async context). `agent`, `parallel`,
`log`, `args`, `budget`, and `opts.{model,phase,schema}` are Workflow primitives;
`ANGLES`/`CLAIMS`/`VERDICT`/`CHECKPOINT`/`REPORT` are your JSON schemas. Schematic —
adapt before use.

```js
export const meta = {
  name: 'deep-research-tiered',
  description: 'Tiered, budget-guarded, checkpointed deep research',
  phases: [
    { title: 'Scope',      model: 'haiku'  },
    { title: 'Search',     model: 'haiku'  },   // search + fetch + extract = one Haiku stage
    { title: 'Verify',     model: 'sonnet' },
    { title: 'Synthesize', model: 'opus'   },
  ],
}

// 1. Scope — cheap decomposition. A schema'd agent() returns an object → read .angles.
const scope = await agent(`Decompose into 5 search angles: ${args}`,
  { phase: 'Scope', model: 'haiku', schema: ANGLES })

// 2. Search + fetch + extract — Haiku fan-out. Cheap, so the budget guard sits on
//    Verify (the costly 3-vote stage), not here.
const claims = (await parallel(scope.angles.map(a => () =>
  agent(`Search, fetch, and extract falsifiable claims for: ${a}`,
    { phase: 'Search', model: 'haiku', schema: CLAIMS }))))
  .filter(Boolean).flatMap(r => r.claims)

// 3. Verify — Sonnet, 3-vote adversarial. Abstentions are tracked separately and are
//    NEVER folded into "refuted" — that masking is exactly what killed the original run.
const graded = []
for (const c of claims) {
  if (budget.total && budget.remaining() < 80_000) {              // null budget.total → no guard
    log(`stopping verify; ${claims.length - graded.length} claims ungraded`); break
  }
  const votes = (await parallel([0, 1, 2].map(() => () =>
    agent(`Adversarially verify: ${c.text}. Return verdict ∈ {confirmed, refuted, abstained}; abstain ONLY if genuinely undecidable.`,
      { phase: 'Verify', model: 'sonnet', schema: VERDICT }))))
    .map(v => v?.verdict ?? 'abstained')                          // dead/null vote = abstained, NOT refuted
  const confirmed = votes.filter(v => v === 'confirmed').length
  const refuted   = votes.filter(v => v === 'refuted').length
  const status = confirmed >= 2 ? 'confirmed' : refuted >= 2 ? 'refuted' : 'unverified'
  graded.push({ ...c, status, confirmed, refuted, abstained: 3 - confirmed - refuted })
}

// 4. CHECKPOINT — REQUIRED, before synthesis: the step whose absence lost the last run.
//    A Workflow script has no filesystem access, and worker Writes are BEST-EFFORT
//    (real fleet: 6/18 wrote to their CWD, 12 wrote nowhere) — so prefer splitting the
//    run: this workflow RETURNS `graded`, the orchestrator Writes the checkpoint, and
//    synthesis runs as a second call taking it as args. Checkpointing in-run (below):
//    the persist agent must READ THE FILE BACK and return {path, bytes}; treat a
//    missing readback as unpersisted. Either way the run journal (journal.jsonl in
//    the run's transcript dir, subagents/workflows/wf_*/) holds every return.
const ck = await agent(
  `Write this payload verbatim to <absolute checkpoint path>, then read the file
   back and return {path, bytes: <byte count read back>}: ${JSON.stringify({ graded })}`,
  { phase: 'Verify', model: 'haiku', schema: CHECKPOINT })
if (!ck?.bytes) log('checkpoint unverified — recovery will need the run journal')

// 5. Synthesize — Opus, single writer; runs even when `graded` is partial.
return await agent(
  `Write a cited report from these graded claims. Tag each with its status
   (confirmed / refuted / unverified), source, and confidence; treat abstentions as
   "unverified, not false"; invent no metrics; note if coverage is partial.
   ${JSON.stringify(graded)}`,
  { phase: 'Synthesize', model: 'opus', schema: REPORT })
```

## Grounding
All `docs/meta/orchestration-research.md` citations below resolve only inside the
claude-code-starter template repo (this skill installs user-level) — elsewhere they
are provenance pointers, and the load-bearing figures are already inlined above.
- The failure benchmark and root cause: `docs/meta/orchestration-research.md` §7;
  the template maintainer memory (`deep-research-token-burn-learning`).
- The tiering mandate: the template's discipline **Rule 10**; the `orchestration`
  skill › *Workflow fan-out: tier every stage, guard the budget, checkpoint before
  loss* (a per-project skill seeded from the template).
- The ~15× premium, context-rot, single-writer, and independent-critic claims:
  `docs/meta/orchestration-research.md` §§1–3, 5 (each with its primary source).
- The worker-Write failure counts (6/18 to CWD, 12/18 nowhere) and the
  `journal.jsonl` recovery recipe: the 2026-07-13 handled-next audit fleets
  (that repo's memory: `multi-agent-audit-lessons`); journal path and schema
  re-verified on disk 2026-07-16.
