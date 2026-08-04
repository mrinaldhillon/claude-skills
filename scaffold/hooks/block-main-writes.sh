#!/usr/bin/env bash
# PreToolUse guard (Bash): refuse `git commit` / `merge` / `push` when the repo
# the command actually TARGETS is on `main`. Trunk-based discipline (git-workflow
# skill; ADR 0001): every change lands via a branch → PR. On this template branch
# protection is BY DISCIPLINE (ADR 0002) — no server-side gate — so this local
# backstop is the primary automated enforcement; a downstream project with real
# GitHub protection gets it as defense-in-depth that fails fast, before a rejected
# push round-trips. Deny is expressed as PreToolUse permissionDecision JSON on
# stdout, exit 0. Ported from a downstream project's hardened version + tests.
set -euo pipefail

# jq is required to reach the deny path — without this guard a jq-less host
# would die on the jq call below and the git command would PROCEED (fail open).
# Fail CLOSED instead: exit 2 blocks the call and surfaces the reason.
command -v jq >/dev/null 2>&1 || { echo "block-main-writes: jq not found — failing closed; install jq" >&2; exit 2; }

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -n "$cmd" ] || exit 0

# The directory the command runs in, absent an explicit `cd`/`-C`. Payload
# `.cwd` first: probe-verified 2026-08-03 that a Bash PreToolUse payload carries
# it, and that in a plain session it equals both CLAUDE_PROJECT_DIR and $PWD. It
# is the better anchor because it names the directory the command is about to
# run in, which for a native-worktree (`claude --worktree`) or started-in-a-
# subdir session need not be the project root. CLAUDE_PROJECT_DIR stays as the
# fallback for hosts that omit `.cwd`.
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
sess="$(printf '%s' "$input" | jq -r '.cwd // empty')"
if [ -z "$sess" ] || [ ! -d "$sess" ]; then sess="$proj"; fi

