---
name: git-workflow
description: >-
  Use for the git/GitHub development flow — creating branches, opening and
  merging PRs, waiting on CI, branch protection. Trunk-based (GitHub Flow):
  branch off main → PR into main → gates green → rebase-merge → delete. Trigger
  before any branch/PR/CI/merge operation. Delegate CI-waits and routine gh ops
  to a Sonnet subagent; keep the merge decision on the main loop. Repo-agnostic;
  a repo may pin specifics (branch routing, required checks) in its own CLAUDE.md.
---

# Git / GitHub workflow (trunk-based, solo)

`main` is the only long-lived branch — always green. No `dev`, no release
branches. Enforce with a local hook that blocks direct commit/merge/push on `main`
plus GitHub branch protection (require PR, required status checks, linear history,
no force-push or delete, admins included). On plans/repos where protection is
unavailable, the hook plus discipline is the enforcement.

## The loop (the unit of change is a PR into main)

1. Branch off `origin/main`: milestone work → descriptively-named branch; small
   work → `fix/…`, `chore/…`, `docs/…`.
   `git switch -c <b> origin/main && git push -u origin <b>`.
2. Work in focused checkpoints; keep iterating with the repo's fast host-side loop
   (build + unit tests) once code exists.
3. All the PR's tasks done? Run the independent reviewer/auditor agents **once
   on the full branch diff** — never per commit, each scoped to the surface it
   audits (`orchestration` › Verification economics) — then PR into `main`:
   `gh pr create --base main` with the PR template checklist filled honestly.
4. **Green-to-merge** (the gate): CI green (the deliberate subset, in lockstep
   with the repo's documented commands); the step-3 review findings addressed.
   No human approval when solo.
5. `gh pr merge --rebase --delete-branch`. Squash only for noisy PRs.

## Coexisting with `superpowers:finishing-a-development-branch`

Both skills fire at the same moment — implementation done, time to integrate — and
they **disagree**. Know which one you're following.

| | `superpowers:finishing-a-development-branch` | this skill |
|---|---|---|
| Merge | `git checkout base && git pull && git merge <branch>` — a **merge commit** | `gh pr merge --rebase --delete-branch` — **linear history** |
| Gate | presents a 4-option menu and **waits for a human** | green-to-merge; no human approval when solo |
| Scope | local integration + worktree cleanup | PR-into-main, protection, required checks, CI delegation |

**Take from it:** verify tests pass *before* integrating, and its worktree cleanup —
both are good, and this skill doesn't cover them. **Don't take:** its merge commit
(breaks linear history) or its base-branch detection (the base is always `main`).

The human-gate difference is a genuine judgment call, not a bug in either. Solo on
your own repo, green CI is the gate. But when the PR is **self-created and
self-merged with no independent review**, prefer its ask — "green" proves the code
compiles, not that anyone looked at it.

## Pre-implementation branch routing (run before touching any file)

Before writing or editing anything, classify every change by concern and route it
to the right branch. One concern per branch/PR. A minimal generic split:

| Type | Branch prefix |
|------|---------------|
| Product/feature code + its own specs/ADRs/tests | milestone/feature name |
| Repo meta / workflow / tooling (`CLAUDE.md`, `.claude/**`, `.github/**`, `.gitignore`, CI config, dev-setup) | `chore/…` |
| Root lint/format configs | `chore/…`, unless 1:1 coupled to code landing in the same PR (e.g. adding a new source root to lint `included:`) — then it rides that branch |
| Docs & content (non-milestone) | `docs/…` |

If the task touches more than one type: cut the `chore/…` or `docs/…` branch off
`main` first, implement and PR it, then return to the feature branch. A feature PR
that also contains CI-config, `.claude/`, or `CLAUDE.md` edits is a red flag —
stop and split before opening the PR. A milestone ADR belongs on the milestone
branch with the code it decides; standalone doc work never does.

> **Individual repos may override this table** with a stricter routing decision of
> record in their own `CLAUDE.md` (e.g. a docs↔CI "lockstep" that overrides the
> `docs/…` default). This skill is the portable baseline; the repo's pin wins.

> **Parallel-subagent worktrees branch off the default branch, not your HEAD.**
> When you fan out file-mutating subagents in `isolation: worktree`, each worktree
> sees neither your uncommitted work nor the other workers' commits. Commit/stash
> first, and keep coupled writes single-threaded. Full caveat: the `orchestration`
> skill › Parallelism, isolation, and merge discipline.

## Delegate the mechanical parts to a Sonnet subagent

Waiting on / watching CI, polling run status, opening PRs, merging on green,
deleting branches are **mechanical** — do them in a **Sonnet subagent**, never on
the strongest model. Two reasons: cheaper model for low-reasoning polling, and the
subagent **absorbs the verbose `gh run watch` / CI / build output** and returns
only the verdict — keeping the main context clean. Pattern:

> Agent (model: sonnet): "Watch CI for branch B's HEAD to completion. Return:
> pass/fail, and if it failed, the failing job + step + the error tail. Do not
> paste full logs."

Keep the **judgment** on the main loop: diagnosing a CI failure, deciding the fix,
deciding whether to merge (see `cost-aware-delegation` and `orchestration`).

## Merge style + main protection

- **Rebase-and-merge** (default) — linear history. Squash for noisy PRs. **Never
  force-push `main`**; rebase a feature branch freely *before* merge. Delete merged
  branches.
- Enable protection via
  `gh api -X PUT repos/<owner>/<repo>/branches/main/protection`. When CI gains a
  job, **add it to the required status checks in the same PR's follow-up** — a
  required check that CI no longer runs blocks every merge; an unrequired new check
  gates nothing.

## CI notes

- CI is the **deliberate subset, never more**, in lockstep with the repo's
  documented command list. Typical gates: lint + format check, host unit tests, a
  build-only compile, and any schema/contract/catalog validation.
- Run the full local gate list before the PR, not just unit tests — the format
  *check* and strict lint are the usual discriminator between a green PR and a red
  round-trip.
