# 7. Annotate superseded clauses in place

- **Summary:** A superseding ADR that replaces only part of an older record must also annotate the affected clause in place with a pointer, in addition to the header stamp.
- **Status:** Accepted
- **Date:** <fill on adoption>
- **Supersedes:** — (amends the process rule in 0000)
- **Superseded by:** —

## Context

ADR 0000 makes records append-only: once Accepted, an ADR is never edited to
change its meaning, and a decision changes only via a new superseding ADR plus
header stamps in both records. In practice the project has twice needed
something finer than whole-record supersession: ADRs 0004 and 0005 each
superseded *individual clauses* of ADR 0003 (the runner mechanism; the state
-file location) while the rest of 0003 remained in force. Both times the
superseded clause was annotated in place — an italic "*(corrected/evolved by
ADR 000X …)*" note under the affected text — in addition to the header stamp.
The practice was declared in the Consequences of 0004/0005 but never sanctioned
by the process rule itself, leaving it an undocumented exception to 0000 that
an external audit flagged.

## Decision

We will record **partial supersession** as follows:

- The superseding ADR states exactly which clauses of the older record it
  replaces, and that the remainder stands.
- The superseded ADR receives BOTH a header stamp ("Superseded by: 000X
  (<scope>)") AND a short italic annotation directly under each affected
  clause pointing to the superseding ADR.
- Annotations are **additive pointers only** — the original text is never
  deleted or reworded, so the record still reads exactly as it was decided.
- Everything else in ADR 0000 stands unchanged: edits that change a record's
  meaning remain prohibited.

## Consequences

- A reader landing on an old ADR sees, at the exact clause, that it has since
  evolved — without diffing headers against every later record.
- The append-only guarantee survives: history is annotated, never rewritten.
- Cost: two records to touch per partial supersession (the new ADR + the
  annotations) — the same two records the header-stamp rule already required.
