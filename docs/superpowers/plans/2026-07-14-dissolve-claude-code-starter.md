# Dissolve claude-code-starter into the scaffold generator — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `scaffold` plugin generate a project's substrate on demand (and migrate existing repos onto it) so new/old projects need zero dependency on the `claude-code-starter` repo.

**Architecture:** Each LLM command (`/scaffold:bootstrap`, `/scaffold:adopt`) has a **deterministic shell core** (`emit-substrate.sh`, `adopt-substrate.sh`) that enforces the correctness invariants and is CI-tested; the skill on top does only the judgment work (stack discovery, diverged-file reconciliation). The milestone runner relocates into the plugin and resolves its sibling checkpoint hook by realpath. Substrate content ships as bundled `templates/` under the `project-bootstrap` skill. `claude-code-starter`'s 8 tests migrate to the marketplace's `scripts/test-*.sh` + CI pattern.

**Tech Stack:** Bash (`set -euo pipefail`, shellcheck 0.11.0-clean), `jq`, git, Claude Code plugin conventions (`hooks/hooks.json`, command/skill frontmatter, `${CLAUDE_PLUGIN_ROOT}`/`${CLAUDE_PROJECT_DIR}`).

## Global Constraints

- **Session scope: `claude-skills` repo ONLY.** Build everything here. Extraction *reads* `../claude-code-starter` (read-only) — **never modify that repo** in this session.
- **Do NOT run `/scaffold:adopt` against `handled-next` or any live repo, and do NOT archive `claude-code-starter`.** Those are user-driven, tested manually in a scratch repo.
- **Marketplace name is `mrinal-skills`**; plugins are referenced as `core@mrinal-skills`, `scaffold@mrinal-skills`.
- **Complement invariant:** generated `settings.json` wires ONLY `statusLine`, `context-nudge` (×2 events), `SessionStart(compact)→cat RESUME.md`, and the 3 project placeholders (format-on-save, offline-check, env-probe). It MUST NOT wire `checkpoint`, `subagent-trail`, `validate-config`, `block-main-writes`, `guard-secrets` — those come from the plugins.
- **Branch before commit:** `core/hooks/block-main-writes.sh` denies commits on `main`/unborn HEAD. Every generated-project commit and this repo's own work happens on a non-`main` branch.
- **Shell style:** every script starts `#!/usr/bin/env bash` + `set -euo pipefail` (tests that capture exit codes use `set -uo pipefail`), quotes all expansions, passes the repo's pinned shellcheck 0.11.0.
- **Plugin components auto-discover** from their directories; `marketplace.json` needs NO edit to add commands/skills/hooks. `hooks.json` command format: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh"`.
- **Command frontmatter keys:** `description` (required), `argument-hint`, `model`, `allowed-tools` — no `name` key. **Skill frontmatter:** `name` + `description`. **No per-skill README** (plugin-root README is the convention).
- **This repo's own commits** go on branch `feat/scaffold-generator` (create at Task 0).
- **TDD + frequent commits:** each task ends with an independently runnable test/green check and a commit.

---

## File Structure

**Created (in `claude-skills/`):**
- `scaffold/scripts/milestone-runner.sh` — relocated runner (checkpoint fix).
- `scaffold/scripts/emit-substrate.sh` — deterministic bootstrap core.
- `scaffold/scripts/adopt-substrate.sh` — deterministic adopt core.
- `scaffold/commands/{bootstrap,adopt,milestone-run}.md` — thin slash entries.
- `scaffold/skills/project-bootstrap/SKILL.md` + `templates/…` — generator + bundled substrate.
- `scaffold/skills/project-adopt/SKILL.md` — adopt judgment wrapper.
- `scaffold/references/decisions/000{3,4,6}-*.md` — machinery ADRs as plugin reference.
- `scripts/test-{guard-secrets,checkpoint,subagent-trail,validate-config,statusline,context-nudge,milestone-runner,bootstrap,adopt}.sh` — migrated + new regression tests.

**Modified:**
- `.github/workflows/validate.yml` — shellcheck globs + one CI step per new test.
- `scaffold/README.md` — document generator/adopt/runner + enable→bootstrap flow.
- `scaffold/.claude-plugin/plugin.json` — bump `0.1.0` → `0.2.0`.

**Read-only source (never modified):** `../claude-code-starter/…`.

---

## Task 0: Branch for this work

- [ ] **Step 1: Create the feature branch**

Run:
```bash
cd /Users/mrinal/Developer/codakali/next/claude-skills
git switch -c feat/scaffold-generator
```
Expected: `Switched to a new branch 'feat/scaffold-generator'`. (Required — `block-main-writes` denies commits on `main`.)

---

## Task 1: Backfill regression tests for the core+scaffold plugin hooks

**Why first:** these hooks already live in the plugins but are untested in marketplace CI. Migrating their tests now guards every later change. No new component — pure coverage.

**Files:**
- Create: `scripts/test-guard-secrets.sh`, `scripts/test-checkpoint.sh`, `scripts/test-subagent-trail.sh`, `scripts/test-validate-config.sh`
- Modify: `.github/workflows/validate.yml`
- Read-only source: `../claude-code-starter/.claude/hooks/tests/{guard-secrets,checkpoint,subagent-trail,validate-config}_test.sh`

**Interfaces:**
- Produces: 4 executable test scripts, each exiting non-zero on failure; 4 new CI steps.

Each migrated test needs exactly one change: the "path to the script under test." In the source, hook tests resolve it one level up from the test file (`hook="$(cd "$here/.." && pwd)/<name>.sh"`). In the marketplace, tests sit at `scripts/` and the hook sits in a plugin dir. The new resolver is:
```bash
here="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$here/.." && pwd)"
hook="$REPO/<core|scaffold>/hooks/<name>.sh"
```

- [ ] **Step 1: Migrate the guard-secrets test**

Copy `../claude-code-starter/.claude/hooks/tests/guard-secrets_test.sh` → `scripts/test-guard-secrets.sh`. Replace its resolver lines
```bash
here="$(cd "$(dirname "$0")" && pwd)"
hook="$(cd "$here/.." && pwd)/guard-secrets.sh"
```
with
```bash
here="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$here/.." && pwd)"
hook="$REPO/core/hooks/guard-secrets.sh"
```
Leave everything else verbatim (its fixtures use `mktemp`, no other repo-relative paths). `chmod +x scripts/test-guard-secrets.sh`.

