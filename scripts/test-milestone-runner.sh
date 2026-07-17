#!/usr/bin/env bash
# Offline test for scripts/milestone-runner.sh (ADR 0004) against a fake
# `claude` stub — no tokens spent. Covers: flag pinning (incl. the
# AUTOCOMPACT env), never --bare/--resume, permission-denial and is_error
# failure paths, the REPLAN and MILESTONE_DONE sentinels with their gates,
# iteration exhaustion, config validation, branch guard, lock, DRY_RUN
# inertness, the trust boundary, and idempotent rerun after done.
#
# The stub logs ONE flattened line per invocation (prompt newlines → spaces),
# so `wc -l` counts invocations and flags stay greppable — the two harness
# bugs that shipped green in the parked plan (docs/meta/milestone-driver-plan.md,
# appendix bugs 1-2). NOTE: the runner's zero-cost flag probe is invocation #1
# in every live case; expected counts below include it.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$here/.." && pwd)"
RUNNER="$REPO/scaffold/scripts/milestone-runner.sh"

fail=0
check()    { if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 — expected '$2' got '$3'"; fail=1; fi; }
contains() { if printf '%s' "$1" | grep -qF -- "$2"; then echo "PASS: $3"; else echo "FAIL: $3 (needle '$2' absent)"; fail=1; fi; }
lacks()    { if printf '%s' "$1" | grep -qF -- "$2"; then echo "FAIL: $3 (needle '$2' present)"; fail=1; else echo "PASS: $3"; fi; }

# Harness self-test: the helpers must detect an absent needle as absent —
# proves the assertions are non-vacuous (parked-plan bug 2 was exactly this).
if printf '%s' "haystack" | grep -qF -- "absent-needle"; then
  echo "FAIL: harness self-test (grep matched an absent needle)"; fail=1
else
  echo "PASS: harness self-test (absent needle detected as absent)"
fi

# --- fake claude on PATH -------------------------------------------------------
stubdir="$(mktemp -d)"
cat > "$stubdir/claude" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
line="$(printf '%s' "$*" | tr '\n' ' ')"
printf '%s | AC=%s\n' "$line" "${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-unset}" >> "${STUB_ARGS_LOG:?}"
[ -n "${STUB_STDERR:-}" ] && printf '%s\n' "$STUB_STDERR" >&2
if [ -n "${STUB_SIDE_EFFECT:-}" ]; then eval "$STUB_SIDE_EFFECT" || true; fi
cat <<EOF
{"type":"result","result":"stub","session_id":"s","total_cost_usd":${STUB_COST:-0.01},"is_error":${STUB_IS_ERROR:-false},"permission_denials":${STUB_DENIALS:-[]}}
EOF
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$stubdir/claude"
export PATH="$stubdir:$PATH"
contains "$(command -v claude)" "$stubdir" "stub shadows real claude"

# --- per-case throwaway repo ---------------------------------------------------
CASES="$(mktemp -d)"
trap 'rm -rf "$stubdir" "$CASES"' EXIT

mkrepo() { # mkrepo <name> [branch] → prints repo path, cds NOT done here
  local d="$CASES/$1" b="${2:-feat-test}"
  mkdir -p "$d"; ( cd "$d" || exit 1
    git init -q -b "$b"; git config user.email t@t; git config user.name t
    mkdir -p docs .context
    echo ctx > .context/project-context.md; echo ptr > .context/RESUME.md )
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/checkpoint-stub.sh"
  chmod +x "$d/checkpoint-stub.sh"
  printf '%s' "$d"
}

mkconfig() { # mkconfig <dir> [overrides-jq]
  local d="$1" jqexpr="${2:-.}"
  jq -n '{milestone:"example", goal:"make HELLO.md",
          model:"claude-sonnet-5", allowed_tools:"Read,Write,Edit",
          max_budget_usd_per_iteration:0.25, max_iterations:5,
          iteration_gate:"true", done_gate:"test -f HELLO.md"}' \
    | jq "$jqexpr" > "$d/m.json"
}

