#!/usr/bin/env bash
# PreToolUse guard (Bash): refuse `git commit` / `merge` / `push` while the
# checkout is on `main`. Trunk-based discipline (git-workflow skill; ADR 0001):
# every change lands via a branch → PR. On this template branch protection is
# BY DISCIPLINE (ADR 0002) — no server-side gate — so this local backstop is
# the primary automated enforcement; a downstream project with real GitHub
# protection gets it as defense-in-depth that fails fast, before a rejected
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
# - Checks THIS checkout's branch, not the repo a `git -C <elsewhere>` command
#   targets — while this project sits on main it also denies commits aimed at
#   other repos. Park the checkout on a branch during cross-repo work, or
#   override via /hooks.
# - Known residual escapes: shell expansion (git${IFS}push), redirects before
#   the word (2>&1 git push), backslash-newline token splits, and wrappers not
#   in the list. Server-side branch protection (where configured) remains the
#   authoritative gate for anything that reaches the remote.
stripped="$(printf '%s' "$cmd" | sed -E 's/merge[[:space:]]+--(abort|quit)([[:space:]]|$)/ /g')"
re='(^|[;&|(]|["'\''`])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|(env|command|nohup|time|xargs|sudo|timeout|nice|ionice|setsid|stdbuf|busybox|then|do|else|elif)([[:space:]]+[^[:space:]]+)?[[:space:]]+|-[^[:space:]]+[[:space:]]+)*([^[:space:]]*/)?git([[:space:]]+(-[^[:space:]]+([[:space:]]+[^[:space:]]+)?|[^[:space:]-][^[:space:]]*=[^[:space:]]*))*[[:space:]]+(commit|merge|push)([[:space:];&|)"'\''`]|$)'
printf '%s' "$stripped" | grep -Eq "$re" || exit 0

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
branch="$(git -C "$proj" branch --show-current 2>/dev/null || true)"
[ "$branch" = "main" ] || exit 0

jq -cn --arg b "$branch" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("Blocked: git commit/merge/push while on `" + $b + "`. Trunk-based workflow (git-workflow skill; ADR 0001/0002): branch first — git switch -c <fix|chore|docs|milestone>/… — then PR into main. Override via /hooks if this is intentional (e.g. an emergency admin action).")}}'
exit 0
