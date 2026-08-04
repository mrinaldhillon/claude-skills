# scaffold

The **project-enabled** half of the personal Claude Code layer — the milestone/ADR machinery
generalized from a personal scaffold template. Where [`core`](../core) is broadly/globally enabled and
project-agnostic, `scaffold` is meant to be turned on **per-repo** and assumes (establishes) a
concrete layout: `docs/decisions/` for ADRs, `docs/playbooks/<milestone>.md` for milestone specs,
`.context/` for resume/checkpoint state, `.claude/state/` for the context-usage bridge.

Enable it only in repos that use that layout — a namespaced plugin, so `scaffold:milestone-workflow`
never shadows a repo's own tuned `milestone-workflow`.

> **Requires `core`.** A hard dependency, declared in `plugin.json` (`"dependencies": ["core"]`), so
> enabling `scaffold` auto-enables `core`. The coupling is real: `milestone-workflow` reaches for the
> `code-reviewer` and `git-workflow` components and for `doc-sync` (as do `/goal` and `/milestone`);
> `skill-maintenance` names `doc-sync` only to disclaim it — the in-PR sync rule is discipline rule 6,
> not that skill's; and `/milestone` + `subagent-trail` name `orchestration` — all of which ship in
> `core`. These are bare-name **prose** references (no literal `subagent_type` dispatch): they name
> `code-reviewer` / `doc-sync` / `orchestration` in prose and resolve by description. They are
> intentionally not `core:`-qualified so that in a repo which tunes one of these, the tuned copy — which
> **coexists** with the plugin's namespaced `core:…` copy, neither shadowing the other — is available to
> satisfy the reference.

## Enable per-project

Add the marketplace once, then opt in from the project's `.claude/settings.json`:

```jsonc
// <repo>/.claude/settings.json
{
  "enabledPlugins": {
    "core@mrinal-skills": true,
    "scaffold@mrinal-skills": true
  }
}
```

(Project-scoped enablement is the same mechanism a repo already uses for any other
project-scoped plugin.) Because it is project-scoped, the checkpoint/context hooks fire
**only** in repos that opted in — never globally.

## Contents

| Kind    | Name                   | What it does |
|---------|------------------------|--------------|
| skill   | `milestone-workflow`   | The milestone **substrate**: playbook + preconditions, forward-looking data capture, the project gate list, the in-PR context rule, and the status-prose sweep at milestone completion. Plan *execution* defers to `superpowers:executing-plans`. Driven by `/goal` and `/milestone`. |
| skill   | `skill-maintenance`    | The **trigger only**: author a project skill on the second recurrence of a knowledge need, and what belongs in one. How to write/test it is `superpowers:writing-skills`. |
| command | `/adr`                 | Scaffold the next ADR in `docs/decisions/` from `TEMPLATE.md` (mechanical; author fills the reasoning). |
| command | `/goal`                | Dispatch a milestone build end-to-end via `milestone-workflow`. |
| command | `/milestone`           | Generic per-milestone driver (copy into named `/m1`, `/m2`, … as milestones firm up). |
| command | `/scaffold:milestone-run` | Prints the exact terminal command to run the milestone loop (resolves the plugin path); the runner itself (`scripts/milestone-runner.sh`) spawns fresh `claude -p` sessions, so it must run from a plain terminal, not nested in this session. |
| agent   | `determinism-auditor`  | Advisory pre-scan for the five determinism/hot-path footguns; genericized (no `<PLACEHOLDER>`). Relevant only to projects with a replay/append-only invariant. Sonnet; terminal. |
| hook    | `block-main-writes`    | PreToolUse(Bash): denies `git commit`/`merge`/`push` when the repo the command **targets** is on `main` (trunk-based backstop). It does not parse shell — it reads one **opening** `cd <literal path>` and a literal `git -C <path>`, else the session's `cwd`, and **denies** anything it cannot determine literally rather than assuming. So a commit from a worktree on a branch is allowed while the anchor checkout sits on `main`, and `git -C <main-repo> push` is denied while the session sits on a branch. Project-scoped here so trunk-PR discipline is **opt-in per repo**, not global — moved out of `core` for exactly that reason. |
| hook    | `checkpoint`           | PreCompact: commit durable state (`.context/`, `docs/decisions/`) on non-`main` branches; the milestone runner also calls it directly at iteration boundaries. Deliberately not wired to Stop — a per-turn trigger landed a commit every turn, interleaving automation commits with in-flight work. No-ops when the substrate is absent; activates once you create `.context/` (see `references/project-setup/`). Retries under index.lock contention from parallel subagents, then skips calmly (best-effort; the next checkpoint retries). |
| hook    | `context-nudge`        | UserPromptSubmit + PostToolUse(*): inject a checkpoint nudge at 40% (watch) / 45% (land) context usage — the defaults; both are configurable, see Threshold configuration — read from the status-line bridge (`.claude/state/context-usage.json`). The land message names the same paths `checkpoint` commits — same env vars, same defaults (see Path configuration) — so it never tells a session to write what nothing preserves. Session-identity guard: silent when the bridge belongs to another session sharing the checkout (the cross-session leak an mtime check cannot catch). Cheap no-op until the project wires the bridge (`references/project-setup/statusline.sh`). ADR 0008. |
| hook    | `resume-inject`        | SessionStart(compact\|clear): re-inject `.context/RESUME.md` into the fresh window after an autocompact or `/clear` — the read-back complement to `checkpoint`'s write, closing the checkpoint→resume loop. Reads from disk, never from git, so it works whether or not the project tracks the file. Assigns authority by kind: the file wins on the next action and durable pointers; after an autocompact the auto-summary may hold fresher mid-task detail. No-op when `RESUME.md` is absent. |
| hook    | `subagent-trail`       | SubagentStop: append-only breadcrumb index of Agent-tool subagent transcripts for post-compaction recovery. |
| hook    | `validate-config`      | PostToolUse(Write\|Edit): validate `.claude/` JSON + frontmatter on edit. |