# Side effect: bump a counter; run extra shell when the counter reaches N.
# (single-quoted on purpose — the stub evals this, not this harness: SC2016)
# shellcheck disable=SC2016
se() { printf 'c=$(cat cnt 2>/dev/null || echo 0); c=$((c+1)); echo $c > cnt; [ "$c" -ge %s ] && { %s; } || true' "$1" "$2"; }

runlog() { export STUB_ARGS_LOG="$1/args.log"; : > "$STUB_ARGS_LOG"; }
nlines() { wc -l < "$STUB_ARGS_LOG" | tr -d ' '; }

# --- 1. happy path: DONE on iteration 1, done_gate passes ----------------------
d="$(mkrepo happy)"; mkconfig "$d"; runlog "$d"
( cd "$d" && STUB_SIDE_EFFECT="$(se 2 'touch HELLO.md; echo example > .context/MILESTONE_DONE')" \
  CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) > "$CASES/happy.out" 2>&1
check "happy path exits 0" "0" "$?"
check "happy path: probe + 1 iteration" "2" "$(nlines)"
log="$(cat "$STUB_ARGS_LOG")"
contains "$log" "--model claude-sonnet-5" "pins the config model"
contains "$log" "--output-format json" "passes json output format"
contains "$log" "--max-budget-usd 0.25" "wires the per-iteration budget cap"
contains "$log" "--permission-mode acceptEdits" "pins acceptEdits"
contains "$log" "--allowedTools" "scopes tools"
contains "$log" "AC=70" "exports CLAUDE_AUTOCOMPACT_PCT_OVERRIDE to the session"
lacks "$log" "--bare" "never passes --bare"
lacks "$log" "--resume" "never resumes a session"
contains "$log" "resuming a milestone" "iterate prompt reaches the session"
contains "$log" "orchestration skill" "prompt binds the tiering doctrine (layer E)"

