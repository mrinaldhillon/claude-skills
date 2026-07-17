---
name: cost-aware-delegation
description: Use when planning or executing any multi-step task to decide which model does what. Routes mechanical, low-judgment work (boilerplate, transcription, config, docs, repetitive edits, and all git/GitHub ops like commit/push/PR/CI-watching) to a cheaper Sonnet 5 subagent, keeps judgment-heavy work on the strong model, and verifies delegated output. Quality is paramount; tokens are not wasted on mechanical workflows.
---

# Cost-aware delegation

**Quality is paramount — never trade correctness for cost.** But do not spend
expensive strong-model tokens on mechanical work a cheaper model does just as well.

## Routing rule

Before starting a chunk of work, classify it.

**Pure-mechanical, high-read, low-reasoning → Haiku** (`model: "haiku"`) — a wrong
answer here is cheap to catch:
- Web search, page fetch + extract, log/file scraping, status polling

**Mechanical → delegate to a Sonnet 5 subagent** (`Agent` tool, `model: "sonnet"`):
- Boilerplate / scaffolding; transcribing known values (design tokens, fixtures, enums)
- Codable/DTO/model structs from a fixed schema; getters/adapters
- Config files — `.gitignore`, lint/format configs, CI YAML, Dockerfiles
- Docs, comments, README edits from a clear spec
- Repetitive edits across many files following one established pattern
- **Git / GitHub ops: commits, pushes, opening/updating PRs, watching CI, release
  notes, changelogs** — route these to the cheap model
- Mechanical search/collection where the answer just needs gathering

**Judgment-heavy → keep on the strong model** (main thread or a strong subagent):
- Architecture, data-model and API design, algorithm choice
- Anything touching an invariant, concurrency, a security boundary, or
  correctness-critical logic
- Ambiguous requirements, trade-off calls, debugging non-obvious failures
- Deciding whether delegated work is actually correct

When unsure, lean to quality: do the thinking on the strong model, hand off only the typing.

## Turn count beats token price — Sonnet is the floor

> **Adopted from `superpowers:subagent-driven-development` § Model Selection** — the
> insight, the 2–3× figure, and the mid-tier-floor rule are theirs, not this skill's.
> Cite it, don't re-derive it. This section exists because that guidance fires only
> *inside* subagent-driven-development, while this skill is the always-on policy.

Per-token price is not per-task cost. **Wall-clock and context cost scale with how many
turns a subagent takes**, and the cheapest tier routinely takes 2–3× the turns on
multi-step work — a Haiku that flails through six turns costs more than a Sonnet that
lands in two, and burns your context re-reading its own mistakes. So:

- **Sonnet is the subagent floor** for anything multi-step — reviewers, and implementers
  working from *prose* rather than transcription-ready text.
- **Drop to Haiku only when the task is genuinely single-pass**: the values are already
  given and the work is transcription, lookup, scraping, or polling.

The Haiku row above is a floor exception, not the default. Tiering down past Sonnet on
work that needs iteration is a false economy in the same way rubber-stamped verification
is.

**This does not contradict the Haiku pins in `orchestration` and `deep-research-tiered`.**
Those stages — search, page fetch + extract, log scraping, status polling — are
single-pass *by construction*: one page in, one extraction out, no iteration to
multiply. They are the floor exception this section describes, not multi-step work.
The floor binds where a subagent must *loop* to converge.

## How to delegate well

1. Give the cheap subagent a **precise, self-contained spec** — exact file paths, the
   exact type/API contract to code against, and "do not touch anything else." Cheap
   models integrate cleanly only when the contract is fixed for them.
2. Run independent chunks **in parallel** on non-overlapping files.
3. **Verify every delegated result yourself** — read the files, run the build/tests.
   Never ship subagent output unread. If a subagent dies on a transient API error, do
   that piece yourself rather than block.

## Workflow fan-outs — pin the model on EVERY stage

The Workflow tool's `agent()` calls **inherit the session's strong model unless
`opts.model` is set per stage** — an unset mechanical stage silently burns the budget
(a documented un-tiered deep-research run spent ~1.95M tokens across 108 agents and
produced no report). Rules:

1. **Set `opts.model` on every `agent()` stage.** Search/fetch/extract → `haiku`;
   verify/moderate analysis → `sonnet`; synthesis and final judgment → the strong model.
2. **Guard the budget.** Scale fleet size and depth to `budget.remaining()`; stop
   fanning out before the cap.
3. **Cap fan-out; never truncate silently** — `log()` whatever you drop.
4. **Checkpoint distilled output to a durable file before synthesis**, as an explicit
   script step — `SubagentStop` hooks never fire for Workflow-internal agents, so a
   hook cannot save you; a run killed during synthesis loses everything unpersisted.
5. **Synthesize even if partial**, from the checkpoint — a labeled-partial report
   beats a dead run.

## Verification economics — size the check to the stakes

- **Don't re-verify what the finder already proved.** If the finding agent *executed*
  the failing case (ran the test, reproduced the crash), its evidence stands;
  re-verify only when the evidence is reasoning rather than execution, or the claim
  drives a priority/money decision.
- **Adversarial multi-vote verify fleets are for criticals only** — findings whose
  being-wrong costs money or corrupts irreplaceable data. Minors ride with the single
  reviewer.
- **Surface fleet size before big launches** — state the agent count and rough token
  estimate; a silent 500k-token fleet is an unreviewed spend decision.

## Verify with the advisor — main-loop work only

The advisor is the check on the **main loop's own** work — the conclusions nothing else
reviews. Set `advisorModel` to **at least the main-loop model** (Opus or stronger); a
weaker advisor can't reliably catch a strong model's mistakes. After nontrivial
main-loop work, verify with the advisor before claiming done. **Evidence before assertions.**

**On a Fable session the built-in advisor tool does not work** — the `advisorModel`
path is unsupported at the top tier (observed 2026-07-16; re-check on harness
updates). Route every consult through the `advisor-plus` agent instead, with **no
`model` override**: `inherit` already yields Fable, and there is no tier above to
select.

**Cheap subagents don't need their own advisor.** The main loop already reads and
verifies every subagent's output (build, tests, read), so a separate advisor pass on
subagent work is redundant. The flow is: delegate → main loop verifies. Reserve the
advisor for what the main loop itself produced.

## Git / GitHub specifically

Commits, pushes, PR creation/updates, and CI-watching are mechanical — route them to
Sonnet 5 (or a cheap subagent), keeping commit messages and PR bodies faithful and
accurate. Do not burn strong-model tokens polling CI: delegate the watch, or schedule a
wake-up and return to it.
