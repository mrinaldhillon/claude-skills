#!/usr/bin/env bash
# Offline test for validate-config.sh in a mktemp sandbox: JSON validity,
# agent/command/SKILL frontmatter presence + required keys, unterminated
# fences, fast-exit for paths outside .claude/ and for deleted files.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$here/.." && pwd)"
hook="$REPO/scaffold/hooks/validate-config.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/agents" "$tmp/.claude/commands" "$tmp/.claude/skills/x"

fail=0
run() { printf '{"tool_input":{"file_path":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | bash "$hook" 2>/dev/null; }
ok()  { local rc=0; run "$1" || rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL(ok): $1 rc=$rc"; fail=1; }; }
bad() { local rc=0; run "$1" || rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL(bad): $1 rc=$rc (want 2)"; fail=1; }; }

# JSON
echo '{"a": 1}'  > "$tmp/.claude/settings.json"
echo '{broken'   > "$tmp/.claude/broken.json"
ok  "$tmp/.claude/settings.json"
bad "$tmp/.claude/broken.json"

# Agent frontmatter: complete / missing key / no fence / unterminated fence
printf -- '---\nname: a\ndescription: fine\n---\nbody\n'  > "$tmp/.claude/agents/good.md"
printf -- '---\nname: a\n---\nbody\n'                     > "$tmp/.claude/agents/nodesc.md"
printf 'no fence here\n'                                  > "$tmp/.claude/agents/nofence.md"
printf -- '---\nname: a\ndescription: d\nnever closed\n'  > "$tmp/.claude/agents/unterminated.md"
ok  "$tmp/.claude/agents/good.md"
bad "$tmp/.claude/agents/nodesc.md"
bad "$tmp/.claude/agents/nofence.md"
bad "$tmp/.claude/agents/unterminated.md"

# Command frontmatter: description required, name not.
printf -- '---\ndescription: run it\n---\nbody\n' > "$tmp/.claude/commands/good.md"
printf -- '---\nmodel: x\n---\nbody\n'            > "$tmp/.claude/commands/nodesc.md"
ok  "$tmp/.claude/commands/good.md"
bad "$tmp/.claude/commands/nodesc.md"

# SKILL.md: name + description required.
printf -- '---\nname: x\ndescription: d\n---\nbody\n' > "$tmp/.claude/skills/x/SKILL.md"
ok  "$tmp/.claude/skills/x/SKILL.md"
printf -- '---\ndescription: d\n---\nbody\n' > "$tmp/.claude/skills/x/SKILL.md"
bad "$tmp/.claude/skills/x/SKILL.md"

# Outside .claude/ → fast exit even if the content is garbage.
echo '{broken' > "$tmp/README.json"
ok "$tmp/README.json"

# Deleted/moved path → nothing to validate.
ok "$tmp/.claude/agents/never-existed.md"

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; fi
exit "$fail"
