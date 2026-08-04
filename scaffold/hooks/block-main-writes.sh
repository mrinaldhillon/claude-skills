#!/usr/bin/env bash
# PreToolUse guard (Bash): refuse `git commit` / `merge` / `push` when the repo
# the command actually TARGETS is on `main`. Trunk-based discipline (git-workflow
# skill; ADR 0001): every change lands via a branch → PR. On this template branch
# protection is BY DISCIPLINE (ADR 0002) — no server-side gate — so this local
# backstop is the primary automated enforcement; a downstream project with real
# GitHub protection gets it as defense-in-depth that fails fast, before a rejected
# push round-trips. Deny is expressed as PreToolUse permissionDecision JSON on
# stdout, exit 0. Ported from a downstream project's hardened version + tests.
set -euo pipefail

# jq is required to reach the deny path — without this guard a jq-less host
# would die on the jq call below and the git command would PROCEED (fail open).
# Fail CLOSED instead: exit 2 blocks the call and surfaces the reason.
command -v jq >/dev/null 2>&1 || { echo "block-main-writes: jq not found — failing closed; install jq" >&2; exit 2; }

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -n "$cmd" ] || exit 0

# The directory the command runs in, absent an explicit `cd`/`-C`. Payload
# `.cwd` first: probe-verified 2026-08-03 that a Bash PreToolUse payload carries
# it, and that in a plain session it equals both CLAUDE_PROJECT_DIR and $PWD. It
# is the better anchor because it names the directory the command is about to
# run in, which for a native-worktree (`claude --worktree`) or started-in-a-
# subdir session need not be the project root. CLAUDE_PROJECT_DIR stays as the
# fallback for hosts that omit `.cwd`.
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
sess="$(printf '%s' "$input" | jq -r '.cwd // empty')"
if [ -z "$sess" ] || [ ! -d "$sess" ]; then sess="$proj"; fi

