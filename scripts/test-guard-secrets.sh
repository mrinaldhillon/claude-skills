#!/usr/bin/env bash
# Offline test for guard-secrets.sh: denies every default secret glob
# (case-insensitively), allows ordinary project files — including .context/
# paths, which the checkpoint/resume suite depends on staying readable.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$here/.." && pwd)"
hook="$REPO/core/hooks/guard-secrets.sh"

fail=0
run()   { printf '{"tool_input":{"file_path":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | bash "$hook"; }
deny()  { out="$(run "$1")"; printf '%s' "$out" | grep -q '"deny"' || { echo "FAIL(deny): $1 -> '$out'"; fail=1; }; }
allow() { out="$(run "$1")"; [ -z "$out" ] || { echo "FAIL(allow): $1 -> '$out'"; fail=1; }; }

# --- denied: the default Secrets globs ------------------------------------------
deny '/home/u/proj/.env'
deny '.env'
deny '.env.production'
deny 'dev/secrets.env'
deny '/a/b/secrets/token.txt'
deny 'secrets/token.json'                    # top-level relative form
deny 'wallet.key'
deny '/home/u/proj/certs/server.pem'
deny 'certs/server.PEM'                      # case-insensitive
deny '.ENVRC'                                # case-insensitive
deny 'compose.local'                         # *.local (gitignore Secrets block)
deny '.claude/settings.local.json'
deny '/home/u/proj/.claude/settings.local.json'

# --- allowed: ordinary files ------------------------------------------------------
allow 'internal/foo.go'
allow 'docs/README.md'
allow '.context/RESUME.md'                   # checkpoint suite must stay readable
allow '.context/project-context.md'
allow 'environment.md'                       # .env* is basename-anchored
allow 'keys.go'                              # *.key is suffix-anchored
allow 'locale.txt'                           # *.local is suffix-anchored
allow '.claude/settings.json'                # only settings.local.json is secret

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; fi
exit "$fail"
