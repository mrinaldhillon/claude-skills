# Dissolve `claude-code-starter` into the `scaffold` generator

- **Date:** 2026-07-14
- **Status:** Draft — pending user review
- **Audience/owner:** Personal (single user). No third-party template consumers.
- **Repos in scope:**
  - `next/claude-skills` (this repo) — the `mrinal-skills` marketplace: plugins `core` (global) and `scaffold` (per-repo). Primary work lands here.
  - `next/claude-code-starter` — the copy-me template being dissolved and archived.

## 1. Goal

Reach **zero dependency on the `claude-code-starter` repo**. New projects must no longer *copy* a template; they enable the `scaffold` plugin and run one generator command. The dependency shifts from *"clone-and-drift a repo"* → *"enable a versioned plugin,"* updatable via `/plugin update`.

"Zero dependency" means zero dependency on **the repo**. It does **not** mean zero substrate: every project still needs `.context/`, ADR conventions, a status-line bridge, and `settings.json` wiring. That substrate is **generated on demand** from templates bundled inside the plugin, not carried in from a template checkout.

Non-goal: eliminating the one-time, per-repo `/plugin` enable step (see §9, chicken-and-egg). That step depends on the *marketplace* — the intended replacement — not on `claude-code-starter`.

## 2. Background: current state (verified)

- **Coupling is strictly one-way.** `claude-code-starter` contains **zero** references to the marketplace, `core`, `scaffold`, or `mrinal-skills`. The plugins were extracted *from* the starter; the starter is unaware they exist. Thinning is therefore greenfield-clean — no dangling refs to chase inside it.
- **Duplication is near-total (20 components).** Every logic artifact in the starter already has a plugin twin:
  - **→ `core` (10):** agents `code-reviewer`, `config-auditor`, `doc-sync`, `search`; skills `deep-research-tiered`, `git-workflow`, `orchestration`; hooks `block-main-writes`, `guard-secrets`; output-style `distinguished-engineer`. (`checkpoint.sh` spot-checked byte-identical across trees.)
  - **→ `scaffold` (10):** agent `determinism-auditor`; commands `/adr`, `/goal`, `/milestone`; hooks `checkpoint`, `subagent-trail`, `validate-config`; skills `dev-workflow`, `milestone-workflow`, `skill-maintenance`.
- **`install-user.sh` is only *partially* superseded.** Its agent/skill/hook/style payload == `core`. But **two payloads cannot be plugin-delivered** — a plugin can write neither user `settings.json` nor `~/.claude/CLAUDE.md`:
  - the curated `enabledPlugins` merge of 8 `@claude-plugins-official` plugins (`install-user.sh:84–94`);
  - the operating-discipline append to `~/.claude/CLAUDE.md` (source `user-claude-md-section.md`, `install-user.sh:96–107`).
  These are already applied to this machine, but their **canonical sources disappear on archive** unless rehomed (§8).
- **`template-sync` is obsoleted** by `/plugin update` for the shared layer; only *substrate reconciliation* residual survives (folded into the generator/adopt commands rather than a standalone sync skill).
- **The milestone subsystem is loosely coupled** (memory previously overstated it):
  - `scripts/milestone-runner.sh:286,299` calls `bash .claude/hooks/checkpoint.sh … || true` — a **direct repo-relative path**, `|| true`-masked.
  - the runner binds `orchestration`/`search` only via **prompt strings** (runner:201–203), not hard subagent dispatch.
- **STARTER-ONLY residue** (no plugin twin): `statusline.sh`, `context-nudge.sh`, `scripts/milestone-runner.sh`, `.context/` layout + `README.md`, `milestones/`, `docs/decisions/` conventions + `TEMPLATE.md` + ADRs `0000–0007`, `project-bootstrap` skill, `template-sync` skill, `user-claude-md-section.md`, and the `settings.json` `statusLine`/hook wiring.

## 3. Platform facts that force the architecture (verified against `code.claude.com/docs`)

