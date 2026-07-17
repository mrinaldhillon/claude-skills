#!/usr/bin/env bash
# Persists durable state so a session can be cleared and resumed from files.
# Claude authors the file CONTENTS in-conversation; this script only stages
# and commits them. Idempotent. Called from the PreCompact and Stop hooks and
# from scripts/milestone-runner.sh. Cannot and does not run /compact or /clear.
#
# Commits ONLY on non-main branches (ADR 0002: PR-into-main is by discipline;
# a hook must not land commits on the trunk). Commits by pathspec so unrelated
# staged files are never swept into a checkpoint commit.
#
# Concurrency: parallel subagents run git in the repo, so index.lock
# contention at Stop is expected, not exceptional. Index-writing steps retry
# briefly and the checkpoint then SKIPS calmly (exit 0) — it is best-effort
# by design; the next Stop retries, and anything left staged is swept into
# that later checkpoint commit by the same pathspec rule.
set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}"
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

paths=(.context/project-context.md docs/decisions .context/RESUME.md)

for f in .context/project-context.md .context/RESUME.md; do
  [ -f "$f" ] || echo "checkpoint: WARNING missing $f — did Claude write it?" >&2
done

# "(detached)" cannot collide with a real branch name — parens are invalid in
# refnames — unlike a literal DETACHED sentinel, which a branch could shadow.
branch="$(git symbolic-ref --short -q HEAD || echo '(detached)')"
if [ "$branch" = "main" ] || [ "$branch" = "(detached)" ]; then
  echo "checkpoint: on $branch — durable files saved on disk but NOT committed (ADR 0002)"
  exit 0
fi

# Retry an index-writing git op while another process holds index.lock.
# Returns 75 (EX_TEMPFAIL) if the lock never freed; any other failure passes
# through with its own stderr and git's own return code.
try_index_op() {
  local out rc i
  for i in 1 2 3 4 5; do
    rc=0
    out="$(git "$@" 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ]; then
      [ -n "$out" ] && printf '%s\n' "$out"
      return 0
    fi
    case "$out" in
      *index.lock*) if [ "$i" -lt 5 ]; then sleep 0.3; fi ;;
      *) printf '%s\n' "$out" >&2; return "$rc" ;;
    esac
  done
  return 75
}

# Add per path, existence-guarded: a multi-pathspec `git add -A` fails
# ATOMICALLY if any one pathspec matches nothing on disk (e.g. .context/ not
# yet created mid-adoption) — staging NOTHING, error swallowed, and the run
# would report "no changes" while real edits sit uncommitted.
add_busy=0
add_failed=0
for p in "${paths[@]}"; do
  if [ -e "$p" ]; then
    rc=0
    try_index_op add -A -- "$p" || rc=$?
    if [ "$rc" -eq 75 ]; then
      add_busy=1
    elif [ "$rc" -ne 0 ]; then
      add_failed=1
    fi
  fi
done

# git commit -- <pathspec> errors if ANY pathspec element matches nothing
# (e.g. docs/decisions with no ADRs yet on a fresh project) — so narrow to
# only the entries that actually have staged changes before committing.
commit_paths=()
for p in "${paths[@]}"; do
  git diff --cached --quiet -- "$p" 2>/dev/null || commit_paths+=("$p")
done

if [ "${#commit_paths[@]}" -eq 0 ]; then
  if [ "$add_busy" -eq 1 ]; then
    echo "checkpoint: git index busy (another agent) — checkpoint skipped; the next Stop retries" >&2
  elif [ "$add_failed" -eq 1 ]; then
    echo "checkpoint: add failed (see stderr) — durable edits NOT committed" >&2
  else
    echo "checkpoint: no changes"
  fi
else
  rc=0
  try_index_op commit -q \
    -m "chore(checkpoint): persist context, ADRs, resume pointer" \
    -m "Co-Authored-By: Claude <noreply@anthropic.com>" \
    -- "${commit_paths[@]}" || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "checkpoint: committed durable state on $branch"
    if [ "$add_busy" -eq 1 ] || [ "$add_failed" -eq 1 ]; then
      echo "checkpoint: some paths were not staged (busy/failed adds) — the next Stop sweeps them" >&2
    fi
  elif [ "$rc" -eq 75 ]; then
    echo "checkpoint: git index busy (another agent) — checkpoint skipped; the next Stop retries" >&2
  else
    echo "checkpoint: commit failed (rc=$rc) — staged durable files remain for the next Stop" >&2
  fi
fi
exit 0
