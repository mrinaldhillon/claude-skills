---
name: skill-maintenance
description: >-
  Use to decide when to suggest an existing skill, when to build a new project
  skill, and how to keep skills and docs current. Trigger when a knowledge need
  recurs, when starting a task (to suggest skills), or when a discovery extends a doc.
---

# Skill maintenance and the self-improvement loop (a discipline.md rule)

## Suggest before starting
At the start of a task, match it against installed skill descriptions and **state
which skills apply** and which you'll use. Reach for a skill before re-deriving a
procedure.

## Build on recurrence
When the **same** knowledge need appears a **second** time (a repeated lookup of a
data shape, an API, a procedure), **author a new project skill** under
`.claude/skills/<name>/SKILL.md` capturing it. Skill format: a directory with
`SKILL.md`, YAML frontmatter `name` (lowercase-hyphen, == folder) + `description`
(a specific activation trigger); Markdown body kept small (progressive disclosure —
only name+description preload; body and bundled files load on demand); optional
bundled scripts callable via Bash. Use the `skill-creator` helper if available.

## Maintain in-PR
When an implementation discovery contradicts or extends a skill, doc, or a
parse-once knowledge artifact, **update it in the same PR** as the code change,
citing the discovery as a `file:line` anchor at the current dependency commit. The
`doc-sync` subagent checks for code-vs-doc drift.

## What to capture vs not
Capture stable, reusable knowledge (record framing, external APIs, stream shapes,
correctness rules). Do not capture one-off task state (that's the playbook/PR) or
secrets.
