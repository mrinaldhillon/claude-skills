# core

Cross-repo personal Claude Code layer — skills, agents, an output style, and a universal secret-guard hook
that apply to *any* project. This plugin holds only what is genuinely project-agnostic; repo-specific
pins (branch-routing tables, named gates, decisions of record) stay in each repo's own `.claude/` and
`CLAUDE.md`; the milestone/ADR machinery lives one level up, in the sibling `scaffold` plugin.

`orchestration` and `git-workflow` were generalized from tuned project skills; the four agents,
the output style, and the guard hook came from a personal scaffold template — in both cases with the
project-specific coupling stripped to portable defaults. Each repo's `CLAUDE.md`/`.claude/` may still
override or extend these (e.g. a stricter branch-routing decision of record, a tuned reviewer).

## Contents

| Kind         | Name                     | What it does |
|--------------|--------------------------|--------------|
| skill        | `cost-aware-delegation`  | Routes mechanical, low-judgment work to a cheaper Sonnet subagent; keeps judgment-heavy work on the strong model; verifies delegated output. **Sonnet is the subagent floor** — turn count beats token price. |
| skill        | `orchestration`          | The full tiered orchestrator-worker fan-out model behind `cost-aware-delegation`: per-stage model pins, budget guard, workers-vs-critics, deterministic gates outrank LLM judges, coupled-write single-threading. Prompt craft defers to `superpowers:dispatching-parallel-agents`. |
| skill        | `git-workflow`           | Trunk-based GitHub Flow: branch off main → PR → gates green → rebase-merge → delete; delegate CI-waits/gh ops to a Sonnet subagent, keep the merge decision on main. Documents its conflict with `superpowers:finishing-a-development-branch`. |
| skill        | `deep-research-tiered`   | Tiered, budget-guarded, checkpointed fan-out research (web search → fetch → verify → synthesize) with per-stage model pins. |
| agent        | `advisor-plus`           | Tier-up second opinion on the main loop's own work (designs, plans, diffs). Caller selects the model one tier above the session model. |
| agent        | `code-reviewer`          | Read-only correctness/security/discipline review of a diff or package; severity-ordered `file:line` findings. One pass per PR on the full branch diff. Inherits the session's strongest model; terminal (consults no one). |
| agent        | `search`                 | Read-only code/doc search-and-locate on Sonnet; returns `file:line` anchors, not file dumps. A cheaper, terminal alternative to built-in `Explore`. |
| agent        | `doc-sync`               | Checks code-vs-docs/spec drift and that discoveries were written back in the same PR; proposes surgical doc/ADR edits. Sonnet. Runs only on docs-adjacent diffs or at milestone close — heaviest per-call agent. |
| agent        | `config-auditor`         | Audits the `.claude/` steering layer itself — frontmatter validity, model-tier consistency, dangling skill/agent/command/hook refs, broken cross-links. Sonnet; read-only. |
| output style | `distinguished-engineer` | Terse principal-engineer voice: verify-before-assert, no fabricated APIs, failure-mode/security reasoning by default, self-review before "done". Available, **not** force-applied. |
| hook         | `guard-secrets`          | PreToolUse(Read\|Edit\|Write): denies file-tool access to secret material (`.env`, `*.key`, `*.pem`, `*.p12`, `*.mobileprovision`, `secrets/…`, `*.local`, …) so key bytes never enter context. |

Skills, agents, and output styles are auto-discovered from `skills/`, `agents/`, and `output-styles/`;
hooks load from `hooks/hooks.json`. The output style is registered via the `outputStyles` key in
`plugin.json`; everything else is directory-layout-driven.

### Deliberately NOT in core (ships in `scaffold` instead)

The milestone/ADR machinery — the `/adr`/`/goal`/`/milestone`/`/scaffold:milestone-run`
commands, the `block-main-writes`/`checkpoint`/`subagent-trail`/`validate-config` hooks, the `determinism-auditor`
agent, and the `milestone-workflow`/`skill-maintenance` skills — ships in the
[`scaffold`](../scaffold) plugin, not here: it is coupled to per-project state (`docs/`,
`.context/`) that a project-agnostic plugin can't assume. See [`scaffold/README.md`](../scaffold/README.md)
for the current inventory rather than duplicating it here (and for why `context-nudge` ships in
neither plugin — it's project-local, see `scaffold/references/project-setup/`).

## Invocation

Once installed from the `mrinal-skills` marketplace, components are namespaced:

- Skills auto-trigger by their `description` exactly as user-level skills do — the namespace does not
  change that. Explicit slash form: `/core:cost-aware-delegation`, `/core:orchestration`,
  `/core:git-workflow`, `/core:deep-research-tiered`.
- Agents: dispatch as subagent type `core:advisor-plus`, `core:code-reviewer`, `core:search`,
  `core:doc-sync`, `core:config-auditor`. (Agents resolve project-over-user, so a repo's own tuned
  agent of the same name still wins.)
- Output style: select `distinguished-engineer` via `/output-style` — it is **not** `force-for-plugin`,
  so enabling core never silently overrides your active style.
- Hooks activate automatically when the plugin is enabled; they **merge** with your user/project hooks
  (identical handlers are de-duplicated). Override either via `/hooks`.

> **Migration note:** any prose that references these by bare name (e.g. `~/.claude/CLAUDE.md`'s
> "the `cost-aware-delegation` skill", "the `advisor-plus` agent") keeps working because
> auto-triggering is by description. Only *explicit* `/name` or bare-`subagent_type` invocations need
> updating to the `core:` form once the user-level originals are removed.
