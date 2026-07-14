# 0. Record architecture decisions

- **Summary:** Decisions are recorded as append-only ADRs in `docs/decisions/`; supersede via a new ADR, never edit an Accepted one's meaning.
- **Status:** Accepted
- **Date:** <bootstrap fills>
- **Amended by:** 0007 (partial supersession is annotated at the affected clause)

## Context

We will make decisions whose rationale matters months later — why a boundary exists,
why an approach was rejected, why a constraint is non-negotiable. Without a record,
that rationale is re-litigated every time someone (human or model) forgets it, and
the "why" is lost to chat history that gets compacted away.

## Decision

We keep **Architecture Decision Records** (Michael Nygard's format) under
`docs/decisions/`, one decision per file, numbered sequentially
(`NNNN-short-title.md`).

ADRs are **append-only**: once Accepted, a record is **never edited** to change its
meaning. A decision is changed only by appending a **new** ADR that supersedes it
(note the supersession in both: "Superseded by 000X" / "Supersedes 000Y"). This makes
the decision history immutable and citable — code and docs reference an ADR by number.
*(Refined by ADR 0007: when a new ADR supersedes individual clauses rather than the
whole record, the affected clauses are additionally annotated in place — additive
pointers only, never rewrites.)*

Each ADR states: **Context** (the forces at play), **Decision** (what we chose, in
the active voice), and **Consequences** (what becomes easier and harder). Use
`TEMPLATE.md`.

## Consequences

- Settled decisions are consultable, not re-debated — cite the ADR number.
- The history of *why* survives context compaction and contributor turnover.
- A small discipline cost: a decision worth following is worth a five-minute record.
