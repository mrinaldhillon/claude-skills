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
# The staleness guard is deliberately NOT applied to UserPromptSubmit: the
# bridge refreshes only while an interactive statusline renders, so after an
# idle stretch a legitimate bridge is arbitrarily old and any short bound would
# swallow the nudge at exactly the moment it matters. The cost is that a
# pre-session-id bridge (no `session_id` to compare) can nudge from stale or
# foreign data on that path — closed by refreshing statusline.sh, which the
# setup guide's migration checklist requires. Don't "fix" this with STALE_S.
#
# A hook cannot run /compact or /clear — this only injects guidance; the
# checkpoint-and-clear happens in-conversation (ADR 0003/0004).
#
# Configurable: CLAUDE_NUDGE_WATCH_PCT / CLAUDE_NUDGE_LAND_PCT (defaults 40/45),
# validated as a pair and clamped below the auto-compact trigger — see below.
set -euo pipefail

# Thresholds, percent of the context window used (ADR 0003 §2, defaults lowered
# to 40/45 in 0.8.0 — landing early costs a cheap /clear, landing late costs the
# turn). A project whose window, model, or milestone rhythm differs overrides
# them in .claude/settings.json > env. The timers below are NOT configurable —
# they tune injection noise, not the checkpoint policy.
WATCH_PCT="${CLAUDE_NUDGE_WATCH_PCT:-40}"  # approaching — finish the current micro-task, then checkpoint
LAND_PCT="${CLAUDE_NUDGE_LAND_PCT:-45}"    # land now — checkpoint and clear (below the auto-compact trigger)
COOLDOWN_S=300   # PostToolUse: min seconds between repeat nudges in the same band
STALE_S=120      # PostToolUse: ignore a bridge file older than this

# Validate the pair as a PAIR: one bad value discards BOTH overrides rather than
# half-applying, because a surviving half can invert the ordering it was checked
# against (a land below watch makes the watch band unreachable and fires the land
# message first). Integers 1..99. `10#` strips leading zeros — `$((070 - 1))` is
# 55, not 69, and that arithmetic runs on the clamp path below.
nudge_warn=""
valid_pct() {
  case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac
  [ "$((10#$1))" -ge 1 ] && [ "$((10#$1))" -le 99 ]
}
if ! valid_pct "$WATCH_PCT" || ! valid_pct "$LAND_PCT" ||
   [ "$((10#$WATCH_PCT))" -gt "$((10#$LAND_PCT))" ]; then
  nudge_warn="context-nudge: ignoring CLAUDE_NUDGE_WATCH_PCT='$WATCH_PCT' / CLAUDE_NUDGE_LAND_PCT='$LAND_PCT' (want integers 1-99, watch <= land) — using 40/45"
  WATCH_PCT=40
  LAND_PCT=45
