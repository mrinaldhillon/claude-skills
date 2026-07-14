---
description: Generic per-milestone driver (copy into named /m1, /m2, … as milestones firm up)
argument-hint: <milestone-name> [notes]
model: claude-opus-4-8
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, Agent, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet
---

Drive the milestone named in `$ARGUMENTS` to completion.

This is the generic milestone driver. A maturing project typically copies this into
named per-milestone commands (`/m1`, `/m2`, …) once its milestones are defined, each
pinning that milestone's goal, gate, and playbook.

1. **Identify the target** — the first token of `$ARGUMENTS`. If it's ambiguous or
   there is no matching playbook, ask which milestone; do not guess.
2. **Read first**: `CLAUDE.md`, `docs/decisions/` (settled ADRs — consult, don't
   relitigate), then `docs/playbooks/<target>.md` and the specs it cites. Load the
   relevant skills and **say which** you'll use.
3. **Follow the `milestone-workflow` skill**: restate goal + gate; check
   preconditions; work the ordered workstreams (create the named packages, implement
   the listed interfaces, write the listed tests); self-verify; **update docs/skills
   in the same PR** as the code (the keep-docs-in-sync rule).
4. **Spawn subagents** for independent tracks per the `orchestration` skill
   (Sonnet legwork from a precise spec; main keeps the judgment). Run the
   `code-reviewer` and `doc-sync` agents on the diff before declaring done.
5. **Stop only** at the playbook's documented decision points or a real ambiguity.

The gate is the milestone's teeth: it must be green (`make ci`, plus any
project-specific correctness gate) before the PR merges.
