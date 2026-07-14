# Docs

The spec and the source of truth for this project. Code reconciles to these docs;
when an implementation discovery contradicts a doc, fix the doc in the same PR (the
keep-docs-in-sync rule).

## Read order

1. **`design-notes.md`** — the reasoning: thesis, architecture, and every decision
   with its rationale. Start here.
2. **`discipline.md`** — the numbered rules distilled from the reasoning. These are
   what bite.
3. **`architecture.md`** — components, processes, layout, and the authoritative
   import/layering-boundary table.
4. **`.context/project-context.md`** (agent-written state, outside `docs/` — ADR 0005)
   — where things stand, the active workstream, open questions.
5. As needed: **`vocabulary.md`** when a term is ambiguous; **`decisions/`** for what
   was already settled.

The repo root also carries **`CLAUDE.md`** (instructions for Claude Code) and
**`.claude/`** (skills, agents, commands, output style, settings).

## Documents

| File | What it covers |
|---|---|
| `design-notes.md` | Thesis, architecture, decisions, milestone plan |
| `discipline.md` | The numbered rules — the non-negotiable constraints |
| `architecture.md` | Components, processes, layout, import/layering boundaries |
| `vocabulary.md` | Terms that are easy to misread, with the misunderstanding each prevents |
| `decisions/` | Append-only ADRs (one decision per file; never edited, only superseded) |

Agent-written project state — `project-context.md` (current milestone, active
workstream, recent decisions, open questions) and `RESUME.md` (one-line resume
pointer, committed by the checkpoint hook) — lives outside `docs/`, in `.context/`
(agent-writable; `.claude/` is not). See `.context/README.md` and ADR 0005.

As the project grows, add `specs/` (per-component specs in build order),
`playbooks/` (per-milestone build plans driven by `/milestone`), and a parse-once
knowledge doc for any large external dependency.

## Conventions

Cite the section (`§X.Y`), discipline rule number, or ADR behind a claim. Keep
settled decisions and open questions distinct — settled lives in `design-notes.md` /
`discipline.md` / `decisions/`, open lives in `.context/project-context.md`.