# Resolve a LITERAL path token ($1) against a base directory ($2) to an existing
# directory; print nothing if it cannot be resolved without guessing. Nothing
# here is ever eval'd or expanded: a token carrying shell metacharacters is
# unresolvable BY DESIGN, and the caller then falls back to the session dir —
# the fail-closed direction.
resolve_dir() {
  local p="$1" base="$2"
  case "$p" in
    \"*\") p="${p#\"}"; p="${p%\"}" ;;
    \'*\') p="${p#\'}"; p="${p%\'}" ;;
  esac
  case "$p" in
    ''|-|--) return 0 ;;
    *'$'*|*'`'*|*'*'*|*'?'*|*'['*|*'~'*|*'"'*|*"'"*) return 0 ;;
  esac
  case "$p" in
    /*) ;;
    *)  p="$base/$p" ;;
  esac
  [ -d "$p" ] || return 0
  printf '%s' "$p"
}

# Empty for a non-repo or a detached HEAD — neither is `main`, so neither denies.
branch_of() { git -C "$1" branch --show-current 2>/dev/null || true; }

# Only branch-advancing git ops. `git` (bare or path-prefixed /usr/bin/git)
# must sit at command position — line start, or after a shell separator ;&|( ,
# an opening quote or backtick (catches sh -c "git push" and `git push`).
# `echo git commit` stays unmatched, though `echo "git push"` IS matched — an
# accepted false positive; the deny message explains the /hooks override.
# Before `git`, a repeated prefix group swallows env assignments (GIT_DIR=x),
# wrapper words (env/command/nohup/time/xargs/sudo/timeout/nice/ionice/setsid/
# stdbuf/busybox) each with one optional argument (timeout 5 git push), shell
# keywords (then/do/else/elif — if true; then git push), and stray flags.
# After `git`, the skip group swallows pre-subcommand flags, a flag's separate
# argument (git -C <path> commit), and key=value args (-c a.b=c). The
# subcommand must be commit/merge/push, terminated by space, EOL, ;&|),
# a closing quote, or a backtick.
# `merge --abort|--quit` is stripped BEFORE matching (state cleanup, not
# branch-advancing) so plain cleanup passes but `merge --abort && git push`
# still trips on the push; --continue stays blocked (it concludes the merge).
#
# LIMITATIONS (accepted — this is a fast local backstop, not a sandbox):
# - A target is honoured only when it is a literal path. `git -C "$WT" push`,
#   a glob, or `~` is unresolvable, so the check falls back to the session dir
#   — the same false positive this guard used to have everywhere. Pass the
#   literal path, or override via /hooks.
# - `cd` attribution is per separator-chain, not a real shell: `cd wt && git
#   push` is understood, `cd wt; cd ..; git push` is not (the last literal cd
#   in the chain wins). Subshell parens reset it, which is right for
#   `(cd wt && git push); git push` but coarse for nested forms. Separators are
#   not quote-aware either, so a `cd` inside a quoted string can be read as a
#   real one — but only when the token survives resolve_dir, which rejects the
#   quote that put it there. Control flow is likewise not evaluated: in
#   `false && cd wt; git push` the shell never cds yet the guard credits `wt`,
#   so a conditional cd can under-deny. Both are contrived shapes; a real shell
#   parser is out of scope for a per-Bash-call hook.
# - Known residual escapes: shell expansion (git${IFS}push), redirects before
#   the word (2>&1 git push), backslash-newline token splits, and wrappers not
#   in the list. Server-side branch protection (where configured) remains the
#   authoritative gate for anything that reaches the remote.
stripped="$(printf '%s' "$cmd" | sed -E 's/merge[[:space:]]+--(abort|quit)([[:space:]]|$)/ /g')"
re='(^|[;&|(]|["'\''`])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|(env|command|nohup|time|xargs|sudo|timeout|nice|ionice|setsid|stdbuf|busybox|then|do|else|elif)([[:space:]]+[^[:space:]]+)?[[:space:]]+|-[^[:space:]]+[[:space:]]+)*([^[:space:]]*/)?git([[:space:]]+(-[^[:space:]]+([[:space:]]+[^[:space:]]+)?|[^[:space:]-][^[:space:]]*=[^[:space:]]*))*[[:space:]]+(commit|merge|push)([[:space:];&|)"'\''`]|$)'
printf '%s' "$stripped" | grep -Eq "$re" || exit 0

# Split into segments so a `-C`/`cd` target is only ever attributed to the git
# invocation that actually tripped the regex. Matching the whole command and
# then hunting globally for a `-C` is unsound in the other direction: in
# `git -C /elsewhere status && git commit`, the `-C` belongs to a subcommand
# this guard does not police, and crediting it to the bare `git commit` would
# wave through a commit on the session's own main checkout. `;&|` break a
# chain; `()` additionally reset the inherited `cd`, since a subshell's cd does
# not escape it. Segment start then plays the role of the regex's `^` anchor.
segments="$(printf '%s\n' "$stripped" | awk '{ gsub(/[()]/, "\n@SUBSHELL@\n"); gsub(/[;&|]/, "\n"); print }')"

cd_target=""
heredoc=0
deny_dir=""
deny_branch=""
while IFS= read -r seg; do
  if [ "$seg" = "@SUBSHELL@" ]; then cd_target=""; continue; fi

  # A segment that is exactly `cd <path>` sets the directory for the segments
  # that follow it in this chain — but only until a heredoc opens. A heredoc
  # BODY is data, not commands, and its lines are segments like any other: a
  # body line reading `cd <some-repo-on-a-branch>` would otherwise be credited
  # to a later real `git push` and wave it through on main. Everything before
  # the `<<` is still trusted, which keeps the shape that actually occurs —
  # `cd wt && git commit -F - <<EOF` — working. (The mirror case is safe on its
  # own: a body line that looks like `git -C x push` can only ADD a segment to
  # check, and the loop denies if ANY segment targets main.)
  if [ "$heredoc" = 0 ] && printf '%s' "$seg" | grep -Eq '^[[:space:]]*cd[[:space:]]+[^[:space:]]+[[:space:]]*$'; then
    cd_target="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]*cd[[:space:]]+//; s/[[:space:]]*$//')"
    continue
  fi
  case "$seg" in *'<<'*) heredoc=1 ;; esac

  printf '%s' "$seg" | grep -Eq "$re" || continue

  # Only `-C` BEFORE the subcommand is git's own (git rejects the unspaced
  # -C<path> form, so the spaced one is the only shape to handle). Truncating
  # at the subcommand keeps a commit message that happens to contain " -C /x"
  # from being read as a target. Two or more are cumulative in git and not
  # worth emulating — leave them unresolved and fall back.
  pre="$(printf '%s' "$seg" | sed -E 's/[[:space:]](commit|merge|push)([[:space:];&|)"'\''`]|$).*//')"
  hits="$(printf '%s\n' "$pre" | { grep -oE '(^|[[:space:]])-C[[:space:]]+[^[:space:]]+' || true; })"
  n="$(printf '%s' "$hits" | grep -c . || true)"

  # The chain's `cd` is the base this invocation runs in, so a relative `-C`
  # resolves against it (`cd wt && git -C sub push`), not against the session.
  base="$sess"
  if [ -n "$cd_target" ]; then
    cdd="$(resolve_dir "$cd_target" "$sess")"
    if [ -n "$cdd" ]; then base="$cdd"; fi
  fi

  dir=""
  if [ "$n" = "1" ]; then
    tok="$(printf '%s' "$hits" | sed -E 's/.*-C[[:space:]]+//')"
    dir="$(resolve_dir "$tok" "$base")"
  elif [ "$n" = "0" ]; then
    dir="$base"
  fi
  # No target, or one that could not be resolved literally → the session dir.
  if [ -z "$dir" ]; then dir="$sess"; fi

  b="$(branch_of "$dir")"
  if [ "$b" = "main" ]; then deny_dir="$dir"; deny_branch="$b"; break; fi
done <<EOF
$segments
EOF

[ -n "$deny_branch" ] || exit 0

jq -cn --arg b "$deny_branch" --arg d "$deny_dir" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("Blocked: git commit/merge/push targeting `" + $d + "`, which is on `" + $b + "`. Trunk-based workflow (git-workflow skill; ADR 0001/0002): branch first — git switch -c <fix|chore|docs|milestone>/… — then PR into main. Override via /hooks if this is intentional (e.g. an emergency admin action).")}}'
exit 0
