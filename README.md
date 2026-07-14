# mrinal-skills

A personal Claude Code **plugin marketplace** — portable personal skills, version-controlled, with
zero manual sync across machines and repos. The idiomatic vehicle for keeping a personal skill set in
sync (per code.claude.com/docs: plugins, plugin-marketplaces, skills).

## Plugins

| Plugin | Scope | Contents |
|--------|-------|----------|
| `core` | user-level (all repos) | `cost-aware-delegation`, `deep-research-tiered` skills + `advisor-plus` agent |

More plugins are added as separate entries in `.claude-plugin/marketplace.json` (e.g. a future
`swift` plugin for Swift/iOS-only skills). Each plugin is its own subdirectory with its own
`.claude-plugin/plugin.json`.

## What belongs here vs. not

- **Belongs:** personal skills/agents that apply across repos and machines.
- **Does not belong:** repo-specific skills saturated with one project's policy (they live in that
  repo's `.claude/skills/`), and Apple's bundled Xcode skills (`swiftui-specialist`, etc.) that are
  re-exported per Xcode update and would go stale if committed — keep those at user level.

## Install

Test locally first (reads the filesystem directly — no push needed):

```bash
/plugin marketplace add ~/Developer/claude-skills
/plugin install core@mrinal-skills            # user scope: available in every repo
```

Pin a plugin to a single project instead of user scope:

```bash
/plugin install core@mrinal-skills --scope project   # writes .claude/settings.json (checked in)
```

### Cross-machine (after pushing to GitHub)

```bash
/plugin marketplace add mrinaldhillon/claude-skills   # once per machine
/plugin install core@mrinal-skills
```

New machine = rerun those two commands. Updates = push here, then `/plugin` update. No file copying.

## Layout

```
claude-skills/
├── .claude-plugin/marketplace.json   # this marketplace's catalog
└── core/                             # the `core` plugin
    ├── .claude-plugin/plugin.json
    ├── skills/<name>/SKILL.md        # auto-discovered
    ├── agents/<name>.md              # auto-discovered
    └── README.md                     # the plugin's inventory
```
