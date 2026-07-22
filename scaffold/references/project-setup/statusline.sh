#!/usr/bin/env bash
# Renders the status line AND bridges context usage to a state file the
# context-nudge hook (shipped by the scaffold plugin) can read. No hook payload
# carries main-session context-window data, so the status line JSON is the only
# live source of context_window.used_percentage — re-probed 2026-07-22 against
# the full hooks reference and the 2.1.217 binary (see ADR 0008 §Verification).
# The bridge also records session_id — which session's percentage this is — so
# the nudge hook can stay silent in sessions the bridge does not describe.
set -euo pipefail

input="$(cat)"

# Degrade to a static line (no bridge write) if jq is missing, stdin is
# empty, or the payload is not parseable JSON.
if ! command -v jq >/dev/null 2>&1 \
  || [ -z "$input" ] \
  || ! printf '%s' "$input" | jq -e . >/dev/null 2>&1; then
  printf 'ctx ?%%'
  exit 0
fi

# Resolve the project dir the same way the nudge hook does — CLAUDE_PROJECT_DIR
# first, payload fallback — so the bridge WRITER and its hook READER can never
# disagree about which .claude/state they share.
proj="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$input" | jq -r '.workspace.project_dir // .cwd // "."')}"
pct="$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0')"
model="$(printf '%s' "$input" | jq -r '.model.display_name // "?"')"
sid="$(printf '%s' "$input" | jq -r '.session_id // ""')"

# Sanitize: the JSON literal below must not be corrupted by a non-numeric pct,
# and the session id lands inside a JSON string literal — strip anything
# beyond the UUID alphabet so a weird payload cannot corrupt the bridge.
case "$pct" in ''|*[!0-9.]*) pct=0 ;; esac
sid="${sid//[^A-Za-z0-9-]/}"

state_dir="$proj/.claude/state"
mkdir -p "$state_dir"
# Atomic write — the nudge hook must never read a partial file.
tmp="$(mktemp "$state_dir/.context-usage.XXXXXX")"
trap 'rm -f "$tmp"' EXIT   # clean the temp if a write fails before the rename
printf '{"used_percentage": %s, "session_id": "%s"}\n' "$pct" "$sid" > "$tmp"
mv -f "$tmp" "$state_dir/context-usage.json"

printf '%s | ctx %s%%' "$model" "${pct%.*}"
