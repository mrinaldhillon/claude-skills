#!/usr/bin/env bash
# PostToolUse(Write|Edit) guard for this repo's .claude/ steering layer — the
# template's actual product. settings.json must be valid JSON; every agent/command/
# skill must carry well-formed YAML frontmatter with its required keys.
#
# PostToolUse fires AFTER the write, so this does not block the edit; a non-zero
# exit (2) surfaces the problem to Claude so it gets fixed in-loop. Fast-exits for
# any path outside .claude/, and degrades to a no-op if jq is unavailable rather
# than breaking the edit loop. Stack-neutral — ships to bootstrapped projects too.
set -euo pipefail

# jq parses the hook payload; its absence must not break editing.
command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
[ -n "$file" ] || exit 0

# Only audit the steering layer.
case "$file" in
  */.claude/*|.claude/*) ;;
  *) exit 0 ;;
esac

# The tool may have moved/deleted the path; nothing to validate.
[ -f "$file" ] || exit 0

fail() { printf 'config-validate: %s\n' "$1" >&2; exit 2; }

case "$file" in
  *.json)
    jq empty "$file" 2>/dev/null || fail "$file: invalid JSON"
    ;;
  */agents/*.md|*/commands/*.md|*/SKILL.md)
    [ "$(head -n1 "$file")" = "---" ] \
      || fail "$file: missing YAML frontmatter (line 1 must be '---')"
    # Extract the block between the first two '---' fences and require a closing
    # fence — one awk pass over the file, no pipe (avoids a pipefail/SIGPIPE edge).
    fm="$(awk 'NR==1 {next} /^---$/ {closed=1; exit} {print} END {if (!closed) exit 1}' "$file")" \
      || fail "$file: unterminated YAML frontmatter"
    need_key() {
      printf '%s\n' "$fm" | grep -Eq "^$1:" \
        || fail "$file: frontmatter missing required key '$1'"
    }
    case "$file" in
      */agents/*.md)   need_key name; need_key description ;;
      */commands/*.md) need_key description ;;
      */SKILL.md)      need_key name; need_key description ;;
    esac
    ;;
esac

exit 0
