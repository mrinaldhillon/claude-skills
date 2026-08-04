#!/usr/bin/env bash
# Regression tests for scaffold/hooks/block-main-writes.sh — the trunk-based PreToolUse
# guard. Exercises the command-detection regex AND the branch gate end-to-end:
# branch-advancing git ops (commit/merge/push) on `main` must be DENIED; the same
# ops on any other branch, non-git commands, quoted echoes, and `merge --abort`
# must be ALLOWED. Plus target resolution: the branch checked is the one of the
# repo the command actually targets (`git -C <path>` / a chain's `cd <path>`),
# not the session's own checkout. The hook only READS branches; it never runs the
# commands under test, so these cases are side-effect free.
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

# A linked worktree of the same repo, parked on a branch. Stands in for the real
# shape this guard used to get wrong: session anchored on a `main` checkout while
# the command targets a correctly-routed worktree elsewhere.
wt="$tmp-wt"
git -C "$tmp" worktree add -q -b wt-branch "$wt"
trap 'git -C "$tmp" worktree remove --force "$wt" >/dev/null 2>&1 || true; rm -rf "$tmp" "$wt"' EXIT

fails=0

# decide <expect> <label> <cwd-or-empty> <command> — the shared assertion.
# CLAUDE_PROJECT_DIR is always $tmp so that every payload-`cwd` case also proves
# `cwd` takes precedence over it.
decide() {
  local expect="$1" label="$2" cwd="$3" cmd="$4" payload out got
  if [ -n "$cwd" ]; then
    payload="$(jq -cn --arg c "$cmd" --arg d "$cwd" '{cwd:$d,tool_input:{command:$c}}')"
  else
    payload="$(jq -cn --arg c "$cmd" '{tool_input:{command:$c}}')"
  fi
  # A nonzero exit becomes a loud marker rather than `|| true`: a hook that
  # CRASHES emits no JSON, which is byte-identical to a clean allow, so
  # swallowing the status would let every `expect=allow` case pass against a
  # dead hook. Same convention as test-context-nudge.sh, and the reason is the
  # same — a crashing hook must FAIL assertions, not silently satisfy them.
  out="$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$tmp" "$hook" 2>/dev/null || printf 'HOOK_FAILED(rc=%s)' "$?")"
  got=allow
  if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then got=deny; fi
  if printf '%s' "$out" | grep -q 'HOOK_FAILED'; then got=crash; fi
  if [ "$got" = "$expect" ]; then
    printf 'ok    [%-14s] %s\n' "$label" "$cmd"
  else
    printf 'FAIL  expected %s got %s [%s] %s\n' "$expect" "$got" "$label" "$cmd" >&2
    fails=$((fails + 1))
  fi
}

# run <deny|allow> <branch> <command> — no `cwd` in the payload, so these keep the
# CLAUDE_PROJECT_DIR fallback path covered for hosts that omit the field.
run() {
  git -C "$tmp" checkout -q -B "$2"
  decide "$1" "$2" "" "$3"
}