Skills/agents/commands auto-discover from their directories; hooks load from `hooks/hooks.json` via
`${CLAUDE_PLUGIN_ROOT}`, and **merge** with your user/project hooks.

### Path configuration (`settings.json` > `env`)

`checkpoint` and `context-nudge` resolve the same two paths from the environment, so a project whose
layout differs from the defaults configures it once and both agree. Set them in the project's
`.claude/settings.json` under `env`:

| Variable | Default | What it names |
|---|---|---|
| `CLAUDE_ADR_DIR` | `docs/decisions` | Where new ADRs land — committed by `checkpoint`, named in `context-nudge`'s land message. |
| `CLAUDE_PROJECT_CONTEXT` | `.context/project-context.md` | The project-context document. Point it at `.context/RESUME.md` to collapse the two into one file; the nudge then omits the separate "update project-context" step rather than naming a file the project does not keep. |

`.context/RESUME.md` is **not** configurable — `checkpoint` writes it and `resume-inject` reads it
from a literal path, deliberately, so an override on one can never silently orphan the other.

Two properties worth knowing. **A project may gitignore `.context/RESUME.md`**: per-checkout state
never converges between branches, so tracking it manufactures a rebase conflict on every branch that
outlives one session. `checkpoint` then skips it instead of failing, and the resume loop is
unaffected because `resume-inject` reads from disk, never from git. And **`context-nudge` emits the
project-context step only when that file exists and is distinct from the resume pointer** — a session
told to update a missing file helpfully creates one, resurrecting a document the project removed on
purpose.

> **Testing note.** Because both hooks read these variables, the suites that exercise them
> (`test-checkpoint`, `test-context-nudge`, `test-milestone-runner`) `unset` both at the top. A
> developer running the suite from a checkout that wires them would otherwise test the *host's*
> layout while CI — where they are unset — tests the defaults. That split hides real breaks behind a
> green CI. For the same reason `test-context-nudge` also unsets the two threshold variables below
> **and** `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` — a suite run from inside a milestone-runner session
> inherits that one and would silently exercise the clamp path.

> **Both skills are deliberately partial** — they carry only what `superpowers` doesn't. Plan
> execution, skill authoring, and the evidence-before-done gate are its job; see the marketplace
> README's [Relationship to `superpowers`](../README.md#relationship-to-superpowers). The coupling is
> by discipline: absent `superpowers`, these skills still load, but their deferrals point nowhere.
>
> **`dev-workflow` was a skill here until it wasn't.** Its content — `make` targets, a Go toolchain, a
> tmux layout — is a *project's* task taxonomy, which a plugin cannot assert on the project's behalf.
> It now lives as a reference example at
> [`references/project-setup/docs/dev-workflow.md`](references/project-setup/docs/dev-workflow.md),
> alongside the other substrate you adapt by hand. Same reasoning as the no-generator rule below.

### Threshold configuration (`settings.json` > `env`)

`context-nudge` fires at two percentages of the context window used. The defaults land early and
leave wide headroom under auto-compact — the asymmetry is the point: landing early costs one cheap
`/clear`, landing late costs the turn to a summary. A project on a 1M window, or one that checkpoints
on a different beat, moves them:

