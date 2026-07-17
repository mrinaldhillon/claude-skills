---
description: Scaffold the next ADR in docs/decisions/ from TEMPLATE.md
argument-hint: <imperative title, e.g. "pin the toolchain version"> [supersedes NNNN]
model: sonnet
allowed-tools: Read, Glob, Grep, Write, Edit, Bash(date +%F)
---

Create the next Architecture Decision Record in `docs/decisions/`. This is
mechanical scaffolding — you write the skeleton; the author fills the reasoning.

1. **Next number** — list `docs/decisions/[0-9]*.md`, take the highest `NNNN`
   prefix, add one, zero-pad to four digits (`docs/decisions/TEMPLATE.md` is not
   numbered, so it never counts).
2. **Slug** — kebab-case `$ARGUMENTS` (lowercase; spaces → `-`; drop punctuation).
   File: `docs/decisions/<NNNN>-<slug>.md`.
3. **Scaffold** — copy `docs/decisions/TEMPLATE.md` verbatim, then fill only the
   header: `# <NNNN>. <Title>` (title from `$ARGUMENTS`, imperative voice),
   `Status: Proposed`, `Date:` = today (`date +%F`), `Supersedes: —`. Leave
   Context / Decision / Consequences as the template prompts them — do **not**
   invent the rationale; that is the author's to write.
4. **Superseding** — if `$ARGUMENTS` names an ADR this replaces, set this record's
   `Supersedes:` to it and, in the same change, set that ADR's `Superseded by:` to
   this number and its `Status:` to `Superseded`. ADRs are append-only — never edit
   a settled decision except to mark it superseded (CLAUDE.md › Context engineering).
5. **Report the path.** Do not add an index line anywhere — ADRs are self-indexing
   by `NNNN-` filename, and `docs/README.md` lists `decisions/` as a category, not
   per record.

Treat `$ARGUMENTS` as the title plus an optional `supersedes NNNN`. If it's empty,
ask for the title — do not guess.
