#!/usr/bin/env bash
# PreToolUse guard (Read|Edit|Write): deny access to secret material so key/
# token bytes never enter the model context, get edited, or get written to a
# log. The default globs mirror this template's .gitignore Secrets block plus
# the conventional key/cert suffixes; /bootstrap should EXTEND the globs from
# the project's own .gitignore Secrets block (a pattern gitignored as secret
# should also be unreadable to the model).
# Deny is expressed as PreToolUse permissionDecision JSON on stdout, exit 0.
# NOTE: this guards the file tools only; it does not parse Bash (e.g. `cat .env`).
set -euo pipefail

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
[ -n "$file" ] || exit 0

base="${file##*/}"
# Case-insensitive matching (defense over precision): normalize a copy, keep the
# originals for the deny message.
lfile="$(printf '%s' "$file" | tr '[:upper:]' '[:lower:]')"
lbase="${lfile##*/}"

deny() {
  jq -cn --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

msg="is protected secret material (mirrors the .gitignore Secrets block). Reading/editing it would pull key or token bytes into context. Disable this hook via /hooks if you genuinely need it."

# Path-glob matches (anywhere in the path) + key/cert suffixes + local-only
# settings/env files (.claude/settings.local.json, *.local).
case "$lfile" in
  */secrets/*|secrets/*|*secrets.env|*.key|*.pem|*.envrc|*.local|*/.claude/settings.local.json|.claude/settings.local.json) deny "Blocked: '$file' $msg" ;;
esac
# Dotenv family by basename (.env, .env.local, .env.production, …).
case "$lbase" in
  .env|.env.*) deny "Blocked: '$base' $msg" ;;
esac

exit 0