# --- 2. rerun after done: idempotent, zero new sessions ------------------------
( cd "$d" && CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "rerun after done exits 0" "0" "$?"
check "rerun spawns no sessions" "2" "$(nlines)"

# --- 3. recorded done but done_gate now fails: desync --------------------------
( cd "$d" && rm -f HELLO.md && CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "done-recorded but gate-failing desync exits 1" "1" "$?"

# --- 4. stale DONE for a different milestone ------------------------------------
d="$(mkrepo staledone)"; mkconfig "$d"; runlog "$d"
( cd "$d" && echo other > .context/MILESTONE_DONE && CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "stale DONE for another milestone exits 2" "2" "$?"

# --- 5. is_error surfaces as failure -------------------------------------------
d="$(mkrepo iserr)"; mkconfig "$d"; runlog "$d"
( cd "$d" && STUB_IS_ERROR=true CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "is_error exits 3" "3" "$?"

# --- 6. permission denials fail the iteration -----------------------------------
d="$(mkrepo denial)"; mkconfig "$d"; runlog "$d"
( cd "$d" && STUB_DENIALS='[{"tool_name":"Write"}]' CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) \
  > "$CASES/denial.out" 2>&1
check "permission denial exits 3" "3" "$?"
contains "$(cat "$CASES/denial.out")" "permission denial" "denial is named in the error"

# --- 7. nonzero claude exit ------------------------------------------------------
d="$(mkrepo rc)"; mkconfig "$d"; runlog "$d"
( cd "$d" && STUB_EXIT=1 CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "nonzero claude exit exits 3" "3" "$?"

# --- 8. REPLAN sentinel ----------------------------------------------------------
d="$(mkrepo replan)"; mkconfig "$d"; runlog "$d"
( cd "$d" && STUB_SIDE_EFFECT="$(se 2 'echo why > .context/REPLAN.md')" \
  CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "replan request exits 6" "6" "$?"

# --- 9. stale REPLAN refuses to start -------------------------------------------
( cd "$d" && CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "stale REPLAN refuses to start (6)" "6" "$?"

# --- 10. iteration_gate failure stops the run, no retry -------------------------
d="$(mkrepo gatefail)"; mkconfig "$d" '.iteration_gate = "false"'; runlog "$d"
( cd "$d" && CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "iteration_gate failure exits 1" "1" "$?"
check "no retry after gate failure (probe + 1 only)" "2" "$(nlines)"

# --- 11. false-done: DONE written but done_gate fails ----------------------------
d="$(mkrepo falsedone)"; mkconfig "$d" '.done_gate = "false"'; runlog "$d"
( cd "$d" && STUB_SIDE_EFFECT="$(se 2 'echo example > .context/MILESTONE_DONE')" \
  CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "false completion claim exits 1" "1" "$?"

# --- 12. iterations exhausted -----------------------------------------------------
d="$(mkrepo exhaust)"; mkconfig "$d" '.max_iterations = 2'; runlog "$d"
( cd "$d" && CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "exhausted iterations exit 7" "7" "$?"
check "exhausted after probe + 2 iterations" "3" "$(nlines)"

# --- 13. bad config ---------------------------------------------------------------
d="$(mkrepo badcfg)"; mkconfig "$d" 'del(.done_gate)'; runlog "$d"
( cd "$d" && CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "missing config key exits 2" "2" "$?"
check "bad config spawns nothing" "0" "$(nlines)"

# --- 14. branch guard --------------------------------------------------------------
d="$(mkrepo onmain main)"; mkconfig "$d"; runlog "$d"
( cd "$d" && CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "main branch refused (4)" "4" "$?"

# --- 15. lock held ------------------------------------------------------------------
d="$(mkrepo locked)"; mkconfig "$d"; runlog "$d"
( cd "$d" && mkdir -p .claude/state/milestone.lock && CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "held lock exits 5" "5" "$?"
check "held lock spawns nothing" "0" "$(nlines)"

# --- 16. DRY_RUN is inert ------------------------------------------------------------
d="$(mkrepo dry)"; mkconfig "$d"; runlog "$d"
( cd "$d" && DRY_RUN=1 CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) > "$CASES/dry.out" 2>&1
check "dry run exits 0" "0" "$?"
check "dry run spawns nothing" "0" "$(nlines)"
if [ ! -d "$d/.claude/state/runs" ]; then echo "PASS: dry run writes no run state"
else echo "FAIL: dry run created run state"; fail=1; fi
if [ ! -d "$d/.claude/state/milestone.lock" ]; then echo "PASS: dry run leaves no lock"
else echo "FAIL: dry run left a lock"; fail=1; fi
contains "$(cat "$CASES/dry.out")" "DRY RUN" "dry run announces itself"

# --- 17. trust boundary: session edits the config --------------------------------
d="$(mkrepo trust)"; mkconfig "$d"; runlog "$d"
( cd "$d" && STUB_SIDE_EFFECT="$(se 2 'echo " " >> m.json')" \
  CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) > "$CASES/trust.out" 2>&1
check "config mutation aborts (1)" "1" "$?"
contains "$(cat "$CASES/trust.out")" "trust boundary" "abort names the trust boundary"

# --- 18. flag-drift probe ----------------------------------------------------------
d="$(mkrepo drift)"; mkconfig "$d"; runlog "$d"
( cd "$d" && STUB_STDERR="error: unknown option '--max-budget-usd'" \
  CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "flag drift detected at probe (3)" "3" "$?"
check "drift stops before any iteration" "1" "$(nlines)"

# --- 19. auto profile: classifier mode + sandbox settings, denials tolerated -------
# (ADR 0006: in auto mode classifier blocks are by-design feedback, not fatal;
# the CLI's own abort thresholds + the gates arbitrate.)
d="$(mkrepo autoprof)"; mkconfig "$d" '.permission_profile = "auto"'; runlog "$d"
( cd "$d" && STUB_DENIALS='[{"tool_name":"Bash"}]' \
  STUB_SIDE_EFFECT="$(se 2 'touch HELLO.md; echo example > .context/MILESTONE_DONE')" \
  CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) > "$CASES/autoprof.out" 2>&1
check "auto profile completes despite denials" "0" "$?"
log="$(cat "$STUB_ARGS_LOG")"
contains "$log" "--permission-mode auto" "auto profile pins permission-mode auto"
contains "$log" "--settings" "auto profile passes settings"
contains "$log" "sandbox" "sandbox block reaches the session"
contains "$log" "autoAllowBashIfSandboxed" "sandbox auto-allow enabled"
contains "$(cat "$CASES/autoprof.out")" "denial" "auto profile still logs denials"

# --- 20. bypass profile refused without containment attestation --------------------
d="$(mkrepo bypassref)"; mkconfig "$d" '.permission_profile = "bypass"'; runlog "$d"
( cd "$d" && CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) > "$CASES/bypassref.out" 2>&1
check "bypass without containment refused (2)" "2" "$?"
check "bypass refusal spawns nothing" "0" "$(nlines)"
contains "$(cat "$CASES/bypassref.out")" "container" "refusal explains the containment gate"

# --- 21. bypass profile with attestation -------------------------------------------
d="$(mkrepo bypassok)"; mkconfig "$d" '.permission_profile = "bypass"'; runlog "$d"
( cd "$d" && MILESTONE_CONTAINED=1 \
  STUB_SIDE_EFFECT="$(se 2 'touch HELLO.md; echo example > .context/MILESTONE_DONE')" \
  CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "bypass with attestation succeeds" "0" "$?"
contains "$(cat "$STUB_ARGS_LOG")" "--dangerously-skip-permissions" "bypass passes the bypass flag"
lacks "$(cat "$STUB_ARGS_LOG")" "--permission-mode acceptEdits" "bypass does not also pin acceptEdits"

# --- 22. invalid profile -------------------------------------------------------------
d="$(mkrepo badprof)"; mkconfig "$d" '.permission_profile = "yolo"'; runlog "$d"
( cd "$d" && CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "unknown profile rejected (2)" "2" "$?"

# --- 23. wrong-repo refusal: config outside the resolved repo ------------------------
# The repo is derived from the caller's cwd; a config living elsewhere must be
# refused, or acceptEdits sessions would run against whatever tree cwd is in.
d="$(mkrepo wrongrepo)"; runlog "$d"
mkdir -p "$CASES/elsewhere"; mkconfig "$CASES/elsewhere"
( cd "$d" && CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" "$CASES/elsewhere/m.json" ) > "$CASES/wrongrepo.out" 2>&1
check "config outside the repo refused (2)" "2" "$?"
check "wrong-repo refusal spawns nothing" "0" "$(nlines)"
contains "$(cat "$CASES/wrongrepo.out")" "outside this repo" "refusal names the containment rule"

# --- 24. subdir-relative config path resolves against the CALLER's cwd ----------------
# (pre-fix: the check ran after cd to the repo root, so ../m.json from a subdir
# failed with "no such config" — ordinary invocation broke off-root.)
d="$(mkrepo subdir)"; mkconfig "$d"; runlog "$d"
mkdir -p "$d/sub"
( cd "$d/sub" && DRY_RUN=1 CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" ../m.json ) > "$CASES/subdir.out" 2>&1
check "subdir-relative config accepted (dry, 0)" "0" "$?"
contains "$(cat "$CASES/subdir.out")" "DRY RUN" "subdir invocation reaches the dry-run summary"

# --- 25. detached HEAD refused, same as main ------------------------------------------
d="$(mkrepo detached)"; mkconfig "$d"; runlog "$d"
( cd "$d" && git commit -q --allow-empty -m init && git checkout -q --detach \
  && CHECKPOINT_SH="$d/checkpoint-stub.sh" bash "$RUNNER" m.json ) >/dev/null 2>&1
check "detached HEAD refused (4)" "4" "$?"

[ "$fail" -eq 0 ] && echo "ALL PASS"
exit "$fail"
