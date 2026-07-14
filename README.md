# mrinal-skills

A personal Claude Code **plugin marketplace** — portable personal skills, agents, hooks, and an output
style, version-controlled, with zero manual sync across machines and repos. The idiomatic vehicle for
keeping a personal steering layer in sync (per code.claude.com/docs: plugins, plugin-marketplaces, skills).

## Plugins

| Plugin | Scope | Contents |
|--------|-------|----------|
| [`core`](./core) | user-level (all repos) | 4 skills (`cost-aware-delegation`, `orchestration`, `git-workflow`, `deep-research-tiered`), 5 agents (`advisor-plus`, `code-reviewer`, `search`, `doc-sync`, `config-auditor`), the `distinguished-engineer` output style, 2 guard hooks (`block-main-writes`, `guard-secrets`) |
| [`scaffold`](./scaffold) | per-repo (opt-in) | 3 skills (`milestone-workflow`, `dev-workflow`, `skill-maintenance`), 4 commands (`/adr`, `/goal`, `/milestone`, `/scaffold:milestone-run`), the `determinism-auditor` agent, 3 hooks (`checkpoint`, `subagent-trail`, `validate-config`), and `references/` for by-hand project setup. **Requires `core`.** |

`core` is broadly/globally enabled and project-agnostic. `scaffold` is the project-enabled half: turn it on
per-repo, and it assumes a concrete `docs/` + `.context/` layout (hand-set up per
[`scaffold/references/project-setup/`](scaffold/references/project-setup/) — there is no generator).
`scaffold` declares a hard dependency on `core` in its `plugin.json` (`"dependencies": ["core"]`), so
enabling `scaffold` auto-enables `core`. Each plugin's own README is the authoritative inventory. Further
plugins are added as new entries in `.claude-plugin/marketplace.json`.

## What belongs here vs. not

- **Belongs:** personal skills/agents/hooks that apply across repos and machines.
- **Does not belong:** repo-specific skills saturated with one project's policy (they live in that repo's
  `.claude/skills/`), and Apple's bundled Xcode skills (`swiftui-specialist`, etc.) that are re-exported per
  Xcode update and would go stale if committed — keep those at user level.

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