fi
WATCH_PCT=$((10#$WATCH_PCT))
LAND_PCT=$((10#$LAND_PCT))
# Equal thresholds are legal and deliberate: it collapses the two bands into a
# single land-now notice for a project that does not want the early warning.

# Auto-compact is the backstop, not the boundary (ADR 0004 §5) — the land nudge
# must fire BELOW the compaction trigger or a summary lands first and the whole
# checkpoint-then-clear loop is defeated. When the session's trigger is visible
# in the environment (settings.json > env, or the milestone runner's export at
# scaffold/scripts/milestone-runner.sh), hold that invariant by clamping rather
# than rejecting: a project that lowers auto-compact under the land threshold is
# otherwise betrayed by a land it never set — the DEFAULT — against a trigger it
# did. Only this env var is visible here; the CLI's built-in default and
# `autoCompactEnabled` are not.
ac="${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-}"
if valid_pct "$ac" && [ "$LAND_PCT" -ge "$((10#$ac))" ]; then
  ac=$((10#$ac))
  LAND_PCT=$((ac - 1))
  [ "$LAND_PCT" -lt 1 ] && LAND_PCT=1
  [ "$WATCH_PCT" -gt "$LAND_PCT" ] && WATCH_PCT="$LAND_PCT"
  nudge_warn="${nudge_warn:+$nudge_warn
}context-nudge: land threshold clamped to ${LAND_PCT}% — auto-compact fires at ${ac}% (CLAUDE_AUTOCOMPACT_PCT_OVERRIDE), and a nudge at or above it never precedes the summary"
fi
# stderr, never stdout: stdout IS the injection channel on UserPromptSubmit, so a
# warning there would land in Claude's context as if it were the notice.
#
# Emitted HERE, before the no-bridge early exit below, on purpose: a rejected
# override must be diagnosable in a repo that has not wired the statusline yet —
# that is exactly when someone is asking why their thresholds do nothing. The
# cost is one stderr line per event (visible only under `claude --debug`) while
# the misconfiguration stands; a correct config is silent.
[ -n "$nudge_warn" ] && printf '%s\n' "$nudge_warn" >&2

# Hook payload arrives on stdin; the -t guard keeps a manual TTY run from
# hanging. Read BEFORE resolving `dir` — the payload carries its fallback.
input=""
[ -t 0 ] || input="$(cat || true)"

# Project dir: CLAUDE_PROJECT_DIR, then the payload's `.cwd`, then `.`. The
# payload step is what makes the parity the bridge WRITER claims real:
# references/project-setup/statusline.sh resolves the same way (from
# `.workspace.project_dir // .cwd` — a statusline payload has a `.workspace`,
# a hook payload does not), and if writer and reader disagree they use
# different .claude/state dirs and the nudge silently reads a bridge that
# isn't there. The harness sets CLAUDE_PROJECT_DIR for hooks in both plain and
# native-worktree (`claude --worktree`) sessions, so this only engages on a
# host that omits it — the same embedded-surface case the log below exists to
# detect. It needs jq, so a jq-less host without CLAUDE_PROJECT_DIR still
# degrades to `.`; keeping that degradation is why the log below stays
# reachable ahead of the jq guard.
dir="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$dir" ] && command -v jq >/dev/null 2>&1; then
  dir="$(jq -r '.cwd // ""' <<<"$input" 2>/dev/null || echo "")"
fi
if [ -z "$dir" ] || [ ! -d "$dir" ]; then dir="."; fi

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
# Round, don't truncate: 44.999 must cross a 45 threshold at the same instant
# the true usage does. Integer part, then round half-up on the first fractional
# digit — pure shell, after the digit guard so garbage never reaches arithmetic.
pct_int="${pct%.*}"
case "$pct_int" in ''|*[!0-9]*) exit 0 ;; esac
frac="${pct#"$pct_int"}"
case "$frac" in .[5-9]*) pct_int=$((pct_int + 1)) ;; esac

band=0
[ "$pct_int" -ge "$WATCH_PCT" ] && band=1
[ "$pct_int" -ge "$LAND_PCT" ] && band=2

# Path resolution MUST match checkpoint.sh's — same env vars, same defaults.
# That hook is what actually commits these files, so a nudge naming a different
# set instructs the session to write what nothing preserves.
adr_dir="${CLAUDE_ADR_DIR:-docs/decisions}"
pc="${CLAUDE_PROJECT_CONTEXT:-.context/project-context.md}"
resume=".context/RESUME.md"

# The project-context step is emitted only when that file is a DISTINCT, present
# document. A project may point CLAUDE_PROJECT_CONTEXT at the resume pointer
# itself (collapsing the two into one file), or carry no project-context file at
# all. In either case an "Update <path>" line names a file the project does not
# keep — and a session told to update a missing file helpfully creates one,
# resurrecting a document the project deliberately removed.
n=0
steps=""
if [ "$pc" != "$resume" ] && [ -f "$dir/$pc" ]; then
  n=$((n + 1))
  steps="${steps}${n}. Update ${pc} — goal, files touched, decisions, and the exact next step.
"
fi
n=$((n + 1))
steps="${steps}${n}. Append any new ADRs under ${adr_dir}/.
"
n=$((n + 1))
steps="${steps}${n}. Write the single next action to ${resume}.
"
n=$((n + 1))
steps="${steps}${n}. Commit those durable files on your branch (never on main) — /clear fires no PreCompact, so no hook commits them for you."

watch_msg="[CONTEXT NOTICE — ${pct_int}% used] Approaching the checkpoint threshold. Finish the current micro-task, then checkpoint before starting anything new."
land_msg="[CONTEXT NOTICE — ${pct_int}% used]
Reach a safe stopping point now. Before doing anything else:
${steps}
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
