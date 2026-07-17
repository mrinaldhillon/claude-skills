# mrinal-skills

A personal Claude Code **plugin marketplace** — portable personal skills, agents, hooks, and an output
style, version-controlled, with zero manual sync across machines and repos. The idiomatic vehicle for
keeping a personal steering layer in sync (per code.claude.com/docs: plugins, plugin-marketplaces, skills).

## Plugins

| Plugin | Scope | Contents |
|--------|-------|----------|
| [`core`](./core) | user-level (all repos) | 4 skills (`cost-aware-delegation`, `orchestration`, `git-workflow`, `deep-research-tiered`), 5 agents (`advisor-plus`, `code-reviewer`, `search`, `doc-sync`, `config-auditor`), the `distinguished-engineer` output style, 1 guard hook (`guard-secrets`) |
| [`scaffold`](./scaffold) | per-repo (opt-in) | 2 skills (`milestone-workflow`, `skill-maintenance`), 4 commands (`/adr`, `/goal`, `/milestone`, `/scaffold:milestone-run`), the `determinism-auditor` agent, 4 hooks (`block-main-writes`, `checkpoint`, `subagent-trail`, `validate-config`), and `references/` for by-hand project setup. **Requires `core`.** |

`core` is broadly/globally enabled and project-agnostic. `scaffold` is the project-enabled half: turn it on
per-repo, and it assumes a concrete `docs/` + `.context/` layout (hand-set up per
[`scaffold/references/project-setup/`](scaffold/references/project-setup/) — there is no generator).
`scaffold` declares a hard dependency on `core` in its `plugin.json` (`"dependencies": ["core"]`), so
enabling `scaffold` auto-enables `core`. Each plugin's own README is the authoritative inventory. Further
plugins are added as new entries in `.claude-plugin/marketplace.json`.

> **TODO — `/scaffold:adopt` generator:** replace the by-hand `scaffold/references/project-setup/` steps
> with a single command that bootstraps a repo's `.context/`, ADR conventions, and `settings.json` from
> templates bundled in the plugin — one command instead of hand-copying, updatable via `/plugin update`.
> Not built yet; the by-hand setup works today.

## What belongs here vs. not

- **Belongs:** personal skills/agents/hooks that apply across repos and machines.
- **Does not belong:** repo-specific skills saturated with one project's policy (they live in that repo's
  `.claude/skills/`), and Apple's bundled Xcode skills (`swiftui-specialist`, etc.) that are re-exported per
  Xcode update and would go stale if committed — keep those at user level.
- **Does not belong: anything `superpowers` already does better** — see below.

## Relationship to `superpowers`

