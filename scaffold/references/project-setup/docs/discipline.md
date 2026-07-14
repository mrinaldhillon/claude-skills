# Discipline

Enforced rules. Each addresses a specific failure class and is **cited by number**
from code, reviews, and the other docs (e.g. "rule 4"). A change that appears to
require violating a rule is almost certainly wrong — raise the question before
bypassing. Each rule's reasoning lives in `design-notes.md` (referenced per rule).

## How this file works
- **Numbered, append-mostly.** Rules get a stable number; cite by it. Tightening the
  wording is fine; renumbering is not (it breaks citations).
- **One failure class per rule.** If you can't name the failure a rule prevents, it
  isn't a rule yet.
- **Universal rules first** (below), then project-specific rules as they emerge from
  the design.

## Universal rules (kept from the template — keep, edit, or extend)

### 0. Verify before asserting
Never fabricate an API, field, flag, or data shape. Confirm against the source/spec
and cite it (`file:line`, §, RFC). Distinguish verified from inferred.
*CLAUDE.md › Persona and standard of work*

### 1. Security first
Threat-model by default: least privilege, validate all inputs, no secrets in code or
logs, respect the trust boundary. *design-notes §4*

### 2. Correctness & failure modes over cleverness
Handle errors explicitly; reason about races, partial failure, and resource cleanup.
Prefer the simplest design that holds. *design-notes §4*

### 3. Tests run offline
The inner loop and CI never reach the network — tests resolve from committed
fixtures/mocks. The correctness gate must be reproducible. *design-notes §3*

### 4. Observability
Make behavior debuggable: structured logs, metrics, and traces where they earn their
keep. Consider the engineer paged at 3am. *design-notes §3*

### 5. Reproducibility
Deterministic builds and environments; pin toolchain and dependency versions;
document the non-obvious. *design-notes §3*

### 6. Keep the committed context in sync
When an implementation discovery contradicts or extends a doc/skill/ADR, fix it in
the **same PR** as the code, citing the discovery. *design-notes §3*

### 7. Decisions are append-only ADRs
Record a decision once, in `decisions/`; change it only by appending a superseding
ADR. Don't relitigate settled decisions. *decisions/0000*

### 8. Stay in scope
Change only what the milestone or task defines. No "while we're here" refactors,
renames, or optimizations — record them as follow-ups, don't fold them in. Widening
scope needs explicit sign-off before the first edit. *design-notes §5*

### 9. Done means green
Don't declare work complete until the gate passes: build, vet/typecheck, offline
tests, and lint all clean. A red or unrun gate means not done — fix it or surface the
blocker; never assert success unverified. *design-notes §3*

### 10. Tier the model to the task's stakes
Choose each subagent's model by the reasoning the task needs, **before** spawning —
Haiku for pure-mechanical/high-read work, Sonnet for moderate legwork, Opus for
correctness-critical judgment; tier **up** when quality is at stake. Never let a
fan-out inherit the strong default: Workflow `agent()` stages MUST set `opts.model`.
The failure this prevents is silent token burn (or a rubber-stamped judgment) from an
un-chosen model. *CLAUDE.md › Models and parallel work; orchestration skill*

---

## Project-specific rules

<PLACEHOLDER: add rules starting at 11 as the design produces them. Each: a terse
imperative, the failure it prevents, and a `§` back to design-notes. The strongest
projects have ~10–40 of these — they are the distilled, hard-won "what bites".>
