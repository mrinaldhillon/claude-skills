#!/usr/bin/env bash
# Offline test for the context-nudge hook, both modes.
# Legacy (UserPromptSubmit / no payload): silence below threshold, watch
# message at >=40%, land message at >=45% (the defaults; both configurable, and
# exercised as such further down), threshold rounding, graceful on garbage or a
# missing bridge file. PostToolUse (mid-turn): hookSpecificOutput
# JSON instead of plain stdout, cooldown between repeat nudges, band-escalation
# override, and a bridge-staleness guard (headless -p must never see a leftover
# interactive percentage). Cross-session guard: a bridge stamped with another
# session's id must silence both paths. Surface log: written once, deduplicated.
#
# Runs in a mktemp sandbox (CLAUDE_PROJECT_DIR points there) — never touches
# the real repo's .claude/state. All hook invocations go through run helpers
# that convert a nonzero hook exit into a loud HOOK_FAILED marker: a crashing
# hook must FAIL assertions, not kill this suite through set -e. (The Linux
# stat regression — GNU `stat -f` stdout leak → "File: unbound variable" —
# died exactly that way and left the suite reporting nothing.)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$here/.." && pwd)"
hook="$REPO/scaffold/hooks/context-nudge.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/state"
export CLAUDE_PROJECT_DIR="$tmp"
# Hermetic: the hook resolves the checkpoint paths from the first two and its
# thresholds from the rest, so a host session that exports any of them (a project
# wiring them in settings.json > env, or a milestone-runner session, which
# exports CLAUDE_AUTOCOMPACT_PCT_OVERRIDE around every spawned `claude -p`) would
# silently retarget the land message or move the bands, and this suite would
# assert against the HOST's config, not the sandbox's. CI has them unset; a
# developer machine may not. Control them here so both agree.
unset CLAUDE_ADR_DIR CLAUDE_PROJECT_CONTEXT
unset CLAUDE_NUDGE_WATCH_PCT CLAUDE_NUDGE_LAND_PCT CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
state="$tmp/.claude/state/context-usage.json"
last="$tmp/.claude/state/.nudge-last"

fail=0
assert_contains()     { printf '%s' "$1" | grep -q "$2" || { echo "FAIL: expected '$2' in '$1'"; fail=1; }; }
assert_not_contains() { printf '%s' "$1" | grep -q "$2" && { echo "FAIL: did not expect '$2'"; fail=1; } || true; }
assert_empty()        { [ -z "$1" ] || { echo "FAIL: expected empty output, got '$1'"; fail=1; }; }

