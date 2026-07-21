#!/usr/bin/env bash
# scripts/milestone-runner.sh — context-managed milestone loop (ADR 0004).
#
# Runs a milestone as a sequence of FRESH `claude -p` sessions — "clear" as a
# process boundary. Each iteration: resume from the checkpoint files
# (.context/project-context.md, .context/RESUME.md), do ONE coherent chunk
# (orchestrating tiered subagents per the orchestration skill), pass a
# deterministic iteration gate, re-checkpoint. The loop ends when the session
# writes .context/MILESTONE_DONE *and* the done_gate passes — or stops early on the
# first failure. No retry: stop-and-triage (ADR 0004).
#
# Never --bare (would skip hooks + CLAUDE.md). Never --resume (context accretes;
# the checkpoint files carry the state). The checkpoint hook fires on PreCompact
# only (its per-turn Stop trigger was removed — it landed a commit every turn),
# so the explicit checkpoint.sh calls below are what commit durable state at
# each iteration boundary.
#
# Usage:
#   scripts/milestone-runner.sh milestones/<name>.json
#   DRY_RUN=1 scripts/milestone-runner.sh milestones/<name>.json
#   AUTOCOMPACT_PCT=60 PHASE_TIMEOUT=900 MILESTONE_MODEL=... (overrides)
#
# Permission profiles (config "permission_profile", ADR 0006):
#   strict (default) — acceptEdits + explicit allowlist; any denial fails the run.
#   auto             — classifier mode + OS sandbox (auto-allowed sandboxed Bash);
#                      no per-command allowlisting; denials logged, gates arbitrate.
#   bypass           — --dangerously-skip-permissions; refused unless containment
#                      is attested (MILESTONE_CONTAINED=1 or /.dockerenv).
#
# Exit: 0 done · 1 gate/trust/false-done · 2 bad config/env/pre-run state ·
#       3 CLI/API/denials · 4 branch refusal · 5 lock held · 6 replan requested ·
#       7 iterations exhausted
set -uo pipefail

config_file="${1:?usage: milestone-runner.sh <milestone.json>}"
command -v jq >/dev/null 2>&1 || { echo "runner: jq is required" >&2; exit 2; }

# Resolve the config to an absolute path BEFORE any cd — a caller-relative path
# must survive the cd to the repo root — and require it to live INSIDE the repo
# this runner is about to drive: the repo is derived from the caller's cwd, and
# accepting a config from elsewhere would aim `claude -p` + acceptEdits at
# whatever tree the caller happens to stand in (wrong-repo hazard).
config_file="$(realpath -e "$config_file" 2>/dev/null || realpath "$config_file" 2>/dev/null)" \
  && [ -f "$config_file" ] \
  || { echo "runner: no such config: $1" >&2; exit 2; }
