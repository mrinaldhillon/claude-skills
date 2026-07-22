#!/usr/bin/env bash
# Offline test for statusline.sh: renders "<model> | ctx <int>%", writes the
# bridge file atomically, and degrades safely on empty/malformed/partial input.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$here/.." && pwd)"
script="$REPO/scaffold/references/project-setup/statusline.sh"

proj="$(mktemp -d)"
trap 'rm -rf "$proj"' EXIT
mkdir -p "$proj/.claude/state"
cd "$proj"   # so a "." cwd fallback writes inside the sandbox, not the real repo
unset CLAUDE_PROJECT_DIR   # payload-fallback cases below must exercise the payload path

fail=0
eq()  { [ "$1" = "$2" ] || { echo "FAIL: expected [$2], got [$1]"; fail=1; }; }
has() { printf '%s' "$1" | grep -q "$2" || { echo "FAIL: wanted '$2' in [$1]"; fail=1; }; }

bridge="$proj/.claude/state/context-usage.json"

# Happy path: render + atomic bridge write (session id rides along).
out="$(printf '{"cwd":".","workspace":{"project_dir":"%s"},"model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":42.7},"session_id":"abc-123"}' "$proj" | bash "$script")"
eq "$out" "Opus 4.8 | ctx 42%"
eq "$(cat "$bridge")" '{"used_percentage": 42.7, "session_id": "abc-123"}'

# Missing fields → "? | ctx 0%" (cwd "." fallback keeps the write in the sandbox).
has "$(echo '{}' | bash "$script")" "? | ctx 0%"

# Empty stdin → static degrade, exit 0.
eq "$(printf '' | bash "$script"; echo " rc=$?")" "ctx ?% rc=0"

# Non-JSON stdin → static degrade, exit 0.
eq "$(echo 'not json' | bash "$script"; echo " rc=$?")" "ctx ?% rc=0"

# Non-numeric percentage is sanitized to 0 so the bridge JSON stays valid;
# a missing session id degrades to the empty string.
out="$(printf '{"workspace":{"project_dir":"%s"},"model":{"display_name":"X"},"context_window":{"used_percentage":"weird"}}' "$proj" | bash "$script")"
eq "$out" "X | ctx 0%"
eq "$(cat "$bridge")" '{"used_percentage": 0, "session_id": ""}'

# Session id is clamped to the UUID alphabet so a weird payload cannot corrupt
# the bridge JSON string literal.
out="$(printf '{"workspace":{"project_dir":"%s"},"model":{"display_name":"X"},"context_window":{"used_percentage":5},"session_id":"we{ir}d_id!"}' "$proj" | bash "$script")"
eq "$(cat "$bridge")" '{"used_percentage": 5, "session_id": "weirdid"}'

# CLAUDE_PROJECT_DIR wins over the payload (writer/reader path contract): the
# bridge must land where the nudge hook will look, even if the payload differs.
proj2="$(mktemp -d)"
mkdir -p "$proj2/.claude/state"
out="$(printf '{"workspace":{"project_dir":"%s"},"model":{"display_name":"Y"},"context_window":{"used_percentage":51}}' "$proj" \
      | CLAUDE_PROJECT_DIR="$proj2" bash "$script")"
eq "$out" "Y | ctx 51%"
eq "$(cat "$proj2/.claude/state/context-usage.json")" '{"used_percentage": 51, "session_id": ""}'
rm -rf "$proj2"

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; fi
exit "$fail"
