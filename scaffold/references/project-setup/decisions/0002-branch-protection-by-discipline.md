# 2. Branch protection is by-discipline

- **Summary:** `main` protection is a documented target, enforced by discipline (not GitHub) until this project configures it.
- **Status:** Accepted
- **Date:** <fill on adoption>
- **Supersedes:** the branch-protection clause of [0001](0001-trunk-based-workflow.md)
- **Superseded by:** —

## Context

ADR 0001 and the `git-workflow` skill describe `main` as GitHub branch-protected
(required PR, passing CI, linear history, no force-push, `enforce_admins=true`). The
actual repository has **no** such protection configured yet: the concrete protection
settings — CI-check names, required reviewers, the hosting platform itself — are
choices this project makes for itself, not properties a seed can assert on its
behalf. Claiming enforced protection the repo does not have is a doc-vs-reality
drift.

## Decision

We will treat `main` protection as a **target documented for adoption, not an
enforced invariant**. Until GitHub protection is configured, the PR-into-`main`
workflow (branch → PR → green gate → rebase-merge → delete) is followed **by
discipline, not enforced by GitHub**. The `git-workflow` skill keeps the
`gh api … branches/main/protection` recipe as the instruction to run to make
protection real. The never-force-push-`main` rule stands regardless of enforcement.

This supersedes **only** ADR 0001's branch-protection clause; the rest of 0001
(trunk-based, one-concern-per-PR, rebase-merge, green-to-merge) remains in force.

## Consequences

- The docs now match reality: no claim of enforcement the repo cannot back.
- This project must explicitly enable GitHub protection (the recipe is in the
  skill) — until it does, the always-green guarantee rests on discipline plus the
  pre-merge gate (critics + the `validate-config` hook), not on a server-side block.
- Loss: nothing mechanically prevents a direct push to `main` yet. Accepted as a
  starting point — enabling protection is a follow-up setup step, not a blocker.
