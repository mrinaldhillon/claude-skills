# Setting up a project on `core` + `scaffold`

These plugins provide skills, agents, hooks, and a milestone runner — not a
copy-script. There is no generator: setting up a project means enabling the
plugins and hand-placing a handful of project-local files, using the examples in
this directory as reference. Nothing here is copied automatically; that's the
point — a plugin that copies plugin-coupled files into your repo owns a drift
liability forever. Do this once per repo.

## 1. Enable the plugins

Add the `mrinal-skills` marketplace, then enable `core` (global is fine — it's
cross-repo) and `scaffold` (per-repo; it assumes the `docs/` + `.context/` layout
this guide sets up). See the `enabledPlugins` block in
[`settings.example.json`](settings.example.json) for the exact keys.

## 2. `settings.json` — the COMPLEMENT rule

**This is the highest-value warning in this document.**

Copy `settings.example.json` to your repo's `.claude/settings.json`. It wires
**only**:

- `statusLine` (the context-usage statusline)
- three `<PLACEHOLDER bootstrap>` hooks you fill in for your stack: format-on-save
  (`PostToolUse`, matcher `Write|Edit`), an offline check (`Stop`), and an
  environment probe (`SessionStart`, matcher `startup|resume`)

**Never wire `checkpoint`, `context-nudge`, `subagent-trail`, `validate-config`,
`block-main-writes`, or `guard-secrets` in your project settings.** They are
provided by the plugins' own `hooks.json` (`scaffold/hooks/hooks.json` and
`core/hooks/hooks.json`) and load automatically the moment the plugin is
enabled. Wiring them again in `.claude/settings.json` double-fires them on every
matching event: two `checkpoint.sh` invocations race on the git `index.lock`,
`subagent-trail` writes a duplicate breadcrumb per subagent stop, and a
double-wired `context-nudge` evaluates twice per tool call and injects its
notice twice at every threshold crossing. This file is a **complement** to the
plugins' hooks, not a replacement or a copy of them — it exists only because a
plugin cannot set project-local keys like `statusLine`.

Do §5's `.gitignore` line even if you skip the statusline: `context-nudge` writes
`.claude/state/hook-surface-log.jsonl` (one line per host surface it has ever
fired on) on its first event in **any** scaffold-enabled repo, bridge or no
bridge. Ignoring `.claude/state/` is what keeps that out of `git status`.

## 3. Context-usage statusline (the nudge hook's bridge)

The 55%/65% context nudges ship in the plugin (`scaffold/hooks/context-nudge.sh`,
ADR 0008) — do not copy or wire the hook. What the plugin cannot ship is the
bridge *writer*: copy [`statusline.sh`](statusline.sh) into your repo's
`.claude/` — `settings.example.json` already wires it via the `statusLine` key,
the one thing a plugin cannot set. It publishes
`.claude/state/context-usage.json` (percentage + `session_id`), which the
plugin's nudge hook reads; without it the hook is a silent no-op. When the
plugin's hook evolves, refresh your statusline copy too — the bridge schema is
their shared contract.

**A pre-0.7.0 statusline copy is a silent half-upgrade.** Its bridge carries no
`session_id`, so the hook's cross-session guard has nothing to compare and
degrades to open. `PostToolUse` still refuses a bridge older than 120 s, but
`UserPromptSubmit` has no staleness backstop by design (the bridge only refreshes
while an interactive statusline renders, so any short bound would eat legitimate
nudges after an idle stretch) — which means a stale or foreign bridge nudges on
every prompt. Re-copy `statusline.sh` in the same change that adopts 0.7.0.

## 4. Branch before your first commit

`core`'s `block-main-writes` hook denies `git commit` on `main` — and
`git branch --show-current` reports `main` even on an unborn HEAD, so the very
first commit in a fresh repo is denied. Run `git switch -c chore/setup` before
you commit anything.

## 5. `.context/` and `docs/decisions/` conventions

See [`context/README.md`](context/README.md) for the `.context/` contract:
agent-written project state (`project-context.md`, `RESUME.md`), committed by
the `checkpoint` hook on non-main branches only. Those two seed files aren't
included here — they're created by your project on its first checkpoint; the
convention doc is enough to bootstrap them.

Add `.context/MILESTONE_DONE`, `.context/REPLAN.md`, and `.claude/state/` to
your project's `.gitignore` — they're per-run/machine-local, per
`context/README.md`.

Adopt the ADR baseline in [`decisions/`](decisions/): copy
[`TEMPLATE.md`](decisions/TEMPLATE.md) plus the seed ADRs `0000`, `0001`,
`0002`, `0007`. The pointer stubs `0003`, `0004`, `0005`, `0006` delegate the
milestone/checkpoint/agent-state machinery's rationale to the plugin — copy
them too to preserve append-only numbering, but the full text of record lives
in [`../decisions/`](../decisions/) (versioned with the plugin, not your project).
ADRs carry a one-line `**Summary:**` — scan those; open a body only to
relitigate or supersede a decision.

