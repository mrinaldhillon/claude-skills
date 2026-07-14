# CLAUDE.md

Guidance for Claude Code when working in this repository.

Read this, then `docs/decisions/` (settled ADRs) and `docs/README.md` (read order),
before writing or changing anything. Cite the section (`§X.Y`), discipline rule
number, or ADR behind every non-trivial decision.

## Persona and standard of work

The `distinguished-engineer` output style sets the voice: terse, senior-peer,
no filler. **Verify before asserting** — confirm any API/struct/flag/data-shape
against the source with a `file:line` anchor; never fabricate. Admit uncertainty
rather than guessing. **Review your own work before declaring anything done:** run
the build, vet/typecheck, tests (offline), and lint; if it doesn't build or pass, it
isn't done (discipline rule 9). The bar is production quality.

## What this project is

<PLACEHOLDER: one paragraph — what this project is, its product/purpose, and the
single load-bearing invariant everything else serves.>

## Commands

<PLACEHOLDER: fill from your build tool's task taxonomy — see the dev-workflow skill.>

| Command | What it does |
|---|---|
| `<build>` | build all binaries/artifacts |
| `<test>` | all tests — **offline** (no network) |
| `<test-offline>` | explicit offline run (must pass with project services down) |
| `<vet/check>` | static analysis / typecheck |
| `<lint>` | linter |
| `<ci>` | mirror CI locally (vet + offline tests + lint + build) before pushing |
| `<watch>` | re-run offline tests on save (inner loop) |

- **Run one test:** `<the focused-test invocation for your stack>`.
- **Offline is law:** never reach the network in a test or in CI (dev-workflow skill).

## Architecture at a glance

<PLACEHOLDER: the component/process map, the hot/critical paths, and the
import/layering boundaries that are ENFORCED. If you have a boundary table, make
`docs/architecture.md` its authoritative home and point here.>

## Context engineering

- **Read `docs/decisions/`** (append-only ADRs) for what was already decided. ADRs
  are statements of record — consult them, don't relitigate. Change a decision only
  by appending a superseding ADR. ADRs carry a one-line `**Summary:**` — scan titles
  + summaries to know what's decided; open a full ADR body only to relitigate or
  supersede a decision, not every session.
- **Parse large external dependencies once**, not every session: distill the facts
  you need into a doc under `docs/` (with a `file:line` anchor at a pinned version),
  and read that instead of re-walking the source. Re-verify only on confirmed drift.
- **Locate code with a language-server MCP, not grep**, where one exists (e.g. gopls
  for Go): symbol/reference/API lookups return a `file:line` + signature instead of a
  grep dump — less context burn for the same answer.
- **Update context in the same PR.** When an implementation discovery contradicts or
  extends any doc/skill/knowledge artifact, fix that artifact in the same PR as the
  code, citing the discovery as a `file:line` anchor. Improving the committed context
  is part of the work (the `doc-sync` agent backstops this).

## Models and parallel work

- **Tier the model to the stakes, not uniformly** (`tier = f(reasoning the task
  needs)`; this is **discipline rule 10**). Three tiers: **Haiku** for pure-mechanical,
  high-read, low-reasoning work
  (web search, fetch/extract, log scraping, status polling); **Sonnet** for moderate
  legwork / structural analysis — the usual subagent floor, where the repo's named
  agents sit (`doc-sync`, `config-auditor`, `search`; e.g. `config-auditor` is
  structural lint of the steering layer the `validate-config` hook backstops, not
  `code-reviewer`-grade judgment); **Opus** only for correctness-critical
  judgment — review/audit (`code-reviewer`), the correctness gate, all verification,
  and milestone *implementation*. Rationale: the strong model bills several× the cheap
  one — spend it only where a wrong answer is expensive.
- **Quality is paramount; the cost and quality rules resolve via stakes.** "Don't
  waste tokens on mechanical work" applies *only* when the task is genuinely
  low-reasoning AND a wrong answer is cheap. When correctness or output quality is at
  stake, tier **up**, not down — in doubt on a quality-critical task, go up. A
  rubber-stamp verification or a botched coupled edit is a false economy; never
  cost-cut the judgment, verification, or gate paths.
