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

# Deny on any `cd` target that was seen inside a heredoc body whose delimiter
# never closed (see the loop): the shell may genuinely be sitting in one of
# them. Sets deny_dir/deny_branch on a hit. `hd_cd_dirs` is empty — so this is
# a no-op — whenever every body closed normally, which is the usual case.
check_hd_dirs() {
  local hd
  [ -n "$hd_cd_dirs" ] || return 0
  while IFS= read -r hd; do
    [ -n "$hd" ] || continue
    if [ "$(branch_of "$hd")" = "main" ]; then deny_dir="$hd"; deny_branch="main"; return 0; fi
  done <<HD
$hd_cd_dirs
HD
}

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
hd_delim=""
hd_cd_dirs=""
matched=0
deny_dir=""
deny_branch=""
while IFS= read -r seg; do
  if [ "$seg" = "@SUBSHELL@" ]; then cd_target=""; continue; fi

  trimmed="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

  # A heredoc BODY is data, not commands, but its lines are segments like any
  # other, so a body line reading `cd <repo-on-a-branch>` must not be credited
  # to a later real `git push`. Track the DELIMITER rather than merely "a `<<`
  # was seen": a sticky flag also blinds the guard to the real `cd` that follows
  # the body, which the shell very much executes — `<<EOF … EOF; cd <main>; git
  # push` was a confirmed bypass for exactly that reason (probe, 2026-08-04).
  # Body lines are skipped entirely, so one spelling `git -C x push` is inert.
  if [ -n "$hd_delim" ]; then
    if [ "$trimmed" = "$hd_delim" ]; then hd_delim=""; continue; fi
    # Should the delimiter never arrive (a `;` inside the body split it, unusual
    # quoting), the flag would stay set and a real post-body `cd` would be lost
    # again. Keep every body `cd` as an extra candidate and judge it too — the
    # shell may actually be there. Fail-closed, and inert once a body closes
    # normally.
    if printf '%s' "$trimmed" | grep -Eq '^cd[[:space:]]+[^[:space:]]+$'; then
      d="$(resolve_dir "${trimmed#cd }" "$sess")"
      if [ -n "$d" ]; then hd_cd_dirs="$hd_cd_dirs$d
"; fi
    fi
    continue
  fi

  # `<<` opens a body from the NEXT segment on; the rest of THIS one is still a
  # real command, so `cd wt && git commit -F - <<EOF` keeps working.
  case "$seg" in
    *'<<'*) hd_delim="$(printf '%s' "$seg" | sed -nE 's/.*<<-?[[:space:]]*["'\'']?([A-Za-z_][A-Za-z0-9_]*).*/\1/p')" ;;
  esac

  # A segment that is exactly `cd <path>` sets the directory for the segments
  # that follow it in this chain.
  if printf '%s' "$trimmed" | grep -Eq '^cd[[:space:]]+[^[:space:]]+$'; then
    cd_target="${trimmed#cd }"
    continue
  fi

  printf '%s' "$seg" | grep -Eq "$re" || continue
  matched=1

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

  check_hd_dirs
  if [ -n "$deny_branch" ]; then break; fi
done <<EOF
$segments
EOF

# Segmentation may only ever REFINE which repo gets judged — never drop the
# command. The whole-command gate above already proved a branch-advancing op is
# in here, so if no segment matched, the split lost it and the session dir is
# what to judge (exactly the pre-segmentation behavior). The split is
# quote-unaware, and that is not hypothetical: a `; | & ( )` inside a
# PRE-subcommand argument cuts `git` from its subcommand so neither half
# matches — `git -c core.foo="a;b" commit -m x` was a full detection bypass
# until this fallback existed (probe-confirmed 2026-08-03; a separator after
# the subcommand, e.g. in a -m message, was always safe because `git commit`
# is already matched intact in the first segment). This backstop also covers
# the `@SUBSHELL@` marker having no nonce: attacker text equal to it can only
# clear `cd_target`, which falls back here or to `$sess`.
if [ "$matched" = 0 ] && [ -z "$deny_branch" ]; then
  b="$(branch_of "$sess")"
  if [ "$b" = "main" ]; then deny_dir="$sess"; deny_branch="$b"; fi
  # An unclosed heredoc body swallows the rest of the command as data, the real
  # git op included, so nothing matched and the loop's own call never ran.
  if [ -z "$deny_branch" ]; then check_hd_dirs; fi
fi

[ -n "$deny_branch" ] || exit 0

jq -cn --arg b "$deny_branch" --arg d "$deny_dir" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("Blocked: git commit/merge/push targeting `" + $d + "`, which is on `" + $b + "`. Trunk-based workflow (git-workflow skill; ADR 0001/0002): branch first — git switch -c <fix|chore|docs|milestone>/… — then PR into main. Override via /hooks if this is intentional (e.g. an emergency admin action).")}}'
exit 0
