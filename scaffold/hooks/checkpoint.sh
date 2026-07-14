#!/usr/bin/env bash
# Persists durable state so a session can be cleared and resumed from files.
# Claude authors the file CONTENTS in-conversation; this script only stages
# and commits them. Idempotent. Called from the PreCompact and Stop hooks and
# from scripts/milestone-runner.sh. Cannot and does not run /compact or /clear.
#
# Commits ONLY on non-main branches (ADR 0002: PR-into-main is by discipline;
# a hook must not land commits on the trunk). Commits by pathspec so unrelated
# staged files are never swept into a checkpoint commit.
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

# Add per path, existence-guarded: a multi-pathspec `git add -A` fails
# ATOMICALLY if any one pathspec matches nothing on disk (e.g. .context/ not
# yet created mid-adoption) — staging NOTHING, error swallowed, and the run
# would report "no changes" while real edits sit uncommitted.
for p in "${paths[@]}"; do
  [ -e "$p" ] && git add -A -- "$p" 2>/dev/null || true
done

# git commit -- <pathspec> errors if ANY pathspec element matches nothing
# (e.g. docs/decisions with no ADRs yet on a fresh project) — so narrow to
# only the entries that actually have staged changes before committing.
commit_paths=()
for p in "${paths[@]}"; do
  git diff --cached --quiet -- "$p" 2>/dev/null || commit_paths+=("$p")
done

if [ "${#commit_paths[@]}" -eq 0 ]; then
  echo "checkpoint: no changes"
else
  git commit -q \
    -m "chore(checkpoint): persist context, ADRs, resume pointer" \
    -m "Co-Authored-By: Claude <noreply@anthropic.com>" \
    -- "${commit_paths[@]}"
  echo "checkpoint: committed durable state on $branch"
fi
exit 0
