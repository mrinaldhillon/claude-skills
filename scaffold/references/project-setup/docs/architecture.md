# Architecture

> Skeleton — replace with your project's content. The **structure** doc: components,
> processes, repository layout, and the authoritative import/layering-boundary table.

## Components & processes

<PLACEHOLDER: each process/service, its responsibility, and its failure domain. Note
which are separate processes vs. shared libraries, and what (if anything) they share
at runtime.>

## Repository layout

<PLACEHOLDER: the top-level package/module map and what belongs where.>

## Import / layering boundaries (authoritative)

The table below is **enforced** — the `code-reviewer` agent checks against it. A
violation is a bug, not a style nit.

| Package / layer | May import | May NOT import | Why |
|---|---|---|---|
| `<pure/core>` | stdlib only | any process/IO package | keep it pure/testable |
| `<process A>` | `<core>` | `<process B>` | separate failure domains |
| … | … | … | … |

<PLACEHOLDER: fill the real boundaries. If you have none yet, delete the example rows
and add them as layers appear — but add the first one before the second process.>
