---
description: Dispatch a milestone build end-to-end (drives /milestone via the milestone-workflow skill)
argument-hint: <milestone-name> [notes]
model: claude-opus-4-8
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, Agent, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet
---

Drive the milestone named in `$ARGUMENTS` to completion.

1. Identify the target (first token of `$ARGUMENTS`). Open the matching milestone
   command and its playbook at `docs/playbooks/<target>.md`. If the target is
   ambiguous or absent, ask which milestone — do not guess.
2. Read first: `CLAUDE.md`, `docs/decisions/`, then the playbook and the specs it
   cites. Load the relevant skills and say which.
3. Follow the `milestone-workflow` skill: restate goal + gate, check
   preconditions, work the ordered workstreams, capture forward-looking data per
   the project's capture plan, self-verify, update context in the same PR.
4. Spawn subagents for independent tracks where the playbook calls for them; run
   code-reviewer and doc-sync before declaring done.
5. Stop only at the playbook's documented decision points or a real ambiguity.

Treat the remaining text in `$ARGUMENTS` as scoping notes for this run.