[`superpowers@claude-plugins-official`](https://github.com/obra/superpowers) is assumed present and is
the **process layer**: brainstorming → writing-plans → executing-plans / subagent-driven-development →
TDD → systematic-debugging → verification-before-completion → writing-skills. This marketplace does
**not** re-implement any of it. The division:

| Concern | Owner |
|---|---|
| How to write, test, and structure a skill | `superpowers:writing-skills` (+ `skill-creator`) |
| Executing a written plan task-by-task; dispatching per-task subagents | `superpowers:executing-plans` / `subagent-driven-development` |
| How to *word* a subagent dispatch (pack context, scope, output format) | `superpowers:dispatching-parallel-agents` |
| Evidence before claiming done | `superpowers:verification-before-completion` |
| **Which model runs it, and what it costs** — concrete Haiku/Sonnet/strong routing, `opts.model` per Workflow stage, the `budget` guard, checkpoint-before-loss | **`core`** — see the note below; superpowers tiers by *role* but never names models or Workflow primitives |
| **Trunk-based git policy** — the *PR* merge method (rebase vs squash), branch routing, protection, required checks, CI delegation | **`core:git-workflow`** — superpowers defines only a *local* `git merge` in `finishing-a-development-branch`, and never a GitHub PR merge method |
| Milestone substrate (`docs/playbooks/`, `.context/`, the post-merge status sweep) | **`scaffold:milestone-workflow`** |
| Agents, commands, output style, guard hooks | **`core`/`scaffold`** — superpowers ships none of these |

> **Credit where due — the tiering overlap is real, and `core` is not the only one who thought of it.**
> `superpowers:subagent-driven-development` has a full *Model Selection* section that independently
> reaches the same conclusion: *"Use the least powerful model that can handle each role"* and
> *"Always specify the model explicitly when dispatching a subagent. An omitted model inherits your
> session's model — often the most capable and most expensive."* That is `cost-aware-delegation`'s
> thesis, arrived at separately. Two things keep `core`'s version: SDD's guidance fires only *inside*
> subagent-driven-development, whereas `cost-aware-delegation` is the always-on routing policy; and
> SDD is deliberately model-agnostic where `core` is Claude-Code-concrete (named tiers, `opts.model`,
> the `budget` object, the git-ops→Sonnet rule). The traffic runs both ways: SDD's *turn count beats
> token price* insight was **missing** from `cost-aware-delegation` and has been adopted into it.

**This coupling is by discipline, not declared.** Cross-marketplace dependencies *are* expressible
(`{"name": "superpowers", "marketplace": "claude-plugins-official"}` plus
`allowCrossMarketplaceDependenciesOn` in `marketplace.json`), but they are **hard** — there is no
documented optional/soft dependency, and a missing dep makes *enable fail*. Making `core` — whose whole
premise is portability — hard-fail without a third-party plugin is a worse trade than a documented
assumption. So the deferrals above are prose pointers: if `superpowers` is absent, you lose the
pointed-to guidance but `core` still loads. Same reasoning as
[ADR 0002](scaffold/references/project-setup/decisions/0002-branch-protection-by-discipline.md):
don't assert enforcement the repo doesn't have.

> One live conflict, documented rather than resolved: `superpowers:finishing-a-development-branch`
> merges with a **merge commit** behind a mandatory human menu; `core:git-workflow` **rebase-merges**
> with no human gate when solo. See that skill's *Coexisting with* section.

## Install

Test locally first (reads the filesystem directly — no push needed):

```bash
/plugin marketplace add <path-to-your-local-clone>   # e.g. ~/src/claude-skills
/plugin install core@mrinal-skills                   # user scope: available in every repo
```

### Enable `scaffold` per-project

`scaffold` is meant to be opted into by the repos that use its `docs/` + `.context/` layout, via the
project's checked-in `.claude/settings.json`:

```jsonc
// <repo>/.claude/settings.json
{
  "enabledPlugins": {
    "core@mrinal-skills": true,
    "scaffold@mrinal-skills": true
  }
}
```

Its checkpoint/context hooks then fire **only** in repos that opted in — never globally.

### Cross-machine (after pushing to GitHub)

```bash
/plugin marketplace add mrinaldhillon/claude-skills   # once per machine
/plugin install core@mrinal-skills
```

New machine = rerun those two commands. Updates = push here, then `/plugin update`. No file copying.

See [`docs/user-setup.md`](docs/user-setup.md) for the full one-time machine setup (including the
curated `@claude-plugins-official` set a project's `settings.example.json` enables) plus the
user-level `~/.claude/CLAUDE.md` operating-discipline text a plugin cannot deliver. Per-project setup
(the `docs/` + `.context/` layout, ADR seeding, etc.) is documented in
[`scaffold/references/project-setup/README.md`](scaffold/references/project-setup/README.md).

## Invocation & namespacing

Installed components are namespaced by plugin (`core:…`, `scaffold:…`), so they never shadow a repo's own
tuned project skills/agents of the same name. Skills auto-trigger by their `description` as usual; explicit
forms are `/core:git-workflow`, subagent type `core:code-reviewer`, etc. Hooks activate automatically and
**merge** with your user/project hooks. See each plugin's README for the full invocation table.

### Extending a core skill in your repo

Namespacing cuts both ways: because a plugin skill is permanently namespaced, a project
**cannot override or extend it by same-naming**. A `.claude/skills/orchestration/` does *not*
replace `core:orchestration` — the two coexist with near-duplicate descriptions (ambiguous
trigger), and the copy then drifts behind core. There is no skill inheritance. To specialize a
core skill for one repo, **add a companion — never fork:**

- **Companion skill** — a *distinct-named* project skill, `<skill>-<yourrepo>` (e.g.
  `orchestration-acme`), carrying only that repo's concrete bindings. **Name it in the repo's
  `CLAUDE.md`** so it reliably co-fires with the core skill — description-based co-triggering of
  two skills isn't guaranteed, and `CLAUDE.md` is always in context.
- **CLAUDE.md pins** — decisions of record and always-relevant rules.

Two rules keep it safe: **guards stay in core** (anything budget- or safety-critical lives in the
core skill and/or `CLAUDE.md`, never *only* in a companion whose co-firing isn't guaranteed — a
companion that fails to load must cost you *examples*, never a guard); and **the companion binds,
it doesn't restate** (it fills the core skill's generic slots with concrete gates/agents/paths).
The core skills built for this — `core:orchestration` and `core:git-workflow` — each carry an
**"Extending this skill"** section naming their binding slots.

## Layout

```
claude-skills/
├── .claude-plugin/marketplace.json   # this marketplace's catalog (lists core + scaffold)
├── LICENSE                           # MIT
├── scripts/validate.sh               # self-test: manifests + component frontmatter + hooks
├── core/                             # the `core` plugin
│   ├── .claude-plugin/plugin.json
│   ├── skills/<name>/SKILL.md        # auto-discovered
│   ├── agents/<name>.md              # auto-discovered
│   ├── output-styles/<name>.md       # registered via plugin.json `outputStyles`
│   ├── hooks/hooks.json + *.sh       # loaded from hooks.json
│   └── README.md                     # the plugin's inventory
└── scaffold/                         # the `scaffold` plugin (requires core)
    ├── .claude-plugin/plugin.json
    ├── skills/<name>/SKILL.md
    ├── commands/<name>.md
    ├── agents/<name>.md
    ├── hooks/hooks.json + *.sh
    ├── scripts/                       # milestone-runner.sh
    ├── references/                    # decisions/ (machinery ADRs) + project-setup/ (adoption docs)
    └── README.md
```

## Validate

`scripts/validate.sh` is the marketplace's self-test — it checks that both manifests are valid JSON, every
declared plugin resolves, every skill/agent/command carries the frontmatter the loader needs, and every hook
script referenced in `hooks.json` exists with a shebang and exec bit. Run it before pushing:

```bash
./scripts/validate.sh          # exit 0 = clean
```

CI runs the same script (plus `shellcheck`) on every push and PR via `.github/workflows/validate.yml`.
Runtime install (`/plugin install`) is verified manually — it is interactive and cannot be scripted.
