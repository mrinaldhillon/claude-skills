#!/usr/bin/env bash
# Offline test for the context-nudge hook, both modes.
# Legacy (UserPromptSubmit / no payload): silence below threshold, watch
# message at >=55%, land message at >=65%, threshold rounding, graceful on
# garbage or a missing bridge file. PostToolUse (mid-turn): hookSpecificOutput
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
state="$tmp/.claude/state/context-usage.json"
last="$tmp/.claude/state/.nudge-last"

fail=0
assert_contains()     { printf '%s' "$1" | grep -q "$2" || { echo "FAIL: expected '$2' in '$1'"; fail=1; }; }
assert_not_contains() { printf '%s' "$1" | grep -q "$2" && { echo "FAIL: did not expect '$2'"; fail=1; } || true; }
assert_empty()        { [ -z "$1" ] || { echo "FAIL: expected empty output, got '$1'"; fail=1; }; }

legacy()   { bash "$hook" </dev/null || printf 'HOOK_FAILED(rc=%s)' "$?"; }
prompt()   { printf '{"hook_event_name":"UserPromptSubmit"}' | bash "$hook" || printf 'HOOK_FAILED(rc=%s)' "$?"; }
posttool() { printf '{"hook_event_name":"PostToolUse","tool_name":"Read"}' | bash "$hook" || printf 'HOOK_FAILED(rc=%s)' "$?"; }
prompt_sid()   { printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s"}' "$1" | bash "$hook" || printf 'HOOK_FAILED(rc=%s)' "$?"; }
posttool_sid() { printf '{"hook_event_name":"PostToolUse","tool_name":"Read","session_id":"%s"}' "$1" | bash "$hook" || printf 'HOOK_FAILED(rc=%s)' "$?"; }

# --- legacy path (UserPromptSubmit stdout; empty stdin must behave the same) ---

echo '{"used_percentage": 30}' > "$state"
assert_empty "$(legacy)"

echo '{"used_percentage": 58}' > "$state"
out="$(legacy)"
assert_contains "$out" "checkpoint threshold"
assert_not_contains "$out" "hookSpecificOutput"   # legacy stays plain stdout

echo '{"used_percentage": 67}' > "$state"
assert_contains "$(legacy)" "RESUME.md"

# Rounding, not truncation: 64.6 → 65 crosses LAND_PCT; 64.4 stays in watch.
echo '{"used_percentage": 64.6}' > "$state"
assert_contains "$(legacy)" "RESUME.md"
echo '{"used_percentage": 64.4}' > "$state"
out="$(legacy)"
assert_contains "$out" "checkpoint threshold"
assert_not_contains "$out" "RESUME.md"

# explicit UserPromptSubmit payload → still the plain-stdout path
echo '{"used_percentage": 58}' > "$state"
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
echo '{"used_percentage": 58}' > "$state"
out="$(posttool)"
assert_contains "$out" "hookSpecificOutput"
assert_contains "$out" "additionalContext"
assert_contains "$out" "checkpoint threshold"
[ -f "$last" ] || { echo "FAIL: .nudge-last not recorded"; fail=1; }

assert_empty "$(posttool)"                        # same band, fresh: cooldown

echo '{"used_percentage": 67}' > "$state"
out="$(posttool)"                                 # band escalation beats cooldown
assert_contains "$out" "hookSpecificOutput"
assert_contains "$out" "RESUME.md"

assert_empty "$(posttool)"                        # band 2, fresh: cooldown again

printf '0 2\n' > "$last"                          # ancient epoch: cooldown elapsed
out="$(posttool)"
assert_contains "$out" "hookSpecificOutput"

rm -f "$last"                                     # stale bridge (headless guard):
echo '{"used_percentage": 67}' > "$state"         # mtime far in the past → silent
touch -mt 202601010000 "$state"
assert_empty "$(posttool)"

# --- cross-session guard: bridge session id vs payload session id -------------

rm -f "$last"
echo '{"used_percentage": 58, "session_id": "sess-A"}' > "$state"
assert_contains "$(prompt_sid sess-A)" "checkpoint threshold"   # own bridge: nudges
assert_empty "$(prompt_sid sess-B)"                             # foreign bridge: silent
out="$(posttool_sid sess-A)"                                    # own bridge, fresh: nudges
assert_contains "$out" "hookSpecificOutput"
rm -f "$last"
assert_empty "$(posttool_sid sess-B)"                           # foreign, even fresh + no cooldown: silent

# id on one side only → guard degrades to the legacy behavior (compat with
# pre-session-id bridge files and manual payload-less runs)
echo '{"used_percentage": 58}' > "$state"
assert_contains "$(prompt_sid sess-A)" "checkpoint threshold"
echo '{"used_percentage": 58, "session_id": "sess-A"}' > "$state"
assert_contains "$(prompt)" "checkpoint threshold"

# --- surface logger: written on first invocation, deduplicated thereafter -----
# Every run above shares one (bundle, execpath) pair, so the log must hold
# exactly one line no matter how many hook invocations this suite made.
slog="$tmp/.claude/state/hook-surface-log.jsonl"
[ -f "$slog" ] || { echo "FAIL: surface log not written"; fail=1; }
[ -f "$slog" ] && [ "$(wc -l < "$slog")" -eq 1 ] \
  || { echo "FAIL: surface log not deduplicated"; fail=1; }

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; fi
exit "$fail"