legacy()   { bash "$hook" </dev/null || printf 'HOOK_FAILED(rc=%s)' "$?"; }
# Env-varying runs go through `env` rather than a `VAR=x legacy` prefix: on a
# shell FUNCTION that prefix persists after the call under POSIX mode (see the
# CLAUDE_ADR_DIR case near the end), which would leak a threshold into every
# later assertion. `nudge` drops stderr (the config warnings have their own
# assertions); `nudge_err` captures stderr and discards stdout.
nudge()     { env "$@" bash "$hook" </dev/null 2>/dev/null || printf 'HOOK_FAILED(rc=%s)' "$?"; }
nudge_err() { env "$@" bash "$hook" </dev/null 2>&1 >/dev/null || true; }
prompt()   { printf '{"hook_event_name":"UserPromptSubmit"}' | bash "$hook" || printf 'HOOK_FAILED(rc=%s)' "$?"; }
posttool() { printf '{"hook_event_name":"PostToolUse","tool_name":"Read"}' | bash "$hook" || printf 'HOOK_FAILED(rc=%s)' "$?"; }
prompt_sid()   { printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s"}' "$1" | bash "$hook" || printf 'HOOK_FAILED(rc=%s)' "$?"; }
posttool_sid() { printf '{"hook_event_name":"PostToolUse","tool_name":"Read","session_id":"%s"}' "$1" | bash "$hook" || printf 'HOOK_FAILED(rc=%s)' "$?"; }

# --- legacy path (UserPromptSubmit stdout; empty stdin must behave the same) ---

echo '{"used_percentage": 30}' > "$state"
assert_empty "$(legacy)"

echo '{"used_percentage": 42}' > "$state"
out="$(legacy)"
assert_contains "$out" "checkpoint threshold"
assert_not_contains "$out" "hookSpecificOutput"   # legacy stays plain stdout

echo '{"used_percentage": 47}' > "$state"
assert_contains "$(legacy)" "RESUME.md"

# Rounding, not truncation: 44.6 → 45 crosses LAND_PCT; 44.4 stays in watch.
echo '{"used_percentage": 44.6}' > "$state"
assert_contains "$(legacy)" "RESUME.md"
echo '{"used_percentage": 44.4}' > "$state"
out="$(legacy)"
assert_contains "$out" "checkpoint threshold"
assert_not_contains "$out" "RESUME.md"

# explicit UserPromptSubmit payload → still the plain-stdout path
echo '{"used_percentage": 42}' > "$state"
out="$(prompt)"
assert_contains "$out" "checkpoint threshold"
assert_not_contains "$out" "hookSpecificOutput"

echo '{"used_percentage": "garbage"}' > "$state"
assert_empty "$(legacy)"

rm -f "$state"
assert_empty "$(legacy)"

# --- PostToolUse path: JSON injection, cooldown, escalation, staleness ---------

rm -f "$last"
echo '{"used_percentage": 30}' > "$state"
assert_empty "$(posttool)"                        # below threshold: silent

# Fresh bridge + first nudge: THE Linux regression pin — at the buggy HEAD this
# crashed ("File: unbound variable") instead of emitting the JSON below.
echo '{"used_percentage": 42}' > "$state"
out="$(posttool)"
assert_contains "$out" "hookSpecificOutput"
assert_contains "$out" "additionalContext"
assert_contains "$out" "checkpoint threshold"
[ -f "$last" ] || { echo "FAIL: .nudge-last not recorded"; fail=1; }

assert_empty "$(posttool)"                        # same band, fresh: cooldown

echo '{"used_percentage": 47}' > "$state"
out="$(posttool)"                                 # band escalation beats cooldown
assert_contains "$out" "hookSpecificOutput"
assert_contains "$out" "RESUME.md"

assert_empty "$(posttool)"                        # band 2, fresh: cooldown again

printf '0 2\n' > "$last"                          # ancient epoch: cooldown elapsed
out="$(posttool)"
assert_contains "$out" "hookSpecificOutput"

rm -f "$last"                                     # stale bridge (headless guard):
echo '{"used_percentage": 47}' > "$state"         # mtime far in the past → silent
touch -mt 202601010000 "$state"
assert_empty "$(posttool)"

# --- cross-session guard: bridge session id vs payload session id -------------

rm -f "$last"
echo '{"used_percentage": 42, "session_id": "sess-A"}' > "$state"
assert_contains "$(prompt_sid sess-A)" "checkpoint threshold"   # own bridge: nudges
assert_empty "$(prompt_sid sess-B)"                             # foreign bridge: silent
out="$(posttool_sid sess-A)"                                    # own bridge, fresh: nudges
assert_contains "$out" "hookSpecificOutput"
rm -f "$last"
assert_empty "$(posttool_sid sess-B)"                           # foreign, even fresh + no cooldown: silent

# id on one side only → guard degrades to the legacy behavior (compat with
# pre-session-id bridge files and manual payload-less runs)
echo '{"used_percentage": 42}' > "$state"
assert_contains "$(prompt_sid sess-A)" "checkpoint threshold"
echo '{"used_percentage": 42, "session_id": "sess-A"}' > "$state"
assert_contains "$(prompt)" "checkpoint threshold"

# --- land message resolves the checkpoint paths, and renumbers --------------
# The land message must name exactly the files checkpoint.sh commits: same env
# vars, same defaults. Naming a file the project does not keep tells the session
# to write what nothing preserves — and a session told to update a missing file
# helpfully creates one, resurrecting a document the project deliberately
# removed. The RESUME line is unconditional; the project-context line is not.
echo '{"used_percentage": 47}' > "$state"
mkdir -p "$tmp/.context"

# Default layout, project-context.md present: all four steps, default ADR dir.
printf 'ctx\n' > "$tmp/.context/project-context.md"
out="$(legacy)"
assert_contains "$out" "1\. Update \.context/project-context\.md"
assert_contains "$out" "2\. Append any new ADRs under docs/decisions/"
assert_contains "$out" "3\. Write the single next action to \.context/RESUME\.md"
assert_contains "$out" "4\. Commit those durable files"

# Same layout, project-context.md ABSENT: the step is dropped and the remaining
# ones renumber — a stale "4." with three steps is the bug this pins.
rm -f "$tmp/.context/project-context.md"
out="$(legacy)"
assert_not_contains "$out" "project-context"
assert_contains "$out" "1\. Append any new ADRs"
assert_contains "$out" "3\. Commit those durable files"
assert_not_contains "$out" "4\. Commit"

# CLAUDE_ADR_DIR / CLAUDE_PROJECT_CONTEXT honored. Pointing the latter at the
# resume pointer collapses the two into one file, so the update step must not
# appear even though the target exists. Invoked directly rather than through
# legacy(): a `VAR=x func` prefix on a shell FUNCTION persists after the call
# under POSIX mode, so the env would leak into every later assertion.
printf 'r\n' > "$tmp/.context/RESUME.md"
out="$(CLAUDE_ADR_DIR=handled-docs/05-decisions \
       CLAUDE_PROJECT_CONTEXT=.context/RESUME.md \
       bash "$hook" </dev/null || printf 'HOOK_FAILED(rc=%s)' "$?")"
assert_contains "$out" "1\. Append any new ADRs under handled-docs/05-decisions/"
assert_not_contains "$out" "Update \.context/RESUME\.md"
rm -f "$tmp/.context/RESUME.md"
rmdir "$tmp/.context"

# --- configurable thresholds (CLAUDE_NUDGE_WATCH_PCT / CLAUDE_NUDGE_LAND_PCT) --
# The defaults (40/45) are ADR 0003 §2 as amended; a project with a different
# window or milestone rhythm moves the bands — these cases raise them well above
# the defaults so a regression to hardcoded constants cannot pass by coincidence.
# Validation is pair-wise on purpose: a half-applied
# override can invert watch <= land, which makes the watch band unreachable and
# fires the land message where the watch message belongs.

echo '{"used_percentage": 42}' > "$state"
assert_empty "$(nudge CLAUDE_NUDGE_WATCH_PCT=70 CLAUDE_NUDGE_LAND_PCT=80)"
echo '{"used_percentage": 72}' > "$state"
assert_contains "$(nudge CLAUDE_NUDGE_WATCH_PCT=70 CLAUDE_NUDGE_LAND_PCT=80)" "checkpoint threshold"
echo '{"used_percentage": 81}' > "$state"
assert_contains "$(nudge CLAUDE_NUDGE_WATCH_PCT=70 CLAUDE_NUDGE_LAND_PCT=80)" "RESUME.md"

# Rounding follows the configured land, not just the default 45.
echo '{"used_percentage": 79.6}' > "$state"
assert_contains "$(nudge CLAUDE_NUDGE_WATCH_PCT=70 CLAUDE_NUDGE_LAND_PCT=80)" "RESUME.md"
echo '{"used_percentage": 79.4}' > "$state"
out="$(nudge CLAUDE_NUDGE_WATCH_PCT=70 CLAUDE_NUDGE_LAND_PCT=80)"
assert_contains "$out" "checkpoint threshold"
assert_not_contains "$out" "RESUME.md"

# Leading zeros are decimal here: 070 is 70, not octal 56.
echo '{"used_percentage": 72}' > "$state"
assert_contains "$(nudge CLAUDE_NUDGE_WATCH_PCT=070 CLAUDE_NUDGE_LAND_PCT=080)" "checkpoint threshold"

# watch == land is legal and deliberate: one land-now notice, no early warning.
echo '{"used_percentage": 69}' > "$state"
assert_empty "$(nudge CLAUDE_NUDGE_WATCH_PCT=70 CLAUDE_NUDGE_LAND_PCT=70)"
echo '{"used_percentage": 70}' > "$state"
assert_contains "$(nudge CLAUDE_NUDGE_WATCH_PCT=70 CLAUDE_NUDGE_LAND_PCT=70)" "RESUME.md"

# An invalid value discards BOTH overrides (40/45 apply, so 42% is a watch) and
# warns on stderr only — stdout is the injection channel, and a warning there
# would enter Claude's context dressed as the notice.
assert_falls_back() {
  local out
  out="$(nudge "$@")"
  assert_contains "$out" "checkpoint threshold"
  assert_not_contains "$out" "ignoring"
  assert_contains "$(nudge_err "$@")" "ignoring CLAUDE_NUDGE"
}
echo '{"used_percentage": 42}' > "$state"
assert_falls_back CLAUDE_NUDGE_WATCH_PCT=abc CLAUDE_NUDGE_LAND_PCT=80   # not a number
assert_falls_back CLAUDE_NUDGE_WATCH_PCT=0   CLAUDE_NUDGE_LAND_PCT=80   # out of range
assert_falls_back CLAUDE_NUDGE_LAND_PCT=100                             # out of range
assert_falls_back CLAUDE_NUDGE_WATCH_PCT=80  CLAUDE_NUDGE_LAND_PCT=60   # inverted pair

# --- auto-compact clamp: the land nudge must precede the summary (ADR 0004 §5) -
# The milestone runner exports CLAUDE_AUTOCOMPACT_PCT_OVERRIDE around every
# spawned session (scaffold/scripts/milestone-runner.sh), and hooks inherit it,
# so the hook can see the trigger it has to stay under. Clamp rather than reject:
# at a 45% trigger it is the untouched DEFAULT land of 45 that would fire only
# after compaction had already summarized the turn away.
echo '{"used_percentage": 44}' > "$state"
assert_contains "$(nudge CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=45)" "RESUME.md"
assert_contains "$(nudge_err CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=45)" "clamped to 44%"

# The watch band follows the clamp down instead of crossing above the land: a
# 38% trigger pulls land to 37, and the default watch of 40 down with it.
echo '{"used_percentage": 37}' > "$state"
assert_contains "$(nudge CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=38)" "RESUME.md"
echo '{"used_percentage": 36}' > "$state"
assert_empty "$(nudge CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=38)"

# A trigger above the land threshold changes nothing, and says nothing.
echo '{"used_percentage": 42}' > "$state"
assert_contains "$(nudge CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70)" "checkpoint threshold"
assert_empty "$(nudge_err CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70)"

# Octal trap on the clamp arithmetic: "070" must clamp to 69, not to 55 (which
# is what $((070 - 1)) yields if the leading zero is read as octal).
echo '{"used_percentage": 69}' > "$state"
env_070=(CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=070 CLAUDE_NUDGE_WATCH_PCT=80 CLAUDE_NUDGE_LAND_PCT=90)
assert_contains "$(nudge "${env_070[@]}")" "RESUME.md"
assert_contains "$(nudge_err "${env_070[@]}")" "clamped to 69%"

# A garbage trigger is ignored, not fatal.
echo '{"used_percentage": 42}' > "$state"
assert_contains "$(nudge CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=garbage)" "checkpoint threshold"

# --- surface logger: written on first invocation, deduplicated thereafter -----
# Every run above shares one (bundle, execpath) pair, so the log must hold
# exactly one line no matter how many hook invocations this suite made.
slog="$tmp/.claude/state/hook-surface-log.jsonl"
[ -f "$slog" ] || { echo "FAIL: surface log not written"; fail=1; }
[ -f "$slog" ] && [ "$(wc -l < "$slog")" -eq 1 ] \
  || { echo "FAIL: surface log not deduplicated"; fail=1; }

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; fi
exit "$fail"