# Resolve a LITERAL path token ($1) against a base directory ($2) to an existing
# directory; print nothing if it cannot be resolved without guessing. Nothing
# here is ever eval'd or expanded: a token carrying shell metacharacters is
# unresolvable BY DESIGN, and the caller then falls back to the session dir —
# the fail-closed direction.
resolve_dir() {
  local p="$1" base="$2"
  case "$p" in
    \"*\") p="${p#\"}"; p="${p%\"}" ;;
    \'*\') p="${p#\'}"; p="${p%\'}" ;;
  esac
  case "$p" in
    ''|-|--) return 0 ;;
    *'$'*|*'`'*|*'*'*|*'?'*|*'['*|*'~'*|*'"'*|*"'"*) return 0 ;;
  esac
  case "$p" in
    /*) ;;
    *)  p="$base/$p" ;;
  esac
  [ -d "$p" ] || return 0
  printf '%s' "$p"
}

# Empty for a non-repo or a detached HEAD — neither is `main`, so neither denies.
branch_of() { git -C "$1" branch --show-current 2>/dev/null || true; }

# Deny on any `cd` target that was seen inside a heredoc body whose delimiter
# never closed (see the loop): the shell may genuinely be sitting in one of
# them. Sets deny_dir/deny_branch on a hit. `hd_cd_dirs` is empty — so this is
# a no-op — whenever every body closed normally, which is the usual case.
check_hd_dirs() {
  local hd
  [ -n "$hd_cd_dirs" ] || return 0
  while IFS= read -r hd; do
    [ -n "$hd" ] || continue
    if [ "$(branch_of "$hd")" = "main" ]; then deny_kind=main; deny_dir="$hd"; deny_branch="main"; return 0; fi
  done <<HD
$hd_cd_dirs
HD
}

# Only branch-advancing git ops. `git` (bare or path-prefixed /usr/bin/git)
# must sit at command position — line start, or after a shell separator ;&|( ,
# an opening quote or backtick (catches sh -c "git push" and `git push`).
# `echo git commit` stays unmatched, though `echo "git push"` IS matched — an
# accepted false positive; the deny message explains the /hooks override.
# Before `git`, a repeated prefix group swallows env assignments (GIT_DIR=x),
# wrapper words (env/command/nohup/time/xargs/sudo/timeout/nice/ionice/setsid/
# stdbuf/busybox) each with one optional argument (timeout 5 git push), shell
# keywords (then/do/else/elif — if true; then git push), and stray flags.
# After `git`, the skip group swallows pre-subcommand flags, a flag's separate
# argument (git -C <path> commit), and key=value args (-c a.b=c). The
# subcommand must be commit/merge/push, terminated by space, EOL, ;&|),
# a closing quote, or a backtick.
# `merge --abort|--quit` is stripped BEFORE matching (state cleanup, not
# branch-advancing) so plain cleanup passes but `merge --abort && git push`
# still trips on the push; --continue stays blocked (it concludes the merge).
#
# LIMITATIONS (accepted — this is a fast local backstop, not a sandbox):
# - A target is honoured only when it is a literal path. `git -C "$WT" push`,
#   a glob, `~`, `popd`, or a bare `cd` leaves the target undeterminable, and
#   an undeterminable target is DENIED, not assumed. Assuming the session dir
#   is only fail-closed when the session is the repo at risk; from a worktree
#   session with the real target on main it is fail-OPEN, which is how `pushd
#   /main && git push` used to slip past. Pass the literal path, or /hooks.
# - `cd`/`pushd` attribution is per separator-chain, not a real shell:
#   `cd wt && git push` is understood, and a later `cd` supersedes an earlier
#   one, but nothing is evaluated. Subshell parens reset the base, which is
#   right for `(cd wt && git push); git push` but coarse for nested forms.
#   Separators are not quote-aware, so a `cd` inside a quoted string can be
#   read as a real one — it then fails to resolve (the quote is part of the
#   token) and lands on the deny above. Control flow is not evaluated either:
#   in `false && cd wt; git push` the shell never cds yet the guard credits
#   `wt`, so a conditional cd can under-deny. A real shell parser is out of
#   scope for a hook that runs on every Bash call.
# - Known residual escapes: shell expansion (git${IFS}push), redirects before
#   the word (2>&1 git push), backslash-newline token splits, and wrappers not
#   in the list. Server-side branch protection (where configured) remains the
#   authoritative gate for anything that reaches the remote.
stripped="$(printf '%s' "$cmd" | sed -E 's/merge[[:space:]]+--(abort|quit)([[:space:]]|$)/ /g')"
re='(^|[;&|(]|["'\''`])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|(env|command|nohup|time|xargs|sudo|timeout|nice|ionice|setsid|stdbuf|busybox|then|do|else|elif)([[:space:]]+[^[:space:]]+)?[[:space:]]+|-[^[:space:]]+[[:space:]]+)*([^[:space:]]*/)?git([[:space:]]+(-[^[:space:]]+([[:space:]]+[^[:space:]]+)?|[^[:space:]-][^[:space:]]*=[^[:space:]]*))*[[:space:]]+(commit|merge|push)([[:space:];&|)"'\''`]|$)'
printf '%s' "$stripped" | grep -Eq "$re" || exit 0

# Split into segments so a `-C`/`cd` target is only ever attributed to the git
# invocation that actually tripped the regex. Matching the whole command and
# then hunting globally for a `-C` is unsound in the other direction: in
# `git -C /elsewhere status && git commit`, the `-C` belongs to a subcommand
# this guard does not police, and crediting it to the bare `git commit` would
# wave through a commit on the session's own main checkout. `;&|` break a
# chain; `()` additionally reset the inherited `cd`, since a subshell's cd does
# not escape it. Segment start then plays the role of the regex's `^` anchor.
segments="$(printf '%s\n' "$stripped" | awk '{ gsub(/[()]/, "\n@SUBSHELL@\n"); gsub(/[;&|]/, "\n"); print }')"

# `cd_base` is where the shell will be when the next segment runs; it goes EMPTY
# with base_unknown=1 the moment that stops being computable. Undeterminable is
# not the same as "assume the session dir" — see the deny below.
cd_base="$sess"
base_unknown=0
hd_delim=""
hd_cd_dirs=""
matched=0
deny_dir=""
deny_branch=""
deny_kind=""
while IFS= read -r seg; do
  if [ "$seg" = "@SUBSHELL@" ]; then cd_base="$sess"; base_unknown=0; continue; fi

  trimmed="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

  # A heredoc BODY is data, not commands, but its lines are segments like any
  # other, so a body line reading `cd <repo-on-a-branch>` must not be credited
  # to a later real `git push`. Track the DELIMITER rather than merely "a `<<`
  # was seen": a sticky flag also blinds the guard to the real `cd` that follows
  # the body, which the shell very much executes — `<<EOF … EOF; cd <main>; git
  # push` was a confirmed bypass for exactly that reason (probe, 2026-08-04).
  # Body lines are skipped entirely, so one spelling `git -C x push` is inert.
  if [ -n "$hd_delim" ]; then
    if [ "$trimmed" = "$hd_delim" ]; then hd_delim=""; continue; fi
    # Should the delimiter never arrive (a `;` inside the body split it, unusual
    # quoting), the flag would stay set and a real post-body `cd` would be lost
    # again. Keep every body `cd` as an extra candidate and judge it too — the
    # shell may actually be there. Fail-closed, and inert once a body closes
    # normally.
    if printf '%s' "$trimmed" | grep -Eq '^cd[[:space:]]+[^[:space:]]+$'; then
      d="$(resolve_dir "${trimmed#cd }" "$sess")"
      if [ -n "$d" ]; then hd_cd_dirs="$hd_cd_dirs$d
"; fi
    fi
    continue
  fi

  # `<<` opens a body from the NEXT segment on; the rest of THIS one is still a
  # real command, so `cd wt && git commit -F - <<EOF` keeps working. Take the
  # delimiter as ANY word and unwrap it here rather than matching an
  # identifier-shaped one: `<<\EOF` and `<<9EOF` are ordinary heredoc spellings,
  # and a capture that missed them left hd_delim empty, which made the whole
  # BODY parse as live commands — the exact bypass delimiter tracking exists to
  # stop (probe-confirmed 2026-08-04). A delimiter we still cannot read becomes
  # a sentinel that never closes, so the body stays data and the unclosed-body
  # backstop below carries the decision.
  case "$seg" in
    *'<<'*)
      raw="$(printf '%s' "$seg" | sed -nE 's/.*<<-?[[:space:]]*([^[:space:]]+).*/\1/p')"
      raw="${raw#\\}"
      case "$raw" in
        \'*\') raw="${raw#\'}"; raw="${raw%\'}" ;;
        \"*\") raw="${raw#\"}"; raw="${raw%\"}" ;;
      esac
      hd_delim="${raw:-@NOCLOSE@}"
      ;;
  esac

  # Directory-changing builtins. `pushd <dir>` moves the shell exactly as `cd`
  # does; `popd`, bare `cd`, and `cd -` move it somewhere this hook cannot
  # compute. Treating an unreadable move as "still in the session dir" is how a
  # guard leaks: from a worktree session, `pushd <main-checkout> && git push`
  # then judged the worktree's branch and allowed a push to main.
  if printf '%s' "$trimmed" | grep -Eq '^(cd|pushd)[[:space:]]+[^[:space:]]+$'; then
    tok="$(printf '%s' "$trimmed" | sed -E 's/^(cd|pushd)[[:space:]]+//')"
    d=""
    if [ "$base_unknown" = 0 ]; then
      d="$(resolve_dir "$tok" "$cd_base")"
    else
      # Base unknown: only an ABSOLUTE target re-anchors us. A relative one must
      # not be joined to an empty base — "" + "/tmp" would resolve to a real
      # directory that the shell was never in.
      case "$tok" in /*) d="$(resolve_dir "$tok" /)" ;; esac
    fi
    if [ -n "$d" ]; then cd_base="$d"; base_unknown=0; else cd_base=""; base_unknown=1; fi
    continue
  fi
  case "$trimmed" in
    cd|popd|popd\ *|pushd|pushd\ *) cd_base=""; base_unknown=1; continue ;;
  esac

  printf '%s' "$seg" | grep -Eq "$re" || continue
  matched=1

  # Only `-C` BEFORE the subcommand is git's own (git rejects the unspaced
  # -C<path> form, so the spaced one is the only shape to handle). Truncating
  # at the subcommand keeps a commit message that happens to contain " -C /x"
  # from being read as a target. Two or more are cumulative in git and not
  # worth emulating — leave them unresolved and fall back.
  pre="$(printf '%s' "$seg" | sed -E 's/[[:space:]](commit|merge|push)([[:space:];&|)"'\''`]|$).*//')"
  hits="$(printf '%s\n' "$pre" | { grep -oE '(^|[[:space:]])-C[[:space:]]+[^[:space:]]+' || true; })"
  n="$(printf '%s' "$hits" | grep -c . || true)"

  # A relative `-C` resolves against the chain's cd (`cd wt && git -C sub push`),
  # not against the session.
  dir=""
  if [ "$n" = "1" ]; then
    tok="$(printf '%s' "$hits" | sed -E 's/.*-C[[:space:]]+//')"
    if [ "$base_unknown" = 0 ]; then
      dir="$(resolve_dir "$tok" "$cd_base")"
    else
      case "$tok" in /*) dir="$(resolve_dir "$tok" /)" ;; esac
    fi
  elif [ "$n" = "0" ]; then
    if [ "$base_unknown" = 0 ]; then dir="$cd_base"; fi
  fi

  # Target undeterminable → DENY. Falling back to the session dir here is only
  # fail-closed when the session IS the repo at risk; with the session on a
  # branch and the real target on main it is fail-OPEN, which is how `cd  /main`
  # (two spaces), `pushd /main`, and `git -C "$VAR" push` all slipped through.
  # An unknown target is the one case where this guard has nothing to judge, so
  # it refuses rather than guesses. Pass a literal path, or override via /hooks.
  if [ -z "$dir" ]; then deny_kind=unknown; deny_branch="?"; break; fi

  b="$(branch_of "$dir")"
  if [ "$b" = "main" ]; then deny_kind=main; deny_dir="$dir"; deny_branch="$b"; break; fi

  check_hd_dirs
  if [ -n "$deny_branch" ]; then break; fi
done <<EOF
$segments
EOF

# Segmentation may only ever REFINE which repo gets judged — never drop the
# command. The whole-command gate above already proved a branch-advancing op is
# in here, so if no segment matched, the split lost it and the session dir is
# what to judge (exactly the pre-segmentation behavior). The split is
# quote-unaware, and that is not hypothetical: a `; | & ( )` inside a
# PRE-subcommand argument cuts `git` from its subcommand so neither half
# matches — `git -c core.foo="a;b" commit -m x` was a full detection bypass
# until this fallback existed (probe-confirmed 2026-08-03; a separator after
# the subcommand, e.g. in a -m message, was always safe because `git commit`
# is already matched intact in the first segment). This backstop also covers
# the `@SUBSHELL@` marker having no nonce: attacker text equal to it can only
# reset the base, which falls back here or to `$sess`.
if [ "$matched" = 0 ] && [ -z "$deny_branch" ]; then
  b="$(branch_of "$sess")"
  if [ "$b" = "main" ]; then deny_kind=main; deny_dir="$sess"; deny_branch="$b"; fi
  # An unclosed heredoc body swallows the rest of the command as data, the real
  # git op included, so nothing matched and the loop's own call never ran.
  if [ -z "$deny_branch" ]; then check_hd_dirs; fi
fi

[ -n "$deny_branch" ] || exit 0

tail='Trunk-based workflow (git-workflow skill; ADR 0001/0002): branch first — git switch -c <fix|chore|docs|milestone>/… — then PR into main. Override via /hooks if this is intentional (e.g. an emergency admin action).'
if [ "$deny_kind" = unknown ]; then
  # shellcheck disable=SC2016  # the backticks are markdown in the user-facing
  # message, not command substitution — single quotes are what keeps them so.
  head='Blocked: git commit/merge/push whose target directory cannot be determined. A `cd`/`pushd`/`popd` or a `-C` in this command is not a literal path (it needs a variable, glob or `~` expanded), so this guard cannot tell which repo it lands in and will not guess. Pass the literal path. '
else
  head="Blocked: git commit/merge/push targeting \`$deny_dir\`, which is on \`$deny_branch\`. "
fi
jq -cn --arg r "$head$tail" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
