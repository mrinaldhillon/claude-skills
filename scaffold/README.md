# scaffold

The **project-enabled** half of the personal Claude Code layer — the milestone/ADR/dev-loop machinery
extracted from `claude-code-starter`. Where [`core`](../core) is broadly/globally enabled and
project-agnostic, `scaffold` is meant to be turned on **per-repo** and assumes (establishes) a
concrete layout: `docs/decisions/` for ADRs, `docs/playbooks/<milestone>.md` for milestone specs,
`.context/` for resume/checkpoint state, `.claude/state/` for the context-usage bridge.

Enable it only in repos that use that layout — a namespaced plugin, so `scaffold:milestone-workflow`
never shadows a repo's own tuned `milestone-workflow`.

> **Requires `core`.** A hard dependency, declared in `plugin.json` (`"dependencies": ["core"]`), so
> enabling `scaffold` auto-enables `core`. The coupling is real: `milestone-workflow` reaches for the
> `code-reviewer` and `git-workflow` components; `/goal`, `/milestone`, and `skill-maintenance` reach
> for `doc-sync`; and `/milestone` + `subagent-trail` name `orchestration` — all of which ship in
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
| skill   | `milestone-workflow`   | Load the playbook, work the ordered workstreams, capture forward-looking data, self-verify before claiming a gate, refresh status prose at milestone completion. Driven by `/goal` and `/milestone`. |
| skill   | `dev-workflow`         | Keep the inner dev/test loop fast and **offline**; standard task taxonomy (`build/test/test-offline/vet/lint/ci/watch`); propose tooling improvements on friction. |
| skill   | `skill-maintenance`    | When to suggest an existing skill, when to author a new project skill (on the second recurrence of a need), and keeping skills/docs current in-PR. |
| command | `/adr`                 | Scaffold the next ADR in `docs/decisions/` from `TEMPLATE.md` (mechanical; author fills the reasoning). |
| command | `/goal`                | Dispatch a milestone build end-to-end via `milestone-workflow`. |
| command | `/milestone`           | Generic per-milestone driver (copy into named `/m1`, `/m2`, … as milestones firm up). |
| agent   | `determinism-auditor`  | Advisory pre-scan for the five determinism/hot-path footguns; genericized (no `<PLACEHOLDER>`). Relevant only to projects with a replay/append-only invariant. Sonnet; terminal. |
| hook    | `checkpoint`           | Stop + PreCompact: commit durable state (`.context/`, `docs/decisions/`) on non-`main` branches. No-ops when the substrate is absent; activates once bootstrap (or you) create `.context/`. |
| hook    | `subagent-trail`       | SubagentStop: append-only breadcrumb index of Agent-tool subagent transcripts for post-compaction recovery. |
| hook    | `validate-config`      | PostToolUse(Write\|Edit): validate `.claude/` JSON + frontmatter on edit. |

Skills/agents/commands auto-discover from their directories; hooks load from `hooks/hooks.json` via
`${CLAUDE_PLUGIN_ROOT}`, and **merge** with your user/project hooks.

> **`context-nudge` is intentionally not here.** Its substrate — `.claude/state/context-usage.json` —
> is written by a statusline bridge (`statusline.sh` + the `statusLine` settings key), and a plugin's
> `hooks.json` cannot contribute a `statusLine`. Shipping the hook alone would be a permanently-dead
> artifact. It returns bundled with `project-bootstrap`, which owns the statusline bridge it depends on.

## Not here yet — `project-bootstrap` and `template-sync`

Deliberately deferred, because the plugin model reshapes both:

- **`template-sync` is obsoleted by plugin versioning.** Its whole job was to git-diff a project's
  *forked copies* of the shared steering layer against the upstream template tip. Once that layer
  ships as versioned `core`/`scaffold` plugins, "sync the shared layer" is just `/plugin update`.
  Porting it verbatim would be a plugin skill instructing you to re-sync the very artifacts the
  plugin delivers. It should be dropped, not ported; only *substrate reconciliation* (a project's
  own `CLAUDE.md`/ADR-template/`.context` contracts vs current defaults) is a residual job.
- **`project-bootstrap` needs a rewrite plus bundled substrate.** In the template repo it *fills a
  `<PLACEHOLDER>` skeleton and self-deletes*; a plugin ships no in-repo skeleton and is read-only, so
  bootstrap must instead **generate** the substrate (docs skeletons, the process ADRs `0000–0007`,
  `.context/` contracts, `docs/decisions/TEMPLATE.md`, `milestones/`, `milestone-runner.sh`) into the
  repo from bundled plugin resources (~1,000 lines). That's a distinct deliverable, tracked
  separately.

Until then, `scaffold` is usable in any repo that already has (or hand-creates) the `docs/` +
`.context/` layout; the workflow skills, commands, hooks, and auditor all work standalone.