| Variable | Default | What it sets |
|---|---|---|
| `CLAUDE_NUDGE_WATCH_PCT` | `40` | Watch band — finish the current micro-task, then checkpoint. |
| `CLAUDE_NUDGE_LAND_PCT` | `45` | Land band — checkpoint, commit, and ask the user to `/clear`. |

Both are integers `1`–`99` and are validated **as a pair**: if either is out of range, non-numeric, or
`watch > land`, *both* overrides are discarded and 40/45 apply, with one line on stderr saying so
(visible under `claude --debug`; stdout can't carry it, since on `UserPromptSubmit` stdout *is* the
injection channel and a warning there would reach Claude dressed as the notice). Half-applying a pair
is the failure worth avoiding — a surviving override can invert `watch <= land`, which makes the
watch band unreachable and fires the land message where the watch message belongs. Setting the two
equal is legal and deliberate: it collapses them into a single land-now notice with no early warning.

**The land threshold is clamped below auto-compact.** Auto-compact is the backstop, not the boundary
(ADR 0004 §5): a nudge at or above the compaction trigger never precedes the summary, and the whole
checkpoint-then-`/clear` loop is defeated. When `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` is visible in the
hook's environment — set in `settings.json` > `env`, or exported around each spawned session by
`scripts/milestone-runner.sh` (`AUTOCOMPACT_PCT`, default 70) — a land at or above it is clamped to
one point below, the watch band follows it down if needed, and the clamp is reported on stderr. It
clamps rather than rejects because the value that most often violates the invariant is a *default*
the project never chose — a land it never set, against a trigger it did. The hook can only see that
env var: the CLI's built-in trigger and `autoCompactEnabled` are invisible to it, so a project that
relies on the built-in default is responsible for keeping its own land threshold under it.
Best-effort by construction — the clamp assumes the statusline's `context_window.used_percentage` and
the auto-compact trigger are percentages of the same window, which is the assumption ADR 0003 §2 and
0004 §5 already make in placing the nudge bands under the trigger; the clamp inherits it rather than
adding it.

The timers (`COOLDOWN_S`, `STALE_S`) are deliberately **not** configurable — they tune injection
noise and staleness tolerance, not checkpoint policy, and their values are load-bearing for the
headless case (see the file's header comment).

> **`context-nudge` ships here since 0.7.0** (ADR
> [0008](references/decisions/0008-graduate-context-nudge-into-plugin.md), reversing the earlier
> "intentionally not here" stance). The split is structural: a plugin cannot set the `statusLine`
> settings key (only `agent`/`subagentStatusLine` are plugin-settable), so the thin, stable bridge
> writer — `statusline.sh` — stays a project-local copy, while the complex, evolving hook half now
> updates by version bump instead of rotting as a hand copy. Without the bridge the hook is a ~1 ms
> no-op, not a dead artifact. **Consumers upgrading to 0.7.0 must delete their project-side
> `context-nudge` copy and its `settings.json` wiring in the same change** — hooks merge, so any
> overlap double-fires the nudge on every tool call.

## No generator — `references/project-setup` instead

There is no bootstrap/adopt command and never will be: a plugin that *copies* plugin-coupled files
(`settings.json`, `CLAUDE.md`) into a project owns a drift liability forever — the copy silently
rots the moment the plugin's own hooks or conventions move on. `scaffold` ships the logic, the
hooks, and the milestone runner; **project setup is a documented, hand-run procedure**, not a
script. See [`references/project-setup/README.md`](references/project-setup/README.md) for the
full guide (enabling the plugins, the `settings.json` complement rule, the `.context/`/ADR
conventions, and a migration checklist for existing starter-derived repos) and
[`references/project-setup/`](references/project-setup) for the reference examples themselves
(`settings.example.json`, `statusline.sh`, the ADR/doc skeletons).

The old cross-repo template-diff step remains obsoleted by plugin versioning: its job was to
git-diff a project's *forked copies* of the shared steering layer against the upstream template
tip, which is just `/plugin update` once that layer ships as versioned plugins. It should stay
dropped, not ported; only *substrate reconciliation* (a project's own
`CLAUDE.md`/ADR-template/`.context` contracts vs current defaults) is a residual job, covered by
the migration checklist above.

`scaffold` is usable in any repo that already has (or hand-creates, per the guide above) the
`docs/` + `.context/` layout; the workflow skills, commands, hooks, and auditor all work standalone.
