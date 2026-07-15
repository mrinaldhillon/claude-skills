# scaffold

The **project-enabled** half of the personal Claude Code layer — the milestone/ADR machinery
extracted from `claude-code-starter`. Where [`core`](../core) is broadly/globally enabled and
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
> `core`. These are bare-name **prose** references (no literal `subagent_type` dispatch): they resolve
> by description and let a repo's own tuned agent of the same name win, so they are intentionally not
> `core:`-qualified.

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

(Project-scoped enablement is the same mechanism handled-next already uses for
`claude-xcindex@claude-community`.) Because it is project-scoped, the checkpoint/context hooks fire
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
| hook    | `checkpoint`           | Stop + PreCompact: commit durable state (`.context/`, `docs/decisions/`) on non-`main` branches. No-ops when the substrate is absent; activates once you create `.context/` (see `references/project-setup/`). |
| hook    | `subagent-trail`       | SubagentStop: append-only breadcrumb index of Agent-tool subagent transcripts for post-compaction recovery. |
| hook    | `validate-config`      | PostToolUse(Write\|Edit): validate `.claude/` JSON + frontmatter on edit. |

Skills/agents/commands auto-discover from their directories; hooks load from `hooks/hooks.json` via
`${CLAUDE_PLUGIN_ROOT}`, and **merge** with your user/project hooks.

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

> **`context-nudge` is intentionally not here.** Its substrate — `.claude/state/context-usage.json` —
> is written by a statusline bridge (`statusline.sh` + the `statusLine` settings key), and a plugin's
> `hooks.json` cannot contribute a `statusLine`. Shipping the hook alone would be a permanently-dead
> artifact. `statusline.sh` + `context-nudge.sh` are documented, project-local files instead — see
> [`references/project-setup/`](references/project-setup) — copied by hand into a repo's `.claude/`,
> never shipped by the plugin.

## No generator — `references/project-setup` instead

There is no bootstrap/adopt command and never will be: a plugin that *copies* plugin-coupled files
(`settings.json`, `CLAUDE.md`) into a project owns a drift liability forever — the copy silently
rots the moment the plugin's own hooks or conventions move on. `scaffold` ships the logic, the
hooks, and the milestone runner; **project setup is a documented, hand-run procedure**, not a
script. See [`references/project-setup/README.md`](references/project-setup/README.md) for the
full guide (enabling the plugins, the `settings.json` complement rule, the `.context/`/ADR
conventions, and a migration checklist for existing starter-derived repos) and
[`references/project-setup/`](references/project-setup) for the reference examples themselves
(`settings.example.json`, `statusline.sh`, `context-nudge.sh`, the ADR/doc skeletons).

The old cross-repo template-diff step remains obsoleted by plugin versioning: its job was to
git-diff a project's *forked copies* of the shared steering layer against the upstream template
tip, which is just `/plugin update` once that layer ships as versioned plugins. It should stay
dropped, not ported; only *substrate reconciliation* (a project's own
`CLAUDE.md`/ADR-template/`.context` contracts vs current defaults) is a residual job, covered by
the migration checklist above.

`scaffold` is usable in any repo that already has (or hand-creates, per the guide above) the
`docs/` + `.context/` layout; the workflow skills, commands, hooks, and auditor all work standalone.
