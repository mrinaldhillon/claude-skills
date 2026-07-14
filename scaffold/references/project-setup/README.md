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
- `context-nudge` on `PostToolUse` (matcher `*`) and `UserPromptSubmit`
- `SessionStart` (matcher `compact`) → `cat .context/RESUME.md`
- three `<PLACEHOLDER bootstrap>` hooks you fill in for your stack: format-on-save
  (`PostToolUse`, matcher `Write|Edit`), an offline check (`Stop`), and an
  environment probe (`SessionStart`, matcher `startup|resume`)

**Never wire `checkpoint`, `subagent-trail`, `validate-config`,
`block-main-writes`, or `guard-secrets` in your project settings.** They are
provided by the plugins' own `hooks.json` (`scaffold/hooks/hooks.json` and
`core/hooks/hooks.json`) and load automatically the moment the plugin is
enabled. Wiring them again in `.claude/settings.json` double-fires them on every
matching event: two `checkpoint.sh` invocations race on the git `index.lock`,
and `subagent-trail` writes a duplicate breadcrumb per subagent stop. This file
is a **complement** to the plugins' hooks, not a replacement or a copy of them —
it exists only because a plugin cannot set project-local keys like `statusLine`
or reach a project's own `.context/RESUME.md` by a fixed relative path.

## 3. Optional context-usage nudges

If you want the statusline and the 55%/65% context nudges, copy
[`statusline.sh`](statusline.sh) and [`context-nudge.sh`](context-nudge.sh) into
your repo's `.claude/` — `settings.example.json` already wires both. They share
a bridge file, `.claude/state/context-usage.json`, written by the statusline and
read by the nudge hook — **keep them together and version them as a pair.**
They live project-local (not in a plugin) because a plugin cannot set the
`statusLine` settings key.

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
     is specific to **hooks**. Tuned project **skills** coexist with the
     namespaced plugin ones, and a tuned **agent** of the same name wins by
     project-over-plugin precedence — so those keep working with no re-wiring
     concern.) Never delete a tuned file without reading what it changed.
2. Enable `core` and `scaffold` (§1).
3. Rewrite `.claude/settings.json` to the complement shape (§2): drop any
   wiring for hooks you deleted in step 1, keep `statusLine`, `context-nudge`,
   the `SessionStart(compact)` → `RESUME.md` line, and the three bootstrap
   placeholders.
4. Re-verify: nothing in your final `.claude/settings.json` wires `checkpoint`,
   `subagent-trail`, `validate-config`, `block-main-writes`, or `guard-secrets`
   (§2) — those come from the plugins now.