## 6. Your `CLAUDE.md` — keep it lean

Do not duplicate the orchestration/git/milestone doctrine — it lives in the
`core` and `scaffold` skills and would drift the moment either plugin updates.
Include only:

- the persona: the `distinguished-engineer` output style, shipped by `core`
- your project's Commands and Architecture (build/test/lint, the layering table)
- a pointer to the checkpoint protocol (`.context/`, `docs/decisions/`, and when
  to checkpoint — see `context/README.md` and the ADRs)
- a note that skills/agents/commands come from the plugins, not this repo

See [`docs/`](docs/) for the recommended doc layout (`design-notes.md` the
reasoning, `discipline.md` the numbered rules, `architecture.md` the structure,
`vocabulary.md` the ambiguous terms) — genericized skeletons, ready to fill in.

## 7. Milestone loop

Run `/scaffold:milestone-run milestones/<name>.json`. The command prints the
exact terminal command to run — the runner itself (`scripts/milestone-runner.sh`)
lives in the plugin and spawns fresh `claude -p` sessions, so it must run from a
plain terminal, not nested inside the current session.
[`milestones/example.json`](milestones/example.json) is a template milestone
config with inline comments on every field.

## 8. Migrating an existing starter-derived repo

A checklist (this replaces the project-adoption command the dropped generator
would have shipped). Do this on a `chore/adopt-plugins` branch:

1. **Hash-compare every vendored hook against its plugin twin.** For each hook
   in `.claude/hooks/` that has a same-named counterpart in `core/hooks/` or
   `scaffold/hooks/`:
   ```
   cmp -s .claude/hooks/X.sh <core|scaffold>/hooks/X.sh
   ```
   - **Identical (pristine):** delete the vendored copy — the plugin now
     supplies it.
   - **Differs (tuned):** KEEP the file, but understand what happens:
     Claude Code **merges** hooks — the plugin's `hooks.json`
     version fires regardless of your project copy — so once you rewrite
     `settings.json` to the complement, your kept tuned hook is wired by
     nothing and no longer runs; the plugin's version runs instead. Treat the
     kept copy as **reference only**: port its changes deliberately (upstream
     them into the plugin, or accept the plugin default). Do NOT re-wire the
     tuned copy in `settings.json` to "restore" it — that double-fires against
     the plugin's hook (see the complement rule above). (This merge behaviour
     is specific to **hooks**. Tuned project **skills** and **agents** behave
     differently: a plugin skill/agent is namespaced (`core:X` / `scaffold:X`),
     so the plugin copy and your same-named project copy **both register and
     coexist** — nothing is shadowed, and no re-wiring is involved. There is no
     project-over-plugin precedence for agents; steer dispatch to your tuned
     copy through its **description** — e.g. *"Prefer this over `core:X` — same
     review plus \<this repo's gates/paths/bindings\>"* — which is how consuming
     repos actually disambiguate.) *(A 2026-07-21 live-registry probe on Claude
     Code 2.1.217 listed both `code-reviewer` and `core:code-reviewer`,
     confirming coexistence; an earlier version of this note wrongly said the
     project agent "wins by project-over-plugin precedence.")* Never delete a
     tuned file without reading what it changed.
2. Enable `core` and `scaffold` (§1).
3. Rewrite `.claude/settings.json` to the complement shape (§2): drop any
   wiring for hooks you deleted in step 1 — including `context-nudge` and any
   `SessionStart` → `RESUME.md` line (`resume-inject` ships in the plugin) —
   keeping only `statusLine` and the three bootstrap placeholders.
4. **Re-copy [`statusline.sh`](statusline.sh)** over your project's copy. Since
   0.7.0 the bridge must carry `session_id`; an older copy leaves the hook's
   cross-session guard inert and a stale bridge nudging on every prompt (§3).
   This step is easy to skip because nothing fails loudly when you do.
5. Confirm `.gitignore` covers `.claude/state/` (§5) — the nudge hook writes
   `hook-surface-log.jsonl` there on its first event even if you never wire the
   statusline.
6. Re-verify: nothing in your final `.claude/settings.json` wires `checkpoint`,
   `context-nudge`, `subagent-trail`, `validate-config`, `block-main-writes`,
   or `guard-secrets` (§2) — those come from the plugins now. Delete any
   project copy of `context-nudge.sh` in the same change: hooks merge, and a
   leftover wired copy double-fires the nudge on every tool call.
