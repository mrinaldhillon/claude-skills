---
name: skill-maintenance
description: >-
  Use to decide WHEN a project skill is worth authoring — the second-recurrence
  trigger — and what belongs in one. Trigger when the same knowledge need (a data
  shape, an API, a procedure) comes up a second time. Covers the trigger only;
  superpowers:writing-skills owns how to actually write and test the skill.
---

# When to author a project skill

The trigger, not the craft. **`superpowers:writing-skills` owns the craft** —
SKILL.md format, frontmatter rules, progressive disclosure, bundled scripts, and
its RED-GREEN pressure-testing method. The `skill-creator` plugin scaffolds one.
Don't restate any of that here; go read it.

## Build on the second recurrence

When the **same** knowledge need appears a **second** time — a repeated lookup of a
data shape, an external API, a procedure you already re-derived once — stop and
author a project skill under `.claude/skills/<name>/SKILL.md`.

Once is an incident; twice is a pattern with a third occurrence coming. The failure
this prevents is re-deriving the same procedure every session and paying full
context for it each time. Authoring on the *first* occurrence is the opposite
failure — speculative skills that never fire.

## What belongs in one

Capture **stable, reusable** knowledge: record framing, external API shapes, stream
formats, correctness rules. Do **not** capture one-off task state (that is the
playbook or the PR body) or secrets of any kind.

## Not covered here, on purpose

- **How to write/test it** → `superpowers:writing-skills`.
- **Announcing which skills apply at task start** → `superpowers:using-superpowers`.
- **Updating a skill/doc in the same PR as the code that contradicted it** → that is
  discipline rule 6, enforced by the `doc-sync` agent — not a rule of this skill.
