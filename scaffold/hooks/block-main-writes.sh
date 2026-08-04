#!/usr/bin/env bash
# PreToolUse guard (Bash): refuse `git commit` / `merge` / `push` when the repo
# the command TARGETS is on `main`. Trunk-based discipline (git-workflow skill;
# ADR 0001): every change lands via a branch → PR. On this template branch
# protection is BY DISCIPLINE (ADR 0002) — no server-side gate — so this local
# backstop is the primary automated enforcement; a downstream project with real
# GitHub protection gets it as defense-in-depth that fails fast, before a
# rejected push round-trips. Deny is PreToolUse permissionDecision JSON on
# stdout, exit 0.
#
# DESIGN — this hook does NOT parse shell, and must never start trying to.
# An earlier version segmented the command and tracked `cd` across the chain to
# work out the working directory. Every attempt to simulate more of the shell
# (heredoc bodies, subshell parens, pushd, quoted separators) created a new hole,
# because a text scanner's mistakes there land in the ALLOW direction. So the
# rule is inverted into two conventions that are cheap to check and whose
# mistakes can only land in the DENY direction:
#
#   1. A command may OPEN with one literal `cd <path>`. That is the shape agents
#      write, and it is unambiguous. Any other thing that moves the shell — a
#      second `cd`, `pushd`, `popd`, a `cd` later in the chain or inside a
#      heredoc body — makes the directory undeterminable.
#   2. `git -C <path>` is honoured only when the command holds exactly one `git`
#      word. Otherwise the `-C` may belong to a subcommand this guard does not
#      police (`git -C /elsewhere status && git commit`), and crediting it would
#      wave a commit through on the session's own checkout.
#
# Undeterminable is a DENY, never an assumption. Assuming "it must be the
# session dir" is only fail-closed when the session IS the repo at risk; with
# the session on a branch and the real target on `main` it is fail-OPEN, which
# is how every past bypass here worked. Over-detection is therefore safe by
# construction: a `cd` seen in a commit message costs one spurious deny with an
# actionable message, not a missed one.
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
# unresolvable BY DESIGN, and unresolvable means DENY at the call site.
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

# --- 1. is a branch-advancing git op in here at all? -------------------------
# `git` (bare or path-prefixed /usr/bin/git) must sit at command position — line
# start, after a shell separator ;&|( , or after an opening quote or backtick
# (catches sh -c "git push" and `git push`). `echo git commit` stays unmatched,
# though `echo "git push"` IS matched — an accepted false positive; the deny
# message explains the /hooks override. Before `git`, a repeated prefix group
# swallows env assignments (GIT_DIR=x), wrapper words each with one optional
# argument (timeout 5 git push), shell keywords (then/do/else/elif), and stray
# flags. After `git`, the skip group swallows pre-subcommand flags, a flag's
# separate argument (git -C <path> commit), and key=value args (-c a.b=c). The
# subcommand must be commit/merge/push, terminated by space, EOL, ;&|), a
# closing quote, or a backtick.
# `merge --abort|--quit` is stripped BEFORE matching (state cleanup, not
# branch-advancing) so plain cleanup passes but `merge --abort && git push`
# still trips on the push; --continue stays blocked (it concludes the merge).
stripped="$(printf '%s' "$cmd" | sed -E 's/merge[[:space:]]+--(abort|quit)([[:space:]]|$)/ /g')"
wrappers='env|command|exec|nohup|time|xargs|sudo|timeout|nice|ionice|setsid|stdbuf|busybox|then|do|else|elif'
re='(^|[;&|(]|["'\''`])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|('"$wrappers"')([[:space:]]+[^[:space:]]+)?[[:space:]]+|-[^[:space:]]+[[:space:]]+)*([^[:space:]]*/)?git([[:space:]]+(-[^[:space:]]+([[:space:]]+[^[:space:]]+)?|[^[:space:]-][^[:space:]]*=[^[:space:]]*))*[[:space:]]+(commit|merge|push)([[:space:];&|)"'\''`]|$)'
printf '%s' "$stripped" | grep -Eq "$re" || exit 0

# --- 2. which directory will it run in? --------------------------------------
base="$sess"
undet=0