- [ ] **Step 2: Run it — expect PASS against the real core hook**

Run: `bash scripts/test-guard-secrets.sh`
Expected: exit 0, all cases pass. (If it fails, the core hook diverged from the starter's — investigate before proceeding; do not weaken the test.)

- [ ] **Step 3: Migrate the checkpoint, subagent-trail, validate-config tests the same way**

- `scripts/test-checkpoint.sh` from `checkpoint_test.sh`: resolver → `script="$REPO/scaffold/hooks/checkpoint.sh"` (source used `script=…/checkpoint.sh`). Its fixtures already `mkdir -p docs/decisions .context` inside a temp git repo — keep verbatim.
- `scripts/test-subagent-trail.sh` from `subagent-trail_test.sh`: resolver → `hook="$REPO/scaffold/hooks/subagent-trail.sh"`. Keep the `export HOME="$tmp/home"` redirection verbatim (it isolates the user-memory path).
- `scripts/test-validate-config.sh` from `validate-config_test.sh`: resolver → `hook="$REPO/scaffold/hooks/validate-config.sh"`. Keep its `$tmp/.claude/...` fixtures verbatim.

`chmod +x` each.

- [ ] **Step 4: Run all four — expect PASS**

Run: `for t in guard-secrets checkpoint subagent-trail validate-config; do echo "== $t =="; bash "scripts/test-$t.sh" || break; done`
Expected: each prints its cases and exits 0.

- [ ] **Step 5: Wire them into CI**

In `.github/workflows/validate.yml`, after the existing `- name: test block-main-writes hook` step, append:
```yaml
      - name: test guard-secrets hook
        run: ./scripts/test-guard-secrets.sh
      - name: test checkpoint hook
        run: ./scripts/test-checkpoint.sh
      - name: test subagent-trail hook
        run: ./scripts/test-subagent-trail.sh
      - name: test validate-config hook
        run: ./scripts/test-validate-config.sh
```
(The existing `shellcheck scripts/*.sh …` step already covers these new files.)

- [ ] **Step 6: Shellcheck + commit**

Run: `shellcheck scripts/test-guard-secrets.sh scripts/test-checkpoint.sh scripts/test-subagent-trail.sh scripts/test-validate-config.sh`
Expected: no output (clean).
```bash
git add scripts/test-*.sh .github/workflows/validate.yml
git commit -m "test: migrate guard-secrets/checkpoint/subagent-trail/validate-config hook regression tests into marketplace CI"
```

---

## Task 2: Relocate the milestone runner + add `/scaffold:milestone-run`

**Files:**
- Create: `scaffold/scripts/milestone-runner.sh` (from `../claude-code-starter/scripts/milestone-runner.sh`), `scaffold/commands/milestone-run.md`, `scripts/test-milestone-runner.sh` (from the starter's runner test)
- Modify: `.github/workflows/validate.yml`
- Read-only source: `../claude-code-starter/scripts/{milestone-runner.sh,tests/milestone-runner_test.sh}`

**Interfaces:**
- Produces: `scaffold/scripts/milestone-runner.sh` invoked as `bash <path> milestones/<name>.json`, honoring env `CHECKPOINT_SH` (test injection), `DRY_RUN`, `MILESTONE_MODEL`, `AUTOCOMPACT_PCT`, `PHASE_TIMEOUT`, `RUN_ID`, `MILESTONE_CONTAINED`.

- [ ] **Step 1: Migrate the runner test first (TDD), pointing at the new location + injectable checkpoint**

Copy `../claude-code-starter/scripts/tests/milestone-runner_test.sh` → `scripts/test-milestone-runner.sh`. Apply two edits:

(a) Resolver — source has:
```bash
here="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$here/../.." && pwd)"
RUNNER="$REPO/scripts/milestone-runner.sh"
```
Change to:
```bash
here="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$here/.." && pwd)"
RUNNER="$REPO/scaffold/scripts/milestone-runner.sh"
```

(b) Checkpoint stub — the source's `mkrepo()` stubs `.claude/hooks/checkpoint.sh`. The relocated runner resolves checkpoint via `CHECKPOINT_SH` (Step 3), so make the test create a stub and export it. Inside `mkrepo()`, after the repo is created, add:
```bash
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/checkpoint-stub.sh"
  chmod +x "$tmp/checkpoint-stub.sh"
```
and ensure each runner invocation runs with `CHECKPOINT_SH="$tmp/checkpoint-stub.sh"` in its environment (add it to the `env`/inline-assignment the test already uses to call `$RUNNER`; the source already prefixes runner calls with env assignments — add `CHECKPOINT_SH="$tmp/checkpoint-stub.sh"` to that prefix). Keep the `set -uo pipefail` header verbatim.

`chmod +x scripts/test-milestone-runner.sh`.

- [ ] **Step 2: Run it — expect FAIL (runner not yet at new path)**

Run: `bash scripts/test-milestone-runner.sh; echo "exit=$?"`
Expected: FAIL — runner path `scaffold/scripts/milestone-runner.sh` does not exist yet.

- [ ] **Step 3: Relocate the runner and fix checkpoint resolution**

Copy `../claude-code-starter/scripts/milestone-runner.sh` → `scaffold/scripts/milestone-runner.sh`. Apply exactly these edits:

After the `runner_path=…` line (source line 47):
```bash
runner_path="$(realpath -e "$0" 2>/dev/null || printf '%s' "$0")"
```
insert:
```bash
# Resolve the checkpoint hook as the runner's plugin sibling (scaffold/hooks/),
# not repo-relative — a dissolved project has no .claude/hooks/checkpoint.sh.
# CHECKPOINT_SH overrides for tests.
checkpoint_sh="${CHECKPOINT_SH:-$(dirname "$runner_path")/../hooks/checkpoint.sh}"
```

Replace both checkpoint call sites (source lines 286 and 299):
```bash
bash .claude/hooks/checkpoint.sh >/dev/null 2>&1 || true
```
with:
```bash
CLAUDE_PROJECT_DIR="$repo" bash "$checkpoint_sh" >/dev/null 2>&1 || true
```
`chmod +x scaffold/scripts/milestone-runner.sh`. Leave all other logic (config validation, gates, permission profiles, `claude -p` invocation) verbatim.

- [ ] **Step 4: Run the test — expect PASS**

Run: `bash scripts/test-milestone-runner.sh; echo "exit=$?"`
Expected: exit 0, all cases pass.

- [ ] **Step 5: Add the `/scaffold:milestone-run` command**

Create `scaffold/commands/milestone-run.md`:
```markdown
---
description: Print the exact terminal command to run the milestone loop (resolves the scaffold plugin path).
argument-hint: milestones/<name>.json
allowed-tools: Bash(printf:*)
---
The milestone runner (ADR 0004/0006) manages context by spawning fresh `claude -p`
sessions, so it runs from a plain terminal — NOT nested inside this session. Resolve
and print the command for the config in `$ARGUMENTS`:

    printf 'Run this in a terminal at your repo root:\n\n  bash "%s/scripts/milestone-runner.sh" %s\n' "${CLAUDE_PLUGIN_ROOT}" "$ARGUMENTS"

Do not execute the runner from within this session.
```
(This resolves §9's open invocation-model item toward "print, don't nest" — confirm on manual test.)

- [ ] **Step 6: Extend shellcheck + CI, then commit**

In `.github/workflows/validate.yml`, change the shellcheck step glob from
```yaml
        run: shellcheck scripts/*.sh core/hooks/*.sh scaffold/hooks/*.sh
```
to
```yaml
        run: shellcheck scripts/*.sh core/hooks/*.sh scaffold/hooks/*.sh scaffold/scripts/*.sh
```
and append a CI step:
```yaml
      - name: test milestone-runner
        run: ./scripts/test-milestone-runner.sh
```
Run: `shellcheck scaffold/scripts/milestone-runner.sh scripts/test-milestone-runner.sh` → clean. Then:
```bash
git add scaffold/scripts/milestone-runner.sh scaffold/commands/milestone-run.md scripts/test-milestone-runner.sh .github/workflows/validate.yml
git commit -m "feat(scaffold): relocate milestone-runner into plugin; resolve checkpoint by plugin-sibling; add /scaffold:milestone-run"
```

---

## Task 3: Bundle the substrate templates

**Files (all under `scaffold/skills/project-bootstrap/templates/`, plus reference ADRs):**
- Create verbatim copies: `statusline.sh`, `context-nudge.sh`, `context/README.md`, `milestones/example.json`, `docs/decisions/TEMPLATE.md`
- Create authored: `settings.json`, `context/project-context.md`, `context/RESUME.md`, `docs/decisions/000{0,1,2,5,7}-*.md` (genericized seeds), `docs/decisions/000{3,4,6}-*.md` (pointer stubs), `docs/{README,design-notes,architecture,vocabulary,discipline}.md` (skeletons), `CLAUDE.md` (skeleton)
- Create reference: `scaffold/references/decisions/000{3,4,6}-*.md` (full machinery ADRs)

**Interfaces:**
- Produces: a complete `templates/` tree consumed by `emit-substrate.sh` (Task 4).

- [ ] **Step 1: Copy the verbatim templates**

```bash
mkdir -p scaffold/skills/project-bootstrap/templates/{context,milestones,docs/decisions}
cp ../claude-code-starter/.claude/statusline.sh        scaffold/skills/project-bootstrap/templates/statusline.sh
cp ../claude-code-starter/.claude/hooks/context-nudge.sh scaffold/skills/project-bootstrap/templates/context-nudge.sh
cp ../claude-code-starter/.context/README.md           scaffold/skills/project-bootstrap/templates/context/README.md
cp ../claude-code-starter/milestones/example.json      scaffold/skills/project-bootstrap/templates/milestones/example.json
cp ../claude-code-starter/docs/decisions/TEMPLATE.md   scaffold/skills/project-bootstrap/templates/docs/decisions/TEMPLATE.md
chmod +x scaffold/skills/project-bootstrap/templates/statusline.sh scaffold/skills/project-bootstrap/templates/context-nudge.sh
```
These are project-dir-anchored already (verified) — no edits needed.

- [ ] **Step 2: Author the `settings.json` complement template**

Create `scaffold/skills/project-bootstrap/templates/settings.json`:
```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "statusLine": {
    "type": "command",
    "command": "bash \"${CLAUDE_PROJECT_DIR:-$PWD}/.claude/statusline.sh\""
  },
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "true  # <PLACEHOLDER bootstrap>: format-on-save — set to your formatter, e.g. gofmt -w . / prettier -w . / cargo fmt / ruff format ." }
        ]
      },
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR:-$PWD}/.claude/context-nudge.sh\"" }
        ]
      }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR:-$PWD}/.claude/context-nudge.sh\"" } ] }
    ],
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "true  # <PLACEHOLDER bootstrap>: fast offline check — set to e.g. make test-offline >/dev/null 2>&1 || echo 'NOTE: offline tests failing — fix before merge'" }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [ { "type": "command", "command": "cat \"${CLAUDE_PROJECT_DIR:-$PWD}/.context/RESUME.md\" 2>/dev/null || true" } ]
      },
      {
        "matcher": "startup|resume",
        "hooks": [ { "type": "command", "command": "true  # <PLACEHOLDER bootstrap>: environment detection — e.g. test -S /run/<service>.sock && echo 'ENV: PRODUCTION host' || echo 'ENV: dev host'." } ]
      }
    ]
  },
  "enabledPlugins": {
    "core@mrinal-skills": true,
    "scaffold@mrinal-skills": true,
    "skill-creator@claude-plugins-official": true,
    "context7@claude-plugins-official": true,
    "github@claude-plugins-official": true,
    "hookify@claude-plugins-official": true,
    "security-guidance@claude-plugins-official": true,
    "superpowers@claude-plugins-official": true,
    "claude-code-setup@claude-plugins-official": true,
    "claude-md-management@claude-plugins-official": true
  }
}
```
This is the **complement**: no `checkpoint`/`subagent-trail`/`validate-config`/`block-main-writes`/`guard-secrets` wiring (those come from the plugins). Verify it parses: `jq -e . scaffold/skills/project-bootstrap/templates/settings.json >/dev/null && echo OK`.

- [ ] **Step 3: Author the generic `.context/` seeds**

`templates/context/project-context.md`:
```markdown
# Project context

> The living "where things stand" doc. Settled decisions live in `design-notes.md` /
> `discipline.md` / `decisions/`; **open** items live here. Convert relative dates to
> absolute when you record them.

## Current state

<Bootstrap seed — replace on your first checkpoint: current goal/milestone, gate status,
files touched and why, and the exact next step.>
```
`templates/context/RESUME.md`:
```markdown
# Resume Pointer

**Next action:** <the single concrete next step for a fresh session>

_This file holds the single next action for a fresh session to pick up. Claude
overwrites it at each checkpoint. Keep it to one concrete step._
```
(Do NOT copy the starter's `.context/project-context.md` / `RESUME.md` — those are the library's own build notes, not seeds.)

- [ ] **Step 4: Author the seed ADRs (genericized) + a one-line Summary + pointer stubs**

First, make ADRs cheaply scannable (runtime cost): edit `templates/docs/decisions/TEMPLATE.md` to add a `- **Summary:** <one sentence — the ruling, so a scan of titles+summaries suffices; open the body only to relitigate/supersede.>` as the **first** header bullet (above `**Status:**`).

Copy each seed ADR from `../claude-code-starter/docs/decisions/` into `templates/docs/decisions/`, and to each add a one-line `- **Summary:**` header bullet capturing its ruling. Strip library-self-referential phrasing (e.g. rename `0002` title `# 2. Branch protection is by-discipline on the template` → `# 2. Branch protection is by-discipline`; remove any "on the template"/"claude-code-starter" wording; set `Status: Accepted`, `Date: <bootstrap fills>`). Seed set: `0000, 0001, 0002, 0005, 0007`.

Create three pointer stubs. `templates/docs/decisions/0003-context-management-checkpoint-resume.md`:
```markdown
# 3. Context management by checkpoint-resume, not compaction

- **Summary:** Durable state lives in files; checkpoint before clearing. Machinery of record is in the scaffold plugin — see plugin reference.
- **Status:** Accepted (machinery relocated)
- **Date:** <bootstrap fills>
- **Supersedes:** —
- **Superseded by:** —

## Decision

This project delegates the context checkpoint-resume **machinery** (the statusline
bridge, the context-nudge thresholds, the `checkpoint.sh` hook, and the milestone
runner) to the `scaffold` plugin. The rationale of record lives in the plugin's ADR
set (`scaffold/references/decisions/0003-*.md`), versioned with the plugin. This slot
is retained to preserve append-only numbering. The project-level convention it implies
— durable state in files, checkpoint before clearing — is stated in `CLAUDE.md`
§"Context & checkpoint protocol".
```
Create `0004-*.md` and `0006-*.md` stubs with the same shape — including a one-line `**Summary:**` header bullet — (titles `# 4. Context-managed milestone loop` and `# 6. Milestone permission profiles`, each pointing at `scaffold/references/decisions/000{4,6}-*.md`).

- [ ] **Step 5: Ship the full machinery ADRs as plugin reference**

```bash
mkdir -p scaffold/references/decisions
cp ../claude-code-starter/docs/decisions/0003-*.md scaffold/references/decisions/
cp ../claude-code-starter/docs/decisions/0004-*.md scaffold/references/decisions/
cp ../claude-code-starter/docs/decisions/0006-*.md scaffold/references/decisions/
```
(These evolve with the plugin; the project only carries the stubs.)

- [ ] **Step 6: Author the docs/ skeletons and CLAUDE.md skeleton**

Copy `../claude-code-starter/docs/{README,design-notes,architecture,vocabulary,discipline}.md` → `templates/docs/`, leaving their `<PLACEHOLDER…>` markers intact (they are downstream-fill slots). Copy `../claude-code-starter/CLAUDE.md` → `templates/CLAUDE.md`, keeping the `# Commands` marker (`<PLACEHOLDER: fill from your build tool's task taxonomy — see the dev-workflow skill.>`) and the `# Architecture at a glance` marker verbatim; **remove** the top banner paragraph that describes the *library itself* (starter `CLAUDE.md:5-8`) and the "Developing the library itself" section — those are template-maintainer content, not project content. Then, in §"Context engineering", extend the "**Read `docs/decisions/`**" bullet with: *ADRs carry a one-line `**Summary:**` — scan titles + summaries to know what's decided; open a full ADR body only to relitigate or supersede a decision, not every session.* (This keeps ADR consultation cheap.)

- [ ] **Step 7: Validate and commit**

Run:
```bash
jq -e . scaffold/skills/project-bootstrap/templates/settings.json >/dev/null && echo "settings OK"
jq -e . scaffold/skills/project-bootstrap/templates/milestones/example.json >/dev/null && echo "milestone OK"
shellcheck scaffold/skills/project-bootstrap/templates/statusline.sh scaffold/skills/project-bootstrap/templates/context-nudge.sh
ls scaffold/skills/project-bootstrap/templates/docs/decisions/   # expect 0000,0001,0002,0003,0004,0005,0006,0007,TEMPLATE
```
Expected: OK lines, clean shellcheck, all 8 ADRs + TEMPLATE present.
```bash
git add scaffold/skills/project-bootstrap/templates scaffold/references/decisions
git commit -m "feat(scaffold): bundle project substrate templates + machinery ADRs as plugin reference"
```

---

## Task 4: Deterministic bootstrap core + skill/command + CI self-test

**Files:**
- Create: `scaffold/scripts/emit-substrate.sh`, `scripts/test-bootstrap.sh`, `scaffold/skills/project-bootstrap/SKILL.md`, `scaffold/commands/bootstrap.md`
- Modify: `.github/workflows/validate.yml`

**Interfaces:**
- Consumes: `templates/` (Task 3).
- Produces: `emit-substrate.sh` — run as `CLAUDE_PROJECT_DIR=<repo> bash scaffold/scripts/emit-substrate.sh`; idempotent; emits substrate, ensures a non-`main` branch, merges/enables plugins.

- [ ] **Step 1: Write the self-test first (TDD)**

Create `scripts/test-bootstrap.sh`:
```bash
#!/usr/bin/env bash
# CI self-test: run the deterministic bootstrap core into a throwaway repo and
# assert the emitted substrate — including the complement invariant and re-entrancy.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$here/.." && pwd)"
EMIT="$REPO/scaffold/scripts/emit-substrate.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fails=0
chk() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; fails=$((fails+1)); fi; }

git -C "$tmp" init -q
git -C "$tmp" config user.email t@t; git -C "$tmp" config user.name t

CLAUDE_PROJECT_DIR="$tmp" bash "$EMIT" >/dev/null 2>&1

chk "statusline emitted"        '[ -f "$tmp/.claude/statusline.sh" ]'
chk "context-nudge emitted"     '[ -f "$tmp/.claude/context-nudge.sh" ]'
chk "settings emitted"          '[ -f "$tmp/.claude/settings.json" ]'
chk "context seed emitted"      '[ -f "$tmp/.context/project-context.md" ]'
chk "seed ADR 0000"             '[ -f "$tmp/docs/decisions/0000-record-architecture-decisions.md" ] || ls "$tmp"/docs/decisions/0000-*.md >/dev/null 2>&1'
chk "pointer stub 0004"         'ls "$tmp"/docs/decisions/0004-*.md >/dev/null 2>&1'
chk "CLAUDE.md emitted"         '[ -f "$tmp/CLAUDE.md" ]'
chk "off main"                  '[ "$(git -C "$tmp" rev-parse --abbrev-ref HEAD)" != "main" ]'
# Complement invariant: plugin hooks must NOT be wired.
chk "no checkpoint wiring"      '! grep -q checkpoint.sh "$tmp/.claude/settings.json"'
chk "no validate-config wiring" '! grep -q validate-config.sh "$tmp/.claude/settings.json"'
chk "no block-main-writes"      '! grep -q block-main-writes.sh "$tmp/.claude/settings.json"'
chk "statusLine wired"          'grep -q statusline.sh "$tmp/.claude/settings.json"'
chk "context-nudge wired"       'grep -q context-nudge.sh "$tmp/.claude/settings.json"'
chk "core enabled"              'jq -e ".enabledPlugins[\"core@mrinal-skills\"]==true" "$tmp/.claude/settings.json" >/dev/null'
# Re-entrancy: modify live state, re-run, assert not clobbered.
echo "MY LIVE STATE" > "$tmp/.context/project-context.md"
CLAUDE_PROJECT_DIR="$tmp" bash "$EMIT" >/dev/null 2>&1
chk "re-run preserves .context" 'grep -q "MY LIVE STATE" "$tmp/.context/project-context.md"'

[ "$fails" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "$fails FAILED"; exit 1; }
```
`chmod +x scripts/test-bootstrap.sh`.

- [ ] **Step 2: Run it — expect FAIL (emit-substrate.sh missing)**

Run: `bash scripts/test-bootstrap.sh; echo "exit=$?"`
Expected: FAIL — `emit-substrate.sh` not found / assertions fail.

- [ ] **Step 3: Write `emit-substrate.sh`**

Create `scaffold/scripts/emit-substrate.sh`:
```bash
#!/usr/bin/env bash
# Deterministically emit the bundled project substrate into the target project.
# Idempotent + non-destructive: never clobbers live .context/ or an existing
# CLAUDE.md; only ENSURES core+scaffold in an existing settings.json. The
# stack-specific placeholder fill is the project-bootstrap skill's job, not this.
set -euo pipefail

self="$(realpath -e "$0" 2>/dev/null || printf '%s' "$0")"
tpl="$(cd "$(dirname "$self")/../skills/project-bootstrap/templates" && pwd)"

proj="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$proj"
command -v jq >/dev/null 2>&1 || { echo "emit-substrate: jq required" >&2; exit 2; }

# Branch guard: block-main-writes denies commits on main/master (incl. unborn HEAD).
# Re-entrant: only switch when on main/master; reuse chore/bootstrap if it exists.
cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
if [ "$cur" = "main" ] || [ "$cur" = "master" ]; then
  git switch chore/bootstrap 2>/dev/null \
    || git switch -c chore/bootstrap 2>/dev/null \
    || git checkout -b chore/bootstrap
fi

copy_if_absent() {  # src dest
  if [ -e "$2" ]; then echo "skip (exists): $2"; else
    mkdir -p "$(dirname "$2")"; cp "$1" "$2"; echo "wrote: $2"; fi
}

mkdir -p .claude .claude/state .context milestones docs/decisions docs/playbooks

copy_if_absent "$tpl/statusline.sh"    ".claude/statusline.sh"
copy_if_absent "$tpl/context-nudge.sh" ".claude/context-nudge.sh"
chmod +x .claude/statusline.sh .claude/context-nudge.sh 2>/dev/null || true

copy_if_absent "$tpl/context/README.md"          ".context/README.md"
copy_if_absent "$tpl/context/project-context.md" ".context/project-context.md"
copy_if_absent "$tpl/context/RESUME.md"          ".context/RESUME.md"
copy_if_absent "$tpl/milestones/example.json"    "milestones/example.json"
copy_if_absent "$tpl/CLAUDE.md"                   "CLAUDE.md"

# docs/ tree (decisions + skeletons), each copy-if-absent.
while IFS= read -r f; do
  copy_if_absent "$f" "docs/${f#"$tpl"/docs/}"
done < <(find "$tpl/docs" -type f)

# settings.json: write template if absent; else only ensure plugins enabled.
if [ -f .claude/settings.json ]; then
  tmp="$(mktemp)"
  jq '.enabledPlugins["core@mrinal-skills"]=true
      | .enabledPlugins["scaffold@mrinal-skills"]=true' \
     .claude/settings.json > "$tmp" && mv "$tmp" .claude/settings.json
  echo "ensured core+scaffold enabled: .claude/settings.json"
else
  cp "$tpl/settings.json" .claude/settings.json
  echo "wrote: .claude/settings.json"
fi

echo "emit-substrate: done in $proj"
```
`chmod +x scaffold/scripts/emit-substrate.sh`.

- [ ] **Step 4: Run the self-test — expect PASS**

Run: `bash scripts/test-bootstrap.sh; echo "exit=$?"`
Expected: `ALL PASS`, exit 0.

- [ ] **Step 5: Write the `project-bootstrap` skill (the judgment wrapper)**

Create `scaffold/skills/project-bootstrap/SKILL.md`:
```markdown
---
name: project-bootstrap
description: >-
  Use once, in a fresh repo that has enabled the scaffold plugin, to scaffold the
  project substrate (.context/, docs/decisions, milestones/, statusline+settings
  wiring, CLAUDE.md) and fill stack-specific placeholders. Trigger on /scaffold:bootstrap
  or when a repo has the plugin enabled but no .context/ or docs/decisions yet.
---

# Project bootstrap

Two parts: a deterministic emit (a script) and the stack-specific fill (your judgment).

## 1. Emit the substrate (deterministic)

Run the bundled core — it branches off main, copies substrate non-destructively, and
ensures core+scaffold are enabled:

    bash "${CLAUDE_PLUGIN_ROOT}/scripts/emit-substrate.sh"

It is idempotent: re-running never clobbers live `.context/` or an existing `CLAUDE.md`.
It CANNOT self-delete (plugin content) — bootstrap is simply not re-run once the repo is
established.

## 2. Fill the stack-specific placeholders (judgment)

Discover the stack — audit any design docs the user dropped in `docs/`, else interview
(build tool, test command, offline-test command, linter, language-server MCP). Then:

- **`CLAUDE.md`** — replace the `<PLACEHOLDER>` in `# Commands` (the build/test/vet/lint/ci
  task taxonomy) and `# Architecture at a glance` (component map + enforced boundaries).
- **`.claude/settings.json`** — replace the three `# <PLACEHOLDER bootstrap>` hook commands:
  format-on-save (e.g. `gofmt -w .`), the Stop offline check (e.g. `make test-offline`), and
  the SessionStart env-probe. Leave every other entry untouched — do NOT add checkpoint,
  subagent-trail, validate-config, block-main-writes, or guard-secrets wiring; those come
  from the plugins (wiring them here double-fires and races the git index).
- Seed ADRs `0000–0002,0005,0007` — set their `Date:` and confirm titles fit the project.
- Delete the placeholder markers you filled; leave `docs/` skeleton placeholders for the
  user to fill as the project grows.

## 3. Commit

Commit on the `chore/bootstrap` branch the emit step created (never `main`):

    git add -A && git commit -m "chore: bootstrap project substrate"
```

- [ ] **Step 6: Write the `/scaffold:bootstrap` command**

Create `scaffold/commands/bootstrap.md`:
```markdown
---
description: One-time — scaffold this repo's project substrate from the scaffold plugin and fill stack-specific placeholders.
argument-hint: [path to a design doc to audit, or empty to interview]
model: claude-opus-4-8
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, AskUserQuestion, Skill
---
Load and follow the `project-bootstrap` skill to scaffold this repository. If `$ARGUMENTS`
names a design doc, audit it for the stack; otherwise interview the user. The skill runs
the deterministic emit first, then fills the CLAUDE.md and settings.json placeholders for
the discovered stack. Do not wire any plugin-provided hook into settings.json.
```

- [ ] **Step 7: Wire the self-test into CI; validate; commit**

Add to `.github/workflows/validate.yml`:
```yaml
      - name: test bootstrap self-test
        run: ./scripts/test-bootstrap.sh
```
Run:
```bash
shellcheck scaffold/scripts/emit-substrate.sh scripts/test-bootstrap.sh
./scripts/validate.sh   # confirms the new SKILL.md + command frontmatter pass
bash scripts/test-bootstrap.sh
```
Expected: clean shellcheck, validate.sh green, `ALL PASS`.
```bash
git add scaffold/scripts/emit-substrate.sh scripts/test-bootstrap.sh scaffold/skills/project-bootstrap/SKILL.md scaffold/commands/bootstrap.md .github/workflows/validate.yml
git commit -m "feat(scaffold): deterministic bootstrap core (emit-substrate) + project-bootstrap skill + /scaffold:bootstrap + CI self-test"
```

---

## Task 5: Deterministic adopt core + skill/command + fixture test

**Files:**
- Create: `scaffold/scripts/adopt-substrate.sh`, `scripts/test-adopt.sh`, `scaffold/skills/project-adopt/SKILL.md`, `scaffold/commands/adopt.md`
- Modify: `.github/workflows/validate.yml`

**Interfaces:**
- Consumes: `core/hooks/*.sh`, `scaffold/hooks/*.sh` (the canonical shipped versions to hash against).
- Produces: `adopt-substrate.sh` — removes only *pristine* vendored twins, preserves diverged (tuned) copies, ensures plugins enabled, reports what needs manual reconciliation.

- [ ] **Step 1: Write the fixture test first (TDD)**

Create `scripts/test-adopt.sh`:
```bash
#!/usr/bin/env bash
# Fixture test: a repo with vendored hooks — one PRISTINE (byte-identical to the
# shipped plugin hook) and one TUNED (diverged). adopt must remove the pristine
# twin, PRESERVE the tuned one, and enable the plugins.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$here/.." && pwd)"
ADOPT="$REPO/scaffold/scripts/adopt-substrate.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fails=0
chk() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; fails=$((fails+1)); fi; }

git -C "$tmp" init -q; git -C "$tmp" config user.email t@t; git -C "$tmp" config user.name t
mkdir -p "$tmp/.claude/hooks"
# pristine twin = exact copy of the shipped scaffold checkpoint hook
cp "$REPO/scaffold/hooks/checkpoint.sh" "$tmp/.claude/hooks/checkpoint.sh"
# tuned twin = shipped guard-secrets + a local modification
cp "$REPO/core/hooks/guard-secrets.sh" "$tmp/.claude/hooks/guard-secrets.sh"
printf '\n# LOCAL TUNING\n' >> "$tmp/.claude/hooks/guard-secrets.sh"
echo '{"enabledPlugins":{}}' > "$tmp/.claude/settings.json"

CLAUDE_PROJECT_DIR="$tmp" bash "$ADOPT" >"$tmp/out.log" 2>&1

chk "pristine checkpoint removed" '[ ! -f "$tmp/.claude/hooks/checkpoint.sh" ]'
chk "tuned guard-secrets kept"    '[ -f "$tmp/.claude/hooks/guard-secrets.sh" ]'
chk "diverged reported"           'grep -qi "guard-secrets" "$tmp/out.log"'
chk "core enabled"                'jq -e ".enabledPlugins[\"core@mrinal-skills\"]==true" "$tmp/.claude/settings.json" >/dev/null'
chk "scaffold enabled"            'jq -e ".enabledPlugins[\"scaffold@mrinal-skills\"]==true" "$tmp/.claude/settings.json" >/dev/null'

[ "$fails" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "$fails FAILED"; exit 1; }
```
`chmod +x scripts/test-adopt.sh`.

- [ ] **Step 2: Run it — expect FAIL (adopt-substrate.sh missing)**

Run: `bash scripts/test-adopt.sh; echo "exit=$?"`
Expected: FAIL.

- [ ] **Step 3: Write `adopt-substrate.sh`**

Create `scaffold/scripts/adopt-substrate.sh`:
```bash
#!/usr/bin/env bash
# Deterministically adopt a starter-derived repo onto the plugins. NON-DESTRUCTIVE:
# remove a vendored hook twin ONLY if byte-identical to the plugin's shipped version
# (pristine); PRESERVE and report any diverged (tuned) copy. Then ensure plugins
# enabled. The settings.json hook-wiring surgery + diverged reconciliation are the
# project-adopt skill's job (judgment), not this script's.
set -euo pipefail

self="$(realpath -e "$0" 2>/dev/null || printf '%s' "$0")"
scaffold_root="$(cd "$(dirname "$self")/.." && pwd)"
core_root="$(cd "$scaffold_root/../core" && pwd)"
proj="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$proj"
command -v jq >/dev/null 2>&1 || { echo "adopt: jq required" >&2; exit 2; }

pairs="\
.claude/hooks/block-main-writes.sh|$core_root/hooks/block-main-writes.sh
.claude/hooks/guard-secrets.sh|$core_root/hooks/guard-secrets.sh
.claude/hooks/checkpoint.sh|$scaffold_root/hooks/checkpoint.sh
.claude/hooks/subagent-trail.sh|$scaffold_root/hooks/subagent-trail.sh
.claude/hooks/validate-config.sh|$scaffold_root/hooks/validate-config.sh"

diverged=""
while IFS='|' read -r vend ship; do
  [ -f "$vend" ] || continue
  if [ -f "$ship" ] && cmp -s "$vend" "$ship"; then
    git rm -q "$vend" 2>/dev/null || rm -f "$vend"
    echo "removed pristine twin: $vend"
  else
    diverged="$diverged $vend"
    echo "PRESERVED (diverged/tuned): $vend"
  fi
done <<EOF
$pairs
EOF

if [ -f .claude/settings.json ]; then
  tmp="$(mktemp)"
  jq '.enabledPlugins["core@mrinal-skills"]=true
      | .enabledPlugins["scaffold@mrinal-skills"]=true' \
     .claude/settings.json > "$tmp" && mv "$tmp" .claude/settings.json
  echo "ensured core+scaffold enabled"
fi

echo "adopt: pristine twins removed; plugins enabled."
echo "NEXT (skill/user): rewrite .claude/settings.json to the complement — drop wiring that"
echo "references the removed hooks; keep statusLine, context-nudge, SessionStart, placeholders."
[ -n "$diverged" ] && { echo "RECONCILE these tuned files manually:"; printf '  %s\n' $diverged; }
exit 0
```
`chmod +x scaffold/scripts/adopt-substrate.sh`.

- [ ] **Step 4: Run the fixture test — expect PASS**

Run: `bash scripts/test-adopt.sh; echo "exit=$?"`
Expected: `ALL PASS`, exit 0.

- [ ] **Step 5: Write the `project-adopt` skill + `/scaffold:adopt` command**

Create `scaffold/skills/project-adopt/SKILL.md`:
```markdown
---
name: project-adopt
description: >-
  Use to migrate an EXISTING starter-derived repo onto the core+scaffold plugins
  without data loss. Trigger on /scaffold:adopt. Removes only pristine vendored hook
  twins, preserves tuned copies, and rewrites settings.json to the plugin complement.
---

# Adopt an existing repo onto the plugins

## 1. Deterministic strip (script)

On a fresh branch (`git switch -c chore/adopt-plugins`), run:

    bash "${CLAUDE_PLUGIN_ROOT}/scripts/adopt-substrate.sh"

It removes vendored hook scripts that are byte-identical to the shipped plugin version,
PRESERVES any diverged (tuned) copy, and ensures core+scaffold are enabled. Read its
output: the "RECONCILE" list is files it refused to touch.

## 2. Settings complement (judgment)

Rewrite `.claude/settings.json` so it is the strict COMPLEMENT of the plugin hooks:
- **Remove** every hook entry that referenced a now-removed vendored script
  (block-main-writes, guard-secrets, checkpoint, subagent-trail, validate-config).
- **Keep** statusLine, both context-nudge entries, SessionStart(compact)→cat RESUME.md,
  and the project placeholders (format-on-save, offline-check, env-probe).
- Never re-add plugin-hook wiring (double-fire races the git index; duplicates breadcrumbs).

## 3. Reconcile tuned files

For each file on the RECONCILE list, show the user the diff vs the shipped plugin version
and let them decide: keep the tuned project copy (it wins over the namespaced plugin by
precedence), or delete it to adopt the plugin's. Do not delete a tuned file unprompted.

## 4. Commit on the chore/adopt-plugins branch.
```
Create `scaffold/commands/adopt.md`:
```markdown
---
description: Migrate an existing starter-derived repo onto the core+scaffold plugins, non-destructively.
model: claude-opus-4-8
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, AskUserQuestion, Skill
---
Load and follow the `project-adopt` skill to migrate this repository onto the plugins.
Work on a `chore/adopt-plugins` branch. Never delete a tuned (diverged) file without
showing the user the diff and asking.
```

- [ ] **Step 6: Wire CI; validate; commit**

Add to `.github/workflows/validate.yml`:
```yaml
      - name: test adopt fixture
        run: ./scripts/test-adopt.sh
```
Run:
```bash
shellcheck scaffold/scripts/adopt-substrate.sh scripts/test-adopt.sh
./scripts/validate.sh
bash scripts/test-adopt.sh
```
Expected: clean, green, `ALL PASS`.
```bash
git add scaffold/scripts/adopt-substrate.sh scripts/test-adopt.sh scaffold/skills/project-adopt/SKILL.md scaffold/commands/adopt.md .github/workflows/validate.yml
git commit -m "feat(scaffold): non-destructive adopt core + project-adopt skill + /scaffold:adopt + fixture test"
```

---

## Task 6: Migrate the statusline + context-nudge template tests

**Why here:** these test the bundled templates (Task 3), so they land after the templates exist.

**Files:**
- Create: `scripts/test-statusline.sh`, `scripts/test-context-nudge.sh`
- Modify: `.github/workflows/validate.yml`
- Read-only source: `../claude-code-starter/.claude/hooks/tests/{statusline_test.sh,nudge_test.sh}`

- [ ] **Step 1: Migrate both, pointing at the templates**

Copy `statusline_test.sh` → `scripts/test-statusline.sh`; change its two-level resolver
```bash
script="$(cd "$here/../.." && pwd)/statusline.sh"
```
to
```bash
REPO="$(cd "$here/.." && pwd)"
script="$REPO/scaffold/skills/project-bootstrap/templates/statusline.sh"
```
Copy `nudge_test.sh` → `scripts/test-context-nudge.sh`; change its resolver
```bash
hook="$(cd "$here/.." && pwd)/context-nudge.sh"
```
to
```bash
REPO="$(cd "$here/.." && pwd)"
hook="$REPO/scaffold/skills/project-bootstrap/templates/context-nudge.sh"
```
Keep the `.claude/state/context-usage.json` bridge fixtures verbatim (the templates use that exact path). `chmod +x` both.

- [ ] **Step 2: Run both — expect PASS**

Run: `bash scripts/test-statusline.sh && bash scripts/test-context-nudge.sh; echo "exit=$?"`
Expected: both exit 0.

- [ ] **Step 3: Wire CI + shellcheck the templates + commit**

Add to `.github/workflows/validate.yml`:
```yaml
      - name: test statusline template
        run: ./scripts/test-statusline.sh
      - name: test context-nudge template
        run: ./scripts/test-context-nudge.sh
```
Also extend the shellcheck glob to include the template scripts:
```yaml
        run: shellcheck scripts/*.sh core/hooks/*.sh scaffold/hooks/*.sh scaffold/scripts/*.sh scaffold/skills/project-bootstrap/templates/*.sh
```
Run: `shellcheck scripts/test-statusline.sh scripts/test-context-nudge.sh` → clean.
```bash
git add scripts/test-statusline.sh scripts/test-context-nudge.sh .github/workflows/validate.yml
git commit -m "test: migrate statusline + context-nudge template regression tests into CI"
```

---

## Task 7: Docs, version bump, and full green

**Files:**
- Modify: `scaffold/README.md`, `scaffold/.claude-plugin/plugin.json`

- [ ] **Step 1: Bump the scaffold plugin version**

In `scaffold/.claude-plugin/plugin.json`, change `"version": "0.1.0"` → `"version": "0.2.0"`.

- [ ] **Step 2: Rehome the user-level orphan that can't be plugin-delivered**

`../claude-code-starter/.claude/user-claude-md-section.md` is the operating-discipline block that `install-user.sh` appended to `~/.claude/CLAUDE.md`. A plugin cannot write user-level `~/.claude/CLAUDE.md`, so its canonical source must survive the archive. Create `docs/user-setup.md` in this repo capturing (a) one-time machine setup — add the `mrinal-skills` marketplace and enable `core` globally — and (b) the operating-discipline section verbatim from that file, framed as the text to paste into `~/.claude/CLAUDE.md`. Verify: `[ -s docs/user-setup.md ]`.

- [ ] **Step 3: Document the new surface in `scaffold/README.md`**

Add a section covering: the generator (`/scaffold:bootstrap` → `project-bootstrap` skill + `emit-substrate.sh` + `templates/`), the migration (`/scaffold:adopt` → `project-adopt` skill + `adopt-substrate.sh`), the relocated runner (`/scaffold:milestone-run`), and the **enable→bootstrap flow** for a new repo:
```markdown
## Bootstrapping a new repo

1. In the new repo: enable this plugin — `/plugin` → enable `scaffold@mrinal-skills`
   (auto-enables `core`), or add `"scaffold@mrinal-skills": true` to `.claude/settings.json`
   `enabledPlugins`. Restart Claude Code.
2. Run `/scaffold:bootstrap`. It emits `.context/`, `docs/decisions/`, `milestones/`, the
   statusline + settings wiring, and `CLAUDE.md`, then fills stack-specific placeholders.
3. Existing starter-derived repos: run `/scaffold:adopt` instead (non-destructive migration).
```
Note explicitly that the generated `settings.json` is the **complement** of the plugin hooks and must never re-wire them.

- [ ] **Step 4: Full local CI + commit**

Run the whole suite:
```bash
shellcheck scripts/*.sh core/hooks/*.sh scaffold/hooks/*.sh scaffold/scripts/*.sh scaffold/skills/project-bootstrap/templates/*.sh
./scripts/validate.sh
for t in scripts/test-*.sh; do echo "== $t =="; bash "$t" || { echo "FAILED: $t"; break; }; done
```
Expected: clean shellcheck, validate.sh green, every `test-*.sh` prints `ALL PASS`/exit 0.
```bash
git add scaffold/README.md scaffold/.claude-plugin/plugin.json docs/user-setup.md
git commit -m "docs(scaffold): document generator/adopt/runner + enable→bootstrap flow; rehome user-setup; bump scaffold to 0.2.0"
```

---

## Out of session (user-driven — DO NOT run here)

These are the user's manual/acceptance steps, per the spec §13 phase 6 and the session constraints:

- **Manual scratch-repo acceptance:** in a throwaway repo, enable `scaffold@mrinal-skills`, run `/scaffold:bootstrap`, confirm the project builds/tests/lints and the checkpoint/statusline/nudge loop works; then test `/scaffold:adopt` on a copy of a real starter-derived repo.
- **Archive `claude-code-starter`:** only after the above passes — archive read-only (keep `docs/meta/` + the ADR trail for provenance). Not done in this session.
- **`/scaffold:adopt` against live repos** (`handled-next`, …): user-run, never in this session.

## Post-implementation verification (this repo)

Before opening a PR for `feat/scaffold-generator`: run the full suite in "Task 7 Step 3", confirm all green, and confirm `git status` is clean. The PR merges the plugin changes only; it does not touch any other repo.
