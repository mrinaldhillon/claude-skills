# core

Cross-repo personal skills that apply to any project, plus one tier-up review agent. Repo-specific
skills (e.g. handled-next's `orchestration`, `git-workflow`) deliberately stay in their own repo's
`.claude/skills/` — this plugin holds only what is genuinely project-agnostic.

## Contents

| Kind  | Name                     | What it does |
|-------|--------------------------|--------------|
| skill | `cost-aware-delegation`  | Routes mechanical, low-judgment work to a cheaper Sonnet subagent; keeps judgment-heavy work on the strong model; verifies delegated output. |
| skill | `deep-research-tiered`   | Tiered, budget-guarded, checkpointed fan-out research (web search → fetch → verify → synthesize) with per-stage model pins. |
| agent | `advisor-plus`           | Tier-up second opinion on the main loop's own work (designs, plans, diffs). Caller selects the model one tier above the session model. |

Skills and the agent are auto-discovered from `skills/` and `agents/` — they are **not** listed in
`plugin.json`; the directory layout is the source of truth.

## Invocation

Once installed from the `mrinal-skills` marketplace, components are namespaced:

- Skills auto-trigger by their `description` exactly as user-level skills do — the namespace does not
  change that. Explicit slash form: `/core:cost-aware-delegation`, `/core:deep-research-tiered`.
- Agent: dispatch as subagent type `core:advisor-plus`.

> **Migration note:** any prose that references these by bare name (e.g. `~/.claude/CLAUDE.md`'s
> "the `cost-aware-delegation` skill", "the `advisor-plus` agent") keeps working because
> auto-triggering is by description. Only *explicit* `/name` or bare-`subagent_type` invocations need
> updating to the `core:` form once the user-level originals are removed.
