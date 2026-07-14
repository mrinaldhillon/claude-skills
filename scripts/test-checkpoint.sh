#!/usr/bin/env bash
# Offline test for checkpoint.sh in a throwaway repo: refuses to commit on
# main, commits on a feature branch, no-ops when clean, leaves unrelated
# staged files alone, and still commits existing paths when another
# checkpointed path is absent from the filesystem entirely.
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

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; fi
exit "$fail"
