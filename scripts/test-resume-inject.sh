#!/usr/bin/env bash
# Offline test for the resume-inject hook (SessionStart re-injection).
# Present RESUME.md -> header + verbatim contents on stdout; absent -> silent
# exit 0; empty stdin behaves the same (the matcher, not the script, scopes
# firing). Runs in a mktemp sandbox (CLAUDE_PROJECT_DIR points there) — never
# touches the real repo's .context. The run helper turns a nonzero hook exit
# into a loud HOOK_FAILED marker so a crash FAILS assertions under set -e
# instead of killing the suite.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$here/.." && pwd)"
hook="$REPO/scaffold/hooks/resume-inject.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.context"
export CLAUDE_PROJECT_DIR="$tmp"
resume="$tmp/.context/RESUME.md"

fail=0
assert_contains() { printf '%s' "$1" | grep -q "$2" || { echo "FAIL: expected '$2' in output"; fail=1; }; }
assert_empty()    { [ -z "$1" ] || { echo "FAIL: expected empty output, got '$1'"; fail=1; }; }

run() { printf '{"hook_event_name":"SessionStart","source":"compact"}' | bash "$hook" || printf 'HOOK_FAILED(rc=%s)' "$?"; }

# --- absent RESUME.md: silent no-op, no crash ---
rm -f "$resume"
assert_empty "$(run)"

# --- present RESUME.md: header + verbatim contents ---
cat > "$resume" <<'EOF'
# RESUME
Next: land the PR, then reshape the held one.
Gate: validate.sh green. Never use the admin override on merge.
EOF
out="$(run)"
assert_contains "$out" "Resuming from checkpoint"
assert_contains "$out" "RESUME.md"
assert_contains "$out" "reshape the held one"
assert_contains "$out" "admin override on merge"

# --- contents with shell/JSON metacharacters pass through verbatim (cat) ---
# A literal $ is the point of this case: single quotes keep it unexpanded so we
# prove the hook re-emits it byte-for-byte rather than evaluating it.
# shellcheck disable=SC2016
printf '%s\n' 'metacharok "q" $V backtick backslash 100% <t> & |' > "$resume"
assert_contains "$(run)" "metacharok"

# --- empty stdin (no payload) behaves identically to a SessionStart payload ---
out="$(bash "$hook" </dev/null || printf 'HOOK_FAILED(rc=%s)' "$?")"
assert_contains "$out" "Resuming from checkpoint"

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; fi
exit "$fail"
