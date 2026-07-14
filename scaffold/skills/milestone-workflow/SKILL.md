---
name: milestone-workflow
description: >-
  Use at the start of and throughout any milestone build to load the playbook,
  follow the workstreams, capture data per the forward-looking plan, and run the
  self-verification checklist before claiming a gate. Trigger from the /goal and
  /milestone commands.
---

# Milestone workflow

Playbooks: `docs/playbooks/<milestone>.md` (authored per milestone). The dependency
graph is in `.context/project-context.md` — milestones are a graph; independent tracks
(e.g. knowledge bootstrap, profiling, fixture capture, dev-env) run in parallel via
subagents (`.claude/agents/`).

## Procedure
1. **Load the playbook** for the milestone. Restate goal + gate. Check
   preconditions (e.g. parse-once knowledge bootstrapped, required credentials
   present, external dependencies resolved).
2. **Work the ordered workstreams.** For each: create the named packages/files,
   implement the listed interfaces/types, enforce the cited rules, write the
   listed tests (unit + golden-fixture + property/fuzz where apt). Most stages are
   **offline** via committed test fixtures.
3. **Capture forward-looking data** per the project's data capture plan — grab
   everything cheaply capturable now, even for later milestones, to retire the
   live-service dependency early. Document observed data shapes into a docs/
   knowledge doc.
4. **Self-verify before declaring done:** build (`make build`), vet (`make vet`),
   test (`make test`), the project's correctness gate (`make ci`), linter
   (e.g. golangci-lint), any project-specific sync checks, fixture round-trip,
   version-stamp present (a discipline.md rule). Run the `code-reviewer` /
   project-specific auditor subagents.
5. **Update context in the same PR** (a discipline.md rule): docs/skills/knowledge
   docs that the work extended, citing `file:line`.
6. **At milestone completion, refresh the status prose everywhere it lives.** Its
   trigger is the *milestone merge itself* — NOT step 5's code-discovery rule — so
   it silently drifts if skipped. In the milestone's final reconciliation: flip
   `.context/project-context.md` **Current state** to the merged milestone + the
   next unblocked one, extend the ADR index, mark resolved open questions; then
   sweep the SAME claims where they are duplicated — the `CLAUDE.md` preamble and
   Commands table (a "Live when" column rots fastest) and the `docs/README.md`
   header. (A downstream audit found all three still claiming the pre-first-
   milestone state two milestones later.) Route per `git-workflow`: a chore/ +
   docs/ PR pair when the files land on different branch types.
7. **Ask only at documented decision points** (e.g. key/credential setup, first
   live capture, first real-money action). Otherwise proceed.
