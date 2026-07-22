#!/usr/bin/env bash
# Context-nudge hook, dual-mode (ADR 0004; plugin-shipped since ADR 0008).
# Reads context usage from the statusline bridge file and nudges Claude to
# checkpoint once usage crosses a threshold. The bridge writer stays a
# project-local file (references/project-setup/statusline.sh) — a plugin
# cannot set the statusLine settings key; without the bridge this hook is a
# cheap no-op.
#
# UserPromptSubmit (legacy): plain stdout on exit 0 is added to Claude's context.
# PostToolUse (mid-turn):    stdout is NOT injected for this event; emit
#   {"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":…}}
#   instead. Guards: a session-identity check on BOTH events (the bridge names
#   the session whose statusline wrote it, so a leftover percentage never
#   nudges a headless -p or foreign session); plus, PostToolUse-only, a
#   cooldown so the notice doesn't repeat on every tool call and a
#   bridge-staleness mtime fallback for pre-session-id bridge files.
#
# A hook cannot run /compact or /clear — this only injects guidance; the
# checkpoint-and-clear happens in-conversation (ADR 0003/0004).
set -euo pipefail

WATCH_PCT=55     # approaching — finish the current micro-task, then checkpoint
LAND_PCT=65      # land now — checkpoint and clear (below the auto-compact trigger)
COOLDOWN_S=300   # PostToolUse: min seconds between repeat nudges in the same band
STALE_S=120      # PostToolUse: ignore a bridge file older than this

dir="${CLAUDE_PROJECT_DIR:-.}"

# Surface log: one line per unique host surface — (bundle id, execpath) pair —
# that has ever run this hook, so "do plugin hooks fire in <host X>" (an IDE
# panel, a headless runner) becomes observable without a dedicated test
# sitting. Sits BEFORE the jq guard on purpose: an embedded host may lack a
# Homebrew PATH, so a jq-gated logger would go silent on exactly the surface
# under test. Writes to .claude/state/ (gitignored per the setup guide); must
# never fail or slow the hook.
sl_line="{\"bundle\":\"${__CFBundleIdentifier:-}\",\"execpath\":\"${CLAUDE_CODE_EXECPATH:-}\"}"
sl_file="$dir/.claude/state/hook-surface-log.jsonl"
if ! grep -qsF "$sl_line" "$sl_file" 2>/dev/null; then
  { mkdir -p "$dir/.claude/state" &&
    printf '{"first_seen":"%s","surface":%s}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sl_line" >>"$sl_file"; } 2>/dev/null || true
fi

command -v jq >/dev/null 2>&1 || exit 0
state_file="$dir/.claude/state/context-usage.json"
[ -f "$state_file" ] || exit 0

# Hook payload arrives on stdin; the -t guard keeps a manual TTY run from hanging.
input=""
[ -t 0 ] || input="$(cat || true)"
event="$(jq -r '.hook_event_name // ""' <<<"$input" 2>/dev/null || echo "")"

# Cross-session guard: the bridge records which session's statusline wrote it.
# If both sides carry a session id and they differ, this hook is running in a
# session the bridge does not describe (headless -p, another window, in-IDE) —
# the percentage is someone else's; stay silent on every path. A missing id on
# either side degrades to the per-path behavior below, where the PostToolUse
# staleness guard still covers pre-session-id bridge files.
sid="$(jq -r '.session_id // ""' <<<"$input" 2>/dev/null || echo "")"
bridge_sid="$(jq -r '.session_id // ""' "$state_file" 2>/dev/null || echo "")"
if [ -n "$sid" ] && [ -n "$bridge_sid" ] && [ "$sid" != "$bridge_sid" ]; then
  exit 0
fi

pct="$(jq -r '.used_percentage // 0' "$state_file" 2>/dev/null || echo 0)"
# Round, don't truncate: 64.999 must cross a 65 threshold at the same instant
# the true usage does. Integer part, then round half-up on the first fractional
# digit — pure shell, after the digit guard so garbage never reaches arithmetic.
pct_int="${pct%.*}"
case "$pct_int" in ''|*[!0-9]*) exit 0 ;; esac
frac="${pct#"$pct_int"}"
case "$frac" in .[5-9]*) pct_int=$((pct_int + 1)) ;; esac

band=0
[ "$pct_int" -ge "$WATCH_PCT" ] && band=1
[ "$pct_int" -ge "$LAND_PCT" ] && band=2

watch_msg="[CONTEXT NOTICE — ${pct_int}% used] Approaching the checkpoint threshold. Finish the current micro-task, then checkpoint before starting anything new."
land_msg="[CONTEXT NOTICE — ${pct_int}% used]
Reach a safe stopping point now. Before doing anything else:
1. Update .context/project-context.md — goal, files touched, decisions, and the exact next step.
2. Append any new ADRs under docs/decisions/.
3. Write the single next action to .context/RESUME.md.
4. Commit those durable files on your branch (never on main) — /clear fires no PreCompact, so no hook commits them for you.
Then ask the user to run /clear and resume from those files. Do NOT start new work in this session."

if [ "$event" != "PostToolUse" ]; then
  # Legacy UserPromptSubmit path — behavior unchanged.
  if [ "$band" -eq 2 ]; then printf '%s\n' "$land_msg"
  elif [ "$band" -eq 1 ]; then printf '%s\n' "$watch_msg"
  fi
  exit 0
fi

# --- PostToolUse mid-turn path ---
[ "$band" -eq 0 ] && exit 0

# Staleness: the bridge only updates while the interactive statusline renders.
# GNU stat FIRST: on GNU coreutils `stat -f` means --file-system — it exits 1
# but still dumps a multi-line report to STDOUT, so a BSD-first fallback chain
# concatenates garbage into the capture and the arithmetic below crashes under
# set -u ("File: unbound variable"). GNU `-c` / BSD `-f` each fail cleanly on
# the other flavor. Belt-and-suspenders: hard-validate the result is numeric.
now="$(date +%s)"
mt="$(stat -c %Y "$state_file" 2>/dev/null || stat -f %m "$state_file" 2>/dev/null || echo 0)"
case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
[ $((now - mt)) -gt "$STALE_S" ] && exit 0

# Cooldown: re-inject only on band escalation or after COOLDOWN_S in-band.
last_file="$dir/.claude/state/.nudge-last"
prev_epoch=0 prev_band=0
if [ -f "$last_file" ]; then
  read -r prev_epoch prev_band < "$last_file" 2>/dev/null || true
  case "$prev_epoch" in ''|*[!0-9]*) prev_epoch=0 ;; esac
  case "$prev_band"  in ''|*[!0-9]*) prev_band=0  ;; esac
fi
if [ "$band" -le "$prev_band" ] && [ $((now - prev_epoch)) -lt "$COOLDOWN_S" ]; then
  exit 0
fi
printf '%s %s\n' "$now" "$band" > "$last_file"

msg="$watch_msg"; [ "$band" -eq 2 ] && msg="$land_msg"
jq -n --arg ctx "$msg" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}'
exit 0
