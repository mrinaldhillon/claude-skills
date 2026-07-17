#!/usr/bin/env bash
# Regression tests for scaffold/hooks/block-main-writes.sh — the trunk-based PreToolUse
# guard. Exercises the command-detection regex AND the branch gate end-to-end:
# branch-advancing git ops (commit/merge/push) on `main` must be DENIED; the same
# ops on any other branch, non-git commands, quoted echoes, and `merge --abort`
# must be ALLOWED. The hook only inspects the command string + current branch; it
# never runs git, so these cases are side-effect free.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook="$here/../scaffold/hooks/block-main-writes.sh"

command -v jq >/dev/null 2>&1 || { printf 'test: jq is required\n' >&2; exit 2; }
[ -x "$hook" ] || { printf 'test: hook not executable: %s\n' "$hook" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
git -C "$tmp" config user.email test@example.com
git -C "$tmp" config user.name  test
git -C "$tmp" commit -q --allow-empty -m init

fails=0
# run <deny|allow> <branch> <command>
run() {
  local expect="$1" branch="$2" cmd="$3" payload out got
  git -C "$tmp" checkout -q -B "$branch"
  payload="$(jq -cn --arg c "$cmd" '{tool_input:{command:$c}}')"
  out="$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$tmp" "$hook" 2>/dev/null || true)"
  got=allow
  if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then got=deny; fi
  if [ "$got" = "$expect" ]; then
    printf 'ok    [%-5s] %s\n' "$branch" "$cmd"
  else
    printf 'FAIL  expected %s got %s [%s] %s\n' "$expect" "$got" "$branch" "$cmd" >&2
    fails=$((fails + 1))
  fi
}

# Denied: branch-advancing git ops on main, including wrappers and merge-then-push.
run deny  main "git push"
run deny  main "git commit -m x"
run deny  main "git merge feature"
run deny  main "timeout 5 git push"
run deny  main "git -C . commit -m x"
run deny  main "merge --abort && git push"
# Allowed on main: non-advancing git, non-git, unquoted echo, state cleanup.
run allow main "git status"
run allow main "git merge --abort"
run allow main "echo git commit"
run allow main "ls -la"
# Allowed off main: the same advancing ops are fine on a feature branch.
run allow work "git push"
run allow work "git commit -m x"

printf '\n'
if [ "$fails" -eq 0 ]; then
  printf 'all block-main-writes tests passed\n'
else
  printf '%d test(s) FAILED\n' "$fails" >&2
  exit 1
fi
