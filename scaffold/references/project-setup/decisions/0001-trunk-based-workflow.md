# 1. Trunk-based git workflow

- **Summary:** `main` is the only long-lived branch — trunk-based, PR-into-main, rebase-merge, green-to-merge; no develop/release branches.
- **Status:** Accepted
- **Date:** <fill on adoption>
- **Supersedes:** —
- **Superseded by:** [0002](0002-branch-protection-by-discipline.md) — branch-protection clause only; the rest of this ADR remains in force

## Context

A solo or small team needs a git workflow that keeps the mainline always shippable
without the overhead of long-lived release/develop branches. Long-lived branches
accumulate merge debt and drift; the value is in a single always-green trunk.

## Decision

**`main` is the only long-lived branch** — always green, always deployable. No
`develop`, no release branches.

- The unit of change is a **PR into `main`**. Branch off `origin/main`: milestones
  `m1`/`m2`/…, small work `fix/…`, `chore/…`, `docs/…`.
- **One concern per branch/PR.** Repo-meta/workflow/tooling changes (`CLAUDE.md`,
  `.claude/**`, CI config, the build file) go on their own `chore/…` branch — never
  mixed into a milestone branch. See the `git-workflow` skill § branch routing.
- **Green-to-merge**: CI green + the project's correctness gate passes + the
  `code-reviewer` agent has run once on the full branch diff (`doc-sync` too
  where the diff touches a docs surface, or at milestone close — see each
  agent's description for its scope).
- **Rebase-and-merge** by default (linear history; squash only noisy PRs); delete the
  branch on merge. Never force-push `main`.
- `main` is **branch-protected**: require a PR + passing CI + linear history + no
  force-push/delete.

## Consequences

- Always-deployable trunk; small, reviewable PRs; linear, bisectable history.
- Mechanical PR/CI/merge steps are delegable to a cheap subagent (the merge
  *decision* stays with the main loop) — see the `orchestration` skill.
- Discipline cost: every change is a branch + PR, even one-line fixes. Worth it for
  the always-green guarantee.
