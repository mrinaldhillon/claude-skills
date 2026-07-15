---
name: milestone-workflow
description: >-
  Use at the start of and throughout any milestone build — the project-substrate
  half of a milestone: playbook + preconditions, forward-looking data capture, the
  in-PR context rule, and the status-prose sweep at milestone completion. Trigger
  from the /goal and /milestone commands. Defers plan execution to
  superpowers:executing-plans (or subagent-driven-development) and the
  evidence-before-done gate to superpowers:verification-before-completion.
---

# Milestone workflow

**This skill is the substrate, not the loop.** Executing a written plan
task-by-task — load, review critically, work in order, verify each step, report —
is `superpowers:executing-plans`, or `superpowers:subagent-driven-development` when
dispatching a subagent per task. Claiming done without fresh command output is
`superpowers:verification-before-completion`. Don't restate those here; use them.

What is *not* in those skills, and is therefore what this one carries: where a
milestone's inputs live, capturing data ahead of need, and the doc-drift sweep that
fires on merge.

Playbooks: `docs/playbooks/<milestone>.md` (authored per milestone). The dependency
graph is in `.context/project-context.md` — milestones are a graph; independent
tracks (e.g. knowledge bootstrap, profiling, fixture capture, dev-env) run in
parallel via subagents, tiered per `orchestration`.

## Procedure

1. **Load the playbook** for the milestone; restate goal + gate. Check
   preconditions (parse-once knowledge bootstrapped, required credentials present,
   external dependencies resolved). Then execute it via
   `superpowers:executing-plans` — a playbook *is* the plan that skill expects.

2. **Capture forward-looking data** per the project's data capture plan — grab
   everything cheaply capturable now, even for later milestones, to retire the
   live-service dependency early. Document observed data shapes into a `docs/`
   knowledge doc. (No superpowers counterpart: this is the project's own
   retire-the-live-dependency strategy, not a generic plan step.)

3. **Gate before claiming done.** The evidence discipline is
   `superpowers:verification-before-completion`. The *project's* gate list is what
   this skill pins: build, vet, test, the correctness gate, the linter, any
   project-specific sync checks, fixture round-trip, and version-stamp present (a
   discipline rule). Then run the `code-reviewer` and any project-specific auditor
   subagents on the diff.

4. **Update context in the same PR** (discipline rule 6): the docs/skills/knowledge
   docs the work extended, citing `file:line`. The `doc-sync` agent checks this.

5. **At milestone completion, refresh the status prose everywhere it lives.** Its
   trigger is the *milestone merge itself* — NOT step 4's code-discovery rule — so
   it silently drifts if skipped. In the milestone's final reconciliation: flip
   `.context/project-context.md` **Current state** to the merged milestone + the
   next unblocked one, extend the ADR index, mark resolved open questions; then
   sweep the SAME claims where they are duplicated — the `CLAUDE.md` preamble and
   Commands table (a "Live when" column rots fastest) and the `docs/README.md`
   header. (A downstream audit found all three still claiming the pre-first-
   milestone state two milestones later.) Route per `git-workflow`: a chore/ +
   docs/ PR pair when the files land on different branch types.

6. **Ask only at documented decision points** (e.g. key/credential setup, first live
   capture, first real-money action). Otherwise proceed.