| Capability | Result | Citation |
|---|---|---|
| Plugin hooks reference bundled scripts via `${CLAUDE_PLUGIN_ROOT}` and receive `${CLAUDE_PROJECT_DIR}` (so a plugin hook reads/writes the *project's* files) | ✅ Yes | `plugins-reference` L647–655 |
| A plugin skill/command reads bundled `templates/` via `${CLAUDE_PLUGIN_ROOT}` and `Write`s into `${CLAUDE_PROJECT_DIR}` (the generator pattern); no "read-only" restriction | ✅ Yes | `plugins-reference` L760–826 |
| `${CLAUDE_PLUGIN_ROOT}` resolves in slash-command/skill content (re-resolved per invocation) | ✅ Yes | `plugins-reference` L649 |
| A project `settings.json` `statusLine.command` can reference a plugin path | ❌ **No** — gets only stdin JSON + `COLUMNS`/`LINES` | `statusline` L151 |
| Installed plugin path is stable across `/plugin update` | ❌ **No** — path changes each update; prior version retained ~7 days | `plugins-reference` L649 |

Consequences: the status-line bridge is forced project-side; a *baked* plugin path is unsafe (goes stale on update) so out-of-session tooling must re-resolve `${CLAUDE_PLUGIN_ROOT}` per call via a slash-command entry.

## 4. Decision: per-subsystem placement

The naive framing ("where do the two leftover scripts live") is wrong: each coupled subsystem has a **forced** home. Update-propagation via `/plugin update` is *already* delivered by the completed hooks migration; the leftover files are precisely the two the plugin mechanism cannot deliver.

| Subsystem | Home | Rationale |
|---|---|---|
| Generic hooks (`checkpoint`, `subagent-trail`, `validate-config`, `block-main-writes`, `guard-secrets`) | **plugin** (already) | `${CLAUDE_PLUGIN_ROOT}` + `${CLAUDE_PROJECT_DIR}` resolve in hooks |
| **Status-line bridge pair** — `statusline.sh` (writer) + `context-nudge.sh` (reader) | **generated project-local, together** | `statusLine` key can't be plugin-set; writer/reader share a bridge-file schema and must version *together* — splitting them across the boundary risks staleness/schema skew |
| `milestone-runner.sh` | **plugin `scripts/`**, entered via `/scaffold:milestone-run` | runs *outside* any session (spawns `claude -p`), so it never sees `${CLAUDE_PLUGIN_ROOT}`; the install path changes on update. A slash-command entry re-resolves the var per call → update-safe |
| Substrate (state + conventions) | **generated project-local** from bundled `templates/` | per-project content |
| Logic (agents/skills/commands/style) | **plugin** (already) | done |

**Accepted tradeoff — the status-line pair is out of `/plugin update`.** Generating `context-nudge.sh` project-local (to keep it schema-locked to its `statusline.sh` writer) freezes the *nudge logic* — the more likely half of the pair to evolve — out of automatic plugin updates. Accepted because the pair is low-churn and must version together. Its update path is **re-generation**, not `/plugin update`: re-running the generator's substrate step (or `/scaffold:adopt`) re-emits the pair from the plugin's bundled templates, so it is refreshable-on-demand, not permanently frozen. Revisit only if nudge logic starts churning.

## 5. Architecture: three layers

1. **`core`** (global, unchanged logic). Gains only rehomed *reference* material that can't be plugin-delivered but must survive the archive (§8): the `user-claude-md-section.md` discipline text and the curated `enabledPlugins` list, as marketplace-repo user-setup docs (not executable plugin content).
2. **`scaffold`** (per-repo). Gains:
   - the **generator**: `/scaffold:bootstrap` command → `project-bootstrap` skill → bundled `templates/`;
   - the **runner**: `scripts/milestone-runner.sh` + `/scaffold:milestone-run` entry;
   - the **migration**: `/scaffold:adopt` command/skill;
   - **plugin reference docs**: the *machinery-rationale* ADRs `0004` (milestone loop) + `0006` (permission profiles), and the `go-example` worked model;
   - the **migrated tests** (§10).
3. **Generated project substrate** (per bootstrapped repo, emitted by the generator): `.context/` seed + `README.md`; `milestones/example.json`; `docs/decisions/` seed ADRs — the *convention* ADRs `0000,0001,0002,0003,0005,0007` plus pointer stubs at `0004,0006` (§8) — and `TEMPLATE.md`; `docs/` skeletons; filled `CLAUDE.md`; `.claude/statusline.sh` + `.claude/context-nudge.sh`; and `.claude/settings.json` **complement** wiring (§6).

## 6. What the generator emits — and the settings.json *complement* invariant

`/scaffold:bootstrap` writes only **project-owned** files. The single most error-prone artifact is `settings.json`: it MUST be the strict **complement** of the plugin-provided hooks.

**Generated `settings.json` contains ONLY:**
- `statusLine.command` → `${CLAUDE_PROJECT_DIR}/.claude/statusline.sh`;
- `context-nudge` wiring (`UserPromptSubmit` + `PostToolUse`) → project-local `.claude/context-nudge.sh`;
- `SessionStart(compact)` → `cat .context/RESUME.md`;
- the three project placeholders the bootstrap fills for the stack: format-on-save (starter `settings.json:34`), offline-check (`:68`), env-probe (`:114`);
- `enabledPlugins` seeded with at least `core` + `scaffold` (plus the curated official set).

**It MUST NOT re-wire** `checkpoint`, `subagent-trail`, `validate-config`, `block-main-writes`, `guard-secrets` — those arrive from the plugins. Rationale (a real defect, not tidiness): same-event double-wiring makes two `checkpoint.sh` instances race on the git `index.lock` (both run `git add`/`commit` under `set -euo pipefail`), and double-wires the append-only `subagent-trail` into **duplicate** breadcrumbs.

## 7. Correctness requirements (each closes a verified defect)

1. **Complement invariant** (§6) — enforced by the generator and asserted in CI.
2. **Bootstrap branches before its first commit.** `core/hooks/block-main-writes.sh` denies `git commit` on `main`, and `git branch --show-current` reports `main` even on an *unborn* HEAD — so the very first commit in a fresh repo is denied. Bootstrap must `git switch -c chore/bootstrap` first (works on unborn HEAD), or hand the first commit to the user.
3. **Runner resolves `checkpoint.sh` by realpath.** After the runner moves into the plugin, its `bash .claude/hooks/checkpoint.sh || true` calls (runner:286,299) silently no-op forever. Resolve the sibling hook via the runner's own `realpath` (`runner_path` already computed at :47) and drop the failure-masking `|| true` on the resolution itself. Bonus: an out-of-repo runner *strengthens* its self-tamper boundary — an `acceptEdits` session can no longer edit its own verifier.
4. **Verify `dependencies:["core"]` auto-enable is honored** by Claude Code before documenting it as fact (`scaffold/.claude-plugin/plugin.json:16`, README:12–13). Harmless here (core is global) but the README must not overclaim.
5. **Bootstrap is re-entrant and non-destructive.** Under the plugin model it **cannot self-delete** (unlike the old `project-bootstrap` skill). So a second `/scaffold:bootstrap` must not clobber live state: **merge** into an existing `.claude/settings.json` (never Write-fresh — that would drop the `enabledPlugins` entry that made the command runnable), and **never overwrite an existing `.context/`** (live agent state). Treat existing substrate as present-unless-absent.
6. **`/scaffold:adopt` is non-destructive by default** (§10): hash-compare before delete; preserve diverged (tuned) files; report, don't clobber.

## 8. Extraction plan — GATING (must precede archiving)

Archiving `claude-code-starter` before these move loses live assets:

- **Tests (8):** the 7 hook tests in `.claude/hooks/tests/` + `scripts/tests/milestone-runner_test.sh`. Migrate into `scaffold` (paths adjusted; the runner test's `checkpoint.sh` stub + realpath resolution updated) and wire into marketplace CI. Today, marketplace CI covers only `block-main-writes`; without migration the plugin copies of `checkpoint`/`subagent-trail`/`validate-config`/`guard-secrets` and the runner go untested.
- **`go-example`** (6 files) is load-bearing: `bootstrap.md:19` uses it as the worked model for build-recipe generation. Bundle it as a plugin resource under the generator, or rewrite that step to not need it.
- **ADR split — by *nature*, not by number.** Classify each ADR as *project convention / decision-of-record* (seed) vs *plugin-machinery rationale* (plugin reference):
  - **Seed (conventions every project needs):** `0000` record-decisions, `0001` trunk-based, `0002` branch-protection-by-discipline, `0003` context-mgmt-by-checkpoint-resume (the discipline the generated `CLAUDE.md` §"Context & checkpoint protocol" states), `0005` agent-state-in-`.context/` (defines the layout the generator *creates*), `0007` annotate-superseded-in-place (**amends `0000` — must travel with it**, else a dangling amendment pointer).
  - **Plugin reference (machinery rationale that `/plugin update` owns):** `0004` context-managed milestone loop, `0006` milestone permission profiles — pure runner internals.
  - **Numbering rule (append-only preserved):** the two relocated slots are seeded as **one-paragraph pointer stubs** at `0004`/`0006` ("machinery of record now lives in the scaffold plugin's ADR set; slot retained to preserve append-only numbering"). This keeps the project's decision log contiguous with **no gaps and no desync** (the stub is stable; the full rationale evolves in the plugin). The project's `/adr` continues from `0008`.
- **Orphans to rehome:** `user-claude-md-section.md` + curated `enabledPlugins` → marketplace user-setup docs (§5, layer 1); `.context/README.md` contract, `docs/decisions/TEMPLATE.md`, `milestones/example.json` → generator `templates/`.

## 9. Failure modes & risks

- **Chicken-and-egg (benign):** a new/empty repo has no `scaffold` enabled, so `/scaffold:bootstrap` doesn't exist yet. Flow: enable `scaffold@mrinal-skills` (`/plugin`, or hand-write `.claude/settings.json`) → restart → `/scaffold:bootstrap`. One residual manual step; the dependency is on the *marketplace* (the intended replacement), so the zero-`claude-code-starter`-dependency goal holds. **Do not** move bootstrap into `core` to shave the step — that pollutes core's project-agnostic contract.
- **Double-fire on *existing* repos:** any starter-derived repo (e.g. `handled-next`) still carries vendored copies of the plugin hooks. Enabling `scaffold` there collides immediately (index-lock race + duplicate breadcrumbs). Addressed by `/scaffold:adopt` (§10).
- **Plugin-path staleness:** `${CLAUDE_PLUGIN_ROOT}` changes on `/plugin update`; never bake it into generated files or out-of-session scripts. The runner entry re-resolves per call.
- **Runner background UX:** `/scaffold:milestone-run` kicks off a long-running loop that spawns `claude -p` sessions. Confirm the invocation model (foreground Bash vs backgrounded) during implementation; out of scope for the design.

## 10. `/scaffold:adopt` — migrate an existing starter-derived repo

Converts a repo that vendored the old `.claude/` onto the plugins, safely. **Non-destructive by default** — a repo may run *tuned* copies (e.g. `handled-next`, from which `orchestration`/`git-workflow` were originally extracted), and blind deletion would destroy them.

1. **Strip only *pristine* vendored twins.** For each candidate in `.claude/{hooks,agents,skills,commands,output-styles}` that has a `core`/`scaffold` twin, **hash-compare against the plugin's shipped version** (resurrect `install-user.sh`'s hash-manifest / skip-and-warn discipline):
   - **exact match (pristine vendored):** delete — the namespaced plugin version takes over.
   - **diverged (vendored-then-tuned):** **preserve and report.** The tuned project copy stays and, per precedence (project skills/agents win over namespaced plugin ones), keeps working. Never overwrite a diverged file; surface the list for the user to reconcile.
   - Candidates: `.claude/hooks/{checkpoint,subagent-trail,validate-config,block-main-writes,guard-secrets}.sh` and any twin `.claude/{agents,skills,commands,output-styles}`.
2. **Enable** `core` + `scaffold` in the repo's `enabledPlugins`.
3. **Rewrite `settings.json`** to the complement wiring (§6): drop the stripped hooks' wiring; keep/repair `statusLine`, `context-nudge`, `SessionStart(compact)`, and the project placeholders.
4. **Keep project-owned substrate** in place (`.context/`, `milestones/`, `docs/decisions/`, `statusline.sh`, `context-nudge.sh`, `CLAUDE.md`).
5. **Relocate the runner:** if the repo runs `scripts/milestone-runner.sh`, switch its checkpoint resolution and its own home to the plugin-provided entry.

Idempotent; runs on a `chore/adopt-plugins` branch (§7.2).

## 11. Testing & CI

- **Generator self-test (primary):** in marketplace CI, run `/scaffold:bootstrap` into a temp dir and assert the emitted substrate — files present, `settings.json` is the complement (no plugin-hook wiring), first commit lands on a non-`main` branch. Test the **generator's output**, never the stale template as a fixture (that tests the wrong artifact and quietly re-creates the dependency being removed).
- **Migrated hook + runner tests (8)** run in CI against the plugin copies.
- **`/scaffold:adopt` test:** seed a fixture repo carrying vendored hooks; run adopt; assert twins stripped, complement wiring, no double-wiring.

## 12. Disposition of `claude-code-starter`

**Archive read-only, *after* extraction (§8).** Reject delete: `docs/meta/*` + the ADR trail are the sole provenance for the design rationale. Reject demoting it to the plugin's test fixture: the correct fixture is the generator's own output, not the frozen template.

## 13. Rollout sequence (phases → become the implementation plan)

1. **Extract** (gating): migrate 8 tests + CI wiring; rehome `go-example`, ADRs `0003–0007`, orphans; land the correctness fixes (runner realpath).
2. **Build the runner relocation** + `/scaffold:milestone-run` entry.
3. **Build the generator**: `project-bootstrap` skill + `/scaffold:bootstrap` + `templates/` (incl. `statusline.sh` + `context-nudge.sh` pair, seed convention ADRs + pointer stubs per §8, `.context/`, `CLAUDE.md`); enforce the complement invariant + branch-before-commit + re-entrancy (§7.5).
4. **Build `/scaffold:adopt`** + its fixture test.
5. **Self-test in CI** (bootstrap-into-tempdir).
6. **Archive** `claude-code-starter` read-only.

## 14. Out of scope / non-goals

- Removing the one-time per-repo `/plugin` enable step.
- Changing `core`'s contents or contract (only receives rehomed reference docs).
- Public/third-party template distribution (audience is the single owner).
- Reworking the milestone/ADR *conventions* themselves — only their placement changes.

## 15. Open items to resolve during implementation (not design blockers)

- Confirm `dependencies:["core"]` auto-enable behavior (§7.4).
- Decide `go-example` rehome mechanism: bundled plugin resource vs. rewritten bootstrap step (§8).
- Confirm the `/scaffold:milestone-run` foreground/background invocation model (§9).
