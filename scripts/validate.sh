#!/usr/bin/env bash
# Self-test for the mrinal-skills marketplace.
#
# Verifies that both manifests are valid JSON, every plugin declared in
# marketplace.json resolves to a directory with a plugin.json, and every
# auto-discovered component (skill, agent, command, output style) carries the
# frontmatter the plugin loader needs. For each plugin's hooks/hooks.json, every
# referenced script must exist, be executable, and start with a shebang.
#
# DEV/CI tool, not a runtime hook: it requires jq and fails LOUD. Reports ALL
# violations, not just the first. Exit 0 = clean, 1 = violations, 2 = usage error.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

command -v jq >/dev/null 2>&1 || { printf 'validate: jq is required\n' >&2; exit 2; }

errors=0
err()  { printf 'FAIL  %s\n' "$*" >&2; errors=$((errors + 1)); }
pass() { printf 'ok    %s\n' "$*"; }

# Print the YAML block between the first two '---' fences; empty if none. Always
# exits 0 so it is safe under `set -e` inside a command substitution.
frontmatter() {
  awk 'NR==1 && $0 != "---" { exit }
       NR==1 { next }
       /^---$/ { exit }
       { print }' "$1"
}
# fm_has <frontmatter> <key> → 0 if a "key:" line exists (boolean context only).
fm_has() { printf '%s\n' "$1" | grep -Eq "^$2:[[:space:]]*"; }
# fm_val <frontmatter> <key> → first scalar value of key, trimmed and unquoted.
fm_val() {
  printf '%s\n' "$1" \
    | awk -v k="$2" 'index($0, k ":") == 1 { sub("^" k ":[ \t]*", ""); print; exit }' \
    | sed -E "s/[[:space:]]+$//; s/^[\"']//; s/[\"']$//"
}

# check_file <file> <label> <name-must-equal|-> <required-key...>
# When arg 3 is a string, the frontmatter `name` must equal it; "-" skips.
check_file() {
  local file="$1" label="$2" want_name="$3"; shift 3
  local fm; fm="$(frontmatter "$file")"
  if [ -z "$fm" ]; then err "$label: $file — missing YAML frontmatter"; return; fi
  local k
  for k in "$@"; do
    fm_has "$fm" "$k" || err "$label: $file — frontmatter missing '$k'"
  done
  if [ "$want_name" != "-" ]; then
    local nm; nm="$(fm_val "$fm" name)"
    if [ -n "$nm" ] && [ "$nm" != "$want_name" ]; then
      err "$label: $file — name '$nm' != expected '$want_name'"
    fi
  fi
}

validate_plugin() {
  local dir="$1" name f slug
  name="$(basename "$dir")"

  if [ ! -f "$dir/.claude-plugin/plugin.json" ]; then
    err "plugin '$name': no .claude-plugin/plugin.json"; return
  fi
  if ! jq empty "$dir/.claude-plugin/plugin.json" 2>/dev/null; then
    err "plugin '$name': invalid JSON in plugin.json"; return
  fi
  pass "plugin '$name': manifest OK"

  if [ -d "$dir/skills" ]; then
    for f in "$dir"/skills/*/SKILL.md; do
      [ -e "$f" ] || continue
      slug="$(basename "$(dirname "$f")")"
      check_file "$f" skill "$slug" name description
    done
  fi
  if [ -d "$dir/agents" ]; then
    for f in "$dir"/agents/*.md; do
      [ -e "$f" ] || continue
      slug="$(basename "$f" .md)"
      check_file "$f" agent "$slug" name description model
    done
  fi
  if [ -d "$dir/commands" ]; then
    for f in "$dir"/commands/*.md; do
      [ -e "$f" ] || continue
      check_file "$f" command - description
    done
  fi

  # Output styles: only validated if plugin.json registers a directory.
  local osdir
  osdir="$(jq -r '.outputStyles // empty' "$dir/.claude-plugin/plugin.json" 2>/dev/null || true)"
  if [ -n "$osdir" ]; then
    osdir="$dir/${osdir#./}"
    if [ -d "$osdir" ]; then
      for f in "$osdir"/*.md; do
        [ -e "$f" ] || continue
        check_file "$f" output-style - name description
      done
    else
      err "plugin '$name': outputStyles points at missing dir '$osdir'"
    fi
  fi

  # Hooks: every script referenced in hooks.json must exist, be exec, have a shebang.
  local hj="$dir/hooks/hooks.json" script sp first
  if [ -f "$hj" ]; then
    jq empty "$hj" 2>/dev/null || err "plugin '$name': invalid JSON in hooks/hooks.json"
    while IFS= read -r script; do
      [ -n "$script" ] || continue
      sp="$dir/hooks/$script"
      if [ ! -f "$sp" ]; then err "hook: $hj references missing script '$script'"; continue; fi
      [ -x "$sp" ] || err "hook: $sp not executable"
      first=""; IFS= read -r first < "$sp" || true
      case "$first" in '#!'*) ;; *) err "hook: $sp missing shebang" ;; esac
    done < <(jq -r '.. | .command? // empty' "$hj" 2>/dev/null \
             | grep -oE '[A-Za-z0-9_.-]+\.sh' | sort -u || true)
  fi
}

mp=".claude-plugin/marketplace.json"
[ -f "$mp" ] || { err "no $mp"; printf '\n%d check(s) FAILED\n' "$errors" >&2; exit 1; }
jq empty "$mp" 2>/dev/null || { err "$mp: invalid JSON"; exit 1; }
pass "marketplace.json OK"

while IFS=$'\t' read -r pname psource; do
  [ -n "$pname" ] || continue
  pdir="${psource#./}"
  if [ ! -d "$pdir" ]; then
    err "marketplace plugin '$pname': source '$psource' is not a directory"; continue
  fi
  validate_plugin "$pdir"
done < <(jq -r '.plugins[] | [.name, .source] | @tsv' "$mp")

printf '\n'
if [ "$errors" -eq 0 ]; then
  pass "all checks passed"
else
  printf '%d check(s) FAILED\n' "$errors" >&2
  exit 1
fi
