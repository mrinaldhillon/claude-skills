# User-level setup

`core` and `scaffold` are marketplace plugins — they can install skills, agents, hooks, and an
output style, but they cannot write your user-level `~/.claude/CLAUDE.md`. That one-time step, and
the operating-discipline text that used to be appended there by `claude-code-starter`'s
`install-user.sh`, has no plugin-deliverable home. This doc is that home: do the machine setup once
below, then paste the discipline block into your own `~/.claude/CLAUDE.md` by hand.

## One-time machine setup

1. **Add the marketplace** (once per machine):
   ```bash
   /plugin marketplace add <path-or-url-to-this-repo>   # e.g. ~/src/claude-skills, or mrinaldhillon/claude-skills
   ```
2. **Enable `core` globally.** It is project-agnostic — skills, review/search/doc agents, the
   `distinguished-engineer` output style, and the two guard hooks apply to any repo:
   ```bash
   /plugin install core@mrinal-skills
   ```
3. **Enable `scaffold` per-repo**, only in repos that use its `docs/` + `.context/` layout, via that
   repo's checked-in `.claude/settings.json`:
   ```jsonc
   {
     "enabledPlugins": {
       "core@mrinal-skills": true,
       "scaffold@mrinal-skills": true
     }
   }
   ```
4. **Curated `@claude-plugins-official` set.** A project's `settings.example.json` (see
   [`scaffold/references/project-setup/`](../scaffold/references/project-setup/)) also enables a
   small curated set of official plugins alongside `core`/`scaffold`: `skill-creator`, `context7`,
   `github`, `hookify`, `security-guidance`, `superpowers`, `claude-code-setup`,
   `claude-md-management`. Copy that file's `enabledPlugins` block rather than retyping it —
   it is the single source of truth for the set.

## Operating discipline — paste this into your `~/.claude/CLAUDE.md`

The block below is reproduced verbatim from `claude-code-starter`'s
`.claude/user-claude-md-section.md` (the text `install-user.sh` used to append to
`~/.claude/CLAUDE.md`), preserved here as the canonical source ahead of that repo's archival. It
predates the `core`/`scaffold` plugin split, so its "seeded into each project" line is dated —
today those skills/agents ship via the `core` and `scaffold` plugins rather than being copied
per-project — but the guidance itself still holds. Paste it as-is:

> # Claude Code operating discipline
>
> How to run Claude Code itself. The voice is the `distinguished-engineer` output style; the
> procedural detail lives in **per-project** skills (`orchestration`, `git-workflow`, `dev-workflow`,
> `milestone-workflow`, `skill-maintenance`) seeded into each project (skills resolve user-over-project,
> so they must NOT live here), plus the user-level `deep-research-tiered`. This summary applies
> everywhere via this file; the review **agents** (`code-reviewer`/`search`/`doc-sync`/`config-auditor`)
> are user-level and project-overridable.
>
> - **Tier the model to the stakes, before spawning** (the main cost lever). Haiku = pure-mechanical /
>   high-read (search, fetch, scrape, polling); Sonnet = moderate legwork (implement-from-spec,
>   doc/config lint, gh/CI ops, search/locate) and the subagent floor; Opus = correctness-critical
>   judgment (architecture, the gate, all verification, milestone implementation). Tier **up** when
>   quality is at stake. **Workflow `agent()` stages MUST set `opts.model` per stage** — an unset stage
>   inherits the strong default and burns the budget (this once cost ~1.95M tokens in a single run).
> - **Keep the orchestrator's context lean.** Delegate read-heavy work to a cheaper subagent *before*
>   loading the files yourself — context isolation means the subagent's reads don't re-bill on every
>   later turn. Prefer the `search` agent over the built-in `Explore`; a language-server MCP over grep
>   where one exists; and **parse external deps once** → distill to a doc → read that, not the source.
> - **Orchestration = orchestrate the legwork, serialize the build.** Parallelize *investigation*
>   (search, review, per-file analysis, critics) freely; **single-thread coupled writes** (one writer).
>   Verify with **independent critics + a deterministic gate**, never orchestrator-as-judge. Critics are
>   **terminal — consult no one**; workers consult main, not `advisor`. Delegating bulk-mechanical
>   edits to a cheaper worker (spec'd + verified by the strong model) is **break-glass**, not a
>   default — no dedicated `builder` agent ships yet (parked; see the template's roadmap).
> - **Discipline.** Decisions are append-only ADRs (don't relitigate); keep committed context in sync in
>   the **same PR** as the change; **done means green** (build/vet/test/lint pass before claiming done);
>   stay in scope — no "while we're here".
> - **Ask only at genuine decision points** (a key/credential, a destructive or outward-facing action, a
>   real ambiguity). Otherwise proceed, verify, self-review.
> - **On compact, preserve** the current task/gate status, the resume pointer, and ADR numbers cited
>   recently; drop tool-output dumps. The durable record is git + docs + memory.

## Per-project setup

Once `core`/`scaffold` are enabled, setting up an individual repo (the `docs/` + `.context/` layout,
`settings.json`'s complement rule, ADR seeding, the migration checklist for existing
starter-derived repos) is a documented, hand-run procedure — see
[`scaffold/references/project-setup/README.md`](../scaffold/references/project-setup/README.md).