- **Decide the model before spawning, per subagent, and pin it.** Agents/commands
  carry `model:` frontmatter (`.claude/agents/`, `.claude/commands/`); **Workflow
  `agent()` stages MUST set `opts.model` per stage** — else they inherit the session's
  strong model and a mechanical fan-out burns the budget in minutes (the deep-research
  burn: ~1.95M tokens, cap hit twice). Cap fan-out, guard the `budget`, and
  **checkpoint distilled output to durable memory as an explicit step — not a hook**
  (`SubagentStop` doesn't fire for Workflow-internal agents at all, and for Agent-tool subagents its payload omits the result text). Bump each
  tier's pinned ID when a stronger model ships. Full model: `orchestration` skill.
- **For search/exploration use the `search` agent** (pinned to the floor model), not
  the built-in `Explore`, which inherits the caller's (expensive) model and whose
  recall failures are silent.
- **Spawn subagents for independent tracks** and **delegate mechanical GitHub-flow
  ops** (opening PRs, watching CI, merging on green, deleting branches) to a cheap
  subagent — it absorbs verbose CI output and returns only the verdict, keeping the
  main context clean. Keep the **judgment** (diagnosing a failure, deciding to merge)
  on the main loop. The full model is the **`orchestration` skill** — load it at the
  start of any milestone/large review that spawns subagents.

## Skills and workflow

- **Suggest relevant skills before starting**, and state which you'll use. When a
  knowledge need recurs (the second lookup of the same thing), **build a project
  skill** under `.claude/skills/` (`skill-maintenance` skill).
- **Before any implementation that touches multiple file categories, run the
  `git-workflow` skill § Pre-implementation branch routing** and split into separate
  `chore/…`, `docs/…`, or milestone branches before writing the first file.
- **Keep the inner loop fast and offline** (`dev-workflow` skill). Surface a manual
  step that should become a hook/command.
- Shipped skills: `project-bootstrap` (one-time), `orchestration`, `git-workflow`,
  `dev-workflow`, `skill-maintenance`, `milestone-workflow`, `template-sync`
  (downstream — pull forward upstream template fixes), `deep-research-tiered` (budget-safe fan-out research). Shipped agents: `search`,
  `code-reviewer`, `doc-sync`, `config-auditor` (audits the `.claude/` layer
  itself), `determinism-auditor` (five replay-parity footguns; placeholder rule
  anchors — fill or delete at bootstrap). Shipped commands: `/bootstrap` (one-time), `/goal`, `/milestone`, `/adr`
  (scaffold the next ADR). The `validate-config` hook
  (`.claude/hooks/validate-config.sh`) checks the steering layer's own
  JSON/frontmatter on every edit; the `subagent-trail` hook
  (`.claude/hooks/subagent-trail.sh`, on `SubagentStop`) leaves a breadcrumb per
  finished subagent.

## Where to ask vs. proceed

Ask only at genuine decision points (a key the user must choose, a destructive or
outward-facing action, a real ambiguity). Everything else: proceed, verify, and
self-review.

## Context & checkpoint protocol

Durable state lives in files, never in the conversation. A session is disposable;
the checkpoint is the source of truth.

**A checkpoint means, in order:**
1. `.context/project-context.md` — current goal/milestone + gate status, files touched
   and why, decisions made, and the exact next step.
2. `docs/decisions/` — append an ADR for any decision settled this session
   (append-only; consult, don't relitigate).
3. `.context/RESUME.md` — the single next action for a fresh session.

The `checkpoint.sh` hook commits these on non-main branches automatically
(PreCompact and Stop); on `main` it saves nothing to git — ADR 0002.

**On a `[CONTEXT NOTICE]`** (injected by the context-nudge hook past 55%/65%
usage — on prompt submit or mid-turn after a tool call; ADR 0004): finish the
current micro-task, checkpoint as above, then ask the user to run `/clear`.
Prefer clear-and-resume over `/compact` at task boundaries — the files hold the
truth; a lossy summary of the chat adds nothing. Tuned auto-compaction
(`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, exported at ~70% by the milestone runner)
is the backstop: it fires above the nudge thresholds, over a fresh checkpoint.

**When compacting anyway**, preserve verbatim: the current milestone and its gate
status; any open correctness-gate failures; the build resume pointer; and ADR
numbers cited in the last ~10 turns. Drop tool-output dumps, file listings, and
resolved sub-steps. After a compaction, `RESUME.md` is re-injected automatically
(SessionStart hook) — re-read `.context/project-context.md` before continuing.

## Map of docs

- `docs/README.md` — index and read order.
- `docs/decisions/` — append-only ADRs (what was decided).
- `docs/design-notes.md` / `architecture.md` / `discipline.md` — reasoning /
  structure / rules.
- `docs/vocabulary.md` — terms that are easy to misread.
- `docs/meta/` — template-maintainer notes (why the template is built this way);
  removed on bootstrap.
- `.context/` — **agent-written project state, not documentation** (ADR 0005):
  `project-context.md` (current state, open questions) and `RESUME.md` (one-line
  resume pointer — the next action for a fresh session), both committed by the
  checkpoint hook; plus the gitignored milestone-run sentinels
  (`MILESTONE_DONE`, `REPLAN.md`).
- `scripts/` — repo tooling; `milestone-runner.sh` runs the hands-off
  context-managed milestone loop — dynamic chunks from a `milestones/*.json`
  config behind deterministic gates (ADR 0004; offline tests in `scripts/tests/`).
- `.claude/` — skills, agents, commands, hooks, settings, output style.
