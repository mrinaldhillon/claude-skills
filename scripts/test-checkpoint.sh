#!/usr/bin/env bash
# Offline test for checkpoint.sh in a throwaway repo: refuses to commit on
# main, commits on a feature branch, no-ops when clean, leaves unrelated
# staged files alone, and still commits existing paths when another
# checkpointed path is absent from the filesystem entirely. Also: reports an
# honest busy-skip when index.lock is held for the whole run, and retries
# through a transient lock to commit.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$here/.." && pwd)"
script="$REPO/scaffold/hooks/checkpoint.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q -b main
git config user.email test@test
git config user.name test
mkdir -p docs/decisions .context
echo ctx > .context/project-context.md
echo ptr > .context/RESUME.md
git add -A
git commit -qm init

fail=0
expect() { printf '%s' "$1" | grep -q "$2" || { echo "FAIL: wanted '$2' in: $1"; fail=1; }; }

# 1. On main with changes: must NOT commit.
echo change1 > .context/RESUME.md
out="$(CLAUDE_PROJECT_DIR="$tmp" bash "$script")"
expect "$out" "NOT committed"
[ "$(git rev-list --count HEAD)" = 1 ] || { echo "FAIL: committed on main"; fail=1; }

# 2. On a feature branch: commits the durable paths.
git checkout -qb feat/x
out="$(CLAUDE_PROJECT_DIR="$tmp" bash "$script")"
expect "$out" "committed durable state"
[ "$(git rev-list --count HEAD)" = 2 ] || { echo "FAIL: no commit on branch"; fail=1; }

# 3. Clean tree: no-op.
out="$(CLAUDE_PROJECT_DIR="$tmp" bash "$script")"
expect "$out" "no changes"
[ "$(git rev-list --count HEAD)" = 2 ] || { echo "FAIL: spurious commit"; fail=1; }

# 4. Unrelated staged file is not swept into a checkpoint commit.
echo unrelated > unrelated.txt
git add unrelated.txt
echo change2 > .context/RESUME.md
out="$(CLAUDE_PROJECT_DIR="$tmp" bash "$script")"
expect "$out" "committed durable state"
git diff --cached --name-only | grep -qx "unrelated.txt" || { echo "FAIL: unrelated.txt not left staged"; fail=1; }
git show --name-only --format= HEAD | grep -qx "unrelated.txt" && { echo "FAIL: unrelated.txt swept into checkpoint commit"; fail=1; }

# 5. A checkpointed path absent from the FILESYSTEM must not void the others:
# with .context/ gone entirely (mid-adoption state), an edit under
# docs/decisions/ still gets committed. The old multi-pathspec `git add -A`
# failed atomically here — staged nothing, swallowed the error, printed
# "no changes" while the ADR sat uncommitted.
git rm -qr .context && git commit -qm "drop .context"
echo "# ADR 999" > docs/decisions/999-test.md
before="$(git rev-list --count HEAD)"
out="$(CLAUDE_PROJECT_DIR="$tmp" bash "$script")"
expect "$out" "committed durable state"
[ "$(git rev-list --count HEAD)" = $((before + 1)) ] || { echo "FAIL: absent .context voided the docs/decisions commit"; fail=1; }
git show --name-only --format= HEAD | grep -qx "docs/decisions/999-test.md" || { echo "FAIL: ADR not in checkpoint commit"; fail=1; }

# 6. index.lock held for the whole run: must NOT lie "no changes" — reports
# the busy skip (stderr) and exits 0. Parallel subagents make this expected.
mkdir -p .context
echo change3 > .context/RESUME.md
touch .git/index.lock
before="$(git rev-list --count HEAD)"
rc=0
out="$(CLAUDE_PROJECT_DIR="$tmp" bash "$script" 2>&1)" || rc=$?
rm -f .git/index.lock
[ "$rc" -eq 0 ] || { echo "FAIL: non-zero exit under held lock"; fail=1; }
expect "$out" "index busy"
[ "$(git rev-list --count HEAD)" = "$before" ] || { echo "FAIL: commit under held lock"; fail=1; }

# 7. Transient lock (freed after ~0.5s): the retry loop must win and commit.
echo change4 > .context/RESUME.md
touch .git/index.lock
( sleep 0.5; rm -f .git/index.lock ) &
locker=$!
before="$(git rev-list --count HEAD)"
rc=0
out="$(CLAUDE_PROJECT_DIR="$tmp" bash "$script" 2>&1)" || rc=$?
wait "$locker"
[ "$rc" -eq 0 ] || { echo "FAIL: non-zero exit on transient lock"; fail=1; }
expect "$out" "committed durable state"
[ "$(git rev-list --count HEAD)" = $((before + 1)) ] || { echo "FAIL: no commit after transient lock"; fail=1; }

# 8. Non-lock hard failure (unwritable object store): must surface "add failed"
# with git's real error on stderr — not report "no changes" — and still exit 0.
echo change5 > .context/RESUME.md
chmod -R a-w .git/objects
rc=0
out="$(CLAUDE_PROJECT_DIR="$tmp" bash "$script" 2>&1)" || rc=$?
chmod -R u+w .git/objects
[ "$rc" -eq 0 ] || { echo "FAIL: non-zero exit on hard add failure"; fail=1; }
expect "$out" "add failed"

# 9. CLAUDE_ADR_DIR override: a project whose ADRs live elsewhere gets that
# directory checkpointed instead of the docs/decisions default.
mkdir -p handled-docs/05-decisions
echo "# ADR 001" > handled-docs/05-decisions/001-x.md
out="$(CLAUDE_PROJECT_DIR="$tmp" CLAUDE_ADR_DIR="handled-docs/05-decisions" bash "$script" 2>&1)" || true
expect "$out" "committed durable state"
git show --name-only --format= HEAD | grep -qx "handled-docs/05-decisions/001-x.md" || { echo "FAIL: CLAUDE_ADR_DIR override not checkpointed"; fail=1; }

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; fi
exit "$fail"