# runc <deny|allow> <session-cwd> <command> — payload carries `cwd`; the anchor
# checkout ($tmp, = CLAUDE_PROJECT_DIR) is held on `main` for every one of these,
# which is precisely the state that used to produce a blanket deny.
runc() {
  git -C "$tmp" checkout -q -B main
  local label=cwd=anchor
  if [ "$2" = "$wt" ]; then label=cwd=worktree; fi
  decide "$1" "$label" "$2" "$3"
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

# --- Target resolution. The anchor checkout is on `main` throughout. ---
# The PR #238 shape: a correctly-routed worktree, both spellings. Used to deny.
runc allow "$tmp" "git -C $wt commit -m x"
runc allow "$tmp" "cd $wt && git commit -m x"
runc allow "$tmp" "(cd $wt && git push)"
# A native-worktree session (cwd IS the worktree) commits its own branch.
runc allow "$wt" "git commit -m x"
# `cwd` beats CLAUDE_PROJECT_DIR: cwd is the worktree, CLAUDE_PROJECT_DIR is main.
runc allow "$wt" "git push"
# The false negative this closes: an op aimed AT the main checkout from a
# worktree session must still be denied.
runc deny "$wt" "git -C $tmp push"
runc deny "$wt" "cd $tmp && git push"
# Attribution: the `-C` belongs to `status`, which this guard does not police —
# crediting it to the bare `git commit` would wave through a commit on main.
runc deny "$tmp" "git -C $wt status && git commit -m x"
# A subshell's cd does not escape it; the trailing push still targets main.
runc deny "$tmp" "(cd $wt && git push); git push"
# Unresolvable targets fall back to the session dir — never expanded, never guessed.
# shellcheck disable=SC2016  # `$WT` must reach the hook UNEXPANDED — that is the case.
runc deny "$tmp" 'git -C "$WT" commit -m x'
runc deny "$tmp" "git -C $tmp-does-not-exist push"
# A relative target resolves against the session cwd, not the hook's own $PWD.
runc allow "$tmp" "git -C ../$(basename "$wt") commit -m x"
# ...and inside a `cd` chain, against that cd — `.` there is the worktree.
runc allow "$tmp" "cd $wt && git -C . commit -m x"
runc deny  "$wt"  "cd $tmp && git -C . push"

# A quote-unaware split is the hazard segmentation introduced: a `; | & ( )`
# inside a PRE-subcommand argument cuts `git` from its subcommand, so no segment
# matches and the op would vanish entirely. Each of these was a confirmed full
# bypass before the no-segment-matched fallback landed. (A separator AFTER the
# subcommand — inside a -m message — was always safe: `git commit` is matched
# intact in the first segment. Both directions are pinned here.)
runc deny "$tmp" 'git -c core.foo="a;b" commit -m x'
runc deny "$tmp" 'git -c foo="a|b" push'
runc deny "$tmp" 'git -C "/tmp/x;y" commit -m x'
runc deny "$tmp" 'git -c a.b="x(y" push'
runc deny "$tmp" 'git commit -m "a;b"'
runc deny "$tmp" 'git commit -m "a|b && c"'
# The refinement must still survive a quoted separator that does NOT split the
# invocation: the worktree target is still honoured.
runc allow "$tmp" "git -C $wt commit -m \"a;b\""

# --- multi-line commands: the Bash tool emits them, and a newline IS a separator.
# A newline is a real chain separator, so a `cd` on its own line carries.
runc allow "$tmp" "cd $wt
git push"
# Backslash continuation leaves a bare `\` segment between the two; it must not
# break the chain.
runc allow "$tmp" "cd $wt && \\
git push"
# Both halves of a multi-line op on main still deny.
runc deny "$tmp" "git add -A
git commit -m x"
runc deny "$tmp" "git commit -m \"line1
line2\""
# HEREDOC BODIES ARE DATA. A body line reading `cd <repo-on-a-branch>` must not
# be credited to the real `git push` that follows — that was a live bypass.
runc deny "$tmp" "cat <<EOF
cd $wt
EOF
git push"
# ...while a `cd` BEFORE the heredoc opens is still honoured, which is the shape
# that actually occurs when committing from a worktree with a here-doc message.
runc allow "$tmp" "cd $wt && git commit -F - <<EOF
msg
EOF"
# The mirror case is safe without special handling: a body line that parses as a
# git op only ADDS a segment, and the loop denies if ANY segment targets main.
runc deny "$tmp" "cat <<EOF
git -C $wt push
EOF
git push"

# Documented parser limits, pinned so a future change has to face them: a `cd`
# inside a quoted string is rejected by the token filter (the quote is what
# rejects it), and separators are split without evaluating control flow, so a
# short-circuited `cd` is still credited — the one shape that under-denies.
runc deny  "$tmp" "echo \"a; cd $wt\" && git push"
runc allow "$tmp" "false && cd $wt; git push"

printf '\n'
if [ "$fails" -eq 0 ]; then
  printf 'all block-main-writes tests passed\n'
else
  printf '%d test(s) FAILED\n' "$fails" >&2
  exit 1
fi