# Convention 1: an opening `cd <literal>`, and nothing else that moves the shell.
# `1s` / `1{...}`: sed is line-oriented and the command may be multi-line, so the
# address MUST pin this to the first line. Without it a `cd` on any line at all
# reads as the opening one -- including a line inside a heredoc body, which is
# exactly the forgery this convention exists to refuse.
lead="$(printf '%s\n' "$stripped" | sed -nE '1s/^[[:space:]]*cd[[:space:]]+([^[:space:]]+)([[:space:]]*(&&|;)|[[:space:]]*$).*/\1/p')"
rest="$stripped"
if [ -n "$lead" ]; then
  d="$(resolve_dir "$lead" "$sess")"
  if [ -n "$d" ]; then base="$d"; else undet=1; fi
  rest="$(printf '%s\n' "$stripped" | sed -E '1s/^[[:space:]]*cd[[:space:]]+[^[:space:]]+[[:space:]]*(&&|;)?//')"
fi
# Any further directory move at command position — start of a line, or after a
# `; & |`. Quotes are deliberately NOT command-position here, so an ordinary
# `git commit -m "cd into the dir"` does not trip it.
if printf '%s' "$rest" | grep -Eq '(^|[;&|])[[:space:]]*(cd|pushd|popd)([[:space:]]|$)'; then
  undet=1
fi

# Convention 2: honour `-C` only when there is exactly one `git` word. Counting
# generously — a `git` inside a message inflates the count and merely costs us
# the `-C` shortcut, which then falls back to `base`.
ngit="$(printf '%s\n' "$stripped" | { grep -oE '(^|[[:space:]"'\''`(;&|])([^[:space:]]*/)?git([[:space:]]|$)' || true; } | grep -c . || true)"
dir="$base"
if [ "$ngit" = "1" ]; then
  # Only `-C` BEFORE the subcommand is git's own (git rejects the unspaced
  # -C<path> form, so the spaced one is the only shape to handle). Truncating at
  # the subcommand keeps a commit message containing " -C /x" from being read as
  # a target. Two or more are cumulative in git and not worth emulating.
  pre="$(printf '%s' "$stripped" | sed -E 's/[[:space:]](commit|merge|push)([[:space:];&|)"'\''`]|$).*//')"
  hits="$(printf '%s\n' "$pre" | { grep -oE '(^|[[:space:]])-C[[:space:]]+[^[:space:]]+' || true; })"
  nc="$(printf '%s' "$hits" | grep -c . || true)"
  if [ "$nc" = "1" ]; then
    tok="$(printf '%s' "$hits" | sed -E 's/.*-C[[:space:]]+//')"
    if [ "$undet" = "1" ]; then
      # The base is unknown, so only an ABSOLUTE -C still pins the target — and
      # when it does, it pins it regardless of where the shell ended up.
      dir=""
      case "$tok" in /*) dir="$(resolve_dir "$tok" /)" ;; esac
    else
      dir="$(resolve_dir "$tok" "$base")"
    fi
    if [ -n "$dir" ]; then undet=0; else undet=1; fi
  elif [ "$nc" != "0" ]; then
    undet=1
  fi
fi

# --- 3. decide ---------------------------------------------------------------
tail='Trunk-based workflow (git-workflow skill; ADR 0001/0002): branch first — git switch -c <fix|chore|docs|milestone>/… — then PR into main. Override via /hooks if this is intentional (e.g. an emergency admin action).'
deny() {
  jq -cn --arg r "$1$tail" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

if [ "$undet" = "1" ]; then
  # shellcheck disable=SC2016  # backticks are markdown in the message, not
  # command substitution — the single quotes are what keeps them literal.
  deny 'Blocked: git commit/merge/push whose target directory cannot be determined. This guard reads one leading `cd <literal path>` and a literal `git -C <path>`; it does not simulate the shell, so a later `cd`, a `pushd`/`popd`, or a path needing a variable, glob or `~` expanded leaves it unable to tell which repo the command lands in — and it denies rather than guess. Put the `cd` first, or pass the literal path to `git -C`. '
fi

b="$(branch_of "$dir")"
[ "$b" = "main" ] || exit 0
deny "Blocked: git commit/merge/push targeting \`$dir\`, which is on \`$b\`. "
