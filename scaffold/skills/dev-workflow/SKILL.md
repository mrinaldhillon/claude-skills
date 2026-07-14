---
name: dev-workflow
description: >-
  Use to keep the development and testing loop fast and offline and to propose
  tooling improvements. Trigger when CI/test friction appears, a manual step
  repeats, or the inner loop is slow.
---

# Dev/test workflow optimization

## Keep the inner loop offline and fast
All unit tests run against committed test fixtures with **no network**.
`make test-offline` must pass without any external service. Use focused runs
(targeting the package under change) and small fixtures during iteration.

## Standard targets
`make dev-setup` (one-time: installs local tools) · `make build` · `make test` ·
`make test-offline` · `make vet` · `make lint` (e.g. golangci-lint for Go) ·
`make ci` (mirror CI locally — pinned module, strict mode: vet + offline tests +
lint + build) · `make watch` (re-run tests on save via a file watcher) ·
`<project-specific targets>` (e.g. fixture capture, knowledge sync checks — run
once or on drift).

**Document target liveness with a "Live when" column.** In the project's
CLAUDE.md Commands table, give each target a `Live when` cell: **now**, or the
concrete milestone/artifact it waits on (e.g. "needs `internal/replay` (M1b)").
It tells a fresh session what is real today vs. aspirational, and each cell
flips to **now** in the milestone-completion doc sweep (`milestone-workflow`
step 6) — a stale cell is doc drift, not a placeholder.

**Pinned external dependency (opt-in local-checkout; see the workflow ADR):** the
default build uses the pinned version. To iterate on the dependency locally:
configure your workspace file or path replace to point at the local checkout · run
an advisory drift check (warns when the checkout diverges from the pin) · revert to
the pinned default when done. Always run `make ci` before push — it validates the
pinned path even while a local workspace is active.

## Propose improvements when you hit friction
- A repeated manual step → propose a hook/command/script (e.g. a `pre-commit`
  hook running a formatter, a linter, a version-stamp check).
- A slow build → propose caching or splitting.
- A change that took many edit-test cycles → propose a faster path (smaller
  fixture, focused test, better assertion).

## Editor/session
A multi-pane terminal layout (e.g. tmux) with panes for process logs, an editor,
and `make watch` covers most workflows. Editor tooling (e.g. a language server,
a formatter/linter on save — for Go: gopls + golangci-lint) supports the loop —
keep it minimal, it is not the product.
