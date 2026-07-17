# 6. Milestone permission profiles: strict, auto (sandboxed), containment-gated bypass

- **Status:** Accepted
- **Date:** 2026-07-09
- **Supersedes:** — (extends the ADR 0004 loop; its strict behavior remains the default)
- **Superseded by:** —

## Context

ADR 0004's loop scopes each headless session with `--allowedTools` and treats any
`permission_denials` entry as fatal. The live smoke validated that design *and* exposed
its scaling limit: two of four runs died on a tool choice nobody predicted (the session
replicating a gate via un-allowlisted Bash). For a long-running milestone the
unpredictable surface is **Bash commands**, which cannot be enumerated up front; the
built-in tools (Read/Write/Edit/Agent/Skill/…) are few and enumerable.

Verified against the installed CLI (2.1.204) and current docs before deciding:

- `--permission-mode auto` exists: a separate **classifier model** reviews actions —
  blocking escalation beyond the request, unrecognized infrastructure, and actions
  driven by hostile content — with no routine prompts. In headless `-p`, repeated
  classifier blocks (3 consecutive / 20 total, non-configurable) **abort the session
  gracefully** instead of wedging. The bypass-mode docs themselves recommend it: "For
  background safety checks with far fewer permission prompts, use auto mode instead."
- The **native OS sandbox** (Seatbelt/bubblewrap; `sandbox` settings key) with
  `autoAllowBashIfSandboxed: true` auto-approves **any** Bash command that runs inside
  its filesystem/network/credential isolation — no per-command allowlisting.
  Unsandboxable commands fall back to the regular permission flow (denied headless).
  Explicit `deny` rules outrank everything in every mode. `--settings` accepts the
  sandbox block inline (flag verified to parse).
- `bypassPermissions` executes everything — including `.claude/` writes (≥2.1.126) —
  and the official guidance restricts it to containers/VMs, non-root, egress-limited.

## Decision

The milestone config gains `permission_profile` (default `strict`) and
`sandbox_allowed_domains`; the runner builds its permission flags, its flag probe, and
its denial policy from the profile:

1. **`strict`** (default; ADR 0004 behavior unchanged): `acceptEdits` + explicit
   `--allowedTools`; any `permission_denials` entry fails the run. For short,
   mechanical milestones with a knowable tool surface. Config authors allowlist their
   gates' own harmless commands — a doctrine-following session will self-verify.
2. **`auto`** (for long-running milestones): `--permission-mode auto` plus a generated
   `--settings` sandbox block (`allowRead`/`allowWrite: ["."]`,
   `autoAllowBashIfSandboxed: true`, `network.allowedDomains` from config). Denials are
   **logged, not fatal** — classifier blocks are by-design feedback the session reacts
   to; the CLI's own abort thresholds surface persistent blocking as a nonzero exit
   (runner exit 3), and the deterministic gates remain the arbiter of progress.
3. **`bypass`**: `--dangerously-skip-permissions`, **refused (exit 2) unless
   containment is attested** — `MILESTONE_CONTAINED=1` or `/.dockerenv` — mirroring the
   branch-guard pattern. Operating requirements per the official guidance: container/VM
   only, non-root, repo-only mount, egress allowlist, scoped API credential (not the
   host's `~/.claude`).

The zero-cost flag probe runs the **profile's actual flags**, so drift in
`--permission-mode auto`, `--settings`, or the bypass flag is caught before tokens are
spent. The deterministic layer — gates, runner+config sha trust boundary, branch guard,
per-iteration `--max-budget-usd`, watchdog, lock — is profile-independent and unchanged.

## Consequences

- The classifier is a model, not a boundary; the sandbox is a boundary. `auto` pairs
  them and keeps the deterministic layer as ground truth — that ordering is the safety
  argument, and it should not be weakened by cost-cutting the gates.
- Auto mode's defaults permit meaningful authority (reading `.env` and sending
  credentials to their matching API; pushing to the session's own branch). House rules
  belong in `permissions.deny` rules, which outrank everything in every mode.
- In `auto`, a silently-denied action can no longer fail the run directly — the ADR 0004
  worst-case (denied work passing a weak gate) is re-opened *unless gates are intrinsic*
  (build/test). The gate-quality requirement is therefore stronger in `auto` than in
  `strict`; existence-probe gates are acceptable only in `strict`.
- `bypass` lifts the `.claude/` write guard, so a contained bypass loop can hands-off
  build steering-layer content — dissolving ADR 0003's "cannot dogfood the template"
  corollary, inside a container only.
- Live validation of the `auto` profile (sandboxed-Bash auto-approval headless,
  classifier-abort surfacing as exit 3) is part of this change's smoke; the offline
  suite covers flag construction, denial tolerance, and the containment gate.
