# Design notes

> Skeleton from the claude-code-starter template. This is the **reasoning** doc —
> the "why" behind every decision. `discipline.md` distills the "what" (the rules),
> `architecture.md` the "how" (the structure). Write prose here; cite back to it with
> `§` anchors from code and the other docs.

## 1. Thesis

<PLACEHOLDER: the one-sentence core idea, then a paragraph. What is the system for,
and what is the single invariant or property everything else serves?>

## 2. The foundational decision(s)

<PLACEHOLDER: the 1–3 decisions that shape everything downstream. State each as
decision → rationale → consequence. These become discipline rules.>

## 3. Architecture

<PLACEHOLDER: the component/process model and the data/control flow. Cross-reference
`architecture.md` for the structural detail; keep the *reasoning* here.>

## 4. Failure modes & threat model

<PLACEHOLDER: what can go wrong (races, partial failure, reorgs/retries, resource
exhaustion, trust boundaries) and how the design handles each. Senior reviewers will
look here first.>

## 5. Milestone plan

<PLACEHOLDER: the milestones as a dependency graph (not a line). What ships first,
what each unlocks, and the gate that proves each is done.>

---

Add sections as the design solidifies. Every numbered discipline rule should trace to
a `§` here.