# Pin the runner's own path pre-cd as well: a caller-relative $0 stops
# resolving after the cd, which would sha-pin an empty string and silently
# disarm the self-tamper check below.
runner_path="$(realpath -e "$0" 2>/dev/null || printf '%s' "$0")"
# Resolve the checkpoint hook as the runner's plugin sibling (scaffold/hooks/),
# not repo-relative — a dissolved project has no .claude/hooks/checkpoint.sh.
# CHECKPOINT_SH overrides for tests.
checkpoint_sh="${CHECKPOINT_SH:-$(dirname "$runner_path")/../hooks/checkpoint.sh}"
repo="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "runner: not a git repo" >&2; exit 2; }
cd "$repo" || exit 2
case "$config_file" in
  "$repo"/*) ;;
  *) echo "runner: config $config_file is outside this repo ($repo) — run from the repo the milestone targets" >&2; exit 2 ;;
esac

# --- config: read ONCE into memory; the disk file is sha-pinned below ---------
config="$(cat "$config_file")"
jq -e . <<<"$config" >/dev/null 2>&1 || { echo "runner: config is not valid JSON" >&2; exit 2; }
for key in milestone goal model allowed_tools max_budget_usd_per_iteration max_iterations iteration_gate done_gate; do
  jq -e --arg k "$key" 'has($k)' <<<"$config" >/dev/null \
    || { echo "runner: config missing '$key'" >&2; exit 2; }
done
jq -e '(.max_iterations | type == "number") and .max_iterations >= 1
   and (.max_budget_usd_per_iteration | type == "number") and .max_budget_usd_per_iteration > 0' \
  <<<"$config" >/dev/null || { echo "runner: bad max_iterations / max_budget_usd_per_iteration" >&2; exit 2; }

milestone="$(jq -r '.milestone' <<<"$config")"
goal="$(jq -r '.goal' <<<"$config")"
model="${MILESTONE_MODEL:-$(jq -r '.model' <<<"$config")}"   # tiering: session = orchestrator
allowed_tools="$(jq -r '.allowed_tools' <<<"$config")"
iter_budget="$(jq -r '.max_budget_usd_per_iteration' <<<"$config")"
max_iterations="$(jq -r '.max_iterations' <<<"$config")"
iteration_gate="$(jq -r '.iteration_gate' <<<"$config")"
done_gate="$(jq -r '.done_gate' <<<"$config")"

# --- permission profile (ADR 0006): strict | auto | bypass ----------------------
# strict: acceptEdits + explicit allowlist; a denial fails the iteration.
# auto:   --permission-mode auto (classifier) + native OS sandbox with
#         auto-allowed sandboxed Bash — no per-Bash-command allowlisting (still
#         passes --allowedTools to scope tool FAMILIES, e.g. exclude WebFetch);
#         denials are logged, not fatal (classifier blocks are by-design
#         feedback; the CLI's own 3-consecutive/20-total abort thresholds + the
#         gates arbitrate).
# bypass: --dangerously-skip-permissions — REFUSED unless containment is attested
#         (MILESTONE_CONTAINED=1 or /.dockerenv), per the official guidance:
#         containers/VMs only, non-root, egress-restricted.
permission_profile="$(jq -r '.permission_profile // "strict"' <<<"$config")"
sandbox_domains="$(jq -c '.sandbox_allowed_domains // []' <<<"$config")"
case "$permission_profile" in
  strict)
    perm_args=(--permission-mode acceptEdits --allowedTools "$allowed_tools") ;;
  auto)
    sandbox_settings="$(jq -nc --argjson d "$sandbox_domains" \
      '{sandbox:{enabled:true, autoAllowBashIfSandboxed:true,
                 filesystem:{allowRead:["."], allowWrite:["."]},
                 network:{allowedDomains:$d}}}')"
    perm_args=(--permission-mode auto --settings "$sandbox_settings" \
               --allowedTools "$allowed_tools") ;;
  bypass)
    perm_args=(--dangerously-skip-permissions) ;;
  *)
    echo "runner: unknown permission_profile '$permission_profile' (strict|auto|bypass)" >&2
    exit 2 ;;
esac

# --- branch guard: checkpoints only commit on non-main branches (ADR 0002) ----
branch="$(git symbolic-ref --short -q HEAD || echo DETACHED)"
if [ "$branch" = "main" ] || [ "$branch" = "DETACHED" ]; then
  echo "runner: refusing to run on $branch — create a milestone branch first (ADR 0001/0002)" >&2
  exit 4
fi

# --- sentinels: never start over stale state ----------------------------------
if [ -f .context/REPLAN.md ]; then
  echo "runner: .context/REPLAN.md exists — resolve the replan (and remove the file) before running" >&2
  exit 6
fi
if [ -f .context/MILESTONE_DONE ]; then
  done_name="$(head -n1 .context/MILESTONE_DONE | tr -d '[:space:]')"
  if [ "$done_name" = "$milestone" ]; then
    if ( eval "$done_gate" ) >/dev/null 2>&1; then
      echo "runner: milestone '$milestone' already recorded done and done_gate passes — nothing to do"
      exit 0
    fi
    echo "runner: .context/MILESTONE_DONE claims '$milestone' but done_gate FAILS — state desync, triage manually" >&2
    exit 1
  fi
  echo "runner: stale .context/MILESTONE_DONE for '$done_name' — remove it before running '$milestone'" >&2
  exit 2
fi

if [ -n "${DRY_RUN:-}" ]; then
  echo "DRY RUN: milestone '$milestone' · model $model · up to $max_iterations iteration(s)"
  echo "DRY RUN: profile=$permission_profile · allowed_tools=$allowed_tools · budget/iter \$$iter_budget"
  echo "DRY RUN: iteration_gate: $iteration_gate"
  echo "DRY RUN: done_gate:      $done_gate"
  echo "DRY RUN: no sessions spawned, no state written"
  exit 0
fi

# --- bypass containment gate (ADR 0006): never bypass on a bare host ------------
if [ "$permission_profile" = "bypass" ] \
   && [ -z "${MILESTONE_CONTAINED:-}" ] && [ ! -f /.dockerenv ]; then
  echo "runner: profile 'bypass' refused — no containment detected. Run inside a container/VM" >&2
  echo "        (non-root, repo-only mount, egress-restricted) and set MILESTONE_CONTAINED=1." >&2
  exit 2
fi

# --- lock: one run per repo (mkdir is atomic; no flock on stock macOS) ---------
lock_dir=".claude/state/milestone.lock"
mkdir -p .claude/state
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "runner: lock held ($(cat "$lock_dir/pid" 2>/dev/null || echo '?')) — another run in progress? rm -rf $lock_dir if stale" >&2
  exit 5
fi
echo $$ > "$lock_dir/pid"
trap 'rm -rf "$lock_dir"' EXIT INT TERM

# --- zero-cost flag probe: catch CLI flag drift at every start -----------------
# No input → the CLI errors before any API call if the flags parse; an
# "unknown option" error names the drifted flag. (--help greps false-negative
# on hidden-but-working flags — parked plan, bug 6.) Probes the PROFILE's real
# flags, so --permission-mode auto / --settings / bypass drift is caught too.
probe_out="$(claude -p --model "$model" "${perm_args[@]}" \
  --output-format json --max-budget-usd 0.01 </dev/null 2>&1)" || true
if grep -qiE "unknown (option|argument)|unrecognized" <<<"$probe_out"; then
  echo "runner: CLI flag drift detected — fix the runner before spending tokens:" >&2
  grep -iE "unknown (option|argument)|unrecognized" <<<"$probe_out" | head -3 >&2
  exit 3
fi

run_id="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
run_dir=".claude/state/runs/$run_id"
mkdir -p "$run_dir"
timeout_s="${PHASE_TIMEOUT:-1800}"

# shasum is the macOS spelling, sha256sum the GNU one — support both hosts.
sha() { { shasum -a 256 "$1" 2>/dev/null || sha256sum "$1" 2>/dev/null; } | awk '{print $1}'; }
runner_sha0="$(sha "$runner_path")"
config_sha0="$(sha "$config_file")"
# Fail closed: an empty pin would make the tamper re-check vacuously pass.
[ -n "$runner_sha0" ] && [ -n "$config_sha0" ] \
  || { echo "runner: cannot sha-pin runner/config — refusing to run untrusted" >&2; exit 2; }

total_cost=0
echo "=== milestone '$milestone' · model $model · ≤$max_iterations iterations · \$$iter_budget/iter · run $run_id ==="

n=0
while [ "$n" -lt "$max_iterations" ]; do
  n=$((n + 1))
  echo "--- iteration $n"

  prompt="You are resuming a milestone in a fresh session with no prior context.

First, read .context/project-context.md and .context/RESUME.md to recover state.

Milestone: $milestone
Goal: $goal

Do exactly ONE coherent chunk of work toward this goal, and nothing beyond it.
For a non-trivial chunk, IF your allowed tools include skill loading and
subagent spawning, load the orchestration skill and delegate legwork to tiered
subagents — the search agent to locate, Sonnet workers from precise specs for
mechanical edits; judgment and verification stay in this session. Otherwise do
the work directly with the tools you have — never attempt a tool outside your
allowlist (a denial fails this run). Do NOT run or replicate the shell gate
commands: the runner executes them deterministically after you stop.
Self-verify by Reading the artifacts you produced, nothing more. Keep your
own context lean: distilled results only, no raw file dumps.

When the chunk is done:
1. Update .context/project-context.md (goal, files touched, decisions, exact next step).
2. Append any new ADRs under docs/decisions/.
3. Write the single next action to .context/RESUME.md.

If the milestone's acceptance criteria are FULLY met, write .context/MILESTONE_DONE
containing exactly: $milestone
If you discover the goal or decomposition is wrong or impossible, do NOT
improvise: write .context/REPLAN.md explaining why, and stop.
Then stop. Do not begin another chunk."

  iter_log="$run_dir/iter-$n.json"
  # Fresh session; output to a file (not command substitution) so the pure-bash
  # watchdog below can babysit it — stock macOS has no timeout/gtimeout.
  CLAUDE_AUTOCOMPACT_PCT_OVERRIDE="${AUTOCOMPACT_PCT:-70}" \
    claude -p "$prompt" \
      --model "$model" \
      "${perm_args[@]}" \
      --output-format json \
      --max-budget-usd "$iter_budget" \
      </dev/null > "$iter_log" 2> "$iter_log.stderr" &
  pid=$!
  ( sleep "$timeout_s" && kill "$pid" 2>/dev/null ) &
  wd=$!
  wait "$pid"; rc=$?
  kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null

  out="$(cat "$iter_log" 2>/dev/null || true)"
  # Guarded parse — cost on BOTH paths (report-only; the CLI's --max-budget-usd is the cap).
  cost="$(jq -r '(.total_cost_usd // .cost_usd // 0)' <<<"$out" 2>/dev/null || echo 0)"
  total_cost="$(awk -v a="$total_cost" -v b="${cost:-0}" 'BEGIN{printf "%.4f", a+b}')"
  echo "    cost \$$cost · total \$$total_cost"

  if [ "$rc" -ne 0 ]; then
    echo "runner: claude exited $rc on iteration $n (timeout, budget cap, or CLI/API error) — see $iter_log" >&2
    exit 3
  fi
  is_error="$(jq -r '(.is_error // false)' <<<"$out" 2>/dev/null || echo false)"
  [ "$is_error" = "true" ] && { echo "runner: model reported is_error on iteration $n — see $iter_log" >&2; exit 3; }
  denials="$(jq -r '(.permission_denials // []) | length' <<<"$out" 2>/dev/null || echo 0)"
  if [ "$denials" -gt 0 ] 2>/dev/null; then
    if [ "$permission_profile" = "strict" ]; then
      echo "runner: $denials permission denial(s) on iteration $n — allowlist gap; work may be silently undone. See $iter_log" >&2
      exit 3
    fi
    # auto/bypass (ADR 0006): classifier blocks and sandbox fallbacks are
    # by-design feedback — log them; the CLI's abort thresholds and the
    # deterministic gates arbitrate.
    echo "    warning: $denials permission denial(s) on iteration $n (profile=$permission_profile) — see $iter_log" >&2
  fi

  # Trust boundary: the session must not modify its own verifier or contract.
  if [ "$(sha "$runner_path")" != "$runner_sha0" ] || [ "$(sha "$config_file")" != "$config_sha0" ]; then
    echo "runner: the runner or config was modified during iteration $n — aborting (trust boundary)" >&2
    exit 1
  fi

  if [ -f .context/REPLAN.md ]; then
    echo "runner: iteration $n requested a replan — .context/REPLAN.md:" >&2
    sed -n '1,10p' .context/REPLAN.md >&2
    exit 6
  fi

  gate_log="$run_dir/iter-$n.gate.log"
  if ! ( eval "$iteration_gate" ) > "$gate_log" 2>&1; then
    echo "runner: iteration_gate FAILED on iteration $n — stopping (no retry; triage manually)." >&2
    echo "        gate: $iteration_gate" >&2
    echo "        log:  $gate_log (last 5 lines follow)" >&2
    tail -n 5 "$gate_log" >&2
    exit 1
  fi

  if [ -f .context/MILESTONE_DONE ]; then
    done_name="$(head -n1 .context/MILESTONE_DONE | tr -d '[:space:]')"
    if [ "$done_name" = "$milestone" ]; then
      if ( eval "$done_gate" ) > "$run_dir/done-gate.log" 2>&1; then
        CLAUDE_PROJECT_DIR="$repo" bash "$checkpoint_sh" >/dev/null 2>&1 || true
        echo "=== milestone '$milestone' DONE in $n iteration(s) · spent \$$total_cost ==="
        exit 0
      fi
      echo "runner: session claimed done but done_gate FAILS — false completion, stopping." >&2
      echo "        log: $run_dir/done-gate.log (last 5 lines follow)" >&2
      tail -n 5 "$run_dir/done-gate.log" >&2
      exit 1
    fi
    echo "runner: .context/MILESTONE_DONE names '$done_name' (≠ '$milestone') — ignoring, continuing" >&2
  fi

  # Primary checkpoint for headless iterations (the hook has no Stop trigger);
  # idempotent.
  CLAUDE_PROJECT_DIR="$repo" bash "$checkpoint_sh" >/dev/null 2>&1 || true
done

echo "runner: $max_iterations iteration(s) exhausted without completion — checkpoint holds the state; raise max_iterations or triage" >&2
exit 7
