#!/usr/bin/env bash
# Offline test for subagent-trail.sh in a mktemp sandbox: the GLOBAL per-project
# memory dir is redirected via HOME + CLAUDE_PROJECT_DIR, so the real ~/.claude
# is never touched. Pins: no-op without a memory dir, TSV breadcrumb with
# transcript path + assistant-text snippet, placeholder when the payload has no
# transcript, 500-line bound, and always-exit-0 (the script must never abort a
# session).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$here/.." && pwd)"
hook="$REPO/scaffold/hooks/subagent-trail.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
export CLAUDE_PROJECT_DIR="$tmp/proj"
mkdir -p "$CLAUDE_PROJECT_DIR" "$HOME"
slug="$(printf '%s' "$CLAUDE_PROJECT_DIR" | sed 's@/@-@g')"
memdir="$HOME/.claude/projects/$slug/memory"
log="$memdir/.subagent-trail.log"

fail=0
invoke() { local rc=0; printf '%s' "$1" | bash "$hook" || rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL: hook exited $rc (must always be 0)"; fail=1; }; }

# 1. No memory dir yet → clean no-op, nothing created.
invoke '{}'
[ ! -e "$log" ] || { echo "FAIL: log created without a memory dir"; fail=1; }

# 2. Memory dir + transcript payload → TSV line with path and snippet.
mkdir -p "$memdir"
t="$tmp/transcript.jsonl"
printf '{"message":{"role":"assistant","content":[{"type":"text","text":"did the thing"}]}}\n' > "$t"
invoke "$(printf '{"transcript_path":%s}' "$(printf '%s' "$t" | jq -Rs .)")"
grep -qF "$t" "$log"            || { echo "FAIL: transcript path missing from breadcrumb"; fail=1; }
grep -q  "did the thing" "$log" || { echo "FAIL: snippet missing from breadcrumb"; fail=1; }

# 3. Payload without a transcript → placeholder breadcrumb, still logged.
invoke '{}'
grep -q "transcript_path absent" "$log" || { echo "FAIL: placeholder breadcrumb missing"; fail=1; }

# 4. The trail is bounded to 500 lines.
for _ in $(seq 1 600); do printf 'x\ty\tz\n' >> "$log"; done
invoke '{}'
n="$(wc -l < "$log" | tr -d ' ')"
[ "$n" -le 500 ] || { echo "FAIL: log unbounded ($n lines)"; fail=1; }

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; fi
exit "$fail"
